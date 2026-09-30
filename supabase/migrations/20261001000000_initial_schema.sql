-- CHOSS initial schema (Supabase / Postgres 15+).
--
-- Design (see docs/BACKEND_PLAN.md):
-- * One row per thing, and one row per relationship (likes, follows, reposts…): adding or
--   removing one is a single-row insert / delete on a primary key.
-- * Counts shown in the app (likes, views, followers, sends…) are stored on the parent row and
--   kept up to date by triggers, so screens never count rows at read time.
-- * Everything the app lists is served by an index in the order it's shown (newest first,
--   most liked first…), with keyset pagination (no OFFSET).
-- * Row Level Security: anyone can read public content; people can only write their own rows.
--   Counters can't be written by clients at all (column privileges).
-- * Videos live in Mux (transcoded, adaptive HLS, CDN); photos in Supabase Storage (CDN).
--   The database only stores their ids / paths.

create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists citext with schema extensions;
-- Name matching (unaccent, trigrams) runs as the signed-in user, so they need the schema.
grant usage on schema extensions to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------------------------

create type public.place_kind as enum ('gym', 'crag');
create type public.discipline as enum ('boulder', 'board', 'sport', 'trad', 'topRope', 'ice', 'solo', 'other');
create type public.send_style as enum ('onsight', 'flash', 'redpoint', 'repeatSend', 'link', 'other');
create type public.grade_system as enum ('vScale', 'font', 'yds', 'french', 'british', 'waterIce', 'mixed');
create type public.video_status as enum ('uploading', 'processing', 'ready', 'failed');
create type public.report_target as enum ('post', 'comment', 'photo', 'profile', 'place', 'climb');

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

-- Same normalization as the app's NameMatcher.normalize: lowercase, no accents, runs of
-- non-alphanumerics collapsed to one space. Immutable so it can back indexes.
create or replace function public.norm_name(input text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select btrim(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(input, ''))),
                              '[^[:alnum:]]+', ' ', 'g'))
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Grades: every grade's position on its scale and on the scale it's compared on.
-- Filled by 20261001000100_grades.sql (generated from the app).
-- ---------------------------------------------------------------------------------------------

create table public.grades (
  system            public.grade_system not null,
  value             text not null,
  rank              smallint not null,
  comparable_system public.grade_system not null,
  comparable_rank   smallint,                 -- null: can't be compared (none today)
  primary key (system, value),
  unique (system, rank)
);

-- ---------------------------------------------------------------------------------------------
-- Profiles (one per auth user)
-- ---------------------------------------------------------------------------------------------

create table public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  username            extensions.citext not null unique
                        check (username ~ '^[A-Za-z0-9._]{3,30}$'),
  display_name        text not null default '' check (char_length(display_name) <= 60),
  bio                 text not null default '' check (char_length(bio) <= 300),
  avatar_path         text,                   -- Storage: avatars/<user id>/<file>
  boulder_system      public.grade_system,
  boulder_low         text,
  boulder_high        text,
  rope_system         public.grade_system,
  rope_low            text,
  rope_high           text,
  shows_grade_range   boolean not null default true,
  shows_hardest_send  boolean not null default true,
  shows_projects      boolean not null default true,
  -- Maintained by triggers:
  follower_count      integer not null default 0,
  following_count     integer not null default 0,
  places_followed     integer not null default 0,
  post_count          integer not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  search_name         text generated always as (public.norm_name(username::text || ' ' || display_name)) stored
);
create index profiles_search_trgm on public.profiles using gin (search_name extensions.gin_trgm_ops);
create index profiles_popular on public.profiles (follower_count desc);
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------------------------
-- Places (gyms and crags)
-- ---------------------------------------------------------------------------------------------

create table public.places (
  id              uuid primary key default gen_random_uuid(),
  external_id     text unique,                -- id in the source dataset / the app's bundled id
  name            text not null check (char_length(name) between 1 and 120),
  kind            public.place_kind not null,
  city            text not null default '',
  region          text not null default '',
  country         text not null default '',
  latitude        double precision not null check (latitude between -90 and 90),
  longitude       double precision not null check (longitude between -180 and 180),
  disciplines     public.discipline[] not null default '{}',   -- empty: any
  about           text not null default '' check (char_length(about) <= 2000),
  source          text not null default 'userSubmitted',
  is_verified     boolean not null default false,
  created_by      uuid references public.profiles (id) on delete set null,
  -- Maintained by triggers:
  follower_count  integer not null default 0,
  post_count      integer not null default 0,
  cover_photo_id  uuid,                       -- most-liked community photo
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  search_name     text generated always as (public.norm_name(name)) stored,
  search_town     text generated always as (public.norm_name(city || ' ' || region)) stored
);
create index places_search_trgm on public.places using gin (search_name extensions.gin_trgm_ops);
create index places_town_trgm on public.places using gin (search_town extensions.gin_trgm_ops);
-- Map: places inside the visible rectangle (point is (longitude, latitude)).
create index places_location on public.places using gist (point(longitude, latitude));
create index places_popular on public.places (kind, follower_count desc, post_count desc);
create trigger places_touch before update on public.places
  for each row execute function public.touch_updated_at();

-- A climber's home gyms / crags (up to 3, ordered).
create table public.profile_home_places (
  user_id   uuid not null references public.profiles (id) on delete cascade,
  place_id  uuid not null references public.places (id) on delete cascade,
  position  smallint not null check (position between 0 and 2),
  primary key (user_id, place_id),
  unique (user_id, position)
);

-- ---------------------------------------------------------------------------------------------
-- Climbs (named outdoor routes / problems)
-- ---------------------------------------------------------------------------------------------

create table public.climbs (
  id              uuid primary key default gen_random_uuid(),
  place_id        uuid not null references public.places (id) on delete cascade,
  name            text not null check (char_length(name) between 1 and 120),
  area            text not null default '' check (char_length(area) <= 120),
  discipline      public.discipline not null,
  grade_system    public.grade_system,        -- guidebook grade (optional)
  grade_value     text,
  about           text not null default '' check (char_length(about) <= 2000),
  is_verified     boolean not null default false,
  created_by      uuid references public.profiles (id) on delete set null,
  -- Maintained by triggers:
  post_count      integer not null default 0,
  cover_photo_id  uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  search_name     text generated always as (public.norm_name(name)) stored,
  foreign key (grade_system, grade_value) references public.grades (system, value)
);
create index climbs_by_place on public.climbs (place_id, search_name);
create index climbs_search_trgm on public.climbs using gin (search_name extensions.gin_trgm_ops);
create index climbs_popular on public.climbs (post_count desc);
create trigger climbs_touch before update on public.climbs
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------------------------
-- Posts (send videos)
-- ---------------------------------------------------------------------------------------------

create table public.posts (
  id                     uuid primary key default gen_random_uuid(),
  author_id              uuid not null references public.profiles (id) on delete cascade,
  place_id               uuid references public.places (id) on delete set null,
  climb_id               uuid references public.climbs (id) on delete set null,
  route_name             text not null default '' check (char_length(route_name) <= 120),
  -- "Same climb" key (set by trigger): climb:<id>, or route:<place>:<normalized name> for
  -- named board problems. Groups proposals into a community grade.
  climb_key              text,
  discipline             public.discipline not null,
  send_style             public.send_style not null default 'redpoint',
  proposed_grade_system  public.grade_system,
  proposed_grade_value   text,
  caption                text not null default '' check (char_length(caption) <= 2200),
  -- Video (Mux). The app streams https://stream.mux.com/<playback id>.m3u8 and shows
  -- https://image.mux.com/<playback id>/thumbnail.jpg.
  video_status           public.video_status not null default 'uploading',
  mux_upload_id          text unique,
  mux_asset_id           text unique,
  mux_playback_id        text,
  video_duration         real,
  video_aspect_ratio     real,                -- width / height
  -- Maintained by triggers / functions:
  like_count             integer not null default 0,
  comment_count          integer not null default 0,
  repost_count           integer not null default 0,
  view_count             integer not null default 0,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  deleted_at             timestamptz,         -- soft delete (keeps counters consistent)
  foreign key (proposed_grade_system, proposed_grade_value) references public.grades (system, value)
);
-- One index per list the app shows, in the order it's shown.
create index posts_recent on public.posts (created_at desc, id desc) where deleted_at is null and video_status = 'ready';
create index posts_by_author on public.posts (author_id, created_at desc) where deleted_at is null;
create index posts_by_place on public.posts (place_id, created_at desc) where deleted_at is null;
create index posts_by_climb on public.posts (climb_id, created_at desc) where deleted_at is null;
create index posts_by_climb_key on public.posts (climb_key) where deleted_at is null;
create index posts_trending on public.posts (like_count desc, created_at desc) where deleted_at is null and video_status = 'ready';
create index posts_leaderboard on public.posts (place_id, discipline, author_id) where deleted_at is null;
create trigger posts_touch before update on public.posts
  for each row execute function public.touch_updated_at();

create or replace function public.posts_set_climb_key()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.climb_key := case
    when new.climb_id is not null then 'climb:' || new.climb_id
    when public.norm_name(new.route_name) <> '' then
      'route:' || coalesce(new.place_id::text, 'user:' || new.author_id) || ':' || public.norm_name(new.route_name)
    else null
  end;
  return new;
end;
$$;
create trigger posts_climb_key before insert or update of climb_id, place_id, route_name on public.posts
  for each row execute function public.posts_set_climb_key();

-- Community grade: proposal totals per climb and scale, updated as posts come and go.
-- The average is the most-used scale's mean rank (see climb_grades).
create table public.climb_grade_votes (
  climb_key  text not null,
  system     public.grade_system not null,
  votes      integer not null default 0,
  rank_sum   integer not null default 0,
  primary key (climb_key, system)
);

create or replace function public.posts_grade_votes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_live boolean := false;
  new_live boolean := false;
begin
  if tg_op <> 'INSERT' then
    old_live := old.deleted_at is null and old.proposed_grade_system is not null and old.climb_key is not null;
  end if;
  if tg_op <> 'DELETE' then
    new_live := new.deleted_at is null and new.proposed_grade_system is not null and new.climb_key is not null;
  end if;
  if old_live then
    update public.climb_grade_votes v
       set votes = v.votes - 1,
           rank_sum = v.rank_sum - g.rank
      from public.grades g
     where v.climb_key = old.climb_key and v.system = old.proposed_grade_system
       and g.system = old.proposed_grade_system and g.value = old.proposed_grade_value;
  end if;
  if new_live then
    insert into public.climb_grade_votes as v (climb_key, system, votes, rank_sum)
    select new.climb_key, new.proposed_grade_system, 1, g.rank
      from public.grades g
     where g.system = new.proposed_grade_system and g.value = new.proposed_grade_value
    on conflict (climb_key, system) do update
      set votes = v.votes + 1, rank_sum = v.rank_sum + excluded.rank_sum;
  end if;
  return null;
end;
$$;
create trigger posts_grade_votes after insert or delete or update of proposed_grade_system, proposed_grade_value, climb_key, deleted_at
  on public.posts for each row execute function public.posts_grade_votes();

-- Each climb's community grade: the mean of proposals on the scale most people used.
create or replace view public.climb_grades with (security_invoker = true) as
select distinct on (v.climb_key)
       v.climb_key,
       v.system,
       g.value,
       v.votes
  from public.climb_grade_votes v
  join public.grades g
    on g.system = v.system and g.rank = round(v.rank_sum::numeric / v.votes)::smallint
 where v.votes > 0
 order by v.climb_key, v.votes desc, v.system;

-- ---------------------------------------------------------------------------------------------
-- Relationships (one row each; primary keys make toggling a single insert / delete)
-- ---------------------------------------------------------------------------------------------

create table public.post_likes (
  post_id     uuid not null references public.posts (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index post_likes_by_user on public.post_likes (user_id, created_at desc);   -- "Liked videos"

create table public.comments (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.posts (id) on delete cascade,
  author_id   uuid not null references public.profiles (id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 2000),
  created_at  timestamptz not null default now()
);
create index comments_by_post on public.comments (post_id, created_at);

create table public.reposts (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  post_id     uuid not null references public.posts (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index reposts_by_post on public.reposts (post_id);
create index reposts_by_user on public.reposts (user_id, created_at desc);

create table public.user_follows (
  follower_id  uuid not null references public.profiles (id) on delete cascade,
  followee_id  uuid not null references public.profiles (id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index user_follows_followers on public.user_follows (followee_id, created_at desc);

create table public.place_follows (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  place_id    uuid not null references public.places (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, place_id)
);
create index place_follows_by_place on public.place_follows (place_id);

create table public.projects (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  climb_id    uuid not null references public.climbs (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, climb_id)
);

-- Views: one per viewer per post per day (the app also only reports a view after the video
-- has been on screen for about a second). Old rows can be pruned; the count stays on posts.
create table public.post_view_dedupe (
  post_id    uuid not null references public.posts (id) on delete cascade,
  viewer_id  uuid not null references public.profiles (id) on delete cascade,
  day        date not null default current_date,
  primary key (post_id, viewer_id, day)
);

-- ---------------------------------------------------------------------------------------------
-- Community photos (places and climbs)
-- ---------------------------------------------------------------------------------------------

create table public.community_photos (
  id            uuid primary key default gen_random_uuid(),
  place_id      uuid references public.places (id) on delete cascade,
  climb_id      uuid references public.climbs (id) on delete cascade,
  author_id     uuid not null references public.profiles (id) on delete cascade,
  storage_path  text not null,                -- Storage: community-photos/<user id>/<file>
  width         integer,
  height        integer,
  like_count    integer not null default 0,
  created_at    timestamptz not null default now(),
  check ((place_id is null) <> (climb_id is null))   -- exactly one subject
);
create index community_photos_place on public.community_photos (place_id, like_count desc, created_at desc) where place_id is not null;
create index community_photos_climb on public.community_photos (climb_id, like_count desc, created_at desc) where climb_id is not null;

alter table public.places add constraint places_cover_photo_fk
  foreign key (cover_photo_id) references public.community_photos (id) on delete set null;
alter table public.climbs add constraint climbs_cover_photo_fk
  foreign key (cover_photo_id) references public.community_photos (id) on delete set null;

create table public.photo_likes (
  photo_id    uuid not null references public.community_photos (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (photo_id, user_id)
);

-- ---------------------------------------------------------------------------------------------
-- Safety (required by the App Store for user-generated content)
-- ---------------------------------------------------------------------------------------------

create table public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references public.profiles (id) on delete cascade,
  target_type  public.report_target not null,
  target_id    uuid not null,
  reason       text not null check (char_length(reason) between 1 and 1000),
  status       text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  created_at   timestamptz not null default now()
);
create index reports_open on public.reports (created_at) where status = 'open';

create table public.user_blocks (
  blocker_id  uuid not null references public.profiles (id) on delete cascade,
  blocked_id  uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- ---------------------------------------------------------------------------------------------
-- Counter triggers (security definer: they update rows the acting user doesn't own)
-- ---------------------------------------------------------------------------------------------

create or replace function public.bump(target regclass, id_column text, id_value uuid, count_column text, delta integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if id_value is null then return; end if;
  execute format('update %s set %I = greatest(%I + $1, 0) where %I = $2', target, count_column, count_column, id_column)
    using delta, id_value;
end;
$$;
revoke execute on function public.bump from public, anon, authenticated;

create or replace function public.count_post_likes() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then perform public.bump('public.posts', 'id', new.post_id, 'like_count', 1);
  else perform public.bump('public.posts', 'id', old.post_id, 'like_count', -1); end if;
  return null;
end; $$;
create trigger post_likes_count after insert or delete on public.post_likes
  for each row execute function public.count_post_likes();

create or replace function public.count_comments() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then perform public.bump('public.posts', 'id', new.post_id, 'comment_count', 1);
  else perform public.bump('public.posts', 'id', old.post_id, 'comment_count', -1); end if;
  return null;
end; $$;
create trigger comments_count after insert or delete on public.comments
  for each row execute function public.count_comments();

create or replace function public.count_reposts() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then perform public.bump('public.posts', 'id', new.post_id, 'repost_count', 1);
  else perform public.bump('public.posts', 'id', old.post_id, 'repost_count', -1); end if;
  return null;
end; $$;
create trigger reposts_count after insert or delete on public.reposts
  for each row execute function public.count_reposts();

create or replace function public.count_user_follows() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform public.bump('public.profiles', 'id', new.followee_id, 'follower_count', 1);
    perform public.bump('public.profiles', 'id', new.follower_id, 'following_count', 1);
  else
    perform public.bump('public.profiles', 'id', old.followee_id, 'follower_count', -1);
    perform public.bump('public.profiles', 'id', old.follower_id, 'following_count', -1);
  end if;
  return null;
end; $$;
create trigger user_follows_count after insert or delete on public.user_follows
  for each row execute function public.count_user_follows();

create or replace function public.count_place_follows() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform public.bump('public.places', 'id', new.place_id, 'follower_count', 1);
    perform public.bump('public.profiles', 'id', new.user_id, 'places_followed', 1);
  else
    perform public.bump('public.places', 'id', old.place_id, 'follower_count', -1);
    perform public.bump('public.profiles', 'id', old.user_id, 'places_followed', -1);
  end if;
  return null;
end; $$;
create trigger place_follows_count after insert or delete on public.place_follows
  for each row execute function public.count_place_follows();

-- Posts count toward their author, place and climb while live (not deleted).
create or replace function public.count_posts() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  old_live boolean := false;
  new_live boolean := false;
begin
  if tg_op <> 'INSERT' then old_live := old.deleted_at is null; end if;
  if tg_op <> 'DELETE' then new_live := new.deleted_at is null; end if;
  if old_live then
    perform public.bump('public.profiles', 'id', old.author_id, 'post_count', -1);
    perform public.bump('public.places', 'id', old.place_id, 'post_count', -1);
    perform public.bump('public.climbs', 'id', old.climb_id, 'post_count', -1);
  end if;
  if new_live then
    perform public.bump('public.profiles', 'id', new.author_id, 'post_count', 1);
    perform public.bump('public.places', 'id', new.place_id, 'post_count', 1);
    perform public.bump('public.climbs', 'id', new.climb_id, 'post_count', 1);
  end if;
  return null;
end; $$;
create trigger posts_count after insert or delete or update of deleted_at, place_id, climb_id on public.posts
  for each row execute function public.count_posts();

-- Photo likes, and keeping each place's / climb's cover = its most-liked photo.
create or replace function public.refresh_cover(p_place uuid, p_climb uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_place is not null then
    update public.places set cover_photo_id = (
      select id from public.community_photos where place_id = p_place
       order by like_count desc, created_at desc limit 1)
     where id = p_place;
  end if;
  if p_climb is not null then
    update public.climbs set cover_photo_id = (
      select id from public.community_photos where climb_id = p_climb
       order by like_count desc, created_at desc limit 1)
     where id = p_climb;
  end if;
end; $$;
revoke execute on function public.refresh_cover from public, anon, authenticated;

create or replace function public.count_photo_likes() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  pid uuid;
  photo record;
begin
  if tg_op = 'INSERT' then pid := new.photo_id; else pid := old.photo_id; end if;
  perform public.bump('public.community_photos', 'id', pid,
                      'like_count', case when tg_op = 'INSERT' then 1 else -1 end);
  select place_id, climb_id into photo from public.community_photos where id = pid;
  if found then perform public.refresh_cover(photo.place_id, photo.climb_id); end if;
  return null;
end; $$;
create trigger photo_likes_count after insert or delete on public.photo_likes
  for each row execute function public.count_photo_likes();

create or replace function public.photos_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_cover(old.place_id, old.climb_id);
  else
    perform public.refresh_cover(new.place_id, new.climb_id);
  end if;
  return null;
end; $$;
create trigger community_photos_cover after insert or delete on public.community_photos
  for each row execute function public.photos_changed();

-- ---------------------------------------------------------------------------------------------
-- Functions the app calls (RPC)
-- ---------------------------------------------------------------------------------------------

-- Delete your own post. It's hidden (soft delete) so counts and grade votes update through
-- the triggers; a scheduled job can purge old deleted rows and their Mux assets.
create or replace function public.delete_post(p_post uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.posts set deleted_at = now()
   where id = p_post and author_id = auth.uid() and deleted_at is null;
  if not found then
    raise exception 'Only the author can delete this post' using errcode = '42501';
  end if;
end; $$;

-- Log a view (the app calls this once a video has really been on screen).
create or replace function public.record_view(p_post uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid();
begin
  if me is null then return; end if;
  if exists (select 1 from public.posts where id = p_post and author_id = me) then return; end if;
  insert into public.post_view_dedupe (post_id, viewer_id) values (p_post, me) on conflict do nothing;
  if found then
    update public.posts set view_count = view_count + 1 where id = p_post;
  end if;
end; $$;

-- Home feed: your posts, posts at places you follow, posts by climbers you follow, and their
-- reposts. Newest first; pass the last row's (sort_ts, post_id) to get the next page.
create or replace function public.home_feed(before_ts timestamptz default null, before_id uuid default null, page_size integer default 20)
returns table (post_id uuid, reason text, reason_id uuid, sort_ts timestamptz)
language sql stable security invoker set search_path = '' as $$
  with me as (select auth.uid() as uid),
  candidates as (
    select p.id as post_id, 'own'::text as reason, null::uuid as reason_id, p.created_at as sort_ts, 1 as priority
      from public.posts p, me
     where p.author_id = me.uid and p.deleted_at is null
       and (before_ts is null or p.created_at <= before_ts)
    union all
    select p.id, 'place', p.place_id, p.created_at, 2
      from public.place_follows f join public.posts p on p.place_id = f.place_id, me
     where f.user_id = me.uid and p.deleted_at is null and p.video_status = 'ready'
       and (before_ts is null or p.created_at <= before_ts)
    union all
    select p.id, 'user', p.author_id, p.created_at, 3
      from public.user_follows f join public.posts p on p.author_id = f.followee_id, me
     where f.follower_id = me.uid and p.deleted_at is null and p.video_status = 'ready'
       and (before_ts is null or p.created_at <= before_ts)
    union all
    select r.post_id, 'repost', r.user_id, r.created_at, 4
      from public.user_follows f join public.reposts r on r.user_id = f.followee_id, me
     where f.follower_id = me.uid
       and (before_ts is null or r.created_at <= before_ts)
  ),
  best as (
    select distinct on (c.post_id) c.post_id, c.reason, c.reason_id, c.sort_ts
      from candidates c
     order by c.post_id, c.priority, c.sort_ts desc
  )
  select b.post_id, b.reason, b.reason_id, b.sort_ts
    from best b
   where (before_ts is null or (b.sort_ts, b.post_id) < (before_ts, before_id))
     and not exists (select 1 from public.user_blocks x, me where x.blocker_id = me.uid
                       and x.blocked_id = (select author_id from public.posts where id = b.post_id))
   order by b.sort_ts desc, b.post_id desc
   limit least(greatest(page_size, 1), 50)
$$;

-- Search (typo-tolerant, uses the trigram indexes). Best matches first, then popularity.
create or replace function public.search_places(q text, p_kind public.place_kind default null, max_results integer default 50)
returns setof public.places
language sql stable set search_path = public, extensions set pg_trgm.word_similarity_threshold = 0.3 as $$
  with query as (select public.norm_name(q) as t)
  select p.* from public.places p, query
   where query.t <> ''
     and (p_kind is null or p.kind = p_kind)
     and (p.search_name like '%' || query.t || '%' or query.t <% p.search_name or p.search_town like query.t || '%')
   order by (p.search_name = query.t) desc,
            (p.search_name like query.t || '%') desc,
            greatest(word_similarity(query.t, p.search_name), word_similarity(query.t, p.search_town) - 0.05) desc,
            p.follower_count desc, p.post_count desc
   limit least(greatest(max_results, 1), 100)
$$;

create or replace function public.search_climbs(q text, p_place uuid default null, max_results integer default 50)
returns setof public.climbs
language sql stable set search_path = public, extensions set pg_trgm.word_similarity_threshold = 0.3 as $$
  with query as (select public.norm_name(q) as t)
  select c.* from public.climbs c, query
   where query.t <> ''
     and (p_place is null or c.place_id = p_place)
     and (c.search_name like '%' || query.t || '%' or query.t <% c.search_name)
   order by (c.search_name = query.t) desc,
            (c.search_name like query.t || '%') desc,
            word_similarity(query.t, c.search_name) desc,
            c.post_count desc
   limit least(greatest(max_results, 1), 100)
$$;

create or replace function public.search_profiles(q text, max_results integer default 50)
returns setof public.profiles
language sql stable set search_path = public, extensions set pg_trgm.word_similarity_threshold = 0.3 as $$
  with query as (select public.norm_name(q) as t)
  select p.* from public.profiles p, query
   where query.t <> ''
     and (p.search_name like '%' || query.t || '%' or query.t <% p.search_name)
   order by (p.search_name like query.t || '%') desc,
            word_similarity(query.t, p.search_name) desc,
            p.follower_count desc
   limit least(greatest(max_results, 1), 100)
$$;

-- Map: the most popular places inside the visible rectangle.
create or replace function public.places_in_box(min_lat double precision, min_lng double precision,
                                                max_lat double precision, max_lng double precision,
                                                max_results integer default 250)
returns setof public.places
language sql stable set search_path = '' as $$
  select p.* from public.places p
   where point(p.longitude, p.latitude) <@ box(point(min_lng, min_lat), point(max_lng, max_lat))
   order by p.follower_count desc, p.post_count desc
   limit least(greatest(max_results, 1), 500)
$$;

-- Legends: most different climbs sent at a place (top 3 places; ties share a place).
create or replace function public.legends_most_sends(p_place uuid)
returns table (place smallint, user_id uuid, score integer, detail text)
language sql stable set search_path = '' as $$
  with sends as (
    select author_id, coalesce(climb_key, 'post:' || id) as k
      from public.posts
     where place_id = p_place and deleted_at is null and send_style not in ('link', 'other')
  ),
  scores as (
    select author_id, count(distinct k)::integer as score, count(*)::integer as videos
      from sends group by author_id
  ),
  ranked as (select s.*, dense_rank() over (order by s.score desc) as r from scores s)
  select r::smallint, author_id, score,
         videos || case when videos = 1 then ' video' else ' videos' end
    from ranked where r <= 3
   order by r, author_id
$$;

-- Legends: hardest send of one discipline at a place, by each climb's community grade
-- (guidebook grade until someone proposes one), compared on the discipline's common scale.
create or replace function public.legends_hardest(p_place uuid, p_discipline public.discipline)
returns table (place smallint, user_id uuid, grade text, climb_name text)
language sql stable set search_path = '' as $$
  with sends as (
    select p.author_id,
           coalesce(c.name, nullif(p.route_name, ''), 'Unnamed route') as climb_name,
           coalesce(cg.system, c.grade_system) as system,
           coalesce(cg.value, c.grade_value) as value
      from public.posts p
      left join public.climbs c on c.id = p.climb_id
      left join public.climb_grades cg on cg.climb_key = p.climb_key
     where p.place_id = p_place and p.discipline = p_discipline
       and p.deleted_at is null and p.send_style not in ('link', 'other')
  ),
  comparable as (
    select s.author_id, s.climb_name, g.comparable_system as csys, g.comparable_rank as crank
      from sends s join public.grades g on g.system = s.system and g.value = s.value
     where g.comparable_rank is not null
  ),
  dominant as (
    select csys from comparable group by csys order by count(*) desc, csys limit 1
  ),
  best as (
    select distinct on (author_id) author_id, crank, climb_name
      from comparable where csys = (select csys from dominant)
     order by author_id, crank desc
  ),
  ranked as (select b.*, dense_rank() over (order by b.crank desc) as r from best b)
  select r.r::smallint, r.author_id, g.value, r.climb_name
    from ranked r
    join public.grades g on g.system = (select csys from dominant) and g.rank = r.crank
   where r.r <= 3
   order by r.r, r.author_id
$$;

-- ---------------------------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------------------------

alter table public.grades              enable row level security;
alter table public.profiles            enable row level security;
alter table public.places              enable row level security;
alter table public.profile_home_places enable row level security;
alter table public.climbs              enable row level security;
alter table public.posts               enable row level security;
alter table public.climb_grade_votes   enable row level security;
alter table public.post_likes          enable row level security;
alter table public.comments            enable row level security;
alter table public.reposts             enable row level security;
alter table public.user_follows        enable row level security;
alter table public.place_follows       enable row level security;
alter table public.projects            enable row level security;
alter table public.post_view_dedupe    enable row level security;   -- no policies: RPC only
alter table public.community_photos    enable row level security;
alter table public.photo_likes         enable row level security;
alter table public.reports             enable row level security;
alter table public.user_blocks         enable row level security;

-- Public reads.
create policy "grades are public"        on public.grades            for select using (true);
create policy "profiles are public"      on public.profiles          for select using (true);
create policy "places are public"        on public.places            for select using (true);
create policy "home places are public"   on public.profile_home_places for select using (true);
create policy "climbs are public"        on public.climbs            for select using (true);
create policy "grade votes are public"   on public.climb_grade_votes for select using (true);
create policy "live posts are public"    on public.posts             for select
  using (deleted_at is null and (video_status = 'ready' or author_id = auth.uid()));
create policy "likes are public"         on public.post_likes        for select using (true);
create policy "comments are public"      on public.comments          for select using (true);
create policy "reposts are public"       on public.reposts           for select using (true);
create policy "follows are public"       on public.user_follows      for select using (true);
create policy "place follows are public" on public.place_follows     for select using (true);
create policy "photos are public"        on public.community_photos  for select using (true);
create policy "photo likes are public"   on public.photo_likes       for select using (true);
-- Projects: visible to their owner always, to others only if the owner shows them.
create policy "projects visible per setting" on public.projects for select
  using (user_id = auth.uid()
         or exists (select 1 from public.profiles p where p.id = user_id and p.shows_projects));

-- Writes: only your own rows.
create policy "create own profile"  on public.profiles for insert with check (id = auth.uid());
create policy "update own profile"  on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

create policy "manage own home places" on public.profile_home_places for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "add places"  on public.places for insert to authenticated
  with check (created_by = auth.uid() and is_verified = false and source = 'userSubmitted');
create policy "add climbs"  on public.climbs for insert to authenticated
  with check (created_by = auth.uid() and is_verified = false);

create policy "create own posts" on public.posts for insert to authenticated with check (author_id = auth.uid());
create policy "edit own posts"   on public.posts for update to authenticated
  using (author_id = auth.uid()) with check (author_id = auth.uid());

create policy "like as yourself"     on public.post_likes    for insert to authenticated with check (user_id = auth.uid());
create policy "unlike your likes"    on public.post_likes    for delete to authenticated using (user_id = auth.uid());
create policy "comment as yourself"  on public.comments      for insert to authenticated with check (author_id = auth.uid());
create policy "delete own comments"  on public.comments      for delete to authenticated using (author_id = auth.uid());
create policy "repost as yourself"   on public.reposts       for insert to authenticated with check (user_id = auth.uid());
create policy "undo own reposts"     on public.reposts       for delete to authenticated using (user_id = auth.uid());
create policy "follow as yourself"   on public.user_follows  for insert to authenticated with check (follower_id = auth.uid());
create policy "unfollow"             on public.user_follows  for delete to authenticated using (follower_id = auth.uid());
create policy "follow places"        on public.place_follows for insert to authenticated with check (user_id = auth.uid());
create policy "unfollow places"      on public.place_follows for delete to authenticated using (user_id = auth.uid());
create policy "add own projects"     on public.projects      for insert to authenticated with check (user_id = auth.uid());
create policy "remove own projects"  on public.projects      for delete to authenticated using (user_id = auth.uid());
create policy "add photos"           on public.community_photos for insert to authenticated with check (author_id = auth.uid());
-- Only the person who added a photo can delete it.
create policy "delete own photos"    on public.community_photos for delete to authenticated using (author_id = auth.uid());
create policy "like photos"          on public.photo_likes   for insert to authenticated with check (user_id = auth.uid());
create policy "unlike photos"        on public.photo_likes   for delete to authenticated using (user_id = auth.uid());
create policy "report as yourself"   on public.reports       for insert to authenticated with check (reporter_id = auth.uid());
create policy "see own reports"      on public.reports       for select to authenticated using (reporter_id = auth.uid());
create policy "manage own blocks"    on public.user_blocks   for all to authenticated
  using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

-- Column privileges: clients can never write counters, verification or video processing
-- fields (triggers and server functions do). RLS decides which rows; these decide which columns.
revoke insert, update on public.profiles from anon, authenticated;
grant insert (id, username, display_name, bio, avatar_path, boulder_system, boulder_low, boulder_high,
              rope_system, rope_low, rope_high, shows_grade_range, shows_hardest_send, shows_projects)
  on public.profiles to authenticated;
grant update (username, display_name, bio, avatar_path, boulder_system, boulder_low, boulder_high,
              rope_system, rope_low, rope_high, shows_grade_range, shows_hardest_send, shows_projects)
  on public.profiles to authenticated;

revoke insert, update on public.posts from anon, authenticated;
grant insert (author_id, place_id, climb_id, route_name, discipline, send_style,
              proposed_grade_system, proposed_grade_value, caption)
  on public.posts to authenticated;
grant update (caption) on public.posts to authenticated;   -- edit the caption; delete via delete_post()

revoke insert, update on public.places from anon, authenticated;
grant insert (name, kind, city, region, country, latitude, longitude, disciplines, about, source,
              is_verified, created_by)
  on public.places to authenticated;

revoke insert, update on public.climbs from anon, authenticated;
grant insert (place_id, name, area, discipline, grade_system, grade_value, about, is_verified, created_by)
  on public.climbs to authenticated;

revoke insert, update on public.community_photos from anon, authenticated;
grant insert (place_id, climb_id, author_id, storage_path, width, height)
  on public.community_photos to authenticated;

revoke all on public.climb_grade_votes from anon, authenticated;
grant select on public.climb_grade_votes to anon, authenticated;
revoke all on public.post_view_dedupe from anon, authenticated;

grant execute on function public.record_view(uuid) to authenticated;
grant execute on function public.delete_post(uuid) to authenticated;
grant execute on function public.home_feed(timestamptz, uuid, integer) to authenticated;
grant execute on function public.search_places(text, public.place_kind, integer) to anon, authenticated;
grant execute on function public.search_climbs(text, uuid, integer) to anon, authenticated;
grant execute on function public.search_profiles(text, integer) to anon, authenticated;
grant execute on function public.places_in_box(double precision, double precision, double precision, double precision, integer) to anon, authenticated;
grant execute on function public.legends_most_sends(uuid) to anon, authenticated;
grant execute on function public.legends_hardest(uuid, public.discipline) to anon, authenticated;
