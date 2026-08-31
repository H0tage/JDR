-- Bestiaire collaboratif : les utilisateurs de la vue publique peuvent le gérer
-- tant que la campagne reste publique. Les images sont conservées dans un
-- compartiment Supabase Storage distinct et limité à 5 Mo par fichier.

create table if not exists public.bestiary_entries (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  resistances text,
  weaknesses text,
  notes text,
  image_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists bestiary_entries_campaign_name_idx
  on public.bestiary_entries (campaign_id, name);

drop trigger if exists bestiary_entries_touch on public.bestiary_entries;
create trigger bestiary_entries_touch before update on public.bestiary_entries
  for each row execute function public.touch_updated_at();

create or replace function public.is_public_campaign(target_campaign_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.campaigns c
    where c.id = target_campaign_id and c.public_enabled
  );
$$;

revoke all on function public.is_public_campaign(uuid) from public;
grant execute on function public.is_public_campaign(uuid) to anon, authenticated;

create or replace function public.is_public_bestiary_path(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.campaigns c
    where c.public_enabled
      and c.id::text = (storage.foldername(object_name))[1]
  );
$$;

revoke all on function public.is_public_bestiary_path(text) from public;
grant execute on function public.is_public_bestiary_path(text) to anon, authenticated;

alter table public.bestiary_entries enable row level security;
grant select, insert, update, delete on public.bestiary_entries to anon, authenticated;

drop policy if exists bestiary_entries_public_manage on public.bestiary_entries;
create policy bestiary_entries_public_manage on public.bestiary_entries
  for all to anon, authenticated
  using (public.is_public_campaign(campaign_id))
  with check (public.is_public_campaign(campaign_id));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'bestiary-images',
  'bestiary-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']::text[]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists bestiary_images_public_read on storage.objects;
create policy bestiary_images_public_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'bestiary-images');

drop policy if exists bestiary_images_public_insert on storage.objects;
create policy bestiary_images_public_insert on storage.objects
  for insert to anon, authenticated
  with check (
    bucket_id = 'bestiary-images'
    and public.is_public_bestiary_path(name)
  );

drop policy if exists bestiary_images_public_update on storage.objects;
create policy bestiary_images_public_update on storage.objects
  for update to anon, authenticated
  using (
    bucket_id = 'bestiary-images'
    and public.is_public_bestiary_path(name)
  )
  with check (
    bucket_id = 'bestiary-images'
    and public.is_public_bestiary_path(name)
  );

drop policy if exists bestiary_images_public_delete on storage.objects;
create policy bestiary_images_public_delete on storage.objects
  for delete to anon, authenticated
  using (
    bucket_id = 'bestiary-images'
    and public.is_public_bestiary_path(name)
  );
