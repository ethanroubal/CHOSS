-- Every rewatch counts as a view. The only limit: the same person's views of the same video
-- less than 10 seconds apart count once (e.g. tapping from the feed into full screen), which
-- also stops a script from inflating counts quickly.
create table if not exists public.post_view_last (
  post_id    uuid not null references public.posts (id) on delete cascade,
  viewer_id  uuid not null references public.profiles (id) on delete cascade,
  viewed_at  timestamptz not null default now(),
  primary key (post_id, viewer_id)
);
alter table public.post_view_last enable row level security;   -- no policies: only record_view
revoke all on public.post_view_last from anon, authenticated;
grant all on public.post_view_last to service_role;

create or replace function public.record_view(p_post uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  total integer;
  counted boolean := false;
begin
  -- Your own videos, and signed-out callers, don't count.
  if me is not null and not exists (select 1 from public.posts where id = p_post and author_id = me) then
    insert into public.post_view_last as v (post_id, viewer_id) values (p_post, me)
    on conflict (post_id, viewer_id) do update set viewed_at = now()
      where v.viewed_at < now() - interval '10 seconds'
    returning true into counted;
    if counted then
      update public.posts set view_count = view_count + 1 where id = p_post;
    end if;
  end if;
  select view_count into total from public.posts where id = p_post and deleted_at is null;
  return total;
end; $$;

-- The old once-a-day table isn't used any more.
drop table if exists public.post_view_dedupe;
