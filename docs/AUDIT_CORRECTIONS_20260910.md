# Corrections de l’audit — premier lot, 10 septembre 2026

## Livré localement

- Nettoyage du HTML du journal avant chaque injection à l’écran, en plus du nettoyage avant sauvegarde.
- Annulation du démontage refusée si un composant n’est plus actif ou a été modifié ; verrouillage des composants durant le contrôle.
- Classement des notes transactionnel, sans réécriture du texte, avec refus des positions périmées.
- Focus et fermeture par Échap pour l’éditeur et l’agrandissement du bestiaire ; défilement arrière bloqué.
- Même comportement pour le zoom des personnages, les contacts joueurs, la confirmation des archives et la résolution des jalons ; prise en charge des fenêtres superposées.
- Les chargements principaux MJ, joueurs et économie ignorent les réponses périmées.
- Fond sans dégradé pour les images manquantes du bestiaire, respect du thème et des préférences de mouvement réduit.
- Noms accessibles des choix de thème MJ sur mobile.
- Actualisation économique suspendue dans une page masquée et reprise au retour.
- Chargement séparé des interfaces MJ et joueurs.
- Protection de la redirection de version contre les boucles sur la même version et contre une saisie commencée durant le contrôle.
- Versions auparavant « latest » figées sur les versions déjà installées, sans mise à niveau.
- Tests et compilation ajoutés aux demandes de fusion, sans déploiement depuis celles-ci.

## Déploiement

Appliquer **avant le déploiement du frontend**, dans cet ordre :

1. `supabase/migrations/20260910120000_guard_dismantle_cancellation.sql`
2. `supabase/migrations/20260910121000_atomic_note_order.sql`

La seconde migration est nécessaire au déplacement des notes du nouveau frontend.
Les migrations ne suppriment aucune donnée. Elles sont testées sur une base locale vierge avec toute la chaîne historique des migrations.
Elles n’ont pas été appliquées à la production pendant ce travail.

## Vérification

- 69 tests dans 21 fichiers ; registre humain mis à jour.
- Compilation de production réussie ; plus d’avertissement de gros bloc JavaScript.
- Aucun push ni déploiement effectué.

## Reste à traiter séparément

- Vérification visuelle exhaustive de toutes les vues (au-delà des formulaires échantillonnés).
- Vérification des permissions effectives de production avant leur réduction.
- Tests navigateur multi-utilisateurs, captures comparatives et validation des cadrages.

Les ajouts fonctionnels de l’audit (pagination visible, recherche étendue, sélecteur d’équipement, repli des notes, notification de mise à jour) restent hors de ce lot.

## Suite : thèmes et fenêtres

- Toutes les fenêtres modales restantes utilisent `ModalFrame`, qui partage la gestion du focus avec les fenêtres déjà corrigées.
- Récupération et conflit du journal : choix explicite conservé, sans fermeture accidentelle par Échap.
- Palettes regroupées dans `src/themes.css` ; 151 règles clair/sombre utilisent désormais les variables centrales, sans changement volontaire de leurs couleurs.
- Champs, titres, boutons secondaires et zones défilantes des fenêtres partagent les mêmes règles.
- Contrôle visuel local : formulaire du bestiaire joueur dans les trois thèmes ; formulaire du journal MJ en clair. Aucun enregistrement de données lors de ces contrôles.
- Aucun push ni déploiement.

## Suite du 11 septembre

- DOMPurify 3.4.15 complète le nettoyage propre au journal ; tests contre les charges SVG/MathML et les URL encodées.
- Vitest passe à 4.1.11 : le correctif retire les deux alertes de sécurité des dépendances. L’installation signale zéro vulnérabilité connue.
- Bestiaire, notes et journal HTML (avec ses vingt versions) sont chargés selon la rubrique ouverte. Les compteurs de l’accueil joueur conservent leurs données nécessaires.
- Une erreur de lecture du journal n’est plus transformée silencieusement en page vide.
- La page personnelle attend sa première ouverture pour charger ses données, puis reste montée pour préserver les saisies.
- Bestiaire : emplacement sans illustration réduit à 160 px ; carte d’ajout moins haute. Les illustrations existantes conservent leur cadrage.
- Menu MJ mobile : nom accessible, état annoncé, focus contenu et fermeture avec Échap ; menu fermé retiré de la navigation clavier.
- Contrôles navigateur locaux en démonstration : 96 combinaisons rubrique/thème/taille (390×844 et 1440×900), sans débordement horizontal de la page ni rubrique absente. Il s’agit de contrôles de structure/navigation, pas d’une certification visuelle exhaustive ni de tests d’écriture multi-utilisateurs.
- Script en lecture seule pour les permissions : `supabase/diagnostics/20260910_permissions_readonly.sql`. Aucun accès SQL distant disponible ; ce contrôle n’a pas été exécuté en production.

Restent dépendants d’un environnement connecté : permissions effectives distantes et parcours navigateur authentifiés avec plusieurs comptes de test. Aucun changement de permissions n’a été appliqué.

## Derniers cas limites vérifiés

- La migration de démontage associe les nouveaux événements à la liste exacte de leurs composants (`dismantle_output_ids`). Les composants d’une annulation précédente ne bloquent plus un nouveau démontage intact.
- Pour les événements historiques sans cette liste, le contrôle reste conservateur et utilise la date de création des composants.
- Le classement du carnet refuse aussi une liste périmée après l’ajout d’une note, sans appliquer une partie du déplacement.
- Les contrôles retirés de l’ordre de tabulation (`tabindex=-1`) ne sont plus inclus dans le cycle Tab des fenêtres.
- Tests de base étendus pour les annulations répétées et les notes ajoutées ailleurs.

## Préparation du push du 11 septembre

- L’utilisateur confirme l’exécution réussie du script SQL combiné (`Success. No rows returned`).
- Vérification finale locale : 69 tests dans 21 fichiers réussis, compilation de production réussie.
- Les mentions d’absence de push ci-dessus décrivent les étapes précédentes de l’audit. Le déploiement effectif et les permissions distantes ne sont pas vérifiés par ces tests locaux.
