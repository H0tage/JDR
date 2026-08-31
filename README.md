# Les Registres de Geb

Application web de gestion de campagnes de jeu de rôle, actuellement centrée
sur **Pathfinder 2e — Blood Lords**. Elle sépare strictement les outils et les
informations du MJ de ce que les joueurs peuvent consulter ou modifier.

Le projet est une aide de jeu non officielle. Pathfinder et les noms associés
appartiennent à leurs ayants droit.

## Fonctionnement actuel

La page d’accueil fournit l’authentification et le portail **Mes campagnes**.
Un compte peut appartenir à plusieurs campagnes avec un rôle propre à chacune :
`gm` ou `player`. Le MJ invite les joueurs au moyen d’un lien révocable.

Les routes d’une campagne sont accessibles avec son slug court (par exemple
`blood-lords`) :

- `/campaign/<slug>/mj` pour l’espace MJ ;
- `/campaign/<slug>/playerscreen` pour l’espace joueurs ;
- `/join/<token>` pour accepter une invitation.

Les anciennes URLs basées sur l’identifiant UUID (`/campaign/<id>/…`) restent
acceptées pour préserver les signets et les liens déjà partagés.

Les anciennes routes restent utilisables pour les aperçus locaux :

- `/MJsecretscreen/?demo=1` ;
- `/playerscreen/?demo=1`.

Sans `?demo=1`, elles renvoient vers le portail afin d’éviter qu’une campagne
soit choisie implicitement.

## Fonctions principales

- réputation, faveurs, tension et services des six factions ;
- journal, préparation de séance et journal de quête partagé ;
- contacts, dettes, portraits et notes séparées MJ/joueurs ;
- politique directionnelle et quinze dossiers bilatéraux ;
- 77 jalons narratifs, choix exclusifs et résolution de leurs effets ;
- archives de personnages et de lieux ;
- butins de référence côté MJ et sélection limitée côté joueurs ;
- pseudos publics sans exposition des adresses e-mail ;
- page personnelle persistante par joueur et campagne, modifiable par son
  propriétaire et consultable en lecture seule par le MJ ;
- attribution des butins aux comptes réels de la campagne ;
- bestiaire collaboratif ;
- portail multi-campagnes, invitations, départ volontaire et gestion des membres ;
- thèmes Clair, Original et Sombre, avec affichage adaptatif côté joueurs.

## Développement local

Prérequis : Node.js 24 et npm.

Sous PowerShell :

```powershell
npm ci
Copy-Item .env.example .env.local
npm run dev
```

La valeur `VITE_SUPABASE_PUBLISHABLE_KEY` est la clé publique du projet. Ne
jamais placer de clé `service_role`, mot de passe PostgreSQL ou token personnel
dans un fichier `.env`, une variable `VITE_*` ou le dépôt.

Le mode démo fonctionne sans connexion à Supabase. Pour contrôler le projet :

```powershell
npm test
npm run build
```

La suite de tests rejoue toutes les migrations dans un PostgreSQL embarqué et
contrôle notamment les frontières MJ/joueurs, les invitations et les butins
partagés.

## Supabase

Le dossier [`supabase`](supabase) contient :

- `migrations/`, l’historique SQL à appliquer dans l’ordre ;
- `schema-remote.sql`, un instantané sans données du schéma de production ;
- `setup/assign_gm.sql`, l’attribution initiale du rôle MJ.

Avec la CLI lancée par npm sous Windows :

```powershell
npx.cmd supabase login
npx.cmd supabase link --project-ref ajrehwjevfttrxnztryr
npx.cmd supabase db push
```

La migration `20260830110000_campaign_portal_and_player_loot.sql` formalise
les ajouts qui avaient d’abord été appliqués manuellement dans le SQL Editor.
Elle est versionnée ici, mais n’est pas appliquée automatiquement à la base de
production par le déploiement GitHub Pages.

La migration `20260830130000_player_profiles_pages_and_loot_ownership.sql`
ajoute les pseudos, les pages personnelles et les propriétaires réels des
butins. Une page survit au retrait d’un membre et redevient accessible si le
même compte rejoint de nouveau la campagne. Seule la suppression de la
campagne la supprime normalement. Cette migration doit être appliquée avant de
déployer la version du client qui utilise ces nouvelles API.

Les migrations `20260830150000_neutralize_player_links_on_removal.sql` et
`20260830160000_allow_players_to_leave_campaigns.sql` neutralisent les
attributions actives lors d’un retrait par le MJ ou d’un départ volontaire du
joueur, tout en conservant sa page personnelle pour une éventuelle réadhésion.

Après une modification SQL distante, régénérer le snapshot comme indiqué dans
[`supabase/README.md`](supabase/README.md).

## Déploiement

Le workflow GitHub Actions exécute les tests, construit le site puis publie le
dossier `dist` sur GitHub Pages. Les variables de dépôt requises sont :

- `VITE_SUPABASE_URL` ;
- `VITE_SUPABASE_PUBLISHABLE_KEY`.

La procédure complète et les vérifications post-déploiement sont décrites dans
[`DEPLOIEMENT.md`](DEPLOIEMENT.md).

## Architecture et sécurité

- React, TypeScript et Vite pour le client ;
- Supabase pour PostgreSQL, Auth, Storage, RPC et RLS ;
- accès Supabase regroupés dans `src/lib` ;
- tables complètes protégées par RLS ;
- vues `player_*` limitées aux membres de la campagne et aux colonnes prévues
  pour les joueurs ;
- aucune donnée privée du MJ ne doit être seulement « cachée » en React ou CSS.

Le modèle conserve `campaign_id` et `user_id` explicitement afin de permettre
plusieurs campagnes et des rôles différents pour un même compte.
