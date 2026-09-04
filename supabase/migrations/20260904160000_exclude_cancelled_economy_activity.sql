-- Cancelled operations remain available in the audit trail, but neither the
-- original operation nor its technical reversal represents a real historic
-- inflow or outflow.

create or replace view public.player_economy_totals
with (security_barrier = true)
as
select campaign.id as campaign_id,
  (
    coalesce((select sum(case
      when event.event_type in ('published', 'created') and (event.event_type <> 'created' or event.related_item_id is null)
        then coalesce(event.value_cp, 0) * coalesce(event.quantity, 1)
      when event.event_type = 'purchased' then coalesce(event.value_cp, 0)
      else 0 end)
      from public.campaign_item_events event
      where event.campaign_id = campaign.id
        and event.reversed_event_id is null
        and not exists (
          select 1 from public.campaign_item_events reversal
          where reversal.reversed_event_id = event.id
        )
        and exists (
          select 1 from public.campaign_inventory_items visible_item where visible_item.id = event.item_id
            and (visible_item.player_visible or public.is_campaign_gm(campaign.id))
        )), 0)
    + coalesce((select sum(transaction.amount_cp) from public.campaign_money_transactions transaction
      where transaction.campaign_id = campaign.id and transaction.source_account = 'external'
        and transaction.reversed_transaction_id is null
        and not exists (
          select 1 from public.campaign_money_transactions reversal
          where reversal.reversed_transaction_id = transaction.id
        )
        and (transaction.related_item_id is null or exists (
          select 1 from public.campaign_inventory_items visible_item where visible_item.id = transaction.related_item_id
            and (visible_item.player_visible or public.is_campaign_gm(campaign.id))
        ))), 0)
  )::bigint as total_entered_cp,
  (
    coalesce((select sum(case when event.event_type in ('sold', 'consumed', 'lost', 'donated') then coalesce(event.value_cp, 0) else 0 end)
      from public.campaign_item_events event
      where event.campaign_id = campaign.id
        and event.reversed_event_id is null
        and not exists (
          select 1 from public.campaign_item_events reversal
          where reversal.reversed_event_id = event.id
        )
        and exists (
          select 1 from public.campaign_inventory_items visible_item where visible_item.id = event.item_id
            and (visible_item.player_visible or public.is_campaign_gm(campaign.id))
        )), 0)
    + coalesce((select sum(transaction.amount_cp) from public.campaign_money_transactions transaction
      where transaction.campaign_id = campaign.id and transaction.destination_account = 'external'
        and transaction.reversed_transaction_id is null
        and not exists (
          select 1 from public.campaign_money_transactions reversal
          where reversal.reversed_transaction_id = transaction.id
        )
        and (transaction.related_item_id is null or exists (
          select 1 from public.campaign_inventory_items visible_item where visible_item.id = transaction.related_item_id
            and (visible_item.player_visible or public.is_campaign_gm(campaign.id))
        ))), 0)
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

