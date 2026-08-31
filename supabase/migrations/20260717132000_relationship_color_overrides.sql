-- Expose editable wording and a simple three-colour reading of each
-- relationship while retaining the richer source data. This migration is
-- deliberately cumulative and can be run even if the previous override
-- migration has not been applied yet.

alter table public.faction_relationships
  add column if not exists headline_override text,
  add column if not exists detail_override text,
  add column if not exists color_override text
    check (color_override in ('favorable', 'uncertain', 'hostile'));

create or replace view public.gm_relationships
with (security_invoker = true)
as
select
  r.id,
  r.campaign_id,
  r.source_faction_id,
  r.target_faction_id,
  coalesce(nullif(btrim(r.headline_override), ''), r.headline) as headline,
  coalesce(nullif(btrim(r.detail_override), ''), r.detail) as detail,
  r.evidence,
  r.tone,
  r.visibility,
  r.updated_at,
  fs.short_name as source_name,
  ft.short_name as target_name,
  fs.sort_order as source_sort_order,
  ft.sort_order as target_sort_order,
  r.headline as default_headline,
  r.detail as default_detail,
  r.headline_override,
  r.detail_override,
  case
    when r.tone = 'hostility' then 'hostile'
    when r.tone in ('tension', 'unclear') then 'uncertain'
    else 'favorable'
  end as default_color,
  r.color_override,
  coalesce(
    r.color_override,
    case
      when r.tone = 'hostility' then 'hostile'
      when r.tone in ('tension', 'unclear') then 'uncertain'
      else 'favorable'
    end
  ) as color
from public.faction_relationships r
join public.factions fs on fs.id = r.source_faction_id
join public.factions ft on ft.id = r.target_faction_id;

create or replace view public.player_relationships
with (security_barrier = true)
as
select
  r.id,
  r.campaign_id,
  r.source_faction_id,
  fs.short_name as source_name,
  r.target_faction_id,
  ft.short_name as target_name,
  coalesce(nullif(btrim(r.headline_override), ''), r.headline) as headline,
  coalesce(nullif(btrim(r.detail_override), ''), r.detail) as detail,
  r.tone,
  r.visibility,
  fs.sort_order as source_sort_order,
  ft.sort_order as target_sort_order,
  coalesce(
    r.color_override,
    case
      when r.tone = 'hostility' then 'hostile'
      when r.tone in ('tension', 'unclear') then 'uncertain'
      else 'favorable'
    end
  ) as color
from public.faction_relationships r
join public.factions fs on fs.id = r.source_faction_id
join public.factions ft on ft.id = r.target_faction_id
join public.campaigns c on c.id = r.campaign_id and c.public_enabled
where r.visibility = 'players';
