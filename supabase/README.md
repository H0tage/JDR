# Schéma Supabase de Regalade JDR

Ce dossier contient l'historique SQL de l'application ainsi qu'un instantané
du schéma réellement présent sur Supabase.

## Fichiers importants

- `migrations/` : évolutions SQL à conserver et appliquer dans l'ordre ;
- `reference/undead-creatures.csv` : source versionnée des mots autorisés pour les slugs de campagne ;
- `schema-remote.sql` : photographie sans données de la base de production au
  30 août 2026 ;
- `setup/assign_gm.sql` : aide ponctuelle pour attribuer le rôle de MJ.

Les migrations publiques ne contiennent volontairement aucun PNJ, lieu,
butin, jalon, synopsis ou autre donnée d’une campagne jouée. Les modèles et
jeux de données propres à un MJ doivent rester dans un paquet local privé,
ignoré par Git (par exemple `private-references/`). Une nouvelle installation
publique crée donc une campagne vide et fonctionnelle ; le MJ y ajoute son
contenu privé séparément.

L'instantané `schema-remote.sql` a été créé après une période où certaines
évolutions étaient appliquées directement via le SQL Editor Supabase. Il est
donc la référence pratique pour retrouver les vues, fonctions RPC, politiques
RLS et tables qui existent réellement, y compris les invitations de campagne
et les métadonnées de partage des butins.

La migration `20260830110000_campaign_portal_and_player_loot.sql` est la
version rejouable de ces ajouts manuels. Elle remet l’historique Git en accord
avec la production et resserre les droits : avant connexion, seul le détail
d’une invitation est consultable ; les autres RPC et les vues joueurs exigent
un compte membre de la campagne.

La migration `20260830130000_player_profiles_pages_and_loot_ownership.sql`
définit la frontière de confidentialité des pages personnelles : propriétaire
en écriture, MJ de la campagne en lecture seule, aucun accès pour les autres
joueurs. Le retrait d’un membre ne touche pas sa page ; l’acceptation ultérieure
d’une invitation avec le même compte rattache la page existante. Elle remplace
aussi les libellés `Joueur1` à `Joueur4` par de vraies références de compte,
sans perdre les anciennes valeurs qui sont conservées comme attributions
historiques jusqu’à leur réaffectation.

La migration `20260830150000_neutralize_player_links_on_removal.sql` conserve
ces pages personnelles mais neutralise les associations actives lorsqu’un
joueur est retiré : ses butins attribués redeviennent `available` et ne sont
plus liés à son compte. Elle rattrape également les attributions déjà
orphelines. Une réadhésion ultérieure restaure l’accès à la page, sans
réattribuer automatiquement les anciens butins.

La migration `20260830160000_allow_players_to_leave_campaigns.sql` ajoute le
départ volontaire côté joueur. Il applique exactement la même neutralisation
que le retrait par le MJ et refuse qu’un compte ayant le rôle `gm` quitte ainsi
la campagne.

La migration `20260830170000_campaign_slug_words.sql` installe les 244 noms de
morts-vivants utilisés pour les futures URL de campagne et la fonction interne
`generate_available_campaign_slug()`. La fonction privilégie une paire ordonnée
de noms distincts (`vampire-bonegolem`), puis utilise trois noms distincts si
toutes les paires sont déjà prises. Le catalogue et la fonction ne sont pas
appelables directement par les rôles clients : la future RPC de création de
campagne les utilisera dans une transaction contrôlée.

Le bloc d’insertion de cette migration est généré depuis le CSV. Après toute
modification du référentiel, régénérer la migration puis lancer les tests :

```powershell
npm run generate:campaign-slugs
npm test -- --run tests/database.integration.test.ts
```

Ne pas corriger directement les lignes `INSERT` générées : le CSV reste la
source de vérité. Les slugs des mots composés n’ont pas de séparateur interne
(`Bone Golem` devient `bonegolem`) ; seul le tiret entre les créatures apparaît
dans l’URL.

La migration `20260830180000_campaign_creation_and_ownership.sql` ajoute la
création autonome depuis le portail. Elle attribue un propriétaire explicite,
crée son adhésion MJ et les réglages dans une seule transaction. Le premier MJ
déjà rattaché à une ancienne campagne en devient automatiquement propriétaire.
Les factions et référentiels spécifiques sont, eux, fournis seulement par un
paquet de campagne privé.

La suppression définitive passe par `delete_owned_campaign()` et n’est permise
qu’au propriétaire. Toutes les données liées à la campagne sont supprimées par
les clés étrangères `on delete cascade`, ce qui libère immédiatement son slug.
L’application retire auparavant les images des buckets `bestiary-images`,
`contact-portraits` et `quest-journal-images`, pendant que les politiques de
stockage reconnaissent encore le propriétaire comme membre de la campagne.

La migration `20260830190000_campaign_portal_details.sql` enrichit le tableau
de bord avec la date de création et permet au propriétaire de modifier le nom
et la description via `update_owned_campaign()`, sans ouvrir l’écriture directe
sur la table `campaigns`. Elle autorise aussi tous les membres d’une campagne à
consulter la liste limitée aux pseudos et rôles de leur groupe ; les adresses
e-mail restent absentes de cette vue.

La migration `20260902120000_player_inventory_and_economy.sql` ajoute les
objets opérationnels, le registre financier, les demandes d’objets, les dettes
et leurs vues filtrées. Les opérations passent par des fonctions contrôlées ;
les annulations ajoutent une écriture inverse au lieu de réécrire l’historique.
Le départ d’un joueur rend ses objets au pot commun et y transfère aussi son
solde positif ou négatif ainsi que ses dettes encore ouvertes.

Tant que cette migration n’a pas été appliquée à la production,
`schema-remote.sql` doit continuer à représenter la production actuelle. Il ne
faut mettre l’instantané à jour qu’après l’exécution distante et sa vérification.

## Règle de travail à partir de maintenant

Toute modification de structure, de fonction SQL, de vue, de politique RLS ou
de droit doit être enregistrée dans un nouveau fichier de migration avant ou
au moment de son application dans le SQL Editor. Après une modification
réussie de la base distante, régénérer l'instantané :

```powershell
npx.cmd supabase db dump --linked --schema public -f supabase/schema-remote.sql
```

Puis vérifier le diff Git et committer ensemble la migration et l'instantané.
Le dump est une référence de contrôle ; une migration est le mécanisme normal
pour faire évoluer une base existante. Ne pas exécuter tout le dump sur la
base de production pour une simple modification.

## Continuité du projet

L'application est une aide de jeu React, TypeScript et Vite. Supabase fournit
PostgreSQL, Auth, les fonctions RPC et les politiques RLS. Elle distingue les
données complètes du MJ des données partagées avec les joueurs, et prévoit un
utilisateur membre de plusieurs campagnes avec un rôle par campagne (`gm` ou
`player`).

Ne jamais committer de mot de passe PostgreSQL, token personnel Supabase,
clé `service_role`, export de données de campagne, ni contenu des schémas
gérés `auth` ou `storage`.

Pour une sauvegarde complète à conserver hors GitHub, exporter les données
dans un fichier séparé, chiffré et privé. Le dépôt ne doit garder que le
schéma et les migrations.
