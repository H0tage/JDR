-- Préférence de présentation de la vue publique : chiffres ou lecture narrative.
alter table public.campaign_settings
  add column if not exists player_display_mode text not null default 'numeric';

alter table public.campaign_settings
  drop constraint if exists campaign_settings_player_display_mode_check;

alter table public.campaign_settings
  add constraint campaign_settings_player_display_mode_check
  check (player_display_mode in ('numeric', 'intuitive'));

-- La vue publique ne divulgue que cette préférence d'affichage inoffensive.
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
where c.public_enabled;

grant select on public.player_campaign to anon, authenticated;
