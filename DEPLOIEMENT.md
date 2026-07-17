# Déploiement de `jdr.regalade.ch`

Ce projet affiche une seule campagne : **Blood Lords**. Le champ `campaign_id` permet une extension ultérieure, mais aucun sélecteur de campagne n’apparaît dans l’interface.

## 1. Installer la base Supabase

Depuis la racine du dépôt :

```bash
supabase login
supabase link --project-ref ajrehwjevfttrxnztryr
supabase db push
```

Les migrations sont appliquées dans cet ordre :

1. schéma, vues et politiques RLS ;
2. données Blood Lords et état initial du groupe ;
3. quinze dossiers politiques bilatéraux.

Créer ensuite le compte du MJ dans **Supabase Dashboard → Authentication → Users**, puis exécuter `supabase/setup/assign_gm.sql` dans le SQL Editor après avoir remplacé `REMPLACER-PAR-EMAIL-MJ`.

La clé `service_role` et le mot de passe PostgreSQL ne doivent jamais être placés dans le dépôt ou dans une variable `VITE_*`.

## 2. Publier sur GitHub Pages

Dans le dépôt GitHub :

1. créer les variables Actions `VITE_SUPABASE_URL` et `VITE_SUPABASE_PUBLISHABLE_KEY` ;
2. dans **Settings → Pages**, choisir **GitHub Actions** ;
3. pousser la branche `main` ou lancer manuellement le workflow **Deploy GitHub Pages**.

Le workflow installe les dépendances, construit les trois pages et publie `dist`.

Le dépôt `H0tage/JDR` étant privé, GitHub Pages demande un abonnement GitHub Pro, Team ou Enterprise. Avec GitHub Free, deux possibilités : rendre ce dépôt public ou publier le site depuis un second dépôt public.

## 3. Relier le sous-domaine

Avant toute modification DNS, ouvrir **Settings → Pages → Custom domain**, saisir `jdr.regalade.ch`, puis enregistrer. Chez Infomaniak, créer ensuite l’enregistrement :

| Type | Nom | Cible |
| --- | --- | --- |
| CNAME | `jdr` | `H0tage.github.io` |

Le fichier `public/CNAME` contient déjà `jdr.regalade.ch`, mais un workflow GitHub Actions exige malgré tout le réglage **Custom domain** dans GitHub. Une fois le DNS propagé, activer **Enforce HTTPS** si l’option n’est pas encore cochée.

## 4. Vérifications après publication

- `https://jdr.regalade.ch/` affiche l’entrée du registre ;
- `https://jdr.regalade.ch/MJsecretscreen/` demande une authentification ;
- `https://jdr.regalade.ch/playerscreen/` fonctionne sans compte ;
- les joueurs voient 5 RP et 5 JF auprès des Réanimateurs ;
- aucune relation politique n’est publique tant que le MJ ne la révèle pas ;
- une relation marquée **Prête à révéler** reste invisible des joueurs ;
- une relation marquée **Visible joueurs** apparaît après l’actualisation automatique.

## 5. Contrôles locaux

```bash
npm test
npm run build
```

La suite de tests exécute les migrations dans un PostgreSQL embarqué et vérifie notamment les permissions `anon`, les politiques MJ, les totaux initiaux et l’absence de colonnes privées dans les vues publiques.
