-- 1. Créez d'abord l'utilisateur MJ dans Supabase Dashboard > Authentication > Users.
-- 2. Remplacez l'adresse ci-dessous, puis exécutez ce fichier une seule fois
--    dans Supabase Dashboard > SQL Editor.

insert into public.campaign_members (campaign_id, user_id, role)
select c.id, u.id, 'gm'
from public.campaigns c
cross join auth.users u
where c.slug = 'blood-lords'
  and lower(u.email) = lower('REMPLACER-PAR-EMAIL-MJ')
on conflict (campaign_id, user_id) do update set role = excluded.role;

-- Vérification : cette requête doit retourner une ligne.
select c.name as campagne, u.email, cm.role
from public.campaign_members cm
join public.campaigns c on c.id = cm.campaign_id
join auth.users u on u.id = cm.user_id
where c.slug = 'blood-lords';
