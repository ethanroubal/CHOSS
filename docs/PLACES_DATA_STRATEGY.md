# Populating gyms & crags

**Question:** should CHOSS ship a pre-built list of every climbing gym and outdoor crag,
or let users add places themselves?

**Recommendation: do both.** Seed from open datasets so the app isn't empty on day one,
and let users add what's missing, with light moderation. Pure user-generated places give
you a cold-start problem and lots of duplicates ("Movement Gowanus" vs. "movement brooklyn").
A pure import is never complete, especially for new gyms and local boulder fields.

The `Place` model already supports this: `source`, `externalID`, `isVerified`, `createdBy`.

---

## 1. Data sources

| Source | Covers | License / access | Verdict |
|---|---|---|---|
| **OpenStreetMap** (Overpass API) | Indoor gyms (`sport=climbing`/`bouldering` on `leisure=sports_centre`, `climbing=gym`) and some crags (`sport=climbing` + `natural=cliff`, `climbing=crag`) | ODbL: free, but you have to show attribution ("© OpenStreetMap contributors"), and share-alike applies to the derived *database* | **Use it for gyms.** Coverage is good in the US/EU and patchy elsewhere. |
| **OpenBeta** (GraphQL API + weekly Parquet exports) | About 200k routes worldwide, organized by area hierarchy (Country → State → Region → Crag) with coordinates | Nonprofit. The climbing data is CC0 (public domain); the API code is AGPL, which doesn't affect you as a client | **Use it for crags.** It's the best open outdoor dataset, and it could later give CHOSS route-level tagging. |
| **Mountain Project** | The most complete US outdoor data | Public API closed in 2020 after onX bought it; onX has sent DMCA takedowns over scraped data | **Don't use it.** Don't scrape it. |
| **theCrag** | Strong outside the US | API needs a partner agreement | Worth asking about later for international coverage. |
| **Google Places / Apple Maps (MapKit `MKLocalSearch`)** | Nearly every gym, with fresh hours and addresses | Paid (Google) or free on-device (Apple). Terms mostly forbid storing results permanently | **Use it in the "Add a place" flow** to autocomplete a gym's name and address. Don't use it as the stored source of truth. |
| **Gym owners** | Their own gym | You control it | A "claim this gym" flow gives a verified badge and lets them post set updates. It's also a good partnership and marketing channel later. |

## 2. Plan

1. **Seed** (`scripts/import_places.py`):
   - `osm --area US` (then CA, GB, FR, DE and so on) to import gyms. `isVerified = false` until they're claimed or reviewed.
   - `openbeta --path USA <State> --depth 4` to import crags. Tune `--depth` and `--min-climbs` per region, because OpenBeta's hierarchy depth varies. A "crag" in CHOSS should be something people would say they "went to", like *Muir Valley* or *the Buttermilks*, not one boulder or a whole state.
   - Upsert on `(source, externalID)` so imports can be re-run safely.
2. **User-submitted places** (already built: *Tag a place → Can't find it? Add a gym or crag*):
   - The place is visible right away, marked unverified, and auto-followed by its creator.
   - **Duplicate check before insert:** same `kind` within about 300 m (gym) or 2 km (crag) and a fuzzy name match (trigram similarity > 0.4) should prompt "Did you mean …?". PostGIS plus `pg_trgm` in Postgres handles this in one query.
   - Set a rate limit per user, and add a "report / suggest edit" option on the place page.
3. **Verification:** gym owners claim their gym (confirmed by email domain or a phone call). For crags, a place counts as verified when it came from OpenBeta or after N distinct climbers have posted there.
4. **Merging:** admins merge duplicates. Posts get re-pointed to the surviving place, and the old ID becomes an alias so deep links still work.

### Outdoor climbs

Crags also get a list of permanent climbs (`Climb` model), so every video of a climb collects on
that climb's page as beta. Gyms don't, because their routes are reset every few weeks.

- **Seed** from OpenBeta: `scripts/import_places.py openbeta-climbs --path <crag path> --crag-id <place id>`.
  It groups climbs by the wall or boulder directly under the crag and maps OpenBeta grades onto the app's scales (e.g. `5.10+` becomes `5.10c`).
- **User-added:** from the composer or the crag's Climbs tab. If a very similar name already exists at that crag, the app suggests "Did you mean…?" first. New climbs are marked unverified.
- **Moderation:** handled the same way as places (merge duplicates and re-point posts). A verified climb needs an OpenBeta match or several climbers posting to it.

## 3. Why not only user-added?

- **Cold start:** a new user searches for their gym, and if it isn't there they may leave the app.
- **Quality:** user entries have typos and wrong pins, and they multiply duplicates, which splits one gym's community across several pages. That defeats the app's main feature.
- **Cost:** importing is cheap (OSM and OpenBeta are free), and moderating a small set of user additions is manageable.

## 4. Backend note

When you move off the mock repository, **Supabase** (Postgres + PostGIS + Storage + Auth)
suits this data well:
- `places` table with a `geography(Point)` column: "gyms near me" is `ST_DWithin`.
- Follow graph: `place_follows(user_id, place_id)` and `user_follows(follower_id, followee_id)`.
- Home feed: `posts WHERE place_id IN (my places) OR author_id IN (my follows) ORDER BY created_at DESC`, with keyset pagination. Past roughly 100k users, switch to fan-out-on-write feed tables.
- Video: upload to Storage/S3, then transcode to HLS (Mux, Cloudflare Stream, or AWS MediaConvert) so the feed streams at adaptive bitrate.

Firebase also works, but geo queries and feed joins are much clumsier there.
