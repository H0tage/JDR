-- Le Journal appartient aussi aux joueurs : ses versions précédentes sont
-- donc consultables et restaurables par toute personne ayant accès à la
-- campagne publique. Les historiques restent limités à cette campagne.

grant select on public.quest_journal_revisions to anon, authenticated;

drop policy if exists quest_journal_revisions_public_read on public.quest_journal_revisions;
create policy quest_journal_revisions_public_read on public.quest_journal_revisions
  for select to anon, authenticated
  using (public.is_public_campaign(campaign_id));
