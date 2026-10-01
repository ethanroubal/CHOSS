-- Comments on a crag's / gym's page or a climb's page (conditions, access, beta…), separate
-- from comments on send videos (public.comments).
create table if not exists public.page_comments (
  id          uuid primary key default gen_random_uuid(),
  place_id    uuid references public.places (id) on delete cascade,
  climb_id    uuid references public.climbs (id) on delete cascade,
  author_id   uuid not null references public.profiles (id) on delete cascade,
  body        text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at  timestamptz not null default now(),
  -- On exactly one page.
  check ((place_id is null) <> (climb_id is null))
);
create index if not exists page_comments_by_place on public.page_comments (place_id, created_at) where place_id is not null;
create index if not exists page_comments_by_climb on public.page_comments (climb_id, created_at) where climb_id is not null;
create index if not exists page_comments_by_author on public.page_comments (author_id);

alter table public.page_comments enable row level security;
create policy "page comments are public" on public.page_comments for select using (true);
create policy "page comment as yourself" on public.page_comments for insert to authenticated
  with check (author_id = auth.uid());
create policy "delete own page comments" on public.page_comments for delete to authenticated
  using (author_id = auth.uid());

-- Newer Supabase projects don't grant new tables to the API roles automatically.
grant select on public.page_comments to anon, authenticated;
grant insert (id, place_id, climb_id, author_id, body), delete on public.page_comments to authenticated;
grant all on public.page_comments to service_role;
