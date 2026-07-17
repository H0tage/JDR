# Les Registres de Geb

Gestionnaire web de réputation, faveurs et politique pour **Pathfinder Adventure Path: Blood Lords**.

L’application contient deux surfaces distinctes :

- `/MJsecretscreen/` : interface authentifiée du MJ ;
- `/playerscreen/` : vue publique qui ne lit que des vues PostgreSQL expurgées.

Le projet est une aide de jeu non officielle. Pathfinder et les noms associés appartiennent à leurs ayants droit.

## Fonctions principales

- journal unique des variations de RP, JF et Tension ;
- tableau de bord des six factions ;
- catalogue et calculateur de services ;
- contacts, promesses, dettes et conséquences ;
- matrice politique directionnelle enrichie ;
- 15 dossiers bilatéraux jouables ;
- registre de 77 jalons officiels vérifiés sur les six volumes ;
- filtre par volume et états `En attente`, `Réussi`, `Manqué`, `Écarté` ;
- résolution des récompenses variables et choix de faction directement dans l’interface ;
- exclusion automatique des branches incompatibles, avec annulation propre en cas de changement de choix ;
- publication élément par élément : `MJ uniquement` ou `Visible joueurs` ;
- actualisation automatique de la vue joueurs ;
- impression de la vue publique.

## Développement local

Prérequis : Node.js 24 et npm.

```bash
npm install
cp .env.example .env.local
npm run dev
```

Renseigner dans `.env.local` :

```text
VITE_SUPABASE_URL=https://ajrehwjevfttrxnztryr.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=la-cle-publique-du-projet
```

Les écrans peuvent être vérifiés avant l’installation de la base :

- `http://localhost:5173/MJsecretscreen/?demo=1`
- `http://localhost:5173/playerscreen/?demo=1`

## Installation Supabase

Le dossier `supabase/migrations` contient le schéma, les politiques RLS et les données Blood Lords.

```bash
supabase login
supabase link --project-ref ajrehwjevfttrxnztryr
supabase db push
```

Sur une installation déjà en ligne, exécuter seulement les nouvelles migrations,
dans l’ordre de leur nom. Pour cette évolution de la progression :

```text
supabase/migrations/20260717133000_progression_overhaul.sql
```

Le registre suit les **jalons narratifs finis**. Les activités génériques et
répétables de temps mort du volume 4, ainsi que les sanctions libres décidées
par le MJ, restent à saisir dans le journal ordinaire.

Ensuite :

1. créer le compte MJ dans **Supabase Dashboard → Authentication → Users** ;
2. ouvrir `supabase/setup/assign_gm.sql` ;
3. remplacer `REMPLACER-PAR-EMAIL-MJ` ;
4. exécuter le script dans **SQL Editor** ;
5. vérifier qu’une ligne MJ est retournée.

Ne jamais placer une clé `service_role` dans le navigateur, le dépôt ou les variables `VITE_*`.

## Déploiement GitHub Pages

Dans **Settings → Secrets and variables → Actions → Variables**, créer :

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

Dans **Settings → Pages**, choisir **GitHub Actions** comme source. Le workflow `.github/workflows/deploy-pages.yml` construit et publie les trois points d’entrée.

Le dépôt actuel étant privé, GitHub Pages nécessite un compte GitHub Pro, Team ou Enterprise. Avec GitHub Free, il faut publier depuis un dépôt public.

Dans **Settings → Pages → Custom domain**, enregistrer `jdr.regalade.ch` avant de créer le DNS. Chez Infomaniak, le CNAME `jdr` devra ensuite pointer vers `H0tage.github.io`. Le fichier `public/CNAME` documente également ce domaine, mais ne remplace pas ce réglage lors d’un déploiement par GitHub Actions.

## Sécurité

La sécurité ne repose pas sur l’URL secrète ni sur des champs cachés en JavaScript :

- les tables de travail n’accordent aucun droit au rôle `anon` ;
- les politiques RLS limitent le compte authentifié aux campagnes dont il est MJ ;
- la vue joueurs utilise uniquement `player_campaign`, `player_faction_overview`, `player_contacts`, `player_services`, `player_relationships` et `player_journal` ;
- ces vues ne contiennent aucune colonne de notes, conséquence ou dossier MJ.

## Vérification

```bash
npm test
npm run build
```
