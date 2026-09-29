#!/usr/bin/env python3
"""Convert the US climbing gym spreadsheet into the app's bundled gym list.

  pip install openpyxl numpy
  python3 scripts/import_gyms_xlsx.py            # data/US_Climbing_Gyms_Simple.xlsx -> CHOSS/Resources/us_climbing_gyms.json

The spreadsheet has Name / Latitude / Longitude. Each gym also gets the nearest town and state
(offline, from data/geonames_us_towns.csv), so it can show "Boulder, CO" and be found by town.
Output records match the app's `Place` model (CHOSS/Models/Place.swift).

IDs are derived from name + coordinates, so re-running with an updated spreadsheet keeps
existing gyms' IDs (and therefore their followers and posts) stable.
"""
import argparse
import csv
import hashlib
import json
import re
from pathlib import Path

import numpy as np
import openpyxl

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_XLSX = ROOT / "data" / "US_Climbing_Gyms_Simple.xlsx"
TOWNS_CSV = ROOT / "data" / "geonames_us_towns.csv"
DEFAULT_OUT = ROOT / "CHOSS" / "Resources" / "us_climbing_gyms.json"

# Only label a gym with a town if one is reasonably close.
MAX_TOWN_KM = 40

STATE_ABBR = {
    "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR", "California": "CA",
    "Colorado": "CO", "Connecticut": "CT", "Delaware": "DE", "District of Columbia": "DC",
    "Washington, D.C.": "DC", "Florida": "FL", "Georgia": "GA", "Hawaii": "HI", "Idaho": "ID",
    "Illinois": "IL", "Indiana": "IN", "Iowa": "IA", "Kansas": "KS", "Kentucky": "KY",
    "Louisiana": "LA", "Maine": "ME", "Maryland": "MD", "Massachusetts": "MA", "Michigan": "MI",
    "Minnesota": "MN", "Mississippi": "MS", "Missouri": "MO", "Montana": "MT", "Nebraska": "NE",
    "Nevada": "NV", "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM", "New York": "NY",
    "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH", "Oklahoma": "OK", "Oregon": "OR",
    "Pennsylvania": "PA", "Rhode Island": "RI", "South Carolina": "SC", "South Dakota": "SD",
    "Tennessee": "TN", "Texas": "TX", "Utah": "UT", "Vermont": "VT", "Virginia": "VA",
    "Washington": "WA", "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY",
}
TERRITORY_ABBR = {"PR": "PR", "GU": "GU", "VI": "VI"}

# Rows in the spreadsheet that are the same gym listed twice (same coordinates). The first name
# is kept; the others are dropped so followers and posts aren't split across two pages.
DUPLICATES = {
    "Climbing Wall at Winona State": ["Winona State University"],
    "Movement Plano": ["Movement The Plano Training Center"],
    "University of North Carolina (Rams Head Climbing Wall, Fetzer Climbing Wall)": [
        "University of North Carolina (Kenan-Flagler Business School)",
    ],
}
DROPPED = {dup: keep for keep, dups in DUPLICATES.items() for dup in dups}

BOULDER_ONLY = re.compile(r"\b(boulder(ing)?|bloc|block|bouldering)\b", re.I)


def load_towns():
    with open(TOWNS_CSV, newline="") as f:
        rows = list(csv.DictReader(f))
    coords = np.radians(np.array([[float(r["lat"]), float(r["lon"])] for r in rows]))
    return rows, coords


def nearest_town(lat, lon, rows, coords):
    """Nearest town by great-circle distance. Returns (city, state_abbr, km)."""
    la, lo = np.radians(lat), np.radians(lon)
    dlat = coords[:, 0] - la
    dlon = coords[:, 1] - lo
    a = np.sin(dlat / 2) ** 2 + np.cos(la) * np.cos(coords[:, 0]) * np.sin(dlon / 2) ** 2
    km = 2 * 6371 * np.arcsin(np.sqrt(a))
    i = int(np.argmin(km))
    row = rows[i]
    state = TERRITORY_ABBR.get(row["cc"]) or STATE_ABBR.get(row["admin1"], row["admin1"])
    return row["name"], state, float(km[i])


def place_id(name, lat, lon):
    slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")[:40]
    digest = hashlib.sha1(f"{name}|{lat:.5f}|{lon:.5f}".encode()).hexdigest()[:6]
    return f"p_gym_{slug}_{digest}"


def disciplines(name):
    # Name says bouldering → bouldering only; otherwise assume a typical mixed gym.
    return ["boulder"] if BOULDER_ONLY.search(name) else ["boulder", "sport", "topRope"]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("xlsx", nargs="?", default=DEFAULT_XLSX, type=Path)
    parser.add_argument("--out", default=DEFAULT_OUT, type=Path)
    args = parser.parse_args()

    sheet = openpyxl.load_workbook(args.xlsx, read_only=True, data_only=True).worksheets[0]
    rows = list(sheet.iter_rows(values_only=True))
    header = [str(h).strip().lower() for h in rows[0]]
    col = {name: header.index(name) for name in ("name", "latitude", "longitude")}

    towns, coords = load_towns()
    names_in_sheet = {str(r[col["name"]]).strip() for r in rows[1:] if r[col["name"]]}
    for keep, dups in DUPLICATES.items():
        missing = [n for n in [keep, *dups] if n not in names_in_sheet]
        if missing:
            print(f"warning: duplicate rule mentions names not in the sheet: {missing}")

    places, skipped, far, merged = [], [], 0, 0
    seen_ids = set()
    for row in rows[1:]:
        name = (row[col["name"]] or "").strip() if isinstance(row[col["name"]], str) else row[col["name"]]
        lat, lon = row[col["latitude"]], row[col["longitude"]]
        try:
            lat, lon = float(lat), float(lon)
        except (TypeError, ValueError):
            skipped.append(row)
            continue
        if not name or not (-90 <= lat <= 90 and -180 <= lon <= 180):
            skipped.append(row)
            continue
        if name in DROPPED:
            merged += 1
            continue

        city, state, km = nearest_town(lat, lon, towns, coords)
        if km > MAX_TOWN_KM:
            city, far = "", far + 1
        pid = place_id(name, lat, lon)
        if pid in seen_ids:
            skipped.append(row)
            continue
        seen_ids.add(pid)
        places.append({
            "id": pid,
            "name": name,
            "kind": "gym",
            "city": city,
            "region": state,
            "country": "USA",
            "latitude": round(lat, 6),
            "longitude": round(lon, 6),
            "disciplines": disciplines(name),
            "about": "",
            "source": "curated",
            "externalID": f"us-gyms-xlsx:{name}",
            # Imported, not yet confirmed by the gym itself.
            "isVerified": False,
        })

    places.sort(key=lambda p: p["name"].lower())
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(places, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"{len(places)} gyms -> {args.out.relative_to(ROOT)}"
          f" ({merged} duplicates merged, {far} without a town within {MAX_TOWN_KM} km,"
          f" {len(skipped)} rows skipped)")


if __name__ == "__main__":
    main()
