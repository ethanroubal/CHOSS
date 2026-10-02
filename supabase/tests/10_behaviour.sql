\set ON_ERROR_STOP 1
-- Two users.
insert into auth.users (id) values ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b');
create temp table ids as select
  '00000000-0000-0000-0000-00000000000a'::uuid as alex,
  '00000000-0000-0000-0000-00000000000b'::uuid as sam,
  (select id from places where external_id = 'p_crag_yosemite_national_park_33f84b') as yosemite;
grant select on ids to authenticated;

-- Act as Alex.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
insert into profiles (id, username, display_name) values ((select alex from ids), 'alexcrimps', 'Alex Chen');
insert into climbs (place_id, name, area, discipline, grade_system, grade_value, created_by)
  values ((select yosemite from ids), 'Midnight Lightning', 'Camp 4', 'boulder', 'vScale', 'V8', (select alex from ids));
insert into posts (author_id, place_id, climb_id, discipline, send_style, proposed_grade_system, proposed_grade_value, caption)
  select alex, yosemite, (select id from climbs where name = 'Midnight Lightning' and created_by is not null), 'boulder', 'redpoint', 'vScale', 'V8', 'sent!' from ids;
reset role;
update posts set video_status = 'ready';   -- what the Mux webhook does

-- Act as Sam: profile, follow, like, view, propose a grade, try to cheat.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
insert into profiles (id, username, display_name) values ((select sam from ids), 'sam.sends', 'Sam Rivera');
insert into place_follows (user_id, place_id) select sam, yosemite from ids;
insert into user_follows (follower_id, followee_id) select sam, alex from ids;
insert into post_likes (post_id, user_id) select id, (select sam from ids) from posts;
select record_view(id) from posts;
select record_view(id) from posts;   -- straight away again: counted once
insert into posts (author_id, place_id, climb_id, discipline, send_style, proposed_grade_system, proposed_grade_value)
  select sam, yosemite, (select id from climbs where name = 'Midnight Lightning' and created_by is not null), 'boulder', 'flash', 'font', '7B+' from ids;
do $$ begin
  begin update posts set like_count = 999; raise exception 'CHEAT WORKED: like_count';
  exception when insufficient_privilege then raise notice 'ok: clients cannot write counters'; end;
  begin insert into post_likes (post_id, user_id) select id, (select alex from ids) from posts limit 1;
        raise exception 'CHEAT WORKED: liked as someone else';
  exception when insufficient_privilege or check_violation then raise notice 'ok: cannot like as someone else'; end;
end $$;
reset role;
update posts set video_status = 'ready';

select 'post counters' as check, like_count, view_count from posts where caption = 'sent!';
select 'follow counters', (select follower_count from profiles where username = 'alexcrimps') as alex_followers,
       (select follower_count from places where id = (select yosemite from ids)) as yosemite_followers,
       (select post_count from places where id = (select yosemite from ids)) as yosemite_posts;
select 'community grade' as check, * from climb_grades;

-- Sam's feed and Legends.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select 'feed' as check, reason, count(*) from home_feed() group by reason order by reason;
select 'most sends' as check, place, (select username from profiles where id = user_id), score, detail from legends_most_sends((select yosemite from ids));
select 'hardest boulder' as check, place, (select username from profiles where id = user_id), grade, climb_name from legends_hardest((select yosemite from ids), 'boulder');

-- Search: typos and towns.
select 'search yosmite' as check, name from search_places('yosmite', null, 3);
select 'search brooklyn gyms' as check, name, city from search_places('brooklyn', 'gym', 3);
select 'search climb' as check, name from search_climbs('midnite lightning', null, 3);
select 'search people' as check, username from search_profiles('alx', 3);
select 'map box' as check, count(*) from places_in_box(37.5, -120, 38, -119.3);

-- Photos: Sam adds one, Alex can't delete it; likes pick the cover.
-- With an id, like the app (it names the file after it).
insert into community_photos (id, place_id, author_id, storage_path) select gen_random_uuid(), yosemite, sam, 'x/1.jpg' from ids;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
insert into community_photos (place_id, author_id, storage_path) select yosemite, alex, 'x/2.jpg' from ids;
delete from community_photos where storage_path = 'x/1.jpg';   -- not Alex's: nothing deleted
select 'photos after alex delete attempt' as check, count(*) from community_photos;
insert into photo_likes (photo_id, user_id) select id, (select alex from ids) from community_photos where storage_path = 'x/1.jpg';
reset role;
select 'cover is most liked' as check, (select storage_path from community_photos where id = cover_photo_id) from places where id = (select yosemite from ids);

-- The imported outdoor climbs (supabase/seeds) all landed at their crags.
select 'imported climbs' as check, count(*) as climbs, count(distinct place_id) as crags,
       count(*) filter (where grade_value is not null) as graded,
       count(*) filter (where latitude is not null) as located
  from climbs where created_by is null;

-- Comments on a crag's page and a climb's page.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
insert into page_comments (place_id, author_id, body) select yosemite, alex, 'Valley is dry this week' from ids;
insert into page_comments (climb_id, author_id, body)
  select (select id from climbs where name = 'Midnight Lightning' and created_by is not null), alex, 'Bring two pads' from ids;
do $$ begin
  begin insert into page_comments (place_id, author_id, body)
          select yosemite, sam, 'pretending to be Sam' from ids;
        raise exception 'CHEAT WORKED: page comment as someone else';
  exception when insufficient_privilege then raise notice 'ok: cannot comment as someone else'; end;
  begin insert into page_comments (author_id, body) select alex, 'on no page' from ids;
        raise exception 'BROKEN: page comment without a page';
  exception when check_violation then raise notice 'ok: a page comment needs a page'; end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
delete from page_comments;   -- Sam can't delete Alex's comments (RLS: no rows match)
select 'page comments after sam delete' as check, count(*) from page_comments;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
delete from page_comments where climb_id is not null;
select 'page comments after alex deletes one' as check, count(*) from page_comments;
reset role;

-- A link or "other" post can't propose a grade.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
do $$ begin
  begin insert into posts (author_id, place_id, discipline, send_style, proposed_grade_system, proposed_grade_value)
          select alex, yosemite, 'boulder', 'link', 'vScale', 'V9' from ids;
        raise exception 'BROKEN: graded a link';
  exception when check_violation then raise notice 'ok: links cannot propose a grade'; end;
end $$;
insert into posts (author_id, place_id, discipline, send_style) select alex, yosemite, 'boulder', 'other' from ids;
reset role;

-- Rewatching counts again once 10 seconds have passed.
update post_view_last set viewed_at = now() - interval '1 minute';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select 'rewatch counts' as check, record_view(id) as views from posts where caption = 'sent!';
select 'immediate rewatch ignored' as check, record_view(id) as views from posts where caption = 'sent!';
reset role;

-- Watching your own video counts too.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select 'own view counts' as check, record_view(id) as views from posts where caption = 'sent!';
reset role;
