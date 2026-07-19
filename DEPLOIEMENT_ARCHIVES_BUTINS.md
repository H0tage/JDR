# Installation — Archives et Butins

Cette mise à jour ajoute deux pages exclusivement réservées au MJ :

- **Archives** : 233 personnages et 307 lieux, avec recherche, filtre par volume, traductions facultatives et édition en ligne ;
- **Butins** : 406 entrées dans l’ordre de découverte, avec recherche, filtre par volume et édition en ligne.

Les ajouts, modifications et suppressions sont propres à la campagne. Chaque page possède un bouton de restauration qui remet intégralement ses données dans leur état d’origine.

## 1. Exécuter le SQL dans Supabase

Cette étape doit être faite **avant** de publier les fichiers du site.

1. Ouvrir le projet Supabase.
2. Aller dans **SQL Editor** puis créer une nouvelle requête.
3. Copier tout le contenu de `Supabase_Archives_Butins.sql`.
4. Exécuter la requête.

Le script peut être relancé sans créer de doublons. Il ne remplace pas les réglages Supabase déjà présents et ne touche pas aux tables de réputation existantes.

## 2. Ajouter les fichiers au dépôt GitHub

Décompresser `Mise_a_jour_Archives_Butins.zip` à la racine d’une copie du dépôt, en autorisant le remplacement des fichiers portant le même nom. Ne pas supprimer les autres fichiers du projet.

Fichiers ajoutés :

- `src/components/ReferenceTables.tsx`
- `src/data/referenceSeed.ts`
- `src/lib/referenceApi.ts`
- `supabase/migrations/20260719120000_archives_and_loot.sql`
- `tests/reference-tables.test.tsx`

Fichiers modifiés :

- `src/components/GmApp.tsx`
- `src/lib/types.ts`
- `src/styles.css`
- `tests/database.integration.test.ts`

Il n’est pas nécessaire de modifier les variables GitHub, le workflow GitHub Pages, le domaine ou les fichiers `.env`.

## 3. Publier

1. Valider les neuf fichiers ci-dessus dans le dépôt.
2. Attendre que **Build and deploy** passe au vert dans l’onglet **Actions**.
3. Recharger la page MJ, de préférence avec `Ctrl+F5` lors du premier essai.

Les deux nouvelles entrées **Archives** et **Butins** apparaîtront dans le menu de gauche du MJ. La vue des joueurs n’est pas modifiée.

## Lecture des traductions dans Archives

- texte normal : traduction attestée dans une source existante ;
- texte bleu : traduction proposée par le site ;
- texte doré avec une plume : traduction personnalisée par le MJ.

Le réglage **Afficher les traductions françaises**, placé sous le tableau des archives, masque ou affiche la colonne traduite pour toute la campagne.
