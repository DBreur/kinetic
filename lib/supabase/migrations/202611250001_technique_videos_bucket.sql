-- Kinetic: eigen video's bij technieken en combinaties. Privé-bucket
-- `technique-videos`; elke gebruiker kan alleen in zijn eigen map
-- (<user id>/...) lezen, uploaden en verwijderen. De app speelt video's af
-- via een tijdelijke (1 uur geldige) ondertekende link.
--
-- Eenmalig plakken in Supabase → SQL Editor en uitvoeren. Veilig om
-- opnieuw te draaien.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'technique-videos',
  'technique-videos',
  false,
  314572800, -- 300 MB
  array['video/mp4', 'video/quicktime', 'video/webm', 'video/3gpp', 'video/x-matroska']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Technique videos: read own" on storage.objects;
create policy "Technique videos: read own"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'technique-videos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Technique videos: upload own" on storage.objects;
create policy "Technique videos: upload own"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'technique-videos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Technique videos: update own" on storage.objects;
create policy "Technique videos: update own"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'technique-videos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Technique videos: delete own" on storage.objects;
create policy "Technique videos: delete own"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'technique-videos' and (storage.foldername(name))[1] = auth.uid()::text);
