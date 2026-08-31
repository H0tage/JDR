-- Identité explicite des contacts et vues conservant strictement les limites MJ/joueurs.
-- Les deux nouveaux champs sont ajoutés à la fin des vues existantes pour ne pas
-- renommer de colonnes : PostgreSQL l'interdit avec CREATE OR REPLACE VIEW.

alter table public.contacts
  add column if not exists first_name text,
  add column if not exists last_name text;

update public.contacts
set
  first_name = coalesce(first_name, nullif(split_part(btrim(name), ' ', 1), '')),
  last_name = coalesce(
    last_name,
    nullif(btrim(substr(btrim(name), length(split_part(btrim(name), ' ', 1)) + 1)), '')
  )
where first_name is null or last_name is null;

-- Cette vue est réservée au MJ. Les notes des joueurs lui restent visibles,
-- mais les notes privées du MJ n'apparaissent jamais dans player_contacts.
-- Les portraits ont ajouté des colonnes après la création initiale de la vue.
-- Il faut donc la recréer : CREATE OR REPLACE ne permet pas d’insérer des
-- colonnes avant celles qui existent déjà.
drop view if exists public.gm_contacts;
create or replace view public.gm_contacts
with (security_invoker = true)
as
select
  ct.id,
  ct.campaign_id,
  ct.faction_id,
  ct.name,
  ct.role,
  ct.state,
  ct.attitude,
  ct.promise_debt,
  ct.due_text,
  ct.gm_notes,
  ct.next_consequence,
  ct.visibility,
  ct.is_primary,
  ct.created_at,
  ct.updated_at,
  ct.public_description,
  ct.image_path,
  ct.avatar_x,
  ct.avatar_y,
  ct.avatar_zoom,
  f.short_name as faction_name,
  f.sort_order as faction_sort_order,
  pn.character_notes as player_character_notes,
  pn.debt_notes as player_debt_notes,
  pn.notes as player_notes,
  ct.first_name,
  ct.last_name
from public.contacts ct
join public.factions f on f.id = ct.faction_id
left join public.contact_player_notes pn on pn.contact_id = ct.id;

grant select on public.gm_contacts to authenticated;

-- Côté joueurs : description, image, attitude, statut et notes partagées
-- seulement. gm_notes n'est volontairement pas sélectionnée ici.
create or replace view public.player_contacts
with (security_barrier = true)
as
select
  ct.id,
  ct.campaign_id,
  ct.faction_id,
  f.short_name as faction_name,
  ct.name,
  ct.role,
  ct.state,
  ct.attitude,
  ct.promise_debt,
  ct.due_text,
  ct.visibility,
  ct.is_primary,
  pn.character_notes as player_character_notes,
  pn.debt_notes as player_debt_notes,
  pn.notes as player_notes,
  ct.public_description,
  ct.image_path,
  ct.avatar_x,
  ct.avatar_y,
  ct.avatar_zoom,
  ct.first_name,
  ct.last_name
from public.contacts ct
join public.factions f on f.id = ct.faction_id
join public.campaign_factions cf
  on cf.campaign_id = ct.campaign_id
  and cf.faction_id = ct.faction_id
  and cf.is_player_visible
join public.campaigns c on c.id = ct.campaign_id and c.public_enabled
left join public.contact_player_notes pn on pn.contact_id = ct.id
where ct.visibility = 'players';
