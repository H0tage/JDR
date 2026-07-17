# Correctif de l’interface Progression

La migration Supabase a déjà été exécutée : il n’est pas nécessaire de la
relancer pour corriger les cartes.

## Fichiers à déposer dans GitHub

1. Extraire le ZIP sur l’ordinateur.
2. Ouvrir le dossier extrait `publication_progression`.
3. Dans le dépôt GitHub `H0tage/JDR`, choisir **Add file → Upload files**.
4. Déposer les dossiers `src`, `supabase` et `tests` — pas le ZIP lui-même et
   pas le dossier extérieur `publication_progression`.
5. Vérifier avant le commit que GitHub annonce notamment le remplacement de :
   - `src/components/GmApp.tsx`
   - `src/styles.css`
   - `src/lib/api.ts`
   - `src/lib/types.ts`
   - `src/data/mockData.ts`
6. Valider le commit sur `main`, puis attendre la coche verte de l’action
   **Deploy GitHub Pages**.

## Contrôle rapide

Après le déploiement, actualiser `/MJsecretscreen/` avec `Ctrl+F5`.

La section Progression correcte présente :

- des cartes intitulées `Volume 1` à `Volume 6` ;
- un clic sur une carte qui filtre immédiatement la table ;
- les états `En attente`, `Réussi`, `Manqué` et `Écarté` ;
- un bouton `Résoudre` sur les jalons en attente.

Si les cartes affichent encore « Présenter les factions » ou « Introduire les
Convoyeurs », le fichier `src/components/GmApp.tsx` n’a pas été remplacé dans
le dépôt ou le déploiement GitHub Pages n’est pas encore terminé.
