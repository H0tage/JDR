-- Permet à un joueur de quitter volontairement une campagne.
--
-- Le départ volontaire suit exactement la même règle que l'exclusion par le
-- MJ : la page personnelle et le profil sont conservés, tandis que les
-- associations actives (notamment les attributions de butin) sont neutralisées.

create or replace function public.leave_campaign(p_campaign_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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

revoke all on function public.leave_campaign(uuid) from public, anon, authenticated;
grant execute on function public.leave_campaign(uuid) to authenticated;

