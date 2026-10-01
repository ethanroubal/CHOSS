-- Explicit table access for the app's roles. Newer Supabase projects don't give new tables
-- to `anon` / `authenticated` automatically ("permission denied for table …"), so every
-- table the app uses is granted here. Row Level Security still decides which ROWS each person
-- can see or change; column grants in the initial migration limit which COLUMNS.

grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to anon, authenticated, service_role;

-- Reading: everything public (RLS filters rows, e.g. unfinished posts, hidden projects).
grant select on all tables in schema public to anon, authenticated;
revoke select on public.post_view_dedupe from anon, authenticated;   -- only via record_view()

-- Relationship rows: add and remove your own (RLS checks they're yours).
grant insert, delete on
  public.post_likes,
  public.comments,
  public.reposts,
  public.user_follows,
  public.place_follows,
  public.projects,
  public.photo_likes,
  public.profile_home_places,
  public.user_blocks
to authenticated;

grant insert on public.reports to authenticated;
-- Only the uploader can delete a photo (RLS); inserts are column-limited in the first migration.
grant delete on public.community_photos to authenticated;
