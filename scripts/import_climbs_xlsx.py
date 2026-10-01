#!/usr/bin/env python3
"""Turn the US outdoor climbs spreadsheet into seed SQL for the backend's climbs table.

  pip install openpyxl
  python3 scripts/import_climbs_xlsx.py      # data/US_Outdoor_Climbs.xlsx -> supabase/seeds/climbs_*.sql

Columns: Climb / Difficulty grade / Latitude / Longitude / Climbing area / State(s) /
Climbing type / Coordinate basis / Source URL / Notes.

Each climb is attached to its crag by (Climbing area, State) against the bundled crag list
(CHOSS/Resources/us_climbing_areas.json, the same crags as supabase/seed.sql). Rows with no
area are attached to the nearest crag if one is within NEAREST_CRAG_KM, otherwise skipped.

Climb ids are the OpenBeta climb uuid from the source URL (other sources: md5 of the URL,
which is also kept as external_id), so
re-running updates climbs in place and never duplicates them; posts stay attached.

Grades are mapped onto the app's scales (CHOSS/Models/Grade.swift):
  YDS  5.10- -> 5.10a, 5.10 -> 5.10b, 5.10+ -> 5.10c, 5.10a/b -> 5.10a, 5.7+ -> 5.7,
       below 5.5 (and class 3 / 4) -> no grade
  V    V3-4 -> V3, V5+ / V5- -> V5, V-easy -> VB
Safety suffixes (PG13, R, X) are dropped. Anything else is left ungraded and counted in the
report the script prints.
"""
import argparse
import hashlib
import json
import math
import re
import unicodedata
import uuid
from collections import Counter, defaultdict
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_XLSX = ROOT / "data" / "US_Outdoor_Climbs.xlsx"
CRAGS = ROOT / "CHOSS" / "Resources" / "us_climbing_areas.json"
OUT_DIR = ROOT / "supabase" / "seeds"
ROWS_PER_INSERT = 1000
ROWS_PER_FILE = 25000
NEAREST_CRAG_KM = 3.0

V_GRADES = ["VB"] + [f"V{i}" for i in range(18)]
YDS_GRADES = [f"5.{i}" for i in range(5, 10)] + [f"5.{n}{l}" for n in range(10, 16) for l in "abcd"]

DISCIPLINES = {
    "bouldering": "boulder", "boulder": "boulder",
    "sport": "sport",
    "trad": "trad", "alpine": "trad",
    "top rope": "topRope", "tr": "topRope",
}

RESTRICTED_NOTE = "The source lists this climb as closed or restricted. Check access before you go."


def norm(text):
    """Same idea as the app's NameMatcher.normalize / the database's norm_name."""
    text = unicodedata.normalize("NFKD", str(text or "")).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", text).strip()


# --- Grades -----------------------------------------------------------------------------------

SAFETY = re.compile(r"\s+(pg-?13|pg|r|x)$", re.I)
YDS = re.compile(r"^5\.(\d{1,2})([a-d])?(?:\s*/\s*(?:5\.)?(\d{1,2})?([a-d])?)?\s*([+-])?$")
YDS_RANGE = re.compile(r"^5\.(\d{1,2})\s*-\s*(?:5\.)?\d{1,2}[a-d]?$")
V = re.compile(r"^v(b|-?easy|\d{1,2})\s*([+-])?(?:\s*[-/]\s*v?(?:\d{1,2}|b|easy)\s*[+-]?)?$")


def parse_grade(raw):
    """(system, value) on the app's scales, or None."""
    text = str(raw or "").strip()
    while True:  # "5.10a R", "V4 PG13", "5.9 PG13 R"
        stripped = SAFETY.sub("", text)
        if stripped == text:
            break
        text = stripped.strip()
    text = text.replace("–", "-").replace("−", "-")
    lower = text.lower()

    match = V.match(lower)
    if match:
        body = match.group(1)
        if body in ("b", "easy", "-easy"):
            return ("vScale", "VB")
        value = f"V{int(body)}"
        return ("vScale", value) if value in V_GRADES else None

    match = YDS_RANGE.match(lower)  # "5.10-11": the lower grade, unlettered
    if match:
        return yds(int(match.group(1)), None, "")
    match = YDS.match(lower)
    if match:
        number, letter, _, _, sign = match.groups()
        return yds(int(number), letter, sign or "")
    return None


def yds(number, letter, sign):
    if number < 5 or number > 15:
        return None
    if number < 10:
        return ("yds", f"5.{number}")
    if not letter:
        letter = {"-": "a", "": "b", "+": "c"}[sign]
    return ("yds", f"5.{number}{letter}")


def parse_discipline(raw, grade):
    first = re.split(r"\s*[/,]\s*", str(raw or "").strip().lower())[0]
    if first in DISCIPLINES:
        return DISCIPLINES[first]
    if grade and grade[0] == "vScale":
        return "boulder"
    return "other"


# --- Ids --------------------------------------------------------------------------------------

OPENBETA = re.compile(r"openbeta\.io/climb/([0-9a-f-]{36})", re.I)


def climb_id(url, fallback_key):
    match = OPENBETA.search(url or "")
    if match:
        return str(uuid.UUID(match.group(1)))
    return str(uuid.UUID(hashlib.md5(("climb:" + (url or fallback_key)).encode()).hexdigest()))


# --- Crag matching ----------------------------------------------------------------------------

def km(lat1, lon1, lat2, lon2):
    p = math.pi / 180
    a = (math.sin((lat2 - lat1) * p / 2) ** 2
         + math.cos(lat1 * p) * math.cos(lat2 * p) * math.sin((lon2 - lon1) * p / 2) ** 2)
    return 12742 * math.asin(math.sqrt(a))


class Crags:
    def __init__(self, crags):
        self.by_key = {}
        self.by_name = defaultdict(list)
        self.grid = defaultdict(list)
        for crag in crags:
            self.by_key[(norm(crag["name"]), norm(crag["region"]))] = crag
            self.by_name[norm(crag["name"])].append(crag)
            self.grid[self.cell(crag["latitude"], crag["longitude"])].append(crag)

    @staticmethod
    def cell(lat, lon):
        return (math.floor(lat * 10), math.floor(lon * 10))  # ~11 km cells

    def match(self, area, state):
        crag = self.by_key.get((norm(area), norm(state)))
        if crag:
            return crag
        # The same area listed under a single state when the crag has a multi-state region
        # (or the other way round): accept it if the name is unique.
        candidates = [c for c in self.by_name.get(norm(area), [])
                      if set(norm(state).split()) & set(norm(c["region"]).split())]
        return candidates[0] if len(candidates) == 1 else None

    def nearest(self, lat, lon, max_km):
        row, col = self.cell(lat, lon)
        best, best_km = None, max_km
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                for crag in self.grid.get((row + dr, col + dc), []):
                    d = km(lat, lon, crag["latitude"], crag["longitude"])
                    if d <= best_km:
                        best, best_km = crag, d
        return best


# --- SQL --------------------------------------------------------------------------------------

def q(text):
    return "'" + str(text).replace("'", "''") + "'" if text is not None else "null"


INSERT_HEAD = (
    "insert into public.climbs (id, external_id, place_id, name, discipline, grade_system, grade_value,\n"
    "                           about, latitude, longitude, is_verified)\n"
    "select v.id::uuid, v.external_id, p.id, v.name, v.discipline::public.discipline,\n"
    "       v.grade_system::public.grade_system, v.grade_value, v.about, v.latitude, v.longitude, true\n"
    "  from (values\n"
)
INSERT_TAIL = (
    "\n  ) as v (id, external_id, place, name, discipline, grade_system, grade_value, about, latitude, longitude)\n"
    "  join public.places p on p.external_id = v.place\n"
    "on conflict (id) do update set\n"
    "  external_id = excluded.external_id, place_id = excluded.place_id, name = excluded.name,\n"
    "  discipline = excluded.discipline, grade_system = excluded.grade_system,\n"
    "  grade_value = excluded.grade_value, about = excluded.about, latitude = excluded.latitude,\n"
    "  longitude = excluded.longitude, is_verified = true;\n"
)


def write_sql(climbs, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("climbs_*.sql"):
        old.unlink()
    files = 0
    for start in range(0, len(climbs), ROWS_PER_FILE):
        part = climbs[start:start + ROWS_PER_FILE]
        files += 1
        chunks = []
        for i in range(0, len(part), ROWS_PER_INSERT):
            rows = ",\n".join(
                f"    ({q(c['id'])}, {q(c['external_id'])}, {q(c['place'])}, {q(c['name'])}, "
                f"{q(c['discipline'])}, {q(c['grade_system'])}, {q(c['grade_value'])}, {q(c['about'])}, "
                f"{c['latitude']}, {c['longitude']})"
                for c in part[i:i + ROWS_PER_INSERT]
            )
            chunks.append(INSERT_HEAD + rows + INSERT_TAIL)
        header = (
            "-- Generated by scripts/import_climbs_xlsx.py from data/US_Outdoor_Climbs.xlsx. Do not edit.\n"
            f"-- Outdoor climbs {start + 1}-{start + len(part)} of {len(climbs)} (climb data: OpenBeta).\n"
            "-- Needs supabase/seed.sql (the crags) first. Safe to re-run.\n\n"
        )
        (out_dir / f"climbs_{files:02d}.sql").write_text(header + "\n".join(chunks))
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("xlsx", nargs="?", default=DEFAULT_XLSX, type=Path)
    parser.add_argument("--out-dir", default=OUT_DIR, type=Path)
    args = parser.parse_args()

    crags = Crags(json.loads(CRAGS.read_text()))
    rows = openpyxl.load_workbook(args.xlsx, read_only=True, data_only=True).worksheets[0].iter_rows(values_only=True)
    header = [str(h).strip().lower() for h in next(rows)]
    col = {key: header.index(name) for key, name in (
        ("name", "climb"), ("grade", "difficulty grade"), ("lat", "latitude"), ("lon", "longitude"),
        ("area", "climbing area"), ("state", "state(s)"), ("type", "climbing type"),
        ("url", "source url"), ("notes", "notes"),
    )}

    climbs, seen = [], set()
    report = Counter()
    ungraded = Counter()
    unmatched = Counter()
    for row in rows:
        name = " ".join(str(row[col["name"]] or "").split())[:120]
        area = str(row[col["area"]] or "").strip()
        state = str(row[col["state"]] or "").strip()
        url = str(row[col["url"]] or "").strip()
        try:
            lat, lon = float(row[col["lat"]]), float(row[col["lon"]])
        except (TypeError, ValueError):
            lat = lon = None
        if not name:
            report["skipped: no name"] += 1
            continue

        crag = crags.match(area, state) if area else None
        if crag is None and lat is not None:
            crag = crags.nearest(lat, lon, NEAREST_CRAG_KM)
            if crag:
                report["matched by nearest crag"] += 1
        if crag is None:
            report["skipped: no crag"] += 1
            unmatched[(area, state)] += 1
            continue

        cid = climb_id(url, f"{crag['id']}|{name}")
        if cid in seen:
            report["skipped: duplicate id"] += 1
            continue
        seen.add(cid)

        raw_grade = row[col["grade"]]
        grade = parse_grade(raw_grade)
        if grade is None:
            ungraded[str(raw_grade)] += 1
        notes = str(row[col["notes"]] or "")
        climbs.append({
            "id": cid,
            # OpenBeta climbs are identified by their id; keep other sources' URL.
            "external_id": None if OPENBETA.search(url) else (url or None),
            "place": crag["id"],
            "name": name,
            "discipline": parse_discipline(row[col["type"]], grade),
            "grade_system": grade[0] if grade else None,
            "grade_value": grade[1] if grade else None,
            "about": RESTRICTED_NOTE if "restricted" in notes.lower() else "",
            "latitude": round(lat, 6) if lat is not None else "null",
            "longitude": round(lon, 6) if lon is not None else "null",
        })

    climbs.sort(key=lambda c: (c["place"], c["name"].lower(), c["id"]))
    files = write_sql(climbs, args.out_dir)

    print(f"Wrote {len(climbs)} climbs at {len({c['place'] for c in climbs})} crags "
          f"to {files} files in {args.out_dir.relative_to(ROOT)}")
    for key, count in sorted(report.items()):
        print(f"  {key}: {count}")
    print(f"  ungraded: {sum(ungraded.values())}  (most common: {ungraded.most_common(12)})")
    if unmatched:
        print(f"  unmatched areas (top): {unmatched.most_common(8)}")


if __name__ == "__main__":
    main()
