-- Portraits et descriptions publiques des contacts.
-- Le MJ demeure le seul à modifier ces données ; les joueurs ne disposent
-- toujours que de leur espace de notes partagé.

alter table public.contacts
  add column if not exists public_description text,
  add column if not exists image_path text,
  add column if not exists avatar_x numeric not null default 50 check (avatar_x between 0 and 100),
  add column if not exists avatar_y numeric not null default 50 check (avatar_y between 0 and 100),
  add column if not exists avatar_zoom numeric not null default 1 check (avatar_zoom between 1 and 2.5);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'contact-portraits',
  'contact-portraits',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']::text[]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.is_gm_contact_portrait_path(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when object_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.[a-z0-9]+$'
      then public.is_campaign_gm((storage.foldername(object_name))[1]::uuid)
    else false
  end;
$$;

revoke all on function public.is_gm_contact_portrait_path(text) from public;
grant execute on function public.is_gm_contact_portrait_path(text) to authenticated;

drop policy if exists contact_portraits_public_read on storage.objects;
create policy contact_portraits_public_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'contact-portraits');

drop policy if exists contact_portraits_gm_insert on storage.objects;
create policy contact_portraits_gm_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'contact-portraits'
    and public.is_gm_contact_portrait_path(name)
  );

drop policy if exists contact_portraits_gm_update on storage.objects;
create policy contact_portraits_gm_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'contact-portraits'
    and public.is_gm_contact_portrait_path(name)
  )
  with check (
    bucket_id = 'contact-portraits'
    and public.is_gm_contact_portrait_path(name)
  );

drop policy if exists contact_portraits_gm_delete on storage.objects;
create policy contact_portraits_gm_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'contact-portraits'
    and public.is_gm_contact_portrait_path(name)
  );

create or replace view public.player_contacts
with (security_barrier = true)
as
select ct.id, ct.campaign_id, ct.faction_id, f.short_name as faction_name,
  ct.name, ct.role, ct.state, ct.attitude, ct.promise_debt, ct.due_text,
  ct.visibility, ct.is_primary,
  pn.character_notes as player_character_notes,
  pn.debt_notes as player_debt_notes,
  pn.notes as player_notes,
  -- Les colonnes ajoutées restent à la fin : PostgreSQL interdit de changer
  -- l’ordre des colonnes existantes avec CREATE OR REPLACE VIEW.
  ct.public_description, ct.image_path,
  ct.avatar_x, ct.avatar_y, ct.avatar_zoom
from public.contacts ct
join public.factions f on f.id = ct.faction_id
join public.campaign_factions cf
  on cf.campaign_id = ct.campaign_id
  and cf.faction_id = ct.faction_id
  and cf.is_player_visible
join public.campaigns c on c.id = ct.campaign_id and c.public_enabled
left join public.contact_player_notes pn on pn.contact_id = ct.id
where ct.visibility = 'players';
