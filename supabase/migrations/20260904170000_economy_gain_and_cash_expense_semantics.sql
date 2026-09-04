-- Gains, cash expenses and current wealth are independent statistics.
alter table public.campaign_inventory_items
  add column if not exists counts_as_gain boolean not null default true;

drop function if exists public.create_manual_campaign_item(uuid, text, numeric, bigint, uuid, text, text, text);

create function public.create_manual_campaign_item(
  p_campaign_id uuid, p_name text, p_quantity numeric default 1,
  p_unit_value_cp bigint default null, p_owner_user_id uuid default null,
  p_aon_legacy_name text default null, p_aon_legacy_url text default null,
  p_comment text default null, p_counts_as_gain boolean default true
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_item_id uuid;
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if btrim(p_name) = '' or p_quantity <= 0 or coalesce(p_unit_value_cp, 0) < 0 then raise exception 'Objet invalide'; end if;
  if p_owner_user_id is not null and not public.is_active_campaign_player(p_campaign_id, p_owner_user_id) then raise exception 'Propriétaire invalide'; end if;
  insert into public.campaign_inventory_items (
    campaign_id, created_by, owner_user_id, name, quantity, source_quantity_label,
    unit_value_cp, aon_legacy_name, aon_legacy_url, source_kind, status, counts_as_gain
  ) values (
    p_campaign_id, auth.uid(), p_owner_user_id, btrim(p_name), p_quantity,
    p_quantity::text, p_unit_value_cp, nullif(btrim(p_aon_legacy_name), ''),
    nullif(btrim(p_aon_legacy_url), ''), 'gm', 'active', coalesce(p_counts_as_gain, true)
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

revoke all on function public.create_manual_campaign_item(uuid, text, numeric, bigint, uuid, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.create_manual_campaign_item(uuid, text, numeric, bigint, uuid, text, text, text, boolean) to authenticated;

create or replace function public.purchase_campaign_item(
  p_campaign_id uuid, p_name text, p_quantity numeric, p_price_cp bigint,
  p_personal_amount_cp bigint, p_common_amount_cp bigint,
  p_owner_user_id uuid default null, p_unit_value_cp bigint default null,
  p_aon_legacy_name text default null, p_aon_legacy_url text default null,
  p_comment text default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_owner_user_id uuid := coalesce(p_owner_user_id, auth.uid());
  v_item_id uuid;
  v_operation_id uuid := gen_random_uuid();
  v_unit_value_cp bigint;
begin
  if not public.is_campaign_member(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if v_owner_user_id <> auth.uid() and not public.is_campaign_gm(p_campaign_id) then raise exception 'Vous ne pouvez acheter que pour votre personnage'; end if;
  if not public.is_active_campaign_player(p_campaign_id, v_owner_user_id) then raise exception 'Propriétaire invalide'; end if;
  if btrim(p_name) = '' or p_quantity <= 0 or p_price_cp < 0 or p_personal_amount_cp < 0 or p_common_amount_cp < 0
    or p_personal_amount_cp + p_common_amount_cp <> p_price_cp then raise exception 'Achat invalide'; end if;
  v_unit_value_cp := case when p_price_cp = 0 then 0 else greatest(1, round(p_price_cp::numeric / p_quantity)::bigint) end;
  insert into public.campaign_inventory_items (
    campaign_id, created_by, owner_user_id, name, quantity, source_quantity_label,
    unit_value_cp, purchase_price_cp, aon_legacy_name, aon_legacy_url,
    source_kind, status, counts_as_gain
  ) values (
    p_campaign_id, auth.uid(), v_owner_user_id, btrim(p_name), p_quantity,
    p_quantity::text, v_unit_value_cp, p_price_cp,
    nullif(btrim(p_aon_legacy_name), ''), nullif(btrim(p_aon_legacy_url), ''),
    'purchase', 'active', false
  ) returning id into v_item_id;
  if p_personal_amount_cp > 0 then
    insert into public.campaign_money_transactions (operation_id, campaign_id, actor_user_id, kind, source_account, source_user_id, destination_account, amount_cp, comment, related_item_id)
    values (v_operation_id, p_campaign_id, auth.uid(), 'purchase', 'player', v_owner_user_id, 'external', p_personal_amount_cp, nullif(btrim(p_comment), ''), v_item_id);
  end if;
  if p_common_amount_cp > 0 then
    insert into public.campaign_money_transactions (operation_id, campaign_id, actor_user_id, kind, source_account, destination_account, amount_cp, comment, related_item_id)
    values (v_operation_id, p_campaign_id, auth.uid(), 'purchase', 'common', 'external', p_common_amount_cp, nullif(btrim(p_comment), ''), v_item_id);
  end if;
  insert into public.campaign_item_events (campaign_id, item_id, actor_user_id, event_type, next_owner_user_id, quantity, value_cp, comment, money_operation_id)
  values (p_campaign_id, v_item_id, auth.uid(), 'purchased', v_owner_user_id, p_quantity, p_price_cp, nullif(btrim(p_comment), ''), v_operation_id);
  return v_item_id;
end;
$$;

create or replace view public.player_economy_totals
with (security_barrier = true) as
select campaign.id as campaign_id,
  (
    coalesce((select sum(coalesce(event.value_cp, 0) * coalesce(event.quantity, 1))
      from public.campaign_item_events event
      join public.campaign_inventory_items item on item.id = event.item_id
      where event.campaign_id = campaign.id
        and event.event_type in ('published', 'created')
        and (event.event_type <> 'created' or event.related_item_id is null)
        and item.counts_as_gain
        and event.reversed_event_id is null
        and not exists (select 1 from public.campaign_item_events reversal where reversal.reversed_event_id = event.id)
        and (item.player_visible or public.is_campaign_gm(campaign.id))), 0)
    + coalesce((select sum(transaction.amount_cp)
      from public.campaign_money_transactions transaction
      where transaction.campaign_id = campaign.id
        and transaction.source_account = 'external' and transaction.kind <> 'sale'
        and transaction.reversed_transaction_id is null
        and not exists (select 1 from public.campaign_money_transactions reversal where reversal.reversed_transaction_id = transaction.id)
        and (transaction.related_item_id is null or exists (
          select 1 from public.campaign_inventory_items visible_item
          where visible_item.id = transaction.related_item_id
            and (visible_item.player_visible or public.is_campaign_gm(campaign.id))))), 0)
    + coalesce((select sum(greatest(0, coalesce(event.value_cp, 0) - coalesce(item.unit_value_cp, 0) * coalesce(event.quantity, 1)))
      from public.campaign_item_events event
      join public.campaign_inventory_items item on item.id = event.item_id
      where event.campaign_id = campaign.id and event.event_type = 'sold'
        and event.reversed_event_id is null
        and not exists (select 1 from public.campaign_item_events reversal where reversal.reversed_event_id = event.id)
        and (item.player_visible or public.is_campaign_gm(campaign.id))), 0)
  )::bigint as total_entered_cp,
  (
    coalesce((select sum(transaction.amount_cp)
      from public.campaign_money_transactions transaction
      where transaction.campaign_id = campaign.id
        and transaction.destination_account = 'external'
        and transaction.reversed_transaction_id is null
        and not exists (select 1 from public.campaign_money_transactions reversal where reversal.reversed_transaction_id = transaction.id)
        and (transaction.related_item_id is null or exists (
          select 1 from public.campaign_inventory_items visible_item
          where visible_item.id = transaction.related_item_id
            and (visible_item.player_visible or public.is_campaign_gm(campaign.id))))), 0)
  )::bigint as total_exited_cp,
  (
    coalesce((select sum(case
      when transaction.source_account = 'external' then transaction.amount_cp
      when transaction.destination_account = 'external' then -transaction.amount_cp
      else 0 end)
      from public.campaign_money_transactions transaction where transaction.campaign_id = campaign.id), 0)
    + coalesce((select sum(coalesce(item.unit_value_cp, 0) * item.quantity)
      from public.campaign_inventory_items item
      where item.campaign_id = campaign.id and item.status = 'active'
        and (item.player_visible or public.is_campaign_gm(campaign.id))), 0)
  )::bigint as current_wealth_cp
from public.campaigns campaign
where public.is_campaign_member(campaign.id);
