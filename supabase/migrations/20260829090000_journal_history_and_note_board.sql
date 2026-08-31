-- Le Carnet de notes devient un tableau de post-it partagé. Les anciennes
-- entrées sont conservées et réparties dans une colonne cohérente.
alter table public.quest_entries
  add column if not exists category text;

-- La contrainte historique ne connaît pas les nouveaux états : il faut la
-- retirer avant de convertir les valeurs déjà enregistrées.
alter table public.quest_entries
  drop constraint if exists quest_entries_status_check;

update public.quest_entries
set category = case status
  when 'À faire' then 'Pistes'
  when 'En cours' then 'Objectifs'
  else 'Informations'
end
where category is null;

update public.quest_entries
set status = case status
  when 'Terminé' then 'Résolu'
  else 'Actif'
end
where status in ('À faire', 'En cours', 'Terminé');

alter table public.quest_entries
  alter column category set default 'Pistes',
  alter column category set not null,
  alter column status set default 'Actif';

alter table public.quest_entries
  drop constraint if exists quest_entries_category_check,
  add constraint quest_entries_status_check check (status in ('Actif', 'Résolu', 'Abandonné')),
  add constraint quest_entries_category_check check (category in ('Pistes', 'Objectifs', 'Questions', 'Informations'));

-- Les instantanés permettent au MJ de restaurer le Journal sans exposer les
-- versions précédentes aux joueurs. Le déclencheur les crée aussi lors d’une
-- modification effectuée depuis la vue joueurs.
create table if not exists public.quest_journal_revisions (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

create index if not exists quest_journal_revisions_campaign_created_idx
  on public.quest_journal_revisions (campaign_id, created_at desc);

alter table public.quest_journal_revisions enable row level security;
revoke all on public.quest_journal_revisions from anon;
grant select on public.quest_journal_revisions to authenticated;

drop policy if exists quest_journal_revisions_gm_read on public.quest_journal_revisions;
create policy quest_journal_revisions_gm_read on public.quest_journal_revisions
  for select to authenticated
  using (public.is_campaign_gm(campaign_id));

create or replace function public.capture_quest_journal_revision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.content is not distinct from new.content then return new; end if;

  insert into public.quest_journal_revisions (campaign_id, content)
  values (old.campaign_id, old.content);

  delete from public.quest_journal_revisions revision
  where revision.campaign_id = new.campaign_id
    and revision.id in (
      select id
      from public.quest_journal_revisions
      where campaign_id = new.campaign_id
      order by created_at desc, id desc
      offset 20
    );
  return new;
end;
$$;

revoke all on function public.capture_quest_journal_revision() from public;

drop trigger if exists quest_journal_pages_revision on public.quest_journal_pages;
create trigger quest_journal_pages_revision
  after update of content on public.quest_journal_pages
  for each row execute function public.capture_quest_journal_revision();

-- Audit de frontière : le Journal et le Carnet sont volontairement les seules
-- tables de prise de notes accessibles à anon. Les archives, fiches MJ,
-- dossiers, contacts privés et sources restent sans droit anon et sont servis
-- uniquement par les vues player_* déjà filtrées.
revoke all on public.quest_journal_revisions from anon;
