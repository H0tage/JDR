-- Notes collaboratives sur les contacts : les joueurs peuvent documenter une
-- personne déjà révélée, sans modifier son identité ni les informations MJ.
create table public.contact_player_notes (
  contact_id uuid primary key references public.contacts(id) on delete cascade,
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  character_notes text,
  debt_notes text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (character_length(coalesce(character_notes, '')) <= 10000),
  check (character_length(coalesce(debt_notes, '')) <= 10000),
  check (character_length(coalesce(notes, '')) <= 10000)
);

create trigger contact_player_notes_touch
before update on public.contact_player_notes
for each row execute function public.touch_updated_at();

alter table public.contact_player_notes enable row level security;

-- Les notes sont lisibles uniquement lorsqu’elles appartiennent à un contact
-- déjà révélé dans une campagne publique.
create policy contact_player_notes_public_read on public.contact_player_notes
for select to anon, authenticated
using (
  exists (
    select 1
    from public.contacts ct
    join public.campaigns c on c.id = ct.campaign_id
    where ct.id = contact_player_notes.contact_id
      and ct.campaign_id = contact_player_notes.campaign_id
      and ct.visibility = 'players'
      and c.public_enabled
  )
);

create policy contact_player_notes_gm_read on public.contact_player_notes
for select to authenticated
using (public.is_campaign_gm(campaign_id));

grant select on public.contact_player_notes to anon, authenticated;

-- Cette fonction ne modifie jamais la table contacts : nom, rôle, faction,
-- visibilité et notes MJ restent sous le contrôle du MJ.
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

revoke all on function public.save_player_contact_notes(uuid, text, text, text) from public;
grant execute on function public.save_player_contact_notes(uuid, text, text, text) to anon, authenticated;

create or replace view public.gm_contacts with (security_invoker = true) as
select ct.*, f.short_name as faction_name, f.sort_order as faction_sort_order,
  pn.character_notes as player_character_notes,
  pn.debt_notes as player_debt_notes,
  pn.notes as player_notes
from public.contacts ct
join public.factions f on f.id = ct.faction_id
left join public.contact_player_notes pn on pn.contact_id = ct.id;

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
join public.campaigns c on c.id = ct.campaign_id and c.public_enabled
left join public.contact_player_notes pn on pn.contact_id = ct.id
where ct.visibility = 'players';
