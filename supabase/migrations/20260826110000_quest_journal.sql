-- Journal de quête collaboratif. Il est volontairement distinct du journal
-- de réputation : ces notes ne modifient ni RP, ni faveurs, ni tension.

create table if not exists public.quest_entries (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  title text not null check (length(btrim(title)) > 0),
  notes text,
  status text not null default 'À faire' check (status in ('À faire', 'En cours', 'Terminé')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists quest_entries_campaign_order_idx
  on public.quest_entries (campaign_id, sort_order, created_at);

drop trigger if exists quest_entries_touch on public.quest_entries;
create trigger quest_entries_touch before update on public.quest_entries
  for each row execute function public.touch_updated_at();

alter table public.quest_entries enable row level security;
grant select, insert, update, delete on public.quest_entries to anon, authenticated;

drop policy if exists quest_entries_public_manage on public.quest_entries;
create policy quest_entries_public_manage on public.quest_entries
  for all to anon, authenticated
  using (public.is_public_campaign(campaign_id))
  with check (public.is_public_campaign(campaign_id));
