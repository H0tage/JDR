# Registre des tests

Ce document est une lecture humaine des tests automatiques du projet.

Il est mis à jour à chaque ajout, suppression ou modification importante d'un test. Les intitulés décrivent le comportement vérifié, pas l'implémentation technique.

État au 4 septembre 2026 : **51 tests**, répartis dans 16 fichiers.

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

## Butins, inventaires et suivi économique

11. L'écran de butin affiche clairement trésorerie, compte commun, demandes et totaux sans devenir lourd.
12. Le gestionnaire de butins et les explications détaillées sont séparés dans deux onglets de premier niveau.
13. On peut ouvrir rapidement l'achat et l'historique d'un objet.
14. On peut sélectionner plusieurs objets pour une action groupée.
15. Une demande d'objet annulée disparaît immédiatement.
16. Un joueur qui crée une dette reste forcément impliqué dans cette dette.
17. Les inventaires des autres joueurs sont rangés dans des colonnes distinctes.
18. Le MJ voit une colonne d'inventaire pour chaque joueur.
19. L'option « Compter comme nouveau gain » est cochée par défaut lors de la création d'un objet MJ.
20. Les quatre monnaies Pathfinder sont correctement converties en pièces d'or pour le monitoring.
21. La valeur indiquée dans le livre et la valeur trouvée sur Archive of Nethys restent distinctes.
22. Les butins sont classés uniquement selon la nouvelle catégorisation propre.
23. Le gestionnaire de butin se charge sans provoquer d'erreur React.
24. Le filtre par volume affiche les lieux associés et masque les autres blocs.

## Économie : cohérence des données et calculs

25. Une base vide peut créer une campagne sans contenu privé.
26. Les objets sont protégés, l'argent peut être transféré, et les possessions d'un joueur partant reviennent correctement au groupe.
27. Gains cumulés, dépenses cumulées et patrimoine sont calculés séparément.
28. L'argent trouvé augmente les gains et le patrimoine.
29. Un objet trouvé augmente les gains selon sa valeur.
30. Une correction d'inventaire peut augmenter le patrimoine sans être comptée comme un gain.
31. Un achat crée une dépense monétaire, sans être considéré comme un gain.
32. Une auberge ou un service payé compte comme dépense.
33. Consommer, perdre ou donner un objet ne crée pas artificiellement une dépense.
34. Revendre au prix payé ne crée aucun gain.
35. Revendre plus cher ne compte que la plus-value comme gain.
36. Revendre moins cher ne diminue pas les gains cumulés.
37. Un transfert entre comptes ne change ni les gains ni les dépenses.
38. Annuler une vente ou une entrée retire correctement son effet des cumuls.
39. Revendre un objet gratuit compte entièrement comme un gain.
40. Acheter trois objets pour 1 pc garde une dépense de 1 pc, tout en donnant une valeur minimale de 1 pc à chaque objet.

## Pages joueurs, journal, relations et références

41. Un joueur peut ouvrir sa page personnelle et reçoit le rappel qu'elle est privée.
42. Le MJ ne voit pas l'onglet « Ma page » dans l'espace joueur.
43. Un joueur peut voir les fiches publiques des autres sans accéder à Pathbuilder ni aux notes MJ.
44. Un joueur ne peut pas ouvrir la vue MJ.
45. Les raccourcis du journal sont accessibles sous le navigateur de page.
46. Les contacts sont affichés par ordre alphabétique avec leur faction.
47. Le journal ne propose que les visibilités « MJ » et « Public ».
48. Les relations de démonstration restent génériques et sans spoilers.
49. Les jalons de démonstration sont anonymisés.
50. Les archives et butins de démonstration ne contiennent pas de vrai contenu de campagne.

## Sécurité et règles de réputation

51. Les données internes ne sont pas exposées : un visiteur anonyme ne peut pas lire les tables, les joueurs ne reçoivent ni notes MJ, ni contacts privés, ni sources internes, ni valeurs cachées, ni champs techniques de relations.

Les règles de réputation sont également couvertes par des cas internes : seuils configurés, tension non révélatrice, premier petit service gratuit, ordre de calcul tension/réputation, blocage après rupture et seuil spécial des Carters.
