-- Blood Lords factions manager
-- Base tables are never exposed to the anonymous role. Player clients read
-- deliberately narrow views that contain no GM-only columns.

create extension if not exists pgcrypto with schema extensions;

create type public.visibility_status as enum ('gm_only', 'players');
create type public.service_scale as enum ('Mineure', 'Modérée', 'Majeure');
create type public.relationship_evidence as enum ('E', 'S', 'H', 'E/S', 'S/H');
create type public.relationship_tone as enum ('alliance', 'cooperation', 'tension', 'hostility', 'unclear');

create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]+$'),
  name text not null,
  description text,
  public_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.campaign_members (
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'gm' check (role = 'gm'),
  created_at timestamptz not null default now(),
  primary key (campaign_id, user_id)
);

create table public.campaign_settings (
  campaign_id uuid primary key references public.campaigns(id) on delete cascade,
  current_volume smallint not null default 1 check (current_volume between 1 and 6),
  jf_cap integer not null default 15 check (jf_cap >= 0),
  minor_cost integer not null default 3 check (minor_cost >= 0),
  moderate_cost integer not null default 7 check (moderate_cost >= 0),
  major_cost integer not null default 12 check (major_cost >= 0),
  liked_threshold integer not null default 5 check (liked_threshold >= 0),
  admired_threshold integer not null default 15 check (admired_threshold >= liked_threshold),
  revered_threshold integer not null default 30 check (revered_threshold >= admired_threshold),
  carters_major_threshold integer not null default 25 check (carters_major_threshold >= 0),
  tension_max integer not null default 4 check (tension_max > 0),
  tension_surcharge_level integer not null default 2 check (tension_surcharge_level >= 0),
  tension_surcharge integer not null default 1 check (tension_surcharge >= 0),
  admired_discount integer not null default 2 check (admired_discount >= 0),
  show_numeric_tension boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.factions (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  short_name text not null,
  accent text not null default '#8f7a5a' check (accent ~ '^#[0-9A-Fa-f]{6}$'),
  domain text not null,
  public_description text not null,
  sort_order smallint not null unique
);

create table public.campaign_factions (
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  faction_id uuid not null references public.factions(id) on delete cascade,
  public_summary text,
  gm_notes text,
  next_consequence text,
  is_player_visible boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (campaign_id, faction_id)
);

create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  faction_id uuid not null references public.factions(id) on delete restrict,
  occurred_on date not null default current_date,
  volume smallint not null check (volume between 1 and 6),
  title text not null check (length(trim(title)) > 0),
  details text,
  rp_delta integer not null default 0,
  jf_delta integer not null default 0,
  tension_delta integer not null default 0,
  visibility public.visibility_status not null default 'gm_only',
  source_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (rp_delta <> 0 or jf_delta <> 0 or tension_delta <> 0 or details is not null)
);

create index journal_campaign_faction_idx on public.journal_entries(campaign_id, faction_id);
create index journal_campaign_date_idx on public.journal_entries(campaign_id, occurred_on desc);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  faction_id uuid not null references public.factions(id) on delete cascade,
  scale public.service_scale not null,
  required_rp integer not null check (required_rp >= 0),
  base_cost integer not null check (base_cost >= 0),
  domain text not null,
  examples text not null,
  safeguard text not null,
  frequency text not null,
  player_visible boolean not null default true,
  sort_order smallint not null default 0,
  unique (campaign_id, faction_id, scale)
);

create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  faction_id uuid not null references public.factions(id) on delete restrict,
  name text not null check (length(trim(name)) > 0),
  role text not null default '',
  state text not null default 'À introduire',
  attitude text not null default 'Neutre',
  promise_debt text,
  due_text text,
  gm_notes text,
  next_consequence text,
  visibility public.visibility_status not null default 'gm_only',
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index one_primary_contact_per_faction
  on public.contacts(campaign_id, faction_id)
  where is_primary;

create table public.faction_relationships (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  source_faction_id uuid not null references public.factions(id) on delete cascade,
  target_faction_id uuid not null references public.factions(id) on delete cascade,
  headline text not null,
  detail text not null,
  evidence public.relationship_evidence not null,
  tone public.relationship_tone not null default 'unclear',
  visibility public.visibility_status not null default 'gm_only',
  updated_at timestamptz not null default now(),
  check (source_faction_id <> target_faction_id),
  unique (campaign_id, source_faction_id, target_faction_id)
);

create table public.bilateral_dossiers (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  faction_a_id uuid not null references public.factions(id) on delete cascade,
  faction_b_id uuid not null references public.factions(id) on delete cascade,
  pair_name text not null,
  canon_core text not null,
  a_to_b text not null,
  b_to_a text not null,
  common_interest text not null,
  fracture text not null,
  triggers text not null,
  scene_hook text not null,
  evidence_note text not null,
  check (faction_a_id <> faction_b_id),
  unique (campaign_id, faction_a_id, faction_b_id)
);

create table public.reputation_milestones (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  volume smallint not null check (volume between 1 and 6),
  chapter text,
  title text not null,
  beneficiary_faction_id uuid references public.factions(id) on delete restrict,
  rp_gain integer not null default 0 check (rp_gain >= 0),
  harmed_faction_id uuid references public.factions(id) on delete restrict,
  rp_loss integer not null default 0 check (rp_loss <= 0),
  condition text not null,
  source_reference text not null,
  applied boolean not null default false,
  gm_notes text,
  sort_order smallint not null default 0,
  applied_at timestamptz
);

create table public.source_references (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  source_type text not null check (source_type in ('Officiel', 'Communauté', 'Synthèse')),
  title text not null,
  reference text,
  usage_note text,
  locator text,
  sort_order smallint not null default 0
);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger campaigns_touch before update on public.campaigns for each row execute function public.touch_updated_at();
create trigger settings_touch before update on public.campaign_settings for each row execute function public.touch_updated_at();
create trigger campaign_factions_touch before update on public.campaign_factions for each row execute function public.touch_updated_at();
create trigger journal_touch before update on public.journal_entries for each row execute function public.touch_updated_at();
create trigger contacts_touch before update on public.contacts for each row execute function public.touch_updated_at();
create trigger relationships_touch before update on public.faction_relationships for each row execute function public.touch_updated_at();

create or replace function public.is_campaign_gm(target_campaign_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.campaign_members cm
    where cm.campaign_id = target_campaign_id
      and cm.user_id = auth.uid()
      and cm.role = 'gm'
  );
$$;

revoke all on function public.is_campaign_gm(uuid) from public;
grant execute on function public.is_campaign_gm(uuid) to authenticated;

alter table public.campaigns enable row level security;
alter table public.campaign_members enable row level security;
alter table public.campaign_settings enable row level security;
alter table public.factions enable row level security;
alter table public.campaign_factions enable row level security;
alter table public.journal_entries enable row level security;
alter table public.services enable row level security;
alter table public.contacts enable row level security;
alter table public.faction_relationships enable row level security;
alter table public.bilateral_dossiers enable row level security;
alter table public.reputation_milestones enable row level security;
alter table public.source_references enable row level security;

create policy campaigns_gm_all on public.campaigns for all to authenticated
  using (public.is_campaign_gm(id)) with check (public.is_campaign_gm(id));
create policy members_self_read on public.campaign_members for select to authenticated
  using (user_id = auth.uid());
create policy settings_gm_all on public.campaign_settings for all to authenticated
  using (public.is_campaign_gm(campaign_id)) with check (public.is_campaign_gm(campaign_id));
create policy factions_authenticated_read on public.factions for select to authenticated using (true);
create policy campaign_factions_gm_all on public.campaign_factions for all to authenticated
  using (public.is_campaign_gm(campaign_id)) with check (public.is_campaign_gm(campaign_id));
create policy journal_gm_all on public.journal_entries for all to authenticated
  using (public.is_campaign_gm(campaign_id)) with check (public.is_campaign_gm(campaign_id));
create policy services_gm_all on public.services for all to authenticated
  using (public.is_campaign_gm(campaign_id)) with check (public.is_campaign_gm(campaign_id));
create policy contacts_gm_all on public.contacts for all to authenticated
  using (public.is_campaign_gm(campaign_id)) with check (public.is_campaign_gm(campaign_id));
create policy relationships_gm_all on public.faction_relationships for all to authenticated
  using (public.is_campaign_gm(campaign_id)) with check (public.is_campaign_gm(campaign_id));
create policy dossiers_gm_all on public.bilateral_dossiers for all to authenticated
  using (public.is_campaign_gm(campaign_id)) with check (public.is_campaign_gm(campaign_id));
create policy milestones_gm_all on public.reputation_milestones for all to authenticated
  using (public.is_campaign_gm(campaign_id)) with check (public.is_campaign_gm(campaign_id));
create policy sources_gm_all on public.source_references for all to authenticated
  using (public.is_campaign_gm(campaign_id)) with check (public.is_campaign_gm(campaign_id));

-- Authenticated views use the caller's RLS policies.
create or replace view public.gm_faction_overview
with (security_invoker = true)
as
with totals as (
  select
    cf.campaign_id,
    cf.faction_id,
    greatest(0, coalesce(sum(j.rp_delta), 0))::integer as rp_raw,
    greatest(0, coalesce(sum(j.jf_delta), 0))::integer as jf_raw,
    greatest(0, coalesce(sum(j.tension_delta), 0))::integer as tension_raw
  from public.campaign_factions cf
  left join public.journal_entries j
    on j.campaign_id = cf.campaign_id and j.faction_id = cf.faction_id
  group by cf.campaign_id, cf.faction_id
)
select
  cf.campaign_id,
  f.id as faction_id,
  f.slug,
  f.name,
  f.short_name,
  f.accent,
  f.domain,
  f.public_description,
  f.sort_order,
  cf.public_summary,
  cf.gm_notes,
  cf.next_consequence,
  cf.is_player_visible,
  t.rp_raw as rp,
  least(s.jf_cap, t.jf_raw) as jf,
  least(s.tension_max, t.tension_raw) as tension,
  case
    when t.rp_raw >= s.revered_threshold then 'Révérés'
    when t.rp_raw >= s.admired_threshold then 'Admirés'
    when t.rp_raw >= s.liked_threshold then 'Appréciés'
    else 'Indifférents'
  end as status,
  case
    when least(s.tension_max, t.tension_raw) = 0 then 'Stable'
    when least(s.tension_max, t.tension_raw) = 1 then 'Signes de froid'
    when least(s.tension_max, t.tension_raw) = 2 then 'Relations tendues'
    when least(s.tension_max, t.tension_raw) = 3 then 'Accès limité'
    else 'Rupture'
  end as tension_label
from public.campaign_factions cf
join public.factions f on f.id = cf.faction_id
join public.campaign_settings s on s.campaign_id = cf.campaign_id
join totals t on t.campaign_id = cf.campaign_id and t.faction_id = cf.faction_id;

create or replace view public.gm_journal_entries with (security_invoker = true) as
select j.*, f.short_name as faction_name
from public.journal_entries j join public.factions f on f.id = j.faction_id;

create or replace view public.gm_contacts with (security_invoker = true) as
select c.*, f.short_name as faction_name, f.sort_order as faction_sort_order
from public.contacts c join public.factions f on f.id = c.faction_id;

create or replace view public.gm_services with (security_invoker = true) as
select s.*, f.short_name as faction_name, f.sort_order as faction_sort_order,
  case s.scale when 'Mineure' then 1 when 'Modérée' then 2 else 3 end as scale_sort
from public.services s join public.factions f on f.id = s.faction_id;

create or replace view public.gm_relationships with (security_invoker = true) as
select r.*, fs.short_name as source_name, ft.short_name as target_name,
  fs.sort_order as source_sort_order, ft.sort_order as target_sort_order
from public.faction_relationships r
join public.factions fs on fs.id = r.source_faction_id
join public.factions ft on ft.id = r.target_faction_id;

create or replace view public.gm_bilateral_dossiers with (security_invoker = true) as
select * from public.bilateral_dossiers;

create or replace view public.gm_milestones with (security_invoker = true) as
select m.*, fb.short_name as beneficiary_name, fh.short_name as harmed_name
from public.reputation_milestones m
left join public.factions fb on fb.id = m.beneficiary_faction_id
left join public.factions fh on fh.id = m.harmed_faction_id;

-- Public views are intentionally security-definer views owned by the migration
-- owner. Anonymous users have no grants on their source tables and receive only
-- the explicitly selected, already-filtered columns below.
create or replace view public.player_campaign
with (security_barrier = true)
as
select c.id as campaign_id, c.slug, c.name, c.description,
  s.current_volume, s.jf_cap, s.minor_cost, s.moderate_cost, s.major_cost,
  s.liked_threshold, s.admired_threshold, s.revered_threshold,
  s.carters_major_threshold, s.tension_max, s.show_numeric_tension
from public.campaigns c
join public.campaign_settings s on s.campaign_id = c.id
where c.public_enabled;

create or replace view public.player_faction_overview
with (security_barrier = true)
as
with totals as (
  select
    cf.campaign_id,
    cf.faction_id,
    greatest(0, coalesce(sum(j.rp_delta), 0))::integer as rp_raw,
    greatest(0, coalesce(sum(j.jf_delta), 0))::integer as jf_raw,
    greatest(0, coalesce(sum(j.tension_delta), 0))::integer as tension_raw
  from public.campaign_factions cf
  left join public.journal_entries j
    on j.campaign_id = cf.campaign_id and j.faction_id = cf.faction_id
  group by cf.campaign_id, cf.faction_id
)
select
  cf.campaign_id,
  f.id as faction_id,
  f.slug,
  f.name,
  f.short_name,
  f.accent,
  f.domain,
  f.public_description,
  f.sort_order,
  cf.public_summary,
  cf.is_player_visible,
  t.rp_raw as rp,
  least(s.jf_cap, t.jf_raw) as jf,
  case when s.show_numeric_tension then least(s.tension_max, t.tension_raw) else null end as tension,
  case
    when t.rp_raw >= s.revered_threshold then 'Révérés'
    when t.rp_raw >= s.admired_threshold then 'Admirés'
    when t.rp_raw >= s.liked_threshold then 'Appréciés'
    else 'Indifférents'
  end as status,
  case
    when least(s.tension_max, t.tension_raw) = 0 then 'Stable'
    when least(s.tension_max, t.tension_raw) = 1 then 'Signes de froid'
    when least(s.tension_max, t.tension_raw) = 2 then 'Relations tendues'
    when least(s.tension_max, t.tension_raw) = 3 then 'Accès limité'
    else 'Rupture'
  end as tension_label
from public.campaign_factions cf
join public.factions f on f.id = cf.faction_id
join public.campaign_settings s on s.campaign_id = cf.campaign_id
join public.campaigns c on c.id = cf.campaign_id and c.public_enabled
join totals t on t.campaign_id = cf.campaign_id and t.faction_id = cf.faction_id
where cf.is_player_visible;

create or replace view public.player_journal
with (security_barrier = true)
as
select j.id, j.campaign_id, j.faction_id, f.short_name as faction_name,
  j.occurred_on, j.volume, j.title, j.details, j.rp_delta, j.jf_delta,
  case when s.show_numeric_tension then j.tension_delta else null end as tension_delta,
  j.visibility
from public.journal_entries j
join public.factions f on f.id = j.faction_id
join public.campaigns c on c.id = j.campaign_id and c.public_enabled
join public.campaign_settings s on s.campaign_id = j.campaign_id
where j.visibility = 'players';

create or replace view public.player_contacts
with (security_barrier = true)
as
select ct.id, ct.campaign_id, ct.faction_id, f.short_name as faction_name,
  ct.name, ct.role, ct.state, ct.attitude, ct.promise_debt, ct.due_text,
  ct.visibility, ct.is_primary
from public.contacts ct
join public.factions f on f.id = ct.faction_id
join public.campaigns c on c.id = ct.campaign_id and c.public_enabled
where ct.visibility = 'players';

create or replace view public.player_relationships
with (security_barrier = true)
as
select r.id, r.campaign_id, r.source_faction_id, fs.short_name as source_name,
  r.target_faction_id, ft.short_name as target_name, r.headline, r.detail,
  r.tone, r.visibility, fs.sort_order as source_sort_order,
  ft.sort_order as target_sort_order
from public.faction_relationships r
join public.factions fs on fs.id = r.source_faction_id
join public.factions ft on ft.id = r.target_faction_id
join public.campaigns c on c.id = r.campaign_id and c.public_enabled
where r.visibility = 'players';

create or replace view public.player_services
with (security_barrier = true)
as
with totals as (
  select
    cf.campaign_id,
    cf.faction_id,
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
  case s.scale when 'Mineure' then 1 when 'Modérée' then 2 else 3 end as scale_sort
from public.services s
join public.factions f on f.id = s.faction_id
join public.campaign_factions cf
  on cf.campaign_id = s.campaign_id and cf.faction_id = s.faction_id
join totals t on t.campaign_id = s.campaign_id and t.faction_id = s.faction_id
join public.campaign_settings cs on cs.campaign_id = s.campaign_id
join public.campaigns c on c.id = s.campaign_id and c.public_enabled
where s.player_visible and cf.is_player_visible
  and t.rp_raw >= s.required_rp
  and least(cs.tension_max, t.tension_raw) < cs.tension_max;

create or replace function public.apply_reputation_milestone(milestone_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.reputation_milestones%rowtype;
begin
  select * into m from public.reputation_milestones where id = milestone_id for update;
  if not found then raise exception 'Jalon introuvable'; end if;
  if not public.is_campaign_gm(m.campaign_id) then raise exception 'Accès refusé'; end if;
  if m.applied then raise exception 'Ce jalon est déjà appliqué'; end if;

  if m.beneficiary_faction_id is not null and m.rp_gain > 0 then
    insert into public.journal_entries
      (campaign_id, faction_id, occurred_on, volume, title, details, rp_delta, jf_delta, visibility, source_reference)
    values
      (m.campaign_id, m.beneficiary_faction_id, current_date, m.volume, m.title || ' — gain', m.condition, m.rp_gain, m.rp_gain, 'gm_only', m.source_reference);
  end if;
  if m.harmed_faction_id is not null and m.rp_loss < 0 then
    insert into public.journal_entries
      (campaign_id, faction_id, occurred_on, volume, title, details, rp_delta, jf_delta, visibility, source_reference)
    values
      (m.campaign_id, m.harmed_faction_id, current_date, m.volume, m.title || ' — perte', m.condition, m.rp_loss, 0, 'gm_only', m.source_reference);
  end if;

  update public.reputation_milestones set applied = true, applied_at = now() where id = milestone_id;
end;
$$;

revoke all on function public.apply_reputation_milestone(uuid) from public;
grant execute on function public.apply_reputation_milestone(uuid) to authenticated;

revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;

grant select, insert, update, delete on public.campaigns, public.campaign_settings,
  public.campaign_factions, public.journal_entries, public.services, public.contacts,
  public.faction_relationships, public.bilateral_dossiers, public.reputation_milestones,
  public.source_references to authenticated;
grant select on public.campaign_members, public.factions to authenticated;
grant select on public.gm_faction_overview, public.gm_journal_entries, public.gm_contacts,
  public.gm_services, public.gm_relationships, public.gm_bilateral_dossiers,
  public.gm_milestones to authenticated;

grant select on public.player_campaign, public.player_faction_overview,
  public.player_journal, public.player_contacts, public.player_relationships,
  public.player_services to anon, authenticated;
