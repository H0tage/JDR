-- Every inventory action is explicit. The GM can safely reverse a player-facing
-- item operation while refusing to rewrite an object that changed afterwards.

alter table public.campaign_item_events
  drop constraint if exists campaign_item_events_event_type_check;

alter table public.campaign_item_events
  add constraint campaign_item_events_event_type_check check (event_type in (
    'created', 'published', 'claimed', 'transferred', 'returned', 'split', 'merged',
    'sold', 'sale_cancelled', 'action_cancelled', 'purchased', 'dismantled',
    'consumed', 'lost', 'donated'
  ));

drop function if exists public.assign_campaign_item(uuid, uuid, text);

create function public.assign_campaign_item(
  p_item_id uuid,
  p_target_user_id uuid,
  p_comment text default null,
  p_quantity numeric default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_item public.campaign_inventory_items%rowtype;
  v_transferred_id uuid;
  v_quantity numeric;
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
  v_quantity := coalesce(p_quantity, v_item.quantity);
  if v_quantity <= 0 or v_quantity > v_item.quantity then raise exception 'Quantité invalide'; end if;
  v_event_type := case when v_item.owner_user_id is null and p_target_user_id = auth.uid() then 'claimed' else 'transferred' end;

  if v_quantity = v_item.quantity then
    update public.campaign_inventory_items set owner_user_id = p_target_user_id where id = p_item_id;
    v_transferred_id := p_item_id;
  else
    update public.campaign_inventory_items set quantity = quantity - v_quantity where id = p_item_id;
    insert into public.campaign_inventory_items (
      campaign_id, origin_loot_id, parent_item_id, created_by, owner_user_id,
      name, quantity, source_quantity_label, unit_value_cp, purchase_price_cp,
      aon_legacy_name, aon_legacy_url, source_kind, player_visible, status,
      acquired_on, counts_as_gain
    ) values (
      v_item.campaign_id, v_item.origin_loot_id, coalesce(v_item.parent_item_id, v_item.id),
      auth.uid(), p_target_user_id, v_item.name, v_quantity, v_quantity::text,
      v_item.unit_value_cp, v_item.purchase_price_cp, v_item.aon_legacy_name,
      v_item.aon_legacy_url, v_item.source_kind, v_item.player_visible, 'active',
      v_item.acquired_on, v_item.counts_as_gain
    ) returning id into v_transferred_id;
  end if;

  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type, previous_owner_user_id,
    next_owner_user_id, quantity, comment, related_item_id
  ) values (
    v_item.campaign_id, v_transferred_id, auth.uid(), v_event_type, v_item.owner_user_id,
    p_target_user_id, v_quantity, nullif(btrim(p_comment), ''),
    case when v_transferred_id <> p_item_id then p_item_id else null end
  );
  update public.campaign_item_requests set status = 'invalidated', resolved_at = now()
  where item_id in (p_item_id, v_transferred_id) and status = 'pending';
end;
$$;

revoke all on function public.assign_campaign_item(uuid, uuid, text, numeric) from public, anon, authenticated;
grant execute on function public.assign_campaign_item(uuid, uuid, text, numeric) to authenticated;

create or replace function public.cancel_campaign_item_event(
  p_event_id uuid,
  p_comment text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_event public.campaign_item_events%rowtype;
  v_item public.campaign_inventory_items%rowtype;
  v_related public.campaign_inventory_items%rowtype;
  v_transaction public.campaign_money_transactions%rowtype;
  v_restore_owner uuid;
  v_reverse_operation uuid := gen_random_uuid();
  v_output_ids uuid[];
begin
  select * into v_event from public.campaign_item_events where id = p_event_id for update;
  if v_event.id is null or v_event.event_type not in ('claimed', 'transferred', 'returned', 'split', 'merged', 'sold', 'dismantled', 'consumed', 'lost', 'donated') then
    raise exception 'Cette action ne peut pas être annulée';
  end if;
  if not public.is_campaign_gm(v_event.campaign_id)
    and not (v_event.event_type = 'sold' and v_event.actor_user_id = auth.uid()) then
    raise exception 'Seul le MJ peut annuler cette action';
  end if;
  if exists (select 1 from public.campaign_item_events event where event.reversed_event_id = p_event_id) then
    raise exception 'Cette action est déjà annulée';
  end if;
  select * into v_item from public.campaign_inventory_items where id = v_event.item_id for update;
  if v_item.id is null or exists (
    select 1 from public.campaign_item_events later
    where later.item_id = v_item.id and later.created_at > v_event.created_at
  ) then
    raise exception 'Impossible d’annuler : cet objet a été modifié depuis cette action';
  end if;

  if v_event.event_type in ('claimed', 'transferred') then
    if v_item.status <> 'active' then raise exception 'Impossible d’annuler : cet objet a été modifié depuis cette action'; end if;
    if v_event.related_item_id is null then
      update public.campaign_inventory_items set owner_user_id = v_event.previous_owner_user_id where id = v_item.id;
    else
      select * into v_related from public.campaign_inventory_items where id = v_event.related_item_id for update;
      if v_related.id is null or v_related.status <> 'active' or exists (
        select 1 from public.campaign_item_events later where later.item_id = v_related.id and later.created_at > v_event.created_at
      ) then raise exception 'Impossible d’annuler : cet objet a été modifié depuis cette action'; end if;
      update public.campaign_inventory_items set quantity = quantity + v_item.quantity where id = v_related.id;
      update public.campaign_inventory_items set status = 'merged', owner_user_id = null where id = v_item.id;
    end if;
  elsif v_event.event_type = 'returned' then
    if v_item.status <> 'active' or v_item.owner_user_id is not null then raise exception 'Impossible d’annuler : cet objet a été modifié depuis cette action'; end if;
    update public.campaign_inventory_items set owner_user_id = v_event.previous_owner_user_id where id = v_item.id;
  elsif v_event.event_type in ('consumed', 'lost', 'donated') then
    if v_item.status <> v_event.event_type then raise exception 'Impossible d’annuler : cet objet a été modifié depuis cette action'; end if;
    if v_item.parent_item_id is null then
      update public.campaign_inventory_items set status = 'active', owner_user_id = v_event.previous_owner_user_id where id = v_item.id;
    else
      select * into v_related from public.campaign_inventory_items where id = v_item.parent_item_id for update;
      if v_related.id is null or v_related.status <> 'active' or exists (
        select 1 from public.campaign_item_events later where later.item_id = v_related.id and later.created_at > v_event.created_at
      ) then raise exception 'Impossible d’annuler : cet objet a été modifié depuis cette action'; end if;
      update public.campaign_inventory_items set quantity = quantity + v_item.quantity where id = v_related.id;
      update public.campaign_inventory_items set status = 'merged', owner_user_id = null where id = v_item.id;
    end if;
  elsif v_event.event_type = 'split' then
    select * into v_related from public.campaign_inventory_items where id = v_event.related_item_id for update;
    if v_item.status <> 'active' or v_related.id is null or v_related.status <> 'active' or exists (
      select 1 from public.campaign_item_events later where later.item_id = v_related.id and later.created_at > v_event.created_at
    ) then raise exception 'Impossible d’annuler : cet objet a été modifié depuis cette action'; end if;
    update public.campaign_inventory_items set quantity = quantity + v_related.quantity where id = v_item.id;
    update public.campaign_inventory_items set status = 'merged', owner_user_id = null where id = v_related.id;
  elsif v_event.event_type = 'merged' then
    select * into v_related from public.campaign_inventory_items where id = v_event.related_item_id for update;
    if v_item.status <> 'merged' or v_related.id is null or v_related.status <> 'active' or v_related.quantity < v_event.quantity or exists (
      select 1 from public.campaign_item_events later where later.item_id = v_related.id and later.created_at > v_event.created_at
    ) then raise exception 'Impossible d’annuler : cet objet a été modifié depuis cette action'; end if;
    update public.campaign_inventory_items set quantity = quantity - v_event.quantity where id = v_related.id;
    update public.campaign_inventory_items set status = 'active', owner_user_id = v_related.owner_user_id, quantity = v_event.quantity where id = v_item.id;
  elsif v_event.event_type = 'dismantled' then
    select array_agg(id) into v_output_ids from public.campaign_inventory_items where parent_item_id = v_item.id and source_kind = 'dismantle' and status = 'active';
    if v_item.status <> 'dismantled' or coalesce(array_length(v_output_ids, 1), 0) = 0 or exists (
      select 1 from public.campaign_item_events later where later.item_id = any(v_output_ids) and later.created_at > v_event.created_at
    ) then raise exception 'Impossible d’annuler : cet objet ou ses composants ont été modifiés depuis cette action'; end if;
    update public.campaign_inventory_items set status = 'merged', owner_user_id = null where id = any(v_output_ids);
    update public.campaign_inventory_items set status = 'active', owner_user_id = v_event.previous_owner_user_id where id = v_item.id;
  else
    if v_item.status <> 'sold' then raise exception 'Impossible d’annuler : cet objet a été modifié depuis cette action'; end if;
    v_restore_owner := case when public.is_active_campaign_player(v_event.campaign_id, v_event.previous_owner_user_id) then v_event.previous_owner_user_id else null end;
    update public.campaign_inventory_items set status = 'active', owner_user_id = v_restore_owner where id = v_item.id;
    select * into v_transaction from public.campaign_money_transactions where operation_id = v_event.money_operation_id and kind = 'sale' limit 1;
    if v_transaction.id is not null then
      insert into public.campaign_money_transactions (operation_id, campaign_id, actor_user_id, kind, source_account, destination_account, amount_cp, comment, related_item_id, reversed_transaction_id)
      values (v_reverse_operation, v_event.campaign_id, auth.uid(), 'reversal', 'common', 'external', v_transaction.amount_cp, nullif(btrim(p_comment), ''), v_event.item_id, v_transaction.id);
    end if;
  end if;

  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type, previous_owner_user_id,
    next_owner_user_id, quantity, value_cp, comment, reversed_event_id, money_operation_id
  ) values (
    v_event.campaign_id, v_event.item_id, auth.uid(),
    case when v_event.event_type = 'sold' then 'sale_cancelled' else 'action_cancelled' end,
    v_event.next_owner_user_id, v_event.previous_owner_user_id, v_event.quantity,
    v_event.value_cp, nullif(btrim(p_comment), ''), v_event.id, v_reverse_operation
  );
end;
$$;
