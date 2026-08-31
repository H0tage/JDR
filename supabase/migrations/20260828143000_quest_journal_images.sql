-- Images insérées directement dans le Journal de quête.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'quest-journal-images',
  'quest-journal-images',
  true,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
set public = true,
    file_size_limit = 8388608,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

create or replace function public.is_public_quest_journal_image_path(object_name text)
returns boolean
language sql
stable
as $$
  select object_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.[a-z0-9]+$';
$$;

revoke all on function public.is_public_quest_journal_image_path(text) from public;
grant execute on function public.is_public_quest_journal_image_path(text) to anon, authenticated;

drop policy if exists quest_journal_images_public_read on storage.objects;
create policy quest_journal_images_public_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'quest-journal-images');

drop policy if exists quest_journal_images_public_insert on storage.objects;
create policy quest_journal_images_public_insert on storage.objects
  for insert to anon, authenticated
  with check (
    bucket_id = 'quest-journal-images'
    and public.is_public_quest_journal_image_path(name)
  );

drop policy if exists quest_journal_images_public_update on storage.objects;
create policy quest_journal_images_public_update on storage.objects
  for update to anon, authenticated
  using (
    bucket_id = 'quest-journal-images'
    and public.is_public_quest_journal_image_path(name)
  )
  with check (
    bucket_id = 'quest-journal-images'
    and public.is_public_quest_journal_image_path(name)
  );

drop policy if exists quest_journal_images_public_delete on storage.objects;
create policy quest_journal_images_public_delete on storage.objects
  for delete to anon, authenticated
  using (
    bucket_id = 'quest-journal-images'
    and public.is_public_quest_journal_image_path(name)
  );
