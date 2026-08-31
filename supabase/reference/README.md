# Référentiel des slugs de campagne

`undead-creatures.csv` est la source de vérité pour les noms utilisés dans les
identifiants publics de campagne. Ses colonnes sont :

- `id` : entier continu, stable dans la version courante du catalogue ;
- `creature` : libellé lisible ;
- `slug` : forme ASCII en minuscules, sans espace ni ponctuation ;
- `univers_categorie` : provenance ou catégorie éditoriale du nom.

## Règles de qualité

- un nom par ligne et un slug unique par nom ;
- uniquement `a-z` et `0-9` dans `slug` ;
- les mots composés sont concaténés (`bonegolem`) ;
- aucune mention de version, de numéro de jeu ou commentaire éditorial dans le nom ;
- les variantes réellement distinctes peuvent avoir chacune leur ligne ;
- après suppression ou ajout, trier les créatures par ordre alphabétique et
  réordonner les IDs de 1 à N.

## Synchronisation SQL

Depuis la racine du projet :

```powershell
npm run generate:campaign-slugs
```

La commande valide les IDs et les slugs, puis régénère
`supabase/migrations/20260830170000_campaign_slug_words.sql`. Le fichier SQL est
volontairement versionné afin de pouvoir être exécuté depuis le SQL Editor de
Supabase sans dépendre d’un import CSV local.
