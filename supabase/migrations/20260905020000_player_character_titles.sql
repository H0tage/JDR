-- Nom conseillé dans le SQL Editor : Titres facultatifs des personnages — 2026-09-05

alter table public.player_pages
  add column if not exists character_title text;

alter table public.player_pages
  drop constraint if exists player_pages_character_title_length,
  add constraint player_pages_character_title_length
    check (char_length(coalesce(character_title, '')) <= 160);

drop function if exists public.get_my_player_page(uuid);
create function public.get_my_player_page(p_campaign_id uuid)
returns table(
  campaign_id uuid, user_id uuid, display_name text, character_name text,
  character_title text, character_summary text, pathbuilder_url text, notes text,
  objectives text, updated_at timestamptz, image_path text, image_x numeric,
  image_y numeric, image_zoom numeric
)
language plpgsql security definer set search_path = '' as $$
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

create function public.update_my_player_page(
  p_campaign_id uuid, p_character_name text, p_character_title text,
  p_character_summary text, p_pathbuilder_url text, p_notes text,
  p_objectives text, p_image_path text, p_image_x numeric, p_image_y numeric,
  p_image_zoom numeric
)
returns void language plpgsql security definer set search_path = '' as $$
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
$$;

-- Compatibilité avec la version précédente du site : elle conserve le titre.
create or replace function public.update_my_player_page(
  p_campaign_id uuid, p_character_name text, p_character_summary text,
  p_pathbuilder_url text, p_notes text, p_objectives text, p_image_path text,
  p_image_x numeric, p_image_y numeric, p_image_zoom numeric
)
returns void language plpgsql security definer set search_path = '' as $$
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

drop function if exists public.list_campaign_player_pages(uuid);
create function public.list_campaign_player_pages(p_campaign_id uuid)
returns table(
  campaign_id uuid, user_id uuid, display_name text, active boolean,
  is_own boolean, character_name text, character_title text,
  character_summary text, pathbuilder_url text, notes text, objectives text,
  updated_at timestamptz, image_path text, image_x numeric, image_y numeric,
  image_zoom numeric
)
language plpgsql stable security definer set search_path = '' as $$
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

revoke all on function public.get_my_player_page(uuid) from public, anon, authenticated;
grant execute on function public.get_my_player_page(uuid) to authenticated;
revoke all on function public.update_my_player_page(uuid, text, text, text, text, text, text, text, numeric, numeric, numeric) from public, anon, authenticated;
grant execute on function public.update_my_player_page(uuid, text, text, text, text, text, text, text, numeric, numeric, numeric) to authenticated;
revoke all on function public.update_my_player_page(uuid, text, text, text, text, text, text, numeric, numeric, numeric) from public, anon, authenticated;
grant execute on function public.update_my_player_page(uuid, text, text, text, text, text, text, numeric, numeric, numeric) to authenticated;
revoke all on function public.list_campaign_player_pages(uuid) from public, anon, authenticated;
grant execute on function public.list_campaign_player_pages(uuid) to authenticated;
