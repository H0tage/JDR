-- Campaign and reference data extracted from the public GM guide v4.1.

insert into public.campaigns (id, slug, name, description, public_enabled) values
  ('00000000-0000-4000-8000-000000000001', 'blood-lords', 'Blood Lords', 'Campagne Pathfinder en six volumes, de Griseplainte aux plus hauts cercles de Geb.', true);

insert into public.campaign_settings (campaign_id) values
  ('00000000-0000-4000-8000-000000000001');

insert into public.factions (id, slug, name, short_name, accent, domain, public_description, sort_order) values
  ('00000000-0000-4000-8100-000000000101', 'bâtisseurs', 'Ligue des Bâtisseurs', 'Bâtisseurs', '#8f7a5a', 'Architecture, ouvrages et secrets', 'Architectes traditionalistes et occultistes chargés des grands ouvrages de Geb.', 1),
  ('00000000-0000-4000-8100-000000000102', 'célébrants', 'Célébrants', 'Célébrants', '#a64052', 'Culte public, cérémonies et propagande', 'Prêtres, organisateurs et maîtres du récit public de la nation.', 2),
  ('00000000-0000-4000-8100-000000000103', 'exportation', 'Guilde des Exportateurs', 'Exportateurs', '#4c7d73', 'Commerce extérieur et diplomatie', 'Gestionnaires du commerce extérieur, des cargaisons et des partenaires étrangers.', 3),
  ('00000000-0000-4000-8100-000000000104', 'réanimateurs', 'Réanimateurs', 'Réanimateurs', '#7a5d93', 'Nécromancie, agriculture et main-d’œuvre', 'Nécromanciens responsables de la production agricole et du travail mort-vivant.', 4),
  ('00000000-0000-4000-8100-000000000105', 'uci', 'Syndicats des Percepteurs d’Impôts', 'Percepteurs', '#b18335', 'Finance, fiscalité et contrats', 'Aristocrates, banquiers et percepteurs qui transforment la richesse en influence.', 5),
  ('00000000-0000-4000-8100-000000000106', 'charretiers', 'Consortium des Convoyeurs', 'Convoyeurs', '#65717c', 'Transport intérieur et logistique', 'Ancienne grande faction déchue, toujours indispensable aux routes et aux convois.', 6);

insert into public.campaign_factions (campaign_id, faction_id, public_summary, is_player_visible)
select '00000000-0000-4000-8000-000000000001', id,
  case when slug = 'réanimateurs' then 'Berline Haldoli a fait connaître l’efficacité du groupe auprès de sa faction.' else null end,
  true
from public.factions;

insert into public.services
  (id, campaign_id, faction_id, scale, required_rp, base_cost, domain, examples, safeguard, frequency, sort_order)
values
  ('00000000-0000-4000-8200-000000000001','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000101','Mineure',5,3,'Bâtiments et permis','Inspection rapide ; petit permis ; consultation d’archives occultes.','Ne remplace ni un achat ni une enquête complète.','Premier service à 5 RP peut être gratuit.',1),
  ('00000000-0000-4000-8200-000000000002','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000101','Modérée',15,7,'Chantier et expertise','Équipe qualifiée ; sécurisation d’un site ; dossier technique approfondi.','Les matériaux rares restent payants.','Première demande modérée du volume : −2 JF.',2),
  ('00000000-0000-4000-8200-000000000003','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000101','Majeure',30,12,'Projet stratégique','Travaux majeurs ; aile dissimulée ; projet public au bénéfice du groupe.','Le calendrier et la discrétion peuvent exiger un test.','Une par faction et par volume.',3),
  ('00000000-0000-4000-8200-000000000004','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000102','Mineure',5,3,'Société et rumeur','Invitation ; rumeur vérifiée ; présentation favorable du groupe.','Une rumeur n’est pas une preuve.','Premier service à 5 RP peut être gratuit.',1),
  ('00000000-0000-4000-8200-000000000005','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000102','Modérée',15,7,'Influence locale','Campagne locale ; événement mondain ; préparation d’une scène d’influence.','Ne garantit pas le vote ou l’adhésion d’un tiers.','Première demande modérée du volume : −2 JF.',2),
  ('00000000-0000-4000-8200-000000000006','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000102','Majeure',30,12,'Mobilisation publique','Cérémonie nationale ; étouffement d’un scandale ; mobilisation d’un réseau social.','Les adversaires conservent leurs moyens d’action.','Une par faction et par volume.',3),
  ('00000000-0000-4000-8200-000000000007','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000103','Mineure',5,3,'Commerce','Accès à un objet peu commun à payer ; manifeste ; route ou contact marchand.','La faveur ouvre l’accès, elle ne paie pas la marchandise.','Premier service à 5 RP peut être gratuit.',1),
  ('00000000-0000-4000-8200-000000000008','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000103','Modérée',15,7,'Logistique commerciale','Accès rare ; contact étranger ; cargaison prioritaire.','Les risques de transport restent fictionnels.','Première demande modérée du volume : −2 JF.',2),
  ('00000000-0000-4000-8200-000000000009','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000103','Majeure',30,12,'Pression économique','Import stratégique ; pression commerciale ; activation d’un réseau international.','Ne crée pas une ressource inexistante sans contrepartie.','Une par faction et par volume.',3),
  ('00000000-0000-4000-8200-000000000010','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000104','Mineure',5,3,'Travail mort-vivant','Équipe d’ouvriers ; formalités sur un cadavre ; diagnostic nécromantique.','Respecter les limites légales et le ton de la table.','Premier service à 5 RP peut être gratuit.',1),
  ('00000000-0000-4000-8200-000000000011','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000104','Modérée',15,7,'Projet nécromantique','Main-d’œuvre de projet ; gestion d’un désastre ; remplacement d’un compagnon selon les règles.','Aucun contournement automatique des coûts ou des règles de création.','Première demande modérée du volume : −2 JF.',2),
  ('00000000-0000-4000-8200-000000000012','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000104','Majeure',30,12,'Mobilisation exceptionnelle','Mobilisation de masse ; reconstitution légale exceptionnelle ; réponse nécromantique stratégique.','Ce n’est pas une résurrection garantie ni gratuite.','Une par faction et par volume.',3),
  ('00000000-0000-4000-8200-000000000013','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000105','Mineure',5,3,'Finance et contrats','Notaire ; coffre sûr ; contrat ; repérage d’actifs.','Le service ne supprime pas les obligations écrites.','Premier service à 5 RP peut être gratuit.',1),
  ('00000000-0000-4000-8200-000000000014','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000105','Modérée',15,7,'Pouvoir financier','Audit ; gel ciblé ; prêt jusqu’à un objet permanent de niveau du groupe −1.','Le prêt doit avoir une échéance et une garantie.','Première demande modérée du volume : −2 JF.',2),
  ('00000000-0000-4000-8200-000000000015','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000105','Majeure',30,12,'Action institutionnelle','Financement stratégique ; saisie ; patronage bancaire ou politique.','Une réaction des concurrents est probable.','Une par faction et par volume.',3),
  ('00000000-0000-4000-8200-000000000016','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000106','Mineure',5,3,'Transport','Messager ; petit convoi ; itinéraire ; manifeste de passage.','Le service ne neutralise pas tous les dangers de route.','Premier service à 5 RP peut être gratuit.',1),
  ('00000000-0000-4000-8200-000000000017','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000106','Modérée',15,7,'Convoi tactique','Convoi blindé ; extraction ; franchissement préparé d’un point de contrôle.','La cargaison et les pertes restent à assumer.','Première demande modérée du volume : −2 JF.',2),
  ('00000000-0000-4000-8200-000000000018','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000106','Majeure',25,12,'Logistique stratégique','Grand mouvement logistique, restauration d’un axe ou extraction à l’échelle de la campagne.','Usage exceptionnel, à cadrer avec une dette ou une conséquence majeure.','Une seule fois sur toute la campagne.',3);

insert into public.contacts
  (id, campaign_id, faction_id, name, role, state, attitude, gm_notes, visibility, is_primary)
values
  ('00000000-0000-4000-8500-000000000001','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000101','Représentant lié à la banque','Inspection, permis et chantiers','À introduire','Neutre','Nommer selon les besoins de la campagne.','gm_only',true),
  ('00000000-0000-4000-8500-000000000002','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000102','Se-Maut-Get','Rumeurs, réception et influence','À introduire','Neutre','Contact suggéré par l’aventure.','gm_only',true),
  ('00000000-0000-4000-8500-000000000003','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000103','Altinmered','Commerce, cargaisons et accès','À introduire','Neutre','Contact suggéré par l’aventure.','gm_only',true),
  ('00000000-0000-4000-8500-000000000004','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000104','Berline Haldoli','Main-d’œuvre et nécromancie','Actif','Favorable','Patronne du groupe à Griseplainte.','players',true),
  ('00000000-0000-4000-8500-000000000005','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000105','Vaskish','Contrats, crédit et actifs','À introduire','Neutre','Contact suggéré par l’aventure.','gm_only',true),
  ('00000000-0000-4000-8500-000000000006','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000106','Mauldor Gavvik','Convois, routes et extraction','À introduire','Neutre','Le Suaire peut devenir un relais ultérieur.','gm_only',true);

insert into public.journal_entries
  (id, campaign_id, faction_id, occurred_on, volume, title, details, rp_delta, jf_delta, visibility, source_reference)
values
  ('00000000-0000-4000-8600-000000000001','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000104','2026-05-10',1,'Crise de la ferme du vieux Hergag résolue','Berline Haldoli fait connaître l’efficacité du groupe auprès des Réanimateurs.',5,5,'players','Zombie Feast, p. 20');

insert into public.faction_relationships
  (id, campaign_id, source_faction_id, target_faction_id, headline, detail, evidence, tone, visibility)
values
  ('00000000-0000-4000-8300-000000000001','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000101','00000000-0000-4000-8100-000000000102','Défiance informationnelle','Secrets et passages cachés contre maîtrise du récit public.','S','tension','gm_only'),
  ('00000000-0000-4000-8300-000000000002','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000101','00000000-0000-4000-8100-000000000103','Hostilité stratégique','Les étrangers et leur richesse menacent le contrôle des secrets.','E','hostility','gm_only'),
  ('00000000-0000-4000-8300-000000000003','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000101','00000000-0000-4000-8100-000000000104','Alliance productive','La main-d’œuvre morte-vivante rend possibles les grands ouvrages.','E/S','alliance','gm_only'),
  ('00000000-0000-4000-8300-000000000004','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000101','00000000-0000-4000-8100-000000000105','Partenaire traditionnel','Coffres, financement et ouvrages secrets se renforcent mutuellement.','S','cooperation','gm_only'),
  ('00000000-0000-4000-8300-000000000005','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000101','00000000-0000-4000-8100-000000000106','Infrastructure contre flux','Le Consortium est utile mais facilement traité comme un exécutant remplaçable.','S/H','cooperation','gm_only'),
  ('00000000-0000-4000-8300-000000000006','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000102','00000000-0000-4000-8100-000000000101','Ennemi déclaré','Chaque secret est un récit abandonné à un rival.','E','hostility','gm_only'),
  ('00000000-0000-4000-8300-000000000007','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000102','00000000-0000-4000-8100-000000000103','Partenaire d’accueil','La diplomatie commerciale a besoin de cérémonies et d’une image maîtrisée.','E/S','alliance','gm_only'),
  ('00000000-0000-4000-8300-000000000008','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000102','00000000-0000-4000-8100-000000000104','Légitimation utile','Le récit public normalise la non-vie mais peut aussi cacher le sale travail.','S','cooperation','gm_only'),
  ('00000000-0000-4000-8300-000000000009','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000102','00000000-0000-4000-8100-000000000105','Dépendance budgétaire','Rivalité d’ascension, de prestige et de contrôle des dépenses.','E','hostility','gm_only'),
  ('00000000-0000-4000-8300-000000000010','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000102','00000000-0000-4000-8100-000000000106','Réhabilitation ou discrédit','La propagande peut restaurer le Consortium ou raviver son scandale.','S/H','tension','gm_only'),
  ('00000000-0000-4000-8300-000000000011','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000103','00000000-0000-4000-8100-000000000101','Blocages traditionnels','Les contrôles et les secrets ralentissent l’expansion commerciale.','S','tension','gm_only'),
  ('00000000-0000-4000-8300-000000000012','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000103','00000000-0000-4000-8100-000000000102','Allié de vitrine','Alliance utile, avec une concurrence permanente pour l’influence.','E/S','alliance','gm_only'),
  ('00000000-0000-4000-8300-000000000013','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000103','00000000-0000-4000-8100-000000000104','Ennemi nécessaire','L’image extérieure dépend pourtant de la production cadavérique.','E','hostility','gm_only'),
  ('00000000-0000-4000-8300-000000000014','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000103','00000000-0000-4000-8100-000000000105','Capital et contrôle','Expansion rapide contre prudence, garanties et surveillance.','S','cooperation','gm_only'),
  ('00000000-0000-4000-8300-000000000015','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000103','00000000-0000-4000-8100-000000000106','Sous-traitant intérieur','Partenaire logistique et rival de juridiction sur les cargaisons.','S','cooperation','gm_only'),
  ('00000000-0000-4000-8300-000000000016','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000104','00000000-0000-4000-8100-000000000101','Partenaire de chantier','Travail et corps contre ouvrages, permis et infrastructures.','S','alliance','gm_only'),
  ('00000000-0000-4000-8300-000000000017','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000104','00000000-0000-4000-8100-000000000102','Symbole national utile','La légitimité publique s’accompagne de la peur d’être sacrifié lors d’un scandale.','S','cooperation','gm_only'),
  ('00000000-0000-4000-8300-000000000018','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000104','00000000-0000-4000-8100-000000000103','Allié officiel sous pression','Les débouchés commerciaux sont vitaux malgré le mépris de la Guilde.','E','alliance','gm_only'),
  ('00000000-0000-4000-8300-000000000019','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000104','00000000-0000-4000-8100-000000000105','Ennemi déclaré','Taxes lourdes et mépris du travail productif.','E','hostility','gm_only'),
  ('00000000-0000-4000-8300-000000000020','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000104','00000000-0000-4000-8100-000000000106','Distribution vitale','Les cargaisons sensibles exigent fiabilité et confiance.','S','cooperation','gm_only'),
  ('00000000-0000-4000-8300-000000000021','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000105','00000000-0000-4000-8100-000000000101','Allié déclaré','Coffres impénétrables, tradition et propriété institutionnelle.','E','alliance','gm_only'),
  ('00000000-0000-4000-8300-000000000022','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000105','00000000-0000-4000-8100-000000000102','Ennemi déclaré','Budget, prestige et ascension menacent le statu quo financier.','E','hostility','gm_only'),
  ('00000000-0000-4000-8300-000000000023','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000105','00000000-0000-4000-8100-000000000103','Investit et surveille','Le rendement commercial doit rester contrôlable.','S','cooperation','gm_only'),
  ('00000000-0000-4000-8300-000000000024','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000105','00000000-0000-4000-8100-000000000104','Taxe et méprise','L’immense force de travail est une richesse à prélever et une puissance à contenir.','E/S','hostility','gm_only'),
  ('00000000-0000-4000-8300-000000000025','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000105','00000000-0000-4000-8100-000000000106','Régulateur et créancier','Péages, saisies et prêts maintiennent le Consortium sous tutelle.','S/H','tension','gm_only'),
  ('00000000-0000-4000-8300-000000000026','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000106','00000000-0000-4000-8100-000000000101','Dépendance routière','Chaque route abandonnée nourrit le ressentiment envers les Grandes Factions.','S','tension','gm_only'),
  ('00000000-0000-4000-8300-000000000027','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000106','00000000-0000-4000-8100-000000000102','Réhabilitation risquée','Le Consortium veut retrouver sa place sans exposer son passé.','S/H','tension','gm_only'),
  ('00000000-0000-4000-8300-000000000028','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000106','00000000-0000-4000-8100-000000000103','Partenaire et rival','Relais intérieur indispensable, mais concurrence sur les marges et la juridiction.','S','cooperation','gm_only'),
  ('00000000-0000-4000-8300-000000000029','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000106','00000000-0000-4000-8100-000000000104','Client majeur','Transporter corps et travailleurs expose le Consortium à des risques singuliers.','S','cooperation','gm_only'),
  ('00000000-0000-4000-8300-000000000030','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8100-000000000106','00000000-0000-4000-8100-000000000105','Contrôle mal accepté','Le crédit est nécessaire, les péages et la tutelle restent humiliants.','S/H','tension','gm_only');

insert into public.reputation_milestones
  (id, campaign_id, volume, title, beneficiary_faction_id, rp_gain, harmed_faction_id, rp_loss, condition, source_reference, applied, sort_order)
values
  ('00000000-0000-4000-8700-000000000001','00000000-0000-4000-8000-000000000001',1,'Résoudre la crise de la ferme','00000000-0000-4000-8100-000000000104',5,null,0,'Récompense prévue par l’aventure.','Blood Lords #1 — Zombie Feast, p. 20',true,1),
  ('00000000-0000-4000-8700-000000000002','00000000-0000-4000-8000-000000000001',1,'Secourir Se-Maut-Get','00000000-0000-4000-8100-000000000102',4,null,0,'Se-Maut-Get doit survivre à l’aventure.','Blood Lords #1 — Zombie Feast, p. 59',false,2),
  ('00000000-0000-4000-8700-000000000003','00000000-0000-4000-8000-000000000001',1,'Libérer Altinmered','00000000-0000-4000-8100-000000000103',4,null,0,'Libérer Altinmered.','Blood Lords #1 — Zombie Feast, p. 62',false,3),
  ('00000000-0000-4000-8700-000000000004','00000000-0000-4000-8000-000000000001',1,'Choisir la branche SPI de la banque','00000000-0000-4000-8100-000000000105',8,'00000000-0000-4000-8100-000000000101',-4,'Choix exclusif avec la branche des Bâtisseurs.','Blood Lords #1 — Zombie Feast, p. 64',false,4),
  ('00000000-0000-4000-8700-000000000005','00000000-0000-4000-8000-000000000001',1,'Choisir la branche des Bâtisseurs','00000000-0000-4000-8100-000000000101',8,'00000000-0000-4000-8100-000000000105',-4,'Choix exclusif avec la branche SPI.','Blood Lords #1 — Zombie Feast, p. 64',false,5);

insert into public.source_references
  (campaign_id, source_type, title, reference, usage_note, locator, sort_order)
values
  ('00000000-0000-4000-8000-000000000001','Officiel','Pathfinder Gamemastery Guide','pp. 164–165','Seuils et fonctionnement de la Réputation.','PZO2103 Pathfinder 2E - Gamemastery Guide.pdf',1),
  ('00000000-0000-4000-8000-000000000001','Officiel','Blood Lords #1 — Zombie Feast','Volume 1','Factions, premiers gains de RP et choix de la banque.','PZO90181 Pathfinder Adventure Path #181 - Blood Lords #1 - Zombie Feast.pdf',2),
  ('00000000-0000-4000-8000-000000000001','Officiel','Blood Lords #2 — Graveclaw','Volume 2','Développement de la campagne et Convoyeurs.','PZO90182 Pathfinder Adventure Path #182 - Blood Lords #2 - Graveclaw.pdf',3),
  ('00000000-0000-4000-8000-000000000001','Officiel','Blood Lords #3 — Field of Maidens','Volume 3','Diplomatie et progression.','PZO90183 Pathfinder Adventure Path #183 - Blood Lords #3 - Field of Maidens.pdf',4),
  ('00000000-0000-4000-8000-000000000001','Officiel','Blood Lords #4 — The Ghouls Hunger','Volume 4','Usage institutionnel et temps morts.','PZO90184 Pathfinder Adventure Path #184 - Blood Lords #4 - The Ghouls Hunger.pdf',5),
  ('00000000-0000-4000-8000-000000000001','Officiel','Blood Lords #5 — A Taste of Ashes','Volume 5','Réemploi des relations et contacts.','PZO90185 Pathfinder Adventure Path #185 - Blood Lords #5 - A Taste of Ashes.pdf',6),
  ('00000000-0000-4000-8000-000000000001','Officiel','Blood Lords #6 — Ghost King’s Rage','Volume 6','Conclusion et raccourcis de campagne.','PZO90186 Pathfinder Adventure Path #186 - Blood Lords #6 - Ghost King_s Rage.pdf',7),
  ('00000000-0000-4000-8000-000000000001','Communauté','Reputation in Blood Lords','Reddit','Discussion sur la sous-utilisation du sous-système.','https://www.reddit.com/r/Pathfinder2e/comments/10suxft/reputation_in_blood_lords/',20),
  ('00000000-0000-4000-8000-000000000001','Synthèse','Guide MJ pratique — factions de Blood Lords v4.1','Version publique','Système RP/JF/Tension, services et matrice enrichie.','Guide_MJ_factions_Blood_Lords_v4_1_public.docx',30);
