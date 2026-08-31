-- Migration de rattrapage du portail multi-campagnes et du butin partagé.
--
-- Ces objets ont d’abord été créés manuellement dans le SQL Editor Supabase.
-- Cette migration les replace dans l’historique Git afin qu’une nouvelle base
-- puisse reconstruire le même schéma. Elle est volontairement réexécutable sur
-- la base actuelle : tables, index et colonnes utilisent IF NOT EXISTS, tandis
-- que fonctions, vues et politiques sont remises dans leur état attendu.

-- Une campagne peut désormais contenir un MJ et plusieurs joueurs.
alter table public.campaign_members
  drop constraint if exists campaign_members_role_check;
alter table public.campaign_members
  add constraint campaign_members_role_check check (role in ('gm', 'player'));

create or replace function public.is_campaign_member(target_campaign_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.campaign_members member
    where member.campaign_id = target_campaign_id
      and member.user_id = auth.uid()
  );
$$;

-- Le nom historique reste utilisé par plusieurs politiques, mais « public »
-- signifie maintenant « membre connecté de la campagne ».
create or replace function public.is_public_campaign(target_campaign_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_campaign_member(target_campaign_id);
$$;

create table if not exists public.campaign_invites (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  token uuid not null default gen_random_uuid() unique,
  role text not null default 'player' check (role = 'player'),
  expires_at timestamptz,
  revoked_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists campaign_invites_campaign_created_idx
  on public.campaign_invites(campaign_id, created_at desc);
create index if not exists campaign_invites_token_idx
  on public.campaign_invites(token);
alter table public.campaign_invites enable row level security;

alter table public.campaign_loot
  add column if not exists player_visible boolean not null default false;

create table if not exists public.loot_player_publications (
  loot_id uuid primary key references public.campaign_loot(id) on delete cascade,
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  published_on date not null,
  created_at timestamptz not null default now(),
  owner_status text not null default 'Non-attribué'
    check (owner_status in (
      'Non-attribué', 'Joueur1', 'Joueur2', 'Joueur3', 'Joueur4',
      'Vendu', 'Démonté', 'Consommé'
    ))
);
create index if not exists loot_player_publications_campaign_date_idx
  on public.loot_player_publications(campaign_id, published_on);
alter table public.loot_player_publications enable row level security;

create or replace function public.get_campaign_invitation(p_token uuid)
returns table(campaign_id uuid, campaign_name text, status text)
language sql
stable
security definer
set search_path = ''
as $$
  select invite.campaign_id, campaign.name,
    case
      when invite.revoked_at is not null then 'revoked'
      when invite.expires_at is not null and invite.expires_at <= now() then 'expired'
      else 'valid'
    end
  from public.campaign_invites invite
  join public.campaigns campaign on campaign.id = invite.campaign_id
  where invite.token = p_token;
$$;

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
  exists_member boolean;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;

  select * into invite from public.campaign_invites where token = p_token;
  if not found then raise exception 'Invitation invalide'; end if;
  if invite.revoked_at is not null then raise exception 'Invitation révoquée'; end if;
  if invite.expires_at is not null and invite.expires_at <= now() then
    raise exception 'Invitation expirée';
  end if;

  select name into campaign_name_value
  from public.campaigns
  where id = invite.campaign_id;
  select exists (
    select 1 from public.campaign_members member
    where member.campaign_id = invite.campaign_id
      and member.user_id = auth.uid()
  ) into exists_member;

  insert into public.campaign_members (campaign_id, user_id, role)
  values (invite.campaign_id, auth.uid(), 'player')
  on conflict (campaign_id, user_id) do nothing;

  return query
  select invite.campaign_id, campaign_name_value, 'player'::text, exists_member;
end;
$$;

create or replace function public.list_my_campaigns()
returns table(
  campaign_id uuid,
  slug text,
  name text,
  description text,
  role text,
  joined_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select campaign.id, campaign.slug, campaign.name, campaign.description,
    member.role, member.created_at
  from public.campaign_members member
  join public.campaigns campaign on campaign.id = member.campaign_id
  where member.user_id = auth.uid()
  order by lower(campaign.name), campaign.id;
$$;

create or replace function public.list_campaign_members(p_campaign_id uuid)
returns table(user_id uuid, email text, role text, joined_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_campaign_gm(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;

  return query
  select member.user_id, account.email, member.role, member.created_at
  from public.campaign_members member
  join auth.users account on account.id = member.user_id
  where member.campaign_id = p_campaign_id
  order by case member.role when 'gm' then 0 else 1 end, lower(account.email);
end;
$$;

create or replace function public.list_campaign_invites(p_campaign_id uuid)
returns table(
  id uuid,
  token uuid,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_campaign_gm(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;

  return query
  select invite.id, invite.token, invite.expires_at, invite.revoked_at,
    invite.created_at
  from public.campaign_invites invite
  where invite.campaign_id = p_campaign_id
  order by invite.created_at desc;
end;
$$;

create or replace function public.create_campaign_invite(
  p_campaign_id uuid,
  p_expires_at timestamptz default null
)
returns table(id uuid, token uuid, expires_at timestamptz, created_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_campaign_gm(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception 'La date d’expiration doit être dans le futur';
  end if;

  return query
  insert into public.campaign_invites (campaign_id, expires_at, created_by)
  values (p_campaign_id, p_expires_at, auth.uid())
  returning campaign_invites.id, campaign_invites.token,
    campaign_invites.expires_at, campaign_invites.created_at;
end;
$$;

create or replace function public.revoke_campaign_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_campaign_id uuid;
begin
  select invite.campaign_id into v_campaign_id
  from public.campaign_invites invite
  where invite.id = p_invite_id;

  if v_campaign_id is null then raise exception 'Invitation introuvable'; end if;
  if not public.is_campaign_gm(v_campaign_id) then raise exception 'Accès refusé'; end if;

  update public.campaign_invites
  set revoked_at = coalesce(revoked_at, now())
  where id = p_invite_id;
end;
$$;

create or replace function public.remove_campaign_player(
  p_campaign_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_campaign_gm(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;
  delete from public.campaign_members
  where campaign_id = p_campaign_id
    and user_id = p_user_id
    and role = 'player';
end;
$$;

create or replace function public.set_loot_player_visibility(
  p_loot_id uuid,
  p_visible boolean,
  p_published_on date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campaign_id uuid;
begin
  select campaign_id into v_campaign_id
  from public.campaign_loot
  where id = p_loot_id;

  if v_campaign_id is null then raise exception 'Butin introuvable'; end if;
  if not public.is_campaign_gm(v_campaign_id) then raise exception 'Accès refusé'; end if;

  update public.campaign_loot
  set player_visible = p_visible
  where id = p_loot_id;

  if p_visible then
    insert into public.loot_player_publications (loot_id, campaign_id, published_on)
    values (p_loot_id, v_campaign_id, coalesce(p_published_on, current_date))
    on conflict (loot_id) do nothing;
  end if;
end;
$$;

create or replace function public.set_player_loot_owner_status(
  p_loot_id uuid,
  p_owner_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_owner_status not in (
    'Non-attribué', 'Joueur1', 'Joueur2', 'Joueur3', 'Joueur4',
    'Vendu', 'Démonté', 'Consommé'
  ) then
    raise exception 'État de butin invalide';
  end if;

  update public.loot_player_publications publication
  set owner_status = p_owner_status
  from public.campaign_loot loot
  where publication.loot_id = p_loot_id
    and loot.id = p_loot_id
    and loot.player_visible
    and public.is_campaign_member(loot.campaign_id);
  if not found then raise exception 'Butin partagé introuvable'; end if;
end;
$$;

create or replace function public.set_player_loot_published_on(
  p_loot_id uuid,
  p_published_on date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_published_on is null then raise exception 'Date d’ajout obligatoire'; end if;

  update public.loot_player_publications publication
  set published_on = p_published_on
  from public.campaign_loot loot
  where publication.loot_id = p_loot_id
    and loot.id = p_loot_id
    and loot.player_visible
    and public.is_campaign_member(loot.campaign_id);
  if not found then raise exception 'Butin partagé introuvable'; end if;
end;
$$;

-- Toutes les vues joueurs vérifient l’appartenance à la campagne. Les vues
-- gardent leur ordre de colonnes historique pour rester compatibles avec l’API.
create or replace view public.player_campaign
with (security_barrier = true)
as
select c.id as campaign_id, c.slug, c.name, c.description,
  s.current_volume, s.jf_cap, s.minor_cost, s.moderate_cost, s.major_cost,
  s.liked_threshold, s.admired_threshold, s.revered_threshold,
  s.carters_major_threshold, s.tension_max, s.show_numeric_tension,
  s.player_display_mode
from public.campaigns c
join public.campaign_settings s on s.campaign_id = c.id
where public.is_campaign_member(c.id);

create or replace view public.player_contacts
with (security_barrier = true)
as
select ct.id, ct.campaign_id, ct.faction_id, f.short_name as faction_name,
  ct.name, ct.role, ct.state, ct.attitude, ct.promise_debt, ct.due_text,
  ct.visibility, ct.is_primary,
  pn.character_notes as player_character_notes,
  pn.debt_notes as player_debt_notes,
  pn.notes as player_notes,
  ct.public_description, ct.image_path, ct.avatar_x, ct.avatar_y,
  ct.avatar_zoom, ct.first_name, ct.last_name
from public.contacts ct
join public.factions f on f.id = ct.faction_id
join public.campaign_factions cf
  on cf.campaign_id = ct.campaign_id
  and cf.faction_id = ct.faction_id
  and cf.is_player_visible
left join public.contact_player_notes pn on pn.contact_id = ct.id
where ct.visibility = 'players'
  and public.is_campaign_member(ct.campaign_id);

create or replace view public.player_faction_overview
with (security_barrier = true)
as
with totals as (
  select cf.campaign_id, cf.faction_id,
    greatest(0, coalesce(sum(j.rp_delta), 0))::integer as rp_raw,
    greatest(0, coalesce(sum(j.jf_delta), 0))::integer as jf_raw,
    greatest(0, coalesce(sum(j.tension_delta), 0))::integer as tension_raw
  from public.campaign_factions cf
  left join public.journal_entries j
    on j.campaign_id = cf.campaign_id and j.faction_id = cf.faction_id
  group by cf.campaign_id, cf.faction_id
)
select cf.campaign_id, f.id as faction_id, f.slug, f.name, f.short_name,
  f.accent, f.domain, f.public_description, f.sort_order,
  cf.public_summary, cf.is_player_visible,
  totals.rp_raw as rp,
  least(s.jf_cap, totals.jf_raw) as jf,
  case when s.show_numeric_tension
    then least(s.tension_max, totals.tension_raw)
    else null::integer
  end as tension,
  case
    when totals.rp_raw >= s.revered_threshold then 'Révérés'
    when totals.rp_raw >= s.admired_threshold then 'Admirés'
    when totals.rp_raw >= s.liked_threshold then 'Appréciés'
    else 'Indifférents'
  end as status,
  case least(s.tension_max, totals.tension_raw)
    when 0 then 'Stable'
    when 1 then 'Signes de froid'
    when 2 then 'Relations tendues'
    when 3 then 'Accès limité'
    else 'Rupture'
  end as tension_label
from public.campaign_factions cf
join public.factions f on f.id = cf.faction_id
join public.campaign_settings s on s.campaign_id = cf.campaign_id
join totals on totals.campaign_id = cf.campaign_id
  and totals.faction_id = cf.faction_id
where cf.is_player_visible
  and public.is_campaign_member(cf.campaign_id);

create or replace view public.player_journal
with (security_barrier = true)
as
select j.id, j.campaign_id, j.faction_id, f.short_name as faction_name,
  j.occurred_on, j.volume, j.title, j.details, j.rp_delta, j.jf_delta,
  case when s.show_numeric_tension then j.tension_delta else null::integer end
    as tension_delta,
  j.visibility
from public.journal_entries j
join public.factions f on f.id = j.faction_id
join public.campaign_factions cf
  on cf.campaign_id = j.campaign_id
  and cf.faction_id = j.faction_id
  and cf.is_player_visible
join public.campaign_settings s on s.campaign_id = j.campaign_id
where j.visibility = 'players'
  and public.is_campaign_member(j.campaign_id);

create or replace view public.player_loot
with (security_barrier = true)
as
select loot.campaign_id, loot.sort_order, loot.original_name, loot.quantity,
  loot.unit_value, loot.location_name, loot.id as loot_id,
  publication.published_on, publication.owner_status
from public.campaign_loot loot
join public.loot_player_publications publication on publication.loot_id = loot.id
where loot.player_visible
  and public.is_campaign_member(loot.campaign_id);

create or replace view public.player_relationships
with (security_barrier = true)
as
select r.id, r.campaign_id, r.source_faction_id,
  fs.short_name as source_name, r.target_faction_id,
  ft.short_name as target_name,
  coalesce(nullif(btrim(r.headline_override), ''), r.headline) as headline,
  coalesce(nullif(btrim(r.detail_override), ''), r.detail) as detail,
  r.tone, r.visibility,
  fs.sort_order as source_sort_order, ft.sort_order as target_sort_order,
  coalesce(r.color_override,
    case
      when r.tone = 'hostility' then 'hostile'
      when r.tone in ('tension', 'unclear') then 'uncertain'
      else 'favorable'
    end
  ) as color
from public.faction_relationships r
join public.factions fs on fs.id = r.source_faction_id
join public.factions ft on ft.id = r.target_faction_id
join public.campaign_factions source_cf
  on source_cf.campaign_id = r.campaign_id
  and source_cf.faction_id = r.source_faction_id
  and source_cf.is_player_visible
join public.campaign_factions target_cf
  on target_cf.campaign_id = r.campaign_id
  and target_cf.faction_id = r.target_faction_id
  and target_cf.is_player_visible
where r.visibility = 'players'
  and public.is_campaign_member(r.campaign_id);

create or replace view public.player_services
with (security_barrier = true)
as
with totals as (
  select cf.campaign_id, cf.faction_id,
    greatest(0, coalesce(sum(j.rp_delta), 0))::integer as rp_raw,
    greatest(0, coalesce(sum(j.tension_delta), 0))::integer as tension_raw
  from public.campaign_factions cf
  left join public.journal_entries j
    on j.campaign_id = cf.campaign_id and j.faction_id = cf.faction_id
  group by cf.campaign_id, cf.faction_id
)
select s.id, s.campaign_id, s.faction_id, f.short_name as faction_name,
  s.scale, s.required_rp, s.base_cost, s.domain, s.examples, s.safeguard,
  s.frequency, s.player_visible, f.sort_order as faction_sort_order,
  case s.scale when 'Mineure' then 1 when 'Modérée' then 2 else 3 end
    as scale_sort
from public.services s
join public.factions f on f.id = s.faction_id
join public.campaign_factions cf
  on cf.campaign_id = s.campaign_id and cf.faction_id = s.faction_id
join totals on totals.campaign_id = s.campaign_id
  and totals.faction_id = s.faction_id
join public.campaign_settings settings on settings.campaign_id = s.campaign_id
where s.player_visible
  and cf.is_player_visible
  and totals.rp_raw >= s.required_rp
  and least(settings.tension_max, totals.tension_raw) < settings.tension_max
  and public.is_campaign_member(s.campaign_id);

-- Politiques d’appartenance et gestion des joueurs par le MJ.
drop policy if exists campaigns_member_read on public.campaigns;
create policy campaigns_member_read on public.campaigns
for select to authenticated
using (public.is_campaign_member(id));

drop policy if exists members_gm_read on public.campaign_members;
create policy members_gm_read on public.campaign_members
for select to authenticated
using (public.is_campaign_gm(campaign_id));

drop policy if exists members_gm_remove_players on public.campaign_members;
create policy members_gm_remove_players on public.campaign_members
for delete to authenticated
using (public.is_campaign_gm(campaign_id) and role = 'player');

drop policy if exists contact_player_notes_public_read on public.contact_player_notes;
drop policy if exists contact_player_notes_gm_read on public.contact_player_notes;
create policy contact_player_notes_gm_read on public.contact_player_notes
for select to authenticated
using (public.is_campaign_gm(campaign_id));
drop policy if exists contact_player_notes_member_read on public.contact_player_notes;
create policy contact_player_notes_member_read on public.contact_player_notes
for select to authenticated
using (public.is_campaign_member(campaign_id));

-- Les politiques historiques conservent leur nom, mais ne ciblent plus les
-- visiteurs anonymes. Le contenu de campagne nécessite un compte membre.
drop policy if exists bestiary_entries_public_manage on public.bestiary_entries;
create policy bestiary_entries_public_manage on public.bestiary_entries
for all to authenticated
using (public.is_campaign_member(campaign_id))
with check (public.is_campaign_member(campaign_id));

drop policy if exists quest_entries_public_manage on public.quest_entries;
create policy quest_entries_public_manage on public.quest_entries
for all to authenticated
using (public.is_campaign_member(campaign_id))
with check (public.is_campaign_member(campaign_id));

drop policy if exists quest_journal_blocks_public_manage on public.quest_journal_blocks;
create policy quest_journal_blocks_public_manage on public.quest_journal_blocks
for all to authenticated
using (public.is_campaign_member(campaign_id))
with check (public.is_campaign_member(campaign_id));

drop policy if exists quest_journal_documents_public_manage on public.quest_journal_documents;
create policy quest_journal_documents_public_manage on public.quest_journal_documents
for all to authenticated
using (public.is_campaign_member(campaign_id))
with check (public.is_campaign_member(campaign_id));

drop policy if exists quest_journal_pages_public_manage on public.quest_journal_pages;
create policy quest_journal_pages_public_manage on public.quest_journal_pages
for all to authenticated
using (public.is_campaign_member(campaign_id))
with check (public.is_campaign_member(campaign_id));

drop policy if exists quest_journal_revisions_public_read on public.quest_journal_revisions;
create policy quest_journal_revisions_public_read on public.quest_journal_revisions
for select to authenticated
using (public.is_campaign_member(campaign_id));

-- Droits minimaux : seule la lecture d’une invitation est publique avant la
-- connexion; toutes les données de campagne exigent le rôle authenticated.
revoke all on table public.campaign_invites from anon, authenticated;
revoke all on table public.loot_player_publications from anon, authenticated;

revoke all on function public.get_campaign_invitation(uuid) from public, anon, authenticated;
grant execute on function public.get_campaign_invitation(uuid) to anon, authenticated;

revoke all on function public.accept_campaign_invitation(uuid) from public, anon, authenticated;
grant execute on function public.accept_campaign_invitation(uuid) to authenticated;

revoke all on function public.list_my_campaigns() from public, anon, authenticated;
grant execute on function public.list_my_campaigns() to authenticated;
revoke all on function public.list_campaign_members(uuid) from public, anon, authenticated;
grant execute on function public.list_campaign_members(uuid) to authenticated;
revoke all on function public.list_campaign_invites(uuid) from public, anon, authenticated;
grant execute on function public.list_campaign_invites(uuid) to authenticated;
revoke all on function public.create_campaign_invite(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.create_campaign_invite(uuid, timestamptz) to authenticated;
revoke all on function public.revoke_campaign_invite(uuid) from public, anon, authenticated;
grant execute on function public.revoke_campaign_invite(uuid) to authenticated;
revoke all on function public.remove_campaign_player(uuid, uuid) from public, anon, authenticated;
grant execute on function public.remove_campaign_player(uuid, uuid) to authenticated;

revoke all on function public.set_loot_player_visibility(uuid, boolean, date) from public, anon, authenticated;
grant execute on function public.set_loot_player_visibility(uuid, boolean, date) to authenticated;
revoke all on function public.set_player_loot_owner_status(uuid, text) from public, anon, authenticated;
grant execute on function public.set_player_loot_owner_status(uuid, text) to authenticated;
revoke all on function public.set_player_loot_published_on(uuid, date) from public, anon, authenticated;
grant execute on function public.set_player_loot_published_on(uuid, date) to authenticated;

revoke all on table public.player_campaign, public.player_contacts,
  public.player_faction_overview, public.player_journal, public.player_loot,
  public.player_relationships, public.player_services from anon;
grant select on table public.player_campaign, public.player_contacts,
  public.player_faction_overview, public.player_journal, public.player_loot,
  public.player_relationships, public.player_services to authenticated;

revoke all on table public.bestiary_entries, public.quest_entries,
  public.quest_journal_blocks, public.quest_journal_documents,
  public.quest_journal_pages, public.quest_journal_revisions,
  public.contact_player_notes from anon;
