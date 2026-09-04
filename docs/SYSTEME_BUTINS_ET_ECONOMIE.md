# Système de butins, inventaires et économie

Ce document explique le fonctionnement du système de butins de la campagne. Il est destiné au groupe : il décrit les règles visibles dans l'outil et leur logique, sans exiger de connaître le code ou la base de données.

L'objectif est de rendre la gestion fluide pendant et entre les séances : savoir ce qui a été découvert, qui possède quoi, où est passé l'argent et quelle est la valeur de l'aventure, sans transformer la partie en tableur.

## Les trois espaces de l'inventaire

Chaque objet actif appartient à l'un de ces espaces :

- **Compte commun** : les objets découverts et pas encore attribués. C'est le sac du groupe.
- **Mes objets** : ce que possède le personnage connecté.
- **Inventaires du groupe** : les objets possédés par les autres joueurs. Sur ordinateur, chaque joueur est présenté dans sa propre colonne ; sur mobile, un sélecteur permet d'afficher un inventaire à la fois.

Le MJ voit l'ensemble de ces inventaires. Un joueur voit son inventaire, le compte commun et les inventaires des autres personnages, mais ses droits d'action restent volontairement limités.

## D'où viennent les objets

### Butin de campagne révélé par le MJ

Le MJ dispose de la liste de butins construite à partir des volumes de Blood Lords. Lorsqu'il révèle un élément, celui-ci devient un objet actif et visible dans le compte commun des joueurs. L'objet conserve son contexte de campagne : volume, lieu, type de butin, quantité, valeur éventuellement indiquée dans le livre et lien Archive of Nethys lorsqu'il existe.

Le MJ peut ainsi révéler rapidement les récompenses d'une scène sans devoir les ressaisir à la main.

### Objet créé manuellement par le MJ

Le MJ peut créer un objet qui n'existait pas dans la liste : improvisation, correction, récompense spéciale ou objet personnel déjà en possession d'un personnage.

Lors de cette création, la case **« Compter comme nouveau gain »** est cochée par défaut.

- Cochée : l'objet représente une nouvelle richesse arrivée dans l'aventure ; sa valeur entre dans les gains cumulés.
- Décochée : c'est une correction ou une régularisation d'inventaire ; l'objet entre dans le patrimoine actuel, mais pas dans les gains cumulés.

Le MJ peut le placer directement dans le compte commun ou dans l'inventaire d'un joueur.

### Achat boutique

Un joueur peut enregistrer un achat en indiquant le nom de l'objet, sa quantité, son prix, une éventuelle référence Archive of Nethys et la part payée par son compte personnel ou le compte commun.

L'objet acheté arrive directement dans son inventaire. L'achat est une sortie d'argent réelle : il compte dans les dépenses cumulées, mais ne compte pas comme un gain.

La valeur enregistrée de chaque exemplaire est calculée à partir du prix réellement payé. Cas particulier assumé : si trois objets sont achetés pour 1 pc, chacun reçoit une valeur minimale de 1 pc pour pouvoir être suivi et revendu proprement, tandis que la dépense réelle reste bien de 1 pc.

## Attribuer, donner et demander un objet

### Attribution directe

Un objet du compte commun peut être attribué à n'importe quel joueur actif par n'importe quel membre du groupe. L'action ouvre un panneau : destinataire, quantité à envoyer et bouton de confirmation. Une pile de trois potions peut donc être partagée sans déplacer automatiquement les trois exemplaires.

Un joueur peut aussi donner un objet qu'il possède à un autre joueur, ou le remettre dans le compte commun.

En revanche, un joueur ne peut jamais prendre, déplacer ou dépenser un objet possédé par un autre joueur. Le MJ peut gérer tous les objets.

### Demande d'objet

Lorsqu'un objet appartient à quelqu'un d'autre, un joueur peut le **demander**.

1. Le demandeur crée la demande depuis la carte de l'objet.
2. Le propriétaire reçoit une demande en attente ; le MJ peut aussi la traiter.
3. Le propriétaire ou le MJ accepte ou refuse.
4. En cas d'acceptation, l'objet est transféré au demandeur.

Le demandeur peut annuler sa demande tant qu'elle est en attente. Une demande devient automatiquement caduque si l'objet est déplacé, vendu, consommé, perdu, donné ou démonté.

## Manipuler des piles d'objets

Une carte peut représenter plusieurs exemplaires d'un même objet.

- **Fractionner** crée deux piles séparées, par exemple pour donner une potion sur trois à un autre personnage.
- **Regrouper** fusionne deux piles équivalentes : même nom, même propriétaire, même valeur unitaire et même référence AoN.
- **Action groupée** permet d'attribuer, remettre au compte commun, consommer, perdre ou donner plusieurs objets en une seule opération.

Ces opérations ne créent ni gain ni dépense : elles changent seulement la manière dont le même patrimoine est rangé.

## Sorties d'un objet

Un objet actif peut quitter l'inventaire de plusieurs façons.

### Vente

La vente retire la quantité vendue de l'inventaire et verse le montant choisi dans le **compte commun**. Le montant proposé peut être corrigé librement au moment de la vente.

La vente crée deux traces liées : le départ de l'objet et l'arrivée de l'argent. Son effet sur les statistiques est particulier :

- l'argent reçu augmente le compte commun ;
- seule une éventuelle **plus-value** augmente les gains cumulés ;
- vendre au prix enregistré ne crée donc aucun gain supplémentaire ;
- vendre à perte ne retire pas de gains cumulés ;
- un objet sans valeur enregistrée est considéré comme gratuit : l'intégralité de son prix de vente est alors une plus-value.

Exemple : une potion enregistrée à 4 po est vendue 6 po. Le compte commun reçoit 6 po, mais les gains cumulés n'augmentent que de 2 po.

### Consommation, perte et don hors du groupe

Un objet peut être marqué comme :

- **consommé** ;
- **perdu** ;
- **donné hors du groupe**.

Il n'est alors plus dans le patrimoine actuel et ne peut plus être attribué. Cela ne compte **pas** comme une dépense cumulée : aucune monnaie n'a quitté le groupe. C'est une disparition ou une utilisation d'objet, pas une sortie d'argent.

### Démontage

Un objet peut être démonté afin d'obtenir autre chose, par exemple récupérer une rune d'une arme.

L'objet d'origine devient « démonté ». La personne qui réalise l'opération renseigne ensuite les objets obtenus : nom, quantité, valeur facultative et lien AoN facultatif. Ces objets arrivent dans le même inventaire que l'objet d'origine.

Le démontage ne crée ni gain ni dépense par lui-même. Les objets obtenus sont des transformations de l'objet initial, pas de nouveaux trésors.

## Argent et comptes

### Compte commun

Le compte commun représente l'or disponible pour le groupe. Il reçoit notamment :

- le prix des objets vendus ;
- les entrées communes ajoutées par le MJ ;
- l'argent remis par un joueur.

Il peut servir à financer un achat boutique ou être transféré à un joueur.

### Comptes personnels

Chaque joueur possède un compte personnel. Les soldes négatifs sont autorisés : le système permet donc de suivre une avance, une dette implicite ou un achat fait avant remboursement.

Les comptes personnels peuvent recevoir de l'argent depuis le compte commun, depuis un autre joueur ou depuis l'extérieur ; ils peuvent aussi payer un achat, une dépense ou donner de l'argent au compte commun ou à un autre joueur.

Le MJ choisit dans les paramètres généraux si les joueurs voient tous les soldes personnels ou seulement leur propre solde et le compte commun. Le MJ conserve toujours la vue complète.

### Transferts

Un transfert déplace de l'argent entre le compte commun et les comptes des joueurs, ou entre deux joueurs.

Un joueur peut débiter son propre compte ou le compte commun ; il ne peut pas débiter le compte personnel d'un autre joueur. Le MJ peut gérer tous les comptes.

Un transfert interne ne change ni le patrimoine global, ni les gains cumulés, ni les dépenses cumulées : seul le propriétaire de l'argent change.

### Revenu ou dépense personnelle

Un joueur peut déclarer un revenu individuel ou une dépense individuelle. Le MJ peut aussi le faire pour un joueur.

- Un **revenu** fait entrer de l'argent depuis l'extérieur dans le compte du joueur : il augmente les gains cumulés.
- Une **dépense** fait sortir de l'argent vers l'extérieur : elle augmente les dépenses cumulées.

Un commentaire est facultatif, par exemple « remboursement de la chambre », « récompense pour un service personnel » ou « taxes de Griselapinte ».

### Entrée commune du MJ

Le MJ peut faire entrer de l'argent extérieur directement dans le compte commun : récompense, paiement de quête, coffre monétaire ou correction décidée en jeu. Cette entrée augmente les gains cumulés.

### Dettes entre joueurs

Une dette ne déplace pas immédiatement d'argent : elle enregistre qu'un joueur doit une somme à un autre. Pour la créer, le joueur connecté doit être débiteur ou créancier ; le MJ peut créer une dette entre n'importe quels joueurs.

Le débiteur — ou le MJ — peut la rembourser, totalement ou progressivement. Chaque remboursement est un transfert interne entre les deux comptes : il ne modifie donc ni gains ni dépenses. Une dette ouverte peut être annulée par son créateur, le débiteur, le créancier ou le MJ.

## Les trois indicateurs de suivi

Les indicateurs du haut ne forment pas une équation comptable. Ils répondent à trois questions différentes.

| Indicateur | Question à laquelle il répond | Ce qui est pris en compte |
| --- | --- | --- |
| **Patrimoine actuel** | Quelle valeur possède actuellement le groupe ? | Tous les soldes d'argent et les objets actifs ayant une valeur enregistrée. |
| **Gains cumulés** | Quelle richesse nouvelle est entrée dans l'aventure depuis le début ? | Butins révélés, objets MJ comptés comme gain, entrées d'argent extérieures, revenus et plus-values réalisées à la revente. |
| **Dépenses cumulées** | Quelle monnaie a réellement quitté le groupe vers l'extérieur ? | Achats boutique, services, taxes, auberge et autres dépenses monétaires. |

Ne comptent pas comme gains : les transferts entre joueurs, les achats, les objets créés uniquement comme correction, ni la partie d'une revente correspondant déjà à la valeur de l'objet.

Ne comptent pas comme dépenses : les transferts internes, les remboursements de dette, un objet consommé, perdu, donné ou démonté.

## Annuler une opération

Le système conserve le journal au lieu d'effacer l'histoire.

Le MJ peut annuler les actions d'inventaire récentes : attribution, envoi, retour au compte commun, fractionnement, regroupement, vente, démontage, consommation, perte ou don. Une vente peut aussi être annulée par le joueur qui l'a enregistrée.

L'annulation est volontairement refusée si l'objet concerné — ou ses composants — a été modifié depuis l'action. Par exemple, le MJ ne peut pas annuler l'envoi d'une potion qui a ensuite été consommée. Le journal reste ainsi une représentation fidèle de la partie, sans correction silencieuse d'actions plus récentes.

Lorsqu'une opération annulable est annulée :

1. l'action d'origine reste dans l'activité, barrée et atténuée ;
2. son ancien bouton est remplacé par le texte **« Action annulée »** ;
3. l'opération inverse est créée et libellée **« Suite à annulation : … »** ;
4. ni l'opération d'origine ni son inverse ne restent comptées dans les gains ou dépenses cumulés.

Ainsi, annuler une entrée de 20 po ne transforme pas artificiellement cette entrée en dépense de 20 po : pour les statistiques, elle cesse simplement d'avoir existé.

Les ventes et achats doivent être annulés depuis l'objet concerné, car l'annulation doit aussi restaurer ou retirer l'objet correspondant. Les transactions financières ordinaires sont annulables depuis le journal par leur auteur ou par le MJ.

## Historique et commentaires

Chaque objet conserve une trace de son parcours : création ou découverte, attribution, transfert, vente, démontage, consommation, perte, don et annulation. Chaque opération monétaire conserve également sa date, son acteur, son montant et son éventuel commentaire.

Le commentaire est toujours facultatif. Il permet de conserver le contexte utile sans imposer une lourdeur de gestion : « vendu au marché de Geb », « remboursement de chambre », « rune récupérée », etc.

## Rôle du MJ

Le MJ est l'administrateur fonctionnel de cette économie : il peut révéler les butins de la campagne, créer des objets, administrer les inventaires, traiter les demandes, gérer les comptes, annuler les opérations qu'il doit corriger et ajouter les entrées communes.

Le MJ n'utilise pas « Achat boutique » : cette action appartient aux joueurs et évite qu'un achat MJ accidentel crée une opération ambiguë.

Si un joueur quitte la campagne, son argent et ses objets retournent au compte commun. Le groupe peut ensuite les redistribuer librement.

## Exemple rapide de séance

1. Le MJ révèle une épée +1 et 12 po après une rencontre : l'épée apparaît dans le compte commun, les 12 po sont ajoutées au compte commun.
2. Une joueuse s'attribue l'épée. Cette attribution ne change aucune statistique globale.
3. Le groupe revend plus tard l'épée, enregistrée à 35 po, pour 40 po. Le compte commun reçoit 40 po ; les gains cumulés n'augmentent que de 5 po.
4. Un joueur achète une potion pour 4 po avec son propre compte. Son solde baisse de 4 po ; les dépenses cumulées augmentent de 4 po ; la potion entre dans son inventaire.
5. La potion est consommée. Elle disparaît du patrimoine actuel, mais les dépenses cumulées ne changent pas : l'argent était déjà sorti au moment de l'achat.
6. Un joueur avance 10 po à un autre. C'est un transfert interne ; il peut aussi déclarer une dette de 10 po pour s'en souvenir. Aucun des deux gestes ne modifie les gains ou dépenses du groupe.

## Limites volontaires

Le système est un outil de suivi de campagne, pas un simulateur économique complet. Il privilégie les opérations rapides, les commentaires facultatifs et un historique compréhensible. Les prix ou références AoN peuvent être complétés progressivement par le MJ lorsque nécessaire ; l'outil n'oblige pas à tout renseigner avant de jouer.
