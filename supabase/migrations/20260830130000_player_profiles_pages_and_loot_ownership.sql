-- Identité publique, page personnelle persistante et attribution réelle des butins.
--
-- Principes de confidentialité :
-- - un joueur ne voit et ne modifie que sa propre page, tant qu'il est membre ;
-- - le MJ peut consulter toutes les pages de sa campagne, sans les modifier ;
-- - retirer un joueur supprime seulement son appartenance, jamais sa page ;
-- - réinviter le même compte rend sa page inchangée de nouveau accessible ;
-- - la suppression de la campagne est la seule suppression normale d'une page.

create table public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_profiles_display_name_check check (
    display_name is null
    or (char_length(btrim(display_name)) between 2 and 40 and display_name = btrim(display_name))
  )
);

create trigger user_profiles_touch
before update on public.user_profiles
for each row execute function public.touch_updated_at();

alter table public.user_profiles enable row level security;

create table public.player_pages (
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  character_name text,
  character_summary text,
  pathbuilder_url text,
  notes text,
  objectives text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (campaign_id, user_id),
  constraint player_pages_character_name_check check (char_length(coalesce(character_name, '')) <= 120),
  constraint player_pages_character_summary_check check (char_length(coalesce(character_summary, '')) <= 4000),
  constraint player_pages_pathbuilder_url_check check (
    pathbuilder_url is null
    or (
      char_length(pathbuilder_url) <= 500
      and (
        lower(pathbuilder_url) like 'https://pathbuilder2e.com/%'
        or lower(pathbuilder_url) like 'https://www.pathbuilder2e.com/%'
      )
    )
  ),
  constraint player_pages_notes_check check (char_length(coalesce(notes, '')) <= 20000),
  constraint player_pages_objectives_check check (char_length(coalesce(objectives, '')) <= 10000)
);

create index player_pages_user_idx on public.player_pages(user_id, campaign_id);

create trigger player_pages_touch
before update on public.player_pages
for each row execute function public.touch_updated_at();

alter table public.player_pages enable row level security;

create policy player_pages_owner_read on public.player_pages
for select to authenticated
using (
  user_id = auth.uid()
  and exists (
    select 1 from public.campaign_members member
    where member.campaign_id = player_pages.campaign_id
      and member.user_id = auth.uid()
      and member.role = 'player'
  )
);

create policy player_pages_gm_read on public.player_pages
for select to authenticated
using (public.is_campaign_gm(campaign_id));

create policy player_pages_owner_update on public.player_pages
for update to authenticated
using (
  user_id = auth.uid()
  and exists (
    select 1 from public.campaign_members member
    where member.campaign_id = player_pages.campaign_id
      and member.user_id = auth.uid()
      and member.role = 'player'
  )
)
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.campaign_members member
    where member.campaign_id = player_pages.campaign_id
      and member.user_id = auth.uid()
      and member.role = 'player'
  )
);

-- Les comptes déjà membres sont préparés sans inventer de pseudo.
insert into public.user_profiles (user_id)
select distinct member.user_id from public.campaign_members member
on conflict (user_id) do nothing;

insert into public.player_pages (campaign_id, user_id)
select member.campaign_id, member.user_id
from public.campaign_members member
where member.role = 'player'
on conflict (campaign_id, user_id) do nothing;

create or replace function public.get_my_profile()
returns table(user_id uuid, display_name text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;

  insert into public.user_profiles (user_id)
  values (auth.uid())
  on conflict on constraint user_profiles_pkey do nothing;

  return query
  select profile.user_id, profile.display_name
  from public.user_profiles profile
  where profile.user_id = auth.uid();
end;
$$;

create or replace function public.update_my_profile(p_display_name text)
returns table(user_id uuid, display_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_name text := btrim(coalesce(p_display_name, ''));
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if char_length(normalized_name) not between 2 and 40 then
    raise exception 'Le pseudo doit comporter entre 2 et 40 caractères';
  end if;

  insert into public.user_profiles (user_id, display_name)
  values (auth.uid(), normalized_name)
  on conflict on constraint user_profiles_pkey do update set display_name = excluded.display_name;

  return query
  select profile.user_id, profile.display_name
  from public.user_profiles profile
  where profile.user_id = auth.uid();
end;
$$;

create or replace function public.list_campaign_players(p_campaign_id uuid)
returns table(user_id uuid, display_name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_campaign_member(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;

  return query
  select member.user_id, coalesce(profile.display_name, 'Sans pseudo')
  from public.campaign_members member
  left join public.user_profiles profile on profile.user_id = member.user_id
  where member.campaign_id = p_campaign_id and member.role = 'player'
  order by lower(coalesce(profile.display_name, 'Sans pseudo')), member.created_at;
end;
$$;

drop function public.list_campaign_members(uuid);
create function public.list_campaign_members(p_campaign_id uuid)
returns table(user_id uuid, display_name text, role text, joined_at timestamptz)
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
  select member.user_id,
    coalesce(profile.display_name, case member.role when 'gm' then 'Maître de jeu' else 'Sans pseudo' end),
    member.role,
    member.created_at
  from public.campaign_members member
  left join public.user_profiles profile on profile.user_id = member.user_id
  where member.campaign_id = p_campaign_id
  order by case member.role when 'gm' then 0 else 1 end,
    lower(coalesce(profile.display_name, 'Sans pseudo'));
end;
$$;

create or replace function public.get_my_player_page(p_campaign_id uuid)
returns table(
  campaign_id uuid,
  user_id uuid,
  display_name text,
  character_name text,
  character_summary text,
  pathbuilder_url text,
  notes text,
  objectives text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id
      and member.user_id = auth.uid()
      and member.role = 'player'
  ) then raise exception 'Accès refusé'; end if;

  insert into public.user_profiles (user_id)
  values (auth.uid())
  on conflict on constraint user_profiles_pkey do nothing;

  insert into public.player_pages (campaign_id, user_id)
  values (p_campaign_id, auth.uid())
  on conflict on constraint player_pages_pkey do nothing;

  return query
  select page.campaign_id, page.user_id, profile.display_name,
    page.character_name, page.character_summary, page.pathbuilder_url,
    page.notes, page.objectives, page.updated_at
  from public.player_pages page
  join public.user_profiles profile on profile.user_id = page.user_id
  where page.campaign_id = p_campaign_id and page.user_id = auth.uid();
end;
$$;

create or replace function public.update_my_player_page(
  p_campaign_id uuid,
  p_character_name text,
  p_character_summary text,
  p_pathbuilder_url text,
  p_notes text,
  p_objectives text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id
      and member.user_id = auth.uid()
      and member.role = 'player'
  ) then raise exception 'Accès refusé'; end if;

  update public.player_pages
  set character_name = nullif(btrim(coalesce(p_character_name, '')), ''),
      character_summary = nullif(btrim(coalesce(p_character_summary, '')), ''),
      pathbuilder_url = nullif(btrim(coalesce(p_pathbuilder_url, '')), ''),
      notes = nullif(btrim(coalesce(p_notes, '')), ''),
      objectives = nullif(btrim(coalesce(p_objectives, '')), '')
  where campaign_id = p_campaign_id and user_id = auth.uid();

  if not found then raise exception 'Page joueur introuvable'; end if;
end;
$$;

create or replace function public.list_campaign_player_pages(p_campaign_id uuid)
returns table(
  campaign_id uuid,
  user_id uuid,
  display_name text,
  active boolean,
  character_name text,
  character_summary text,
  pathbuilder_url text,
  notes text,
  objectives text,
  updated_at timestamptz
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
  select page.campaign_id, page.user_id,
    coalesce(profile.display_name, 'Sans pseudo'),
    (member.user_id is not null),
    page.character_name, page.character_summary, page.pathbuilder_url,
    page.notes, page.objectives, page.updated_at
  from public.player_pages page
  left join public.user_profiles profile on profile.user_id = page.user_id
  left join public.campaign_members member
    on member.campaign_id = page.campaign_id
    and member.user_id = page.user_id
    and member.role = 'player'
  where page.campaign_id = p_campaign_id
  order by member.user_id is null, lower(coalesce(profile.display_name, 'Sans pseudo'));
end;
$$;

-- Accepter une invitation crée la page seulement si elle n'existe pas déjà.
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

  select name into campaign_name_value from public.campaigns where id = invite.campaign_id;
  select exists (
    select 1 from public.campaign_members member
    where member.campaign_id = invite.campaign_id and member.user_id = auth.uid()
  ) into exists_member;

  insert into public.user_profiles (user_id)
  values (auth.uid())
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

-- Conversion sans perte des anciens libellés Joueur1 à Joueur4.
drop view public.player_loot;
drop function public.set_player_loot_owner_status(uuid, text);

alter table public.loot_player_publications
  add column owner_user_id uuid references auth.users(id) on delete set null,
  add column lifecycle_status text not null default 'available'
    check (lifecycle_status in ('available', 'assigned', 'sold', 'dismantled', 'consumed', 'legacy')),
  add column legacy_owner_label text;

update public.loot_player_publications
set lifecycle_status = case owner_status
    when 'Vendu' then 'sold'
    when 'Démonté' then 'dismantled'
    when 'Consommé' then 'consumed'
    when 'Non-attribué' then 'available'
    else 'legacy'
  end,
  legacy_owner_label = case
    when owner_status in ('Joueur1', 'Joueur2', 'Joueur3', 'Joueur4') then owner_status
    else null
  end;

alter table public.loot_player_publications drop column owner_status;

create view public.player_loot
with (security_barrier = true)
as
select loot.campaign_id, loot.sort_order, loot.original_name, loot.quantity,
  loot.unit_value, loot.location_name, loot.id as loot_id,
  publication.published_on, publication.owner_user_id,
  profile.display_name as owner_display_name,
  publication.lifecycle_status, publication.legacy_owner_label
from public.campaign_loot loot
join public.loot_player_publications publication on publication.loot_id = loot.id
left join public.user_profiles profile on profile.user_id = publication.owner_user_id
where loot.player_visible
  and public.is_campaign_member(loot.campaign_id);

create or replace function public.set_player_loot_assignment(
  p_loot_id uuid,
  p_owner_user_id uuid,
  p_lifecycle_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campaign_id uuid;
begin
  if p_lifecycle_status not in ('available', 'assigned', 'sold', 'dismantled', 'consumed') then
    raise exception 'État de butin invalide';
  end if;

  select loot.campaign_id into v_campaign_id
  from public.campaign_loot loot
  join public.loot_player_publications publication on publication.loot_id = loot.id
  where loot.id = p_loot_id and loot.player_visible;

  if v_campaign_id is null or not public.is_campaign_member(v_campaign_id) then
    raise exception 'Butin partagé introuvable';
  end if;

  if p_lifecycle_status = 'assigned' then
    if p_owner_user_id is null or not exists (
      select 1 from public.campaign_members member
      where member.campaign_id = v_campaign_id
        and member.user_id = p_owner_user_id
        and member.role = 'player'
    ) then raise exception 'Propriétaire invalide'; end if;
  elsif p_owner_user_id is not null then
    raise exception 'Un état non attribué ne peut pas avoir de propriétaire';
  end if;

  update public.loot_player_publications
  set owner_user_id = p_owner_user_id,
      lifecycle_status = p_lifecycle_status,
      legacy_owner_label = null
  where loot_id = p_loot_id;
end;
$$;

-- Aucun accès direct aux profils/pages : l'API passe par les fonctions filtrées.
revoke all on table public.user_profiles, public.player_pages from anon, authenticated;

revoke all on function public.get_my_profile() from public, anon, authenticated;
grant execute on function public.get_my_profile() to authenticated;
revoke all on function public.update_my_profile(text) from public, anon, authenticated;
grant execute on function public.update_my_profile(text) to authenticated;
revoke all on function public.list_campaign_players(uuid) from public, anon, authenticated;
grant execute on function public.list_campaign_players(uuid) to authenticated;
revoke all on function public.list_campaign_members(uuid) from public, anon, authenticated;
grant execute on function public.list_campaign_members(uuid) to authenticated;
revoke all on function public.get_my_player_page(uuid) from public, anon, authenticated;
grant execute on function public.get_my_player_page(uuid) to authenticated;
revoke all on function public.update_my_player_page(uuid, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.update_my_player_page(uuid, text, text, text, text, text) to authenticated;
revoke all on function public.list_campaign_player_pages(uuid) from public, anon, authenticated;
grant execute on function public.list_campaign_player_pages(uuid) to authenticated;
revoke all on function public.set_player_loot_assignment(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.set_player_loot_assignment(uuid, uuid, text) to authenticated;

revoke all on table public.player_loot from anon;
grant select on table public.player_loot to authenticated;
