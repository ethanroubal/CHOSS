-- The app picks each community photo's id itself (it's also the file name in Storage), but the
-- insert grant didn't include the id column, so adding a photo failed with "permission denied".
grant insert (id, place_id, climb_id, author_id, storage_path, width, height)
  on public.community_photos to authenticated;
