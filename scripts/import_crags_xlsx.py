#!/usr/bin/env python3
"""Convert the US climbing areas spreadsheet into the app's bundled crag list.

  pip install openpyxl numpy
  python3 scripts/import_crags_xlsx.py           # data/US_Climbing_Areas.xlsx -> CHOSS/Resources/us_climbing_areas.json

Columns: Climbing area / State(s) / Latitude / Longitude / Climbing type
("Bouldering", "Rope" or "Bouldering / Rope"). Each crag also gets its nearest town (offline,
from data/geonames_us_towns.csv). Output records match the app's `Place` model.

IDs are derived from name + coordinates (like the gym import), so re-running keeps existing
crags' followers, posts and climbs attached, as long as a crag's name and coordinates don't change.
"""
import argparse
import json
from pathlib import Path

import openpyxl

from import_gyms_xlsx import MAX_TOWN_KM, ROOT, load_towns, nearest_town, place_id

DEFAULT_XLSX = ROOT / "data" / "US_Climbing_Areas.xlsx"
DEFAULT_OUT = ROOT / "CHOSS" / "Resources" / "us_climbing_areas.json"

DISCIPLINES = {
    "bouldering": ["boulder"],
    "rope": ["sport", "trad"],
    "bouldering / rope": ["boulder", "sport", "trad"],
}

# Coordinates in the spreadsheet that are clearly wrong. Checked by comparing each area's
# point against towns in its listed state; the spreadsheet itself is left untouched.
COORDINATE_FIXES = {
    # Listed in NY but plotted in central Connecticut; the park is on the Hudson in Upper Nyack.
    ("Nyack beach state park", "NY"): (41.1206, -73.9137),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("xlsx", nargs="?", default=DEFAULT_XLSX, type=Path)
    parser.add_argument("--out", default=DEFAULT_OUT, type=Path)
    args = parser.parse_args()

    rows = list(openpyxl.load_workbook(args.xlsx, read_only=True, data_only=True).worksheets[0]
                .iter_rows(values_only=True))
    header = [str(h).strip().lower() for h in rows[0]]
    col = {key: header.index(name) for key, name in (
        ("name", "climbing area"), ("state", "state(s)"), ("lat", "latitude"),
        ("lon", "longitude"), ("type", "climbing type"),
    )}

    towns, coords = load_towns()
    places, skipped, fixed = [], [], 0
    seen = set()
    for row in rows[1:]:
        name = str(row[col["name"]] or "").strip()
        state = str(row[col["state"]] or "").strip()
        kind = str(row[col["type"]] or "").strip().lower()
        try:
            lat, lon = float(row[col["lat"]]), float(row[col["lon"]])
        except (TypeError, ValueError):
            skipped.append(row)
            continue
        if not name or kind not in DISCIPLINES:
            skipped.append(row)
            continue
        if (name, state) in COORDINATE_FIXES:
            lat, lon = COORDINATE_FIXES[(name, state)]
            fixed += 1

        city, _, km = nearest_town(lat, lon, towns, coords)
        pid = place_id(name, lat, lon, prefix="p_crag")
        if pid in seen:
            skipped.append(row)
            continue
        seen.add(pid)
        places.append({
            "id": pid,
            "name": name,
            "kind": "crag",
            # "Near <town>" for crags, since most aren't in a town.
            "city": city if km <= MAX_TOWN_KM else "",
            "region": state,  # as listed, e.g. "CA" or "CA/NV" for areas on a border
            "country": "USA",
            "latitude": round(lat, 6),
            "longitude": round(lon, 6),
            "disciplines": DISCIPLINES[kind],
            "about": "",
            "source": "curated",
            "externalID": f"us-areas-xlsx:{name}|{state}",
            "isVerified": False,
        })

    places.sort(key=lambda p: (p["name"].lower(), p["region"]))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(places, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"{len(places)} crags -> {args.out.relative_to(ROOT)}"
          f" ({fixed} coordinates corrected, {len(skipped)} rows skipped)")


if __name__ == "__main__":
    main()
