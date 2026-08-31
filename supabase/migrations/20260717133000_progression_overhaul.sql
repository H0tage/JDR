-- Turn the reputation milestones into a six-volume campaign register.
-- A milestone can be succeeded, missed, or automatically excluded by a
-- mutually exclusive choice. Successful resolutions write reversible journal
-- entries, so changing a decision never leaves duplicate reputation gains.

alter table public.reputation_milestones
  add column if not exists status text not null default 'pending'
    check (status in ('pending', 'succeeded', 'missed', 'excluded')),
  add column if not exists resolution_note text,
  add column if not exists choice_group text,
  add column if not exists reward_effects jsonb not null default '[]'::jsonb,
  add column if not exists resolved_effects jsonb,
  add column if not exists resolved_at timestamptz,
  add column if not exists excluded_by_milestone_id uuid
    references public.reputation_milestones(id) on delete set null,
  add column if not exists status_before_exclusion text
    check (status_before_exclusion in ('pending', 'succeeded', 'missed'));

alter table public.journal_entries
  add column if not exists milestone_id uuid
    references public.reputation_milestones(id) on delete set null;

create index if not exists reputation_milestones_volume_idx
  on public.reputation_milestones (campaign_id, volume, sort_order);

create index if not exists reputation_milestones_choice_idx
  on public.reputation_milestones (campaign_id, choice_group)
  where choice_group is not null;

create index if not exists journal_entries_milestone_idx
  on public.journal_entries (milestone_id)
  where milestone_id is not null;

update public.reputation_milestones
set
  status = case when applied then 'succeeded' else 'pending' end,
  resolved_at = case when applied then coalesce(applied_at, now()) else null end
where status = 'pending';

-- Link the seeded volume 1 success to its existing journal entry so it can be
-- reopened and recalculated just like later milestones.
update public.journal_entries
set milestone_id = '00000000-0000-4000-8700-000000000001'
where id = '00000000-0000-4000-8600-000000000001'
  and milestone_id is null;

create or replace view public.gm_milestones
with (security_invoker = true)
as
select
  m.id,
  m.campaign_id,
  m.volume,
  m.chapter,
  m.title,
  m.beneficiary_faction_id,
  m.rp_gain,
  m.harmed_faction_id,
  m.rp_loss,
  m.condition,
  m.source_reference,
  m.applied,
  m.gm_notes,
  m.sort_order,
  m.applied_at,
  fb.short_name as beneficiary_name,
  fh.short_name as harmed_name,
  m.status,
  m.resolution_note,
  m.choice_group,
  m.reward_effects,
  m.resolved_effects,
  m.resolved_at,
  m.excluded_by_milestone_id,
  m.status_before_exclusion,
  winner.title as excluded_by_title
from public.reputation_milestones m
left join public.factions fb on fb.id = m.beneficiary_faction_id
left join public.factions fh on fh.id = m.harmed_faction_id
left join public.reputation_milestones winner
  on winner.id = m.excluded_by_milestone_id;

create or replace function public.resolve_reputation_milestone(
  p_milestone_id uuid,
  p_outcome text,
  p_note text default null,
  p_effects jsonb default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.reputation_milestones%rowtype;
  v_effects jsonb;
  v_effect jsonb;
  v_faction_id uuid;
  v_amount integer;
  v_jf_amount integer;
  v_previous_winner uuid;
begin
  if p_outcome not in ('pending', 'succeeded', 'missed') then
    raise exception 'État de jalon invalide';
  end if;

  select * into m
  from public.reputation_milestones
  where id = p_milestone_id
  for update;

  if not found then raise exception 'Jalon introuvable'; end if;
  if not public.is_campaign_gm(m.campaign_id) then raise exception 'Accès refusé'; end if;
  if m.status = 'excluded' and p_outcome <> 'succeeded' then
    raise exception 'Un choix écarté ne peut être remplacé que par une réussite';
  end if;

  -- Reversing or changing a successful resolution first removes the exact
  -- journal rows it created. Reputation and favour totals are journal-derived.
  delete from public.journal_entries
  where milestone_id = m.id;

  -- Reopening the selected choice restores every sibling that it excluded.
  update public.reputation_milestones
  set
    status = coalesce(status_before_exclusion, 'pending'),
    status_before_exclusion = null,
    excluded_by_milestone_id = null
  where excluded_by_milestone_id = m.id;

  if p_outcome = 'succeeded' and m.choice_group is not null then
    -- Replacing an existing winner reverses its journal effects and restores
    -- the choices it had automatically excluded before the new winner is set.
    for v_previous_winner in
      select id
      from public.reputation_milestones
      where campaign_id = m.campaign_id
        and choice_group = m.choice_group
        and id <> m.id
        and status = 'succeeded'
      for update
    loop
      delete from public.journal_entries
      where milestone_id = v_previous_winner;

      update public.reputation_milestones
      set
        status = coalesce(status_before_exclusion, 'pending'),
        status_before_exclusion = null,
        excluded_by_milestone_id = null
      where excluded_by_milestone_id = v_previous_winner;

      update public.reputation_milestones
      set
        status = 'pending',
        applied = false,
        applied_at = null,
        resolved_at = null,
        resolved_effects = null,
        resolution_note = null
      where id = v_previous_winner;
    end loop;

    update public.reputation_milestones
    set
      status_before_exclusion = status,
      status = 'excluded',
      excluded_by_milestone_id = m.id,
      applied = false,
      applied_at = null
    where campaign_id = m.campaign_id
      and choice_group = m.choice_group
      and id <> m.id;
  end if;

  if p_outcome = 'succeeded' then
    v_effects := coalesce(p_effects, m.reward_effects, '[]'::jsonb);
    if jsonb_typeof(v_effects) <> 'array' then
      raise exception 'Les effets résolus doivent former une liste';
    end if;

    for v_effect in select value from jsonb_array_elements(v_effects)
    loop
      v_faction_id := nullif(v_effect ->> 'faction_id', '')::uuid;
      v_amount := coalesce((v_effect ->> 'amount')::integer, 0);
      v_jf_amount := coalesce(
        (v_effect ->> 'jf_amount')::integer,
        greatest(v_amount, 0)
      );

      if v_faction_id is null then
        raise exception 'Chaque effet appliqué doit désigner une faction';
      end if;
      if not exists (
        select 1 from public.campaign_factions cf
        where cf.campaign_id = m.campaign_id
          and cf.faction_id = v_faction_id
      ) then
        raise exception 'Faction étrangère à cette campagne';
      end if;

      if v_amount <> 0 or v_jf_amount <> 0 then
        insert into public.journal_entries
          (campaign_id, faction_id, occurred_on, volume, title, details,
           rp_delta, jf_delta, visibility, source_reference, milestone_id)
        values
          (m.campaign_id, v_faction_id, current_date, m.volume,
           m.title || case when v_amount < 0 then ' — perte' else ' — gain' end,
           coalesce(nullif(btrim(p_note), ''), m.condition),
           v_amount, v_jf_amount, 'gm_only', m.source_reference, m.id);
      end if;
    end loop;
  else
    v_effects := null;
  end if;

  update public.reputation_milestones
  set
    status = p_outcome,
    resolution_note = nullif(btrim(p_note), ''),
    resolved_effects = v_effects,
    resolved_at = case when p_outcome = 'pending' then null else now() end,
    excluded_by_milestone_id = null,
    status_before_exclusion = null,
    applied = (p_outcome = 'succeeded'),
    applied_at = case when p_outcome = 'succeeded' then now() else null end
  where id = m.id;
end;
$$;

revoke all on function public.resolve_reputation_milestone(uuid, text, text, jsonb) from public;
grant execute on function public.resolve_reputation_milestone(uuid, text, text, jsonb) to authenticated;


-- Private campaign milestones intentionally omitted.
