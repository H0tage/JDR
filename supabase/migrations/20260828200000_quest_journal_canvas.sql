-- Journal de quête : une page de texte continue, avec sections repliables
-- indexées automatiquement côté interface.

create table if not exists public.quest_journal_pages (
  campaign_id uuid primary key references public.campaigns(id) on delete cascade,
  content text not null default '',
  updated_at timestamptz not null default now()
);

drop trigger if exists quest_journal_pages_touch on public.quest_journal_pages;
create trigger quest_journal_pages_touch before update on public.quest_journal_pages
  for each row execute function public.touch_updated_at();

alter table public.quest_journal_pages enable row level security;
grant select, insert, update, delete on public.quest_journal_pages to anon, authenticated;

drop policy if exists quest_journal_pages_public_manage on public.quest_journal_pages;
create policy quest_journal_pages_public_manage on public.quest_journal_pages
  for all to anon, authenticated
  using (public.is_public_campaign(campaign_id))
  with check (public.is_public_campaign(campaign_id));

do $$
begin
  if not exists (
    select 1 from pg_publication_rel pr
    join pg_publication p on p.oid = pr.prpubid
    where p.pubname = 'supabase_realtime'
      and pr.prrelid = 'public.quest_journal_pages'::regclass
  ) then
    alter publication supabase_realtime add table public.quest_journal_pages;
  end if;
end $$;
