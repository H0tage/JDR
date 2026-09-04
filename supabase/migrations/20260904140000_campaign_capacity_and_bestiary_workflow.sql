-- Nom conseillé dans le SQL Editor : Capacité des campagnes et bestiaire collaboratif — 2026-09-04
-- Limite les campagnes à 1–7 participants (MJ compris) et sécurise le
-- cycle de création, modification, révélation et suppression des créatures.

alter table public.campaigns
  add column if not exists max_participants smallint not null default 7
    check (max_participants between 1 and 7);

-- Une suppression complète du compte efface bien sa page personnelle. Les
-- créatures et événements, eux, conservent leur existence avec un auteur nul.
alter table public.player_pages drop constraint if exists player_pages_user_id_fkey;
alter table public.player_pages
  add constraint player_pages_user_id_fkey foreign key (user_id)
  references auth.users(id) on delete cascade;

alter table public.bestiary_entries
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists is_visible boolean not null default true,
  add column if not exists revealed_at timestamptz;

update public.bestiary_entries
set revealed_at = coalesce(revealed_at, created_at)
where is_visible and revealed_at is null;

create index if not exists bestiary_entries_campaign_visibility_order_idx
  on public.bestiary_entries (campaign_id, is_visible, revealed_at, created_at);

create table if not exists public.bestiary_events (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  entry_id uuid,
  creature_name text not null,
  event_type text not null check (event_type in ('created', 'updated', 'revealed', 'hidden', 'deleted')),
  actor_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists bestiary_events_campaign_date_idx
  on public.bestiary_events (campaign_id, created_at desc);

alter table public.bestiary_events enable row level security;
revoke all on table public.bestiary_events from public, anon, authenticated;
grant select on table public.bestiary_events to authenticated;

drop policy if exists bestiary_events_gm_read on public.bestiary_events;
create policy bestiary_events_gm_read on public.bestiary_events
for select to authenticated
using (public.is_campaign_gm(campaign_id));

-- La table n'est plus modifiable directement : les fonctions ci-dessous
-- appliquent les droits par rôle et inscrivent chaque action dans l'historique.
drop policy if exists bestiary_entries_public_manage on public.bestiary_entries;
drop policy if exists bestiary_entries_member_read on public.bestiary_entries;
revoke insert, update, delete on table public.bestiary_entries from anon, authenticated;
grant select on table public.bestiary_entries to authenticated;

create policy bestiary_entries_member_read on public.bestiary_entries
for select to authenticated
using (
  public.is_campaign_member(campaign_id)
  and (is_visible or public.is_campaign_gm(campaign_id))
);

create or replace function public.get_campaign_capacity(p_campaign_id uuid)
returns table(max_participants smallint, current_participants bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_campaign_member(p_campaign_id) then raise exception 'Accès refusé'; end if;
  return query
  select campaign.max_participants, count(member.user_id)
  from public.campaigns campaign
  left join public.campaign_members member on member.campaign_id = campaign.id
  where campaign.id = p_campaign_id
  group by campaign.id, campaign.max_participants;
end;
$$;

create or replace function public.update_campaign_capacity(p_campaign_id uuid, p_max_participants integer)
returns smallint
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_count integer;
  saved_capacity smallint;
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if p_max_participants not between 1 and 7 then
    raise exception 'La capacité doit être comprise entre 1 et 7 participants';
  end if;
  select count(*) into current_count from public.campaign_members where campaign_id = p_campaign_id;
  if p_max_participants < current_count then
    raise exception 'La capacité ne peut pas être inférieure au nombre actuel de participants';
  end if;
  update public.campaigns set max_participants = p_max_participants
  where id = p_campaign_id
  returning max_participants into saved_capacity;
  return saved_capacity;
end;
$$;

-- Le verrou sur la campagne sérialise deux acceptations simultanées : la
-- capacité ne peut donc pas être dépassée entre le contrôle et l'insertion.
create or replace function public.accept_campaign_invitation(p_token uuid)
returns table(campaign_id uuid, campaign_name text, role text, already_member boolean)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  invite public.campaign_invites%rowtype;
  campaign_name_value text;
  campaign_capacity smallint;
  member_count integer;
  exists_member boolean;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into invite from public.campaign_invites where token = p_token;
  if not found then raise exception 'Invitation invalide'; end if;
  if invite.revoked_at is not null then raise exception 'Invitation révoquée'; end if;
  if invite.expires_at is not null and invite.expires_at <= now() then raise exception 'Invitation expirée'; end if;

  select campaign.name, campaign.max_participants
  into campaign_name_value, campaign_capacity
  from public.campaigns campaign
  where campaign.id = invite.campaign_id
  for update;
  if not found then raise exception 'Campagne introuvable'; end if;

  select exists (
    select 1 from public.campaign_members member
    where member.campaign_id = invite.campaign_id and member.user_id = auth.uid()
  ) into exists_member;

  if not exists_member then
    select count(*) into member_count
    from public.campaign_members member
    where member.campaign_id = invite.campaign_id;
    if member_count >= campaign_capacity then
      raise exception 'La campagne que vous cherchez à rejoindre est pleine. Contactez votre MJ pour qu''il libère de la place, ou augmente la taille maximale de la campagne.';
    end if;
  end if;

  insert into public.user_profiles (user_id) values (auth.uid())
  on conflict on constraint user_profiles_pkey do nothing;
  insert into public.campaign_members (campaign_id, user_id, role)
  values (invite.campaign_id, auth.uid(), 'player')
  on conflict on constraint campaign_members_pkey do nothing;
  insert into public.player_pages (campaign_id, user_id)
  values (invite.campaign_id, auth.uid())
  on conflict on constraint player_pages_pkey do nothing;

  return query select invite.campaign_id, campaign_name_value, 'player'::text, exists_member;
end;
$$;

create or replace function public.list_campaign_bestiary(p_campaign_id uuid)
returns table(
  id uuid, campaign_id uuid, name text, resistances text, weaknesses text,
  notes text, image_path text, created_by uuid, is_visible boolean,
  revealed_at timestamptz, created_at timestamptz, updated_at timestamptz,
  creator_display_name text, can_edit boolean, can_delete boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare viewer_is_gm boolean;
begin
  if not public.is_campaign_member(p_campaign_id) then raise exception 'Accès refusé'; end if;
  viewer_is_gm := public.is_campaign_gm(p_campaign_id);
  return query
  select entry.id, entry.campaign_id, entry.name, entry.resistances,
    entry.weaknesses, entry.notes, entry.image_path, entry.created_by,
    entry.is_visible, entry.revealed_at, entry.created_at, entry.updated_at,
    case when entry.created_by is null then 'Joueur parti' else coalesce(profile.display_name, 'Sans pseudo') end,
    (viewer_is_gm or entry.created_by = auth.uid()), viewer_is_gm
  from public.bestiary_entries entry
  left join public.user_profiles profile on profile.user_id = entry.created_by
  where entry.campaign_id = p_campaign_id and (viewer_is_gm or entry.is_visible)
  order by entry.is_visible desc,
    case when entry.is_visible then entry.revealed_at end,
    entry.created_at, entry.id;
end;
$$;

create or replace function public.save_bestiary_entry(
  p_id uuid, p_campaign_id uuid, p_name text, p_resistances text default null,
  p_weaknesses text default null, p_notes text default null, p_image_path text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing public.bestiary_entries%rowtype;
  viewer_is_gm boolean;
  clean_name text := btrim(coalesce(p_name, ''));
  initial_visibility boolean;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if not public.is_campaign_member(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if clean_name = '' then raise exception 'Le nom de la créature est requis'; end if;
  viewer_is_gm := public.is_campaign_gm(p_campaign_id);
  select * into existing from public.bestiary_entries where id = p_id for update;

  if found then
    if existing.campaign_id <> p_campaign_id then raise exception 'Campagne invalide'; end if;
    if not viewer_is_gm and existing.created_by is distinct from auth.uid() then raise exception 'Vous ne pouvez modifier que vos propres créatures'; end if;
    update public.bestiary_entries
    set name = clean_name,
      resistances = nullif(btrim(coalesce(p_resistances, '')), ''),
      weaknesses = nullif(btrim(coalesce(p_weaknesses, '')), ''),
      notes = nullif(btrim(coalesce(p_notes, '')), ''), image_path = p_image_path
    where id = p_id;
    insert into public.bestiary_events (campaign_id, entry_id, creature_name, event_type, actor_user_id)
    values (p_campaign_id, p_id, clean_name, 'updated', auth.uid());
  else
    initial_visibility := not viewer_is_gm;
    insert into public.bestiary_entries (
      id, campaign_id, name, resistances, weaknesses, notes, image_path,
      created_by, is_visible, revealed_at
    ) values (
      p_id, p_campaign_id, clean_name,
      nullif(btrim(coalesce(p_resistances, '')), ''),
      nullif(btrim(coalesce(p_weaknesses, '')), ''),
      nullif(btrim(coalesce(p_notes, '')), ''), p_image_path,
      auth.uid(), initial_visibility, case when initial_visibility then now() else null end
    );
    insert into public.bestiary_events (campaign_id, entry_id, creature_name, event_type, actor_user_id)
    values (p_campaign_id, p_id, clean_name, 'created', auth.uid());
  end if;
end;
$$;

create or replace function public.set_bestiary_entry_visibility(p_entry_id uuid, p_visible boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare entry public.bestiary_entries%rowtype;
begin
  select * into entry from public.bestiary_entries where id = p_entry_id for update;
  if not found then raise exception 'Créature introuvable'; end if;
  if not public.is_campaign_gm(entry.campaign_id) then raise exception 'Accès refusé'; end if;
  if entry.is_visible = p_visible then return; end if;
  update public.bestiary_entries
  set is_visible = p_visible, revealed_at = case when p_visible then now() else revealed_at end
  where id = p_entry_id;
  insert into public.bestiary_events (campaign_id, entry_id, creature_name, event_type, actor_user_id)
  values (entry.campaign_id, entry.id, entry.name, case when p_visible then 'revealed' else 'hidden' end, auth.uid());
end;
$$;

create or replace function public.delete_bestiary_entry(p_entry_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare entry public.bestiary_entries%rowtype;
begin
  select * into entry from public.bestiary_entries where id = p_entry_id for update;
  if not found then raise exception 'Créature introuvable'; end if;
  if not public.is_campaign_gm(entry.campaign_id) then raise exception 'Accès refusé'; end if;
  insert into public.bestiary_events (campaign_id, entry_id, creature_name, event_type, actor_user_id)
  values (entry.campaign_id, entry.id, entry.name, 'deleted', auth.uid());
  delete from public.bestiary_entries where id = p_entry_id;
  return entry.image_path;
end;
$$;

create or replace view public.gm_bestiary_history
with (security_barrier = true)
as
select event.id, event.campaign_id, event.entry_id, event.creature_name,
  event.event_type,
  case
    when event.actor_user_id is null then 'Joueur parti'
    when member.role = 'gm' then 'Le Maître du Jeu'
    else coalesce(profile.display_name, 'Sans pseudo')
  end as actor_display_name,
  event.created_at
from public.bestiary_events event
left join public.campaign_members member
  on member.campaign_id = event.campaign_id and member.user_id = event.actor_user_id
left join public.user_profiles profile on profile.user_id = event.actor_user_id
where public.is_campaign_gm(event.campaign_id);

revoke all on function public.get_campaign_capacity(uuid) from public, anon, authenticated;
revoke all on function public.update_campaign_capacity(uuid, integer) from public, anon, authenticated;
revoke all on function public.list_campaign_bestiary(uuid) from public, anon, authenticated;
revoke all on function public.save_bestiary_entry(uuid, uuid, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.set_bestiary_entry_visibility(uuid, boolean) from public, anon, authenticated;
revoke all on function public.delete_bestiary_entry(uuid) from public, anon, authenticated;
grant execute on function public.get_campaign_capacity(uuid) to authenticated;
grant execute on function public.update_campaign_capacity(uuid, integer) to authenticated;
grant execute on function public.list_campaign_bestiary(uuid) to authenticated;
grant execute on function public.save_bestiary_entry(uuid, uuid, text, text, text, text, text) to authenticated;
grant execute on function public.set_bestiary_entry_visibility(uuid, boolean) to authenticated;
grant execute on function public.delete_bestiary_entry(uuid) to authenticated;
revoke all on table public.gm_bestiary_history from public, anon, authenticated;
grant select on table public.gm_bestiary_history to authenticated;
