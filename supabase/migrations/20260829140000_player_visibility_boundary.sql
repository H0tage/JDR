-- Une information publique ne doit jamais révéler indirectement une faction
-- que le MJ n’a pas encore rendue visible.

create or replace view public.player_journal
with (security_barrier = true)
as
select j.id, j.campaign_id, j.faction_id, f.short_name as faction_name,
  j.occurred_on, j.volume, j.title, j.details, j.rp_delta, j.jf_delta,
  case when s.show_numeric_tension then j.tension_delta else null end as tension_delta,
  j.visibility
from public.journal_entries j
join public.factions f on f.id = j.faction_id
join public.campaign_factions cf
  on cf.campaign_id = j.campaign_id
  and cf.faction_id = j.faction_id
  and cf.is_player_visible
join public.campaigns c on c.id = j.campaign_id and c.public_enabled
join public.campaign_settings s on s.campaign_id = j.campaign_id
where j.visibility = 'players';

create or replace view public.player_contacts
with (security_barrier = true)
as
select ct.id, ct.campaign_id, ct.faction_id, f.short_name as faction_name,
  ct.name, ct.role, ct.state, ct.attitude, ct.promise_debt, ct.due_text,
  ct.visibility, ct.is_primary,
  pn.character_notes as player_character_notes,
  pn.debt_notes as player_debt_notes,
  pn.notes as player_notes
from public.contacts ct
join public.factions f on f.id = ct.faction_id
join public.campaign_factions cf
  on cf.campaign_id = ct.campaign_id
  and cf.faction_id = ct.faction_id
  and cf.is_player_visible
join public.campaigns c on c.id = ct.campaign_id and c.public_enabled
left join public.contact_player_notes pn on pn.contact_id = ct.id
where ct.visibility = 'players';

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
join public.campaign_factions source_cf
  on source_cf.campaign_id = r.campaign_id
  and source_cf.faction_id = r.source_faction_id
  and source_cf.is_player_visible
join public.campaign_factions target_cf
  on target_cf.campaign_id = r.campaign_id
  and target_cf.faction_id = r.target_faction_id
  and target_cf.is_player_visible
join public.campaigns c on c.id = r.campaign_id and c.public_enabled
where r.visibility = 'players';

drop policy if exists contact_player_notes_public_read on public.contact_player_notes;
create policy contact_player_notes_public_read on public.contact_player_notes
for select to anon, authenticated
using (
  exists (
    select 1
    from public.contacts ct
    join public.campaign_factions cf
      on cf.campaign_id = ct.campaign_id
      and cf.faction_id = ct.faction_id
      and cf.is_player_visible
    join public.campaigns c on c.id = ct.campaign_id
    where ct.id = contact_player_notes.contact_id
      and ct.campaign_id = contact_player_notes.campaign_id
      and ct.visibility = 'players'
      and c.public_enabled
  )
);

create or replace function public.save_player_contact_notes(
  target_contact_id uuid,
  next_character_notes text,
  next_debt_notes text,
  next_notes text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_campaign_id uuid;
begin
  select ct.campaign_id
  into target_campaign_id
  from public.contacts ct
  join public.campaign_factions cf
    on cf.campaign_id = ct.campaign_id
    and cf.faction_id = ct.faction_id
    and cf.is_player_visible
  join public.campaigns c on c.id = ct.campaign_id
  where ct.id = target_contact_id
    and ct.visibility = 'players'
    and c.public_enabled;

  if target_campaign_id is null then
    raise exception 'Contact non disponible dans la vue des joueurs';
  end if;

  insert into public.contact_player_notes (
    contact_id,
    campaign_id,
    character_notes,
    debt_notes,
    notes
  ) values (
    target_contact_id,
    target_campaign_id,
    nullif(trim(next_character_notes), ''),
    nullif(trim(next_debt_notes), ''),
    nullif(trim(next_notes), '')
  )
  on conflict (contact_id) do update set
    character_notes = excluded.character_notes,
    debt_notes = excluded.debt_notes,
    notes = excluded.notes;
end;
$$;
