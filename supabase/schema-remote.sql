


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE SCHEMA IF NOT EXISTS "storage";


ALTER SCHEMA "storage" OWNER TO "supabase_admin";


CREATE TYPE "public"."relationship_evidence" AS ENUM (
    'E',
    'S',
    'H',
    'E/S',
    'S/H'
);


ALTER TYPE "public"."relationship_evidence" OWNER TO "postgres";


CREATE TYPE "public"."relationship_tone" AS ENUM (
    'alliance',
    'cooperation',
    'tension',
    'hostility',
    'unclear'
);


ALTER TYPE "public"."relationship_tone" OWNER TO "postgres";


CREATE TYPE "public"."service_scale" AS ENUM (
    'Mineure',
    'Modérée',
    'Majeure'
);


ALTER TYPE "public"."service_scale" OWNER TO "postgres";


CREATE TYPE "public"."visibility_status" AS ENUM (
    'gm_only',
    'ready',
    'players'
);


ALTER TYPE "public"."visibility_status" OWNER TO "postgres";


CREATE TYPE "storage"."buckettype" AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


ALTER TYPE "storage"."buckettype" OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "public"."accept_campaign_invitation"("p_token" "uuid") RETURNS TABLE("campaign_id" "uuid", "campaign_name" "text", "role" "text", "already_member" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
#variable_conflict use_column
declare
  invite public.campaign_invites%rowtype;
  campaign_name_value text;
  campaign_capacity smallint;
  member_count integer;
  exists_member boolean;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into invite from public.campaign_invites where token = p_token;
  if not found then raise exception 'Invitation invalide'; end if;
  if invite.revoked_at is not null then raise exception 'Invitation révoquée'; end if;
  if invite.expires_at is not null and invite.expires_at <= now() then raise exception 'Invitation expirée'; end if;

  select campaign.name, campaign.max_participants
  into campaign_name_value, campaign_capacity
  from public.campaigns campaign
  where campaign.id = invite.campaign_id
  for update;
  if not found then raise exception 'Campagne introuvable'; end if;

  select exists (
    select 1 from public.campaign_members member
    where member.campaign_id = invite.campaign_id and member.user_id = auth.uid()
  ) into exists_member;

  if not exists_member then
    select count(*) into member_count
    from public.campaign_members member
    where member.campaign_id = invite.campaign_id;
    if member_count >= campaign_capacity then
      raise exception 'La campagne que vous cherchez à rejoindre est pleine. Contactez votre MJ pour qu''il libère de la place, ou augmente la taille maximale de la campagne.';
    end if;
  end if;

  insert into public.user_profiles (user_id) values (auth.uid())
  on conflict on constraint user_profiles_pkey do nothing;
  insert into public.campaign_members (campaign_id, user_id, role)
  values (invite.campaign_id, auth.uid(), 'player')
  on conflict on constraint campaign_members_pkey do nothing;
  insert into public.player_pages (campaign_id, user_id)
  values (invite.campaign_id, auth.uid())
  on conflict on constraint player_pages_pkey do nothing;

  return query select invite.campaign_id, campaign_name_value, 'player'::text, exists_member;
end;
$$;


ALTER FUNCTION "public"."accept_campaign_invitation"("p_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_reputation_milestone"("milestone_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  m public.reputation_milestones%rowtype;
begin
  select * into m from public.reputation_milestones where id = milestone_id for update;
  if not found then raise exception 'Jalon introuvable'; end if;
  if not public.is_campaign_gm(m.campaign_id) then raise exception 'Accès refusé'; end if;
  if m.applied then raise exception 'Ce jalon est déjà appliqué'; end if;

  if m.beneficiary_faction_id is not null and m.rp_gain > 0 then
    insert into public.journal_entries
      (campaign_id, faction_id, occurred_on, volume, title, details, rp_delta, jf_delta, visibility, source_reference)
    values
      (m.campaign_id, m.beneficiary_faction_id, current_date, m.volume, m.title || ' — gain', m.condition, m.rp_gain, m.rp_gain, 'ready', m.source_reference);
  end if;
  if m.harmed_faction_id is not null and m.rp_loss < 0 then
    insert into public.journal_entries
      (campaign_id, faction_id, occurred_on, volume, title, details, rp_delta, jf_delta, visibility, source_reference)
    values
      (m.campaign_id, m.harmed_faction_id, current_date, m.volume, m.title || ' — perte', m.condition, m.rp_loss, 0, 'ready', m.source_reference);
  end if;

  update public.reputation_milestones set applied = true, applied_at = now() where id = milestone_id;
end;
$$;


ALTER FUNCTION "public"."apply_reputation_milestone"("milestone_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_campaign_item"("p_item_id" "uuid", "p_target_user_id" "uuid", "p_comment" "text" DEFAULT NULL::"text", "p_quantity" numeric DEFAULT NULL::numeric) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."assign_campaign_item"("p_item_id" "uuid", "p_target_user_id" "uuid", "p_comment" "text", "p_quantity" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_first_campaign_owner"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if new.role = 'gm' then
    update public.campaigns
    set owner_user_id = new.user_id
    where id = new.campaign_id and owner_user_id is null;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."assign_first_campaign_owner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."batch_update_campaign_items"("p_item_ids" "uuid"[], "p_action" "text", "p_target_user_id" "uuid" DEFAULT NULL::"uuid", "p_comment" "text" DEFAULT NULL::"text") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_item_id uuid;
  v_count integer := 0;
begin
  if coalesce(array_length(p_item_ids, 1), 0) = 0
    or array_length(p_item_ids, 1) > 100
    or p_action not in ('assign', 'return', 'consumed', 'lost', 'donated') then
    raise exception 'Action groupÃ©e invalide';
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


ALTER FUNCTION "public"."batch_update_campaign_items"("p_item_ids" "uuid"[], "p_action" "text", "p_target_user_id" "uuid", "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_control_campaign_item"("p_item_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."can_control_campaign_item"("p_item_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_campaign_item_event"("p_event_id" "uuid", "p_comment" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."cancel_campaign_item_event"("p_event_id" "uuid", "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_campaign_item_request"("p_request_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  update public.campaign_item_requests
  set status = 'cancelled', resolved_at = now()
  where id = p_request_id and requester_user_id = auth.uid() and status = 'pending';
  if not found then raise exception 'Demande introuvable'; end if;
end;
$$;


ALTER FUNCTION "public"."cancel_campaign_item_request"("p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_campaign_money_debt"("p_debt_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."cancel_campaign_money_debt"("p_debt_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_campaign_money_transaction"("p_transaction_id" "uuid", "p_comment" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_transaction public.campaign_money_transactions%rowtype;
  v_reversal_id uuid;
begin
  select * into v_transaction
  from public.campaign_money_transactions
  where id = p_transaction_id for update;
  if v_transaction.id is null or v_transaction.kind in ('sale', 'purchase', 'reversal', 'departure_transfer') then
    raise exception 'Cette opÃ©ration doit Ãªtre annulÃ©e depuis lâ€™objet concernÃ©';
  end if;
  if v_transaction.actor_user_id <> auth.uid()
    and not public.is_campaign_gm(v_transaction.campaign_id) then
    raise exception 'Vous ne pouvez pas annuler cette opÃ©ration';
  end if;
  if exists (
    select 1 from public.campaign_money_transactions reversal
    where reversal.reversed_transaction_id = p_transaction_id
  ) then raise exception 'Cette opÃ©ration est dÃ©jÃ  annulÃ©e'; end if;

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


ALTER FUNCTION "public"."cancel_campaign_money_transaction"("p_transaction_id" "uuid", "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."capture_quest_journal_revision"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if old.content is not distinct from new.content then
    return new;
  end if;

  insert into public.quest_journal_revisions (campaign_id, content)
  values (old.campaign_id, old.content);

  delete from public.quest_journal_revisions revision
  where revision.campaign_id = new.campaign_id
    and revision.id in (
      select id
      from public.quest_journal_revisions
      where campaign_id = new.campaign_id
      order by created_at desc, id desc
      offset 100
    );

  return new;
end;
$$;


ALTER FUNCTION "public"."capture_quest_journal_revision"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_campaign"("p_name" "text", "p_description" "text" DEFAULT NULL::"text") RETURNS TABLE("campaign_id" "uuid", "slug" "text", "name" "text", "description" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  created_id uuid;
  created_slug text;
  clean_name text := btrim(coalesce(p_name, ''));
  clean_description text := nullif(btrim(coalesce(p_description, '')), '');
  attempt integer;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if char_length(clean_name) < 2 or char_length(clean_name) > 80 then
    raise exception 'Le nom doit comporter entre 2 et 80 caractères';
  end if;
  if clean_description is not null and char_length(clean_description) > 500 then
    raise exception 'La description ne peut pas dépasser 500 caractères';
  end if;

  for attempt in 1..20 loop
    created_slug := public.generate_available_campaign_slug();
    begin
      insert into public.campaigns (slug, name, description, public_enabled, owner_user_id)
      values (created_slug, clean_name, clean_description, true, auth.uid())
      returning id into created_id;
      exit;
    exception when unique_violation then
      created_id := null;
    end;
  end loop;
  if created_id is null then raise exception 'Impossible de réserver un identifiant de campagne'; end if;

  insert into public.campaign_members (campaign_id, user_id, role)
  values (created_id, auth.uid(), 'gm');
  insert into public.campaign_settings (campaign_id) values (created_id);
  insert into public.campaign_factions (campaign_id, faction_id, is_player_visible)
  select created_id, faction.id, true from public.factions faction;
  perform public.seed_campaign_reference_data(created_id, 'all');

  return query select created_id, created_slug, clean_name, clean_description;
end;
$$;


ALTER FUNCTION "public"."create_campaign"("p_name" "text", "p_description" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_campaign_invite"("p_campaign_id" "uuid", "p_expires_at" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS TABLE("id" "uuid", "token" "uuid", "expires_at" timestamp with time zone, "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_campaign_gm(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception 'La date d’expiration doit être dans le futur';
  end if;

  return query
  insert into public.campaign_invites (campaign_id, expires_at, created_by)
  values (p_campaign_id, p_expires_at, auth.uid())
  returning campaign_invites.id, campaign_invites.token,
    campaign_invites.expires_at, campaign_invites.created_at;
end;
$$;


ALTER FUNCTION "public"."create_campaign_invite"("p_campaign_id" "uuid", "p_expires_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_campaign_money_debt"("p_campaign_id" "uuid", "p_debtor_user_id" "uuid", "p_creditor_user_id" "uuid", "p_amount_cp" bigint, "p_comment" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_debt_id uuid;
begin
  if not public.is_campaign_member(p_campaign_id) then raise exception 'AccÃ¨s refusÃ©'; end if;
  if auth.uid() not in (p_debtor_user_id, p_creditor_user_id)
    and not public.is_campaign_gm(p_campaign_id) then raise exception 'Dette non autorisÃ©e'; end if;
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


ALTER FUNCTION "public"."create_campaign_money_debt"("p_campaign_id" "uuid", "p_debtor_user_id" "uuid", "p_creditor_user_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_manual_campaign_item"("p_campaign_id" "uuid", "p_name" "text", "p_quantity" numeric DEFAULT 1, "p_unit_value_cp" bigint DEFAULT NULL::bigint, "p_owner_user_id" "uuid" DEFAULT NULL::"uuid", "p_aon_legacy_name" "text" DEFAULT NULL::"text", "p_aon_legacy_url" "text" DEFAULT NULL::"text", "p_comment" "text" DEFAULT NULL::"text", "p_counts_as_gain" boolean DEFAULT true) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_item_id uuid;
begin
  if not public.is_campaign_gm(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;

  if btrim(p_name) = ''
    or p_quantity <= 0
    or coalesce(p_unit_value_cp, 0) < 0
  then
    raise exception 'Objet invalide';
  end if;

  if p_owner_user_id is not null
    and not public.is_active_campaign_player(
      p_campaign_id,
      p_owner_user_id
    )
  then
    raise exception 'Propriétaire invalide';
  end if;

  insert into public.campaign_inventory_items (
    campaign_id,
    created_by,
    owner_user_id,
    name,
    quantity,
    source_quantity_label,
    unit_value_cp,
    aon_legacy_name,
    aon_legacy_url,
    source_kind,
    status,
    counts_as_gain
  ) values (
    p_campaign_id,
    auth.uid(),
    p_owner_user_id,
    btrim(p_name),
    p_quantity,
    p_quantity::text,
    p_unit_value_cp,
    nullif(btrim(p_aon_legacy_name), ''),
    nullif(btrim(p_aon_legacy_url), ''),
    'gm',
    'active',
    coalesce(p_counts_as_gain, true)
  )
  returning id into v_item_id;

  insert into public.campaign_item_events (
    campaign_id,
    item_id,
    actor_user_id,
    event_type,
    next_owner_user_id,
    quantity,
    value_cp,
    comment
  ) values (
    p_campaign_id,
    v_item_id,
    auth.uid(),
    'created',
    p_owner_user_id,
    p_quantity,
    p_unit_value_cp,
    nullif(btrim(p_comment), '')
  );

  return v_item_id;
end;
$$;


ALTER FUNCTION "public"."create_manual_campaign_item"("p_campaign_id" "uuid", "p_name" "text", "p_quantity" numeric, "p_unit_value_cp" bigint, "p_owner_user_id" "uuid", "p_aon_legacy_name" "text", "p_aon_legacy_url" "text", "p_comment" "text", "p_counts_as_gain" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_bestiary_entry"("p_entry_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare entry public.bestiary_entries%rowtype;
begin
  select * into entry from public.bestiary_entries where id = p_entry_id for update;
  if not found then raise exception 'Créature introuvable'; end if;
  if not public.is_campaign_gm(entry.campaign_id) then raise exception 'Accès refusé'; end if;
  insert into public.bestiary_events (campaign_id, entry_id, creature_name, event_type, actor_user_id)
  values (entry.campaign_id, entry.id, entry.name, 'deleted', auth.uid());
  delete from public.bestiary_entries where id = p_entry_id;
  return entry.image_path;
end;
$$;


ALTER FUNCTION "public"."delete_bestiary_entry"("p_entry_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_owned_campaign"("p_campaign_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  deleted_slug text;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  delete from public.campaigns
  where id = p_campaign_id and owner_user_id = auth.uid()
  returning slug into deleted_slug;
  if deleted_slug is null then
    raise exception 'Seul le propriétaire peut supprimer cette campagne';
  end if;
  return deleted_slug;
end;
$$;


ALTER FUNCTION "public"."delete_owned_campaign"("p_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dismantle_campaign_item"("p_item_id" "uuid", "p_outputs" "jsonb", "p_comment" "text" DEFAULT NULL::"text") RETURNS "uuid"[]
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
    raise exception 'Vous ne pouvez pas dÃ©monter cet objet';
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


ALTER FUNCTION "public"."dismantle_campaign_item"("p_item_id" "uuid", "p_outputs" "jsonb", "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_available_campaign_slug"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  candidate text;
begin
  -- Les paires sont ordonnées : vampire-bonegolem et bonegolem-vampire sont
  -- deux identifiants différents. random() répartit les nouvelles campagnes.
  select first_word.slug || '-' || second_word.slug
  into candidate
  from public.campaign_slug_words first_word
  cross join public.campaign_slug_words second_word
  where first_word.id <> second_word.id
    and not exists (
      select 1 from public.campaigns campaign
      where campaign.slug = first_word.slug || '-' || second_word.slug
    )
  order by random()
  limit 1;

  if candidate is not null then
    return candidate;
  end if;

  -- Ce parcours n'est atteint qu'après épuisement de toutes les paires. Sans
  -- ORDER BY random(), PostgreSQL peut s'arrêter dès le premier triplet libre.
  select first_word.slug || '-' || second_word.slug || '-' || third_word.slug
  into candidate
  from public.campaign_slug_words first_word
  cross join public.campaign_slug_words second_word
  cross join public.campaign_slug_words third_word
  where first_word.id <> second_word.id
    and first_word.id <> third_word.id
    and second_word.id <> third_word.id
    and not exists (
      select 1 from public.campaigns campaign
      where campaign.slug = first_word.slug || '-' || second_word.slug || '-' || third_word.slug
    )
  order by first_word.id, second_word.id, third_word.id
  limit 1;

  if candidate is null then
    raise exception 'Aucune combinaison de noms de campagne n’est encore disponible';
  end if;
  return candidate;
end;
$$;


ALTER FUNCTION "public"."generate_available_campaign_slug"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_campaign_capacity"("p_campaign_id" "uuid") RETURNS TABLE("max_participants" smallint, "current_participants" bigint)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_campaign_member(p_campaign_id) then raise exception 'Accès refusé'; end if;
  return query
  select campaign.max_participants, count(member.user_id)
  from public.campaigns campaign
  left join public.campaign_members member on member.campaign_id = campaign.id
  where campaign.id = p_campaign_id
  group by campaign.id, campaign.max_participants;
end;
$$;


ALTER FUNCTION "public"."get_campaign_capacity"("p_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_campaign_invitation"("p_token" "uuid") RETURNS TABLE("campaign_id" "uuid", "campaign_name" "text", "status" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select invite.campaign_id, campaign.name,
    case
      when invite.revoked_at is not null then 'revoked'
      when invite.expires_at is not null and invite.expires_at <= now() then 'expired'
      else 'valid'
    end
  from public.campaign_invites invite
  join public.campaigns campaign on campaign.id = invite.campaign_id
  where invite.token = p_token;
$$;


ALTER FUNCTION "public"."get_campaign_invitation"("p_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_player_page"("p_campaign_id" "uuid") RETURNS TABLE("campaign_id" "uuid", "user_id" "uuid", "display_name" "text", "character_name" "text", "character_title" "text", "character_summary" "text", "pathbuilder_url" "text", "notes" "text", "objectives" "text", "updated_at" timestamp with time zone, "image_path" "text", "image_x" numeric, "image_y" numeric, "image_zoom" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not exists (
    select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id
      and member.user_id = auth.uid()
      and member.role = 'player'
  ) then raise exception 'Accès refusé'; end if;

  insert into public.user_profiles (user_id) values (auth.uid())
  on conflict on constraint user_profiles_pkey do nothing;
  insert into public.player_pages (campaign_id, user_id) values (p_campaign_id, auth.uid())
  on conflict on constraint player_pages_pkey do nothing;

  return query
  select page.campaign_id, page.user_id, profile.display_name,
    page.character_name, page.character_title, page.character_summary,
    page.pathbuilder_url, page.notes, page.objectives, page.updated_at,
    page.image_path, page.image_x, page.image_y, page.image_zoom
  from public.player_pages page
  join public.user_profiles profile on profile.user_id = page.user_id
  where page.campaign_id = p_campaign_id and page.user_id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."get_my_player_page"("p_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_profile"() RETURNS TABLE("user_id" "uuid", "display_name" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;

  insert into public.user_profiles (user_id)
  values (auth.uid())
  on conflict on constraint user_profiles_pkey do nothing;

  return query
  select profile.user_id, profile.display_name
  from public.user_profiles profile
  where profile.user_id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."get_my_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_active_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select p_user_id is not null and exists (
    select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id
      and member.user_id = p_user_id
      and member.role = 'player'
  );
$$;


ALTER FUNCTION "public"."is_active_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_campaign_gm"("target_campaign_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.campaign_members cm
    where cm.campaign_id = target_campaign_id
      and cm.user_id = auth.uid()
      and cm.role = 'gm'
  );
$$;


ALTER FUNCTION "public"."is_campaign_gm"("target_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_campaign_member"("target_campaign_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select auth.uid() is not null and exists (
    select 1
    from public.campaign_members member
    where member.campaign_id = target_campaign_id
      and member.user_id = auth.uid()
  );
$$;


ALTER FUNCTION "public"."is_campaign_member"("target_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_campaign_member_storage_path"("object_name" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
  select case
    when object_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.[a-z0-9]+$'
      then public.is_campaign_member((storage.foldername(object_name))[1]::uuid)
    else false
  end;
$_$;


ALTER FUNCTION "public"."is_campaign_member_storage_path"("object_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_gm_contact_portrait_path"("object_name" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
  select case
    when object_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.[a-z0-9]+$'
      then public.is_campaign_gm((storage.foldername(object_name))[1]::uuid)
    else false
  end;
$_$;


ALTER FUNCTION "public"."is_gm_contact_portrait_path"("object_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_own_player_character_image_path"("object_name" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
  select case
    when object_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.[a-z0-9]+$'
      then auth.uid() is not null
        and (storage.foldername(object_name))[2] = auth.uid()::text
        and exists (
          select 1 from public.campaign_members member
          where member.campaign_id = (storage.foldername(object_name))[1]::uuid
            and member.user_id = auth.uid()
            and member.role = 'player'
        )
    else false
  end;
$_$;


ALTER FUNCTION "public"."is_own_player_character_image_path"("object_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_public_bestiary_path"("object_name" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.campaigns c
    where c.public_enabled
      and c.id::text = (storage.foldername(object_name))[1]
  );
$$;


ALTER FUNCTION "public"."is_public_bestiary_path"("object_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_public_campaign"("target_campaign_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select public.is_campaign_member(target_campaign_id);
$$;


ALTER FUNCTION "public"."is_public_campaign"("target_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_public_quest_journal_image_path"("object_name" "text") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $_$
  select object_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.[a-z0-9]+$';
$_$;


ALTER FUNCTION "public"."is_public_quest_journal_image_path"("object_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."leave_campaign"("p_campaign_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if not public.is_active_campaign_player(p_campaign_id, auth.uid()) then
    raise exception 'Vous nâ€™Ãªtes pas joueur de cette campagne';
  end if;
  perform public.transfer_departing_player_assets(p_campaign_id, auth.uid());
  delete from public.campaign_members
  where campaign_id = p_campaign_id and user_id = auth.uid() and role = 'player';
  update public.loot_player_publications
  set owner_user_id = null, lifecycle_status = 'available', legacy_owner_label = null
  where campaign_id = p_campaign_id and owner_user_id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."leave_campaign"("p_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_campaign_bestiary"("p_campaign_id" "uuid") RETURNS TABLE("id" "uuid", "campaign_id" "uuid", "name" "text", "resistances" "text", "weaknesses" "text", "notes" "text", "image_path" "text", "created_by" "uuid", "is_visible" boolean, "revealed_at" timestamp with time zone, "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "creator_display_name" "text", "can_edit" boolean, "can_delete" boolean)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare viewer_is_gm boolean;
begin
  if not public.is_campaign_member(p_campaign_id) then raise exception 'Accès refusé'; end if;
  viewer_is_gm := public.is_campaign_gm(p_campaign_id);
  return query
  select entry.id, entry.campaign_id, entry.name, entry.resistances,
    entry.weaknesses, entry.notes, entry.image_path, entry.created_by,
    entry.is_visible, entry.revealed_at, entry.created_at, entry.updated_at,
    case when entry.created_by is null then 'Joueur parti' else coalesce(profile.display_name, 'Sans pseudo') end,
    (viewer_is_gm or entry.created_by = auth.uid()), viewer_is_gm
  from public.bestiary_entries entry
  left join public.user_profiles profile on profile.user_id = entry.created_by
  where entry.campaign_id = p_campaign_id and (viewer_is_gm or entry.is_visible)
  order by entry.is_visible desc,
    case when entry.is_visible then entry.revealed_at end,
    entry.created_at, entry.id;
end;
$$;


ALTER FUNCTION "public"."list_campaign_bestiary"("p_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_campaign_invites"("p_campaign_id" "uuid") RETURNS TABLE("id" "uuid", "token" "uuid", "expires_at" timestamp with time zone, "revoked_at" timestamp with time zone, "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_campaign_gm(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;

  return query
  select invite.id, invite.token, invite.expires_at, invite.revoked_at, invite.created_at
  from public.campaign_invites invite
  where invite.campaign_id = p_campaign_id
  order by invite.created_at desc;
end;
$$;


ALTER FUNCTION "public"."list_campaign_invites"("p_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_campaign_members"("p_campaign_id" "uuid") RETURNS TABLE("user_id" "uuid", "display_name" "text", "role" "text", "joined_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_campaign_member(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;

  return query
  select member.user_id,
    coalesce(profile.display_name, case member.role when 'gm' then 'Maître de jeu' else 'Sans pseudo' end),
    member.role,
    member.created_at
  from public.campaign_members member
  left join public.user_profiles profile on profile.user_id = member.user_id
  where member.campaign_id = p_campaign_id
  order by case member.role when 'gm' then 0 else 1 end,
    lower(coalesce(profile.display_name, 'Sans pseudo'));
end;
$$;


ALTER FUNCTION "public"."list_campaign_members"("p_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_campaign_player_pages"("p_campaign_id" "uuid") RETURNS TABLE("campaign_id" "uuid", "user_id" "uuid", "display_name" "text", "active" boolean, "is_own" boolean, "character_name" "text", "character_title" "text", "character_summary" "text", "pathbuilder_url" "text", "notes" "text", "objectives" "text", "updated_at" timestamp with time zone, "image_path" "text", "image_x" numeric, "image_y" numeric, "image_zoom" numeric)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  viewer_is_gm boolean := public.is_campaign_gm(p_campaign_id);
begin
  if not public.is_campaign_member(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;

  return query
  select page.campaign_id,
    page.user_id,
    coalesce(profile.display_name, 'Sans pseudo'),
    (member.user_id is not null),
    (page.user_id = auth.uid()),
    page.character_name,
    page.character_title,
    page.character_summary,
    case when page.user_id = auth.uid() then page.pathbuilder_url else null end,
    case when viewer_is_gm or page.user_id = auth.uid() then page.notes else null end,
    page.objectives,
    page.updated_at,
    page.image_path,
    page.image_x,
    page.image_y,
    page.image_zoom
  from public.player_pages page
  left join public.user_profiles profile on profile.user_id = page.user_id
  left join public.campaign_members member
    on member.campaign_id = page.campaign_id
    and member.user_id = page.user_id
    and member.role = 'player'
  where page.campaign_id = p_campaign_id
    and (viewer_is_gm or member.user_id is not null)
  order by member.user_id is null,
    page.user_id <> auth.uid(),
    lower(coalesce(profile.display_name, 'Sans pseudo'));
end;
$$;


ALTER FUNCTION "public"."list_campaign_player_pages"("p_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_campaign_players"("p_campaign_id" "uuid") RETURNS TABLE("user_id" "uuid", "display_name" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_campaign_member(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;

  return query
  select member.user_id, coalesce(profile.display_name, 'Sans pseudo')
  from public.campaign_members member
  left join public.user_profiles profile on profile.user_id = member.user_id
  where member.campaign_id = p_campaign_id and member.role = 'player'
  order by lower(coalesce(profile.display_name, 'Sans pseudo')), member.created_at;
end;
$$;


ALTER FUNCTION "public"."list_campaign_players"("p_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_my_campaigns"() RETURNS TABLE("campaign_id" "uuid", "slug" "text", "name" "text", "description" "text", "role" "text", "joined_at" timestamp with time zone, "is_owner" boolean, "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select campaign.id, campaign.slug, campaign.name, campaign.description,
    member.role, member.created_at, campaign.owner_user_id = auth.uid(),
    campaign.created_at
  from public.campaign_members member
  join public.campaigns campaign on campaign.id = member.campaign_id
  where member.user_id = auth.uid()
  order by lower(campaign.name), campaign.id;
$$;


ALTER FUNCTION "public"."list_my_campaigns"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_my_player_relationship_notes"("p_campaign_id" "uuid") RETURNS TABLE("target_user_id" "uuid", "notes" "text", "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not exists (
    select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id
      and member.user_id = auth.uid()
      and member.role = 'player'
  ) then raise exception 'Accès refusé'; end if;

  return query
  select note.target_user_id, note.notes, note.updated_at
  from public.player_relationship_notes note
  join public.campaign_members target
    on target.campaign_id = note.campaign_id
    and target.user_id = note.target_user_id
    and target.role = 'player'
  where note.campaign_id = p_campaign_id
    and note.author_user_id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."list_my_player_relationship_notes"("p_campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."merge_campaign_items"("p_target_item_id" "uuid", "p_source_item_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
    raise exception 'Seules deux piles Ã©quivalentes peuvent Ãªtre fusionnÃ©es';
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


ALTER FUNCTION "public"."merge_campaign_items"("p_target_item_id" "uuid", "p_source_item_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pay_campaign_money_debt"("p_debt_id" "uuid", "p_amount_cp" bigint, "p_comment" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_debt public.campaign_money_debts%rowtype;
begin
  select * into v_debt from public.campaign_money_debts where id = p_debt_id for update;
  if v_debt.id is null or v_debt.status <> 'open' then raise exception 'Dette introuvable'; end if;
  if v_debt.debtor_user_id <> auth.uid() and not public.is_campaign_gm(v_debt.campaign_id) then
    raise exception 'Seul le dÃ©biteur peut rembourser cette dette';
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


ALTER FUNCTION "public"."pay_campaign_money_debt"("p_debt_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."purchase_campaign_item"("p_campaign_id" "uuid", "p_name" "text", "p_quantity" numeric, "p_price_cp" bigint, "p_personal_amount_cp" bigint, "p_common_amount_cp" bigint, "p_owner_user_id" "uuid" DEFAULT NULL::"uuid", "p_unit_value_cp" bigint DEFAULT NULL::bigint, "p_aon_legacy_name" "text" DEFAULT NULL::"text", "p_aon_legacy_url" "text" DEFAULT NULL::"text", "p_comment" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_owner_user_id uuid := coalesce(p_owner_user_id, auth.uid());
  v_item_id uuid;
  v_operation_id uuid := gen_random_uuid();
  v_unit_value_cp bigint;
begin
  if not public.is_campaign_member(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;

  if v_owner_user_id <> auth.uid()
    and not public.is_campaign_gm(p_campaign_id)
  then
    raise exception 'Vous ne pouvez acheter que pour votre personnage';
  end if;

  if not public.is_active_campaign_player(
    p_campaign_id,
    v_owner_user_id
  )
  then
    raise exception 'Propriétaire invalide';
  end if;

  if btrim(p_name) = ''
    or p_quantity <= 0
    or p_price_cp < 0
    or p_personal_amount_cp < 0
    or p_common_amount_cp < 0
    or p_personal_amount_cp + p_common_amount_cp <> p_price_cp
  then
    raise exception 'Achat invalide';
  end if;

  v_unit_value_cp :=
    case
      when p_price_cp = 0 then 0
      else greatest(
        1,
        round(p_price_cp::numeric / p_quantity)::bigint
      )
    end;

  insert into public.campaign_inventory_items (
    campaign_id,
    created_by,
    owner_user_id,
    name,
    quantity,
    source_quantity_label,
    unit_value_cp,
    purchase_price_cp,
    aon_legacy_name,
    aon_legacy_url,
    source_kind,
    status,
    counts_as_gain
  ) values (
    p_campaign_id,
    auth.uid(),
    v_owner_user_id,
    btrim(p_name),
    p_quantity,
    p_quantity::text,
    v_unit_value_cp,
    p_price_cp,
    nullif(btrim(p_aon_legacy_name), ''),
    nullif(btrim(p_aon_legacy_url), ''),
    'purchase',
    'active',
    false
  )
  returning id into v_item_id;

  if p_personal_amount_cp > 0 then
    insert into public.campaign_money_transactions (
      operation_id,
      campaign_id,
      actor_user_id,
      kind,
      source_account,
      source_user_id,
      destination_account,
      amount_cp,
      comment,
      related_item_id
    ) values (
      v_operation_id,
      p_campaign_id,
      auth.uid(),
      'purchase',
      'player',
      v_owner_user_id,
      'external',
      p_personal_amount_cp,
      nullif(btrim(p_comment), ''),
      v_item_id
    );
  end if;

  if p_common_amount_cp > 0 then
    insert into public.campaign_money_transactions (
      operation_id,
      campaign_id,
      actor_user_id,
      kind,
      source_account,
      destination_account,
      amount_cp,
      comment,
      related_item_id
    ) values (
      v_operation_id,
      p_campaign_id,
      auth.uid(),
      'purchase',
      'common',
      'external',
      p_common_amount_cp,
      nullif(btrim(p_comment), ''),
      v_item_id
    );
  end if;

  insert into public.campaign_item_events (
    campaign_id,
    item_id,
    actor_user_id,
    event_type,
    next_owner_user_id,
    quantity,
    value_cp,
    comment,
    money_operation_id
  ) values (
    p_campaign_id,
    v_item_id,
    auth.uid(),
    'purchased',
    v_owner_user_id,
    p_quantity,
    p_price_cp,
    nullif(btrim(p_comment), ''),
    v_operation_id
  );

  return v_item_id;
end;
$$;


ALTER FUNCTION "public"."purchase_campaign_item"("p_campaign_id" "uuid", "p_name" "text", "p_quantity" numeric, "p_price_cp" bigint, "p_personal_amount_cp" bigint, "p_common_amount_cp" bigint, "p_owner_user_id" "uuid", "p_unit_value_cp" bigint, "p_aon_legacy_name" "text", "p_aon_legacy_url" "text", "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_common_income"("p_campaign_id" "uuid", "p_amount_cp" bigint, "p_comment" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_transaction_id uuid;
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'AccÃ¨s refusÃ©'; end if;
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


ALTER FUNCTION "public"."record_common_income"("p_campaign_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_personal_money"("p_campaign_id" "uuid", "p_kind" "text", "p_amount_cp" bigint, "p_user_id" "uuid" DEFAULT NULL::"uuid", "p_comment" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user_id uuid := coalesce(p_user_id, auth.uid());
  v_transaction_id uuid;
begin
  if p_kind not in ('income', 'expense') or p_amount_cp <= 0 then
    raise exception 'OpÃ©ration personnelle invalide';
  end if;
  if not public.is_campaign_member(p_campaign_id) then raise exception 'AccÃ¨s refusÃ©'; end if;
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


ALTER FUNCTION "public"."record_personal_money"("p_campaign_id" "uuid", "p_kind" "text", "p_amount_cp" bigint, "p_user_id" "uuid", "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'AccÃ¨s refusÃ©'; end if;
  if not public.is_active_campaign_player(p_campaign_id, p_user_id) then return; end if;
  perform public.transfer_departing_player_assets(p_campaign_id, p_user_id);
  delete from public.campaign_members
  where campaign_id = p_campaign_id and user_id = p_user_id and role = 'player';
  update public.loot_player_publications
  set owner_user_id = null, lifecycle_status = 'available', legacy_owner_label = null
  where campaign_id = p_campaign_id and owner_user_id = p_user_id;
end;
$$;


ALTER FUNCTION "public"."remove_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_campaign_item"("p_item_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_item public.campaign_inventory_items%rowtype;
  v_request_id uuid;
begin
  select * into v_item from public.campaign_inventory_items where id = p_item_id;
  if v_item.id is null or v_item.status <> 'active' or v_item.owner_user_id is null
    or v_item.owner_user_id = auth.uid() or not public.is_campaign_member(v_item.campaign_id) then
    raise exception 'Cet objet ne peut pas Ãªtre demandÃ©';
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


ALTER FUNCTION "public"."request_campaign_item"("p_item_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if p_scope not in ('archives','all') then
    raise exception 'Le nouveau registre de butin ne dépend plus d’un modèle global';
  end if;
  delete from public.archive_characters where campaign_id = p_campaign_id;
  delete from public.archive_places where campaign_id = p_campaign_id;
  perform public.seed_campaign_reference_data(p_campaign_id, 'archives');
end;
$$;


ALTER FUNCTION "public"."reset_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_campaign_item_request"("p_request_id" "uuid", "p_accept" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_request public.campaign_item_requests%rowtype;
  v_item public.campaign_inventory_items%rowtype;
begin
  select * into v_request from public.campaign_item_requests where id = p_request_id for update;
  if v_request.id is null or v_request.status <> 'pending' then raise exception 'Demande introuvable'; end if;
  if v_request.owner_user_id <> auth.uid() and not public.is_campaign_gm(v_request.campaign_id) then
    raise exception 'Vous ne pouvez pas rÃ©pondre Ã  cette demande';
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


ALTER FUNCTION "public"."resolve_campaign_item_request"("p_request_id" "uuid", "p_accept" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_reputation_milestone"("p_milestone_id" "uuid", "p_outcome" "text", "p_note" "text" DEFAULT NULL::"text", "p_effects" "jsonb" DEFAULT NULL::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  m public.reputation_milestones%rowtype;
  v_effects jsonb;
  v_effect jsonb;
  v_faction_id uuid;
  v_amount integer;
  v_jf_amount integer;
  v_previous_winner uuid;
begin
  if p_outcome not in ('pending', 'succeeded', 'missed') then
    raise exception 'État de jalon invalide';
  end if;

  select * into m
  from public.reputation_milestones
  where id = p_milestone_id
  for update;

  if not found then raise exception 'Jalon introuvable'; end if;
  if not public.is_campaign_gm(m.campaign_id) then raise exception 'Accès refusé'; end if;
  if m.status = 'excluded' and p_outcome <> 'succeeded' then
    raise exception 'Un choix écarté ne peut être remplacé que par une réussite';
  end if;

  -- Reversing or changing a successful resolution first removes the exact
  -- journal rows it created. Reputation and favour totals are journal-derived.
  delete from public.journal_entries
  where milestone_id = m.id;

  -- Reopening the selected choice restores every sibling that it excluded.
  update public.reputation_milestones
  set
    status = coalesce(status_before_exclusion, 'pending'),
    status_before_exclusion = null,
    excluded_by_milestone_id = null
  where excluded_by_milestone_id = m.id;

  if p_outcome = 'succeeded' and m.choice_group is not null then
    -- Replacing an existing winner reverses its journal effects and restores
    -- the choices it had automatically excluded before the new winner is set.
    for v_previous_winner in
      select id
      from public.reputation_milestones
      where campaign_id = m.campaign_id
        and choice_group = m.choice_group
        and id <> m.id
        and status = 'succeeded'
      for update
    loop
      delete from public.journal_entries
      where milestone_id = v_previous_winner;

      update public.reputation_milestones
      set
        status = coalesce(status_before_exclusion, 'pending'),
        status_before_exclusion = null,
        excluded_by_milestone_id = null
      where excluded_by_milestone_id = v_previous_winner;

      update public.reputation_milestones
      set
        status = 'pending',
        applied = false,
        applied_at = null,
        resolved_at = null,
        resolved_effects = null,
        resolution_note = null
      where id = v_previous_winner;
    end loop;

    update public.reputation_milestones
    set
      status_before_exclusion = status,
      status = 'excluded',
      excluded_by_milestone_id = m.id,
      applied = false,
      applied_at = null
    where campaign_id = m.campaign_id
      and choice_group = m.choice_group
      and id <> m.id;
  end if;

  if p_outcome = 'succeeded' then
    v_effects := coalesce(p_effects, m.reward_effects, '[]'::jsonb);
    if jsonb_typeof(v_effects) <> 'array' then
      raise exception 'Les effets résolus doivent former une liste';
    end if;

    for v_effect in select value from jsonb_array_elements(v_effects)
    loop
      v_faction_id := nullif(v_effect ->> 'faction_id', '')::uuid;
      v_amount := coalesce((v_effect ->> 'amount')::integer, 0);
      v_jf_amount := coalesce(
        (v_effect ->> 'jf_amount')::integer,
        greatest(v_amount, 0)
      );

      if v_faction_id is null then
        raise exception 'Chaque effet appliqué doit désigner une faction';
      end if;
      if not exists (
        select 1 from public.campaign_factions cf
        where cf.campaign_id = m.campaign_id
          and cf.faction_id = v_faction_id
      ) then
        raise exception 'Faction étrangère à cette campagne';
      end if;

      if v_amount <> 0 or v_jf_amount <> 0 then
        insert into public.journal_entries
          (campaign_id, faction_id, occurred_on, volume, title, details,
           rp_delta, jf_delta, visibility, source_reference, milestone_id)
        values
          (m.campaign_id, v_faction_id, current_date, m.volume,
           m.title || case when v_amount < 0 then ' — perte' else ' — gain' end,
           coalesce(nullif(btrim(p_note), ''), m.condition),
           v_amount, v_jf_amount, 'gm_only', m.source_reference, m.id);
      end if;
    end loop;
  else
    v_effects := null;
  end if;

  update public.reputation_milestones
  set
    status = p_outcome,
    resolution_note = nullif(btrim(p_note), ''),
    resolved_effects = v_effects,
    resolved_at = case when p_outcome = 'pending' then null else now() end,
    excluded_by_milestone_id = null,
    status_before_exclusion = null,
    applied = (p_outcome = 'succeeded'),
    applied_at = case when p_outcome = 'succeeded' then now() else null end
  where id = m.id;
end;
$$;


ALTER FUNCTION "public"."resolve_reputation_milestone"("p_milestone_id" "uuid", "p_outcome" "text", "p_note" "text", "p_effects" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."return_campaign_item_to_common"("p_item_id" "uuid", "p_comment" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."return_campaign_item_to_common"("p_item_id" "uuid", "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."revoke_campaign_invite"("p_invite_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
#variable_conflict use_column
declare
  v_campaign_id uuid;
begin
  select invite.campaign_id into v_campaign_id
  from public.campaign_invites invite
  where invite.id = p_invite_id;

  if v_campaign_id is null then raise exception 'Invitation introuvable'; end if;
  if not public.is_campaign_gm(v_campaign_id) then raise exception 'Accès refusé'; end if;

  update public.campaign_invites set revoked_at = coalesce(revoked_at, now()) where id = p_invite_id;
end;
$$;


ALTER FUNCTION "public"."revoke_campaign_invite"("p_invite_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_bestiary_entry"("p_id" "uuid", "p_campaign_id" "uuid", "p_name" "text", "p_resistances" "text" DEFAULT NULL::"text", "p_weaknesses" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text", "p_image_path" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  existing public.bestiary_entries%rowtype;
  viewer_is_gm boolean;
  clean_name text := btrim(coalesce(p_name, ''));
  initial_visibility boolean;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if not public.is_campaign_member(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if clean_name = '' then raise exception 'Le nom de la créature est requis'; end if;
  viewer_is_gm := public.is_campaign_gm(p_campaign_id);
  select * into existing from public.bestiary_entries where id = p_id for update;

  if found then
    if existing.campaign_id <> p_campaign_id then raise exception 'Campagne invalide'; end if;
    if not viewer_is_gm and existing.created_by is distinct from auth.uid() then raise exception 'Vous ne pouvez modifier que vos propres créatures'; end if;
    update public.bestiary_entries
    set name = clean_name,
      resistances = nullif(btrim(coalesce(p_resistances, '')), ''),
      weaknesses = nullif(btrim(coalesce(p_weaknesses, '')), ''),
      notes = nullif(btrim(coalesce(p_notes, '')), ''), image_path = p_image_path
    where id = p_id;
    insert into public.bestiary_events (campaign_id, entry_id, creature_name, event_type, actor_user_id)
    values (p_campaign_id, p_id, clean_name, 'updated', auth.uid());
  else
    initial_visibility := not viewer_is_gm;
    insert into public.bestiary_entries (
      id, campaign_id, name, resistances, weaknesses, notes, image_path,
      created_by, is_visible, revealed_at
    ) values (
      p_id, p_campaign_id, clean_name,
      nullif(btrim(coalesce(p_resistances, '')), ''),
      nullif(btrim(coalesce(p_weaknesses, '')), ''),
      nullif(btrim(coalesce(p_notes, '')), ''), p_image_path,
      auth.uid(), initial_visibility, case when initial_visibility then now() else null end
    );
    insert into public.bestiary_events (campaign_id, entry_id, creature_name, event_type, actor_user_id)
    values (p_campaign_id, p_id, clean_name, 'created', auth.uid());
  end if;
end;
$$;


ALTER FUNCTION "public"."save_bestiary_entry"("p_id" "uuid", "p_campaign_id" "uuid", "p_name" "text", "p_resistances" "text", "p_weaknesses" "text", "p_notes" "text", "p_image_path" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_player_contact_notes"("target_contact_id" "uuid", "next_character_notes" "text", "next_debt_notes" "text", "next_notes" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  target_campaign_id uuid;
begin
  select ct.campaign_id into target_campaign_id
  from public.contacts ct
  join public.campaign_factions cf
    on cf.campaign_id = ct.campaign_id
    and cf.faction_id = ct.faction_id
    and cf.is_player_visible
  where ct.id = target_contact_id and ct.visibility = 'players';

  if target_campaign_id is null or not public.is_campaign_member(target_campaign_id) then
    raise exception 'Contact non disponible dans la vue des joueurs';
  end if;

  insert into public.contact_player_notes
    (contact_id, campaign_id, character_notes, debt_notes, notes)
  values (
    target_contact_id,
    target_campaign_id,
    nullif(btrim(next_character_notes), ''),
    nullif(btrim(next_debt_notes), ''),
    nullif(btrim(next_notes), '')
  )
  on conflict (contact_id) do update set
    character_notes = excluded.character_notes,
    debt_notes = excluded.debt_notes,
    notes = excluded.notes;
end;
$$;


ALTER FUNCTION "public"."save_player_contact_notes"("target_contact_id" "uuid", "next_character_notes" "text", "next_debt_notes" "text", "next_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_quest_journal_page"("target_campaign_id" "uuid", "expected_revision" integer, "next_content" "text") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  next_revision integer;
begin
  if not public.is_public_campaign(target_campaign_id) then
    raise exception 'Journal indisponible pour cette campagne';
  end if;

  update public.quest_journal_pages
  set content = next_content,
      revision = revision + 1
  where campaign_id = target_campaign_id
    and revision = expected_revision
  returning revision into next_revision;

  if found then
    return next_revision;
  end if;

  -- Une campagne ancienne peut ne pas encore avoir de ligne de Journal.
  if expected_revision = 0 then
    begin
      insert into public.quest_journal_pages (campaign_id, content, revision)
      values (target_campaign_id, next_content, 1)
      returning revision into next_revision;
      return next_revision;
    exception when unique_violation then
      -- Une autre fenêtre vient de créer la ligne. Le conflit est signalé
      -- ci-dessous sans écraser le contenu local.
    end;
  end if;

  raise exception 'Le Journal a été modifié dans une autre fenêtre'
    using errcode = '40001';
end;
$$;


ALTER FUNCTION "public"."save_quest_journal_page"("target_campaign_id" "uuid", "expected_revision" integer, "next_content" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."seed_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text" DEFAULT 'all'::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if p_scope not in ('archives','loot','all') then raise exception 'Périmètre de restauration invalide'; end if;
  if p_scope in ('archives','all') then
    insert into public.archive_characters
      (campaign_id, template_key, sort_order, first_name, last_name, translated_name, translation_origin, role_text, first_volume, first_page, is_custom)
    select p_campaign_id, template_key, sort_order, first_name, last_name, translated_name, translation_origin, role_text, first_volume, first_page, false
    from public.archive_character_templates
    on conflict (campaign_id, template_key) where template_key is not null do nothing;
    insert into public.archive_places
      (campaign_id, template_key, sort_order, original_name, translated_name, translation_origin, place_type, function_text, first_volume, first_page, is_custom)
    select p_campaign_id, template_key, sort_order, original_name, translated_name, translation_origin, place_type, function_text, first_volume, first_page, false
    from public.archive_place_templates
    on conflict (campaign_id, template_key) where template_key is not null do nothing;
  end if;
end;
$$;


ALTER FUNCTION "public"."seed_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sell_campaign_item"("p_item_id" "uuid", "p_quantity" numeric, "p_amount_cp" bigint, "p_comment" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
  if p_quantity <= 0 or p_quantity > v_item.quantity then raise exception 'QuantitÃ© invalide'; end if;
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


ALTER FUNCTION "public"."sell_campaign_item"("p_item_id" "uuid", "p_quantity" numeric, "p_amount_cp" bigint, "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_bestiary_entry_visibility"("p_entry_id" "uuid", "p_visible" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare entry public.bestiary_entries%rowtype;
begin
  select * into entry from public.bestiary_entries where id = p_entry_id for update;
  if not found then raise exception 'Créature introuvable'; end if;
  if not public.is_campaign_gm(entry.campaign_id) then raise exception 'Accès refusé'; end if;
  if entry.is_visible = p_visible then return; end if;
  update public.bestiary_entries
  set is_visible = p_visible, revealed_at = case when p_visible then now() else revealed_at end
  where id = p_entry_id;
  insert into public.bestiary_events (campaign_id, entry_id, creature_name, event_type, actor_user_id)
  values (entry.campaign_id, entry.id, entry.name, case when p_visible then 'revealed' else 'hidden' end, auth.uid());
end;
$$;


ALTER FUNCTION "public"."set_bestiary_entry_visibility"("p_entry_id" "uuid", "p_visible" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_campaign_item_terminal"("p_item_id" "uuid", "p_status" "text", "p_quantity" numeric DEFAULT NULL::numeric, "p_comment" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_item public.campaign_inventory_items%rowtype;
  v_terminal_id uuid;
  v_quantity numeric;
begin
  if p_status not in ('consumed', 'lost', 'donated') then
    raise exception 'Ã‰tat final invalide';
  end if;
  select * into v_item from public.campaign_inventory_items where id = p_item_id for update;
  if v_item.id is null or not public.can_control_campaign_item(p_item_id) then
    raise exception 'Vous ne pouvez pas modifier cet objet';
  end if;
  v_quantity := coalesce(p_quantity, v_item.quantity);
  if v_quantity <= 0 or v_quantity > v_item.quantity then raise exception 'QuantitÃ© invalide'; end if;

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


ALTER FUNCTION "public"."set_campaign_item_terminal"("p_item_id" "uuid", "p_status" "text", "p_quantity" numeric, "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_loot_player_visibility"("p_loot_id" "uuid", "p_visible" boolean, "p_published_on" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."set_loot_player_visibility"("p_loot_id" "uuid", "p_visible" boolean, "p_published_on" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_player_loot_assignment"("p_loot_id" "uuid", "p_owner_user_id" "uuid", "p_lifecycle_status" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_campaign_id uuid;
begin
  if p_lifecycle_status not in ('available', 'assigned', 'sold', 'dismantled', 'consumed') then
    raise exception 'État de butin invalide';
  end if;

  select loot.campaign_id into v_campaign_id
  from public.campaign_loot loot
  join public.loot_player_publications publication on publication.loot_id = loot.id
  where loot.id = p_loot_id and loot.player_visible;

  if v_campaign_id is null or not public.is_campaign_member(v_campaign_id) then
    raise exception 'Butin partagé introuvable';
  end if;

  if p_lifecycle_status = 'assigned' then
    if p_owner_user_id is null or not exists (
      select 1 from public.campaign_members member
      where member.campaign_id = v_campaign_id
        and member.user_id = p_owner_user_id
        and member.role = 'player'
    ) then raise exception 'Propriétaire invalide'; end if;
  elsif p_owner_user_id is not null then
    raise exception 'Un état non attribué ne peut pas avoir de propriétaire';
  end if;

  update public.loot_player_publications
  set owner_user_id = p_owner_user_id,
      lifecycle_status = p_lifecycle_status,
      legacy_owner_label = null
  where loot_id = p_loot_id;
end;
$$;


ALTER FUNCTION "public"."set_player_loot_assignment"("p_loot_id" "uuid", "p_owner_user_id" "uuid", "p_lifecycle_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_player_loot_published_on"("p_loot_id" "uuid", "p_published_on" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if p_published_on is null then raise exception 'Date d’ajout obligatoire'; end if;
  update public.loot_player_publications publication
  set published_on = p_published_on
  from public.campaign_loot loot
  where publication.loot_id = p_loot_id and loot.id = p_loot_id
    and loot.player_visible and public.is_campaign_member(loot.campaign_id);
  if not found then raise exception 'Butin partagé introuvable'; end if;
end;
$$;


ALTER FUNCTION "public"."set_player_loot_published_on"("p_loot_id" "uuid", "p_published_on" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."split_campaign_item"("p_item_id" "uuid", "p_quantity" numeric) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_item public.campaign_inventory_items%rowtype;
  v_new_id uuid;
begin
  select * into v_item from public.campaign_inventory_items where id = p_item_id for update;
  if v_item.id is null or not public.can_control_campaign_item(p_item_id) then
    raise exception 'Vous ne pouvez pas fractionner cet objet';
  end if;
  if p_quantity <= 0 or p_quantity >= v_item.quantity then
    raise exception 'QuantitÃ© Ã  sÃ©parer invalide';
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


ALTER FUNCTION "public"."split_campaign_item"("p_item_id" "uuid", "p_quantity" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."touch_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."transfer_campaign_money"("p_campaign_id" "uuid", "p_source_user_id" "uuid", "p_destination_user_id" "uuid", "p_amount_cp" bigint, "p_comment" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_transaction_id uuid;
begin
  if not public.is_campaign_member(p_campaign_id) then raise exception 'AccÃ¨s refusÃ©'; end if;
  if p_amount_cp <= 0 or p_source_user_id is not distinct from p_destination_user_id then
    raise exception 'Transfert invalide';
  end if;
  if p_source_user_id is not null
    and p_source_user_id <> auth.uid()
    and not public.is_campaign_gm(p_campaign_id) then
    raise exception 'Vous ne pouvez pas dÃ©biter ce compte';
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


ALTER FUNCTION "public"."transfer_campaign_money"("p_campaign_id" "uuid", "p_source_user_id" "uuid", "p_destination_user_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."transfer_departing_player_assets"("p_campaign_id" "uuid", "p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_balance bigint;
begin
  -- Les dettes explicites sont matÃ©rialisÃ©es dans les comptes avant le retrait :
  -- le pot commun reprend aussi bien la dette que la crÃ©ance du joueur sortant.
  insert into public.campaign_money_transactions (
    campaign_id, actor_user_id, kind, source_account,
    destination_account, destination_user_id, amount_cp, comment
  )
  select debt.campaign_id, auth.uid(), 'departure_transfer', 'common',
    'player', debt.creditor_user_id, debt.remaining_cp,
    'Dette reprise par le pot commun au dÃ©part du joueur'
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
    'CrÃ©ance reprise par le pot commun au dÃ©part du joueur'
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
      'common', v_balance, 'DÃ©part du joueur'
    );
  elsif v_balance < 0 then
    insert into public.campaign_money_transactions (
      campaign_id, actor_user_id, kind, source_account,
      destination_account, destination_user_id, amount_cp, comment
    ) values (
      p_campaign_id, auth.uid(), 'departure_transfer', 'common',
      'player', p_user_id, abs(v_balance), 'Reprise de la dette au dÃ©part du joueur'
    );
  end if;

  insert into public.campaign_item_events (
    campaign_id, item_id, actor_user_id, event_type,
    previous_owner_user_id, quantity, comment
  )
  select p_campaign_id, item.id, auth.uid(), 'returned', p_user_id,
    item.quantity, 'DÃ©part du joueur'
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


ALTER FUNCTION "public"."transfer_departing_player_assets"("p_campaign_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_campaign_capacity"("p_campaign_id" "uuid", "p_max_participants" integer) RETURNS smallint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  current_count integer;
  saved_capacity smallint;
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if p_max_participants not between 1 and 7 then
    raise exception 'La capacité doit être comprise entre 1 et 7 participants';
  end if;
  select count(*) into current_count from public.campaign_members where campaign_id = p_campaign_id;
  if p_max_participants < current_count then
    raise exception 'La capacité ne peut pas être inférieure au nombre actuel de participants';
  end if;
  update public.campaigns set max_participants = p_max_participants
  where id = p_campaign_id
  returning max_participants into saved_capacity;
  return saved_capacity;
end;
$$;


ALTER FUNCTION "public"."update_campaign_capacity"("p_campaign_id" "uuid", "p_max_participants" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  current_image_path text;
begin
  select page.image_path into current_image_path
  from public.player_pages page
  where page.campaign_id = p_campaign_id and page.user_id = auth.uid();
  perform public.update_my_player_page(p_campaign_id, p_character_name,
    p_character_summary, p_pathbuilder_url, p_notes, p_objectives,
    current_image_path);
end;
$$;


ALTER FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  current_x numeric;
  current_y numeric;
  current_zoom numeric;
begin
  select page.image_x, page.image_y, page.image_zoom
    into current_x, current_y, current_zoom
  from public.player_pages page
  where page.campaign_id = p_campaign_id and page.user_id = auth.uid();

  perform public.update_my_player_page(
    p_campaign_id, p_character_name, p_character_summary, p_pathbuilder_url,
    p_notes, p_objectives, p_image_path,
    coalesce(current_x, 50), coalesce(current_y, 50), coalesce(current_zoom, 1)
  );
end;
$$;


ALTER FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text", "p_image_x" numeric, "p_image_y" numeric, "p_image_zoom" numeric) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  current_title text;
begin
  select page.character_title into current_title
  from public.player_pages page
  where page.campaign_id = p_campaign_id and page.user_id = auth.uid();

  perform public.update_my_player_page(
    p_campaign_id, p_character_name, current_title, p_character_summary,
    p_pathbuilder_url, p_notes, p_objectives, p_image_path,
    p_image_x, p_image_y, p_image_zoom
  );
end;
$$;


ALTER FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text", "p_image_x" numeric, "p_image_y" numeric, "p_image_zoom" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_title" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text", "p_image_x" numeric, "p_image_y" numeric, "p_image_zoom" numeric) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
begin
  if not exists (
    select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id
      and member.user_id = auth.uid()
      and member.role = 'player'
  ) then raise exception 'Accès refusé'; end if;

  if char_length(coalesce(p_character_title, '')) > 160 then
    raise exception 'Le titre du personnage est trop long';
  end if;
  if nullif(btrim(coalesce(p_image_path, '')), '') is not null
    and p_image_path !~ ('^' || p_campaign_id::text || '/' || auth.uid()::text || '/[0-9a-f-]{36}\.[a-z0-9]+$')
  then raise exception 'Chemin de portrait invalide'; end if;
  if p_image_x is null or p_image_x not between 0 and 100
    or p_image_y is null or p_image_y not between 0 and 100
    or p_image_zoom is null or p_image_zoom not between 1 and 2.5
  then raise exception 'Cadrage du portrait invalide'; end if;

  update public.player_pages set
    character_name = nullif(btrim(coalesce(p_character_name, '')), ''),
    character_title = nullif(btrim(coalesce(p_character_title, '')), ''),
    character_summary = nullif(btrim(coalesce(p_character_summary, '')), ''),
    pathbuilder_url = nullif(btrim(coalesce(p_pathbuilder_url, '')), ''),
    notes = nullif(btrim(coalesce(p_notes, '')), ''),
    objectives = nullif(btrim(coalesce(p_objectives, '')), ''),
    image_path = nullif(btrim(coalesce(p_image_path, '')), ''),
    image_x = p_image_x,
    image_y = p_image_y,
    image_zoom = p_image_zoom
  where campaign_id = p_campaign_id and user_id = auth.uid();
  if not found then raise exception 'Page joueur introuvable'; end if;
end;
$_$;


ALTER FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_title" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text", "p_image_x" numeric, "p_image_y" numeric, "p_image_zoom" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_my_player_relationship_note"("p_campaign_id" "uuid", "p_target_user_id" "uuid", "p_notes" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  normalized_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
  if p_target_user_id = auth.uid() then
    raise exception 'Vous ne pouvez pas créer une relation avec vous-même';
  end if;
  if not exists (
    select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id
      and member.user_id = auth.uid()
      and member.role = 'player'
  ) or not exists (
    select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id
      and member.user_id = p_target_user_id
      and member.role = 'player'
  ) then raise exception 'Joueur introuvable dans cette campagne'; end if;

  if normalized_notes is null then
    delete from public.player_relationship_notes
    where campaign_id = p_campaign_id
      and author_user_id = auth.uid()
      and target_user_id = p_target_user_id;
  else
    insert into public.player_relationship_notes (campaign_id, author_user_id, target_user_id, notes)
    values (p_campaign_id, auth.uid(), p_target_user_id, normalized_notes)
    on conflict (campaign_id, author_user_id, target_user_id)
    do update set notes = excluded.notes;
  end if;
end;
$$;


ALTER FUNCTION "public"."update_my_player_relationship_note"("p_campaign_id" "uuid", "p_target_user_id" "uuid", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_my_profile"("p_display_name" "text") RETURNS TABLE("user_id" "uuid", "display_name" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  normalized_name text := btrim(coalesce(p_display_name, ''));
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if char_length(normalized_name) not between 2 and 40 then
    raise exception 'Le pseudo doit comporter entre 2 et 40 caractères';
  end if;

  insert into public.user_profiles (user_id, display_name)
  values (auth.uid(), normalized_name)
  on conflict on constraint user_profiles_pkey do update set display_name = excluded.display_name;

  return query
  select profile.user_id, profile.display_name
  from public.user_profiles profile
  where profile.user_id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."update_my_profile"("p_display_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_owned_campaign"("p_campaign_id" "uuid", "p_name" "text", "p_description" "text" DEFAULT NULL::"text") RETURNS TABLE("campaign_id" "uuid", "slug" "text", "name" "text", "description" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  clean_name text := btrim(coalesce(p_name, ''));
  clean_description text := nullif(btrim(coalesce(p_description, '')), '');
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if char_length(clean_name) < 2 or char_length(clean_name) > 80 then
    raise exception 'Le nom doit comporter entre 2 et 80 caractères';
  end if;
  if clean_description is not null and char_length(clean_description) > 500 then
    raise exception 'La description ne peut pas dépasser 500 caractères';
  end if;

  return query
  update public.campaigns campaign
  set name = clean_name, description = clean_description
  where campaign.id = p_campaign_id and campaign.owner_user_id = auth.uid()
  returning campaign.id, campaign.slug, campaign.name, campaign.description, campaign.created_at;

  if not found then raise exception 'Seul le propriétaire peut modifier cette campagne'; end if;
end;
$$;


ALTER FUNCTION "public"."update_owned_campaign"("p_campaign_id" "uuid", "p_name" "text", "p_description" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "storage"."allow_any_operation"("expected_operations" "text"[]) RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT CASE
      WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
      ELSE raw_operation
    END AS current_operation
    FROM current_operation
  )
  SELECT EXISTS (
    SELECT 1
    FROM normalized n
    CROSS JOIN LATERAL unnest(expected_operations) AS expected_operation
    WHERE expected_operation IS NOT NULL
      AND expected_operation <> ''
      AND n.current_operation = CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END
  );
$$;


ALTER FUNCTION "storage"."allow_any_operation"("expected_operations" "text"[]) OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."allow_only_operation"("expected_operation" "text") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT
      CASE
        WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
        ELSE raw_operation
      END AS current_operation,
      CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END AS requested_operation
    FROM current_operation
  )
  SELECT CASE
    WHEN requested_operation IS NULL OR requested_operation = '' THEN FALSE
    ELSE COALESCE(current_operation = requested_operation, FALSE)
  END
  FROM normalized;
$$;


ALTER FUNCTION "storage"."allow_only_operation"("expected_operation" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


ALTER FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."enforce_bucket_name_length"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


ALTER FUNCTION "storage"."enforce_bucket_name_length"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."extension"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Get the last path segment (the actual filename)
    SELECT _parts[array_length(_parts, 1)] INTO _filename;
    -- Extract extension: reverse, split on '.', then reverse again
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


ALTER FUNCTION "storage"."extension"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."filename"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    RETURN _parts[array_length(_parts, 1)];
END
$$;


ALTER FUNCTION "storage"."filename"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."foldername"("name" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


ALTER FUNCTION "storage"."foldername"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_common_prefix"("p_key" "text", "p_prefix" "text", "p_delimiter" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
SELECT CASE
    WHEN position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)) > 0
    THEN left(p_key, length(p_prefix) + position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)))
    ELSE NULL
END;
$$;


ALTER FUNCTION "storage"."get_common_prefix"("p_key" "text", "p_prefix" "text", "p_delimiter" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_size_by_bucket"() RETURNS TABLE("size" bigint, "bucket_id" "text")
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint)::bigint as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


ALTER FUNCTION "storage"."get_size_by_bucket"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "next_key_token" "text" DEFAULT ''::"text", "next_upload_token" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "id" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


ALTER FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "next_key_token" "text", "next_upload_token" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_objects_with_delimiter"("_bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "start_after" "text" DEFAULT ''::"text", "next_token" "text" DEFAULT ''::"text", "sort_order" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "metadata" "jsonb", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;

    -- Configuration
    v_is_asc BOOLEAN;
    v_prefix TEXT;
    v_start TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_is_asc := lower(coalesce(sort_order, 'asc')) = 'asc';
    v_prefix := coalesce(prefix_param, '');
    v_start := CASE WHEN coalesce(next_token, '') <> '' THEN next_token ELSE coalesce(start_after, '') END;
    v_file_batch_size := LEAST(GREATEST(max_keys * 2, 100), 1000);

    -- Calculate upper bound for prefix filtering (bytewise, using COLLATE "C")
    IF v_prefix = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix, 1) = delimiter_param THEN
        v_upper_bound := left(v_prefix, -1) || chr(ascii(delimiter_param) + 1);
    ELSE
        v_upper_bound := left(v_prefix, -1) || chr(ascii(right(v_prefix, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'AND o.name COLLATE "C" < $3 ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'AND o.name COLLATE "C" >= $3 ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- ========================================================================
    -- SEEK INITIALIZATION: Determine starting position
    -- ========================================================================
    IF v_start = '' THEN
        IF v_is_asc THEN
            v_next_seek := v_prefix;
        ELSE
            -- DESC without cursor: find the last item in range
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;

            IF v_next_seek IS NOT NULL THEN
                v_next_seek := v_next_seek || delimiter_param;
            ELSE
                RETURN;
            END IF;
        END IF;
    ELSE
        -- Cursor provided: determine if it refers to a folder or leaf
        IF EXISTS (
            SELECT 1 FROM storage.objects o
            WHERE o.bucket_id = _bucket_id
              AND o.name COLLATE "C" LIKE v_start || delimiter_param || '%'
            LIMIT 1
        ) THEN
            -- Cursor refers to a folder
            IF v_is_asc THEN
                v_next_seek := v_start || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_start || delimiter_param;
            END IF;
        ELSE
            -- Cursor refers to a leaf object
            IF v_is_asc THEN
                v_next_seek := v_start || delimiter_param;
            ELSE
                v_next_seek := v_start;
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= max_keys;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(v_peek_name, v_prefix, delimiter_param);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Emit and skip to next folder (no heap access needed)
            name := rtrim(v_common_prefix, delimiter_param);
            id := NULL;
            updated_at := NULL;
            created_at := NULL;
            last_accessed_at := NULL;
            metadata := NULL;
            RETURN NEXT;
            v_count := v_count + 1;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := left(v_common_prefix, -1) || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_common_prefix;
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query USING _bucket_id, v_next_seek,
                CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(v_current.name, v_prefix, delimiter_param);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := v_current.name;
                    EXIT;
                END IF;

                -- Emit file
                name := v_current.name;
                id := v_current.id;
                updated_at := v_current.updated_at;
                created_at := v_current.created_at;
                last_accessed_at := v_current.last_accessed_at;
                metadata := v_current.metadata;
                RETURN NEXT;
                v_count := v_count + 1;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := v_current.name || delimiter_param;
                ELSE
                    v_next_seek := v_current.name;
                END IF;

                EXIT WHEN v_count >= max_keys;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION "storage"."list_objects_with_delimiter"("_bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "start_after" "text", "next_token" "text", "sort_order" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."operation"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


ALTER FUNCTION "storage"."operation"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."protect_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Check if storage.allow_delete_query is set to 'true'
    IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
        RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
            USING HINT = 'This prevents accidental data loss from orphaned objects.',
                  ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION "storage"."protect_delete"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;
    v_delimiter CONSTANT TEXT := '/';

    -- Configuration
    v_limit INT;
    v_prefix TEXT;
    v_prefix_lower TEXT;
    v_prefix_len INT;
    v_prefix_start INT;
    v_combined_levels INT;
    v_is_asc BOOLEAN;
    v_order_by TEXT;
    v_sort_order TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;
    v_skipped INT := 0;
BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_limit := LEAST(coalesce(limits, 100), 1500);
    v_prefix := coalesce(prefix, '') || coalesce(search, '');
    v_prefix_lower := lower(v_prefix);
    v_prefix_len := length(coalesce(prefix, ''));
    v_prefix_start := coalesce(array_length(string_to_array(coalesce(prefix, ''), v_delimiter), 1), 1);
    v_combined_levels := coalesce(array_length(string_to_array(v_prefix, v_delimiter), 1), 1);
    v_is_asc := lower(coalesce(sortorder, 'asc')) = 'asc';
    v_file_batch_size := LEAST(GREATEST(v_limit * 2, 100), 1000);

    -- Validate sort column
    CASE lower(coalesce(sortcolumn, 'name'))
        WHEN 'name' THEN v_order_by := 'name';
        WHEN 'updated_at' THEN v_order_by := 'updated_at';
        WHEN 'created_at' THEN v_order_by := 'created_at';
        WHEN 'last_accessed_at' THEN v_order_by := 'last_accessed_at';
        ELSE v_order_by := 'name';
    END CASE;

    v_sort_order := CASE WHEN v_is_asc THEN 'asc' ELSE 'desc' END;

    -- ========================================================================
    -- NON-NAME SORTING: Use path_tokens approach
    -- ========================================================================
    IF v_order_by != 'name' THEN
        RETURN QUERY EXECUTE format(
            $sql$
            WITH folders AS (
                SELECT array_to_string(path_tokens[$1:$2], '/') AS folder
                FROM storage.objects
                WHERE objects.name ILIKE $3 || '%%'
                  AND bucket_id = $4
                  AND array_length(objects.path_tokens, 1) <> $2
                GROUP BY folder
                ORDER BY folder %s
            )
            (SELECT folder AS "name",
                   NULL::uuid AS id,
                   NULL::timestamptz AS updated_at,
                   NULL::timestamptz AS created_at,
                   NULL::timestamptz AS last_accessed_at,
                   NULL::jsonb AS metadata FROM folders)
            UNION ALL
            (SELECT array_to_string(path_tokens[$1:$2], '/') AS "name",
                   id, updated_at, created_at, last_accessed_at, metadata
             FROM storage.objects
             WHERE objects.name ILIKE $3 || '%%'
               AND bucket_id = $4
               AND array_length(objects.path_tokens, 1) = $2
             ORDER BY %I %s)
            LIMIT $5 OFFSET $6
            $sql$, v_sort_order, v_order_by, v_sort_order
        ) USING v_prefix_start, v_combined_levels, v_prefix, bucketname, v_limit, offsets;
        RETURN;
    END IF;

    -- ========================================================================
    -- NAME SORTING: Hybrid skip-scan with batch optimization
    -- ========================================================================

    -- Calculate upper bound for prefix filtering
    IF v_prefix_lower = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix_lower, 1) = v_delimiter THEN
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(v_delimiter) + 1);
    ELSE
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(right(v_prefix_lower, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'AND lower(o.name) COLLATE "C" < $3 ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'AND lower(o.name) COLLATE "C" >= $3 ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- Initialize seek position
    IF v_is_asc THEN
        v_next_seek := v_prefix_lower;
    ELSE
        -- DESC: find the last item in range first (static SQL)
        IF v_upper_bound IS NOT NULL THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower AND lower(o.name) COLLATE "C" < v_upper_bound
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSIF v_prefix_lower <> '' THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSE
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        END IF;

        IF v_peek_name IS NOT NULL THEN
            v_next_seek := lower(v_peek_name) || v_delimiter;
        ELSE
            RETURN;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= v_limit;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix_lower <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(lower(v_peek_name), v_prefix_lower, v_delimiter);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Handle offset, emit if needed, skip to next folder
            IF v_skipped < offsets THEN
                v_skipped := v_skipped + 1;
            ELSE
                name := substring(rtrim(storage.get_common_prefix(v_peek_name, v_prefix, v_delimiter), v_delimiter) from v_prefix_len + 1);
                id := NULL;
                updated_at := NULL;
                created_at := NULL;
                last_accessed_at := NULL;
                metadata := NULL;
                RETURN NEXT;
                v_count := v_count + 1;
            END IF;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := lower(left(v_common_prefix, -1)) || chr(ascii(v_delimiter) + 1);
            ELSE
                v_next_seek := lower(v_common_prefix);
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix_lower is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(lower(v_current.name), v_prefix_lower, v_delimiter);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := lower(v_current.name);
                    EXIT;
                END IF;

                -- Handle offset skipping
                IF v_skipped < offsets THEN
                    v_skipped := v_skipped + 1;
                ELSE
                    -- Emit file
                    name := substring(v_current.name from v_prefix_len + 1);
                    id := v_current.id;
                    updated_at := v_current.updated_at;
                    created_at := v_current.created_at;
                    last_accessed_at := v_current.last_accessed_at;
                    metadata := v_current.metadata;
                    RETURN NEXT;
                    v_count := v_count + 1;
                END IF;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := lower(v_current.name) || v_delimiter;
                ELSE
                    v_next_seek := lower(v_current.name);
                END IF;

                EXIT WHEN v_count >= v_limit;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_by_timestamp"("p_prefix" "text", "p_bucket_id" "text", "p_limit" integer, "p_level" integer, "p_start_after" "text", "p_sort_order" "text", "p_sort_column" "text", "p_sort_column_after" "text") RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_cursor_op text;
    v_query text;
    v_prefix text;
    v_sort_order text;
    v_sort_column text;
BEGIN
    v_prefix := coalesce(p_prefix, '');

    -- Defense-in-depth: this function is independently reachable and must
    -- not trust p_sort_order/p_sort_column to already be validated by a
    -- caller. Normalize to the same strict allow-list storage.search_v2
    -- uses before interpolating anything into dynamic SQL below.
    v_sort_order := lower(coalesce(p_sort_order, 'asc'));
    IF v_sort_order NOT IN ('asc', 'desc') THEN
        v_sort_order := 'asc';
    END IF;

    v_sort_column := lower(coalesce(p_sort_column, 'updated_at'));
    IF v_sort_column NOT IN ('updated_at', 'created_at') THEN
        v_sort_column := 'updated_at';
    END IF;

    IF v_sort_order = 'asc' THEN
        v_cursor_op := '>';
    ELSE
        v_cursor_op := '<';
    END IF;

    v_query := format($sql$
        WITH raw_objects AS (
            SELECT
                o.name AS obj_name,
                o.id AS obj_id,
                o.updated_at AS obj_updated_at,
                o.created_at AS obj_created_at,
                o.last_accessed_at AS obj_last_accessed_at,
                o.metadata AS obj_metadata,
                storage.get_common_prefix(o.name, $1, '/') AS common_prefix
            FROM storage.objects o
            WHERE o.bucket_id = $2
              AND o.name COLLATE "C" LIKE $1 || '%%'
        ),
        -- Aggregate common prefixes (folders)
        -- Both created_at and updated_at use MIN(obj_created_at) to match the old prefixes table behavior
        aggregated_prefixes AS (
            SELECT
                rtrim(common_prefix, '/') AS name,
                NULL::uuid AS id,
                MIN(obj_created_at) AS updated_at,
                MIN(obj_created_at) AS created_at,
                NULL::timestamptz AS last_accessed_at,
                NULL::jsonb AS metadata,
                TRUE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NOT NULL
            GROUP BY common_prefix
        ),
        leaf_objects AS (
            SELECT
                obj_name AS name,
                obj_id AS id,
                obj_updated_at AS updated_at,
                obj_created_at AS created_at,
                obj_last_accessed_at AS last_accessed_at,
                obj_metadata AS metadata,
                FALSE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NULL
        ),
        combined AS (
            SELECT * FROM aggregated_prefixes
            UNION ALL
            SELECT * FROM leaf_objects
        ),
        filtered AS (
            SELECT *
            FROM combined
            WHERE (
                $5 = ''
                OR ROW(
                    date_trunc('milliseconds', %I),
                    name COLLATE "C"
                ) %s ROW(
                    COALESCE(NULLIF($6, '')::timestamptz, 'epoch'::timestamptz),
                    $5
                )
            )
        )
        SELECT
            split_part(name, '/', $3) AS key,
            name,
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
        FROM filtered
        ORDER BY
            COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz) %s,
            name COLLATE "C" %s
        LIMIT $4
    $sql$,
        v_sort_column,
        v_cursor_op,
        v_sort_column,
        v_sort_order,
        v_sort_order
    );

    RETURN QUERY EXECUTE v_query
    USING v_prefix, p_bucket_id, p_level, p_limit, p_start_after, p_sort_column_after;
END;
$_$;


ALTER FUNCTION "storage"."search_by_timestamp"("p_prefix" "text", "p_bucket_id" "text", "p_limit" integer, "p_level" integer, "p_start_after" "text", "p_sort_order" "text", "p_sort_column" "text", "p_sort_column_after" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "start_after" "text" DEFAULT ''::"text", "sort_order" "text" DEFAULT 'asc'::"text", "sort_column" "text" DEFAULT 'name'::"text", "sort_column_after" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    v_sort_col text;
    v_sort_ord text;
    v_limit int;
BEGIN
    -- Cap limit to maximum of 1500 records
    v_limit := LEAST(coalesce(limits, 100), 1500);

    -- Validate and normalize sort_order
    v_sort_ord := lower(coalesce(sort_order, 'asc'));
    IF v_sort_ord NOT IN ('asc', 'desc') THEN
        v_sort_ord := 'asc';
    END IF;

    -- Validate and normalize sort_column
    v_sort_col := lower(coalesce(sort_column, 'name'));
    IF v_sort_col NOT IN ('name', 'updated_at', 'created_at') THEN
        v_sort_col := 'name';
    END IF;

    -- Route to appropriate implementation
    IF v_sort_col = 'name' THEN
        -- Use list_objects_with_delimiter for name sorting (most efficient: O(k * log n))
        RETURN QUERY
        SELECT
            split_part(l.name, '/', levels) AS key,
            l.name AS name,
            l.id,
            l.updated_at,
            l.created_at,
            l.last_accessed_at,
            l.metadata
        FROM storage.list_objects_with_delimiter(
            bucket_name,
            coalesce(prefix, ''),
            '/',
            v_limit,
            start_after,
            '',
            v_sort_ord
        ) l;
    ELSE
        -- Use aggregation approach for timestamp sorting
        -- Not efficient for large datasets but supports correct pagination
        RETURN QUERY SELECT * FROM storage.search_by_timestamp(
            prefix, bucket_name, v_limit, levels, start_after,
            v_sort_ord, v_sort_col, sort_column_after
        );
    END IF;
END;
$$;


ALTER FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer, "levels" integer, "start_after" "text", "sort_order" "text", "sort_column" "text", "sort_column_after" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."update_updated_at_column"() OWNER TO "supabase_storage_admin";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."archive_character_templates" (
    "template_key" "text" NOT NULL,
    "sort_order" integer NOT NULL,
    "first_name" "text" DEFAULT ''::"text" NOT NULL,
    "last_name" "text",
    "translated_name" "text",
    "translation_origin" "text" DEFAULT 'none'::"text" NOT NULL,
    "role_text" "text",
    "first_volume" smallint NOT NULL,
    "first_page" integer,
    CONSTRAINT "archive_character_templates_first_page_check" CHECK ((("first_page" IS NULL) OR ("first_page" > 0))),
    CONSTRAINT "archive_character_templates_first_volume_check" CHECK ((("first_volume" >= 1) AND ("first_volume" <= 6))),
    CONSTRAINT "archive_character_templates_translation_origin_check" CHECK (("translation_origin" = ANY (ARRAY['none'::"text", 'attested'::"text", 'site'::"text"])))
);


ALTER TABLE "public"."archive_character_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."archive_characters" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "template_key" "text",
    "sort_order" integer NOT NULL,
    "first_name" "text" DEFAULT ''::"text" NOT NULL,
    "last_name" "text",
    "translated_name" "text",
    "translation_origin" "text" DEFAULT 'none'::"text" NOT NULL,
    "role_text" "text",
    "first_volume" smallint NOT NULL,
    "first_page" integer,
    "is_custom" boolean DEFAULT false NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "archive_characters_first_page_check" CHECK ((("first_page" IS NULL) OR ("first_page" > 0))),
    CONSTRAINT "archive_characters_first_volume_check" CHECK ((("first_volume" >= 1) AND ("first_volume" <= 6))),
    CONSTRAINT "archive_characters_translation_origin_check" CHECK (("translation_origin" = ANY (ARRAY['none'::"text", 'attested'::"text", 'site'::"text", 'custom'::"text"])))
);


ALTER TABLE "public"."archive_characters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."archive_place_templates" (
    "template_key" "text" NOT NULL,
    "sort_order" integer NOT NULL,
    "original_name" "text" NOT NULL,
    "translated_name" "text",
    "translation_origin" "text" DEFAULT 'none'::"text" NOT NULL,
    "place_type" "text",
    "function_text" "text",
    "first_volume" smallint NOT NULL,
    "first_page" integer,
    CONSTRAINT "archive_place_templates_first_page_check" CHECK ((("first_page" IS NULL) OR ("first_page" > 0))),
    CONSTRAINT "archive_place_templates_first_volume_check" CHECK ((("first_volume" >= 1) AND ("first_volume" <= 6))),
    CONSTRAINT "archive_place_templates_translation_origin_check" CHECK (("translation_origin" = ANY (ARRAY['none'::"text", 'attested'::"text", 'site'::"text"])))
);


ALTER TABLE "public"."archive_place_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."archive_places" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "template_key" "text",
    "sort_order" integer NOT NULL,
    "original_name" "text" NOT NULL,
    "translated_name" "text",
    "translation_origin" "text" DEFAULT 'none'::"text" NOT NULL,
    "place_type" "text",
    "function_text" "text",
    "first_volume" smallint NOT NULL,
    "first_page" integer,
    "is_custom" boolean DEFAULT false NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "archive_places_first_page_check" CHECK ((("first_page" IS NULL) OR ("first_page" > 0))),
    CONSTRAINT "archive_places_first_volume_check" CHECK ((("first_volume" >= 1) AND ("first_volume" <= 6))),
    CONSTRAINT "archive_places_translation_origin_check" CHECK (("translation_origin" = ANY (ARRAY['none'::"text", 'attested'::"text", 'site'::"text", 'custom'::"text"])))
);


ALTER TABLE "public"."archive_places" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bestiary_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "resistances" "text",
    "weaknesses" "text",
    "notes" "text",
    "image_path" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "is_visible" boolean DEFAULT true NOT NULL,
    "revealed_at" timestamp with time zone,
    CONSTRAINT "bestiary_entries_name_check" CHECK (("length"("btrim"("name")) > 0))
);


ALTER TABLE "public"."bestiary_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bestiary_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "entry_id" "uuid",
    "creature_name" "text" NOT NULL,
    "event_type" "text" NOT NULL,
    "actor_user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "bestiary_events_event_type_check" CHECK (("event_type" = ANY (ARRAY['created'::"text", 'updated'::"text", 'revealed'::"text", 'hidden'::"text", 'deleted'::"text"])))
);


ALTER TABLE "public"."bestiary_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bilateral_dossiers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "faction_a_id" "uuid" NOT NULL,
    "faction_b_id" "uuid" NOT NULL,
    "pair_name" "text" NOT NULL,
    "canon_core" "text" NOT NULL,
    "a_to_b" "text" NOT NULL,
    "b_to_a" "text" NOT NULL,
    "common_interest" "text" NOT NULL,
    "fracture" "text" NOT NULL,
    "triggers" "text" NOT NULL,
    "scene_hook" "text" NOT NULL,
    "evidence_note" "text" NOT NULL,
    CONSTRAINT "bilateral_dossiers_check" CHECK (("faction_a_id" <> "faction_b_id"))
);


ALTER TABLE "public"."bilateral_dossiers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_factions" (
    "campaign_id" "uuid" NOT NULL,
    "faction_id" "uuid" NOT NULL,
    "public_summary" "text",
    "gm_notes" "text",
    "is_player_visible" boolean DEFAULT true NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."campaign_factions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_inventory_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "origin_loot_id" "uuid",
    "parent_item_id" "uuid",
    "created_by" "uuid",
    "owner_user_id" "uuid",
    "name" "text" NOT NULL,
    "quantity" numeric(14,4) DEFAULT 1 NOT NULL,
    "source_quantity_label" "text",
    "unit_value_cp" bigint,
    "purchase_price_cp" bigint,
    "aon_legacy_name" "text",
    "aon_legacy_url" "text",
    "source_kind" "text" DEFAULT 'loot'::"text" NOT NULL,
    "player_visible" boolean DEFAULT true NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "acquired_on" "date" DEFAULT CURRENT_DATE NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "counts_as_gain" boolean DEFAULT true NOT NULL,
    CONSTRAINT "campaign_inventory_items_name_check" CHECK ((("length"("btrim"("name")) >= 1) AND ("length"("btrim"("name")) <= 240))),
    CONSTRAINT "campaign_inventory_items_purchase_price_cp_check" CHECK ((("purchase_price_cp" IS NULL) OR ("purchase_price_cp" >= 0))),
    CONSTRAINT "campaign_inventory_items_quantity_check" CHECK (("quantity" > (0)::numeric)),
    CONSTRAINT "campaign_inventory_items_source_kind_check" CHECK (("source_kind" = ANY (ARRAY['loot'::"text", 'gm'::"text", 'purchase'::"text", 'dismantle'::"text"]))),
    CONSTRAINT "campaign_inventory_items_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'sold'::"text", 'dismantled'::"text", 'consumed'::"text", 'lost'::"text", 'donated'::"text", 'merged'::"text"]))),
    CONSTRAINT "campaign_inventory_items_unit_value_cp_check" CHECK ((("unit_value_cp" IS NULL) OR ("unit_value_cp" >= 0)))
);


ALTER TABLE "public"."campaign_inventory_items" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_inventory_items" IS 'Objets rÃ©ellement entrÃ©s dans lâ€™Ã©conomie des joueurs, distincts du registre de rÃ©fÃ©rence MJ.';



CREATE TABLE IF NOT EXISTS "public"."campaign_invites" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "token" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "role" "text" DEFAULT 'player'::"text" NOT NULL,
    "expires_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "campaign_invites_role_check" CHECK (("role" = 'player'::"text"))
);


ALTER TABLE "public"."campaign_invites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_item_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "item_id" "uuid",
    "actor_user_id" "uuid",
    "event_type" "text" NOT NULL,
    "previous_owner_user_id" "uuid",
    "next_owner_user_id" "uuid",
    "quantity" numeric(14,4),
    "value_cp" bigint,
    "comment" "text",
    "related_item_id" "uuid",
    "money_operation_id" "uuid",
    "reversed_event_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "campaign_item_events_comment_check" CHECK ((("comment" IS NULL) OR ("length"("comment") <= 500))),
    CONSTRAINT "campaign_item_events_event_type_check" CHECK (("event_type" = ANY (ARRAY['created'::"text", 'published'::"text", 'claimed'::"text", 'transferred'::"text", 'returned'::"text", 'split'::"text", 'merged'::"text", 'sold'::"text", 'sale_cancelled'::"text", 'action_cancelled'::"text", 'purchased'::"text", 'dismantled'::"text", 'consumed'::"text", 'lost'::"text", 'donated'::"text"])))
);


ALTER TABLE "public"."campaign_item_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_item_events" IS 'Biographie complÃ¨te des objets de campagne.';



CREATE TABLE IF NOT EXISTS "public"."campaign_item_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "item_id" "uuid" NOT NULL,
    "requester_user_id" "uuid" NOT NULL,
    "owner_user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    CONSTRAINT "campaign_item_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'refused'::"text", 'cancelled'::"text", 'invalidated'::"text"])))
);


ALTER TABLE "public"."campaign_item_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_loot" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reference_id" "text",
    "sort_order" integer NOT NULL,
    "volume" smallint NOT NULL,
    "chapter" smallint,
    "source_page" integer,
    "pdf_page" integer,
    "stat_block_page" integer,
    "area_code" "text",
    "area_title" "text",
    "location_name" "text",
    "source_kind" "text" NOT NULL,
    "source_owner" "text",
    "source_text" "text",
    "item_name" "text" NOT NULL,
    "quantity_initial" "text" DEFAULT '1'::"text" NOT NULL,
    "quantity_recoverable" "text" DEFAULT '1'::"text" NOT NULL,
    "loot_category" "text",
    "acquisition_condition" "text",
    "consumable_during_encounter" boolean DEFAULT false NOT NULL,
    "availability_rule" "text",
    "book_unit_value_amount" numeric,
    "book_unit_value_currency" "text",
    "book_total_value_amount" numeric,
    "book_total_value_currency" "text",
    "aon_legacy_name" "text",
    "aon_legacy_unit_value_amount" numeric,
    "aon_legacy_unit_value_currency" "text",
    "aon_legacy_total_value_amount" numeric,
    "aon_legacy_total_value_currency" "text",
    "aon_legacy_url" "text",
    "pricing_basis" "text",
    "pricing_status" "text",
    "verification_status" "text",
    "discovery_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "player_visible" boolean DEFAULT false NOT NULL,
    "is_custom" boolean DEFAULT false NOT NULL,
    CONSTRAINT "campaign_loot_aon_legacy_total_value_currency_check" CHECK ((("aon_legacy_total_value_currency" IS NULL) OR ("aon_legacy_total_value_currency" = ANY (ARRAY['pp'::"text", 'gp'::"text", 'sp'::"text", 'cp'::"text"])))),
    CONSTRAINT "campaign_loot_aon_legacy_unit_value_currency_check" CHECK ((("aon_legacy_unit_value_currency" IS NULL) OR ("aon_legacy_unit_value_currency" = ANY (ARRAY['pp'::"text", 'gp'::"text", 'sp'::"text", 'cp'::"text"])))),
    CONSTRAINT "campaign_loot_book_total_value_currency_check" CHECK ((("book_total_value_currency" IS NULL) OR ("book_total_value_currency" = ANY (ARRAY['pp'::"text", 'gp'::"text", 'sp'::"text", 'cp'::"text"])))),
    CONSTRAINT "campaign_loot_book_unit_value_currency_check" CHECK ((("book_unit_value_currency" IS NULL) OR ("book_unit_value_currency" = ANY (ARRAY['pp'::"text", 'gp'::"text", 'sp'::"text", 'cp'::"text"])))),
    CONSTRAINT "campaign_loot_discovery_status_check" CHECK (("discovery_status" = ANY (ARRAY['pending'::"text", 'found'::"text", 'missed'::"text"]))),
    CONSTRAINT "campaign_loot_pdf_page_check" CHECK ((("pdf_page" IS NULL) OR ("pdf_page" > 0))),
    CONSTRAINT "campaign_loot_source_kind_check" CHECK (("source_kind" = ANY (ARRAY['treasure'::"text", 'reward'::"text", 'carried'::"text", 'infused_carried'::"text", 'narrative'::"text", 'chapter_checklist_only'::"text"]))),
    CONSTRAINT "campaign_loot_source_page_check" CHECK ((("source_page" IS NULL) OR ("source_page" > 0))),
    CONSTRAINT "campaign_loot_stat_block_page_check" CHECK ((("stat_block_page" IS NULL) OR ("stat_block_page" > 0))),
    CONSTRAINT "campaign_loot_volume_check" CHECK ((("volume" >= 1) AND ("volume" <= 6)))
);


ALTER TABLE "public"."campaign_loot" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_loot" IS 'Registre neuf construit exclusivement depuis la source autoritative privée, complété par les saisies MJ.';



COMMENT ON COLUMN "public"."campaign_loot"."book_total_value_amount" IS 'Valeur imprimée dans l’ouvrage ; elle n’est jamais remplacée par la valeur AoN.';



COMMENT ON COLUMN "public"."campaign_loot"."aon_legacy_total_value_amount" IS 'Valeur de référence AoN Legacy, conservée séparément de la valeur du livre.';



CREATE TABLE IF NOT EXISTS "public"."campaign_members" (
    "campaign_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'gm'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "campaign_members_role_check" CHECK (("role" = ANY (ARRAY['gm'::"text", 'player'::"text"])))
);


ALTER TABLE "public"."campaign_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_money_debts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "debtor_user_id" "uuid" NOT NULL,
    "creditor_user_id" "uuid" NOT NULL,
    "amount_cp" bigint NOT NULL,
    "remaining_cp" bigint NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "comment" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "campaign_money_debts_amount_cp_check" CHECK (("amount_cp" > 0)),
    CONSTRAINT "campaign_money_debts_check" CHECK ((("remaining_cp" >= 0) AND ("remaining_cp" <= "amount_cp"))),
    CONSTRAINT "campaign_money_debts_check1" CHECK (("debtor_user_id" <> "creditor_user_id")),
    CONSTRAINT "campaign_money_debts_comment_check" CHECK ((("comment" IS NULL) OR ("length"("comment") <= 500))),
    CONSTRAINT "campaign_money_debts_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'settled'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."campaign_money_debts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_money_transactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "operation_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "actor_user_id" "uuid",
    "kind" "text" NOT NULL,
    "source_account" "text" NOT NULL,
    "source_user_id" "uuid",
    "destination_account" "text" NOT NULL,
    "destination_user_id" "uuid",
    "amount_cp" bigint NOT NULL,
    "comment" "text",
    "related_item_id" "uuid",
    "reversed_transaction_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "campaign_money_transactions_amount_cp_check" CHECK (("amount_cp" > 0)),
    CONSTRAINT "campaign_money_transactions_check" CHECK ((("source_account" <> "destination_account") OR ("source_account" = 'player'::"text"))),
    CONSTRAINT "campaign_money_transactions_check1" CHECK ((("source_account" = 'player'::"text") = ("source_user_id" IS NOT NULL))),
    CONSTRAINT "campaign_money_transactions_check2" CHECK ((("destination_account" = 'player'::"text") = ("destination_user_id" IS NOT NULL))),
    CONSTRAINT "campaign_money_transactions_check3" CHECK ((("source_account" <> 'player'::"text") OR ("destination_account" <> 'player'::"text") OR ("source_user_id" <> "destination_user_id"))),
    CONSTRAINT "campaign_money_transactions_comment_check" CHECK ((("comment" IS NULL) OR ("length"("comment") <= 500))),
    CONSTRAINT "campaign_money_transactions_destination_account_check" CHECK (("destination_account" = ANY (ARRAY['external'::"text", 'common'::"text", 'player'::"text"]))),
    CONSTRAINT "campaign_money_transactions_kind_check" CHECK (("kind" = ANY (ARRAY['common_income'::"text", 'personal_income'::"text", 'personal_expense'::"text", 'transfer'::"text", 'sale'::"text", 'purchase'::"text", 'reversal'::"text", 'departure_transfer'::"text", 'gm_adjustment'::"text"]))),
    CONSTRAINT "campaign_money_transactions_source_account_check" CHECK (("source_account" = ANY (ARRAY['external'::"text", 'common'::"text", 'player'::"text"])))
);


ALTER TABLE "public"."campaign_money_transactions" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_money_transactions" IS 'Registre financier immuable ; les corrections sont des transactions inverses.';



CREATE TABLE IF NOT EXISTS "public"."campaign_session_preps" (
    "campaign_id" "uuid" NOT NULL,
    "objective" "text",
    "scenes" "text",
    "reminders" "text",
    "notes" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."campaign_session_preps" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_settings" (
    "campaign_id" "uuid" NOT NULL,
    "current_volume" smallint DEFAULT 1 NOT NULL,
    "jf_cap" integer DEFAULT 15 NOT NULL,
    "minor_cost" integer DEFAULT 3 NOT NULL,
    "moderate_cost" integer DEFAULT 7 NOT NULL,
    "major_cost" integer DEFAULT 12 NOT NULL,
    "liked_threshold" integer DEFAULT 5 NOT NULL,
    "admired_threshold" integer DEFAULT 15 NOT NULL,
    "revered_threshold" integer DEFAULT 30 NOT NULL,
    "carters_major_threshold" integer DEFAULT 25 NOT NULL,
    "tension_max" integer DEFAULT 4 NOT NULL,
    "tension_surcharge_level" integer DEFAULT 2 NOT NULL,
    "tension_surcharge" integer DEFAULT 1 NOT NULL,
    "admired_discount" integer DEFAULT 2 NOT NULL,
    "show_numeric_tension" boolean DEFAULT false NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "show_archive_translations" boolean DEFAULT true NOT NULL,
    "player_display_mode" "text" DEFAULT 'numeric'::"text" NOT NULL,
    "show_all_player_balances" boolean DEFAULT false NOT NULL,
    CONSTRAINT "campaign_settings_admired_discount_check" CHECK (("admired_discount" >= 0)),
    CONSTRAINT "campaign_settings_carters_major_threshold_check" CHECK (("carters_major_threshold" >= 0)),
    CONSTRAINT "campaign_settings_check" CHECK (("admired_threshold" >= "liked_threshold")),
    CONSTRAINT "campaign_settings_check1" CHECK (("revered_threshold" >= "admired_threshold")),
    CONSTRAINT "campaign_settings_current_volume_check" CHECK ((("current_volume" >= 1) AND ("current_volume" <= 6))),
    CONSTRAINT "campaign_settings_jf_cap_check" CHECK (("jf_cap" >= 0)),
    CONSTRAINT "campaign_settings_liked_threshold_check" CHECK (("liked_threshold" >= 0)),
    CONSTRAINT "campaign_settings_major_cost_check" CHECK (("major_cost" >= 0)),
    CONSTRAINT "campaign_settings_minor_cost_check" CHECK (("minor_cost" >= 0)),
    CONSTRAINT "campaign_settings_moderate_cost_check" CHECK (("moderate_cost" >= 0)),
    CONSTRAINT "campaign_settings_player_display_mode_check" CHECK (("player_display_mode" = ANY (ARRAY['numeric'::"text", 'intuitive'::"text"]))),
    CONSTRAINT "campaign_settings_tension_max_check" CHECK (("tension_max" > 0)),
    CONSTRAINT "campaign_settings_tension_surcharge_check" CHECK (("tension_surcharge" >= 0)),
    CONSTRAINT "campaign_settings_tension_surcharge_level_check" CHECK (("tension_surcharge_level" >= 0))
);


ALTER TABLE "public"."campaign_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."campaign_slug_words" (
    "id" integer NOT NULL,
    "creature" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "universe_category" "text" NOT NULL,
    CONSTRAINT "campaign_slug_words_slug_check" CHECK (("slug" ~ '^[a-z0-9]+$'::"text"))
);


ALTER TABLE "public"."campaign_slug_words" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_slug_words" IS 'Référentiel versionné de noms de morts-vivants servant à composer les identifiants publics des campagnes.';



CREATE TABLE IF NOT EXISTS "public"."campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "public_enabled" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "owner_user_id" "uuid",
    "max_participants" smallint DEFAULT 7 NOT NULL,
    CONSTRAINT "campaigns_max_participants_check" CHECK ((("max_participants" >= 1) AND ("max_participants" <= 7))),
    CONSTRAINT "campaigns_slug_check" CHECK (("slug" ~ '^[a-z0-9-]+$'::"text"))
);


ALTER TABLE "public"."campaigns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contact_player_notes" (
    "contact_id" "uuid" NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "character_notes" "text",
    "debt_notes" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "contact_player_notes_character_notes_check" CHECK (("character_length"(COALESCE("character_notes", ''::"text")) <= 10000)),
    CONSTRAINT "contact_player_notes_debt_notes_check" CHECK (("character_length"(COALESCE("debt_notes", ''::"text")) <= 10000)),
    CONSTRAINT "contact_player_notes_notes_check" CHECK (("character_length"(COALESCE("notes", ''::"text")) <= 10000))
);


ALTER TABLE "public"."contact_player_notes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contacts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "faction_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "role" "text" DEFAULT ''::"text" NOT NULL,
    "state" "text" DEFAULT 'À introduire'::"text" NOT NULL,
    "attitude" "text" DEFAULT 'Neutre'::"text" NOT NULL,
    "promise_debt" "text",
    "due_text" "text",
    "gm_notes" "text",
    "visibility" "public"."visibility_status" DEFAULT 'gm_only'::"public"."visibility_status" NOT NULL,
    "is_primary" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "public_description" "text",
    "image_path" "text",
    "avatar_x" numeric DEFAULT 50 NOT NULL,
    "avatar_y" numeric DEFAULT 50 NOT NULL,
    "avatar_zoom" numeric DEFAULT 1 NOT NULL,
    "first_name" "text",
    "last_name" "text",
    CONSTRAINT "contacts_avatar_x_check" CHECK ((("avatar_x" >= (0)::numeric) AND ("avatar_x" <= (100)::numeric))),
    CONSTRAINT "contacts_avatar_y_check" CHECK ((("avatar_y" >= (0)::numeric) AND ("avatar_y" <= (100)::numeric))),
    CONSTRAINT "contacts_avatar_zoom_check" CHECK ((("avatar_zoom" >= (1)::numeric) AND ("avatar_zoom" <= 2.5))),
    CONSTRAINT "contacts_name_check" CHECK (("length"(TRIM(BOTH FROM "name")) > 0))
);


ALTER TABLE "public"."contacts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."faction_relationships" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "source_faction_id" "uuid" NOT NULL,
    "target_faction_id" "uuid" NOT NULL,
    "headline" "text" NOT NULL,
    "detail" "text" NOT NULL,
    "evidence" "public"."relationship_evidence" NOT NULL,
    "tone" "public"."relationship_tone" DEFAULT 'unclear'::"public"."relationship_tone" NOT NULL,
    "visibility" "public"."visibility_status" DEFAULT 'gm_only'::"public"."visibility_status" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "headline_override" "text",
    "detail_override" "text",
    "color_override" "text",
    CONSTRAINT "faction_relationships_check" CHECK (("source_faction_id" <> "target_faction_id")),
    CONSTRAINT "faction_relationships_color_override_check" CHECK (("color_override" = ANY (ARRAY['favorable'::"text", 'uncertain'::"text", 'hostile'::"text"])))
);


ALTER TABLE "public"."faction_relationships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."factions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "name" "text" NOT NULL,
    "short_name" "text" NOT NULL,
    "accent" "text" DEFAULT '#8f7a5a'::"text" NOT NULL,
    "domain" "text" NOT NULL,
    "public_description" "text" NOT NULL,
    "sort_order" smallint NOT NULL,
    CONSTRAINT "factions_accent_check" CHECK (("accent" ~ '^#[0-9A-Fa-f]{6}$'::"text"))
);


ALTER TABLE "public"."factions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "user_id" "uuid" NOT NULL,
    "display_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_profiles_display_name_check" CHECK ((("display_name" IS NULL) OR ((("char_length"("btrim"("display_name")) >= 2) AND ("char_length"("btrim"("display_name")) <= 40)) AND ("display_name" = "btrim"("display_name")))))
);


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."gm_bestiary_history" WITH ("security_barrier"='true') AS
 SELECT "event"."id",
    "event"."campaign_id",
    "event"."entry_id",
    "event"."creature_name",
    "event"."event_type",
        CASE
            WHEN ("event"."actor_user_id" IS NULL) THEN 'Joueur parti'::"text"
            WHEN ("member"."role" = 'gm'::"text") THEN 'Le Maître du Jeu'::"text"
            ELSE COALESCE("profile"."display_name", 'Sans pseudo'::"text")
        END AS "actor_display_name",
    "event"."created_at"
   FROM (("public"."bestiary_events" "event"
     LEFT JOIN "public"."campaign_members" "member" ON ((("member"."campaign_id" = "event"."campaign_id") AND ("member"."user_id" = "event"."actor_user_id"))))
     LEFT JOIN "public"."user_profiles" "profile" ON (("profile"."user_id" = "event"."actor_user_id")))
  WHERE "public"."is_campaign_gm"("event"."campaign_id");


ALTER VIEW "public"."gm_bestiary_history" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."gm_bilateral_dossiers" WITH ("security_invoker"='true') AS
 SELECT "id",
    "campaign_id",
    "faction_a_id",
    "faction_b_id",
    "pair_name",
    "canon_core",
    "a_to_b",
    "b_to_a",
    "common_interest",
    "fracture",
    "triggers",
    "scene_hook",
    "evidence_note"
   FROM "public"."bilateral_dossiers";


ALTER VIEW "public"."gm_bilateral_dossiers" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."gm_contacts" WITH ("security_invoker"='true') AS
 SELECT "ct"."id",
    "ct"."campaign_id",
    "ct"."faction_id",
    "ct"."name",
    "ct"."role",
    "ct"."state",
    "ct"."attitude",
    "ct"."promise_debt",
    "ct"."due_text",
    "ct"."gm_notes",
    "ct"."visibility",
    "ct"."is_primary",
    "ct"."created_at",
    "ct"."updated_at",
    "ct"."public_description",
    "ct"."image_path",
    "ct"."avatar_x",
    "ct"."avatar_y",
    "ct"."avatar_zoom",
    "f"."short_name" AS "faction_name",
    "f"."sort_order" AS "faction_sort_order",
    "pn"."character_notes" AS "player_character_notes",
    "pn"."debt_notes" AS "player_debt_notes",
    "pn"."notes" AS "player_notes",
    "ct"."first_name",
    "ct"."last_name"
   FROM (("public"."contacts" "ct"
     JOIN "public"."factions" "f" ON (("f"."id" = "ct"."faction_id")))
     LEFT JOIN "public"."contact_player_notes" "pn" ON (("pn"."contact_id" = "ct"."id")));


ALTER VIEW "public"."gm_contacts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."journal_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "faction_id" "uuid" NOT NULL,
    "occurred_on" "date" DEFAULT CURRENT_DATE NOT NULL,
    "volume" smallint NOT NULL,
    "title" "text" NOT NULL,
    "details" "text",
    "rp_delta" integer DEFAULT 0 NOT NULL,
    "jf_delta" integer DEFAULT 0 NOT NULL,
    "tension_delta" integer DEFAULT 0 NOT NULL,
    "visibility" "public"."visibility_status" DEFAULT 'gm_only'::"public"."visibility_status" NOT NULL,
    "source_reference" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "milestone_id" "uuid",
    CONSTRAINT "journal_entries_check" CHECK ((("rp_delta" <> 0) OR ("jf_delta" <> 0) OR ("tension_delta" <> 0) OR ("details" IS NOT NULL))),
    CONSTRAINT "journal_entries_title_check" CHECK (("length"(TRIM(BOTH FROM "title")) > 0)),
    CONSTRAINT "journal_entries_volume_check" CHECK ((("volume" >= 1) AND ("volume" <= 6)))
);


ALTER TABLE "public"."journal_entries" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."gm_faction_overview" WITH ("security_invoker"='true') AS
 WITH "totals" AS (
         SELECT "cf_1"."campaign_id",
            "cf_1"."faction_id",
            (GREATEST((0)::bigint, COALESCE("sum"("j"."rp_delta"), (0)::bigint)))::integer AS "rp_raw",
            (GREATEST((0)::bigint, COALESCE("sum"("j"."jf_delta"), (0)::bigint)))::integer AS "jf_raw",
            (GREATEST((0)::bigint, COALESCE("sum"("j"."tension_delta"), (0)::bigint)))::integer AS "tension_raw"
           FROM ("public"."campaign_factions" "cf_1"
             LEFT JOIN "public"."journal_entries" "j" ON ((("j"."campaign_id" = "cf_1"."campaign_id") AND ("j"."faction_id" = "cf_1"."faction_id"))))
          GROUP BY "cf_1"."campaign_id", "cf_1"."faction_id"
        )
 SELECT "cf"."campaign_id",
    "f"."id" AS "faction_id",
    "f"."slug",
    "f"."name",
    "f"."short_name",
    "f"."accent",
    "f"."domain",
    "f"."public_description",
    "f"."sort_order",
    "cf"."public_summary",
    "cf"."gm_notes",
    "cf"."is_player_visible",
    "t"."rp_raw" AS "rp",
    LEAST("s"."jf_cap", "t"."jf_raw") AS "jf",
    LEAST("s"."tension_max", "t"."tension_raw") AS "tension",
        CASE
            WHEN ("t"."rp_raw" >= "s"."revered_threshold") THEN 'Révérés'::"text"
            WHEN ("t"."rp_raw" >= "s"."admired_threshold") THEN 'Admirés'::"text"
            WHEN ("t"."rp_raw" >= "s"."liked_threshold") THEN 'Appréciés'::"text"
            ELSE 'Indifférents'::"text"
        END AS "status",
        CASE
            WHEN (LEAST("s"."tension_max", "t"."tension_raw") = 0) THEN 'Stable'::"text"
            WHEN (LEAST("s"."tension_max", "t"."tension_raw") = 1) THEN 'Signes de froid'::"text"
            WHEN (LEAST("s"."tension_max", "t"."tension_raw") = 2) THEN 'Relations tendues'::"text"
            WHEN (LEAST("s"."tension_max", "t"."tension_raw") = 3) THEN 'Accès limité'::"text"
            ELSE 'Rupture'::"text"
        END AS "tension_label"
   FROM ((("public"."campaign_factions" "cf"
     JOIN "public"."factions" "f" ON (("f"."id" = "cf"."faction_id")))
     JOIN "public"."campaign_settings" "s" ON (("s"."campaign_id" = "cf"."campaign_id")))
     JOIN "totals" "t" ON ((("t"."campaign_id" = "cf"."campaign_id") AND ("t"."faction_id" = "cf"."faction_id"))));


ALTER VIEW "public"."gm_faction_overview" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."gm_journal_entries" WITH ("security_invoker"='true') AS
 SELECT "j"."id",
    "j"."campaign_id",
    "j"."faction_id",
    "j"."occurred_on",
    "j"."volume",
    "j"."title",
    "j"."details",
    "j"."rp_delta",
    "j"."jf_delta",
    "j"."tension_delta",
    "j"."visibility",
    "j"."source_reference",
    "j"."created_at",
    "j"."updated_at",
    "f"."short_name" AS "faction_name"
   FROM ("public"."journal_entries" "j"
     JOIN "public"."factions" "f" ON (("f"."id" = "j"."faction_id")));


ALTER VIEW "public"."gm_journal_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reputation_milestones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "volume" smallint NOT NULL,
    "chapter" "text",
    "title" "text" NOT NULL,
    "beneficiary_faction_id" "uuid",
    "rp_gain" integer DEFAULT 0 NOT NULL,
    "harmed_faction_id" "uuid",
    "rp_loss" integer DEFAULT 0 NOT NULL,
    "condition" "text" NOT NULL,
    "source_reference" "text" NOT NULL,
    "applied" boolean DEFAULT false NOT NULL,
    "gm_notes" "text",
    "sort_order" smallint DEFAULT 0 NOT NULL,
    "applied_at" timestamp with time zone,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "resolution_note" "text",
    "choice_group" "text",
    "reward_effects" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "resolved_effects" "jsonb",
    "resolved_at" timestamp with time zone,
    "excluded_by_milestone_id" "uuid",
    "status_before_exclusion" "text",
    CONSTRAINT "reputation_milestones_rp_gain_check" CHECK (("rp_gain" >= 0)),
    CONSTRAINT "reputation_milestones_rp_loss_check" CHECK (("rp_loss" <= 0)),
    CONSTRAINT "reputation_milestones_status_before_exclusion_check" CHECK (("status_before_exclusion" = ANY (ARRAY['pending'::"text", 'succeeded'::"text", 'missed'::"text"]))),
    CONSTRAINT "reputation_milestones_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'succeeded'::"text", 'missed'::"text", 'excluded'::"text"]))),
    CONSTRAINT "reputation_milestones_volume_check" CHECK ((("volume" >= 1) AND ("volume" <= 6)))
);


ALTER TABLE "public"."reputation_milestones" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."gm_milestones" WITH ("security_invoker"='true') AS
 SELECT "m"."id",
    "m"."campaign_id",
    "m"."volume",
    "m"."chapter",
    "m"."title",
    "m"."beneficiary_faction_id",
    "m"."rp_gain",
    "m"."harmed_faction_id",
    "m"."rp_loss",
    "m"."condition",
    "m"."source_reference",
    "m"."applied",
    "m"."gm_notes",
    "m"."sort_order",
    "m"."applied_at",
    "fb"."short_name" AS "beneficiary_name",
    "fh"."short_name" AS "harmed_name",
    "m"."status",
    "m"."resolution_note",
    "m"."choice_group",
    "m"."reward_effects",
    "m"."resolved_effects",
    "m"."resolved_at",
    "m"."excluded_by_milestone_id",
    "m"."status_before_exclusion",
    "winner"."title" AS "excluded_by_title"
   FROM ((("public"."reputation_milestones" "m"
     LEFT JOIN "public"."factions" "fb" ON (("fb"."id" = "m"."beneficiary_faction_id")))
     LEFT JOIN "public"."factions" "fh" ON (("fh"."id" = "m"."harmed_faction_id")))
     LEFT JOIN "public"."reputation_milestones" "winner" ON (("winner"."id" = "m"."excluded_by_milestone_id")));


ALTER VIEW "public"."gm_milestones" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."gm_relationships" WITH ("security_invoker"='true') AS
 SELECT "r"."id",
    "r"."campaign_id",
    "r"."source_faction_id",
    "r"."target_faction_id",
    COALESCE(NULLIF("btrim"("r"."headline_override"), ''::"text"), "r"."headline") AS "headline",
    COALESCE(NULLIF("btrim"("r"."detail_override"), ''::"text"), "r"."detail") AS "detail",
    "r"."evidence",
    "r"."tone",
    "r"."visibility",
    "r"."updated_at",
    "fs"."short_name" AS "source_name",
    "ft"."short_name" AS "target_name",
    "fs"."sort_order" AS "source_sort_order",
    "ft"."sort_order" AS "target_sort_order",
    "r"."headline" AS "default_headline",
    "r"."detail" AS "default_detail",
    "r"."headline_override",
    "r"."detail_override",
        CASE
            WHEN ("r"."tone" = 'hostility'::"public"."relationship_tone") THEN 'hostile'::"text"
            WHEN ("r"."tone" = ANY (ARRAY['tension'::"public"."relationship_tone", 'unclear'::"public"."relationship_tone"])) THEN 'uncertain'::"text"
            ELSE 'favorable'::"text"
        END AS "default_color",
    "r"."color_override",
    COALESCE("r"."color_override",
        CASE
            WHEN ("r"."tone" = 'hostility'::"public"."relationship_tone") THEN 'hostile'::"text"
            WHEN ("r"."tone" = ANY (ARRAY['tension'::"public"."relationship_tone", 'unclear'::"public"."relationship_tone"])) THEN 'uncertain'::"text"
            ELSE 'favorable'::"text"
        END) AS "color"
   FROM (("public"."faction_relationships" "r"
     JOIN "public"."factions" "fs" ON (("fs"."id" = "r"."source_faction_id")))
     JOIN "public"."factions" "ft" ON (("ft"."id" = "r"."target_faction_id")));


ALTER VIEW "public"."gm_relationships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."services" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "faction_id" "uuid" NOT NULL,
    "scale" "public"."service_scale" NOT NULL,
    "required_rp" integer NOT NULL,
    "base_cost" integer NOT NULL,
    "domain" "text" NOT NULL,
    "examples" "text" NOT NULL,
    "safeguard" "text" NOT NULL,
    "frequency" "text" NOT NULL,
    "player_visible" boolean DEFAULT true NOT NULL,
    "sort_order" smallint DEFAULT 0 NOT NULL,
    CONSTRAINT "services_base_cost_check" CHECK (("base_cost" >= 0)),
    CONSTRAINT "services_required_rp_check" CHECK (("required_rp" >= 0))
);


ALTER TABLE "public"."services" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."gm_services" WITH ("security_invoker"='true') AS
 SELECT "s"."id",
    "s"."campaign_id",
    "s"."faction_id",
    "s"."scale",
    "s"."required_rp",
    "s"."base_cost",
    "s"."domain",
    "s"."examples",
    "s"."safeguard",
    "s"."frequency",
    "s"."player_visible",
    "s"."sort_order",
    "f"."short_name" AS "faction_name",
    "f"."sort_order" AS "faction_sort_order",
        CASE "s"."scale"
            WHEN 'Mineure'::"public"."service_scale" THEN 1
            WHEN 'Modérée'::"public"."service_scale" THEN 2
            ELSE 3
        END AS "scale_sort"
   FROM ("public"."services" "s"
     JOIN "public"."factions" "f" ON (("f"."id" = "s"."faction_id")));


ALTER VIEW "public"."gm_services" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."loot_player_publications" (
    "loot_id" "uuid" NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "published_on" "date" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "owner_user_id" "uuid",
    "lifecycle_status" "text" DEFAULT 'available'::"text" NOT NULL,
    "legacy_owner_label" "text",
    CONSTRAINT "loot_player_publications_lifecycle_status_check" CHECK (("lifecycle_status" = ANY (ARRAY['available'::"text", 'assigned'::"text", 'sold'::"text", 'dismantled'::"text", 'consumed'::"text", 'legacy'::"text"])))
);


ALTER TABLE "public"."loot_player_publications" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_campaign" WITH ("security_barrier"='true') AS
 SELECT "c"."id" AS "campaign_id",
    "c"."slug",
    "c"."name",
    "c"."description",
    "s"."current_volume",
    "s"."jf_cap",
    "s"."minor_cost",
    "s"."moderate_cost",
    "s"."major_cost",
    "s"."liked_threshold",
    "s"."admired_threshold",
    "s"."revered_threshold",
    "s"."carters_major_threshold",
    "s"."tension_max",
    "s"."show_numeric_tension",
    "s"."player_display_mode",
    "s"."show_all_player_balances"
   FROM ("public"."campaigns" "c"
     JOIN "public"."campaign_settings" "s" ON (("s"."campaign_id" = "c"."id")))
  WHERE "public"."is_campaign_member"("c"."id");


ALTER VIEW "public"."player_campaign" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_contacts" WITH ("security_barrier"='true') AS
 SELECT "ct"."id",
    "ct"."campaign_id",
    "ct"."faction_id",
    "f"."short_name" AS "faction_name",
    "ct"."name",
    "ct"."role",
    "ct"."state",
    "ct"."attitude",
    "ct"."promise_debt",
    "ct"."due_text",
    "ct"."visibility",
    "ct"."is_primary",
    "pn"."character_notes" AS "player_character_notes",
    "pn"."debt_notes" AS "player_debt_notes",
    "pn"."notes" AS "player_notes",
    "ct"."public_description",
    "ct"."image_path",
    "ct"."avatar_x",
    "ct"."avatar_y",
    "ct"."avatar_zoom",
    "ct"."first_name",
    "ct"."last_name"
   FROM ((("public"."contacts" "ct"
     JOIN "public"."factions" "f" ON (("f"."id" = "ct"."faction_id")))
     JOIN "public"."campaign_factions" "cf" ON ((("cf"."campaign_id" = "ct"."campaign_id") AND ("cf"."faction_id" = "ct"."faction_id") AND "cf"."is_player_visible")))
     LEFT JOIN "public"."contact_player_notes" "pn" ON (("pn"."contact_id" = "ct"."id")))
  WHERE (("ct"."visibility" = 'players'::"public"."visibility_status") AND "public"."is_campaign_member"("ct"."campaign_id"));


ALTER VIEW "public"."player_contacts" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_economy_totals" WITH ("security_barrier"='true') AS
 SELECT "id" AS "campaign_id",
    (((COALESCE(( SELECT "sum"(((COALESCE("event"."value_cp", (0)::bigint))::numeric * COALESCE("event"."quantity", (1)::numeric))) AS "sum"
           FROM ("public"."campaign_item_events" "event"
             JOIN "public"."campaign_inventory_items" "item" ON (("item"."id" = "event"."item_id")))
          WHERE (("event"."campaign_id" = "campaign"."id") AND ("event"."event_type" = ANY (ARRAY['published'::"text", 'created'::"text"])) AND (("event"."event_type" <> 'created'::"text") OR ("event"."related_item_id" IS NULL)) AND "item"."counts_as_gain" AND ("event"."reversed_event_id" IS NULL) AND (NOT (EXISTS ( SELECT 1
                   FROM "public"."campaign_item_events" "reversal"
                  WHERE ("reversal"."reversed_event_id" = "event"."id")))) AND ("item"."player_visible" OR "public"."is_campaign_gm"("campaign"."id")))), (0)::numeric) + COALESCE(( SELECT "sum"("transaction"."amount_cp") AS "sum"
           FROM "public"."campaign_money_transactions" "transaction"
          WHERE (("transaction"."campaign_id" = "campaign"."id") AND ("transaction"."source_account" = 'external'::"text") AND ("transaction"."kind" <> 'sale'::"text") AND ("transaction"."reversed_transaction_id" IS NULL) AND (NOT (EXISTS ( SELECT 1
                   FROM "public"."campaign_money_transactions" "reversal"
                  WHERE ("reversal"."reversed_transaction_id" = "transaction"."id")))) AND (("transaction"."related_item_id" IS NULL) OR (EXISTS ( SELECT 1
                   FROM "public"."campaign_inventory_items" "visible_item"
                  WHERE (("visible_item"."id" = "transaction"."related_item_id") AND ("visible_item"."player_visible" OR "public"."is_campaign_gm"("campaign"."id")))))))), (0)::numeric)) + COALESCE(( SELECT "sum"(GREATEST((0)::numeric, ((COALESCE("event"."value_cp", (0)::bigint))::numeric - ((COALESCE("item"."unit_value_cp", (0)::bigint))::numeric * COALESCE("event"."quantity", (1)::numeric))))) AS "sum"
           FROM ("public"."campaign_item_events" "event"
             JOIN "public"."campaign_inventory_items" "item" ON (("item"."id" = "event"."item_id")))
          WHERE (("event"."campaign_id" = "campaign"."id") AND ("event"."event_type" = 'sold'::"text") AND ("event"."reversed_event_id" IS NULL) AND (NOT (EXISTS ( SELECT 1
                   FROM "public"."campaign_item_events" "reversal"
                  WHERE ("reversal"."reversed_event_id" = "event"."id")))) AND ("item"."player_visible" OR "public"."is_campaign_gm"("campaign"."id")))), (0)::numeric)))::bigint AS "total_entered_cp",
    (COALESCE(( SELECT "sum"("transaction"."amount_cp") AS "sum"
           FROM "public"."campaign_money_transactions" "transaction"
          WHERE (("transaction"."campaign_id" = "campaign"."id") AND ("transaction"."destination_account" = 'external'::"text") AND ("transaction"."reversed_transaction_id" IS NULL) AND (NOT (EXISTS ( SELECT 1
                   FROM "public"."campaign_money_transactions" "reversal"
                  WHERE ("reversal"."reversed_transaction_id" = "transaction"."id")))) AND (("transaction"."related_item_id" IS NULL) OR (EXISTS ( SELECT 1
                   FROM "public"."campaign_inventory_items" "visible_item"
                  WHERE (("visible_item"."id" = "transaction"."related_item_id") AND ("visible_item"."player_visible" OR "public"."is_campaign_gm"("campaign"."id")))))))), (0)::numeric))::bigint AS "total_exited_cp",
    ((COALESCE(( SELECT "sum"(
                CASE
                    WHEN ("transaction"."source_account" = 'external'::"text") THEN "transaction"."amount_cp"
                    WHEN ("transaction"."destination_account" = 'external'::"text") THEN (- "transaction"."amount_cp")
                    ELSE (0)::bigint
                END) AS "sum"
           FROM "public"."campaign_money_transactions" "transaction"
          WHERE ("transaction"."campaign_id" = "campaign"."id")), (0)::numeric) + COALESCE(( SELECT "sum"(((COALESCE("item"."unit_value_cp", (0)::bigint))::numeric * "item"."quantity")) AS "sum"
           FROM "public"."campaign_inventory_items" "item"
          WHERE (("item"."campaign_id" = "campaign"."id") AND ("item"."status" = 'active'::"text") AND ("item"."player_visible" OR "public"."is_campaign_gm"("campaign"."id")))), (0)::numeric)))::bigint AS "current_wealth_cp"
   FROM "public"."campaigns" "campaign"
  WHERE "public"."is_campaign_member"("id");


ALTER VIEW "public"."player_economy_totals" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_faction_overview" WITH ("security_barrier"='true') AS
 WITH "totals" AS (
         SELECT "cf_1"."campaign_id",
            "cf_1"."faction_id",
            (GREATEST((0)::bigint, COALESCE("sum"("j"."rp_delta"), (0)::bigint)))::integer AS "rp_raw",
            (GREATEST((0)::bigint, COALESCE("sum"("j"."jf_delta"), (0)::bigint)))::integer AS "jf_raw",
            (GREATEST((0)::bigint, COALESCE("sum"("j"."tension_delta"), (0)::bigint)))::integer AS "tension_raw"
           FROM ("public"."campaign_factions" "cf_1"
             LEFT JOIN "public"."journal_entries" "j" ON ((("j"."campaign_id" = "cf_1"."campaign_id") AND ("j"."faction_id" = "cf_1"."faction_id"))))
          GROUP BY "cf_1"."campaign_id", "cf_1"."faction_id"
        )
 SELECT "cf"."campaign_id",
    "f"."id" AS "faction_id",
    "f"."slug",
    "f"."name",
    "f"."short_name",
    "f"."accent",
    "f"."domain",
    "f"."public_description",
    "f"."sort_order",
    "cf"."public_summary",
    "cf"."is_player_visible",
    "totals"."rp_raw" AS "rp",
    LEAST("s"."jf_cap", "totals"."jf_raw") AS "jf",
        CASE
            WHEN "s"."show_numeric_tension" THEN LEAST("s"."tension_max", "totals"."tension_raw")
            ELSE NULL::integer
        END AS "tension",
        CASE
            WHEN ("totals"."rp_raw" >= "s"."revered_threshold") THEN 'Révérés'::"text"
            WHEN ("totals"."rp_raw" >= "s"."admired_threshold") THEN 'Admirés'::"text"
            WHEN ("totals"."rp_raw" >= "s"."liked_threshold") THEN 'Appréciés'::"text"
            ELSE 'Indifférents'::"text"
        END AS "status",
        CASE
            WHEN (LEAST("s"."tension_max", "totals"."tension_raw") = 0) THEN 'Stable'::"text"
            WHEN (LEAST("s"."tension_max", "totals"."tension_raw") = 1) THEN 'Signes de froid'::"text"
            WHEN (LEAST("s"."tension_max", "totals"."tension_raw") = 2) THEN 'Relations tendues'::"text"
            WHEN (LEAST("s"."tension_max", "totals"."tension_raw") = 3) THEN 'Accès limité'::"text"
            ELSE 'Rupture'::"text"
        END AS "tension_label"
   FROM ((("public"."campaign_factions" "cf"
     JOIN "public"."factions" "f" ON (("f"."id" = "cf"."faction_id")))
     JOIN "public"."campaign_settings" "s" ON (("s"."campaign_id" = "cf"."campaign_id")))
     JOIN "totals" ON ((("totals"."campaign_id" = "cf"."campaign_id") AND ("totals"."faction_id" = "cf"."faction_id"))))
  WHERE ("cf"."is_player_visible" AND "public"."is_campaign_member"("cf"."campaign_id"));


ALTER VIEW "public"."player_faction_overview" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_inventory_items" WITH ("security_barrier"='true') AS
 SELECT "item"."id",
    "item"."campaign_id",
    "item"."origin_loot_id",
    "item"."parent_item_id",
    "item"."created_by",
    "item"."owner_user_id",
    "item"."name",
    "item"."quantity",
    "item"."source_quantity_label",
    "item"."unit_value_cp",
    "item"."purchase_price_cp",
    "item"."aon_legacy_name",
    "item"."aon_legacy_url",
    "item"."source_kind",
    "item"."player_visible",
    "item"."status",
    "item"."acquired_on",
    "item"."created_at",
    "item"."updated_at",
    "owner_profile"."display_name" AS "owner_display_name",
    "creator_profile"."display_name" AS "created_by_display_name",
    (COALESCE("request_totals"."pending_request_count", (0)::bigint))::integer AS "pending_request_count",
    (EXISTS ( SELECT 1
           FROM "public"."campaign_item_requests" "request"
          WHERE (("request"."item_id" = "item"."id") AND ("request"."requester_user_id" = "auth"."uid"()) AND ("request"."status" = 'pending'::"text")))) AS "requested_by_me"
   FROM ((("public"."campaign_inventory_items" "item"
     LEFT JOIN "public"."user_profiles" "owner_profile" ON (("owner_profile"."user_id" = "item"."owner_user_id")))
     LEFT JOIN "public"."user_profiles" "creator_profile" ON (("creator_profile"."user_id" = "item"."created_by")))
     LEFT JOIN LATERAL ( SELECT "count"(*) AS "pending_request_count"
           FROM "public"."campaign_item_requests" "request"
          WHERE (("request"."item_id" = "item"."id") AND ("request"."status" = 'pending'::"text"))) "request_totals" ON (true))
  WHERE ("item"."player_visible" AND "public"."is_campaign_member"("item"."campaign_id"));


ALTER VIEW "public"."player_inventory_items" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_item_history" WITH ("security_barrier"='true') AS
 SELECT "event"."id",
    "event"."campaign_id",
    "event"."item_id",
    "event"."actor_user_id",
    "event"."event_type",
    "event"."previous_owner_user_id",
    "event"."next_owner_user_id",
    "event"."quantity",
    "event"."value_cp",
    "event"."comment",
    "event"."related_item_id",
    "event"."money_operation_id",
    "event"."reversed_event_id",
    "event"."created_at",
    "item"."name" AS "item_name",
    "related"."name" AS "related_item_name",
        CASE
            WHEN ("actor_member"."role" = 'gm'::"text") THEN 'Le Maître du Jeu'::"text"
            ELSE "actor_profile"."display_name"
        END AS "actor_display_name",
    "previous_profile"."display_name" AS "previous_owner_display_name",
    "next_profile"."display_name" AS "next_owner_display_name"
   FROM (((((("public"."campaign_item_events" "event"
     LEFT JOIN "public"."campaign_inventory_items" "item" ON (("item"."id" = "event"."item_id")))
     LEFT JOIN "public"."campaign_inventory_items" "related" ON (("related"."id" = "event"."related_item_id")))
     LEFT JOIN "public"."user_profiles" "actor_profile" ON (("actor_profile"."user_id" = "event"."actor_user_id")))
     LEFT JOIN "public"."campaign_members" "actor_member" ON ((("actor_member"."campaign_id" = "event"."campaign_id") AND ("actor_member"."user_id" = "event"."actor_user_id"))))
     LEFT JOIN "public"."user_profiles" "previous_profile" ON (("previous_profile"."user_id" = "event"."previous_owner_user_id")))
     LEFT JOIN "public"."user_profiles" "next_profile" ON (("next_profile"."user_id" = "event"."next_owner_user_id")))
  WHERE ("public"."is_campaign_member"("event"."campaign_id") AND ("public"."is_campaign_gm"("event"."campaign_id") OR COALESCE("item"."player_visible", "related"."player_visible", false)));


ALTER VIEW "public"."player_item_history" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_item_request_overview" WITH ("security_barrier"='true') AS
 SELECT "request"."id",
    "request"."campaign_id",
    "request"."item_id",
    "request"."requester_user_id",
    "request"."owner_user_id",
    "request"."status",
    "request"."created_at",
    "request"."resolved_at",
    "item"."name" AS "item_name",
    "requester"."display_name" AS "requester_display_name",
    "owner"."display_name" AS "owner_display_name"
   FROM ((("public"."campaign_item_requests" "request"
     JOIN "public"."campaign_inventory_items" "item" ON (("item"."id" = "request"."item_id")))
     LEFT JOIN "public"."user_profiles" "requester" ON (("requester"."user_id" = "request"."requester_user_id")))
     LEFT JOIN "public"."user_profiles" "owner" ON (("owner"."user_id" = "request"."owner_user_id")))
  WHERE ("public"."is_campaign_member"("request"."campaign_id") AND (("request"."requester_user_id" = "auth"."uid"()) OR ("request"."owner_user_id" = "auth"."uid"()) OR "public"."is_campaign_gm"("request"."campaign_id")));


ALTER VIEW "public"."player_item_request_overview" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_journal" WITH ("security_barrier"='true') AS
 SELECT "j"."id",
    "j"."campaign_id",
    "j"."faction_id",
    "f"."short_name" AS "faction_name",
    "j"."occurred_on",
    "j"."volume",
    "j"."title",
    "j"."details",
    "j"."rp_delta",
    "j"."jf_delta",
        CASE
            WHEN "s"."show_numeric_tension" THEN "j"."tension_delta"
            ELSE NULL::integer
        END AS "tension_delta",
    "j"."visibility"
   FROM ((("public"."journal_entries" "j"
     JOIN "public"."factions" "f" ON (("f"."id" = "j"."faction_id")))
     JOIN "public"."campaign_factions" "cf" ON ((("cf"."campaign_id" = "j"."campaign_id") AND ("cf"."faction_id" = "j"."faction_id") AND "cf"."is_player_visible")))
     JOIN "public"."campaign_settings" "s" ON (("s"."campaign_id" = "j"."campaign_id")))
  WHERE (("j"."visibility" = 'players'::"public"."visibility_status") AND "public"."is_campaign_member"("j"."campaign_id"));


ALTER VIEW "public"."player_journal" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_loot" WITH ("security_barrier"='true') AS
 SELECT "loot"."campaign_id",
    "loot"."sort_order",
    "loot"."item_name" AS "original_name",
    "loot"."quantity_recoverable" AS "quantity",
        CASE
            WHEN ("loot"."book_unit_value_amount" IS NOT NULL) THEN ((("loot"."book_unit_value_amount")::"text" || ' '::"text") || "loot"."book_unit_value_currency")
            WHEN ("loot"."aon_legacy_unit_value_amount" IS NOT NULL) THEN ((("loot"."aon_legacy_unit_value_amount")::"text" || ' '::"text") || "loot"."aon_legacy_unit_value_currency")
            ELSE NULL::"text"
        END AS "unit_value",
    COALESCE("loot"."location_name", "loot"."area_title") AS "location_name",
    "loot"."aon_legacy_name",
    "loot"."aon_legacy_url",
    "loot"."id" AS "loot_id",
    "publication"."published_on",
    "publication"."owner_user_id",
    "profile"."display_name" AS "owner_display_name",
    "publication"."lifecycle_status",
    "publication"."legacy_owner_label"
   FROM (("public"."campaign_loot" "loot"
     JOIN "public"."loot_player_publications" "publication" ON (("publication"."loot_id" = "loot"."id")))
     LEFT JOIN "public"."user_profiles" "profile" ON (("profile"."user_id" = "publication"."owner_user_id")))
  WHERE ("loot"."player_visible" AND "public"."is_campaign_member"("loot"."campaign_id"));


ALTER VIEW "public"."player_loot" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_money_balances" WITH ("security_barrier"='true') AS
 WITH "accounts" AS (
         SELECT "campaign"."id" AS "campaign_id",
            NULL::"uuid" AS "account_user_id",
            'Compte commun'::"text" AS "display_name",
            true AS "is_common"
           FROM "public"."campaigns" "campaign"
          WHERE "public"."is_campaign_member"("campaign"."id")
        UNION ALL
         SELECT "member"."campaign_id",
            "member"."user_id",
            COALESCE("profile"."display_name", 'Joueur'::"text") AS "display_name",
            false AS "is_common"
           FROM ("public"."campaign_members" "member"
             LEFT JOIN "public"."user_profiles" "profile" ON (("profile"."user_id" = "member"."user_id")))
          WHERE (("member"."role" = 'player'::"text") AND "public"."is_campaign_member"("member"."campaign_id"))
        )
 SELECT "account"."campaign_id",
    "account"."account_user_id",
    "account"."display_name",
    "account"."is_common",
    (COALESCE("sum"(
        CASE
            WHEN (("transaction"."destination_account" =
            CASE
                WHEN "account"."is_common" THEN 'common'::"text"
                ELSE 'player'::"text"
            END) AND ("account"."is_common" OR ("transaction"."destination_user_id" = "account"."account_user_id"))) THEN "transaction"."amount_cp"
            WHEN (("transaction"."source_account" =
            CASE
                WHEN "account"."is_common" THEN 'common'::"text"
                ELSE 'player'::"text"
            END) AND ("account"."is_common" OR ("transaction"."source_user_id" = "account"."account_user_id"))) THEN (- "transaction"."amount_cp")
            ELSE (0)::bigint
        END), (0)::numeric))::bigint AS "balance_cp"
   FROM (("accounts" "account"
     JOIN "public"."campaign_settings" "settings" ON (("settings"."campaign_id" = "account"."campaign_id")))
     LEFT JOIN "public"."campaign_money_transactions" "transaction" ON (("transaction"."campaign_id" = "account"."campaign_id")))
  WHERE ("account"."is_common" OR ("account"."account_user_id" = "auth"."uid"()) OR "public"."is_campaign_gm"("account"."campaign_id") OR "settings"."show_all_player_balances")
  GROUP BY "account"."campaign_id", "account"."account_user_id", "account"."display_name", "account"."is_common";


ALTER VIEW "public"."player_money_balances" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_money_debt_overview" WITH ("security_barrier"='true') AS
 SELECT "debt"."id",
    "debt"."campaign_id",
    "debt"."debtor_user_id",
    "debt"."creditor_user_id",
    "debt"."amount_cp",
    "debt"."remaining_cp",
    "debt"."status",
    "debt"."comment",
    "debt"."created_by",
    "debt"."created_at",
    "debt"."updated_at",
    "debtor"."display_name" AS "debtor_display_name",
    "creditor"."display_name" AS "creditor_display_name"
   FROM ((("public"."campaign_money_debts" "debt"
     LEFT JOIN "public"."user_profiles" "debtor" ON (("debtor"."user_id" = "debt"."debtor_user_id")))
     LEFT JOIN "public"."user_profiles" "creditor" ON (("creditor"."user_id" = "debt"."creditor_user_id")))
     JOIN "public"."campaign_settings" "settings" ON (("settings"."campaign_id" = "debt"."campaign_id")))
  WHERE ("public"."is_campaign_member"("debt"."campaign_id") AND ("public"."is_campaign_gm"("debt"."campaign_id") OR "settings"."show_all_player_balances" OR ("debt"."debtor_user_id" = "auth"."uid"()) OR ("debt"."creditor_user_id" = "auth"."uid"())));


ALTER VIEW "public"."player_money_debt_overview" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_money_history" WITH ("security_barrier"='true') AS
 SELECT "transaction"."id",
    "transaction"."operation_id",
    "transaction"."campaign_id",
    "transaction"."actor_user_id",
    "transaction"."kind",
    "transaction"."source_account",
    "transaction"."source_user_id",
    "transaction"."destination_account",
    "transaction"."destination_user_id",
    "transaction"."amount_cp",
    "transaction"."comment",
    "transaction"."related_item_id",
    "transaction"."reversed_transaction_id",
    "transaction"."created_at",
        CASE
            WHEN ("actor_member"."role" = 'gm'::"text") THEN 'Le Maître du Jeu'::"text"
            ELSE "actor_profile"."display_name"
        END AS "actor_display_name",
    "source_profile"."display_name" AS "source_display_name",
    "destination_profile"."display_name" AS "destination_display_name",
    "item"."name" AS "related_item_name"
   FROM (((((("public"."campaign_money_transactions" "transaction"
     JOIN "public"."campaign_settings" "settings" ON (("settings"."campaign_id" = "transaction"."campaign_id")))
     LEFT JOIN "public"."user_profiles" "actor_profile" ON (("actor_profile"."user_id" = "transaction"."actor_user_id")))
     LEFT JOIN "public"."campaign_members" "actor_member" ON ((("actor_member"."campaign_id" = "transaction"."campaign_id") AND ("actor_member"."user_id" = "transaction"."actor_user_id"))))
     LEFT JOIN "public"."user_profiles" "source_profile" ON (("source_profile"."user_id" = "transaction"."source_user_id")))
     LEFT JOIN "public"."user_profiles" "destination_profile" ON (("destination_profile"."user_id" = "transaction"."destination_user_id")))
     LEFT JOIN "public"."campaign_inventory_items" "item" ON (("item"."id" = "transaction"."related_item_id")))
  WHERE ("public"."is_campaign_member"("transaction"."campaign_id") AND (("transaction"."related_item_id" IS NULL) OR "item"."player_visible" OR "public"."is_campaign_gm"("transaction"."campaign_id")) AND ("public"."is_campaign_gm"("transaction"."campaign_id") OR "settings"."show_all_player_balances" OR ("transaction"."source_account" = 'common'::"text") OR ("transaction"."destination_account" = 'common'::"text") OR ("transaction"."source_user_id" = "auth"."uid"()) OR ("transaction"."destination_user_id" = "auth"."uid"()) OR ("transaction"."actor_user_id" = "auth"."uid"())));


ALTER VIEW "public"."player_money_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."player_pages" (
    "campaign_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "character_name" "text",
    "character_summary" "text",
    "pathbuilder_url" "text",
    "notes" "text",
    "objectives" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "image_path" "text",
    "image_x" numeric DEFAULT 50 NOT NULL,
    "image_y" numeric DEFAULT 50 NOT NULL,
    "image_zoom" numeric DEFAULT 1 NOT NULL,
    "character_title" "text",
    CONSTRAINT "player_pages_character_name_check" CHECK (("char_length"(COALESCE("character_name", ''::"text")) <= 120)),
    CONSTRAINT "player_pages_character_summary_check" CHECK (("char_length"(COALESCE("character_summary", ''::"text")) <= 4000)),
    CONSTRAINT "player_pages_character_title_length" CHECK (("char_length"(COALESCE("character_title", ''::"text")) <= 160)),
    CONSTRAINT "player_pages_image_x_range" CHECK ((("image_x" >= (0)::numeric) AND ("image_x" <= (100)::numeric))),
    CONSTRAINT "player_pages_image_y_range" CHECK ((("image_y" >= (0)::numeric) AND ("image_y" <= (100)::numeric))),
    CONSTRAINT "player_pages_image_zoom_range" CHECK ((("image_zoom" >= (1)::numeric) AND ("image_zoom" <= 2.5))),
    CONSTRAINT "player_pages_notes_check" CHECK (("char_length"(COALESCE("notes", ''::"text")) <= 20000)),
    CONSTRAINT "player_pages_objectives_check" CHECK (("char_length"(COALESCE("objectives", ''::"text")) <= 10000)),
    CONSTRAINT "player_pages_pathbuilder_url_check" CHECK ((("pathbuilder_url" IS NULL) OR (("char_length"("pathbuilder_url") <= 500) AND (("lower"("pathbuilder_url") ~~ 'https://pathbuilder2e.com/%'::"text") OR ("lower"("pathbuilder_url") ~~ 'https://www.pathbuilder2e.com/%'::"text")))))
);


ALTER TABLE "public"."player_pages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."player_relationship_notes" (
    "campaign_id" "uuid" NOT NULL,
    "author_user_id" "uuid" NOT NULL,
    "target_user_id" "uuid" NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "player_relationship_notes_distinct_players" CHECK (("author_user_id" <> "target_user_id")),
    CONSTRAINT "player_relationship_notes_length" CHECK (("char_length"(COALESCE("notes", ''::"text")) <= 10000))
);


ALTER TABLE "public"."player_relationship_notes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_relationships" WITH ("security_barrier"='true') AS
 SELECT "r"."id",
    "r"."campaign_id",
    "r"."source_faction_id",
    "fs"."short_name" AS "source_name",
    "r"."target_faction_id",
    "ft"."short_name" AS "target_name",
    COALESCE(NULLIF("btrim"("r"."headline_override"), ''::"text"), "r"."headline") AS "headline",
    COALESCE(NULLIF("btrim"("r"."detail_override"), ''::"text"), "r"."detail") AS "detail",
    "r"."tone",
    "r"."visibility",
    "fs"."sort_order" AS "source_sort_order",
    "ft"."sort_order" AS "target_sort_order",
    COALESCE("r"."color_override",
        CASE
            WHEN ("r"."tone" = 'hostility'::"public"."relationship_tone") THEN 'hostile'::"text"
            WHEN ("r"."tone" = ANY (ARRAY['tension'::"public"."relationship_tone", 'unclear'::"public"."relationship_tone"])) THEN 'uncertain'::"text"
            ELSE 'favorable'::"text"
        END) AS "color"
   FROM (((("public"."faction_relationships" "r"
     JOIN "public"."factions" "fs" ON (("fs"."id" = "r"."source_faction_id")))
     JOIN "public"."factions" "ft" ON (("ft"."id" = "r"."target_faction_id")))
     JOIN "public"."campaign_factions" "source_cf" ON ((("source_cf"."campaign_id" = "r"."campaign_id") AND ("source_cf"."faction_id" = "r"."source_faction_id") AND "source_cf"."is_player_visible")))
     JOIN "public"."campaign_factions" "target_cf" ON ((("target_cf"."campaign_id" = "r"."campaign_id") AND ("target_cf"."faction_id" = "r"."target_faction_id") AND "target_cf"."is_player_visible")))
  WHERE (("r"."visibility" = 'players'::"public"."visibility_status") AND "public"."is_campaign_member"("r"."campaign_id"));


ALTER VIEW "public"."player_relationships" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."player_services" WITH ("security_barrier"='true') AS
 WITH "totals" AS (
         SELECT "cf_1"."campaign_id",
            "cf_1"."faction_id",
            (GREATEST((0)::bigint, COALESCE("sum"("j"."rp_delta"), (0)::bigint)))::integer AS "rp_raw",
            (GREATEST((0)::bigint, COALESCE("sum"("j"."tension_delta"), (0)::bigint)))::integer AS "tension_raw"
           FROM ("public"."campaign_factions" "cf_1"
             LEFT JOIN "public"."journal_entries" "j" ON ((("j"."campaign_id" = "cf_1"."campaign_id") AND ("j"."faction_id" = "cf_1"."faction_id"))))
          GROUP BY "cf_1"."campaign_id", "cf_1"."faction_id"
        )
 SELECT "s"."id",
    "s"."campaign_id",
    "s"."faction_id",
    "f"."short_name" AS "faction_name",
    "s"."scale",
    "s"."required_rp",
    "s"."base_cost",
    "s"."domain",
    "s"."examples",
    "s"."safeguard",
    "s"."frequency",
    "s"."player_visible",
    "f"."sort_order" AS "faction_sort_order",
        CASE "s"."scale"
            WHEN 'Mineure'::"public"."service_scale" THEN 1
            WHEN 'Modérée'::"public"."service_scale" THEN 2
            ELSE 3
        END AS "scale_sort"
   FROM (((("public"."services" "s"
     JOIN "public"."factions" "f" ON (("f"."id" = "s"."faction_id")))
     JOIN "public"."campaign_factions" "cf" ON ((("cf"."campaign_id" = "s"."campaign_id") AND ("cf"."faction_id" = "s"."faction_id"))))
     JOIN "totals" ON ((("totals"."campaign_id" = "s"."campaign_id") AND ("totals"."faction_id" = "s"."faction_id"))))
     JOIN "public"."campaign_settings" "settings" ON (("settings"."campaign_id" = "s"."campaign_id")))
  WHERE ("s"."player_visible" AND "cf"."is_player_visible" AND ("totals"."rp_raw" >= "s"."required_rp") AND (LEAST("settings"."tension_max", "totals"."tension_raw") < "settings"."tension_max") AND "public"."is_campaign_member"("s"."campaign_id"));


ALTER VIEW "public"."player_services" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."quest_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "notes" "text",
    "status" "text" DEFAULT 'Actif'::"text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "category" "text" DEFAULT 'Pistes'::"text" NOT NULL,
    CONSTRAINT "quest_entries_category_check" CHECK (("category" = ANY (ARRAY['Pistes'::"text", 'Objectifs'::"text", 'Questions'::"text", 'Informations'::"text"]))),
    CONSTRAINT "quest_entries_status_check" CHECK (("status" = ANY (ARRAY['Actif'::"text", 'Résolu'::"text", 'Abandonné'::"text"]))),
    CONSTRAINT "quest_entries_title_check" CHECK (("length"("btrim"("title")) > 0))
);


ALTER TABLE "public"."quest_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."quest_journal_blocks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "document_id" "uuid" NOT NULL,
    "kind" "text" DEFAULT 'paragraph'::"text" NOT NULL,
    "content" "text" DEFAULT ''::"text" NOT NULL,
    "label" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_locked" boolean DEFAULT false NOT NULL,
    "is_collapsed" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "quest_journal_blocks_kind_check" CHECK (("kind" = ANY (ARRAY['paragraph'::"text", 'heading'::"text", 'callout'::"text", 'quote'::"text", 'toggle'::"text", 'divider'::"text"])))
);


ALTER TABLE "public"."quest_journal_blocks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."quest_journal_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "occurred_on" "date" DEFAULT CURRENT_DATE NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_collapsed" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "quest_journal_documents_title_check" CHECK (("length"("btrim"("title")) > 0))
);


ALTER TABLE "public"."quest_journal_documents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."quest_journal_pages" (
    "campaign_id" "uuid" NOT NULL,
    "content" "text" DEFAULT ''::"text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revision" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."quest_journal_pages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."quest_journal_revisions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "content" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."quest_journal_revisions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."source_references" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "source_type" "text" NOT NULL,
    "title" "text" NOT NULL,
    "reference" "text",
    "usage_note" "text",
    "locator" "text",
    "sort_order" smallint DEFAULT 0 NOT NULL,
    CONSTRAINT "source_references_source_type_check" CHECK (("source_type" = ANY (ARRAY['Officiel'::"text", 'Communauté'::"text", 'Synthèse'::"text"])))
);


ALTER TABLE "public"."source_references" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "storage"."buckets" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "public" boolean DEFAULT false,
    "avif_autodetection" boolean DEFAULT false,
    "file_size_limit" bigint,
    "allowed_mime_types" "text"[],
    "owner_id" "text",
    "type" "storage"."buckettype" DEFAULT 'STANDARD'::"storage"."buckettype" NOT NULL,
    "versioning_status" "text" DEFAULT 'DISABLED'::"text" NOT NULL,
    CONSTRAINT "buckets_versioning_dark_check" CHECK (("versioning_status" = 'DISABLED'::"text")),
    CONSTRAINT "buckets_versioning_standard_only_check" CHECK ((("type" = 'STANDARD'::"storage"."buckettype") OR ("versioning_status" = 'DISABLED'::"text"))),
    CONSTRAINT "buckets_versioning_status_check" CHECK (("versioning_status" = ANY (ARRAY['DISABLED'::"text", 'ENABLED'::"text", 'SUSPENDED'::"text"])))
);


ALTER TABLE "storage"."buckets" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."buckets"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."buckets_analytics" (
    "name" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'ANALYTICS'::"storage"."buckettype" NOT NULL,
    "format" "text" DEFAULT 'ICEBERG'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "storage"."buckets_analytics" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."buckets_vectors" (
    "id" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'VECTOR'::"storage"."buckettype" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."buckets_vectors" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."migrations" (
    "id" integer NOT NULL,
    "name" character varying(100) NOT NULL,
    "hash" character varying(40) NOT NULL,
    "executed_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "storage"."migrations" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."objects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bucket_id" "text",
    "name" "text",
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_accessed_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb",
    "path_tokens" "text"[] GENERATED ALWAYS AS ("string_to_array"("name", '/'::"text")) STORED,
    "version" "text",
    "owner_id" "text",
    "user_metadata" "jsonb",
    "archived_at" timestamp with time zone,
    "is_delete_marker" boolean DEFAULT false NOT NULL,
    "is_versioned" boolean DEFAULT false NOT NULL
);


ALTER TABLE "storage"."objects" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."objects"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads" (
    "id" "text" NOT NULL,
    "in_progress_size" bigint DEFAULT 0 NOT NULL,
    "upload_signature" "text" NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "version" "text" NOT NULL,
    "owner_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_metadata" "jsonb",
    "metadata" "jsonb"
);


ALTER TABLE "storage"."s3_multipart_uploads" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads_parts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "upload_id" "text" NOT NULL,
    "size" bigint DEFAULT 0 NOT NULL,
    "part_number" integer NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "etag" "text" NOT NULL,
    "owner_id" "text",
    "version" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."s3_multipart_uploads_parts" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."vector_indexes" (
    "id" "text" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL COLLATE "pg_catalog"."C",
    "bucket_id" "text" NOT NULL,
    "data_type" "text" NOT NULL,
    "dimension" integer NOT NULL,
    "distance_metric" "text" NOT NULL,
    "metadata_configuration" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."vector_indexes" OWNER TO "supabase_storage_admin";


ALTER TABLE ONLY "public"."archive_character_templates"
    ADD CONSTRAINT "archive_character_templates_pkey" PRIMARY KEY ("template_key");



ALTER TABLE ONLY "public"."archive_characters"
    ADD CONSTRAINT "archive_characters_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."archive_place_templates"
    ADD CONSTRAINT "archive_place_templates_pkey" PRIMARY KEY ("template_key");



ALTER TABLE ONLY "public"."archive_places"
    ADD CONSTRAINT "archive_places_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bestiary_entries"
    ADD CONSTRAINT "bestiary_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bestiary_events"
    ADD CONSTRAINT "bestiary_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bilateral_dossiers"
    ADD CONSTRAINT "bilateral_dossiers_campaign_id_faction_a_id_faction_b_id_key" UNIQUE ("campaign_id", "faction_a_id", "faction_b_id");



ALTER TABLE ONLY "public"."bilateral_dossiers"
    ADD CONSTRAINT "bilateral_dossiers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_factions"
    ADD CONSTRAINT "campaign_factions_pkey" PRIMARY KEY ("campaign_id", "faction_id");



ALTER TABLE ONLY "public"."campaign_inventory_items"
    ADD CONSTRAINT "campaign_inventory_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_invites"
    ADD CONSTRAINT "campaign_invites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_invites"
    ADD CONSTRAINT "campaign_invites_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."campaign_item_events"
    ADD CONSTRAINT "campaign_item_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_item_requests"
    ADD CONSTRAINT "campaign_item_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_loot"
    ADD CONSTRAINT "campaign_loot_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_members"
    ADD CONSTRAINT "campaign_members_pkey" PRIMARY KEY ("campaign_id", "user_id");



ALTER TABLE ONLY "public"."campaign_money_debts"
    ADD CONSTRAINT "campaign_money_debts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_money_transactions"
    ADD CONSTRAINT "campaign_money_transactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_session_preps"
    ADD CONSTRAINT "campaign_session_preps_pkey" PRIMARY KEY ("campaign_id");



ALTER TABLE ONLY "public"."campaign_settings"
    ADD CONSTRAINT "campaign_settings_pkey" PRIMARY KEY ("campaign_id");



ALTER TABLE ONLY "public"."campaign_slug_words"
    ADD CONSTRAINT "campaign_slug_words_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_slug_words"
    ADD CONSTRAINT "campaign_slug_words_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."contact_player_notes"
    ADD CONSTRAINT "contact_player_notes_pkey" PRIMARY KEY ("contact_id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."faction_relationships"
    ADD CONSTRAINT "faction_relationships_campaign_id_source_faction_id_target__key" UNIQUE ("campaign_id", "source_faction_id", "target_faction_id");



ALTER TABLE ONLY "public"."faction_relationships"
    ADD CONSTRAINT "faction_relationships_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."factions"
    ADD CONSTRAINT "factions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."factions"
    ADD CONSTRAINT "factions_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."factions"
    ADD CONSTRAINT "factions_sort_order_key" UNIQUE ("sort_order");



ALTER TABLE ONLY "public"."journal_entries"
    ADD CONSTRAINT "journal_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."loot_player_publications"
    ADD CONSTRAINT "loot_player_publications_pkey" PRIMARY KEY ("loot_id");



ALTER TABLE ONLY "public"."player_pages"
    ADD CONSTRAINT "player_pages_pkey" PRIMARY KEY ("campaign_id", "user_id");



ALTER TABLE ONLY "public"."player_relationship_notes"
    ADD CONSTRAINT "player_relationship_notes_pkey" PRIMARY KEY ("campaign_id", "author_user_id", "target_user_id");



ALTER TABLE ONLY "public"."quest_entries"
    ADD CONSTRAINT "quest_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."quest_journal_blocks"
    ADD CONSTRAINT "quest_journal_blocks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."quest_journal_documents"
    ADD CONSTRAINT "quest_journal_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."quest_journal_pages"
    ADD CONSTRAINT "quest_journal_pages_pkey" PRIMARY KEY ("campaign_id");



ALTER TABLE ONLY "public"."quest_journal_revisions"
    ADD CONSTRAINT "quest_journal_revisions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reputation_milestones"
    ADD CONSTRAINT "reputation_milestones_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."services"
    ADD CONSTRAINT "services_campaign_id_faction_id_scale_key" UNIQUE ("campaign_id", "faction_id", "scale");



ALTER TABLE ONLY "public"."services"
    ADD CONSTRAINT "services_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."source_references"
    ADD CONSTRAINT "source_references_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "storage"."buckets_analytics"
    ADD CONSTRAINT "buckets_analytics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets"
    ADD CONSTRAINT "buckets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets_vectors"
    ADD CONSTRAINT "buckets_vectors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_name_key" UNIQUE ("name");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."vector_indexes"
    ADD CONSTRAINT "vector_indexes_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "archive_characters_template_idx" ON "public"."archive_characters" USING "btree" ("campaign_id", "template_key") WHERE ("template_key" IS NOT NULL);



CREATE INDEX "archive_characters_volume_idx" ON "public"."archive_characters" USING "btree" ("campaign_id", "first_volume", "sort_order");



CREATE UNIQUE INDEX "archive_places_template_idx" ON "public"."archive_places" USING "btree" ("campaign_id", "template_key") WHERE ("template_key" IS NOT NULL);



CREATE INDEX "archive_places_volume_idx" ON "public"."archive_places" USING "btree" ("campaign_id", "first_volume", "sort_order");



CREATE INDEX "bestiary_entries_campaign_name_idx" ON "public"."bestiary_entries" USING "btree" ("campaign_id", "name");



CREATE INDEX "bestiary_entries_campaign_visibility_order_idx" ON "public"."bestiary_entries" USING "btree" ("campaign_id", "is_visible", "revealed_at", "created_at");



CREATE INDEX "bestiary_events_campaign_date_idx" ON "public"."bestiary_events" USING "btree" ("campaign_id", "created_at" DESC);



CREATE INDEX "campaign_inventory_items_campaign_status_idx" ON "public"."campaign_inventory_items" USING "btree" ("campaign_id", "status", "owner_user_id", "acquired_on" DESC);



CREATE INDEX "campaign_inventory_items_origin_idx" ON "public"."campaign_inventory_items" USING "btree" ("origin_loot_id");



CREATE INDEX "campaign_inventory_items_parent_idx" ON "public"."campaign_inventory_items" USING "btree" ("parent_item_id");



CREATE INDEX "campaign_invites_campaign_created_idx" ON "public"."campaign_invites" USING "btree" ("campaign_id", "created_at" DESC);



CREATE INDEX "campaign_invites_token_idx" ON "public"."campaign_invites" USING "btree" ("token");



CREATE INDEX "campaign_item_events_campaign_date_idx" ON "public"."campaign_item_events" USING "btree" ("campaign_id", "created_at" DESC);



CREATE INDEX "campaign_item_events_item_date_idx" ON "public"."campaign_item_events" USING "btree" ("item_id", "created_at" DESC);



CREATE UNIQUE INDEX "campaign_item_events_reversal_idx" ON "public"."campaign_item_events" USING "btree" ("reversed_event_id") WHERE ("reversed_event_id" IS NOT NULL);



CREATE UNIQUE INDEX "campaign_item_requests_one_pending_per_player_idx" ON "public"."campaign_item_requests" USING "btree" ("item_id", "requester_user_id") WHERE ("status" = 'pending'::"text");



CREATE INDEX "campaign_item_requests_participants_idx" ON "public"."campaign_item_requests" USING "btree" ("campaign_id", "owner_user_id", "requester_user_id", "status", "created_at" DESC);



CREATE UNIQUE INDEX "campaign_loot_reference_idx" ON "public"."campaign_loot" USING "btree" ("campaign_id", "reference_id") WHERE ("reference_id" IS NOT NULL);



CREATE INDEX "campaign_loot_source_idx" ON "public"."campaign_loot" USING "btree" ("campaign_id", "volume", "source_kind", "discovery_status", "sort_order");



CREATE INDEX "campaign_members_user_campaign_idx" ON "public"."campaign_members" USING "btree" ("user_id", "campaign_id");



CREATE INDEX "campaign_money_debts_campaign_status_idx" ON "public"."campaign_money_debts" USING "btree" ("campaign_id", "status", "created_at" DESC);



CREATE INDEX "campaign_money_transactions_campaign_date_idx" ON "public"."campaign_money_transactions" USING "btree" ("campaign_id", "created_at" DESC);



CREATE INDEX "campaign_money_transactions_operation_idx" ON "public"."campaign_money_transactions" USING "btree" ("operation_id");



CREATE UNIQUE INDEX "campaign_money_transactions_reversal_idx" ON "public"."campaign_money_transactions" USING "btree" ("reversed_transaction_id") WHERE ("reversed_transaction_id" IS NOT NULL);



CREATE INDEX "journal_campaign_date_idx" ON "public"."journal_entries" USING "btree" ("campaign_id", "occurred_on" DESC);



CREATE INDEX "journal_campaign_faction_idx" ON "public"."journal_entries" USING "btree" ("campaign_id", "faction_id");



CREATE INDEX "journal_entries_milestone_idx" ON "public"."journal_entries" USING "btree" ("milestone_id") WHERE ("milestone_id" IS NOT NULL);



CREATE INDEX "loot_player_publications_campaign_date_idx" ON "public"."loot_player_publications" USING "btree" ("campaign_id", "published_on");



CREATE UNIQUE INDEX "one_primary_contact_per_faction" ON "public"."contacts" USING "btree" ("campaign_id", "faction_id") WHERE "is_primary";



CREATE INDEX "player_pages_user_idx" ON "public"."player_pages" USING "btree" ("user_id", "campaign_id");



CREATE INDEX "quest_entries_campaign_order_idx" ON "public"."quest_entries" USING "btree" ("campaign_id", "sort_order", "created_at");



CREATE INDEX "quest_journal_blocks_document_order_idx" ON "public"."quest_journal_blocks" USING "btree" ("document_id", "sort_order");



CREATE INDEX "quest_journal_documents_campaign_order_idx" ON "public"."quest_journal_documents" USING "btree" ("campaign_id", "occurred_on" DESC, "sort_order", "created_at" DESC);



CREATE INDEX "quest_journal_revisions_campaign_created_idx" ON "public"."quest_journal_revisions" USING "btree" ("campaign_id", "created_at" DESC);



CREATE INDEX "reputation_milestones_choice_idx" ON "public"."reputation_milestones" USING "btree" ("campaign_id", "choice_group") WHERE ("choice_group" IS NOT NULL);



CREATE INDEX "reputation_milestones_volume_idx" ON "public"."reputation_milestones" USING "btree" ("campaign_id", "volume", "sort_order");



CREATE UNIQUE INDEX "bname" ON "storage"."buckets" USING "btree" ("name");



CREATE UNIQUE INDEX "bucketid_objname" ON "storage"."objects" USING "btree" ("bucket_id", "name");



CREATE UNIQUE INDEX "buckets_analytics_unique_name_idx" ON "storage"."buckets_analytics" USING "btree" ("name") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_multipart_uploads_list" ON "storage"."s3_multipart_uploads" USING "btree" ("bucket_id", "key", "created_at");



CREATE INDEX "idx_objects_bucket_id_name" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C");



CREATE INDEX "idx_objects_bucket_id_name_lower" ON "storage"."objects" USING "btree" ("bucket_id", "lower"("name") COLLATE "C");



CREATE INDEX "name_prefix_search" ON "storage"."objects" USING "btree" ("name" "text_pattern_ops");



CREATE UNIQUE INDEX "vector_indexes_name_bucket_id_idx" ON "storage"."vector_indexes" USING "btree" ("name", "bucket_id");



CREATE OR REPLACE TRIGGER "archive_characters_touch" BEFORE UPDATE ON "public"."archive_characters" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "archive_places_touch" BEFORE UPDATE ON "public"."archive_places" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "bestiary_entries_touch" BEFORE UPDATE ON "public"."bestiary_entries" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "campaign_factions_touch" BEFORE UPDATE ON "public"."campaign_factions" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "campaign_inventory_items_touch" BEFORE UPDATE ON "public"."campaign_inventory_items" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "campaign_loot_touch" BEFORE UPDATE ON "public"."campaign_loot" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "campaign_members_assign_first_owner" AFTER INSERT OR UPDATE OF "role" ON "public"."campaign_members" FOR EACH ROW EXECUTE FUNCTION "public"."assign_first_campaign_owner"();



CREATE OR REPLACE TRIGGER "campaign_money_debts_touch" BEFORE UPDATE ON "public"."campaign_money_debts" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "campaign_session_preps_touch" BEFORE UPDATE ON "public"."campaign_session_preps" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "campaigns_touch" BEFORE UPDATE ON "public"."campaigns" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "contact_player_notes_touch" BEFORE UPDATE ON "public"."contact_player_notes" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "contacts_touch" BEFORE UPDATE ON "public"."contacts" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "journal_touch" BEFORE UPDATE ON "public"."journal_entries" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "player_pages_touch" BEFORE UPDATE ON "public"."player_pages" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "player_relationship_notes_touch" BEFORE UPDATE ON "public"."player_relationship_notes" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "quest_entries_touch" BEFORE UPDATE ON "public"."quest_entries" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "quest_journal_blocks_touch" BEFORE UPDATE ON "public"."quest_journal_blocks" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "quest_journal_documents_touch" BEFORE UPDATE ON "public"."quest_journal_documents" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "quest_journal_pages_revision" AFTER UPDATE OF "content" ON "public"."quest_journal_pages" FOR EACH ROW EXECUTE FUNCTION "public"."capture_quest_journal_revision"();



CREATE OR REPLACE TRIGGER "quest_journal_pages_touch" BEFORE UPDATE ON "public"."quest_journal_pages" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "relationships_touch" BEFORE UPDATE ON "public"."faction_relationships" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "settings_touch" BEFORE UPDATE ON "public"."campaign_settings" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "user_profiles_touch" BEFORE UPDATE ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "enforce_bucket_name_length_trigger" BEFORE INSERT OR UPDATE OF "name" ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."enforce_bucket_name_length"();



CREATE OR REPLACE TRIGGER "protect_buckets_delete" BEFORE DELETE ON "storage"."buckets" FOR EACH STATEMENT EXECUTE FUNCTION "storage"."protect_delete"();



CREATE OR REPLACE TRIGGER "protect_objects_delete" BEFORE DELETE ON "storage"."objects" FOR EACH STATEMENT EXECUTE FUNCTION "storage"."protect_delete"();



CREATE OR REPLACE TRIGGER "update_objects_updated_at" BEFORE UPDATE ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."update_updated_at_column"();



ALTER TABLE ONLY "public"."archive_characters"
    ADD CONSTRAINT "archive_characters_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."archive_characters"
    ADD CONSTRAINT "archive_characters_template_key_fkey" FOREIGN KEY ("template_key") REFERENCES "public"."archive_character_templates"("template_key") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."archive_places"
    ADD CONSTRAINT "archive_places_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."archive_places"
    ADD CONSTRAINT "archive_places_template_key_fkey" FOREIGN KEY ("template_key") REFERENCES "public"."archive_place_templates"("template_key") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bestiary_entries"
    ADD CONSTRAINT "bestiary_entries_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bestiary_entries"
    ADD CONSTRAINT "bestiary_entries_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bestiary_events"
    ADD CONSTRAINT "bestiary_events_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bestiary_events"
    ADD CONSTRAINT "bestiary_events_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bilateral_dossiers"
    ADD CONSTRAINT "bilateral_dossiers_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bilateral_dossiers"
    ADD CONSTRAINT "bilateral_dossiers_faction_a_id_fkey" FOREIGN KEY ("faction_a_id") REFERENCES "public"."factions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bilateral_dossiers"
    ADD CONSTRAINT "bilateral_dossiers_faction_b_id_fkey" FOREIGN KEY ("faction_b_id") REFERENCES "public"."factions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_factions"
    ADD CONSTRAINT "campaign_factions_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_factions"
    ADD CONSTRAINT "campaign_factions_faction_id_fkey" FOREIGN KEY ("faction_id") REFERENCES "public"."factions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_inventory_items"
    ADD CONSTRAINT "campaign_inventory_items_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_inventory_items"
    ADD CONSTRAINT "campaign_inventory_items_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_inventory_items"
    ADD CONSTRAINT "campaign_inventory_items_origin_loot_id_fkey" FOREIGN KEY ("origin_loot_id") REFERENCES "public"."campaign_loot"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_inventory_items"
    ADD CONSTRAINT "campaign_inventory_items_owner_user_id_fkey" FOREIGN KEY ("owner_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_inventory_items"
    ADD CONSTRAINT "campaign_inventory_items_parent_item_id_fkey" FOREIGN KEY ("parent_item_id") REFERENCES "public"."campaign_inventory_items"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_invites"
    ADD CONSTRAINT "campaign_invites_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_invites"
    ADD CONSTRAINT "campaign_invites_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_item_events"
    ADD CONSTRAINT "campaign_item_events_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_item_events"
    ADD CONSTRAINT "campaign_item_events_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_item_events"
    ADD CONSTRAINT "campaign_item_events_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."campaign_inventory_items"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_item_events"
    ADD CONSTRAINT "campaign_item_events_next_owner_user_id_fkey" FOREIGN KEY ("next_owner_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_item_events"
    ADD CONSTRAINT "campaign_item_events_previous_owner_user_id_fkey" FOREIGN KEY ("previous_owner_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_item_events"
    ADD CONSTRAINT "campaign_item_events_related_item_id_fkey" FOREIGN KEY ("related_item_id") REFERENCES "public"."campaign_inventory_items"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_item_events"
    ADD CONSTRAINT "campaign_item_events_reversed_event_id_fkey" FOREIGN KEY ("reversed_event_id") REFERENCES "public"."campaign_item_events"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."campaign_item_requests"
    ADD CONSTRAINT "campaign_item_requests_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_item_requests"
    ADD CONSTRAINT "campaign_item_requests_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."campaign_inventory_items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_item_requests"
    ADD CONSTRAINT "campaign_item_requests_owner_user_id_fkey" FOREIGN KEY ("owner_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_item_requests"
    ADD CONSTRAINT "campaign_item_requests_requester_user_id_fkey" FOREIGN KEY ("requester_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_loot"
    ADD CONSTRAINT "campaign_loot_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_members"
    ADD CONSTRAINT "campaign_members_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_members"
    ADD CONSTRAINT "campaign_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_money_debts"
    ADD CONSTRAINT "campaign_money_debts_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_money_debts"
    ADD CONSTRAINT "campaign_money_debts_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_money_debts"
    ADD CONSTRAINT "campaign_money_debts_creditor_user_id_fkey" FOREIGN KEY ("creditor_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_money_debts"
    ADD CONSTRAINT "campaign_money_debts_debtor_user_id_fkey" FOREIGN KEY ("debtor_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_money_transactions"
    ADD CONSTRAINT "campaign_money_transactions_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_money_transactions"
    ADD CONSTRAINT "campaign_money_transactions_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_money_transactions"
    ADD CONSTRAINT "campaign_money_transactions_destination_user_id_fkey" FOREIGN KEY ("destination_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_money_transactions"
    ADD CONSTRAINT "campaign_money_transactions_related_item_id_fkey" FOREIGN KEY ("related_item_id") REFERENCES "public"."campaign_inventory_items"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_money_transactions"
    ADD CONSTRAINT "campaign_money_transactions_reversed_transaction_id_fkey" FOREIGN KEY ("reversed_transaction_id") REFERENCES "public"."campaign_money_transactions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."campaign_money_transactions"
    ADD CONSTRAINT "campaign_money_transactions_source_user_id_fkey" FOREIGN KEY ("source_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_session_preps"
    ADD CONSTRAINT "campaign_session_preps_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_settings"
    ADD CONSTRAINT "campaign_settings_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_owner_user_id_fkey" FOREIGN KEY ("owner_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_player_notes"
    ADD CONSTRAINT "contact_player_notes_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_player_notes"
    ADD CONSTRAINT "contact_player_notes_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_faction_id_fkey" FOREIGN KEY ("faction_id") REFERENCES "public"."factions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."faction_relationships"
    ADD CONSTRAINT "faction_relationships_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."faction_relationships"
    ADD CONSTRAINT "faction_relationships_source_faction_id_fkey" FOREIGN KEY ("source_faction_id") REFERENCES "public"."factions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."faction_relationships"
    ADD CONSTRAINT "faction_relationships_target_faction_id_fkey" FOREIGN KEY ("target_faction_id") REFERENCES "public"."factions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."journal_entries"
    ADD CONSTRAINT "journal_entries_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."journal_entries"
    ADD CONSTRAINT "journal_entries_faction_id_fkey" FOREIGN KEY ("faction_id") REFERENCES "public"."factions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."journal_entries"
    ADD CONSTRAINT "journal_entries_milestone_id_fkey" FOREIGN KEY ("milestone_id") REFERENCES "public"."reputation_milestones"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."loot_player_publications"
    ADD CONSTRAINT "loot_player_publications_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."loot_player_publications"
    ADD CONSTRAINT "loot_player_publications_loot_id_fkey" FOREIGN KEY ("loot_id") REFERENCES "public"."campaign_loot"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."loot_player_publications"
    ADD CONSTRAINT "loot_player_publications_owner_user_id_fkey" FOREIGN KEY ("owner_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."player_pages"
    ADD CONSTRAINT "player_pages_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."player_pages"
    ADD CONSTRAINT "player_pages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."player_relationship_notes"
    ADD CONSTRAINT "player_relationship_notes_campaign_id_author_user_id_fkey" FOREIGN KEY ("campaign_id", "author_user_id") REFERENCES "public"."player_pages"("campaign_id", "user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."player_relationship_notes"
    ADD CONSTRAINT "player_relationship_notes_campaign_id_target_user_id_fkey" FOREIGN KEY ("campaign_id", "target_user_id") REFERENCES "public"."player_pages"("campaign_id", "user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quest_entries"
    ADD CONSTRAINT "quest_entries_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quest_journal_blocks"
    ADD CONSTRAINT "quest_journal_blocks_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quest_journal_blocks"
    ADD CONSTRAINT "quest_journal_blocks_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "public"."quest_journal_documents"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quest_journal_documents"
    ADD CONSTRAINT "quest_journal_documents_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quest_journal_pages"
    ADD CONSTRAINT "quest_journal_pages_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quest_journal_revisions"
    ADD CONSTRAINT "quest_journal_revisions_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reputation_milestones"
    ADD CONSTRAINT "reputation_milestones_beneficiary_faction_id_fkey" FOREIGN KEY ("beneficiary_faction_id") REFERENCES "public"."factions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reputation_milestones"
    ADD CONSTRAINT "reputation_milestones_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reputation_milestones"
    ADD CONSTRAINT "reputation_milestones_excluded_by_milestone_id_fkey" FOREIGN KEY ("excluded_by_milestone_id") REFERENCES "public"."reputation_milestones"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reputation_milestones"
    ADD CONSTRAINT "reputation_milestones_harmed_faction_id_fkey" FOREIGN KEY ("harmed_faction_id") REFERENCES "public"."factions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."services"
    ADD CONSTRAINT "services_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."services"
    ADD CONSTRAINT "services_faction_id_fkey" FOREIGN KEY ("faction_id") REFERENCES "public"."factions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."source_references"
    ADD CONSTRAINT "source_references_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_upload_id_fkey" FOREIGN KEY ("upload_id") REFERENCES "storage"."s3_multipart_uploads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."vector_indexes"
    ADD CONSTRAINT "vector_indexes_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets_vectors"("id");



ALTER TABLE "public"."archive_character_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."archive_characters" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "archive_characters_gm_all" ON "public"."archive_characters" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."archive_place_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."archive_places" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "archive_places_gm_all" ON "public"."archive_places" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."bestiary_entries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bestiary_entries_member_read" ON "public"."bestiary_entries" FOR SELECT TO "authenticated" USING (("public"."is_campaign_member"("campaign_id") AND ("is_visible" OR "public"."is_campaign_gm"("campaign_id"))));



ALTER TABLE "public"."bestiary_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bestiary_events_gm_read" ON "public"."bestiary_events" FOR SELECT TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."bilateral_dossiers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_factions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaign_factions_gm_all" ON "public"."campaign_factions" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."campaign_inventory_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_invites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_item_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_item_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_loot" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaign_loot_gm_all" ON "public"."campaign_loot" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."campaign_members" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_money_debts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_money_transactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_session_preps" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaign_session_preps_gm_all" ON "public"."campaign_session_preps" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."campaign_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_slug_words" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaigns" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaigns_member_read" ON "public"."campaigns" FOR SELECT TO "authenticated" USING ("public"."is_campaign_member"("id"));



ALTER TABLE "public"."contact_player_notes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "contact_player_notes_gm_read" ON "public"."contact_player_notes" FOR SELECT TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id"));



CREATE POLICY "contact_player_notes_member_read" ON "public"."contact_player_notes" FOR SELECT TO "authenticated" USING ("public"."is_campaign_member"("campaign_id"));



ALTER TABLE "public"."contacts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "contacts_gm_all" ON "public"."contacts" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



CREATE POLICY "dossiers_gm_all" ON "public"."bilateral_dossiers" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."faction_relationships" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."factions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "factions_authenticated_read" ON "public"."factions" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."journal_entries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "journal_gm_all" ON "public"."journal_entries" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."loot_player_publications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "members_gm_read" ON "public"."campaign_members" FOR SELECT TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id"));



CREATE POLICY "members_gm_remove_players" ON "public"."campaign_members" FOR DELETE TO "authenticated" USING (("public"."is_campaign_gm"("campaign_id") AND ("role" = 'player'::"text")));



CREATE POLICY "members_self_read" ON "public"."campaign_members" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "milestones_gm_all" ON "public"."reputation_milestones" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."player_pages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "player_pages_gm_read" ON "public"."player_pages" FOR SELECT TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id"));



CREATE POLICY "player_pages_owner_read" ON "public"."player_pages" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."campaign_members" "member"
  WHERE (("member"."campaign_id" = "player_pages"."campaign_id") AND ("member"."user_id" = "auth"."uid"()) AND ("member"."role" = 'player'::"text"))))));



CREATE POLICY "player_pages_owner_update" ON "public"."player_pages" FOR UPDATE TO "authenticated" USING ((("user_id" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."campaign_members" "member"
  WHERE (("member"."campaign_id" = "player_pages"."campaign_id") AND ("member"."user_id" = "auth"."uid"()) AND ("member"."role" = 'player'::"text")))))) WITH CHECK ((("user_id" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."campaign_members" "member"
  WHERE (("member"."campaign_id" = "player_pages"."campaign_id") AND ("member"."user_id" = "auth"."uid"()) AND ("member"."role" = 'player'::"text"))))));



ALTER TABLE "public"."player_relationship_notes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "player_relationship_notes_owner_all" ON "public"."player_relationship_notes" TO "authenticated" USING (("author_user_id" = "auth"."uid"())) WITH CHECK (("author_user_id" = "auth"."uid"()));



ALTER TABLE "public"."quest_entries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "quest_entries_public_manage" ON "public"."quest_entries" TO "authenticated", "anon" USING ("public"."is_public_campaign"("campaign_id")) WITH CHECK ("public"."is_public_campaign"("campaign_id"));



ALTER TABLE "public"."quest_journal_blocks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "quest_journal_blocks_public_manage" ON "public"."quest_journal_blocks" TO "authenticated", "anon" USING ("public"."is_public_campaign"("campaign_id")) WITH CHECK ("public"."is_public_campaign"("campaign_id"));



ALTER TABLE "public"."quest_journal_documents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "quest_journal_documents_public_manage" ON "public"."quest_journal_documents" TO "authenticated", "anon" USING ("public"."is_public_campaign"("campaign_id")) WITH CHECK ("public"."is_public_campaign"("campaign_id"));



ALTER TABLE "public"."quest_journal_pages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "quest_journal_pages_public_manage" ON "public"."quest_journal_pages" TO "authenticated", "anon" USING ("public"."is_public_campaign"("campaign_id")) WITH CHECK ("public"."is_public_campaign"("campaign_id"));



ALTER TABLE "public"."quest_journal_revisions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "quest_journal_revisions_gm_read" ON "public"."quest_journal_revisions" FOR SELECT TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id"));



CREATE POLICY "quest_journal_revisions_public_read" ON "public"."quest_journal_revisions" FOR SELECT TO "authenticated", "anon" USING ("public"."is_public_campaign"("campaign_id"));



CREATE POLICY "relationships_gm_all" ON "public"."faction_relationships" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."reputation_milestones" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."services" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "services_gm_all" ON "public"."services" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



CREATE POLICY "settings_gm_all" ON "public"."campaign_settings" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."source_references" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sources_gm_all" ON "public"."source_references" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bestiary_images_member_delete" ON "storage"."objects" FOR DELETE TO "authenticated" USING ((("bucket_id" = 'bestiary-images'::"text") AND "public"."is_campaign_member_storage_path"("name")));



CREATE POLICY "bestiary_images_member_insert" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK ((("bucket_id" = 'bestiary-images'::"text") AND "public"."is_campaign_member_storage_path"("name")));



CREATE POLICY "bestiary_images_member_update" ON "storage"."objects" FOR UPDATE TO "authenticated" USING ((("bucket_id" = 'bestiary-images'::"text") AND "public"."is_campaign_member_storage_path"("name"))) WITH CHECK ((("bucket_id" = 'bestiary-images'::"text") AND "public"."is_campaign_member_storage_path"("name")));



CREATE POLICY "bestiary_images_public_read" ON "storage"."objects" FOR SELECT TO "authenticated", "anon" USING (("bucket_id" = 'bestiary-images'::"text"));



ALTER TABLE "storage"."buckets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_analytics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_vectors" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "contact_portraits_gm_delete" ON "storage"."objects" FOR DELETE TO "authenticated" USING ((("bucket_id" = 'contact-portraits'::"text") AND "public"."is_gm_contact_portrait_path"("name")));



CREATE POLICY "contact_portraits_gm_insert" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK ((("bucket_id" = 'contact-portraits'::"text") AND "public"."is_gm_contact_portrait_path"("name")));



CREATE POLICY "contact_portraits_gm_update" ON "storage"."objects" FOR UPDATE TO "authenticated" USING ((("bucket_id" = 'contact-portraits'::"text") AND "public"."is_gm_contact_portrait_path"("name"))) WITH CHECK ((("bucket_id" = 'contact-portraits'::"text") AND "public"."is_gm_contact_portrait_path"("name")));



CREATE POLICY "contact_portraits_public_read" ON "storage"."objects" FOR SELECT TO "authenticated", "anon" USING (("bucket_id" = 'contact-portraits'::"text"));



ALTER TABLE "storage"."migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."objects" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "player_character_images_owner_delete" ON "storage"."objects" FOR DELETE TO "authenticated" USING ((("bucket_id" = 'player-character-images'::"text") AND "public"."is_own_player_character_image_path"("name")));



CREATE POLICY "player_character_images_owner_insert" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK ((("bucket_id" = 'player-character-images'::"text") AND "public"."is_own_player_character_image_path"("name")));



CREATE POLICY "player_character_images_owner_update" ON "storage"."objects" FOR UPDATE TO "authenticated" USING ((("bucket_id" = 'player-character-images'::"text") AND "public"."is_own_player_character_image_path"("name"))) WITH CHECK ((("bucket_id" = 'player-character-images'::"text") AND "public"."is_own_player_character_image_path"("name")));



CREATE POLICY "player_character_images_public_read" ON "storage"."objects" FOR SELECT TO "authenticated", "anon" USING (("bucket_id" = 'player-character-images'::"text"));



CREATE POLICY "quest_journal_images_member_delete" ON "storage"."objects" FOR DELETE TO "authenticated" USING ((("bucket_id" = 'quest-journal-images'::"text") AND "public"."is_campaign_member_storage_path"("name")));



CREATE POLICY "quest_journal_images_member_insert" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK ((("bucket_id" = 'quest-journal-images'::"text") AND "public"."is_campaign_member_storage_path"("name")));



CREATE POLICY "quest_journal_images_member_update" ON "storage"."objects" FOR UPDATE TO "authenticated" USING ((("bucket_id" = 'quest-journal-images'::"text") AND "public"."is_campaign_member_storage_path"("name"))) WITH CHECK ((("bucket_id" = 'quest-journal-images'::"text") AND "public"."is_campaign_member_storage_path"("name")));



CREATE POLICY "quest_journal_images_public_read" ON "storage"."objects" FOR SELECT TO "authenticated", "anon" USING (("bucket_id" = 'quest-journal-images'::"text"));



ALTER TABLE "storage"."s3_multipart_uploads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads_parts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."vector_indexes" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT USAGE ON SCHEMA "storage" TO "postgres" WITH GRANT OPTION;
GRANT USAGE ON SCHEMA "storage" TO "anon";
GRANT USAGE ON SCHEMA "storage" TO "authenticated";
GRANT USAGE ON SCHEMA "storage" TO "service_role";
GRANT ALL ON SCHEMA "storage" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON SCHEMA "storage" TO "dashboard_user";



REVOKE ALL ON FUNCTION "public"."accept_campaign_invitation"("p_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."accept_campaign_invitation"("p_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_campaign_invitation"("p_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_campaign_invitation"("p_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."apply_reputation_milestone"("milestone_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."apply_reputation_milestone"("milestone_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."apply_reputation_milestone"("milestone_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_reputation_milestone"("milestone_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."assign_campaign_item"("p_item_id" "uuid", "p_target_user_id" "uuid", "p_comment" "text", "p_quantity" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assign_campaign_item"("p_item_id" "uuid", "p_target_user_id" "uuid", "p_comment" "text", "p_quantity" numeric) TO "service_role";
GRANT ALL ON FUNCTION "public"."assign_campaign_item"("p_item_id" "uuid", "p_target_user_id" "uuid", "p_comment" "text", "p_quantity" numeric) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."assign_first_campaign_owner"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assign_first_campaign_owner"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."batch_update_campaign_items"("p_item_ids" "uuid"[], "p_action" "text", "p_target_user_id" "uuid", "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."batch_update_campaign_items"("p_item_ids" "uuid"[], "p_action" "text", "p_target_user_id" "uuid", "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."batch_update_campaign_items"("p_item_ids" "uuid"[], "p_action" "text", "p_target_user_id" "uuid", "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."can_control_campaign_item"("p_item_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_control_campaign_item"("p_item_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_campaign_item_event"("p_event_id" "uuid", "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_campaign_item_event"("p_event_id" "uuid", "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."cancel_campaign_item_event"("p_event_id" "uuid", "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."cancel_campaign_item_request"("p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_campaign_item_request"("p_request_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."cancel_campaign_item_request"("p_request_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."cancel_campaign_money_debt"("p_debt_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_campaign_money_debt"("p_debt_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."cancel_campaign_money_debt"("p_debt_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."cancel_campaign_money_transaction"("p_transaction_id" "uuid", "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_campaign_money_transaction"("p_transaction_id" "uuid", "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."cancel_campaign_money_transaction"("p_transaction_id" "uuid", "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."capture_quest_journal_revision"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."capture_quest_journal_revision"() TO "anon";
GRANT ALL ON FUNCTION "public"."capture_quest_journal_revision"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."capture_quest_journal_revision"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_campaign"("p_name" "text", "p_description" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_campaign"("p_name" "text", "p_description" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."create_campaign"("p_name" "text", "p_description" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."create_campaign_invite"("p_campaign_id" "uuid", "p_expires_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_campaign_invite"("p_campaign_id" "uuid", "p_expires_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."create_campaign_invite"("p_campaign_id" "uuid", "p_expires_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_campaign_invite"("p_campaign_id" "uuid", "p_expires_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_campaign_money_debt"("p_campaign_id" "uuid", "p_debtor_user_id" "uuid", "p_creditor_user_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_campaign_money_debt"("p_campaign_id" "uuid", "p_debtor_user_id" "uuid", "p_creditor_user_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."create_campaign_money_debt"("p_campaign_id" "uuid", "p_debtor_user_id" "uuid", "p_creditor_user_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."create_manual_campaign_item"("p_campaign_id" "uuid", "p_name" "text", "p_quantity" numeric, "p_unit_value_cp" bigint, "p_owner_user_id" "uuid", "p_aon_legacy_name" "text", "p_aon_legacy_url" "text", "p_comment" "text", "p_counts_as_gain" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_manual_campaign_item"("p_campaign_id" "uuid", "p_name" "text", "p_quantity" numeric, "p_unit_value_cp" bigint, "p_owner_user_id" "uuid", "p_aon_legacy_name" "text", "p_aon_legacy_url" "text", "p_comment" "text", "p_counts_as_gain" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."create_manual_campaign_item"("p_campaign_id" "uuid", "p_name" "text", "p_quantity" numeric, "p_unit_value_cp" bigint, "p_owner_user_id" "uuid", "p_aon_legacy_name" "text", "p_aon_legacy_url" "text", "p_comment" "text", "p_counts_as_gain" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."delete_bestiary_entry"("p_entry_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_bestiary_entry"("p_entry_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."delete_bestiary_entry"("p_entry_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."delete_owned_campaign"("p_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_owned_campaign"("p_campaign_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."delete_owned_campaign"("p_campaign_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."dismantle_campaign_item"("p_item_id" "uuid", "p_outputs" "jsonb", "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."dismantle_campaign_item"("p_item_id" "uuid", "p_outputs" "jsonb", "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."dismantle_campaign_item"("p_item_id" "uuid", "p_outputs" "jsonb", "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."generate_available_campaign_slug"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."generate_available_campaign_slug"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_campaign_capacity"("p_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_campaign_capacity"("p_campaign_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_campaign_capacity"("p_campaign_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_campaign_invitation"("p_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_campaign_invitation"("p_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_campaign_invitation"("p_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_campaign_invitation"("p_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_player_page"("p_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_player_page"("p_campaign_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_my_player_page"("p_campaign_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_my_profile"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_profile"() TO "service_role";
GRANT ALL ON FUNCTION "public"."get_my_profile"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_active_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_active_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_campaign_gm"("target_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_campaign_gm"("target_campaign_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_campaign_gm"("target_campaign_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_campaign_gm"("target_campaign_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_campaign_member"("target_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_campaign_member"("target_campaign_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_campaign_member"("target_campaign_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_campaign_member"("target_campaign_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_campaign_member_storage_path"("object_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_campaign_member_storage_path"("object_name" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."is_campaign_member_storage_path"("object_name" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_gm_contact_portrait_path"("object_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_gm_contact_portrait_path"("object_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_gm_contact_portrait_path"("object_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_gm_contact_portrait_path"("object_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_own_player_character_image_path"("object_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_own_player_character_image_path"("object_name" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."is_own_player_character_image_path"("object_name" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_public_bestiary_path"("object_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_public_bestiary_path"("object_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_public_bestiary_path"("object_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_public_bestiary_path"("object_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_public_campaign"("target_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_public_campaign"("target_campaign_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_public_campaign"("target_campaign_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_public_campaign"("target_campaign_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_public_quest_journal_image_path"("object_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_public_quest_journal_image_path"("object_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_public_quest_journal_image_path"("object_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_public_quest_journal_image_path"("object_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."leave_campaign"("p_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."leave_campaign"("p_campaign_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."leave_campaign"("p_campaign_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_campaign_bestiary"("p_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_campaign_bestiary"("p_campaign_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."list_campaign_bestiary"("p_campaign_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_campaign_invites"("p_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_campaign_invites"("p_campaign_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."list_campaign_invites"("p_campaign_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_campaign_invites"("p_campaign_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."list_campaign_members"("p_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_campaign_members"("p_campaign_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."list_campaign_members"("p_campaign_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_campaign_player_pages"("p_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_campaign_player_pages"("p_campaign_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."list_campaign_player_pages"("p_campaign_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_campaign_players"("p_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_campaign_players"("p_campaign_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."list_campaign_players"("p_campaign_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_my_campaigns"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_my_campaigns"() TO "service_role";
GRANT ALL ON FUNCTION "public"."list_my_campaigns"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_my_player_relationship_notes"("p_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_my_player_relationship_notes"("p_campaign_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."list_my_player_relationship_notes"("p_campaign_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."merge_campaign_items"("p_target_item_id" "uuid", "p_source_item_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."merge_campaign_items"("p_target_item_id" "uuid", "p_source_item_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."merge_campaign_items"("p_target_item_id" "uuid", "p_source_item_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."pay_campaign_money_debt"("p_debt_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."pay_campaign_money_debt"("p_debt_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."pay_campaign_money_debt"("p_debt_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."purchase_campaign_item"("p_campaign_id" "uuid", "p_name" "text", "p_quantity" numeric, "p_price_cp" bigint, "p_personal_amount_cp" bigint, "p_common_amount_cp" bigint, "p_owner_user_id" "uuid", "p_unit_value_cp" bigint, "p_aon_legacy_name" "text", "p_aon_legacy_url" "text", "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."purchase_campaign_item"("p_campaign_id" "uuid", "p_name" "text", "p_quantity" numeric, "p_price_cp" bigint, "p_personal_amount_cp" bigint, "p_common_amount_cp" bigint, "p_owner_user_id" "uuid", "p_unit_value_cp" bigint, "p_aon_legacy_name" "text", "p_aon_legacy_url" "text", "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."purchase_campaign_item"("p_campaign_id" "uuid", "p_name" "text", "p_quantity" numeric, "p_price_cp" bigint, "p_personal_amount_cp" bigint, "p_common_amount_cp" bigint, "p_owner_user_id" "uuid", "p_unit_value_cp" bigint, "p_aon_legacy_name" "text", "p_aon_legacy_url" "text", "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."record_common_income"("p_campaign_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_common_income"("p_campaign_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."record_common_income"("p_campaign_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."record_personal_money"("p_campaign_id" "uuid", "p_kind" "text", "p_amount_cp" bigint, "p_user_id" "uuid", "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_personal_money"("p_campaign_id" "uuid", "p_kind" "text", "p_amount_cp" bigint, "p_user_id" "uuid", "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."record_personal_money"("p_campaign_id" "uuid", "p_kind" "text", "p_amount_cp" bigint, "p_user_id" "uuid", "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."remove_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."remove_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."remove_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."request_campaign_item"("p_item_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."request_campaign_item"("p_item_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."request_campaign_item"("p_item_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."reset_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reset_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."reset_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."resolve_campaign_item_request"("p_request_id" "uuid", "p_accept" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_campaign_item_request"("p_request_id" "uuid", "p_accept" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."resolve_campaign_item_request"("p_request_id" "uuid", "p_accept" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."resolve_reputation_milestone"("p_milestone_id" "uuid", "p_outcome" "text", "p_note" "text", "p_effects" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_reputation_milestone"("p_milestone_id" "uuid", "p_outcome" "text", "p_note" "text", "p_effects" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."resolve_reputation_milestone"("p_milestone_id" "uuid", "p_outcome" "text", "p_note" "text", "p_effects" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."return_campaign_item_to_common"("p_item_id" "uuid", "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."return_campaign_item_to_common"("p_item_id" "uuid", "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."return_campaign_item_to_common"("p_item_id" "uuid", "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."revoke_campaign_invite"("p_invite_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."revoke_campaign_invite"("p_invite_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."revoke_campaign_invite"("p_invite_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."save_bestiary_entry"("p_id" "uuid", "p_campaign_id" "uuid", "p_name" "text", "p_resistances" "text", "p_weaknesses" "text", "p_notes" "text", "p_image_path" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_bestiary_entry"("p_id" "uuid", "p_campaign_id" "uuid", "p_name" "text", "p_resistances" "text", "p_weaknesses" "text", "p_notes" "text", "p_image_path" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."save_bestiary_entry"("p_id" "uuid", "p_campaign_id" "uuid", "p_name" "text", "p_resistances" "text", "p_weaknesses" "text", "p_notes" "text", "p_image_path" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."save_player_contact_notes"("target_contact_id" "uuid", "next_character_notes" "text", "next_debt_notes" "text", "next_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_player_contact_notes"("target_contact_id" "uuid", "next_character_notes" "text", "next_debt_notes" "text", "next_notes" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."save_player_contact_notes"("target_contact_id" "uuid", "next_character_notes" "text", "next_debt_notes" "text", "next_notes" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."save_quest_journal_page"("target_campaign_id" "uuid", "expected_revision" integer, "next_content" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_quest_journal_page"("target_campaign_id" "uuid", "expected_revision" integer, "next_content" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."save_quest_journal_page"("target_campaign_id" "uuid", "expected_revision" integer, "next_content" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."seed_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."seed_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."sell_campaign_item"("p_item_id" "uuid", "p_quantity" numeric, "p_amount_cp" bigint, "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sell_campaign_item"("p_item_id" "uuid", "p_quantity" numeric, "p_amount_cp" bigint, "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."sell_campaign_item"("p_item_id" "uuid", "p_quantity" numeric, "p_amount_cp" bigint, "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_bestiary_entry_visibility"("p_entry_id" "uuid", "p_visible" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_bestiary_entry_visibility"("p_entry_id" "uuid", "p_visible" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."set_bestiary_entry_visibility"("p_entry_id" "uuid", "p_visible" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_campaign_item_terminal"("p_item_id" "uuid", "p_status" "text", "p_quantity" numeric, "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_campaign_item_terminal"("p_item_id" "uuid", "p_status" "text", "p_quantity" numeric, "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."set_campaign_item_terminal"("p_item_id" "uuid", "p_status" "text", "p_quantity" numeric, "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_loot_player_visibility"("p_loot_id" "uuid", "p_visible" boolean, "p_published_on" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_loot_player_visibility"("p_loot_id" "uuid", "p_visible" boolean, "p_published_on" "date") TO "service_role";
GRANT ALL ON FUNCTION "public"."set_loot_player_visibility"("p_loot_id" "uuid", "p_visible" boolean, "p_published_on" "date") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_player_loot_assignment"("p_loot_id" "uuid", "p_owner_user_id" "uuid", "p_lifecycle_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_player_loot_assignment"("p_loot_id" "uuid", "p_owner_user_id" "uuid", "p_lifecycle_status" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."set_player_loot_assignment"("p_loot_id" "uuid", "p_owner_user_id" "uuid", "p_lifecycle_status" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_player_loot_published_on"("p_loot_id" "uuid", "p_published_on" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_player_loot_published_on"("p_loot_id" "uuid", "p_published_on" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_player_loot_published_on"("p_loot_id" "uuid", "p_published_on" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."split_campaign_item"("p_item_id" "uuid", "p_quantity" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."split_campaign_item"("p_item_id" "uuid", "p_quantity" numeric) TO "service_role";
GRANT ALL ON FUNCTION "public"."split_campaign_item"("p_item_id" "uuid", "p_quantity" numeric) TO "authenticated";



GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."transfer_campaign_money"("p_campaign_id" "uuid", "p_source_user_id" "uuid", "p_destination_user_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."transfer_campaign_money"("p_campaign_id" "uuid", "p_source_user_id" "uuid", "p_destination_user_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."transfer_campaign_money"("p_campaign_id" "uuid", "p_source_user_id" "uuid", "p_destination_user_id" "uuid", "p_amount_cp" bigint, "p_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."transfer_departing_player_assets"("p_campaign_id" "uuid", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."transfer_departing_player_assets"("p_campaign_id" "uuid", "p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_campaign_capacity"("p_campaign_id" "uuid", "p_max_participants" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_campaign_capacity"("p_campaign_id" "uuid", "p_max_participants" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."update_campaign_capacity"("p_campaign_id" "uuid", "p_max_participants" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text", "p_image_x" numeric, "p_image_y" numeric, "p_image_zoom" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text", "p_image_x" numeric, "p_image_y" numeric, "p_image_zoom" numeric) TO "service_role";
GRANT ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text", "p_image_x" numeric, "p_image_y" numeric, "p_image_zoom" numeric) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_title" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text", "p_image_x" numeric, "p_image_y" numeric, "p_image_zoom" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_title" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text", "p_image_x" numeric, "p_image_y" numeric, "p_image_zoom" numeric) TO "service_role";
GRANT ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_title" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text", "p_image_x" numeric, "p_image_y" numeric, "p_image_zoom" numeric) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_my_player_relationship_note"("p_campaign_id" "uuid", "p_target_user_id" "uuid", "p_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_my_player_relationship_note"("p_campaign_id" "uuid", "p_target_user_id" "uuid", "p_notes" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."update_my_player_relationship_note"("p_campaign_id" "uuid", "p_target_user_id" "uuid", "p_notes" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_my_profile"("p_display_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_my_profile"("p_display_name" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."update_my_profile"("p_display_name" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_owned_campaign"("p_campaign_id" "uuid", "p_name" "text", "p_description" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_owned_campaign"("p_campaign_id" "uuid", "p_name" "text", "p_description" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."update_owned_campaign"("p_campaign_id" "uuid", "p_name" "text", "p_description" "text") TO "authenticated";



GRANT ALL ON TABLE "public"."archive_character_templates" TO "service_role";



GRANT ALL ON TABLE "public"."archive_characters" TO "anon";
GRANT ALL ON TABLE "public"."archive_characters" TO "authenticated";
GRANT ALL ON TABLE "public"."archive_characters" TO "service_role";



GRANT ALL ON TABLE "public"."archive_place_templates" TO "service_role";



GRANT ALL ON TABLE "public"."archive_places" TO "anon";
GRANT ALL ON TABLE "public"."archive_places" TO "authenticated";
GRANT ALL ON TABLE "public"."archive_places" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."bestiary_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."bestiary_entries" TO "service_role";



GRANT ALL ON TABLE "public"."bestiary_events" TO "service_role";
GRANT SELECT ON TABLE "public"."bestiary_events" TO "authenticated";



GRANT ALL ON TABLE "public"."bilateral_dossiers" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."bilateral_dossiers" TO "authenticated";



GRANT ALL ON TABLE "public"."campaign_factions" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."campaign_factions" TO "authenticated";



GRANT ALL ON TABLE "public"."campaign_inventory_items" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_invites" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_item_events" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_item_requests" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_loot" TO "anon";
GRANT ALL ON TABLE "public"."campaign_loot" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_loot" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_members" TO "service_role";
GRANT SELECT ON TABLE "public"."campaign_members" TO "authenticated";



GRANT ALL ON TABLE "public"."campaign_money_debts" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_money_transactions" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_session_preps" TO "anon";
GRANT ALL ON TABLE "public"."campaign_session_preps" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_session_preps" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_settings" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."campaign_settings" TO "authenticated";



GRANT ALL ON TABLE "public"."campaign_slug_words" TO "service_role";



GRANT ALL ON TABLE "public"."campaigns" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."campaigns" TO "authenticated";



GRANT ALL ON TABLE "public"."contact_player_notes" TO "authenticated";
GRANT ALL ON TABLE "public"."contact_player_notes" TO "service_role";



GRANT ALL ON TABLE "public"."contacts" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."contacts" TO "authenticated";



GRANT ALL ON TABLE "public"."faction_relationships" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."faction_relationships" TO "authenticated";



GRANT ALL ON TABLE "public"."factions" TO "service_role";
GRANT SELECT ON TABLE "public"."factions" TO "authenticated";



GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."gm_bestiary_history" TO "service_role";
GRANT SELECT ON TABLE "public"."gm_bestiary_history" TO "authenticated";



GRANT ALL ON TABLE "public"."gm_bilateral_dossiers" TO "service_role";
GRANT SELECT ON TABLE "public"."gm_bilateral_dossiers" TO "authenticated";



GRANT ALL ON TABLE "public"."gm_contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."gm_contacts" TO "service_role";



GRANT ALL ON TABLE "public"."journal_entries" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."journal_entries" TO "authenticated";



GRANT ALL ON TABLE "public"."gm_faction_overview" TO "authenticated";
GRANT ALL ON TABLE "public"."gm_faction_overview" TO "service_role";



GRANT ALL ON TABLE "public"."gm_journal_entries" TO "service_role";
GRANT SELECT ON TABLE "public"."gm_journal_entries" TO "authenticated";



GRANT ALL ON TABLE "public"."reputation_milestones" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."reputation_milestones" TO "authenticated";



GRANT ALL ON TABLE "public"."gm_milestones" TO "service_role";
GRANT SELECT ON TABLE "public"."gm_milestones" TO "authenticated";



GRANT ALL ON TABLE "public"."gm_relationships" TO "service_role";
GRANT SELECT ON TABLE "public"."gm_relationships" TO "authenticated";



GRANT ALL ON TABLE "public"."services" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."services" TO "authenticated";



GRANT ALL ON TABLE "public"."gm_services" TO "service_role";
GRANT SELECT ON TABLE "public"."gm_services" TO "authenticated";



GRANT ALL ON TABLE "public"."loot_player_publications" TO "service_role";



GRANT ALL ON TABLE "public"."player_campaign" TO "service_role";
GRANT SELECT ON TABLE "public"."player_campaign" TO "authenticated";



GRANT ALL ON TABLE "public"."player_contacts" TO "service_role";
GRANT SELECT ON TABLE "public"."player_contacts" TO "authenticated";



GRANT ALL ON TABLE "public"."player_economy_totals" TO "authenticated";
GRANT ALL ON TABLE "public"."player_economy_totals" TO "service_role";



GRANT ALL ON TABLE "public"."player_faction_overview" TO "service_role";
GRANT SELECT ON TABLE "public"."player_faction_overview" TO "authenticated";



GRANT ALL ON TABLE "public"."player_inventory_items" TO "authenticated";
GRANT ALL ON TABLE "public"."player_inventory_items" TO "service_role";



GRANT ALL ON TABLE "public"."player_item_history" TO "authenticated";
GRANT ALL ON TABLE "public"."player_item_history" TO "service_role";



GRANT ALL ON TABLE "public"."player_item_request_overview" TO "authenticated";
GRANT ALL ON TABLE "public"."player_item_request_overview" TO "service_role";



GRANT ALL ON TABLE "public"."player_journal" TO "service_role";
GRANT SELECT ON TABLE "public"."player_journal" TO "authenticated";



GRANT ALL ON TABLE "public"."player_loot" TO "authenticated";
GRANT ALL ON TABLE "public"."player_loot" TO "service_role";



GRANT ALL ON TABLE "public"."player_money_balances" TO "authenticated";
GRANT ALL ON TABLE "public"."player_money_balances" TO "service_role";



GRANT ALL ON TABLE "public"."player_money_debt_overview" TO "authenticated";
GRANT ALL ON TABLE "public"."player_money_debt_overview" TO "service_role";



GRANT ALL ON TABLE "public"."player_money_history" TO "authenticated";
GRANT ALL ON TABLE "public"."player_money_history" TO "service_role";



GRANT ALL ON TABLE "public"."player_pages" TO "service_role";



GRANT ALL ON TABLE "public"."player_relationship_notes" TO "service_role";



GRANT ALL ON TABLE "public"."player_relationships" TO "service_role";
GRANT SELECT ON TABLE "public"."player_relationships" TO "authenticated";



GRANT ALL ON TABLE "public"."player_services" TO "service_role";
GRANT SELECT ON TABLE "public"."player_services" TO "authenticated";



GRANT ALL ON TABLE "public"."quest_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."quest_entries" TO "service_role";



GRANT ALL ON TABLE "public"."quest_journal_blocks" TO "anon";
GRANT ALL ON TABLE "public"."quest_journal_blocks" TO "authenticated";
GRANT ALL ON TABLE "public"."quest_journal_blocks" TO "service_role";



GRANT ALL ON TABLE "public"."quest_journal_documents" TO "anon";
GRANT ALL ON TABLE "public"."quest_journal_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."quest_journal_documents" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."quest_journal_pages" TO "authenticated";
GRANT ALL ON TABLE "public"."quest_journal_pages" TO "service_role";



GRANT ALL ON TABLE "public"."quest_journal_revisions" TO "authenticated";
GRANT ALL ON TABLE "public"."quest_journal_revisions" TO "service_role";



GRANT ALL ON TABLE "public"."source_references" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."source_references" TO "authenticated";



REVOKE ALL ON TABLE "storage"."buckets" FROM "supabase_storage_admin";
GRANT ALL ON TABLE "storage"."buckets" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON TABLE "storage"."buckets" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets" TO "anon";
GRANT ALL ON TABLE "storage"."buckets" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."buckets_analytics" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "anon";



GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "service_role";
GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "authenticated";
GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "anon";



REVOKE ALL ON TABLE "storage"."objects" FROM "supabase_storage_admin";
GRANT ALL ON TABLE "storage"."objects" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON TABLE "storage"."objects" TO "service_role";
GRANT ALL ON TABLE "storage"."objects" TO "authenticated";
GRANT ALL ON TABLE "storage"."objects" TO "anon";
GRANT ALL ON TABLE "storage"."objects" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."s3_multipart_uploads" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "anon";



GRANT ALL ON TABLE "storage"."s3_multipart_uploads_parts" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "anon";



GRANT SELECT ON TABLE "storage"."vector_indexes" TO "service_role";
GRANT SELECT ON TABLE "storage"."vector_indexes" TO "authenticated";
GRANT SELECT ON TABLE "storage"."vector_indexes" TO "anon";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "service_role";
