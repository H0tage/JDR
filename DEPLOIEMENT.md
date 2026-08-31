# Déploiement de `jdr.regalade.ch`

## 1. Vérifier le projet

Depuis la racine du dépôt :

```powershell
npm ci
npm test
npm run build
```

Le déploiement GitHub exécute les mêmes tests avant de construire le site.

## 2. Mettre le schéma Supabase à niveau

Le site et la base sont déployés séparément. GitHub Pages ne lance aucune
migration SQL.

```powershell
npx.cmd supabase login
npx.cmd supabase link --project-ref ajrehwjevfttrxnztryr
npx.cmd supabase migration list --linked
npx.cmd supabase db push
```

Avant `db push`, lire le diff des nouvelles migrations et sauvegarder la base.
Ne jamais réexécuter `schema-remote.sql` sur la production : ce fichier est un
instantané de contrôle, pas une migration.

Pour initialiser un nouveau MJ :

1. créer son compte dans **Supabase → Authentication → Users** ;
2. ouvrir `supabase/setup/assign_gm.sql` ;
3. remplacer l’adresse factice ;
4. exécuter le script dans le SQL Editor ;
5. vérifier la ligne retournée.

## 3. Configurer GitHub Pages

Dans **Settings → Secrets and variables → Actions → Variables**, définir :

- `VITE_SUPABASE_URL` ;
- `VITE_SUPABASE_PUBLISHABLE_KEY`.

Dans **Settings → Pages**, choisir **GitHub Actions**. Un push sur `main` lance
`.github/workflows/deploy-pages.yml` : installation, tests, build et publication.

Pour le domaine personnalisé, enregistrer `jdr.regalade.ch` dans GitHub avant
de créer chez Infomaniak :

| Type | Nom | Cible |
| --- | --- | --- |
| CNAME | `jdr` | `H0tage.github.io` |

Le fichier `public/CNAME` doit rester présent. Activer **Enforce HTTPS** après
la propagation DNS.

## 4. Configurer les redirections Supabase Auth

Dans les réglages URL de Supabase Auth, autoriser au minimum :

- `https://jdr.regalade.ch/auth/callback` ;
- `http://localhost:5173/auth/callback` pour le développement.

GitHub Pages renvoie les routes profondes par `404.html`. Le script restaure la
route avant le chargement de l’application afin que Supabase puisse lire le
paramètre `code` ou le fragment de récupération de mot de passe.

## 5. Contrôles après publication

- `/` affiche l’authentification ou **Mes campagnes** ;
- un lien `/join/<token>` décrit la campagne et permet de la rejoindre ;
- un MJ ouvre `/campaign/<id>/mj` ;
- un joueur membre ouvre `/campaign/<id>/playerscreen` ;
- un utilisateur extérieur ne voit aucune donnée de la campagne ;
- `/MJsecretscreen/?demo=1` et `/playerscreen/?demo=1` ouvrent les aperçus ;
- une invitation révoquée ou expirée affiche un état explicite ;
- un butin rendu visible apparaît côté joueurs sans exposer sa fiche MJ.

## 6. Sauvegarde du schéma

Après une évolution SQL appliquée avec succès :

```powershell
npx.cmd supabase db dump --linked --schema public -f supabase/schema-remote.sql
```

Committer la nouvelle migration et l’instantané ensemble. Conserver les dumps
de données hors du dépôt, chiffrés et privés.
