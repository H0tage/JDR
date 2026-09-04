-- Nom conseillé dans le SQL Editor : Audit intégrité économie — 2026-09-04
-- Lecture seule : cette requête ne modifie aucune donnée.

select 'demandes_pending_dupliquees' as controle, count(*)::bigint as anomalies
from (
  select item_id, requester_user_id from public.campaign_item_requests
  where status = 'pending' group by item_id, requester_user_id having count(*) > 1
) duplicates
union all
select 'demandes_pending_objet_inactif', count(*)
from public.campaign_item_requests request
join public.campaign_inventory_items item on item.id = request.item_id
where request.status = 'pending' and (item.status <> 'active' or item.owner_user_id is distinct from request.owner_user_id)
union all
select 'objets_proprietaire_hors_campagne', count(*)
from public.campaign_inventory_items item
where item.owner_user_id is not null and not exists (
  select 1 from public.campaign_members member
  where member.campaign_id = item.campaign_id and member.user_id = item.owner_user_id and member.role = 'player'
)
union all
select 'transactions_montant_invalide', count(*)
from public.campaign_money_transactions where amount_cp <= 0
union all
select 'objets_quantite_invalide', count(*)
from public.campaign_inventory_items where quantity <= 0;

