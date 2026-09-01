-- Nom conseillé dans le SQL Editor : Butins — nouveau modèle autoritatif
--
-- Remplacement complet de l'ancien registre de butin. Aucune ligne historique
-- n'est reprise ou convertie : le contenu sera réinstallé séparément depuis la
-- reconstruction privée et autoritative des six tomes.
-- Cette migration publique ne contient aucun spoiler.

drop view if exists public.player_loot;

-- Les anciennes lignes et leurs publications sont volontairement abandonnées.
-- Elles ne constituent pas une source de la nouvelle table.
truncate table public.campaign_loot cascade;

drop index if exists public.campaign_loot_template_idx;
drop index if exists public.campaign_loot_volume_idx;
drop index if exists public.campaign_loot_monitoring_idx;

alter table public.campaign_loot
  drop constraint if exists campaign_loot_source_kind_check,
  drop constraint if exists campaign_loot_discovery_status_check,
  drop column if exists template_key,
  drop column if exists sort_order,
  drop column if exists original_name,
  drop column if exists quantity,
  drop column if exists description,
  drop column if exists unit_value,
  drop column if exists total_value,
  drop column if exists location_name,
  drop column if exists position,
  drop column if exists volume,
  drop column if exists page,
  drop column if exists nature,
  drop column if exists notes,
  drop column if exists is_custom,
  drop column if exists player_visible,
  drop column if exists source_kind,
  drop column if exists source_owner,
  drop column if exists aon_legacy_name,
  drop column if exists aon_legacy_url,
  drop column if exists discovery_status,
  drop column if exists acquisition_condition;

alter table public.campaign_loot
  add column reference_id text,
  add column sort_order integer not null,
  add column volume smallint not null check (volume between 1 and 6),
  add column chapter smallint,
  add column source_page integer check (source_page is null or source_page > 0),
  add column pdf_page integer check (pdf_page is null or pdf_page > 0),
  add column stat_block_page integer check (stat_block_page is null or stat_block_page > 0),
  add column area_code text,
  add column area_title text,
  add column location_name text,
  add column source_kind text not null
    check (source_kind in ('treasure', 'reward', 'carried', 'infused_carried', 'narrative', 'chapter_checklist_only')),
  add column source_owner text,
  add column source_text text,
  add column item_name text not null,
  add column quantity_initial text not null default '1',
  add column quantity_recoverable text not null default '1',
  add column loot_category text,
  add column acquisition_condition text,
  add column consumable_during_encounter boolean not null default false,
  add column availability_rule text,
  add column book_unit_value_amount numeric,
  add column book_unit_value_currency text
    check (book_unit_value_currency is null or book_unit_value_currency in ('pp', 'gp', 'sp', 'cp')),
  add column book_total_value_amount numeric,
  add column book_total_value_currency text
    check (book_total_value_currency is null or book_total_value_currency in ('pp', 'gp', 'sp', 'cp')),
  add column aon_legacy_name text,
  add column aon_legacy_unit_value_amount numeric,
  add column aon_legacy_unit_value_currency text
    check (aon_legacy_unit_value_currency is null or aon_legacy_unit_value_currency in ('pp', 'gp', 'sp', 'cp')),
  add column aon_legacy_total_value_amount numeric,
  add column aon_legacy_total_value_currency text
    check (aon_legacy_total_value_currency is null or aon_legacy_total_value_currency in ('pp', 'gp', 'sp', 'cp')),
  add column aon_legacy_url text,
  add column pricing_basis text,
  add column pricing_status text,
  add column verification_status text,
  add column discovery_status text not null default 'pending'
    check (discovery_status in ('pending', 'found', 'missed')),
  add column player_visible boolean not null default false,
  add column is_custom boolean not null default false;

create unique index campaign_loot_reference_idx
  on public.campaign_loot (campaign_id, reference_id)
  where reference_id is not null;
create index campaign_loot_source_idx
  on public.campaign_loot (campaign_id, volume, source_kind, discovery_status, sort_order);

comment on table public.campaign_loot is
  'Registre neuf construit exclusivement depuis la source autoritative privée, complété par les saisies MJ.';
comment on column public.campaign_loot.book_total_value_amount is
  'Valeur imprimée dans l’ouvrage ; elle n’est jamais remplacée par la valeur AoN.';
comment on column public.campaign_loot.aon_legacy_total_value_amount is
  'Valeur de référence AoN Legacy, conservée séparément de la valeur du livre.';

-- L'ancien modèle global de modèles de butin n'est plus utilisé. Une campagne
-- neuve commence avec un registre vide ; son référentiel éventuel est importé
-- explicitement depuis une source privée.
drop table if exists public.loot_templates;

create or replace function public.seed_campaign_reference_data(p_campaign_id uuid, p_scope text default 'all')
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_scope not in ('archives','loot','all') then raise exception 'Périmètre de restauration invalide'; end if;
  if p_scope in ('archives','all') then
    insert into public.archive_characters
      (campaign_id, template_key, sort_order, first_name, last_name, translated_name, translation_origin, role_text, first_volume, first_page, is_custom)
    select p_campaign_id, template_key, sort_order, first_name, last_name, translated_name, translation_origin, role_text, first_volume, first_page, false
    from public.archive_character_templates
    on conflict (campaign_id, template_key) where template_key is not null do nothing;
    insert into public.archive_places
      (campaign_id, template_key, sort_order, original_name, translated_name, translation_origin, place_type, function_text, first_volume, first_page, is_custom)
    select p_campaign_id, template_key, sort_order, original_name, translated_name, translation_origin, place_type, function_text, first_volume, first_page, false
    from public.archive_place_templates
    on conflict (campaign_id, template_key) where template_key is not null do nothing;
  end if;
end;
$$;

create or replace function public.reset_campaign_reference_data(p_campaign_id uuid, p_scope text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if p_scope not in ('archives','all') then
    raise exception 'Le nouveau registre de butin ne dépend plus d’un modèle global';
  end if;
  delete from public.archive_characters where campaign_id = p_campaign_id;
  delete from public.archive_places where campaign_id = p_campaign_id;
  perform public.seed_campaign_reference_data(p_campaign_id, 'archives');
end;
$$;

create or replace view public.player_loot
with (security_barrier = true)
as
select
  loot.campaign_id,
  loot.sort_order,
  loot.item_name as original_name,
  loot.quantity_recoverable as quantity,
  case
    when loot.book_unit_value_amount is not null then loot.book_unit_value_amount::text || ' ' || loot.book_unit_value_currency
    when loot.aon_legacy_unit_value_amount is not null then loot.aon_legacy_unit_value_amount::text || ' ' || loot.aon_legacy_unit_value_currency
    else null
  end as unit_value,
  coalesce(loot.location_name, loot.area_title) as location_name,
  loot.aon_legacy_name,
  loot.aon_legacy_url,
  loot.id as loot_id,
  publication.published_on,
  publication.owner_user_id,
  profile.display_name as owner_display_name,
  publication.lifecycle_status,
  publication.legacy_owner_label
from public.campaign_loot loot
join public.loot_player_publications publication on publication.loot_id = loot.id
left join public.user_profiles profile on profile.user_id = publication.owner_user_id
where loot.player_visible
  and public.is_campaign_member(loot.campaign_id);

create or replace function public.set_loot_player_visibility(
  p_loot_id uuid,
  p_visible boolean,
  p_published_on date
) returns void
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
  set player_visible = p_visible,
      discovery_status = case when p_visible then 'found' else discovery_status end
  where id = p_loot_id;

  if p_visible then
    insert into public.loot_player_publications (loot_id, campaign_id, published_on)
    values (p_loot_id, v_campaign_id, coalesce(p_published_on, current_date))
    on conflict (loot_id) do nothing;
  end if;
end;
$$;

revoke all on function public.seed_campaign_reference_data(uuid, text) from public, anon, authenticated;
revoke all on function public.reset_campaign_reference_data(uuid, text) from public, anon, authenticated;
revoke all on function public.set_loot_player_visibility(uuid, boolean, date) from public, anon, authenticated;
grant execute on function public.reset_campaign_reference_data(uuid, text) to authenticated;
grant execute on function public.set_loot_player_visibility(uuid, boolean, date) to authenticated;
revoke all on table public.player_loot from anon;
grant select on table public.player_loot to authenticated;
