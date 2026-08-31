-- Enrichit le portail de campagnes : date de création et édition réservée au
-- propriétaire. L’accès direct à la table reste en lecture seule via RLS.

drop function if exists public.list_my_campaigns();
create function public.list_my_campaigns()
returns table(
  campaign_id uuid,
  slug text,
  name text,
  description text,
  role text,
  joined_at timestamptz,
  is_owner boolean,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select campaign.id, campaign.slug, campaign.name, campaign.description,
    member.role, member.created_at, campaign.owner_user_id = auth.uid(),
    campaign.created_at
  from public.campaign_members member
  join public.campaigns campaign on campaign.id = member.campaign_id
  where member.user_id = auth.uid()
  order by lower(campaign.name), campaign.id;
$$;

create function public.update_owned_campaign(
  p_campaign_id uuid,
  p_name text,
  p_description text default null
)
returns table(campaign_id uuid, slug text, name text, description text, created_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
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

revoke all on function public.list_my_campaigns() from public, anon, authenticated;
revoke all on function public.update_owned_campaign(uuid, text, text) from public, anon, authenticated;
grant execute on function public.list_my_campaigns() to authenticated;
grant execute on function public.update_owned_campaign(uuid, text, text) to authenticated;

create or replace function public.list_campaign_members(p_campaign_id uuid)
returns table(user_id uuid, display_name text, role text, joined_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
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
