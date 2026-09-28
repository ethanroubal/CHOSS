#!/usr/bin/env python3
"""Seed CHOSS places (gyms + crags) from open datasets.

Outputs JSON matching the app's `Place` model (CHOSS/Models/Place.swift), ready to
load into the backend. See docs/PLACES_DATA_STRATEGY.md for why these sources.

  # Climbing gyms from OpenStreetMap (ODbL - attribution required)
  python3 scripts/import_places.py osm --area US-CO > gyms-co.json

  # Crags from OpenBeta (CC0 climbing data)
  python3 scripts/import_places.py openbeta --path USA Kentucky --depth 4 > crags-ky.json

  # Every climb inside one crag (matches the app's `Climb` model)
  python3 scripts/import_places.py openbeta-climbs --path USA Kentucky "Red River Gorge" "Muir Valley" > climbs.json

Stdlib only. Re-running is safe: every record carries `externalID`, so the backend can
upsert on (source, externalID) and never create duplicates.
"""
import argparse
import json
import sys
import urllib.parse
import urllib.request

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
OPENBETA_URL = "https://api.openbeta.io/"
USER_AGENT = "CHOSS-place-import/0.1"


def post(url, data, content_type):
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": content_type, "User-Agent": USER_AGENT}
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        return json.load(resp)


# --- OpenStreetMap gyms -------------------------------------------------------

def overpass_query(iso_area):
    """Indoor climbing facilities inside an ISO 3166 area (e.g. 'US', 'US-CO', 'FR')."""
    key = "ISO3166-2" if "-" in iso_area else "ISO3166-1"
    return f"""
[out:json][timeout:170];
area["{key}"="{iso_area}"]->.a;
(
  nwr["leisure"~"sports_centre|sports_hall|fitness_centre"]["sport"~"climbing|bouldering"](area.a);
  nwr["climbing"="gym"](area.a);
);
out center tags;
"""


def osm_disciplines(tags):
    sport = tags.get("sport", "")
    result = []
    if "bouldering" in sport or tags.get("climbing:boulder") == "yes" or "boulder" in tags.get("name", "").lower():
        result.append("boulder")
    if tags.get("climbing:sport") == "yes" or tags.get("climbing:toprope") == "yes" or "bouldering" not in sport:
        result += ["sport", "topRope"]
    return result or ["boulder"]


def osm_to_place(element):
    tags = element.get("tags", {})
    name = tags.get("name")
    lat = element.get("lat") or element.get("center", {}).get("lat")
    lon = element.get("lon") or element.get("center", {}).get("lon")
    if not name or lat is None or lon is None:
        return None
    # Skip outdoor climbing mapped as sports facilities.
    if tags.get("indoor") == "no" or tags.get("natural") in ("cliff", "rock"):
        return None
    osm_id = f"{element['type']}/{element['id']}"
    return {
        "id": f"p_osm_{element['type'][0]}{element['id']}",
        "name": name,
        "kind": "gym",
        "city": tags.get("addr:city", ""),
        "region": tags.get("addr:state", ""),
        "country": tags.get("addr:country", ""),
        "latitude": lat,
        "longitude": lon,
        "disciplines": osm_disciplines(tags),
        "about": tags.get("description", ""),
        "source": "openStreetMap",
        "externalID": osm_id,
        # Imported data is trustworthy enough to show, but owners should claim/verify.
        "isVerified": False,
    }


def import_osm(args):
    raw = post(OVERPASS_URL, ("data=" + urllib.parse.quote(overpass_query(args.area))).encode(),
               "application/x-www-form-urlencoded")
    return [p for p in map(osm_to_place, raw.get("elements", [])) if p]


# --- OpenBeta crags -----------------------------------------------------------

OPENBETA_QUERY = """
query Crags($tokens: [String]!) {
  areas(filter: { path_tokens: { tokens: $tokens } }) {
    uuid
    area_name
    pathTokens
    totalClimbs
    metadata { lat lng isBoulder }
    content { description }
  }
}
"""


def openbeta_to_place(area, country_hint):
    meta = area.get("metadata") or {}
    if meta.get("lat") is None or meta.get("lng") is None:
        return None
    tokens = area.get("pathTokens") or []
    description = ((area.get("content") or {}).get("description") or "").strip()
    return {
        "id": f"p_ob_{area['uuid']}",
        "name": area["area_name"],
        "kind": "crag",
        # pathTokens look like [Country, State, Region, Crag, ...]
        "city": tokens[2] if len(tokens) > 3 else "",
        "region": tokens[1] if len(tokens) > 1 else "",
        "country": country_hint or (tokens[0] if tokens else ""),
        "latitude": meta["lat"],
        "longitude": meta["lng"],
        "disciplines": ["boulder"] if meta.get("isBoulder") else ["sport", "trad"],
        "about": description[:500],
        "source": "openBeta",
        "externalID": area["uuid"],
        "isVerified": True,
    }


def import_openbeta(args):
    raw = post(OPENBETA_URL,
               json.dumps({"query": OPENBETA_QUERY, "variables": {"tokens": args.path}}).encode(),
               "application/json")
    if raw.get("errors"):
        sys.exit(f"OpenBeta error: {raw['errors']}")
    areas = raw["data"]["areas"]
    # Depth decides what counts as a "crag" (a followable place) vs. a region or a single wall.
    picked = [a for a in areas
              if len(a.get("pathTokens") or []) == args.depth and a.get("totalClimbs", 0) >= args.min_climbs]
    return [p for p in (openbeta_to_place(a, args.path[0]) for a in picked) if p]


# --- OpenBeta climbs -------------------------------------------------------------

OPENBETA_CLIMBS_QUERY = """
query CragClimbs($tokens: [String]!) {
  areas(filter: { path_tokens: { tokens: $tokens } }) {
    uuid
    area_name
    pathTokens
    climbs {
      uuid
      name
      grades { vscale yds font french }
      type { sport trad bouldering tr }
      content { description }
    }
  }
}
"""

# App grade systems, in preference order per discipline.
GRADE_FIELDS = {"boulder": [("vscale", "vScale"), ("font", "font")],
                "rope": [("yds", "yds"), ("french", "french")]}


def climb_discipline(types):
    types = types or {}
    if types.get("bouldering"):
        return "boulder"
    if types.get("trad"):
        return "trad"
    if types.get("sport"):
        return "sport"
    if types.get("tr"):
        return "topRope"
    return None


def yds_letter_grade(value):
    """'5.10-' → 5.10a, '5.10' → 5.10b, '5.10+' → 5.10c (the app's YDS scale uses letters from 5.10 up)."""
    base = value.split()[0].split("/")[0]  # "5.12a/b" → 5.12a
    modifier = base[-1] if base[-1] in "+-" else ""
    base = base.rstrip("+-")
    try:
        number = int(base.split(".")[1]) if base.startswith("5.") and base[2:].isdigit() else None
    except (IndexError, ValueError):
        number = None
    if number is not None and number >= 10:
        return base + {"-": "a", "": "b", "+": "c"}[modifier]
    return base


def climb_grade(grades, discipline):
    grades = grades or {}
    for field, system in GRADE_FIELDS["boulder" if discipline == "boulder" else "rope"]:
        value = (grades.get(field) or "").strip()
        if value:
            # OpenBeta sometimes adds modifiers ("V4-5", "5.10+"); keep the base grade the app knows.
            if system == "vScale":
                value = value.split("-")[0].rstrip("+-")
            if system == "yds":
                value = yds_letter_grade(value)
            return {"system": system, "value": value}
    return None


def openbeta_climb(climb, crag_id, area_name):
    discipline = climb_discipline(climb.get("type"))
    if not discipline:  # ice, alpine, aid-only… not supported in the app yet
        return None
    record = {
        "id": f"c_ob_{climb['uuid']}",
        "placeID": crag_id,
        "name": climb["name"],
        "area": area_name,
        "discipline": discipline,
        "about": ((climb.get("content") or {}).get("description") or "").strip()[:500],
        "source": "openBeta",
        "externalID": climb["uuid"],
        "isVerified": True,
    }
    grade = climb_grade(climb.get("grades"), discipline)
    if grade:
        record["grade"] = grade
    return record


def import_openbeta_climbs(args):
    raw = post(OPENBETA_URL,
               json.dumps({"query": OPENBETA_CLIMBS_QUERY, "variables": {"tokens": args.path}}).encode(),
               "application/json")
    if raw.get("errors"):
        sys.exit(f"OpenBeta error: {raw['errors']}")
    areas = raw["data"]["areas"]
    crag = next((a for a in areas if a.get("pathTokens") == args.path), None)
    if crag is None:
        sys.exit(f"No OpenBeta area with path {args.path}")
    crag_id = args.crag_id or f"p_ob_{crag['uuid']}"
    depth = len(args.path)
    climbs = []
    for area in areas:
        tokens = area.get("pathTokens") or []
        # Group under the wall/boulder directly below the crag ("Midnight Lightning" → "Camp 4").
        area_name = tokens[depth] if len(tokens) > depth else ""
        for climb in area.get("climbs") or []:
            record = openbeta_climb(climb, crag_id, area_name)
            if record:
                climbs.append(record)
    return climbs


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="source", required=True)

    osm = sub.add_parser("osm", help="climbing gyms from OpenStreetMap")
    osm.add_argument("--area", required=True, help="ISO 3166 code, e.g. US, US-CO, GB, FR")
    osm.set_defaults(run=import_osm)

    ob = sub.add_parser("openbeta", help="outdoor crags from OpenBeta")
    ob.add_argument("--path", nargs="+", required=True, help="area path prefix, e.g. USA Kentucky")
    ob.add_argument("--depth", type=int, default=4, help="pathTokens length treated as a crag")
    ob.add_argument("--min-climbs", type=int, default=10, help="skip tiny areas")
    ob.set_defaults(run=import_openbeta)

    obc = sub.add_parser("openbeta-climbs", help="all climbs inside one OpenBeta crag")
    obc.add_argument("--path", nargs="+", required=True, help="the crag's full area path")
    obc.add_argument("--crag-id", help="CHOSS place ID to attach climbs to (default: p_ob_<crag uuid>)")
    obc.set_defaults(run=import_openbeta_climbs)

    args = parser.parse_args()
    places = args.run(args)
    json.dump(places, sys.stdout, indent=2, ensure_ascii=False)
    print(f"\n{len(places)} records", file=sys.stderr)


if __name__ == "__main__":
    main()
