-- Watching your own video counts as a view too (still once per 10 seconds per person).
create or replace function public.record_view(p_post uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  total integer;
  counted boolean := false;
begin
  if me is not null and exists (select 1 from public.posts where id = p_post and deleted_at is null) then
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
