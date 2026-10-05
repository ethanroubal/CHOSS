-- Cleaning up media nobody can see any more. The database queues what to remove; the
-- `media-cleanup` Edge Function (run hourly, see the end of this file) removes it from Mux and
-- Storage, which can only be done through their APIs.
--
-- 1. Videos of deleted posts (deleted by their author, or with a deleted account) are deleted
--    from Mux, so they stop counting toward the Mux bill.
-- 2. Profile pictures that were replaced (or whose account was deleted) are deleted from Storage.
-- 3. Uploads abandoned for a day (still "uploading") are marked failed and removed.

-- Mux videos / uploads to delete.
create table if not exists public.mux_cleanup (
  kind       text not null check (kind in ('asset', 'upload')),
  mux_id     text not null,
  queued_at  timestamptz not null default now(),
  attempts   integer not null default 0,
  primary key (kind, mux_id)
);

-- Storage files to delete.
create table if not exists public.storage_cleanup (
  bucket     text not null,
  path       text not null,
  queued_at  timestamptz not null default now(),
  attempts   integer not null default 0,
  primary key (bucket, path)
);

-- Server-only: no policies, so the app's roles can't read or write them.
alter table public.mux_cleanup enable row level security;
alter table public.storage_cleanup enable row level security;
revoke all on public.mux_cleanup, public.storage_cleanup from anon, authenticated;
grant all on public.mux_cleanup, public.storage_cleanup to service_role;

-- A post's video: delete the Mux asset if there is one, else cancel its upload.
create or replace function public.queue_mux_cleanup(asset text, upload text) returns void
language sql security definer set search_path = '' as $$
  insert into public.mux_cleanup (kind, mux_id)
  select 'asset', asset where asset is not null
  union all
  select 'upload', upload where upload is not null and asset is null
  on conflict do nothing
$$;
revoke all on function public.queue_mux_cleanup(text, text) from public, anon, authenticated;

create or replace function public.posts_media_cleanup() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    -- Row removed (e.g. its account was deleted).
    perform public.queue_mux_cleanup(old.mux_asset_id, old.mux_upload_id);
    return old;
  end if;
  if new.deleted_at is not null and old.deleted_at is null then
    -- Deleted by its author (delete_post) or swept as abandoned.
    perform public.queue_mux_cleanup(new.mux_asset_id, new.mux_upload_id);
  elsif new.deleted_at is not null and new.mux_asset_id is distinct from old.mux_asset_id then
    -- Mux finished processing a video whose post was already deleted.
    perform public.queue_mux_cleanup(new.mux_asset_id, null);
  end if;
  return new;
end; $$;

drop trigger if exists posts_media_cleanup on public.posts;
create trigger posts_media_cleanup after update of deleted_at, mux_asset_id or delete on public.posts
  for each row execute function public.posts_media_cleanup();

create or replace function public.profiles_avatar_cleanup() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    if old.avatar_path is not null then
      insert into public.storage_cleanup (bucket, path) values ('avatars', old.avatar_path)
      on conflict do nothing;
    end if;
    return old;
  end if;
  if old.avatar_path is not null and old.avatar_path is distinct from new.avatar_path then
    insert into public.storage_cleanup (bucket, path) values ('avatars', old.avatar_path)
    on conflict do nothing;
  end if;
  return new;
end; $$;

drop trigger if exists profiles_avatar_cleanup on public.profiles;
create trigger profiles_avatar_cleanup after update of avatar_path or delete on public.profiles
  for each row execute function public.profiles_avatar_cleanup();

-- Posts whose video never finished uploading within a day: marked failed and deleted (which
-- queues their Mux upload for cancelling). Returns how many.
create or replace function public.sweep_stale_uploads(older_than interval default interval '24 hours')
returns integer
language plpgsql security definer set search_path = '' as $$
declare swept integer;
begin
  update public.posts
     set video_status = 'failed', deleted_at = now()
   where video_status = 'uploading' and deleted_at is null and created_at < now() - older_than;
  get diagnostics swept = row_count;
  return swept;
end; $$;
revoke all on function public.sweep_stale_uploads(interval) from public, anon, authenticated;
grant execute on function public.sweep_stale_uploads(interval) to service_role;

-- Run the cleanup function every hour (on Supabase, where pg_cron and pg_net exist). It reads
-- the project URL and a shared secret from Vault, so neither is stored in this repository:
--   select vault.create_secret('https://<project ref>.supabase.co', 'project_url');
--   select vault.create_secret('<long random string>', 'cleanup_secret');
-- and give the function the same secret: supabase secrets set CLEANUP_SECRET=<same string>
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_cron with schema pg_catalog;
    create extension if not exists pg_net with schema extensions;
    if exists (select 1 from cron.job where jobname = 'media-cleanup') then
      perform cron.unschedule('media-cleanup');
    end if;
    perform cron.schedule('media-cleanup', '17 * * * *', $cron$
      select net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
               || '/functions/v1/media-cleanup',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cleanup-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cleanup_secret')
        ),
        body := '{}'::jsonb
      )
    $cron$);
  end if;
end $$;
