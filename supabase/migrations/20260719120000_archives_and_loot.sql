-- Archives MJ et registre de butin de campagne.
-- Les tables *_templates restent immuables. Les tables de campagne sont librement
-- éditables et peuvent être entièrement restaurées depuis ces modèles.

alter table public.campaign_settings
  add column if not exists show_archive_translations boolean not null default true;

create table if not exists public.archive_character_templates (
  template_key text primary key, sort_order integer not null, first_name text not null default '',
  last_name text, translated_name text, translation_origin text not null default 'none'
    check (translation_origin in ('none','attested','site')),
  role_text text, first_volume smallint not null check (first_volume between 1 and 6),
  first_page integer check (first_page is null or first_page > 0)
);

create table if not exists public.archive_place_templates (
  template_key text primary key, sort_order integer not null, original_name text not null,
  translated_name text, translation_origin text not null default 'none'
    check (translation_origin in ('none','attested','site')),
  place_type text, function_text text,
  first_volume smallint not null check (first_volume between 1 and 6),
  first_page integer check (first_page is null or first_page > 0)
);

create table if not exists public.loot_templates (
  template_key text primary key, sort_order integer not null, original_name text not null,
  quantity text not null default '1', description text, unit_value text, total_value text,
  location_name text, position text, volume smallint not null check (volume between 1 and 6),
  page integer check (page is null or page > 0), nature text, notes text
);

create table if not exists public.archive_characters (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  template_key text references public.archive_character_templates(template_key) on delete set null,
  sort_order integer not null, first_name text not null default '', last_name text,
  translated_name text, translation_origin text not null default 'none'
    check (translation_origin in ('none','attested','site','custom')),
  role_text text, first_volume smallint not null check (first_volume between 1 and 6),
  first_page integer check (first_page is null or first_page > 0),
  is_custom boolean not null default false, updated_at timestamptz not null default now()
);
create unique index if not exists archive_characters_template_idx
  on public.archive_characters(campaign_id, template_key) where template_key is not null;
create index if not exists archive_characters_volume_idx
  on public.archive_characters(campaign_id, first_volume, sort_order);

create table if not exists public.archive_places (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  template_key text references public.archive_place_templates(template_key) on delete set null,
  sort_order integer not null, original_name text not null, translated_name text,
  translation_origin text not null default 'none'
    check (translation_origin in ('none','attested','site','custom')),
  place_type text, function_text text,
  first_volume smallint not null check (first_volume between 1 and 6),
  first_page integer check (first_page is null or first_page > 0),
  is_custom boolean not null default false, updated_at timestamptz not null default now()
);
create unique index if not exists archive_places_template_idx
  on public.archive_places(campaign_id, template_key) where template_key is not null;
create index if not exists archive_places_volume_idx
  on public.archive_places(campaign_id, first_volume, sort_order);

create table if not exists public.campaign_loot (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  template_key text references public.loot_templates(template_key) on delete set null,
  sort_order integer not null, original_name text not null, quantity text not null default '1',
  description text, unit_value text, total_value text, location_name text, position text,
  volume smallint not null check (volume between 1 and 6),
  page integer check (page is null or page > 0), nature text, notes text,
  is_custom boolean not null default false, updated_at timestamptz not null default now()
);
create unique index if not exists campaign_loot_template_idx
  on public.campaign_loot(campaign_id, template_key) where template_key is not null;
create index if not exists campaign_loot_volume_idx
  on public.campaign_loot(campaign_id, volume, sort_order);

drop trigger if exists archive_characters_touch on public.archive_characters;
create trigger archive_characters_touch before update on public.archive_characters
  for each row execute function public.touch_updated_at();
drop trigger if exists archive_places_touch on public.archive_places;
create trigger archive_places_touch before update on public.archive_places
  for each row execute function public.touch_updated_at();
drop trigger if exists campaign_loot_touch on public.campaign_loot;
create trigger campaign_loot_touch before update on public.campaign_loot
  for each row execute function public.touch_updated_at();

alter table public.archive_character_templates enable row level security;
alter table public.archive_place_templates enable row level security;
alter table public.loot_templates enable row level security;
alter table public.archive_characters enable row level security;
alter table public.archive_places enable row level security;
alter table public.campaign_loot enable row level security;

revoke all on public.archive_character_templates from anon, authenticated;
revoke all on public.archive_place_templates from anon, authenticated;
revoke all on public.loot_templates from anon, authenticated;
grant select, insert, update, delete on public.archive_characters to authenticated;
grant select, insert, update, delete on public.archive_places to authenticated;
grant select, insert, update, delete on public.campaign_loot to authenticated;

drop policy if exists archive_characters_gm_all on public.archive_characters;
create policy archive_characters_gm_all on public.archive_characters for all to authenticated
  using (public.is_campaign_gm(campaign_id)) with check (public.is_campaign_gm(campaign_id));
drop policy if exists archive_places_gm_all on public.archive_places;
create policy archive_places_gm_all on public.archive_places for all to authenticated
  using (public.is_campaign_gm(campaign_id)) with check (public.is_campaign_gm(campaign_id));
drop policy if exists campaign_loot_gm_all on public.campaign_loot;
create policy campaign_loot_gm_all on public.campaign_loot for all to authenticated
  using (public.is_campaign_gm(campaign_id)) with check (public.is_campaign_gm(campaign_id));


-- Private archive and loot templates intentionally omitted.

create or replace function public.seed_campaign_reference_data(p_campaign_id uuid, p_scope text default 'all')
returns void language plpgsql security definer set search_path = '' as $$
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
  if p_scope in ('loot','all') then
    insert into public.campaign_loot
      (campaign_id, template_key, sort_order, original_name, quantity, description, unit_value, total_value, location_name, position, volume, page, nature, notes, is_custom)
    select p_campaign_id, template_key, sort_order, original_name, quantity, description, unit_value, total_value, location_name, position, volume, page, nature, notes, false
    from public.loot_templates
    on conflict (campaign_id, template_key) where template_key is not null do nothing;
  end if;
end;
$$;

create or replace function public.reset_campaign_reference_data(p_campaign_id uuid, p_scope text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_campaign_gm(p_campaign_id) then raise exception 'Accès refusé'; end if;
  if p_scope not in ('archives','loot','all') then raise exception 'Périmètre de restauration invalide'; end if;
  if p_scope in ('archives','all') then
    delete from public.archive_characters where campaign_id = p_campaign_id;
    delete from public.archive_places where campaign_id = p_campaign_id;
  end if;
  if p_scope in ('loot','all') then delete from public.campaign_loot where campaign_id = p_campaign_id; end if;
  perform public.seed_campaign_reference_data(p_campaign_id, p_scope);
end;
$$;

revoke all on function public.seed_campaign_reference_data(uuid, text) from public;
revoke all on function public.reset_campaign_reference_data(uuid, text) from public;
grant execute on function public.reset_campaign_reference_data(uuid, text) to authenticated;
