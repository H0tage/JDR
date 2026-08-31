-- Portraits de personnages et présentation de « Ma page ».

alter table public.player_pages
  add column if not exists image_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'player-character-images', 'player-character-images', true, 8388608,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.is_own_player_character_image_path(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when object_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.[a-z0-9]+$'
      then auth.uid() is not null
        and (storage.foldername(object_name))[2] = auth.uid()::text
        and exists (
          select 1 from public.campaign_members member
          where member.campaign_id = (storage.foldername(object_name))[1]::uuid
            and member.user_id = auth.uid()
            and member.role = 'player'
        )
    else false
  end;
$$;

revoke all on function public.is_own_player_character_image_path(text) from public, anon, authenticated;
grant execute on function public.is_own_player_character_image_path(text) to authenticated;

drop policy if exists player_character_images_public_read on storage.objects;
drop policy if exists player_character_images_owner_insert on storage.objects;
drop policy if exists player_character_images_owner_update on storage.objects;
drop policy if exists player_character_images_owner_delete on storage.objects;

create policy player_character_images_public_read on storage.objects
  for select to anon, authenticated using (bucket_id = 'player-character-images');
create policy player_character_images_owner_insert on storage.objects
  for insert to authenticated with check (
    bucket_id = 'player-character-images' and public.is_own_player_character_image_path(name)
  );
create policy player_character_images_owner_update on storage.objects
  for update to authenticated using (
    bucket_id = 'player-character-images' and public.is_own_player_character_image_path(name)
  ) with check (
    bucket_id = 'player-character-images' and public.is_own_player_character_image_path(name)
  );
create policy player_character_images_owner_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'player-character-images' and public.is_own_player_character_image_path(name)
  );

drop function public.get_my_player_page(uuid);
create function public.get_my_player_page(p_campaign_id uuid)
returns table(campaign_id uuid, user_id uuid, display_name text, character_name text,
  character_summary text, pathbuilder_url text, notes text, objectives text,
  updated_at timestamptz, image_path text)
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id and member.user_id = auth.uid() and member.role = 'player')
  then raise exception 'Accès refusé'; end if;
  insert into public.user_profiles (user_id) values (auth.uid()) on conflict on constraint user_profiles_pkey do nothing;
  insert into public.player_pages (campaign_id, user_id) values (p_campaign_id, auth.uid()) on conflict on constraint player_pages_pkey do nothing;
  return query select page.campaign_id, page.user_id, profile.display_name,
    page.character_name, page.character_summary, page.pathbuilder_url, page.notes,
    page.objectives, page.updated_at, page.image_path
  from public.player_pages page join public.user_profiles profile on profile.user_id = page.user_id
  where page.campaign_id = p_campaign_id and page.user_id = auth.uid();
end;
$$;

drop function public.update_my_player_page(uuid, text, text, text, text, text);
create function public.update_my_player_page(p_campaign_id uuid, p_character_name text,
  p_character_summary text, p_pathbuilder_url text, p_notes text, p_objectives text,
  p_image_path text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id and member.user_id = auth.uid() and member.role = 'player')
  then raise exception 'Accès refusé'; end if;
  if nullif(btrim(coalesce(p_image_path, '')), '') is not null
    and p_image_path !~ ('^' || p_campaign_id::text || '/' || auth.uid()::text || '/[0-9a-f-]{36}\.[a-z0-9]+$')
  then raise exception 'Chemin de portrait invalide'; end if;
  update public.player_pages set
    character_name = nullif(btrim(coalesce(p_character_name, '')), ''),
    character_summary = nullif(btrim(coalesce(p_character_summary, '')), ''),
    pathbuilder_url = nullif(btrim(coalesce(p_pathbuilder_url, '')), ''),
    notes = nullif(btrim(coalesce(p_notes, '')), ''),
    objectives = nullif(btrim(coalesce(p_objectives, '')), ''),
    image_path = nullif(btrim(coalesce(p_image_path, '')), '')
  where campaign_id = p_campaign_id and user_id = auth.uid();
  if not found then raise exception 'Page joueur introuvable'; end if;
end;
$$;

-- Compatibilité avec les clients ouverts avant cette migration : ils peuvent
-- encore enregistrer les champs textuels sans effacer le portrait existant.
create function public.update_my_player_page(p_campaign_id uuid, p_character_name text,
  p_character_summary text, p_pathbuilder_url text, p_notes text, p_objectives text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  current_image_path text;
begin
  select page.image_path into current_image_path
  from public.player_pages page
  where page.campaign_id = p_campaign_id and page.user_id = auth.uid();
  perform public.update_my_player_page(p_campaign_id, p_character_name,
    p_character_summary, p_pathbuilder_url, p_notes, p_objectives,
    current_image_path);
end;
$$;

drop function public.list_campaign_player_pages(uuid);
create function public.list_campaign_player_pages(p_campaign_id uuid)
returns table(campaign_id uuid, user_id uuid, display_name text, active boolean,
  character_name text, character_summary text, pathbuilder_url text, notes text,
  objectives text, updated_at timestamptz, image_path text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'Accès refusé'; end if;
  return query select page.campaign_id, page.user_id, coalesce(profile.display_name, 'Sans pseudo'),
    (member.user_id is not null), page.character_name, page.character_summary,
    page.pathbuilder_url, page.notes, page.objectives, page.updated_at, page.image_path
  from public.player_pages page
  left join public.user_profiles profile on profile.user_id = page.user_id
  left join public.campaign_members member on member.campaign_id = page.campaign_id
    and member.user_id = page.user_id and member.role = 'player'
  where page.campaign_id = p_campaign_id
  order by member.user_id is null, lower(coalesce(profile.display_name, 'Sans pseudo'));
end;
$$;

revoke all on function public.get_my_player_page(uuid) from public, anon, authenticated;
grant execute on function public.get_my_player_page(uuid) to authenticated;
revoke all on function public.update_my_player_page(uuid, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.update_my_player_page(uuid, text, text, text, text, text, text) to authenticated;
revoke all on function public.update_my_player_page(uuid, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.update_my_player_page(uuid, text, text, text, text, text) to authenticated;
revoke all on function public.list_campaign_player_pages(uuid) from public, anon, authenticated;
grant execute on function public.list_campaign_player_pages(uuid) to authenticated;
