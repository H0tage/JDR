-- Durcit le cycle de vie des campagnes après l'audit complet.
--
-- Les anciennes politiques Storage dataient de la démo publique : toute
-- personne, même anonyme, pouvait créer, remplacer ou supprimer une image si
-- elle connaissait un chemin valide. Les données applicatives sont désormais
-- réservées aux membres ; les fichiers doivent suivre la même frontière.

create or replace function public.is_campaign_member_storage_path(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when object_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.[a-z0-9]+$'
      then public.is_campaign_member((storage.foldername(object_name))[1]::uuid)
    else false
  end;
$$;

revoke all on function public.is_campaign_member_storage_path(text) from public, anon, authenticated;
grant execute on function public.is_campaign_member_storage_path(text) to authenticated;

drop policy if exists bestiary_images_public_insert on storage.objects;
drop policy if exists bestiary_images_public_update on storage.objects;
drop policy if exists bestiary_images_public_delete on storage.objects;
drop policy if exists bestiary_images_member_insert on storage.objects;
drop policy if exists bestiary_images_member_update on storage.objects;
drop policy if exists bestiary_images_member_delete on storage.objects;

create policy bestiary_images_member_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'bestiary-images'
    and public.is_campaign_member_storage_path(name)
  );

create policy bestiary_images_member_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'bestiary-images'
    and public.is_campaign_member_storage_path(name)
  )
  with check (
    bucket_id = 'bestiary-images'
    and public.is_campaign_member_storage_path(name)
  );

create policy bestiary_images_member_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'bestiary-images'
    and public.is_campaign_member_storage_path(name)
  );

drop policy if exists quest_journal_images_public_insert on storage.objects;
drop policy if exists quest_journal_images_public_update on storage.objects;
drop policy if exists quest_journal_images_public_delete on storage.objects;
drop policy if exists quest_journal_images_member_insert on storage.objects;
drop policy if exists quest_journal_images_member_update on storage.objects;
drop policy if exists quest_journal_images_member_delete on storage.objects;

create policy quest_journal_images_member_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'quest-journal-images'
    and public.is_campaign_member_storage_path(name)
  );

create policy quest_journal_images_member_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'quest-journal-images'
    and public.is_campaign_member_storage_path(name)
  )
  with check (
    bucket_id = 'quest-journal-images'
    and public.is_campaign_member_storage_path(name)
  );

create policy quest_journal_images_member_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'quest-journal-images'
    and public.is_campaign_member_storage_path(name)
  );

-- La fonction de notes de contacts avait été sécurisée manuellement sur la
-- production, sans que sa version finale soit présente dans les migrations.
-- On versionne ici sa frontière réelle : contact publié + membre actif.
create or replace function public.save_player_contact_notes(
  target_contact_id uuid,
  next_character_notes text,
  next_debt_notes text,
  next_notes text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_campaign_id uuid;
begin
  select ct.campaign_id into target_campaign_id
  from public.contacts ct
  join public.campaign_factions cf
    on cf.campaign_id = ct.campaign_id
    and cf.faction_id = ct.faction_id
    and cf.is_player_visible
  where ct.id = target_contact_id and ct.visibility = 'players';

  if target_campaign_id is null or not public.is_campaign_member(target_campaign_id) then
    raise exception 'Contact non disponible dans la vue des joueurs';
  end if;

  insert into public.contact_player_notes
    (contact_id, campaign_id, character_notes, debt_notes, notes)
  values (
    target_contact_id,
    target_campaign_id,
    nullif(btrim(next_character_notes), ''),
    nullif(btrim(next_debt_notes), ''),
    nullif(btrim(next_notes), '')
  )
  on conflict (contact_id) do update set
    character_notes = excluded.character_notes,
    debt_notes = excluded.debt_notes,
    notes = excluded.notes;
end;
$$;

-- Les privilèges par défaut historiques accordaient EXECUTE à anon lors de
-- chaque CREATE OR REPLACE. On fixe explicitement l'état final des fonctions
-- participant au cycle de vie ou aux écritures de campagne.
revoke all on function public.save_player_contact_notes(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.save_player_contact_notes(uuid, text, text, text) to authenticated;

revoke all on function public.save_quest_journal_page(uuid, integer, text) from public, anon, authenticated;
grant execute on function public.save_quest_journal_page(uuid, integer, text) to authenticated;

revoke all on function public.remove_campaign_player(uuid, uuid) from public, anon, authenticated;
grant execute on function public.remove_campaign_player(uuid, uuid) to authenticated;

revoke all on function public.revoke_campaign_invite(uuid) from public, anon, authenticated;
grant execute on function public.revoke_campaign_invite(uuid) to authenticated;

revoke all on function public.reset_campaign_reference_data(uuid, text) from public, anon, authenticated;
grant execute on function public.reset_campaign_reference_data(uuid, text) to authenticated;

revoke all on function public.resolve_reputation_milestone(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.resolve_reputation_milestone(uuid, text, text, jsonb) to authenticated;

revoke all on function public.set_loot_player_visibility(uuid, boolean, date) from public, anon, authenticated;
grant execute on function public.set_loot_player_visibility(uuid, boolean, date) to authenticated;

-- Fonction interne appelée par create_campaign/reset_campaign_reference_data.
-- Aucun navigateur ne doit pouvoir l'exécuter directement.
revoke all on function public.seed_campaign_reference_data(uuid, text) from public, anon, authenticated;
