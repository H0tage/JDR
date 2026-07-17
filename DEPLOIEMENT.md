# Relations et code couleur — déploiement

Ce paquet est cumulatif. Il contient la terminologie française des factions, l’éditeur des textes et le nouveau code couleur éditable.

## 1. Mettre à jour Supabase en premier

Dans **Supabase > SQL Editor**, ouvrir puis exécuter uniquement le contenu de :

`supabase/migrations/20260717132000_relationship_color_overrides.sql`

Le résultat normal est : `Success. No rows returned`.

Cette migration est autonome : elle fonctionne que la migration précédente des textes personnalisés ait déjà été appliquée ou non.

## 2. Mettre à jour GitHub

Décompresser ce paquet, puis déposer les dossiers `src`, `supabase` et `tests` à la racine du dépôt `H0tage/JDR`, en acceptant le remplacement des fichiers existants.

Ne pas déposer le dossier extérieur `publication_relations_couleurs_v2` dans le dépôt.

GitHub Actions doit ensuite lancer automatiquement le build et le déploiement.

## 3. Vérifier

1. Ouvrir `/MJsecretscreen/`, puis l’onglet **Politique**.
2. Vérifier que la légende présente uniquement les trois couleurs et qu’aucune pastille `E`, `S` ou `H` n’apparaît dans la matrice.
3. Cliquer sur une relation, choisir une autre couleur et enregistrer.
4. Si la relation est publique, vérifier la même couleur dans `/playerscreen/`.
5. Tester **Reprendre le défaut** dans la section du code couleur.

Validation locale effectuée : 14 tests automatisés réussis et build de production réussi.
