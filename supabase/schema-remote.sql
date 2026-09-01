


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


CREATE OR REPLACE FUNCTION "public"."accept_campaign_invitation"("p_token" "uuid") RETURNS TABLE("campaign_id" "uuid", "campaign_name" "text", "role" "text", "already_member" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
#variable_conflict use_column
declare
  invite public.campaign_invites%rowtype;
  campaign_name_value text;
  exists_member boolean;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;

  select * into invite from public.campaign_invites where token = p_token;
  if not found then raise exception 'Invitation invalide'; end if;
  if invite.revoked_at is not null then raise exception 'Invitation révoquée'; end if;
  if invite.expires_at is not null and invite.expires_at <= now() then
    raise exception 'Invitation expirée';
  end if;

  select name into campaign_name_value from public.campaigns where id = invite.campaign_id;
  select exists (
    select 1 from public.campaign_members member
    where member.campaign_id = invite.campaign_id and member.user_id = auth.uid()
  ) into exists_member;

  insert into public.user_profiles (user_id)
  values (auth.uid())
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


CREATE OR REPLACE FUNCTION "public"."get_my_player_page"("p_campaign_id" "uuid") RETURNS TABLE("campaign_id" "uuid", "user_id" "uuid", "display_name" "text", "character_name" "text", "character_summary" "text", "pathbuilder_url" "text", "notes" "text", "objectives" "text", "updated_at" timestamp with time zone, "image_path" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not exists (select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id and member.user_id = auth.uid() and member.role = 'player')
  then raise exception 'Accès refusé'; end if;
  insert into public.user_profiles (user_id) values (auth.uid()) on conflict on constraint user_profiles_pkey do nothing;
  insert into public.player_pages (campaign_id, user_id) values (p_campaign_id, auth.uid()) on conflict on constraint player_pages_pkey do nothing;
  return query select page.campaign_id, page.user_id, profile.display_name,
    page.character_name, page.character_summary, page.pathbuilder_url, page.notes,
    page.objectives, page.updated_at, page.image_path
  from public.player_pages page join public.user_profiles profile on profile.user_id = page.user_id
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
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;

  delete from public.campaign_members
  where campaign_id = p_campaign_id
    and user_id = auth.uid()
    and role = 'player';

  if not found then
    raise exception 'Vous n’êtes pas joueur de cette campagne';
  end if;

  update public.loot_player_publications
  set owner_user_id = null,
      lifecycle_status = 'available',
      legacy_owner_label = null
  where campaign_id = p_campaign_id
    and owner_user_id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."leave_campaign"("p_campaign_id" "uuid") OWNER TO "postgres";


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


CREATE OR REPLACE FUNCTION "public"."list_campaign_player_pages"("p_campaign_id" "uuid") RETURNS TABLE("campaign_id" "uuid", "user_id" "uuid", "display_name" "text", "active" boolean, "character_name" "text", "character_summary" "text", "pathbuilder_url" "text", "notes" "text", "objectives" "text", "updated_at" timestamp with time zone, "image_path" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'Accès refusé'; end if;
  return query select page.campaign_id, page.user_id, coalesce(profile.display_name, 'Sans pseudo'),
    (member.user_id is not null), page.character_name, page.character_summary,
    page.pathbuilder_url, page.notes, page.objectives, page.updated_at, page.image_path
  from public.player_pages page
  left join public.user_profiles profile on profile.user_id = page.user_id
  left join public.campaign_members member on member.campaign_id = page.campaign_id
    and member.user_id = page.user_id and member.role = 'player'
  where page.campaign_id = p_campaign_id
  order by member.user_id is null, lower(coalesce(profile.display_name, 'Sans pseudo'));
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


CREATE OR REPLACE FUNCTION "public"."remove_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_campaign_gm(p_campaign_id) then
    raise exception 'Accès refusé';
  end if;

  -- La suppression est volontairement limitée aux joueurs actifs. Si la
  -- cible n'est pas un joueur de cette campagne, le comportement historique
  -- reste un no-op et aucune attribution ne peut être modifiée par erreur.
  delete from public.campaign_members
  where campaign_id = p_campaign_id
    and user_id = p_user_id
    and role = 'player';

  if not found then
    return;
  end if;

  -- Les publications de butin restent dans le registre, mais leur état
  -- redevient neutre. Les pages personnelles ne sont jamais touchées ici.
  update public.loot_player_publications
  set owner_user_id = null,
      lifecycle_status = 'available',
      legacy_owner_label = null
  where campaign_id = p_campaign_id
    and owner_user_id = p_user_id;
end;
$$;


ALTER FUNCTION "public"."remove_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


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


CREATE OR REPLACE FUNCTION "public"."set_loot_player_visibility"("p_loot_id" "uuid", "p_visible" boolean, "p_published_on" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_campaign_id uuid;
begin
  select campaign_id into v_campaign_id
  from public.campaign_loot
  where id = p_loot_id;

  if v_campaign_id is null then raise exception 'Butin introuvable'; end if;
  if not public.is_campaign_gm(v_campaign_id) then raise exception 'Accès refusé'; end if;

  update public.campaign_loot
  set player_visible = p_visible,
      discovery_status = case when p_visible then 'found' else discovery_status end
  where id = p_loot_id;

  if p_visible then
    insert into public.loot_player_publications (loot_id, campaign_id, published_on)
    values (p_loot_id, v_campaign_id, coalesce(p_published_on, current_date))
    on conflict (loot_id) do nothing;
  end if;
end;
$$;


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
    AS $_$
begin
  if not exists (select 1 from public.campaign_members member
    where member.campaign_id = p_campaign_id and member.user_id = auth.uid() and member.role = 'player')
  then raise exception 'Accès refusé'; end if;
  if nullif(btrim(coalesce(p_image_path, '')), '') is not null
    and p_image_path !~ ('^' || p_campaign_id::text || '/' || auth.uid()::text || '/[0-9a-f-]{36}\.[a-z0-9]+$')
  then raise exception 'Chemin de portrait invalide'; end if;
  update public.player_pages set
    character_name = nullif(btrim(coalesce(p_character_name, '')), ''),
    character_summary = nullif(btrim(coalesce(p_character_summary, '')), ''),
    pathbuilder_url = nullif(btrim(coalesce(p_pathbuilder_url, '')), ''),
    notes = nullif(btrim(coalesce(p_notes, '')), ''),
    objectives = nullif(btrim(coalesce(p_objectives, '')), ''),
    image_path = nullif(btrim(coalesce(p_image_path, '')), '')
  where campaign_id = p_campaign_id and user_id = auth.uid();
  if not found then raise exception 'Page joueur introuvable'; end if;
end;
$_$;


ALTER FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text") OWNER TO "postgres";


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
    CONSTRAINT "bestiary_entries_name_check" CHECK (("length"("btrim"("name")) > 0))
);


ALTER TABLE "public"."bestiary_entries" OWNER TO "postgres";


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
    "s"."player_display_mode"
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


CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "user_id" "uuid" NOT NULL,
    "display_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_profiles_display_name_check" CHECK ((("display_name" IS NULL) OR ((("char_length"("btrim"("display_name")) >= 2) AND ("char_length"("btrim"("display_name")) <= 40)) AND ("display_name" = "btrim"("display_name")))))
);


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";


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
    CONSTRAINT "player_pages_character_name_check" CHECK (("char_length"(COALESCE("character_name", ''::"text")) <= 120)),
    CONSTRAINT "player_pages_character_summary_check" CHECK (("char_length"(COALESCE("character_summary", ''::"text")) <= 4000)),
    CONSTRAINT "player_pages_notes_check" CHECK (("char_length"(COALESCE("notes", ''::"text")) <= 20000)),
    CONSTRAINT "player_pages_objectives_check" CHECK (("char_length"(COALESCE("objectives", ''::"text")) <= 10000)),
    CONSTRAINT "player_pages_pathbuilder_url_check" CHECK ((("pathbuilder_url" IS NULL) OR (("char_length"("pathbuilder_url") <= 500) AND (("lower"("pathbuilder_url") ~~ 'https://pathbuilder2e.com/%'::"text") OR ("lower"("pathbuilder_url") ~~ 'https://www.pathbuilder2e.com/%'::"text")))))
);


ALTER TABLE "public"."player_pages" OWNER TO "postgres";


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



ALTER TABLE ONLY "public"."bilateral_dossiers"
    ADD CONSTRAINT "bilateral_dossiers_campaign_id_faction_a_id_faction_b_id_key" UNIQUE ("campaign_id", "faction_a_id", "faction_b_id");



ALTER TABLE ONLY "public"."bilateral_dossiers"
    ADD CONSTRAINT "bilateral_dossiers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_factions"
    ADD CONSTRAINT "campaign_factions_pkey" PRIMARY KEY ("campaign_id", "faction_id");



ALTER TABLE ONLY "public"."campaign_invites"
    ADD CONSTRAINT "campaign_invites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_invites"
    ADD CONSTRAINT "campaign_invites_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."campaign_loot"
    ADD CONSTRAINT "campaign_loot_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_members"
    ADD CONSTRAINT "campaign_members_pkey" PRIMARY KEY ("campaign_id", "user_id");



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



CREATE UNIQUE INDEX "archive_characters_template_idx" ON "public"."archive_characters" USING "btree" ("campaign_id", "template_key") WHERE ("template_key" IS NOT NULL);



CREATE INDEX "archive_characters_volume_idx" ON "public"."archive_characters" USING "btree" ("campaign_id", "first_volume", "sort_order");



CREATE UNIQUE INDEX "archive_places_template_idx" ON "public"."archive_places" USING "btree" ("campaign_id", "template_key") WHERE ("template_key" IS NOT NULL);



CREATE INDEX "archive_places_volume_idx" ON "public"."archive_places" USING "btree" ("campaign_id", "first_volume", "sort_order");



CREATE INDEX "bestiary_entries_campaign_name_idx" ON "public"."bestiary_entries" USING "btree" ("campaign_id", "name");



CREATE INDEX "campaign_invites_campaign_created_idx" ON "public"."campaign_invites" USING "btree" ("campaign_id", "created_at" DESC);



CREATE INDEX "campaign_invites_token_idx" ON "public"."campaign_invites" USING "btree" ("token");



CREATE UNIQUE INDEX "campaign_loot_reference_idx" ON "public"."campaign_loot" USING "btree" ("campaign_id", "reference_id") WHERE ("reference_id" IS NOT NULL);



CREATE INDEX "campaign_loot_source_idx" ON "public"."campaign_loot" USING "btree" ("campaign_id", "volume", "source_kind", "discovery_status", "sort_order");



CREATE INDEX "campaign_members_user_campaign_idx" ON "public"."campaign_members" USING "btree" ("user_id", "campaign_id");



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



CREATE OR REPLACE TRIGGER "archive_characters_touch" BEFORE UPDATE ON "public"."archive_characters" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "archive_places_touch" BEFORE UPDATE ON "public"."archive_places" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "bestiary_entries_touch" BEFORE UPDATE ON "public"."bestiary_entries" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "campaign_factions_touch" BEFORE UPDATE ON "public"."campaign_factions" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "campaign_loot_touch" BEFORE UPDATE ON "public"."campaign_loot" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "campaign_members_assign_first_owner" AFTER INSERT OR UPDATE OF "role" ON "public"."campaign_members" FOR EACH ROW EXECUTE FUNCTION "public"."assign_first_campaign_owner"();



CREATE OR REPLACE TRIGGER "campaign_session_preps_touch" BEFORE UPDATE ON "public"."campaign_session_preps" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "campaigns_touch" BEFORE UPDATE ON "public"."campaigns" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "contact_player_notes_touch" BEFORE UPDATE ON "public"."contact_player_notes" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "contacts_touch" BEFORE UPDATE ON "public"."contacts" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "journal_touch" BEFORE UPDATE ON "public"."journal_entries" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "player_pages_touch" BEFORE UPDATE ON "public"."player_pages" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "quest_entries_touch" BEFORE UPDATE ON "public"."quest_entries" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "quest_journal_blocks_touch" BEFORE UPDATE ON "public"."quest_journal_blocks" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "quest_journal_documents_touch" BEFORE UPDATE ON "public"."quest_journal_documents" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "quest_journal_pages_revision" AFTER UPDATE OF "content" ON "public"."quest_journal_pages" FOR EACH ROW EXECUTE FUNCTION "public"."capture_quest_journal_revision"();



CREATE OR REPLACE TRIGGER "quest_journal_pages_touch" BEFORE UPDATE ON "public"."quest_journal_pages" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "relationships_touch" BEFORE UPDATE ON "public"."faction_relationships" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "settings_touch" BEFORE UPDATE ON "public"."campaign_settings" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "user_profiles_touch" BEFORE UPDATE ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



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



ALTER TABLE ONLY "public"."campaign_invites"
    ADD CONSTRAINT "campaign_invites_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_invites"
    ADD CONSTRAINT "campaign_invites_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_loot"
    ADD CONSTRAINT "campaign_loot_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_members"
    ADD CONSTRAINT "campaign_members_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_members"
    ADD CONSTRAINT "campaign_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



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
    ADD CONSTRAINT "player_pages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



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



ALTER TABLE "public"."archive_character_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."archive_characters" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "archive_characters_gm_all" ON "public"."archive_characters" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."archive_place_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."archive_places" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "archive_places_gm_all" ON "public"."archive_places" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."bestiary_entries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bestiary_entries_public_manage" ON "public"."bestiary_entries" TO "authenticated", "anon" USING ("public"."is_public_campaign"("campaign_id")) WITH CHECK ("public"."is_public_campaign"("campaign_id"));



ALTER TABLE "public"."bilateral_dossiers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_factions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaign_factions_gm_all" ON "public"."campaign_factions" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."campaign_invites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."campaign_loot" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaign_loot_gm_all" ON "public"."campaign_loot" TO "authenticated" USING ("public"."is_campaign_gm"("campaign_id")) WITH CHECK ("public"."is_campaign_gm"("campaign_id"));



ALTER TABLE "public"."campaign_members" ENABLE ROW LEVEL SECURITY;


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


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."accept_campaign_invitation"("p_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."accept_campaign_invitation"("p_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_campaign_invitation"("p_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_campaign_invitation"("p_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."apply_reputation_milestone"("milestone_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."apply_reputation_milestone"("milestone_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."apply_reputation_milestone"("milestone_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_reputation_milestone"("milestone_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."assign_first_campaign_owner"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assign_first_campaign_owner"() TO "service_role";



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



REVOKE ALL ON FUNCTION "public"."delete_owned_campaign"("p_campaign_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_owned_campaign"("p_campaign_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."delete_owned_campaign"("p_campaign_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."generate_available_campaign_slug"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."generate_available_campaign_slug"() TO "service_role";



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



REVOKE ALL ON FUNCTION "public"."remove_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."remove_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."remove_campaign_player"("p_campaign_id" "uuid", "p_user_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."reset_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reset_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."reset_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."resolve_reputation_milestone"("p_milestone_id" "uuid", "p_outcome" "text", "p_note" "text", "p_effects" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_reputation_milestone"("p_milestone_id" "uuid", "p_outcome" "text", "p_note" "text", "p_effects" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."resolve_reputation_milestone"("p_milestone_id" "uuid", "p_outcome" "text", "p_note" "text", "p_effects" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."revoke_campaign_invite"("p_invite_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."revoke_campaign_invite"("p_invite_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."revoke_campaign_invite"("p_invite_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."save_player_contact_notes"("target_contact_id" "uuid", "next_character_notes" "text", "next_debt_notes" "text", "next_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_player_contact_notes"("target_contact_id" "uuid", "next_character_notes" "text", "next_debt_notes" "text", "next_notes" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."save_player_contact_notes"("target_contact_id" "uuid", "next_character_notes" "text", "next_debt_notes" "text", "next_notes" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."save_quest_journal_page"("target_campaign_id" "uuid", "expected_revision" integer, "next_content" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_quest_journal_page"("target_campaign_id" "uuid", "expected_revision" integer, "next_content" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."save_quest_journal_page"("target_campaign_id" "uuid", "expected_revision" integer, "next_content" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."seed_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."seed_campaign_reference_data"("p_campaign_id" "uuid", "p_scope" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_loot_player_visibility"("p_loot_id" "uuid", "p_visible" boolean, "p_published_on" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_loot_player_visibility"("p_loot_id" "uuid", "p_visible" boolean, "p_published_on" "date") TO "service_role";
GRANT ALL ON FUNCTION "public"."set_loot_player_visibility"("p_loot_id" "uuid", "p_visible" boolean, "p_published_on" "date") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_player_loot_assignment"("p_loot_id" "uuid", "p_owner_user_id" "uuid", "p_lifecycle_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_player_loot_assignment"("p_loot_id" "uuid", "p_owner_user_id" "uuid", "p_lifecycle_status" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."set_player_loot_assignment"("p_loot_id" "uuid", "p_owner_user_id" "uuid", "p_lifecycle_status" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_player_loot_published_on"("p_loot_id" "uuid", "p_published_on" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_player_loot_published_on"("p_loot_id" "uuid", "p_published_on" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_player_loot_published_on"("p_loot_id" "uuid", "p_published_on" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."update_my_player_page"("p_campaign_id" "uuid", "p_character_name" "text", "p_character_summary" "text", "p_pathbuilder_url" "text", "p_notes" "text", "p_objectives" "text", "p_image_path" "text") TO "authenticated";



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



GRANT ALL ON TABLE "public"."bestiary_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."bestiary_entries" TO "service_role";



GRANT ALL ON TABLE "public"."bilateral_dossiers" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."bilateral_dossiers" TO "authenticated";



GRANT ALL ON TABLE "public"."campaign_factions" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."campaign_factions" TO "authenticated";



GRANT ALL ON TABLE "public"."campaign_invites" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_loot" TO "anon";
GRANT ALL ON TABLE "public"."campaign_loot" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_loot" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_members" TO "service_role";
GRANT SELECT ON TABLE "public"."campaign_members" TO "authenticated";



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



GRANT ALL ON TABLE "public"."player_faction_overview" TO "service_role";
GRANT SELECT ON TABLE "public"."player_faction_overview" TO "authenticated";



GRANT ALL ON TABLE "public"."player_journal" TO "service_role";
GRANT SELECT ON TABLE "public"."player_journal" TO "authenticated";



GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."player_loot" TO "authenticated";
GRANT ALL ON TABLE "public"."player_loot" TO "service_role";



GRANT ALL ON TABLE "public"."player_pages" TO "service_role";



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







