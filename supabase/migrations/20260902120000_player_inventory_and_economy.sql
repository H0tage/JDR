-- Nom conseillé dans le SQL Editor : Inventaire joueur et économie partagée
--
-- Couche opérationnelle générique, séparée du référentiel MJ. Cette migration
-- ne contient aucune donnée de campagne et ne révèle donc aucun spoiler.

alter table public.campaign_settings
  add column if not exists show_all_player_balances boolean not null default false;

create or replace view public.player_campaign
with (security_barrier = true)
as
select c.id as campaign_id, c.slug, c.name, c.description,
  s.current_volume, s.jf_cap, s.minor_cost, s.moderate_cost, s.major_cost,
  s.liked_threshold, s.admired_threshold, s.revered_threshold,
  s.carters_major_threshold, s.tension_max, s.show_numeric_tension,
  s.player_display_mode, s.show_all_player_balances
from public.campaigns c
join public.campaign_settings s on s.campaign_id = c.id
where public.is_campaign_member(c.id);

create table if not exists public.campaign_inventory_items (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  origin_loot_id uuid references public.campaign_loot(id) on delete set null,
  parent_item_id uuid references public.campaign_inventory_items(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  owner_user_id uuid references auth.users(id) on delete set null,
  name text not null check (length(btrim(name)) between 1 and 240),
  quantity numeric(14,4) not null default 1 check (quantity > 0),
  source_quantity_label text,
  unit_value_cp bigint check (unit_value_cp is null or unit_value_cp >= 0),
  purchase_price_cp bigint check (purchase_price_cp is null or purchase_price_cp >= 0),
  aon_legacy_name text,
  aon_legacy_url text,
  source_kind text not null default 'loot'
    check (source_kind in ('loot', 'gm', 'purchase', 'dismantle')),
  player_visible boolean not null default true,
  status text not null default 'active'
    check (status in ('active', 'sold', 'dismantled', 'consumed', 'lost', 'donated', 'merged')),
  acquired_on date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists campaign_inventory_items_campaign_status_idx
  on public.campaign_inventory_items(campaign_id, status, owner_user_id, acquired_on desc);
create index if not exists campaign_inventory_items_origin_idx
  on public.campaign_inventory_items(origin_loot_id);
create index if not exists campaign_inventory_items_parent_idx
  on public.campaign_inventory_items(parent_item_id);
alter table public.campaign_inventory_items enable row level security;

drop trigger if exists campaign_inventory_items_touch on public.campaign_inventory_items;
create trigger campaign_inventory_items_touch before update on public.campaign_inventory_items
  for each row execute function public.touch_updated_at();

create table if not exists public.campaign_money_transactions (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  kind text not null check (kind in (
    'common_income', 'personal_income', 'personal_expense', 'transfer',
    'sale', 'purchase', 'reversal', 'departure_transfer', 'gm_adjustment'
  )),
  source_account text not null check (source_account in ('external', 'common', 'player')),
  source_user_id uuid references auth.users(id) on delete set null,
  destination_account text not null check (destination_account in ('external', 'common', 'player')),
  destination_user_id uuid references auth.users(id) on delete set null,
  amount_cp bigint not null check (amount_cp > 0),
  comment text check (comment is null or length(comment) <= 500),
  related_item_id uuid references public.campaign_inventory_items(id) on delete set null,
  reversed_transaction_id uuid references public.campaign_money_transactions(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (source_account <> destination_account or source_account = 'player'),
  check ((source_account = 'player') = (source_user_id is not null)),
  check ((destination_account = 'player') = (destination_user_id is not null)),
  check (source_account <> 'player' or destination_account <> 'player' or source_user_id <> destination_user_id)
);

create unique index if not exists campaign_money_transactions_reversal_idx
  on public.campaign_money_transactions(reversed_transaction_id)
  where reversed_transaction_id is not null;
create index if not exists campaign_money_transactions_campaign_date_idx
  on public.campaign_money_transactions(campaign_id, created_at desc);
create index if not exists campaign_money_transactions_operation_idx
  on public.campaign_money_transactions(operation_id);
alter table public.campaign_money_transactions enable row level security;

create table if not exists public.campaign_item_events (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  item_id uuid references public.campaign_inventory_items(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null check (event_type in (
    'created', 'published', 'claimed', 'transferred', 'returned', 'split', 'merged',
    'sold', 'sale_cancelled', 'purchased', 'dismantled', 'consumed', 'lost', 'donated'
  )),
  previous_owner_user_id uuid references auth.users(id) on delete set null,
  next_owner_user_id uuid references auth.users(id) on delete set null,
  quantity numeric(14,4),
  value_cp bigint,
  comment text check (comment is null or length(comment) <= 500),
  related_item_id uuid references public.campaign_inventory_items(id) on delete set null,
  money_operation_id uuid,
  reversed_event_id uuid references public.campaign_item_events(id) on delete restrict,
  created_at timestamptz not null default now()
);

create unique index if not exists campaign_item_events_reversal_idx
  on public.campaign_item_events(reversed_event_id)
  where reversed_event_id is not null;
create index if not exists campaign_item_events_item_date_idx
  on public.campaign_item_events(item_id, created_at desc);
create index if not exists campaign_item_events_campaign_date_idx
  on public.campaign_item_events(campaign_id, created_at desc);
alter table public.campaign_item_events enable row level security;

create table if not exists public.campaign_item_requests (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  item_id uuid not null references public.campaign_inventory_items(id) on delete cascade,
  requester_user_id uuid not null references auth.users(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'refused', 'cancelled', 'invalidated')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (item_id, requester_user_id, status)
);

create index if not exists campaign_item_requests_participants_idx
  on public.campaign_item_requests(campaign_id, owner_user_id, requester_user_id, status, created_at desc);
alter table public.campaign_item_requests enable row level security;

create table if not exists public.campaign_money_debts (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  debtor_user_id uuid not null references auth.users(id) on delete cascade,
  creditor_user_id uuid not null references auth.users(id) on delete cascade,
  amount_cp bigint not null check (amount_cp > 0),
  remaining_cp bigint not null check (remaining_cp >= 0 and remaining_cp <= amount_cp),
  status text not null default 'open' check (status in ('open', 'settled', 'cancelled')),
  comment text check (comment is null or length(comment) <= 500),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (debtor_user_id <> creditor_user_id)
);

create index if not exists campaign_money_debts_campaign_status_idx
  on public.campaign_money_debts(campaign_id, status, created_at desc);
alter table public.campaign_money_debts enable row level security;

drop trigger if exists campaign_money_debts_touch on public.campaign_money_debts;
create trigger campaign_money_debts_touch before update on public.campaign_money_debts
  for each row execute function public.touch_updated_at();

-- Les publications existantes deviennent des objets opérationnels sans
-- modifier le référentiel MJ ni ses 523 entrées.
insert into public.campaign_inventory_items (
  campaign_id, origin_loot_id, owner_user_id, name, quantity,
  source_quantity_label, unit_value_cp, aon_legacy_name, aon_legacy_url,
  source_kind, status, acquired_on
)
select
  loot.campaign_id,
  loot.id,
  case when publication.lifecycle_status = 'assigned' then publication.owner_user_id else null end,
  loot.item_name,
  case
    when loot.quantity_recoverable ~ '^[0-9]+([.,][0-9]+)?$'
      then replace(loot.quantity_recoverable, ',', '.')::numeric
    else 1
  end,
  loot.quantity_recoverable,
  case
    when loot.book_unit_value_amount is not null then round(loot.book_unit_value_amount * case loot.book_unit_value_currency when 'pp' then 1000 when 'gp' then 100 when 'sp' then 10 else 1 end)::bigint
    when loot.aon_legacy_unit_value_amount is not null then round(loot.aon_legacy_unit_value_amount * case loot.aon_legacy_unit_value_currency when 'pp' then 1000 when 'gp' then 100 when 'sp' then 10 else 1 end)::bigint
    else null
  end,
  loot.aon_legacy_name,
  loot.aon_legacy_url,
  'loot',
  case publication.lifecycle_status
    when 'sold' then 'sold'
    when 'dismantled' then 'dismantled'
    when 'consumed' then 'consumed'
    else 'active'
  end,
  publication.published_on
from public.campaign_loot loot
join public.loot_player_publications publication on publication.loot_id = loot.id
where not exists (
  select 1 from public.campaign_inventory_items item
  where item.origin_loot_id = loot.id and item.source_kind = 'loot'
);

insert into public.campaign_item_events (
  campaign_id, item_id, event_type, next_owner_user_id, quantity, value_cp, created_at
)
select item.campaign_id, item.id, 'published', item.owner_user_id,
  item.quantity, item.unit_value_cp, item.acquired_on::timestamptz
from public.campaign_inventory_items item
where item.origin_loot_id is not null
  and not exists (
    select 1 from public.campaign_item_events event
    where event.item_id = item.id and event.event_type = 'published'
  );

create or replace view public.player_inventory_items
with (security_barrier = true)
as
select
  item.*,
  owner_profile.display_name as owner_display_name,
  creator_profile.display_name as created_by_display_name,
  coalesce(request_totals.pending_request_count, 0)::integer as pending_request_count,
  exists (
    select 1 from public.campaign_item_requests request
    where request.item_id = item.id
      and request.requester_user_id = auth.uid()
      and request.status = 'pending'
  ) as requested_by_me
from public.campaign_inventory_items item
left join public.user_profiles owner_profile on owner_profile.user_id = item.owner_user_id
left join public.user_profiles creator_profile on creator_profile.user_id = item.created_by
left join lateral (
  select count(*) pending_request_count
  from public.campaign_item_requests request
  where request.item_id = item.id and request.status = 'pending'
) request_totals on true
where item.player_visible and public.is_campaign_member(item.campaign_id);

create or replace view public.player_money_balances
with (security_barrier = true)
as
with accounts as (
  select campaign.id as campaign_id, null::uuid as account_user_id,
    'Pot commun'::text as display_name, true as is_common
  from public.campaigns campaign
  where public.is_campaign_member(campaign.id)
  union all
  select member.campaign_id, member.user_id,
    coalesce(profile.display_name, 'Joueur') as display_name, false as is_common
  from public.campaign_members member
  left join public.user_profiles profile on profile.user_id = member.user_id
  where member.role = 'player' and public.is_campaign_member(member.campaign_id)
)
select account.campaign_id, account.account_user_id, account.display_name,
  account.is_common,
  coalesce(sum(
    case
      when transaction.destination_account = case when account.is_common then 'common' else 'player' end
        and (account.is_common or transaction.destination_user_id = account.account_user_id)
        then transaction.amount_cp
      when transaction.source_account = case when account.is_common then 'common' else 'player' end
        and (account.is_common or transaction.source_user_id = account.account_user_id)
        then -transaction.amount_cp
      else 0
    end
  ), 0)::bigint as balance_cp
from accounts account
join public.campaign_settings settings on settings.campaign_id = account.campaign_id
left join public.campaign_money_transactions transaction on transaction.campaign_id = account.campaign_id
where account.is_common
  or account.account_user_id = auth.uid()
  or public.is_campaign_gm(account.campaign_id)
  or settings.show_all_player_balances
group by account.campaign_id, account.account_user_id, account.display_name, account.is_common;

create or replace view public.player_money_history
with (security_barrier = true)
as
select transaction.*,
  actor_profile.display_name as actor_display_name,
  source_profile.display_name as source_display_name,
  destination_profile.display_name as destination_display_name,
  item.name as related_item_name
from public.campaign_money_transactions transaction
join public.campaign_settings settings on settings.campaign_id = transaction.campaign_id
left join public.user_profiles actor_profile on actor_profile.user_id = transaction.actor_user_id
left join public.user_profiles source_profile on source_profile.user_id = transaction.source_user_id
left join public.user_profiles destination_profile on destination_profile.user_id = transaction.destination_user_id
left join public.campaign_inventory_items item on item.id = transaction.related_item_id
where public.is_campaign_member(transaction.campaign_id)
  and (
    transaction.related_item_id is null
    or item.player_visible
    or public.is_campaign_gm(transaction.campaign_id)
  )
  and (
    public.is_campaign_gm(transaction.campaign_id)
    or settings.show_all_player_balances
    or transaction.source_account = 'common'
    or transaction.destination_account = 'common'
    or transaction.source_user_id = auth.uid()
    or transaction.destination_user_id = auth.uid()
    or transaction.actor_user_id = auth.uid()
  );

create or replace view public.player_economy_totals
with (security_barrier = true)
as
select campaign.id as campaign_id,
  (
    coalesce((
      select sum(
        case
          when event.event_type in ('published', 'created')
            and (event.event_type <> 'created' or event.related_item_id is null)
            then coalesce(event.value_cp, 0) * coalesce(event.quantity, 1)
          when event.event_type in ('purchased', 'sale_cancelled')
            then coalesce(event.value_cp, 0)
          else 0
        end
      )
      from public.campaign_item_events event
      where event.campaign_id = campaign.id
        and exists (
          select 1 from public.campaign_inventory_items visible_item
          where visible_item.id = event.item_id
            and (visible_item.player_visible or public.is_campaign_gm(campaign.id))
        )
    ), 0)
    + coalesce((
      select sum(transaction.amount_cp)
      from public.campaign_money_transactions transaction
      where transaction.campaign_id = campaign.id
        and transaction.source_account = 'external'
        and (
          transaction.related_item_id is null
          or exists (
            select 1 from public.campaign_inventory_items visible_item
            where visible_item.id = transaction.related_item_id
              and (visible_item.player_visible or public.is_campaign_gm(campaign.id))
          )
        )
    ), 0)
  )::bigint as total_entered_cp,
  (
    coalesce((
      select sum(
        case
          when event.event_type in ('sold', 'consumed', 'lost', 'donated')
            then coalesce(event.value_cp, 0)
          else 0
        end
      )
      from public.campaign_item_events event
      where event.campaign_id = campaign.id
        and exists (
          select 1 from public.campaign_inventory_items visible_item
          where visible_item.id = event.item_id
            and (visible_item.player_visible or public.is_campaign_gm(campaign.id))
        )
    ), 0)
    + coalesce((
      select sum(transaction.amount_cp)
      from public.campaign_money_transactions transaction
      where transaction.campaign_id = campaign.id
        and transaction.destination_account = 'external'
        and (
          transaction.related_item_id is null
          or exists (
            select 1 from public.campaign_inventory_items visible_item
            where visible_item.id = transaction.related_item_id
              and (visible_item.player_visible or public.is_campaign_gm(campaign.id))
          )
        )
    ), 0)
  )::bigint as total_exited_cp
from public.campaigns campaign
where public.is_campaign_member(campaign.id);

create or replace view public.player_item_history
with (security_barrier = true)
as
select event.*,
  item.name as item_name,
  related.name as related_item_name,
  actor_profile.display_name as actor_display_name,
  previous_profile.display_name as previous_owner_display_name,
  next_profile.display_name as next_owner_display_name
from public.campaign_item_events event
left join public.campaign_inventory_items item on item.id = event.item_id
left join public.campaign_inventory_items related on related.id = event.related_item_id
left join public.user_profiles actor_profile on actor_profile.user_id = event.actor_user_id
left join public.user_profiles previous_profile on previous_profile.user_id = event.previous_owner_user_id
left join public.user_profiles next_profile on next_profile.user_id = event.next_owner_user_id
where public.is_campaign_member(event.campaign_id)
  and (
    public.is_campaign_gm(event.campaign_id)
    or coalesce(item.player_visible, related.player_visible, false)
  );

create or replace view public.player_item_request_overview
with (security_barrier = true)
as
select request.*,
  item.name as item_name,
  requester.display_name as requester_display_name,
  owner.display_name as owner_display_name
from public.campaign_item_requests request
join public.campaign_inventory_items item on item.id = request.item_id
left join public.user_profiles requester on requester.user_id = request.requester_user_id
left join public.user_profiles owner on owner.user_id = request.owner_user_id
where public.is_campaign_member(request.campaign_id)
  and (
    request.requester_user_id = auth.uid()
    or request.owner_user_id = auth.uid()
    or public.is_campaign_gm(request.campaign_id)
  );

create or replace view public.player_money_debt_overview
with (security_barrier = true)
as
select debt.*,
  debtor.display_name as debtor_display_name,
  creditor.display_name as creditor_display_name
from public.campaign_money_debts debt
left join public.user_profiles debtor on debtor.user_id = debt.debtor_user_id
left join public.user_profiles creditor on creditor.user_id = debt.creditor_user_id
join public.campaign_settings settings on settings.campaign_id = debt.campaign_id
where public.is_campaign_member(debt.campaign_id)
  and (
    public.is_campaign_gm(debt.campaign_id)
    or settings.show_all_player_balances
    or debt.debtor_user_id = auth.uid()
    or debt.creditor_user_id = auth.uid()
  );

create or replace function public.is_active_campaign_player(
  p_campaign_id uuid,
  p_user_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user_id is not null and exists (
    select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id
      and member.user_id = p_user_id
      and member.role = 'player'
  );
$$;

create or replace function public.can_control_campaign_item(
  p_item_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.campaign_inventory_items item
    where item.id = p_item_id
      and item.status = 'active'
      and public.is_campaign_member(item.campaign_id)
      and (item.player_visible or public.is_campaign_gm(item.campaign_id))
      and (
        public.is_campaign_gm(item.campaign_id)
        or item.owner_user_id is null
        or item.owner_user_id = auth.uid()
      )
  );
$$;

create or replace function public.assign_campaign_item(
  p_item_id uuid,
  p_target_user_id uuid,
  p_comment text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.campaign_inventory_items%rowtype;
  v_event_type text;
begin
  select * into v_item from public.campaign_inventory_items where id = p_item_id for update;
  if v_item.id is null or not public.can_control_campaign_item(p_item_id) then
    raise exception 'Vous ne pouvez pas attribuer cet objet';
  end if;
  if not public.is_active_campaign_player(v_item.campaign_id, p_target_user_id) then
    raise exception 'Destinataire invalide';
  end if;
  if v_item.owner_user_id = p_target_user_id then return; end if;

  v_event_type := case
    when v_item.owner_user_id is null and p_target_user_id = auth.uid() then 'claimed'
    else 'transferred'
  end;

  update public.campaign_inventory_items
  set owner_user_id = p_target_user_id
  where id = p_item_id;

  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type,
    previous_owner_user_id, next_owner_user_id, quantity, comment
  ) values (
    v_item.campaign_id, p_item_id, auth.uid(), v_event_type,
    v_item.owner_user_id, p_target_user_id, v_item.quantity, nullif(btrim(p_comment), '')
  );

  update public.campaign_item_requests
  set status = 'invalidated', resolved_at = now()
  where item_id = p_item_id and status = 'pending';
end;
$$;

create or replace function public.return_campaign_item_to_common(
  p_item_id uuid,
  p_comment text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_item public.campaign_inventory_items%rowtype;
begin
  select * into v_item from public.campaign_inventory_items where id = p_item_id for update;
  if v_item.id is null or v_item.status <> 'active'
    or not public.is_campaign_member(v_item.campaign_id)
    or not (public.is_campaign_gm(v_item.campaign_id) or v_item.owner_user_id = auth.uid()) then
    raise exception 'Vous ne pouvez pas remettre cet objet dans le pot commun';
  end if;
  if v_item.owner_user_id is null then return; end if;

  update public.campaign_inventory_items set owner_user_id = null where id = p_item_id;
  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type,
    previous_owner_user_id, quantity, comment
  ) values (
    v_item.campaign_id, p_item_id, auth.uid(), 'returned',
    v_item.owner_user_id, v_item.quantity, nullif(btrim(p_comment), '')
  );
  update public.campaign_item_requests
  set status = 'invalidated', resolved_at = now()
  where item_id = p_item_id and status = 'pending';
end;
$$;

create or replace function public.split_campaign_item(
  p_item_id uuid,
  p_quantity numeric
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.campaign_inventory_items%rowtype;
  v_new_id uuid;
begin
  select * into v_item from public.campaign_inventory_items where id = p_item_id for update;
  if v_item.id is null or not public.can_control_campaign_item(p_item_id) then
    raise exception 'Vous ne pouvez pas fractionner cet objet';
  end if;
  if p_quantity <= 0 or p_quantity >= v_item.quantity then
    raise exception 'Quantité à séparer invalide';
  end if;

  update public.campaign_inventory_items set quantity = quantity - p_quantity where id = p_item_id;
  insert into public.campaign_inventory_items (
    campaign_id, origin_loot_id, parent_item_id, created_by, owner_user_id,
    name, quantity, source_quantity_label, unit_value_cp, purchase_price_cp,
    aon_legacy_name, aon_legacy_url, source_kind, status, acquired_on
  ) values (
    v_item.campaign_id, v_item.origin_loot_id, coalesce(v_item.parent_item_id, v_item.id),
    auth.uid(), v_item.owner_user_id, v_item.name, p_quantity, p_quantity::text,
    v_item.unit_value_cp, v_item.purchase_price_cp, v_item.aon_legacy_name,
    v_item.aon_legacy_url, v_item.source_kind, 'active', v_item.acquired_on
  ) returning id into v_new_id;

  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type, quantity, related_item_id
  ) values (v_item.campaign_id, p_item_id, auth.uid(), 'split', p_quantity, v_new_id);
  return v_new_id;
end;
$$;

create or replace function public.merge_campaign_items(
  p_target_item_id uuid,
  p_source_item_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.campaign_inventory_items%rowtype;
  v_source public.campaign_inventory_items%rowtype;
begin
  if p_target_item_id = p_source_item_id then raise exception 'Objets identiques'; end if;
  select * into v_target from public.campaign_inventory_items where id = p_target_item_id for update;
  select * into v_source from public.campaign_inventory_items where id = p_source_item_id for update;
  if v_target.id is null or v_source.id is null
    or not public.can_control_campaign_item(p_target_item_id)
    or not public.can_control_campaign_item(p_source_item_id) then
    raise exception 'Fusion impossible';
  end if;
  if v_target.campaign_id <> v_source.campaign_id
    or v_target.name <> v_source.name
    or v_target.owner_user_id is distinct from v_source.owner_user_id
    or v_target.unit_value_cp is distinct from v_source.unit_value_cp
    or v_target.aon_legacy_url is distinct from v_source.aon_legacy_url then
    raise exception 'Seules deux piles équivalentes peuvent être fusionnées';
  end if;

  update public.campaign_inventory_items
  set quantity = quantity + v_source.quantity
  where id = p_target_item_id;
  update public.campaign_inventory_items
  set status = 'merged', owner_user_id = null
  where id = p_source_item_id;
  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type, quantity, related_item_id
  ) values (
    v_target.campaign_id, p_source_item_id, auth.uid(), 'merged',
    v_source.quantity, p_target_item_id
  );
  update public.campaign_item_requests
  set status = 'invalidated', resolved_at = now()
  where item_id = p_source_item_id and status = 'pending';
end;
$$;

create or replace function public.batch_update_campaign_items(
  p_item_ids uuid[],
  p_action text,
  p_target_user_id uuid default null,
  p_comment text default null
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item_id uuid;
  v_count integer := 0;
begin
  if coalesce(array_length(p_item_ids, 1), 0) = 0
    or array_length(p_item_ids, 1) > 100
    or p_action not in ('assign', 'return', 'consumed', 'lost', 'donated') then
    raise exception 'Action groupée invalide';
  end if;
  if p_action = 'assign' and p_target_user_id is null then
    raise exception 'Destinataire requis';
  end if;

  foreach v_item_id in array p_item_ids loop
    if p_action = 'assign' then
      perform public.assign_campaign_item(v_item_id, p_target_user_id, p_comment);
    elsif p_action = 'return' then
      perform public.return_campaign_item_to_common(v_item_id, p_comment);
    else
      perform public.set_campaign_item_terminal(v_item_id, p_action, null, p_comment);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.set_campaign_item_terminal(
  p_item_id uuid,
  p_status text,
  p_quantity numeric default null,
  p_comment text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.campaign_inventory_items%rowtype;
  v_terminal_id uuid;
  v_quantity numeric;
begin
  if p_status not in ('consumed', 'lost', 'donated') then
    raise exception 'État final invalide';
  end if;
  select * into v_item from public.campaign_inventory_items where id = p_item_id for update;
  if v_item.id is null or not public.can_control_campaign_item(p_item_id) then
    raise exception 'Vous ne pouvez pas modifier cet objet';
  end if;
  v_quantity := coalesce(p_quantity, v_item.quantity);
  if v_quantity <= 0 or v_quantity > v_item.quantity then raise exception 'Quantité invalide'; end if;

  if v_quantity = v_item.quantity then
    update public.campaign_inventory_items
    set status = p_status, owner_user_id = null
    where id = p_item_id;
    v_terminal_id := p_item_id;
  else
    update public.campaign_inventory_items set quantity = quantity - v_quantity where id = p_item_id;
    insert into public.campaign_inventory_items (
      campaign_id, origin_loot_id, parent_item_id, created_by, name, quantity,
      source_quantity_label, unit_value_cp, purchase_price_cp, aon_legacy_name,
      aon_legacy_url, source_kind, status, acquired_on
    ) values (
      v_item.campaign_id, v_item.origin_loot_id, coalesce(v_item.parent_item_id, v_item.id),
      auth.uid(), v_item.name, v_quantity, v_quantity::text, v_item.unit_value_cp,
      v_item.purchase_price_cp, v_item.aon_legacy_name, v_item.aon_legacy_url,
      v_item.source_kind, p_status, v_item.acquired_on
    ) returning id into v_terminal_id;
  end if;

  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type,
    previous_owner_user_id, quantity, value_cp, comment
  ) values (
    v_item.campaign_id, v_terminal_id, auth.uid(), p_status,
    v_item.owner_user_id, v_quantity,
    case when v_item.unit_value_cp is null then null else round(v_item.unit_value_cp * v_quantity)::bigint end,
    nullif(btrim(p_comment), '')
  );
  update public.campaign_item_requests
  set status = 'invalidated', resolved_at = now()
  where item_id = v_terminal_id and status = 'pending';
  return v_terminal_id;
end;
$$;

create or replace function public.sell_campaign_item(
  p_item_id uuid,
  p_quantity numeric,
  p_amount_cp bigint,
  p_comment text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.campaign_inventory_items%rowtype;
  v_sold_id uuid;
  v_event_id uuid;
  v_operation_id uuid := gen_random_uuid();
begin
  select * into v_item from public.campaign_inventory_items where id = p_item_id for update;
  if v_item.id is null or not public.can_control_campaign_item(p_item_id) then
    raise exception 'Vous ne pouvez pas vendre cet objet';
  end if;
  if p_quantity <= 0 or p_quantity > v_item.quantity then raise exception 'Quantité invalide'; end if;
  if p_amount_cp < 0 then raise exception 'Prix de vente invalide'; end if;

  if p_quantity = v_item.quantity then
    update public.campaign_inventory_items
    set status = 'sold', owner_user_id = null
    where id = p_item_id;
    v_sold_id := p_item_id;
  else
    update public.campaign_inventory_items set quantity = quantity - p_quantity where id = p_item_id;
    insert into public.campaign_inventory_items (
      campaign_id, origin_loot_id, parent_item_id, created_by, name, quantity,
      source_quantity_label, unit_value_cp, purchase_price_cp, aon_legacy_name,
      aon_legacy_url, source_kind, status, acquired_on
    ) values (
      v_item.campaign_id, v_item.origin_loot_id, coalesce(v_item.parent_item_id, v_item.id),
      auth.uid(), v_item.name, p_quantity, p_quantity::text, v_item.unit_value_cp,
      v_item.purchase_price_cp, v_item.aon_legacy_name, v_item.aon_legacy_url,
      v_item.source_kind, 'sold', v_item.acquired_on
    ) returning id into v_sold_id;
  end if;

  if p_amount_cp > 0 then
    insert into public.campaign_money_transactions (
      operation_id, campaign_id, actor_user_id, kind,
      source_account, destination_account, amount_cp, comment, related_item_id
    ) values (
      v_operation_id, v_item.campaign_id, auth.uid(), 'sale',
      'external', 'common', p_amount_cp, nullif(btrim(p_comment), ''), v_sold_id
    );
  end if;

  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type, previous_owner_user_id,
    quantity, value_cp, comment, money_operation_id
  ) values (
    v_item.campaign_id, v_sold_id, auth.uid(), 'sold', v_item.owner_user_id,
    p_quantity, p_amount_cp, nullif(btrim(p_comment), ''), v_operation_id
  ) returning id into v_event_id;

  update public.campaign_item_requests
  set status = 'invalidated', resolved_at = now()
  where item_id = v_sold_id and status = 'pending';
  return v_event_id;
end;
$$;

create or replace function public.cancel_campaign_item_event(
  p_event_id uuid,
  p_comment text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.campaign_item_events%rowtype;
  v_item public.campaign_inventory_items%rowtype;
  v_transaction public.campaign_money_transactions%rowtype;
  v_restore_owner uuid;
  v_reverse_operation uuid := gen_random_uuid();
begin
  select * into v_event from public.campaign_item_events where id = p_event_id for update;
  if v_event.id is null or v_event.event_type <> 'sold' then
    raise exception 'Seules les ventes peuvent actuellement être annulées';
  end if;
  if not public.is_campaign_member(v_event.campaign_id)
    or not (public.is_campaign_gm(v_event.campaign_id) or v_event.actor_user_id = auth.uid()) then
    raise exception 'Vous ne pouvez pas annuler cette opération';
  end if;
  if exists (select 1 from public.campaign_item_events event where event.reversed_event_id = p_event_id) then
    raise exception 'Cette opération est déjà annulée';
  end if;
  select * into v_item from public.campaign_inventory_items where id = v_event.item_id for update;
  if v_item.status <> 'sold' or exists (
    select 1 from public.campaign_item_events later
    where later.item_id = v_event.item_id and later.created_at > v_event.created_at
  ) then raise exception 'L’objet a été modifié depuis la vente'; end if;

  v_restore_owner := case
    when public.is_active_campaign_player(v_event.campaign_id, v_event.previous_owner_user_id)
      then v_event.previous_owner_user_id
    else null
  end;
  update public.campaign_inventory_items
  set status = 'active', owner_user_id = v_restore_owner
  where id = v_event.item_id;

  select * into v_transaction
  from public.campaign_money_transactions
  where operation_id = v_event.money_operation_id and kind = 'sale'
  limit 1;
  if v_transaction.id is not null then
    insert into public.campaign_money_transactions (
      operation_id, campaign_id, actor_user_id, kind,
      source_account, destination_account, amount_cp, comment,
      related_item_id, reversed_transaction_id
    ) values (
      v_reverse_operation, v_event.campaign_id, auth.uid(), 'reversal',
      'common', 'external', v_transaction.amount_cp, nullif(btrim(p_comment), ''),
      v_event.item_id, v_transaction.id
    );
  end if;

  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type, next_owner_user_id,
    quantity, value_cp, comment, reversed_event_id, money_operation_id
  ) values (
    v_event.campaign_id, v_event.item_id, auth.uid(), 'sale_cancelled',
    v_restore_owner, v_event.quantity, v_event.value_cp,
    nullif(btrim(p_comment), ''), p_event_id, v_reverse_operation
  );
end;
$$;

create or replace function public.dismantle_campaign_item(
  p_item_id uuid,
  p_outputs jsonb,
  p_comment text default null
) returns uuid[]
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.campaign_inventory_items%rowtype;
  v_output jsonb;
  v_output_id uuid;
  v_output_ids uuid[] := '{}';
  v_name text;
  v_quantity numeric;
  v_value_cp bigint;
begin
  select * into v_item from public.campaign_inventory_items where id = p_item_id for update;
  if v_item.id is null or not public.can_control_campaign_item(p_item_id) then
    raise exception 'Vous ne pouvez pas démonter cet objet';
  end if;
  if jsonb_typeof(p_outputs) <> 'array' or jsonb_array_length(p_outputs) = 0 then
    raise exception 'Indiquez au moins un objet obtenu';
  end if;

  update public.campaign_inventory_items
  set status = 'dismantled', owner_user_id = null
  where id = p_item_id;
  update public.campaign_item_requests
  set status = 'invalidated', resolved_at = now()
  where item_id = p_item_id and status = 'pending';

  for v_output in select value from jsonb_array_elements(p_outputs) loop
    v_name := btrim(v_output->>'name');
    v_quantity := coalesce(nullif(v_output->>'quantity', '')::numeric, 1);
    v_value_cp := nullif(v_output->>'unit_value_cp', '')::bigint;
    if v_name is null or v_name = '' or v_quantity <= 0 or coalesce(v_value_cp, 0) < 0 then
      raise exception 'Objet obtenu invalide';
    end if;
    insert into public.campaign_inventory_items (
      campaign_id, parent_item_id, created_by, owner_user_id, name, quantity,
      source_quantity_label, unit_value_cp, aon_legacy_name, aon_legacy_url,
      source_kind, status, acquired_on
    ) values (
      v_item.campaign_id, p_item_id, auth.uid(), v_item.owner_user_id,
      v_name, v_quantity, v_quantity::text, v_value_cp,
      nullif(btrim(v_output->>'aon_legacy_name'), ''),
      nullif(btrim(v_output->>'aon_legacy_url'), ''),
      'dismantle', 'active', current_date
    ) returning id into v_output_id;
    v_output_ids := array_append(v_output_ids, v_output_id);
    insert into public.campaign_item_events (
      campaign_id, item_id, actor_user_id, event_type, next_owner_user_id,
      quantity, value_cp, comment, related_item_id
    ) values (
      v_item.campaign_id, v_output_id, auth.uid(), 'created', v_item.owner_user_id,
      v_quantity, v_value_cp, nullif(btrim(p_comment), ''), p_item_id
    );
  end loop;

  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type, previous_owner_user_id,
    quantity, value_cp, comment, related_item_id
  ) values (
    v_item.campaign_id, p_item_id, auth.uid(), 'dismantled', v_item.owner_user_id,
    v_item.quantity,
    case when v_item.unit_value_cp is null then null else round(v_item.unit_value_cp * v_item.quantity)::bigint end,
    nullif(btrim(p_comment), ''), v_output_ids[1]
  );
  return v_output_ids;
end;
$$;

create or replace function public.create_manual_campaign_item(
  p_campaign_id uuid,
  p_name text,
  p_quantity numeric default 1,
  p_unit_value_cp bigint default null,
  p_owner_user_id uuid default null,
  p_aon_legacy_name text default null,
  p_aon_legacy_url text default null,
  p_comment text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_item_id uuid;
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if btrim(p_name) = '' or p_quantity <= 0 or coalesce(p_unit_value_cp, 0) < 0 then
    raise exception 'Objet invalide';
  end if;
  if p_owner_user_id is not null and not public.is_active_campaign_player(p_campaign_id, p_owner_user_id) then
    raise exception 'Propriétaire invalide';
  end if;
  insert into public.campaign_inventory_items (
    campaign_id, created_by, owner_user_id, name, quantity, source_quantity_label,
    unit_value_cp, aon_legacy_name, aon_legacy_url, source_kind, status
  ) values (
    p_campaign_id, auth.uid(), p_owner_user_id, btrim(p_name), p_quantity,
    p_quantity::text, p_unit_value_cp, nullif(btrim(p_aon_legacy_name), ''),
    nullif(btrim(p_aon_legacy_url), ''), 'gm', 'active'
  ) returning id into v_item_id;
  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type, next_owner_user_id,
    quantity, value_cp, comment
  ) values (
    p_campaign_id, v_item_id, auth.uid(), 'created', p_owner_user_id,
    p_quantity, p_unit_value_cp, nullif(btrim(p_comment), '')
  );
  return v_item_id;
end;
$$;

create or replace function public.record_personal_money(
  p_campaign_id uuid,
  p_kind text,
  p_amount_cp bigint,
  p_user_id uuid default null,
  p_comment text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := coalesce(p_user_id, auth.uid());
  v_transaction_id uuid;
begin
  if p_kind not in ('income', 'expense') or p_amount_cp <= 0 then
    raise exception 'Opération personnelle invalide';
  end if;
  if not public.is_campaign_member(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if v_user_id <> auth.uid() and not public.is_campaign_gm(p_campaign_id) then
    raise exception 'Vous ne pouvez modifier que votre compte';
  end if;
  if not public.is_active_campaign_player(p_campaign_id, v_user_id) then
    raise exception 'Compte joueur invalide';
  end if;

  insert into public.campaign_money_transactions (
    campaign_id, actor_user_id, kind, source_account, source_user_id,
    destination_account, destination_user_id, amount_cp, comment
  ) values (
    p_campaign_id, auth.uid(),
    case when p_kind = 'income' then 'personal_income' else 'personal_expense' end,
    case when p_kind = 'income' then 'external' else 'player' end,
    case when p_kind = 'expense' then v_user_id else null end,
    case when p_kind = 'income' then 'player' else 'external' end,
    case when p_kind = 'income' then v_user_id else null end,
    p_amount_cp, nullif(btrim(p_comment), '')
  ) returning id into v_transaction_id;
  return v_transaction_id;
end;
$$;

create or replace function public.record_common_income(
  p_campaign_id uuid,
  p_amount_cp bigint,
  p_comment text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_transaction_id uuid;
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if p_amount_cp <= 0 then raise exception 'Montant invalide'; end if;
  insert into public.campaign_money_transactions (
    campaign_id, actor_user_id, kind, source_account,
    destination_account, amount_cp, comment
  ) values (
    p_campaign_id, auth.uid(), 'common_income', 'external',
    'common', p_amount_cp, nullif(btrim(p_comment), '')
  ) returning id into v_transaction_id;
  return v_transaction_id;
end;
$$;

create or replace function public.transfer_campaign_money(
  p_campaign_id uuid,
  p_source_user_id uuid,
  p_destination_user_id uuid,
  p_amount_cp bigint,
  p_comment text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_transaction_id uuid;
begin
  if not public.is_campaign_member(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if p_amount_cp <= 0 or p_source_user_id is not distinct from p_destination_user_id then
    raise exception 'Transfert invalide';
  end if;
  if p_source_user_id is not null
    and p_source_user_id <> auth.uid()
    and not public.is_campaign_gm(p_campaign_id) then
    raise exception 'Vous ne pouvez pas débiter ce compte';
  end if;
  if p_source_user_id is not null and not public.is_active_campaign_player(p_campaign_id, p_source_user_id) then
    raise exception 'Compte source invalide';
  end if;
  if p_destination_user_id is not null and not public.is_active_campaign_player(p_campaign_id, p_destination_user_id) then
    raise exception 'Compte destinataire invalide';
  end if;

  insert into public.campaign_money_transactions (
    campaign_id, actor_user_id, kind,
    source_account, source_user_id, destination_account, destination_user_id,
    amount_cp, comment
  ) values (
    p_campaign_id, auth.uid(), 'transfer',
    case when p_source_user_id is null then 'common' else 'player' end,
    p_source_user_id,
    case when p_destination_user_id is null then 'common' else 'player' end,
    p_destination_user_id,
    p_amount_cp, nullif(btrim(p_comment), '')
  ) returning id into v_transaction_id;
  return v_transaction_id;
end;
$$;

create or replace function public.purchase_campaign_item(
  p_campaign_id uuid,
  p_name text,
  p_quantity numeric,
  p_price_cp bigint,
  p_personal_amount_cp bigint,
  p_common_amount_cp bigint,
  p_owner_user_id uuid default null,
  p_unit_value_cp bigint default null,
  p_aon_legacy_name text default null,
  p_aon_legacy_url text default null,
  p_comment text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_user_id uuid := coalesce(p_owner_user_id, auth.uid());
  v_item_id uuid;
  v_operation_id uuid := gen_random_uuid();
begin
  if not public.is_campaign_member(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if v_owner_user_id <> auth.uid() and not public.is_campaign_gm(p_campaign_id) then
    raise exception 'Vous ne pouvez acheter que pour votre personnage';
  end if;
  if not public.is_active_campaign_player(p_campaign_id, v_owner_user_id) then
    raise exception 'Propriétaire invalide';
  end if;
  if btrim(p_name) = '' or p_quantity <= 0 or p_price_cp < 0
    or p_personal_amount_cp < 0 or p_common_amount_cp < 0
    or p_personal_amount_cp + p_common_amount_cp <> p_price_cp then
    raise exception 'Achat invalide';
  end if;

  insert into public.campaign_inventory_items (
    campaign_id, created_by, owner_user_id, name, quantity, source_quantity_label,
    unit_value_cp, purchase_price_cp, aon_legacy_name, aon_legacy_url,
    source_kind, status
  ) values (
    p_campaign_id, auth.uid(), v_owner_user_id, btrim(p_name), p_quantity,
    p_quantity::text, p_unit_value_cp, p_price_cp,
    nullif(btrim(p_aon_legacy_name), ''), nullif(btrim(p_aon_legacy_url), ''),
    'purchase', 'active'
  ) returning id into v_item_id;

  if p_personal_amount_cp > 0 then
    insert into public.campaign_money_transactions (
      operation_id, campaign_id, actor_user_id, kind,
      source_account, source_user_id, destination_account,
      amount_cp, comment, related_item_id
    ) values (
      v_operation_id, p_campaign_id, auth.uid(), 'purchase',
      'player', v_owner_user_id, 'external', p_personal_amount_cp,
      nullif(btrim(p_comment), ''), v_item_id
    );
  end if;
  if p_common_amount_cp > 0 then
    insert into public.campaign_money_transactions (
      operation_id, campaign_id, actor_user_id, kind,
      source_account, destination_account, amount_cp, comment, related_item_id
    ) values (
      v_operation_id, p_campaign_id, auth.uid(), 'purchase',
      'common', 'external', p_common_amount_cp,
      nullif(btrim(p_comment), ''), v_item_id
    );
  end if;
  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type, next_owner_user_id,
    quantity, value_cp, comment, money_operation_id
  ) values (
    p_campaign_id, v_item_id, auth.uid(), 'purchased', v_owner_user_id,
    p_quantity, p_price_cp, nullif(btrim(p_comment), ''), v_operation_id
  );
  return v_item_id;
end;
$$;

create or replace function public.request_campaign_item(
  p_item_id uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.campaign_inventory_items%rowtype;
  v_request_id uuid;
begin
  select * into v_item from public.campaign_inventory_items where id = p_item_id;
  if v_item.id is null or v_item.status <> 'active' or v_item.owner_user_id is null
    or v_item.owner_user_id = auth.uid() or not public.is_campaign_member(v_item.campaign_id) then
    raise exception 'Cet objet ne peut pas être demandé';
  end if;
  if not public.is_active_campaign_player(v_item.campaign_id, auth.uid()) then
    raise exception 'Seuls les joueurs peuvent demander un objet';
  end if;
  select id into v_request_id from public.campaign_item_requests
  where item_id = p_item_id and requester_user_id = auth.uid() and status = 'pending';
  if v_request_id is not null then return v_request_id; end if;
  insert into public.campaign_item_requests (
    campaign_id, item_id, requester_user_id, owner_user_id
  ) values (
    v_item.campaign_id, p_item_id, auth.uid(), v_item.owner_user_id
  ) returning id into v_request_id;
  return v_request_id;
end;
$$;

create or replace function public.resolve_campaign_item_request(
  p_request_id uuid,
  p_accept boolean
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.campaign_item_requests%rowtype;
  v_item public.campaign_inventory_items%rowtype;
begin
  select * into v_request from public.campaign_item_requests where id = p_request_id for update;
  if v_request.id is null or v_request.status <> 'pending' then raise exception 'Demande introuvable'; end if;
  if v_request.owner_user_id <> auth.uid() and not public.is_campaign_gm(v_request.campaign_id) then
    raise exception 'Vous ne pouvez pas répondre à cette demande';
  end if;
  select * into v_item from public.campaign_inventory_items where id = v_request.item_id for update;
  if v_item.status <> 'active' or v_item.owner_user_id <> v_request.owner_user_id then
    update public.campaign_item_requests set status = 'invalidated', resolved_at = now() where id = p_request_id;
    return;
  end if;
  if not p_accept then
    update public.campaign_item_requests set status = 'refused', resolved_at = now() where id = p_request_id;
    return;
  end if;
  if not public.is_active_campaign_player(v_request.campaign_id, v_request.requester_user_id) then
    update public.campaign_item_requests set status = 'invalidated', resolved_at = now() where id = p_request_id;
    return;
  end if;

  update public.campaign_inventory_items set owner_user_id = v_request.requester_user_id where id = v_item.id;
  update public.campaign_item_requests
  set status = case when id = p_request_id then 'accepted' else 'invalidated' end,
      resolved_at = now()
  where item_id = v_item.id and status = 'pending';
  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type,
    previous_owner_user_id, next_owner_user_id, quantity
  ) values (
    v_request.campaign_id, v_item.id, auth.uid(), 'transferred',
    v_request.owner_user_id, v_request.requester_user_id, v_item.quantity
  );
end;
$$;

create or replace function public.cancel_campaign_item_request(
  p_request_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.campaign_item_requests
  set status = 'cancelled', resolved_at = now()
  where id = p_request_id and requester_user_id = auth.uid() and status = 'pending';
  if not found then raise exception 'Demande introuvable'; end if;
end;
$$;

create or replace function public.cancel_campaign_money_transaction(
  p_transaction_id uuid,
  p_comment text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_transaction public.campaign_money_transactions%rowtype;
  v_reversal_id uuid;
begin
  select * into v_transaction
  from public.campaign_money_transactions
  where id = p_transaction_id for update;
  if v_transaction.id is null or v_transaction.kind in ('sale', 'purchase', 'reversal', 'departure_transfer') then
    raise exception 'Cette opération doit être annulée depuis l’objet concerné';
  end if;
  if v_transaction.actor_user_id <> auth.uid()
    and not public.is_campaign_gm(v_transaction.campaign_id) then
    raise exception 'Vous ne pouvez pas annuler cette opération';
  end if;
  if exists (
    select 1 from public.campaign_money_transactions reversal
    where reversal.reversed_transaction_id = p_transaction_id
  ) then raise exception 'Cette opération est déjà annulée'; end if;

  insert into public.campaign_money_transactions (
    campaign_id, actor_user_id, kind,
    source_account, source_user_id, destination_account, destination_user_id,
    amount_cp, comment, reversed_transaction_id
  ) values (
    v_transaction.campaign_id, auth.uid(), 'reversal',
    v_transaction.destination_account, v_transaction.destination_user_id,
    v_transaction.source_account, v_transaction.source_user_id,
    v_transaction.amount_cp, nullif(btrim(p_comment), ''), p_transaction_id
  ) returning id into v_reversal_id;
  return v_reversal_id;
end;
$$;

create or replace function public.create_campaign_money_debt(
  p_campaign_id uuid,
  p_debtor_user_id uuid,
  p_creditor_user_id uuid,
  p_amount_cp bigint,
  p_comment text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_debt_id uuid;
begin
  if not public.is_campaign_member(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if auth.uid() not in (p_debtor_user_id, p_creditor_user_id)
    and not public.is_campaign_gm(p_campaign_id) then raise exception 'Dette non autorisée'; end if;
  if not public.is_active_campaign_player(p_campaign_id, p_debtor_user_id)
    or not public.is_active_campaign_player(p_campaign_id, p_creditor_user_id)
    or p_debtor_user_id = p_creditor_user_id or p_amount_cp <= 0 then
    raise exception 'Dette invalide';
  end if;
  insert into public.campaign_money_debts (
    campaign_id, debtor_user_id, creditor_user_id, amount_cp, remaining_cp,
    comment, created_by
  ) values (
    p_campaign_id, p_debtor_user_id, p_creditor_user_id, p_amount_cp, p_amount_cp,
    nullif(btrim(p_comment), ''), auth.uid()
  ) returning id into v_debt_id;
  return v_debt_id;
end;
$$;

create or replace function public.pay_campaign_money_debt(
  p_debt_id uuid,
  p_amount_cp bigint,
  p_comment text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_debt public.campaign_money_debts%rowtype;
begin
  select * into v_debt from public.campaign_money_debts where id = p_debt_id for update;
  if v_debt.id is null or v_debt.status <> 'open' then raise exception 'Dette introuvable'; end if;
  if v_debt.debtor_user_id <> auth.uid() and not public.is_campaign_gm(v_debt.campaign_id) then
    raise exception 'Seul le débiteur peut rembourser cette dette';
  end if;
  if p_amount_cp <= 0 or p_amount_cp > v_debt.remaining_cp then raise exception 'Montant invalide'; end if;

  insert into public.campaign_money_transactions (
    campaign_id, actor_user_id, kind, source_account, source_user_id,
    destination_account, destination_user_id, amount_cp, comment
  ) values (
    v_debt.campaign_id, auth.uid(), 'transfer', 'player', v_debt.debtor_user_id,
    'player', v_debt.creditor_user_id, p_amount_cp, coalesce(nullif(btrim(p_comment), ''), 'Remboursement de dette')
  );
  update public.campaign_money_debts
  set remaining_cp = remaining_cp - p_amount_cp,
      status = case when remaining_cp - p_amount_cp = 0 then 'settled' else 'open' end
  where id = p_debt_id;
end;
$$;

create or replace function public.cancel_campaign_money_debt(
  p_debt_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.campaign_money_debts debt
  set status = 'cancelled'
  where debt.id = p_debt_id and debt.status = 'open'
    and (
      debt.created_by = auth.uid()
      or debt.debtor_user_id = auth.uid()
      or debt.creditor_user_id = auth.uid()
      or public.is_campaign_gm(debt.campaign_id)
    );
  if not found then raise exception 'Dette introuvable'; end if;
end;
$$;

create or replace function public.transfer_departing_player_assets(
  p_campaign_id uuid,
  p_user_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_balance bigint;
begin
  -- Les dettes explicites sont matérialisées dans les comptes avant le retrait :
  -- le pot commun reprend aussi bien la dette que la créance du joueur sortant.
  insert into public.campaign_money_transactions (
    campaign_id, actor_user_id, kind, source_account,
    destination_account, destination_user_id, amount_cp, comment
  )
  select debt.campaign_id, auth.uid(), 'departure_transfer', 'common',
    'player', debt.creditor_user_id, debt.remaining_cp,
    'Dette reprise par le pot commun au départ du joueur'
  from public.campaign_money_debts debt
  where debt.campaign_id = p_campaign_id
    and debt.debtor_user_id = p_user_id
    and debt.status = 'open'
    and debt.remaining_cp > 0;

  insert into public.campaign_money_transactions (
    campaign_id, actor_user_id, kind, source_account, source_user_id,
    destination_account, amount_cp, comment
  )
  select debt.campaign_id, auth.uid(), 'departure_transfer', 'player',
    debt.debtor_user_id, 'common', debt.remaining_cp,
    'Créance reprise par le pot commun au départ du joueur'
  from public.campaign_money_debts debt
  where debt.campaign_id = p_campaign_id
    and debt.creditor_user_id = p_user_id
    and debt.status = 'open'
    and debt.remaining_cp > 0;

  select coalesce(sum(
    case
      when transaction.destination_account = 'player' and transaction.destination_user_id = p_user_id then transaction.amount_cp
      when transaction.source_account = 'player' and transaction.source_user_id = p_user_id then -transaction.amount_cp
      else 0
    end
  ), 0)::bigint into v_balance
  from public.campaign_money_transactions transaction
  where transaction.campaign_id = p_campaign_id;

  if v_balance > 0 then
    insert into public.campaign_money_transactions (
      campaign_id, actor_user_id, kind, source_account, source_user_id,
      destination_account, amount_cp, comment
    ) values (
      p_campaign_id, auth.uid(), 'departure_transfer', 'player', p_user_id,
      'common', v_balance, 'Départ du joueur'
    );
  elsif v_balance < 0 then
    insert into public.campaign_money_transactions (
      campaign_id, actor_user_id, kind, source_account,
      destination_account, destination_user_id, amount_cp, comment
    ) values (
      p_campaign_id, auth.uid(), 'departure_transfer', 'common',
      'player', p_user_id, abs(v_balance), 'Reprise de la dette au départ du joueur'
    );
  end if;

  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type,
    previous_owner_user_id, quantity, comment
  )
  select p_campaign_id, item.id, auth.uid(), 'returned', p_user_id,
    item.quantity, 'Départ du joueur'
  from public.campaign_inventory_items item
  where item.campaign_id = p_campaign_id
    and item.owner_user_id = p_user_id
    and item.status = 'active';

  update public.campaign_inventory_items
  set owner_user_id = null
  where campaign_id = p_campaign_id and owner_user_id = p_user_id and status = 'active';
  update public.campaign_item_requests
  set status = 'invalidated', resolved_at = now()
  where campaign_id = p_campaign_id and status = 'pending'
    and (owner_user_id = p_user_id or requester_user_id = p_user_id);
  update public.campaign_money_debts
  set status = 'cancelled'
  where campaign_id = p_campaign_id and status = 'open'
    and (debtor_user_id = p_user_id or creditor_user_id = p_user_id);
end;
$$;

create or replace function public.remove_campaign_player(
  p_campaign_id uuid,
  p_user_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if not public.is_active_campaign_player(p_campaign_id, p_user_id) then return; end if;
  perform public.transfer_departing_player_assets(p_campaign_id, p_user_id);
  delete from public.campaign_members
  where campaign_id = p_campaign_id and user_id = p_user_id and role = 'player';
  update public.loot_player_publications
  set owner_user_id = null, lifecycle_status = 'available', legacy_owner_label = null
  where campaign_id = p_campaign_id and owner_user_id = p_user_id;
end;
$$;

create or replace function public.leave_campaign(p_campaign_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if not public.is_active_campaign_player(p_campaign_id, auth.uid()) then
    raise exception 'Vous n’êtes pas joueur de cette campagne';
  end if;
  perform public.transfer_departing_player_assets(p_campaign_id, auth.uid());
  delete from public.campaign_members
  where campaign_id = p_campaign_id and user_id = auth.uid() and role = 'player';
  update public.loot_player_publications
  set owner_user_id = null, lifecycle_status = 'available', legacy_owner_label = null
  where campaign_id = p_campaign_id and owner_user_id = auth.uid();
end;
$$;

create or replace function public.set_loot_player_visibility(
  p_loot_id uuid,
  p_visible boolean,
  p_published_on date
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loot public.campaign_loot%rowtype;
  v_item_id uuid;
  v_quantity numeric;
  v_value_cp bigint;
begin
  select * into v_loot from public.campaign_loot where id = p_loot_id for update;
  if v_loot.id is null then raise exception 'Butin introuvable'; end if;
  if not public.is_campaign_gm(v_loot.campaign_id) then raise exception 'Accès refusé'; end if;

  update public.campaign_loot
  set player_visible = p_visible,
      discovery_status = case when p_visible then 'found' else discovery_status end
  where id = p_loot_id;

  if not p_visible then
    update public.campaign_inventory_items set player_visible = false where origin_loot_id = p_loot_id;
    update public.campaign_item_requests request
    set status = 'invalidated', resolved_at = now()
    where request.status = 'pending' and exists (
      select 1 from public.campaign_inventory_items item
      where item.id = request.item_id and item.origin_loot_id = p_loot_id
    );
    return;
  end if;

  insert into public.loot_player_publications (loot_id, campaign_id, published_on)
  values (p_loot_id, v_loot.campaign_id, coalesce(p_published_on, current_date))
  on conflict (loot_id) do update set published_on = excluded.published_on;

  select id into v_item_id
  from public.campaign_inventory_items
  where origin_loot_id = p_loot_id and source_kind = 'loot'
  order by created_at limit 1;
  if v_item_id is not null then
    update public.campaign_inventory_items set player_visible = true where origin_loot_id = p_loot_id;
    return;
  end if;

  v_quantity := case
    when v_loot.quantity_recoverable ~ '^[0-9]+([.,][0-9]+)?$'
      then replace(v_loot.quantity_recoverable, ',', '.')::numeric
    else 1
  end;
  v_value_cp := case
    when v_loot.book_unit_value_amount is not null then round(v_loot.book_unit_value_amount * case v_loot.book_unit_value_currency when 'pp' then 1000 when 'gp' then 100 when 'sp' then 10 else 1 end)::bigint
    when v_loot.aon_legacy_unit_value_amount is not null then round(v_loot.aon_legacy_unit_value_amount * case v_loot.aon_legacy_unit_value_currency when 'pp' then 1000 when 'gp' then 100 when 'sp' then 10 else 1 end)::bigint
    else null
  end;
  insert into public.campaign_inventory_items (
    campaign_id, origin_loot_id, created_by, name, quantity, source_quantity_label,
    unit_value_cp, aon_legacy_name, aon_legacy_url, source_kind, player_visible,
    status, acquired_on
  ) values (
    v_loot.campaign_id, p_loot_id, auth.uid(), v_loot.item_name, v_quantity,
    v_loot.quantity_recoverable, v_value_cp, v_loot.aon_legacy_name,
    v_loot.aon_legacy_url, 'loot', true, 'active', coalesce(p_published_on, current_date)
  ) returning id into v_item_id;
  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type, quantity, value_cp, created_at
  ) values (
    v_loot.campaign_id, v_item_id, auth.uid(), 'published', v_quantity, v_value_cp,
    coalesce(p_published_on, current_date)::timestamptz
  );
end;
$$;

revoke all on table
  public.campaign_inventory_items,
  public.campaign_money_transactions,
  public.campaign_item_events,
  public.campaign_item_requests,
  public.campaign_money_debts
from public, anon, authenticated;

revoke all on table
  public.player_inventory_items,
  public.player_money_balances,
  public.player_economy_totals,
  public.player_money_history,
  public.player_item_history,
  public.player_item_request_overview,
  public.player_money_debt_overview
from anon;
grant select on table
  public.player_inventory_items,
  public.player_money_balances,
  public.player_economy_totals,
  public.player_money_history,
  public.player_item_history,
  public.player_item_request_overview,
  public.player_money_debt_overview
to authenticated;

revoke all on function public.is_active_campaign_player(uuid, uuid) from public, anon, authenticated;
revoke all on function public.can_control_campaign_item(uuid) from public, anon, authenticated;
revoke all on function public.assign_campaign_item(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.return_campaign_item_to_common(uuid, text) from public, anon, authenticated;
revoke all on function public.split_campaign_item(uuid, numeric) from public, anon, authenticated;
revoke all on function public.merge_campaign_items(uuid, uuid) from public, anon, authenticated;
revoke all on function public.batch_update_campaign_items(uuid[], text, uuid, text) from public, anon, authenticated;
revoke all on function public.set_campaign_item_terminal(uuid, text, numeric, text) from public, anon, authenticated;
revoke all on function public.sell_campaign_item(uuid, numeric, bigint, text) from public, anon, authenticated;
revoke all on function public.cancel_campaign_item_event(uuid, text) from public, anon, authenticated;
revoke all on function public.dismantle_campaign_item(uuid, jsonb, text) from public, anon, authenticated;
revoke all on function public.create_manual_campaign_item(uuid, text, numeric, bigint, uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.record_personal_money(uuid, text, bigint, uuid, text) from public, anon, authenticated;
revoke all on function public.record_common_income(uuid, bigint, text) from public, anon, authenticated;
revoke all on function public.transfer_campaign_money(uuid, uuid, uuid, bigint, text) from public, anon, authenticated;
revoke all on function public.purchase_campaign_item(uuid, text, numeric, bigint, bigint, bigint, uuid, bigint, text, text, text) from public, anon, authenticated;
revoke all on function public.request_campaign_item(uuid) from public, anon, authenticated;
revoke all on function public.resolve_campaign_item_request(uuid, boolean) from public, anon, authenticated;
revoke all on function public.cancel_campaign_item_request(uuid) from public, anon, authenticated;
revoke all on function public.cancel_campaign_money_transaction(uuid, text) from public, anon, authenticated;
revoke all on function public.create_campaign_money_debt(uuid, uuid, uuid, bigint, text) from public, anon, authenticated;
revoke all on function public.pay_campaign_money_debt(uuid, bigint, text) from public, anon, authenticated;
revoke all on function public.cancel_campaign_money_debt(uuid) from public, anon, authenticated;
revoke all on function public.transfer_departing_player_assets(uuid, uuid) from public, anon, authenticated;
revoke all on function public.set_loot_player_visibility(uuid, boolean, date) from public, anon, authenticated;

grant execute on function public.assign_campaign_item(uuid, uuid, text) to authenticated;
grant execute on function public.return_campaign_item_to_common(uuid, text) to authenticated;
grant execute on function public.split_campaign_item(uuid, numeric) to authenticated;
grant execute on function public.merge_campaign_items(uuid, uuid) to authenticated;
grant execute on function public.batch_update_campaign_items(uuid[], text, uuid, text) to authenticated;
grant execute on function public.set_campaign_item_terminal(uuid, text, numeric, text) to authenticated;
grant execute on function public.sell_campaign_item(uuid, numeric, bigint, text) to authenticated;
grant execute on function public.cancel_campaign_item_event(uuid, text) to authenticated;
grant execute on function public.dismantle_campaign_item(uuid, jsonb, text) to authenticated;
grant execute on function public.create_manual_campaign_item(uuid, text, numeric, bigint, uuid, text, text, text) to authenticated;
grant execute on function public.record_personal_money(uuid, text, bigint, uuid, text) to authenticated;
grant execute on function public.record_common_income(uuid, bigint, text) to authenticated;
grant execute on function public.transfer_campaign_money(uuid, uuid, uuid, bigint, text) to authenticated;
grant execute on function public.purchase_campaign_item(uuid, text, numeric, bigint, bigint, bigint, uuid, bigint, text, text, text) to authenticated;
grant execute on function public.request_campaign_item(uuid) to authenticated;
grant execute on function public.resolve_campaign_item_request(uuid, boolean) to authenticated;
grant execute on function public.cancel_campaign_item_request(uuid) to authenticated;
grant execute on function public.cancel_campaign_money_transaction(uuid, text) to authenticated;
grant execute on function public.create_campaign_money_debt(uuid, uuid, uuid, bigint, text) to authenticated;
grant execute on function public.pay_campaign_money_debt(uuid, bigint, text) to authenticated;
grant execute on function public.cancel_campaign_money_debt(uuid) to authenticated;
grant execute on function public.set_loot_player_visibility(uuid, boolean, date) to authenticated;

revoke all on function public.remove_campaign_player(uuid, uuid) from public, anon, authenticated;
grant execute on function public.remove_campaign_player(uuid, uuid) to authenticated;
revoke all on function public.leave_campaign(uuid) from public, anon, authenticated;
grant execute on function public.leave_campaign(uuid) to authenticated;

comment on table public.campaign_inventory_items is
  'Objets réellement entrés dans l’économie des joueurs, distincts du registre de référence MJ.';
comment on table public.campaign_money_transactions is
  'Registre financier immuable ; les corrections sont des transactions inverses.';
comment on table public.campaign_item_events is
  'Biographie complète des objets de campagne.';
