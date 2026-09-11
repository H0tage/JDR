-- Preserve the existing cancellation behavior, but inspect inactive outputs too.
-- Lock all outputs before checking them so a concurrent consumption cannot slip in.
alter table public.campaign_item_events add column if not exists dismantle_output_ids uuid[];

-- Associate each new dismantling with its exact outputs, independently of timestamps.
do $$
declare
  definition text := pg_get_functiondef('public.dismantle_campaign_item(uuid,jsonb,text)'::regprocedure);
begin
  if position('return v_output_ids;' in definition) = 0 then
    raise exception 'Unexpected dismantle function';
  end if;
  definition := replace(definition, 'return v_output_ids;', $record$
    update public.campaign_item_events set dismantle_output_ids = v_output_ids
      where item_id = p_item_id and event_type = 'dismantled' and related_item_id = v_output_ids[1];
    return v_output_ids;
  $record$);
  execute definition;
end;
$$;
do $$
declare
  definition text := pg_get_functiondef('public.cancel_campaign_item_event(uuid,text)'::regprocedure);
  old_fragment text := 'select array_agg(id) into v_output_ids from public.campaign_inventory_items where parent_item_id = v_item.id and source_kind = ''dismantle'' and status = ''active'';';
begin
  if position(old_fragment in definition) = 0 then
    raise exception 'Unexpected cancellation function: review dismantle guard before migration';
  end if;
  definition := replace(definition, old_fragment, $guard$
    perform id from public.campaign_inventory_items
      where parent_item_id = v_item.id and source_kind = 'dismantle' order by id for update;
    if exists (select 1 from public.campaign_inventory_items
      where parent_item_id = v_item.id and source_kind = 'dismantle' and status <> 'active') then
      raise exception 'Impossible d’annuler : cet objet ou ses composants ont été modifiés depuis cette action';
    end if;
    select array_agg(id) into v_output_ids from public.campaign_inventory_items
      where parent_item_id = v_item.id and source_kind = 'dismantle';
  $guard$);
  definition := replace(definition,
    'later.item_id = any(v_output_ids) and later.created_at > v_event.created_at',
    'later.item_id = any(v_output_ids) and (later.created_at > v_event.created_at or (later.created_at = v_event.created_at and later.event_type <> ''created''))');
  definition := replace(definition,
    'parent_item_id = v_item.id and source_kind = ''dismantle''',
    'parent_item_id = v_item.id and source_kind = ''dismantle'' and (case when v_event.dismantle_output_ids is not null then id = any(v_event.dismantle_output_ids) else created_at >= v_event.created_at end)');
  execute definition;
end;
$$;
