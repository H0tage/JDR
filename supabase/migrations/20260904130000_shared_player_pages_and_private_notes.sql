-- Nom conseillé dans le SQL Editor : Pages joueurs partagées et notes privées — 2026-09-04
-- Fiches de personnage partagées dans la campagne et notes privées entre PJ.
--
-- Confidentialité :
-- - les membres actifs peuvent consulter les informations publiques des PJ actifs ;
-- - seul le propriétaire voit Pathbuilder et modifie sa fiche ;
-- - le MJ peut consulter toutes les fiches, y compris les notes personnelles ;
-- - les notes prises sur un autre PJ restent strictement privées à leur auteur.

drop function if exists public.list_campaign_player_pages(uuid);
create function public.list_campaign_player_pages(p_campaign_id uuid)
returns table(
  campaign_id uuid,
  user_id uuid,
  display_name text,
  active boolean,
  is_own boolean,
  character_name text,
  character_summary text,
  pathbuilder_url text,
  notes text,
  objectives text,
  updated_at timestamptz,
  image_path text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
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
    page.character_summary,
    case when page.user_id = auth.uid() then page.pathbuilder_url else null end,
    case when viewer_is_gm or page.user_id = auth.uid() then page.notes else null end,
    page.objectives,
    page.updated_at,
    page.image_path
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

create table public.player_relationship_notes (
  campaign_id uuid not null,
  author_user_id uuid not null,
  target_user_id uuid not null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (campaign_id, author_user_id, target_user_id),
  foreign key (campaign_id, author_user_id)
    references public.player_pages(campaign_id, user_id) on delete cascade,
  foreign key (campaign_id, target_user_id)
    references public.player_pages(campaign_id, user_id) on delete cascade,
  constraint player_relationship_notes_distinct_players check (author_user_id <> target_user_id),
  constraint player_relationship_notes_length check (char_length(coalesce(notes, '')) <= 10000)
);

create trigger player_relationship_notes_touch
before update on public.player_relationship_notes
for each row execute function public.touch_updated_at();

alter table public.player_relationship_notes enable row level security;

create policy player_relationship_notes_owner_all on public.player_relationship_notes
for all to authenticated
using (author_user_id = auth.uid())
with check (author_user_id = auth.uid());

create function public.list_my_player_relationship_notes(p_campaign_id uuid)
returns table(target_user_id uuid, notes text, updated_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
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

create function public.update_my_player_relationship_note(
  p_campaign_id uuid,
  p_target_user_id uuid,
  p_notes text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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

revoke all on table public.player_relationship_notes from anon, authenticated;
revoke all on function public.list_campaign_player_pages(uuid) from public, anon, authenticated;
grant execute on function public.list_campaign_player_pages(uuid) to authenticated;
revoke all on function public.list_my_player_relationship_notes(uuid) from public, anon, authenticated;
grant execute on function public.list_my_player_relationship_notes(uuid) to authenticated;
revoke all on function public.update_my_player_relationship_note(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.update_my_player_relationship_note(uuid, uuid, text) to authenticated;
