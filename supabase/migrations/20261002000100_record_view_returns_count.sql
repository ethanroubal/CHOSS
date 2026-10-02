-- record_view now returns the post's current view count, so the app shows the real number
-- (including other people's views since it loaded) instead of guessing.
drop function if exists public.record_view(uuid);
create function public.record_view(p_post uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  total integer;
begin
  -- Your own videos, and signed-out callers, don't count.
  if me is not null and not exists (select 1 from public.posts where id = p_post and author_id = me) then
    -- One view per person per post per day.
    insert into public.post_view_dedupe (post_id, viewer_id) values (p_post, me) on conflict do nothing;
    if found then
      update public.posts set view_count = view_count + 1 where id = p_post;
    end if;
  end if;
  select view_count into total from public.posts where id = p_post and deleted_at is null;
  return total;
end; $$;
revoke all on function public.record_view(uuid) from public, anon;
grant execute on function public.record_view(uuid) to authenticated;
