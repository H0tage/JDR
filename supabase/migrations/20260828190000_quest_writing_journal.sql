-- Journal de quête collaboratif par blocs. Il est distinct du Carnet de
-- notes : les anciennes entrées quest_entries restent donc inchangées.

create table if not exists public.quest_journal_documents (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  title text not null check (length(btrim(title)) > 0),
  occurred_on date not null default current_date,
  sort_order integer not null default 0,
  is_collapsed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists quest_journal_documents_campaign_order_idx
  on public.quest_journal_documents (campaign_id, occurred_on desc, sort_order, created_at desc);

create table if not exists public.quest_journal_blocks (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  document_id uuid not null references public.quest_journal_documents(id) on delete cascade,
  kind text not null default 'paragraph'
    check (kind in ('paragraph', 'heading', 'callout', 'quote', 'toggle', 'divider')),
  content text not null default '',
  label text,
  sort_order integer not null default 0,
  is_locked boolean not null default false,
  is_collapsed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists quest_journal_blocks_document_order_idx
  on public.quest_journal_blocks (document_id, sort_order);

drop trigger if exists quest_journal_documents_touch on public.quest_journal_documents;
create trigger quest_journal_documents_touch before update on public.quest_journal_documents
  for each row execute function public.touch_updated_at();

drop trigger if exists quest_journal_blocks_touch on public.quest_journal_blocks;
create trigger quest_journal_blocks_touch before update on public.quest_journal_blocks
  for each row execute function public.touch_updated_at();

alter table public.quest_journal_documents enable row level security;
alter table public.quest_journal_blocks enable row level security;

grant select, insert, update, delete on public.quest_journal_documents to anon, authenticated;
grant select, insert, update, delete on public.quest_journal_blocks to anon, authenticated;

drop policy if exists quest_journal_documents_public_manage on public.quest_journal_documents;
create policy quest_journal_documents_public_manage on public.quest_journal_documents
  for all to anon, authenticated
  using (public.is_public_campaign(campaign_id))
  with check (public.is_public_campaign(campaign_id));

drop policy if exists quest_journal_blocks_public_manage on public.quest_journal_blocks;
create policy quest_journal_blocks_public_manage on public.quest_journal_blocks
  for all to anon, authenticated
  using (public.is_public_campaign(campaign_id))
  with check (public.is_public_campaign(campaign_id));

-- Synchronisation temps réel entre la vue joueurs et l’écran MJ. Le contrôle
-- rend la migration réexécutable sans erreur si elle a déjà été appliquée.
do $$
begin
  if not exists (
    select 1 from pg_publication_rel pr
    join pg_publication p on p.oid = pr.prpubid
    where p.pubname = 'supabase_realtime'
      and pr.prrelid = 'public.quest_journal_documents'::regclass
  ) then
    alter publication supabase_realtime add table public.quest_journal_documents;
  end if;

  if not exists (
    select 1 from pg_publication_rel pr
    join pg_publication p on p.oid = pr.prpubid
    where p.pubname = 'supabase_realtime'
      and pr.prrelid = 'public.quest_journal_blocks'::regclass
  ) then
    alter publication supabase_realtime add table public.quest_journal_blocks;
  end if;
end $$;
