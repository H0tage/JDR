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

  update public.campaign_loot set player_visible = p_visible where id = p_loot_id;

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

