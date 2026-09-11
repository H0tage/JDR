-- Mise à jour économique : aucune suppression de données.
-- Vérifier une sauvegarde avant l’exécution. Exécuter le bloc entier.
begin;
set local lock_timeout = '10s';
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

-- Only reorder existing notes; never overwrite their text from a stale drag snapshot.
create or replace function public.reorder_quest_entries(p_campaign_id uuid, p_entries jsonb)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if not public.is_campaign_member(p_campaign_id) then
    raise exception 'Cette campagne est inaccessible';
  end if;
  if jsonb_typeof(p_entries) is distinct from 'array' then
    raise exception 'Classement invalide';
  end if;
  perform id from public.quest_entries where campaign_id = p_campaign_id order by id for update;
  if (select count(*) from jsonb_to_recordset(p_entries) as e(id uuid)) <>
     (select count(distinct id) from jsonb_to_recordset(p_entries) as e(id uuid))
     or jsonb_array_length(p_entries) <> (select count(*) from public.quest_entries where campaign_id = p_campaign_id)
     or exists (
       select 1 from jsonb_to_recordset(p_entries) as e(id uuid, previous_category text, previous_order integer, category text, sort_order integer)
       left join public.quest_entries q on q.id = e.id and q.campaign_id = p_campaign_id
       where q.id is null or q.category is distinct from e.previous_category
         or q.sort_order is distinct from e.previous_order
         or e.category is null or e.sort_order is null or e.sort_order < 0
     ) then
    raise exception 'Le classement a changé depuis : actualisez le carnet avant de réessayer';
  end if;
  update public.quest_entries q set category = e.category, sort_order = e.sort_order
    from jsonb_to_recordset(p_entries) as e(id uuid, category text, sort_order integer)
    where q.id = e.id and q.campaign_id = p_campaign_id;
end;
$$;
revoke all on function public.reorder_quest_entries(uuid,jsonb) from public, anon;
grant execute on function public.reorder_quest_entries(uuid,jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
