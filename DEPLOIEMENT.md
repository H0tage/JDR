# Éditeur des textes de relations — déploiement

Ce paquet est cumulatif : il contient aussi la terminologie française des factions déjà validée.

## 1. Mettre à jour Supabase en premier

Dans **Supabase > SQL Editor**, ouvrir puis exécuter le contenu de :

`supabase/migrations/20260717131000_relation_text_overrides.sql`

Le résultat normal est : `Success. No rows returned`.

La migration ajoute deux champs de personnalisation facultatifs et recrée les vues MJ/joueur. Les textes existants restent les valeurs par défaut.

## 2. Mettre à jour GitHub

Décompresser ce paquet, puis déposer les dossiers `src`, `supabase` et `tests` à la racine du dépôt `H0tage/JDR` en acceptant le remplacement des fichiers existants.

Ne pas déposer le dossier extérieur `publication_editeur_relations_v1` dans le dépôt.

GitHub Actions doit ensuite lancer automatiquement le build et le déploiement.

## 3. Vérifier

1. Ouvrir `/MJsecretscreen/`, puis l'onglet **Politique**.
2. Cliquer sur une relation de la matrice.
3. Modifier son titre ou son descriptif, choisir sa visibilité et enregistrer.
4. Si elle est publique, vérifier son texte final dans `/playerscreen/`.
5. Revenir dans l'éditeur et tester **Reprendre le défaut**.

Validation locale effectuée : 14 tests automatisés réussis et build de production réussi.
