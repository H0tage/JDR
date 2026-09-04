-- Nom conseillé dans le SQL Editor : Correctifs économie et demandes — 2026-09-04
-- Cohérence de l'économie : redemandes, patrimoine global, achats et identité du MJ.

alter table public.campaign_item_requests
  drop constraint if exists campaign_item_requests_item_id_requester_user_id_status_key;

create unique index if not exists campaign_item_requests_one_pending_per_player_idx
  on public.campaign_item_requests(item_id, requester_user_id)
  where status = 'pending';

create or replace view public.player_money_balances
with (security_barrier = true)
as
with accounts as (
  select campaign.id as campaign_id, null::uuid as account_user_id,
    'Compte commun'::text as display_name, true as is_common
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
  case when actor_member.role = 'gm' then 'Le Maître du Jeu' else actor_profile.display_name end as actor_display_name,
  source_profile.display_name as source_display_name,
  destination_profile.display_name as destination_display_name,
  item.name as related_item_name
from public.campaign_money_transactions transaction
join public.campaign_settings settings on settings.campaign_id = transaction.campaign_id
left join public.user_profiles actor_profile on actor_profile.user_id = transaction.actor_user_id
left join public.campaign_members actor_member on actor_member.campaign_id = transaction.campaign_id and actor_member.user_id = transaction.actor_user_id
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
    coalesce((select sum(case
      when event.event_type in ('published', 'created') and (event.event_type <> 'created' or event.related_item_id is null)
        then coalesce(event.value_cp, 0) * coalesce(event.quantity, 1)
      when event.event_type in ('purchased', 'sale_cancelled') then coalesce(event.value_cp, 0)
      else 0 end)
      from public.campaign_item_events event
      where event.campaign_id = campaign.id and exists (
        select 1 from public.campaign_inventory_items visible_item where visible_item.id = event.item_id
          and (visible_item.player_visible or public.is_campaign_gm(campaign.id))
      )), 0)
    + coalesce((select sum(transaction.amount_cp) from public.campaign_money_transactions transaction
      where transaction.campaign_id = campaign.id and transaction.source_account = 'external'
        and (transaction.related_item_id is null or exists (
          select 1 from public.campaign_inventory_items visible_item where visible_item.id = transaction.related_item_id
            and (visible_item.player_visible or public.is_campaign_gm(campaign.id))
        ))), 0)
  )::bigint as total_entered_cp,
  (
    coalesce((select sum(case when event.event_type in ('sold', 'consumed', 'lost', 'donated') then coalesce(event.value_cp, 0) else 0 end)
      from public.campaign_item_events event
      where event.campaign_id = campaign.id and exists (
        select 1 from public.campaign_inventory_items visible_item where visible_item.id = event.item_id
          and (visible_item.player_visible or public.is_campaign_gm(campaign.id))
      )), 0)
    + coalesce((select sum(transaction.amount_cp) from public.campaign_money_transactions transaction
      where transaction.campaign_id = campaign.id and transaction.destination_account = 'external'
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

create or replace view public.player_item_history
with (security_barrier = true)
as
select event.*,
  item.name as item_name,
  related.name as related_item_name,
  case when actor_member.role = 'gm' then 'Le Maître du Jeu' else actor_profile.display_name end as actor_display_name,
  previous_profile.display_name as previous_owner_display_name,
  next_profile.display_name as next_owner_display_name
from public.campaign_item_events event
left join public.campaign_inventory_items item on item.id = event.item_id
left join public.campaign_inventory_items related on related.id = event.related_item_id
left join public.user_profiles actor_profile on actor_profile.user_id = event.actor_user_id
left join public.campaign_members actor_member on actor_member.campaign_id = event.campaign_id and actor_member.user_id = event.actor_user_id
left join public.user_profiles previous_profile on previous_profile.user_id = event.previous_owner_user_id
left join public.user_profiles next_profile on next_profile.user_id = event.next_owner_user_id
where public.is_campaign_member(event.campaign_id)
  and (public.is_campaign_gm(event.campaign_id) or coalesce(item.player_visible, related.player_visible, false));

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
  v_unit_value_cp := round(p_price_cp::numeric / p_quantity)::bigint;

  insert into public.campaign_inventory_items (
    campaign_id, created_by, owner_user_id, name, quantity, source_quantity_label,
    unit_value_cp, purchase_price_cp, aon_legacy_name, aon_legacy_url, source_kind, status
  ) values (
    p_campaign_id, auth.uid(), v_owner_user_id, btrim(p_name), p_quantity, p_quantity::text,
    v_unit_value_cp, p_price_cp, nullif(btrim(p_aon_legacy_name), ''), nullif(btrim(p_aon_legacy_url), ''), 'purchase', 'active'
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
