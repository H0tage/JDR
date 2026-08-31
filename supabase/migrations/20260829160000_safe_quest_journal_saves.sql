-- Le Journal est un document partagé : une sauvegarde ancienne ne doit jamais
-- écraser silencieusement une version plus récente.

alter table public.quest_journal_pages
  add column if not exists revision integer not null default 0;

-- L’écriture passe désormais par une fonction qui vérifie la révision connue
-- par le navigateur. Les droits directs sont retirés afin de ne pas contourner
-- cette vérification.
revoke insert, update, delete on public.quest_journal_pages from anon, authenticated;

create or replace function public.save_quest_journal_page(
  target_campaign_id uuid,
  expected_revision integer,
  next_content text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  next_revision integer;
begin
  if not public.is_public_campaign(target_campaign_id) then
    raise exception 'Journal indisponible pour cette campagne';
  end if;

  update public.quest_journal_pages
  set content = next_content,
      revision = revision + 1
  where campaign_id = target_campaign_id
    and revision = expected_revision
  returning revision into next_revision;

  if found then return next_revision; end if;

  -- Une campagne ancienne peut ne pas encore avoir de ligne de Journal.
  if expected_revision = 0 then
    begin
      insert into public.quest_journal_pages (campaign_id, content, revision)
      values (target_campaign_id, next_content, 1)
      returning revision into next_revision;
      return next_revision;
    exception when unique_violation then
      -- Une autre fenêtre vient de créer la page : le conflit est signalé
      -- juste après, sans perdre le contenu local.
    end;
  end if;

  raise exception 'Le Journal a été modifié dans une autre fenêtre'
    using errcode = '40001';
end;
$$;

revoke all on function public.save_quest_journal_page(uuid, integer, text) from public;
grant execute on function public.save_quest_journal_page(uuid, integer, text) to anon, authenticated;

-- Les versions restent récupérables longtemps, y compris après une journée de
-- prises de notes. Le déclencheur existant garde l’état précédent à chaque
-- écriture, donc aussi avant toute restauration.
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
      offset 100
    );
  return new;
end;
$$;

-- L’historique fait partie du Journal partagé : cette déclaration rend la
-- migration indépendante de celle qui l’ouvre pour la première fois.
grant select on public.quest_journal_revisions to anon, authenticated;
drop policy if exists quest_journal_revisions_public_read on public.quest_journal_revisions;
create policy quest_journal_revisions_public_read on public.quest_journal_revisions
  for select to anon, authenticated
  using (public.is_public_campaign(campaign_id));
