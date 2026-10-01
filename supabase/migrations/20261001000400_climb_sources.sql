-- Imported outdoor climbs (supabase/seeds/climbs_*.sql, from scripts/import_climbs_xlsx.py):
-- where each climb came from and its own location. Ids of OpenBeta climbs are OpenBeta's own
-- climb ids; other sources keep their URL in external_id so re-imports update in place.
alter table public.climbs
  add column if not exists external_id text unique,
  add column if not exists latitude    double precision check (latitude between -90 and 90),
  add column if not exists longitude   double precision check (longitude between -180 and 180);

-- A crag's climbs in name order (the crag page / route picker page through these).
create index if not exists climbs_by_place_name on public.climbs (place_id, name, id);
