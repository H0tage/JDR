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
