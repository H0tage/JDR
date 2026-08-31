-- Notes privées et persistantes de préparation de la prochaine séance.
create table if not exists public.campaign_session_preps (
  campaign_id uuid primary key references public.campaigns(id) on delete cascade,
  objective text,
  scenes text,
  reminders text,
  notes text,
  updated_at timestamptz not null default now()
);

drop trigger if exists campaign_session_preps_touch on public.campaign_session_preps;
create trigger campaign_session_preps_touch
  before update on public.campaign_session_preps
  for each row execute function public.touch_updated_at();

alter table public.campaign_session_preps enable row level security;

drop policy if exists campaign_session_preps_gm_all on public.campaign_session_preps;
create policy campaign_session_preps_gm_all
  on public.campaign_session_preps for all to authenticated
  using (public.is_campaign_gm(campaign_id))
  with check (public.is_campaign_gm(campaign_id));

grant select, insert, update, delete on public.campaign_session_preps to authenticated;

insert into public.campaign_session_preps (campaign_id)
select id from public.campaigns
on conflict (campaign_id) do nothing;
