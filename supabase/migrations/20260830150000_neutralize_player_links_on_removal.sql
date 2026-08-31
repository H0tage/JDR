-- Neutralise les associations actives avant de retirer un joueur.
--
-- La page personnelle et le profil restent volontairement conservés afin de
-- permettre une réadhésion sans perte. En revanche, aucune attribution de
-- butin ne doit continuer à pointer vers un ancien membre de la campagne.

-- Rattrapage des attributions déjà orphelines avant l'installation de la
-- nouvelle fonction de retrait. Les anciennes étiquettes Joueur1–4 ne sont
-- pas concernées : elles ne permettent pas d'identifier un compte réel.
update public.loot_player_publications publication
set owner_user_id = null,
    lifecycle_status = 'available',
    legacy_owner_label = null
where publication.owner_user_id is not null
  and not exists (
    select 1
    from public.campaign_members member
    where member.campaign_id = publication.campaign_id
      and member.user_id = publication.owner_user_id
      and member.role = 'player'
  );

create or replace function public.remove_campaign_player(
  p_campaign_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
