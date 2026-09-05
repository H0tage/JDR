# Registre des tests

Ce document est une lecture humaine des tests automatiques du projet.

Il est mis à jour à chaque ajout, suppression ou modification importante d'un test. Les intitulés décrivent le comportement vérifié, pas l'implémentation technique.

État au 5 septembre 2026 : **54 tests**, répartis dans 16 fichiers.

## Accès, routes et démonstration

1. La démo MJ s'ouvre même avec l'ancienne URL et des majuscules.
2. La démo joueur s'ouvre avec l'ancienne URL.
3. L'accueil déconnecté propose bien les deux démos.
4. La démo remplace les vrais noms, factions et références sans modifier les données d'origine.
5. Les numéros de butin sont identiques dans la démo MJ et la démo joueur.
6. L'écran MJ fonctionne avec l'URL complète de la campagne.
7. L'écran MJ fonctionne aussi avec le slug court de campagne.
8. Une personne sans accès ne peut pas savoir qu'une campagne existe.

## Bestiaire

9. Un joueur peut ajouter et modifier une créature, mais pas la supprimer ni décider de sa visibilité.
10. Le MJ peut révéler, masquer et supprimer les créatures.
11. Les six volumes de la feuille de route restent visibles en permanence dans l’espace MJ, avec le volume actif mis en avant, sans commande de masquage.

## Butins, inventaires et suivi économique

12. L'écran de butin affiche clairement trésorerie, compte commun, demandes et totaux sans devenir lourd ; l'auteur d'un ordre est identifié et tout compte MJ est présenté comme « Maître du Jeu ».
13. Le gestionnaire de butins et les explications détaillées sont séparés dans deux onglets de premier niveau.
14. Envoyer un objet demande un destinataire, une quantité et une confirmation directement dans la carte concernée ; le menu se ferme aussi par clic extérieur.
15. On peut ouvrir rapidement l'achat et l'historique d'un objet.
16. On peut sélectionner plusieurs objets pour une action groupée.
17. Une demande d'objet annulée disparaît immédiatement.
18. Un joueur qui crée une dette reste forcément impliqué dans cette dette.
19. Les inventaires des autres joueurs sont rangés dans des colonnes distinctes.
20. Le MJ voit une colonne d'inventaire pour chaque joueur.
21. L'option « Compter comme nouveau gain » est cochée par défaut lors de la création d'un objet MJ.
22. Les quatre monnaies Pathfinder sont correctement converties en pièces d'or pour le monitoring.
23. La valeur indiquée dans le livre et la valeur trouvée sur Archive of Nethys restent distinctes.
24. Les butins sont classés uniquement selon la nouvelle catégorisation propre.
25. « Acquis » révèle automatiquement un butin, « À découvrir » et « Manqué » le masquent, puis l’œil peut modifier librement sa visibilité sans changer son statut.
26. Le filtre par volume affiche les lieux associés et masque les autres blocs.

## Économie : cohérence des données et calculs

27. Une base vide installe les 225 références d’équipement PF2e, avec leur type, leur lien AoN et les prix connus convertis en pièces de cuivre, puis peut créer une campagne sans contenu privé.
28. Les objets sont protégés, l'argent peut être transféré, les possessions d'un joueur partant reviennent correctement au groupe, et le MJ peut annuler un envoi partiel tant que l'objet n'a pas changé depuis.
29. Gains cumulés, dépenses cumulées et patrimoine sont calculés séparément.
30. L'argent trouvé augmente les gains et le patrimoine.
31. Un objet trouvé augmente les gains selon sa valeur.
32. Une correction d'inventaire peut augmenter le patrimoine sans être comptée comme un gain.
33. Un achat crée une dépense monétaire, sans être considéré comme un gain.
34. Une auberge ou un service payé compte comme dépense.
35. Consommer, perdre ou donner un objet ne crée pas artificiellement une dépense.
36. Revendre au prix payé ne crée aucun gain.
37. Revendre plus cher ne compte que la plus-value comme gain.
38. Revendre moins cher ne diminue pas les gains cumulés.
39. Un transfert entre comptes ne change ni les gains ni les dépenses.
40. Annuler une vente ou une entrée retire correctement son effet des cumuls.
41. Revendre un objet gratuit compte entièrement comme un gain.
42. Acheter trois objets pour 1 pc garde une dépense de 1 pc, tout en donnant une valeur minimale de 1 pc à chaque objet.

## Pages joueurs, journal, relations et références

43. Un joueur peut ouvrir sa page personnelle et reçoit le rappel qu'elle est privée.
44. Un PJ peut choisir un titre facultatif affiché en doré sous son nom, ainsi que zoomer, centrer et réinitialiser son portrait ; ces choix sont conservés dans les vues joueur et MJ.
45. Le MJ ne voit pas l'onglet « Ma page » dans l'espace joueur.
46. Un joueur peut voir les fiches publiques des autres sans accéder à Pathbuilder ni aux notes MJ.
47. Un joueur ne peut pas ouvrir la vue MJ.
48. Les raccourcis du journal sont accessibles sous le navigateur de page.
49. Les contacts sont affichés par ordre alphabétique avec leur faction.
50. Le journal ne propose que les visibilités « MJ » et « Public ».
51. Les relations de démonstration restent génériques et sans spoilers.
52. Les jalons de démonstration sont anonymisés.
53. Les archives et butins de démonstration ne contiennent pas de vrai contenu de campagne.

## Sécurité et règles de réputation

54. Les données internes ne sont pas exposées : un visiteur anonyme ne peut pas lire les tables, les joueurs ne reçoivent ni notes MJ, ni contacts privés, ni sources internes, ni valeurs cachées, ni champs techniques de relations.

Les règles de réputation sont également couvertes par des cas internes : seuils configurés, tension non révélatrice, premier petit service gratuit, ordre de calcul tension/réputation, blocage après rupture et seuil spécial des Carters.
