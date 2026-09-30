\set ON_ERROR_STOP 1
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false) \g /dev/null
delete from post_likes;
delete from user_follows;
select delete_post(id) from posts where author_id = '00000000-0000-0000-0000-00000000000b' \g /dev/null
do $$ begin perform delete_post(id) from posts where caption = 'sent!'; raise exception 'CHEAT WORKED: deleted someone else''s post'; exception when insufficient_privilege then raise notice 'ok: cannot delete someone else''s post'; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false) \g /dev/null
delete from photo_likes;
reset role;
select 'after undo' as check,
  (select like_count from posts where caption = 'sent!') as likes,
  (select follower_count from profiles where username = 'alexcrimps') as alex_followers,
  (select post_count from places where external_id = 'p_crag_yosemite_national_park_33f84b') as yosemite_posts,
  (select post_count from profiles where username = 'sam.sends') as sam_posts,
  (select sum(votes) from climb_grade_votes) as grade_votes,
  (select storage_path from community_photos c join places p on p.cover_photo_id = c.id
    where p.external_id = 'p_crag_yosemite_national_park_33f84b') as cover;
