-- Création autonome et propriété explicite des campagnes.
--
-- Une campagne possède un propriétaire unique. Les autres MJ éventuels peuvent
-- la gérer, mais seule cette personne peut la supprimer définitivement.

alter table public.campaigns
  add column owner_user_id uuid references auth.users(id) on delete cascade;

update public.campaigns campaign
set owner_user_id = (
  select member.user_id
  from public.campaign_members member
  where member.campaign_id = campaign.id and member.role = 'gm'
  order by member.created_at, member.user_id
  limit 1
)
where campaign.owner_user_id is null
  and exists (
    select 1 from public.campaign_members member
    where member.campaign_id = campaign.id and member.role = 'gm'
  );

create or replace function public.assign_first_campaign_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role = 'gm' then
    update public.campaigns
    set owner_user_id = new.user_id
    where id = new.campaign_id and owner_user_id is null;
  end if;
  return new;
end;
$$;

create trigger campaign_members_assign_first_owner
after insert or update of role on public.campaign_members
for each row execute function public.assign_first_campaign_owner();

drop policy if exists campaigns_gm_all on public.campaigns;
drop policy if exists campaigns_member_read on public.campaigns;
create policy campaigns_member_read on public.campaigns
for select to authenticated
using (public.is_campaign_member(id));

drop function if exists public.list_my_campaigns();
create function public.list_my_campaigns()
returns table(
  campaign_id uuid,
  slug text,
  name text,
  description text,
  role text,
  joined_at timestamptz,
  is_owner boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select campaign.id, campaign.slug, campaign.name, campaign.description,
    member.role, member.created_at, campaign.owner_user_id = auth.uid()
  from public.campaign_members member
  join public.campaigns campaign on campaign.id = member.campaign_id
  where member.user_id = auth.uid()
  order by lower(campaign.name), campaign.id;
$$;

create function public.create_campaign(p_name text, p_description text default null)
returns table(campaign_id uuid, slug text, name text, description text)
language plpgsql
security definer
set search_path = ''
as $$
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

create function public.delete_owned_campaign(p_campaign_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
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

revoke all on function public.assign_first_campaign_owner() from public, anon, authenticated;
revoke all on function public.list_my_campaigns() from public, anon, authenticated;
revoke all on function public.create_campaign(text, text) from public, anon, authenticated;
revoke all on function public.delete_owned_campaign(uuid) from public, anon, authenticated;
grant execute on function public.list_my_campaigns() to authenticated;
grant execute on function public.create_campaign(text, text) to authenticated;
grant execute on function public.delete_owned_campaign(uuid) to authenticated;
