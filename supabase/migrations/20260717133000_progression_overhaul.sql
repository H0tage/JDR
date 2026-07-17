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
           v_amount, v_jf_amount, 'ready', m.source_reference, m.id);
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

-- Official story milestones. Generic repeatable Blood Lord downtime activities
-- from volume 4 are intentionally not seeded: they are tools, not finite story
-- checkpoints. Printed book pages are used in every source reference.

insert into public.reputation_milestones
  (id, campaign_id, volume, chapter, title, condition, source_reference,
   sort_order, choice_group, reward_effects)
values
  ('00000000-0000-4000-8700-000000000001','00000000-0000-4000-8000-000000000001',1,'Chapitre 1','Résoudre la crise de la ferme','Mettre fin aux troubles de la ferme confiée par Berline.','Blood Lords #1 — Zombie Feast, p. 21',1,null,'[{"label":"Réanimateurs","faction_id":"00000000-0000-4000-8100-000000000104","amount":5}]'),
  ('00000000-0000-4000-8700-000000000002','00000000-0000-4000-8000-000000000001',1,'Chapitre 3','Secourir Se-Maut-Get','Se-Maut-Get doit être secouru et survivre à l’aventure.','Blood Lords #1 — Zombie Feast, p. 59',2,null,'[{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount":4}]'),
  ('00000000-0000-4000-8700-000000000003','00000000-0000-4000-8000-000000000001',1,'Chapitre 3','Libérer Altinmered','Libérer Altinmered de sa captivité.','Blood Lords #1 — Zombie Feast, p. 62',3,null,'[{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount":4}]'),
  ('00000000-0000-4000-8700-000000000004','00000000-0000-4000-8000-000000000001',1,'Épilogue','Confier la banque aux Percepteurs','Permettre à Vaskish de rouvrir la banque pour les Percepteurs.','Blood Lords #1 — Zombie Feast, p. 63',4,'v1-graydirge-bank','[{"label":"Percepteurs","faction_id":"00000000-0000-4000-8100-000000000105","amount":8},{"label":"Bâtisseurs","faction_id":"00000000-0000-4000-8100-000000000101","amount":-4}]'),
  ('00000000-0000-4000-8700-000000000005','00000000-0000-4000-8000-000000000001',1,'Épilogue','Confier la banque aux Bâtisseurs','Révéler la revendication légale de la Ligue des Bâtisseurs.','Blood Lords #1 — Zombie Feast, p. 63',5,'v1-graydirge-bank','[{"label":"Bâtisseurs","faction_id":"00000000-0000-4000-8100-000000000101","amount":8},{"label":"Percepteurs","faction_id":"00000000-0000-4000-8100-000000000105","amount":-4}]')
on conflict (id) do update set
  volume = excluded.volume,
  chapter = excluded.chapter,
  title = excluded.title,
  condition = excluded.condition,
  source_reference = excluded.source_reference,
  sort_order = excluded.sort_order,
  choice_group = excluded.choice_group,
  reward_effects = excluded.reward_effects;

insert into public.reputation_milestones
  (id, campaign_id, volume, chapter, title, condition, source_reference,
   sort_order, choice_group, reward_effects)
values
  ('00000000-0000-4000-8700-000000000045','00000000-0000-4000-8000-000000000001',5,'Chapitre 1','Rendre visite à Kyril','Prendre le temps de rencontrer Kyril à Yled.','Blood Lords #5 — A Taste of Ashes, p. 10',1,null,'[{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount":1}]'),
  ('00000000-0000-4000-8700-000000000046','00000000-0000-4000-8000-000000000001',5,'Chapitre 1','Sauver Bteth Ynar','Protéger le marchand victime de la campagne de rumeurs.','Blood Lords #5 — A Taste of Ashes, p. 12',2,null,'[{"label":"Percepteurs","faction_id":"00000000-0000-4000-8100-000000000105","amount":1}]'),
  ('00000000-0000-4000-8700-000000000047','00000000-0000-4000-8000-000000000001',5,'Chapitre 1','Éliminer les Duskdrinkers','Détruire entièrement le gang de vrykolakas.','Blood Lords #5 — A Taste of Ashes, p. 15',3,null,'[{"label":"Bâtisseurs et Réanimateurs","faction_ids":["00000000-0000-4000-8100-000000000101","00000000-0000-4000-8100-000000000104"],"amount":1}]'),
  ('00000000-0000-4000-8700-000000000048','00000000-0000-4000-8000-000000000001',5,'Chapitre 2','Nouer des relations avec le patron des Bâtisseurs','Établir des relations amicales avec le représentant correspondant présent au théâtre.','Blood Lords #5 — A Taste of Ashes, p. 30',4,null,'[{"label":"Bâtisseurs","faction_id":"00000000-0000-4000-8100-000000000101","amount":3}]'),
  ('00000000-0000-4000-8700-000000000049','00000000-0000-4000-8000-000000000001',5,'Chapitre 2','Nouer des relations avec le patron des Célébrants','Établir des relations amicales avec le représentant correspondant présent au théâtre.','Blood Lords #5 — A Taste of Ashes, p. 30',5,null,'[{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount":3}]'),
  ('00000000-0000-4000-8700-000000000050','00000000-0000-4000-8000-000000000001',5,'Chapitre 2','Nouer des relations avec le patron des Exportateurs','Établir des relations amicales avec le représentant correspondant présent au théâtre.','Blood Lords #5 — A Taste of Ashes, p. 30',6,null,'[{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount":3}]'),
  ('00000000-0000-4000-8700-000000000051','00000000-0000-4000-8000-000000000001',5,'Chapitre 2','Nouer des relations avec le patron des Réanimateurs','Établir des relations amicales avec le représentant correspondant présent au théâtre.','Blood Lords #5 — A Taste of Ashes, p. 30',7,null,'[{"label":"Réanimateurs","faction_id":"00000000-0000-4000-8100-000000000104","amount":3}]'),
  ('00000000-0000-4000-8700-000000000052','00000000-0000-4000-8000-000000000001',5,'Chapitre 2','Nouer des relations avec le patron des Percepteurs','Établir des relations amicales avec le représentant correspondant présent au théâtre.','Blood Lords #5 — A Taste of Ashes, p. 30',8,null,'[{"label":"Percepteurs","faction_id":"00000000-0000-4000-8100-000000000105","amount":3}]'),
  ('00000000-0000-4000-8700-000000000053','00000000-0000-4000-8000-000000000001',5,'Chapitre 2','Participer à la représentation','Au moins un PJ accepte de jouer : chaque Grande Faction accorde 1 RP.','Blood Lords #5 — A Taste of Ashes, p. 33',9,'v5-play-participation','[{"label":"Grandes Factions","scope":"all_great","amount":1}]'),
  ('00000000-0000-4000-8700-000000000054','00000000-0000-4000-8000-000000000001',5,'Chapitre 2','Refuser de participer à la représentation','Aucun PJ ne se porte volontaire ; la faction du PNJ clé perd 1d4 RP.','Blood Lords #5 — A Taste of Ashes, p. 33',10,'v5-play-participation','[{"label":"Faction du PNJ clé","scope":"any_great","amount_min":-4,"amount_max":-1}]'),
  ('00000000-0000-4000-8700-000000000055','00000000-0000-4000-8000-000000000001',5,'Chapitre 2','Triompher avec 30 points de représentation ou plus','Attribuer 8 RP à la faction du PNJ clé, puis 6 et 4 RP à deux autres factions.','Blood Lords #5 — A Taste of Ashes, p. 36',11,'v5-play-performance','[{"label":"Faction du PNJ clé","scope":"any_great","amount":8,"distinct_group":"v5-performance"},{"label":"Deuxième faction","scope":"any","amount":6,"distinct_group":"v5-performance"},{"label":"Troisième faction","scope":"any","amount":4,"distinct_group":"v5-performance"}]'),
  ('00000000-0000-4000-8700-000000000056','00000000-0000-4000-8000-000000000001',5,'Chapitre 2','Obtenir 25 à 29 points de représentation','Le livre imprime « 20–29 » ; cette plage est traitée comme 25–29 pour éviter son chevauchement avec 20–24.','Blood Lords #5 — A Taste of Ashes, p. 36',12,'v5-play-performance','[{"label":"Faction du PNJ clé","scope":"any_great","amount":8,"distinct_group":"v5-performance"},{"label":"Deuxième faction","scope":"any","amount":4,"distinct_group":"v5-performance"},{"label":"Troisième faction","scope":"any","amount":2,"distinct_group":"v5-performance"}]'),
  ('00000000-0000-4000-8700-000000000057','00000000-0000-4000-8000-000000000001',5,'Chapitre 2','Obtenir 20 à 24 points de représentation','Attribuer 6 RP à la faction du PNJ clé, puis 4 et 2 RP à deux autres factions.','Blood Lords #5 — A Taste of Ashes, p. 36',13,'v5-play-performance','[{"label":"Faction du PNJ clé","scope":"any_great","amount":6,"distinct_group":"v5-performance"},{"label":"Deuxième faction","scope":"any","amount":4,"distinct_group":"v5-performance"},{"label":"Troisième faction","scope":"any","amount":2,"distinct_group":"v5-performance"}]'),
  ('00000000-0000-4000-8700-000000000058','00000000-0000-4000-8000-000000000001',5,'Chapitre 2','Obtenir 10 à 19 points de représentation','Attribuer 4 RP à la faction du PNJ clé et 2 RP à une autre faction.','Blood Lords #5 — A Taste of Ashes, p. 36',14,'v5-play-performance','[{"label":"Faction du PNJ clé","scope":"any_great","amount":4,"distinct_group":"v5-performance"},{"label":"Deuxième faction","scope":"any","amount":2,"distinct_group":"v5-performance"}]'),
  ('00000000-0000-4000-8700-000000000059','00000000-0000-4000-8000-000000000001',5,'Chapitre 2','Obtenir au plus 9 points de représentation','Attribuer 2 RP à la faction du PNJ clé.','Blood Lords #5 — A Taste of Ashes, p. 36',15,'v5-play-performance','[{"label":"Faction du PNJ clé","scope":"any_great","amount":2}]')
on conflict (id) do update set
  volume = excluded.volume,
  chapter = excluded.chapter,
  title = excluded.title,
  condition = excluded.condition,
  source_reference = excluded.source_reference,
  sort_order = excluded.sort_order,
  choice_group = excluded.choice_group,
  reward_effects = excluded.reward_effects;

insert into public.reputation_milestones
  (id, campaign_id, volume, chapter, title, condition, source_reference,
   sort_order, choice_group, reward_effects)
values
  ('00000000-0000-4000-8700-000000000060','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Préserver le secret de Castel','Accepter de rester discret au sujet de la base secrète des Convoyeurs.','Blood Lords #6 — Ghost King’s Rage, p. 6',1,null,'[{"label":"Convoyeurs","faction_id":"00000000-0000-4000-8100-000000000106","amount":2}]'),
  ('00000000-0000-4000-8700-000000000061','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Remettre les ossements aux Réanimateurs','Donner aux Réanimateurs les ossements de l’ossuaire pharasméen.','Blood Lords #6 — Ghost King’s Rage, p. 10',2,'v6-ossuary-bones','[{"label":"Réanimateurs","faction_id":"00000000-0000-4000-8100-000000000104","amount":2}]'),
  ('00000000-0000-4000-8700-000000000062','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Remettre les ossements aux Célébrants','Offrir les ossements à Daikhal pour en faire un spectacle.','Blood Lords #6 — Ghost King’s Rage, p. 10',3,'v6-ossuary-bones','[{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount":4},{"label":"Réanimateurs","faction_id":"00000000-0000-4000-8100-000000000104","amount":-2}]'),
  ('00000000-0000-4000-8700-000000000063','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Rendre le sceptre à Gulvar','Choisir le frère lié aux Percepteurs.','Blood Lords #6 — Ghost King’s Rage, p. 11',4,'v6-scepter','[{"label":"Percepteurs","faction_id":"00000000-0000-4000-8100-000000000105","amount":1}]'),
  ('00000000-0000-4000-8700-000000000064','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Rendre le sceptre à Lugvar','Choisir le frère lié aux Bâtisseurs.','Blood Lords #6 — Ghost King’s Rage, p. 11',5,'v6-scepter','[{"label":"Bâtisseurs","faction_id":"00000000-0000-4000-8100-000000000101","amount":1}]'),
  ('00000000-0000-4000-8700-000000000065','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Confier le sceptre à Castel','Accepter de faire disparaître le sceptre et de ne plus en parler.','Blood Lords #6 — Ghost King’s Rage, p. 11',6,'v6-scepter','[{"label":"Convoyeurs","faction_id":"00000000-0000-4000-8100-000000000106","amount":2}]'),
  ('00000000-0000-4000-8700-000000000066','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Vendre le framboisier aux Exportateurs','Privilégier la vente immédiate de la plante et des objets associés.','Blood Lords #6 — Ghost King’s Rage, p. 11',7,'v6-raspberry-bush','[{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount":1},{"label":"Réanimateurs","faction_id":"00000000-0000-4000-8100-000000000104","amount":-1}]'),
  ('00000000-0000-4000-8700-000000000067','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Confier le framboisier aux Réanimateurs','Investir dans une future culture plutôt que dans le profit immédiat.','Blood Lords #6 — Ghost King’s Rage, p. 11',8,'v6-raspberry-bush','[{"label":"Réanimateurs","faction_id":"00000000-0000-4000-8100-000000000104","amount":1}]'),
  ('00000000-0000-4000-8700-000000000068','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Livrer Erthrais à Mirgona','Remettre la shabti à l’alliée de la Guilde des Exportateurs.','Blood Lords #6 — Ghost King’s Rage, p. 13',9,'v6-erthrais','[{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount":4}]'),
  ('00000000-0000-4000-8700-000000000069','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Livrer Erthrais aux adversaires de Mirgona','Remettre la shabti à Alagun Faulks et Quarnim Ix.','Blood Lords #6 — Ghost King’s Rage, p. 13',10,'v6-erthrais','[{"label":"Percepteurs","faction_id":"00000000-0000-4000-8100-000000000105","amount":2},{"label":"Bâtisseurs","faction_id":"00000000-0000-4000-8100-000000000101","amount":2}]'),
  ('00000000-0000-4000-8700-000000000070','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Libérer Erthrais','Laisser Erthrais libre ; ce choix ne rapporte aucun RP.','Blood Lords #6 — Ghost King’s Rage, p. 13',11,'v6-erthrais','[]'),
  ('00000000-0000-4000-8700-000000000071','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Donner les titres de propriété à une faction','Renoncer aux 10 000 po et offrir les actes à la faction choisie.','Blood Lords #6 — Ghost King’s Rage, p. 13',12,null,'[{"label":"Faction choisie","scope":"any","amount":2}]'),
  ('00000000-0000-4000-8700-000000000072','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Donner les œuvres aux Exportateurs','Confier les œuvres et bijoux à Oreen Argilt.','Blood Lords #6 — Ghost King’s Rage, p. 15',13,'v6-art-and-jewelry','[{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount":2},{"label":"Percepteurs","faction_id":"00000000-0000-4000-8100-000000000105","amount":-1}]'),
  ('00000000-0000-4000-8700-000000000073','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Donner les œuvres aux Percepteurs','Confier les œuvres et bijoux à Alunkhamen.','Blood Lords #6 — Ghost King’s Rage, p. 15',14,'v6-art-and-jewelry','[{"label":"Percepteurs","faction_id":"00000000-0000-4000-8100-000000000105","amount":2},{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount":-1}]'),
  ('00000000-0000-4000-8700-000000000074','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Donner les noms des urnes aux Célébrants','Remettre la liste à Daikhal.','Blood Lords #6 — Ghost King’s Rage, p. 16',15,'v6-urn-names','[{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount":2}]'),
  ('00000000-0000-4000-8700-000000000075','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Donner les noms des urnes aux Convoyeurs','Remettre la liste à Castel et accepter de l’oublier.','Blood Lords #6 — Ghost King’s Rage, p. 16',16,'v6-urn-names','[{"label":"Convoyeurs","faction_id":"00000000-0000-4000-8100-000000000106","amount":1}]'),
  ('00000000-0000-4000-8700-000000000076','00000000-0000-4000-8000-000000000001',6,'Chapitre 1','Faire absorber les Convoyeurs par une Grande Faction','Transférer tous les RP des Convoyeurs à la Grande Faction choisie, sans créer de nouveaux JF.','Blood Lords #6 — Ghost King’s Rage, p. 27',17,null,'[{"label":"Grande Faction bénéficiaire","scope":"transfer_carters"}]'),
  ('00000000-0000-4000-8700-000000000077','00000000-0000-4000-8000-000000000001',6,'Chapitre 2','Rendre les ouvriers fugitifs à Berline','Ramener les travailleurs ou communiquer leur emplacement à Berline.','Blood Lords #6 — Ghost King’s Rage, p. 53',18,null,'[{"label":"Réanimateurs","faction_id":"00000000-0000-4000-8100-000000000104","amount":2}]')
on conflict (id) do update set
  volume = excluded.volume,
  chapter = excluded.chapter,
  title = excluded.title,
  condition = excluded.condition,
  source_reference = excluded.source_reference,
  sort_order = excluded.sort_order,
  choice_group = excluded.choice_group,
  reward_effects = excluded.reward_effects;

insert into public.source_references
  (campaign_id, source_type, title, reference, usage_note, locator, sort_order)
values
  ('00000000-0000-4000-8000-000000000001','Communauté',
   'How much reputation with each faction can a party get throughout the campaign?',
   'Reddit — relevé des maxima RAW',
   'Contrôle communautaire des choix et maxima ; chaque jalon du site reste vérifié dans le PDF officiel.',
   'https://www.reddit.com/r/BloodLords/comments/1ks3erh/how_much_reputation_with_each_faction_can_a_party/',21)
on conflict do nothing;

insert into public.reputation_milestones
  (id, campaign_id, volume, chapter, title, condition, source_reference,
   sort_order, choice_group, reward_effects)
values
  ('00000000-0000-4000-8700-000000000021','00000000-0000-4000-8000-000000000001',3,'Chapitre 1','Partager la mission de Seldeg avec Berline','Être transparent avec Berline et l’autoriser à informer ses contacts.','Blood Lords #3 — Field of Maidens, p. 7',1,null,'[{"label":"Réanimateurs","faction_id":"00000000-0000-4000-8100-000000000104","amount":1}]'),
  ('00000000-0000-4000-8700-000000000022','00000000-0000-4000-8000-000000000001',3,'Chapitre 1','Rendre la bannière aux Célébrants','Identifier puis restituer l’ancienne bannière cousue d’or.','Blood Lords #3 — Field of Maidens, p. 20',2,null,'[{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount":1}]'),
  ('00000000-0000-4000-8700-000000000023','00000000-0000-4000-8000-000000000001',3,'Chapitre 1','Reloger Thornhearth à Graydirge','Organiser le départ des habitants et les installer spécifiquement à Graydirge.','Blood Lords #3 — Field of Maidens, p. 22',3,'v3-thornhearth','[{"label":"Percepteurs","faction_id":"00000000-0000-4000-8100-000000000105","amount":2},{"label":"Réanimateurs","faction_id":"00000000-0000-4000-8100-000000000104","amount":1}]'),
  ('00000000-0000-4000-8700-000000000024','00000000-0000-4000-8000-000000000001',3,'Chapitre 1','Reloger Thornhearth ailleurs','Organiser un départ ordonné sans installer les habitants à Graydirge.','Blood Lords #3 — Field of Maidens, p. 22',4,'v3-thornhearth','[{"label":"Percepteurs","faction_id":"00000000-0000-4000-8100-000000000105","amount":2}]'),
  ('00000000-0000-4000-8700-000000000025','00000000-0000-4000-8000-000000000001',3,'Chapitre 1','Maintenir Thornhearth comme étape commerciale','Sécuriser la ville et convaincre les habitants de rester.','Blood Lords #3 — Field of Maidens, p. 22',5,'v3-thornhearth','[{"label":"Convoyeurs","faction_id":"00000000-0000-4000-8100-000000000106","amount":2}]'),
  ('00000000-0000-4000-8700-000000000026','00000000-0000-4000-8000-000000000001',3,'Chapitre 1','Confier Thornhearth à une faction','Faire venir une nouvelle direction issue de la faction choisie.','Blood Lords #3 — Field of Maidens, p. 22',6,'v3-thornhearth','[{"label":"Faction choisie","scope":"any","amount":4}]'),
  ('00000000-0000-4000-8700-000000000027','00000000-0000-4000-8000-000000000001',3,'Chapitre 2','Donner les tablettes aux Bâtisseurs','Remettre les plans architecturaux du Marché de Chair Creuse aux Bâtisseurs.','Blood Lords #3 — Field of Maidens, p. 26',7,'v3-market-tablets','[{"label":"Bâtisseurs","faction_id":"00000000-0000-4000-8100-000000000101","amount":2}]'),
  ('00000000-0000-4000-8700-000000000028','00000000-0000-4000-8000-000000000001',3,'Chapitre 2','Donner les tablettes aux Célébrants','Remettre les plans architecturaux du Marché de Chair Creuse aux Célébrants.','Blood Lords #3 — Field of Maidens, p. 26',8,'v3-market-tablets','[{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount":1}]'),
  ('00000000-0000-4000-8700-000000000029','00000000-0000-4000-8000-000000000001',3,'Chapitre 2','Donner les tablettes aux Convoyeurs','Remettre les plans architecturaux du Marché de Chair Creuse aux Convoyeurs.','Blood Lords #3 — Field of Maidens, p. 26',9,'v3-market-tablets','[{"label":"Convoyeurs","faction_id":"00000000-0000-4000-8100-000000000106","amount":1}]'),
  ('00000000-0000-4000-8700-000000000030','00000000-0000-4000-8000-000000000001',3,'Chapitre 2','Épargner Yulthruk','Négocier avec Yulthruk et le laisser en vie.','Blood Lords #3 — Field of Maidens, p. 46',10,null,'[{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount":1}]'),
  ('00000000-0000-4000-8700-000000000031','00000000-0000-4000-8000-000000000001',3,'Chapitre 3','Tuer les bulettes de Gristlehall','Venger l’ancien membre influent de la Guilde des Exportateurs.','Blood Lords #3 — Field of Maidens, p. 54',11,null,'[{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount":1}]')
on conflict (id) do update set
  volume = excluded.volume,
  chapter = excluded.chapter,
  title = excluded.title,
  condition = excluded.condition,
  source_reference = excluded.source_reference,
  sort_order = excluded.sort_order,
  choice_group = excluded.choice_group,
  reward_effects = excluded.reward_effects;

insert into public.reputation_milestones
  (id, campaign_id, volume, chapter, title, condition, source_reference,
   sort_order, choice_group, reward_effects)
values
  ('00000000-0000-4000-8700-000000000032','00000000-0000-4000-8000-000000000001',4,'Chapitre 1','Mener la procession','Le résultat accorde de 1 à 3 RP à la faction soutenue, ou aux Célébrants sans soutien déclaré.','Blood Lords #4 — The Ghouls Hunger, p. 7',1,null,'[{"label":"Faction soutenue","scope":"any","amount_min":1,"amount_max":3}]'),
  ('00000000-0000-4000-8700-000000000033','00000000-0000-4000-8000-000000000001',4,'Chapitre 1','Donner les preuves à une Grande Faction','Confier discrètement les preuves compromettant les Convoyeurs à une seule Grande Faction.','Blood Lords #4 — The Ghouls Hunger, p. 15',2,'v4-carters-evidence','[{"label":"Grande Faction choisie","scope":"any_great","amount":1}]'),
  ('00000000-0000-4000-8700-000000000034','00000000-0000-4000-8000-000000000001',4,'Chapitre 1','Distribuer discrètement des copies','Donner une copie à chaque Grande Faction sans que la manœuvre soit découverte.','Blood Lords #4 — The Ghouls Hunger, p. 15',3,'v4-carters-evidence','[{"label":"Grandes Factions","scope":"all_great","amount":1}]'),
  ('00000000-0000-4000-8700-000000000035','00000000-0000-4000-8000-000000000001',4,'Chapitre 1','Voir la distribution des copies découverte','Les gains des copies sont retirés et la première faction approchée fait perdre 1 RP.','Blood Lords #4 — The Ghouls Hunger, p. 15',4,'v4-carters-evidence','[{"label":"Première faction approchée","scope":"any_great","amount":-1}]'),
  ('00000000-0000-4000-8700-000000000036','00000000-0000-4000-8000-000000000001',4,'Chapitre 1','Rendre les preuves aux Convoyeurs','Ne remettre les preuves à aucune autre faction.','Blood Lords #4 — The Ghouls Hunger, p. 15',5,'v4-carters-evidence','[{"label":"Convoyeurs","faction_id":"00000000-0000-4000-8100-000000000106","amount":2}]'),
  ('00000000-0000-4000-8700-000000000037','00000000-0000-4000-8000-000000000001',4,'Chapitre 1','Présenter dignement le nouveau domaine','Réussir ou réussir de façon critique la présentation de la demeure des nouveaux Blood Lords.','Blood Lords #4 — The Ghouls Hunger, p. 16',6,null,'[{"label":"Bâtisseurs","faction_id":"00000000-0000-4000-8100-000000000101","amount_min":1,"amount_max":2}]'),
  ('00000000-0000-4000-8700-000000000038','00000000-0000-4000-8000-000000000001',4,'Chapitre 2','Suspendre les bannières de Kortash','Proclamer que la Tour aux Os Rongés est passée sous le contrôle de Geb.','Blood Lords #4 — The Ghouls Hunger, p. 31',7,null,'[{"label":"Bâtisseurs","faction_id":"00000000-0000-4000-8100-000000000101","amount":2}]'),
  ('00000000-0000-4000-8700-000000000039','00000000-0000-4000-8000-000000000001',4,'Chapitre 2','Remettre les goules aux Réanimateurs','Livrer rapidement les corps des Secret Eaters aux Réanimateurs pour étude.','Blood Lords #4 — The Ghouls Hunger, p. 31',8,'v4-secret-eater-corpses','[{"label":"Réanimateurs","faction_id":"00000000-0000-4000-8100-000000000104","amount":2}]'),
  ('00000000-0000-4000-8700-000000000040','00000000-0000-4000-8000-000000000001',4,'Chapitre 2','Remettre les goules aux Célébrants','Livrer rapidement les corps des Secret Eaters aux Célébrants comme trophées.','Blood Lords #4 — The Ghouls Hunger, p. 31',9,'v4-secret-eater-corpses','[{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount":2}]'),
  ('00000000-0000-4000-8700-000000000041','00000000-0000-4000-8000-000000000001',4,'Chapitre 2','Sauver les dockers d’Ossum','Gagner 1 RP avec trois survivants, puis 1 par quatre survivants supplémentaires, jusqu’à 4.','Blood Lords #4 — The Ghouls Hunger, p. 35',10,null,'[{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount_min":1,"amount_max":4}]'),
  ('00000000-0000-4000-8700-000000000042','00000000-0000-4000-8000-000000000001',4,'Chapitre 3','Négocier pacifiquement avec Rinnella','Éviter le combat et faire connaître le soutien de son église. Le sponsor peut être les Célébrants.','Blood Lords #4 — The Ghouls Hunger, p. 53',11,'v4-rinnella','[{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount":2},{"label":"Faction marraine","scope":"any","amount":3}]'),
  ('00000000-0000-4000-8700-000000000043','00000000-0000-4000-8000-000000000001',4,'Chapitre 3','Provoquer un combat avec Rinnella','La rencontre dégénère en combat et atteint aussi la faction marraine.','Blood Lords #4 — The Ghouls Hunger, p. 53',12,'v4-rinnella','[{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount":-2},{"label":"Faction marraine","scope":"any","amount":-1}]'),
  ('00000000-0000-4000-8700-000000000044','00000000-0000-4000-8000-000000000001',4,'Chapitre 3','Défier Hyrune avec éclat','Un succès accorde 1 RP aux deux factions, une réussite critique en accorde 2.','Blood Lords #4 — The Ghouls Hunger, p. 55',13,null,'[{"label":"Célébrants et Percepteurs","faction_ids":["00000000-0000-4000-8100-000000000102","00000000-0000-4000-8100-000000000105"],"amount_min":1,"amount_max":2}]')
on conflict (id) do update set
  volume = excluded.volume,
  chapter = excluded.chapter,
  title = excluded.title,
  condition = excluded.condition,
  source_reference = excluded.source_reference,
  sort_order = excluded.sort_order,
  choice_group = excluded.choice_group,
  reward_effects = excluded.reward_effects;

insert into public.reputation_milestones
  (id, campaign_id, volume, chapter, title, condition, source_reference,
   sort_order, choice_group, reward_effects)
values
  ('00000000-0000-4000-8700-000000000006','00000000-0000-4000-8000-000000000001',2,'Chapitre 1','Remettre le carnet de Gessamon aux Convoyeurs','Transmettre le carnet compromettant au Consortium des Convoyeurs.','Blood Lords #2 — Graveclaw, p. 13',1,null,'[{"label":"Convoyeurs","faction_id":"00000000-0000-4000-8100-000000000106","amount":1}]'),
  ('00000000-0000-4000-8700-000000000007','00000000-0000-4000-8000-000000000001',2,'Chapitre 2','Remettre les comptes à Gishkar','Donner les documents financiers de Sahni à Gishkar.','Blood Lords #2 — Graveclaw, p. 25',2,'v2-sahni-records','[{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount":2}]'),
  ('00000000-0000-4000-8700-000000000008','00000000-0000-4000-8000-000000000001',2,'Chapitre 2','Rapporter l’anneau à Tobias','Retrouver l’anneau dans le repaire de Sahni et le rendre à Tobias.','Blood Lords #2 — Graveclaw, p. 26',3,'v2-tobias-ring','[{"label":"Percepteurs","faction_id":"00000000-0000-4000-8100-000000000105","amount":3}]'),
  ('00000000-0000-4000-8700-000000000009','00000000-0000-4000-8000-000000000001',2,'Chapitre 2','Refuser d’aider Tobias','Refuser explicitement de récupérer ou de rendre l’anneau.','Blood Lords #2 — Graveclaw, p. 26',4,'v2-tobias-ring','[{"label":"Percepteurs","faction_id":"00000000-0000-4000-8100-000000000105","amount":-1}]'),
  ('00000000-0000-4000-8700-000000000010','00000000-0000-4000-8000-000000000001',2,'Chapitre 2','Donner la potion d’annulation à Stana','Remettre à Stana la potion trouvée dans le repaire de Sahni.','Blood Lords #2 — Graveclaw, p. 27',5,'v2-annulment-potion','[{"label":"Bâtisseurs","faction_id":"00000000-0000-4000-8100-000000000101","amount":3}]'),
  ('00000000-0000-4000-8700-000000000011','00000000-0000-4000-8000-000000000001',2,'Chapitre 2','Donner la potion à une autre faction','Choisir une autre faction que les Bâtisseurs pour recevoir la potion.','Blood Lords #2 — Graveclaw, p. 27',6,'v2-annulment-potion','[{"label":"Faction bénéficiaire","scope":"any","exclude_faction_ids":["00000000-0000-4000-8100-000000000101"],"amount":1},{"label":"Bâtisseurs","faction_id":"00000000-0000-4000-8100-000000000101","amount":-1}]'),
  ('00000000-0000-4000-8700-000000000012','00000000-0000-4000-8000-000000000001',2,'Chapitre 2','Remettre les comptes à Stana','Donner à Stana les documents également recherchés par Gishkar.','Blood Lords #2 — Graveclaw, p. 27',7,'v2-sahni-records','[{"label":"Bâtisseurs","faction_id":"00000000-0000-4000-8100-000000000101","amount":1},{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount":-1}]'),
  ('00000000-0000-4000-8700-000000000013','00000000-0000-4000-8000-000000000001',2,'Chapitre 3','Laisser partir le chariot','Ne pas éliminer le conducteur du chariot quittant Pagked.','Blood Lords #2 — Graveclaw, p. 41',8,'v2-pagked-wagon','[{"label":"Convoyeurs","faction_id":"00000000-0000-4000-8100-000000000106","amount":1}]'),
  ('00000000-0000-4000-8700-000000000014','00000000-0000-4000-8000-000000000001',2,'Chapitre 3','Éliminer le conducteur du chariot','Empêcher le chariot de partir en éliminant son conducteur.','Blood Lords #2 — Graveclaw, p. 41',9,'v2-pagked-wagon','[{"label":"Convoyeurs","faction_id":"00000000-0000-4000-8100-000000000106","amount":-1}]'),
  ('00000000-0000-4000-8700-000000000015','00000000-0000-4000-8000-000000000001',2,'Chapitre 3','Écarter Decrosia sans contrer le Shroud','Tuer ou chasser Decrosia et laisser le Shroud prendre le contrôle de Pagked.','Blood Lords #2 — Graveclaw, p. 47',10,null,'[{"label":"Convoyeurs","faction_id":"00000000-0000-4000-8100-000000000106","amount":2}]'),
  ('00000000-0000-4000-8700-000000000016','00000000-0000-4000-8000-000000000001',2,'Chapitre 4','Suivre les entreprises de Zthni','Le gain correspond au plus grand nombre d’entreprises accomplies par un PJ, jusqu’à cinq.','Blood Lords #2 — Graveclaw, p. 60',11,null,'[{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount_min":1,"amount_max":5}]'),
  ('00000000-0000-4000-8700-000000000017','00000000-0000-4000-8000-000000000001',2,'Chapitre 4','Jouer au Prix du Sang avec Kyril','Gagner 1 RP par PJ participant, plus 1 si Kyril ne remporte pas la partie.','Blood Lords #2 — Graveclaw, p. 61',12,null,'[{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount_min":1,"amount_max":10}]'),
  ('00000000-0000-4000-8700-000000000018','00000000-0000-4000-8000-000000000001',2,'Chapitre 4','Livrer Nathnelma à Zthni','Remettre Nathnelma vivante à Zthni.','Blood Lords #2 — Graveclaw, p. 66',13,'v2-nathnelma','[{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount":3},{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount":-1}]'),
  ('00000000-0000-4000-8700-000000000019','00000000-0000-4000-8000-000000000001',2,'Chapitre 4','Livrer Nathnelma à Kyril','Remettre Nathnelma vivante à Kyril.','Blood Lords #2 — Graveclaw, p. 66',14,'v2-nathnelma','[{"label":"Exportateurs","faction_id":"00000000-0000-4000-8100-000000000103","amount":3},{"label":"Célébrants","faction_id":"00000000-0000-4000-8100-000000000102","amount":-1}]'),
  ('00000000-0000-4000-8700-000000000020','00000000-0000-4000-8000-000000000001',2,'Chapitre 4','Briser la coven Graveclaw','Berline accorde cette récompense quelle que soit la destinée de Nathnelma.','Blood Lords #2 — Graveclaw, p. 66',15,null,'[{"label":"Réanimateurs","faction_id":"00000000-0000-4000-8100-000000000104","amount":3}]')
on conflict (id) do update set
  volume = excluded.volume,
  chapter = excluded.chapter,
  title = excluded.title,
  condition = excluded.condition,
  source_reference = excluded.source_reference,
  sort_order = excluded.sort_order,
  choice_group = excluded.choice_group,
  reward_effects = excluded.reward_effects;
