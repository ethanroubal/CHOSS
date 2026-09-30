-- Storage buckets for pictures (videos go to Mux). Served through Supabase's CDN; the app asks
-- for resized versions (e.g. ?width=400) with Supabase image transformations.
--
-- Files live under a folder named after the uploader's user id, e.g.
--   community-photos/<user id>/<uuid>.jpg
-- so the rules below can check ownership from the path.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5 * 1024 * 1024, array['image/jpeg', 'image/png', 'image/heic']),
  ('community-photos', 'community-photos', true, 10 * 1024 * 1024, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;

create policy "pictures are public"
  on storage.objects for select
  using (bucket_id in ('avatars', 'community-photos'));

create policy "upload into your own folder"
  on storage.objects for insert to authenticated
  with check (bucket_id in ('avatars', 'community-photos')
              and (storage.foldername(name))[1] = auth.uid()::text);

create policy "replace your own files"
  on storage.objects for update to authenticated
  using (bucket_id in ('avatars', 'community-photos')
         and (storage.foldername(name))[1] = auth.uid()::text);

-- Only the uploader can delete a picture.
create policy "delete your own files"
  on storage.objects for delete to authenticated
  using (bucket_id in ('avatars', 'community-photos')
         and (storage.foldername(name))[1] = auth.uid()::text);
