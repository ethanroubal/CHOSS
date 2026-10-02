-- A link (part of a climb) or an "other" post isn't a send of the whole climb, so it can't
-- propose a grade for it. Clear any existing ones (the grade-vote trigger takes them back out
-- of the community grade), then make the database refuse new ones.
update public.posts
   set proposed_grade_system = null, proposed_grade_value = null
 where send_style in ('link', 'other') and proposed_grade_system is not null;

alter table public.posts drop constraint if exists posts_grade_only_for_sends;
alter table public.posts add constraint posts_grade_only_for_sends
  check (send_style not in ('link', 'other') or (proposed_grade_system is null and proposed_grade_value is null));
