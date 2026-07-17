import type {
  BilateralDossier,
  CampaignData,
  CampaignSettings,
  Contact,
  FactionOverview,
  JournalEntry,
  Milestone,
  Relationship,
  Service,
} from "../lib/types";

export const CAMPAIGN_ID = "00000000-0000-4000-8000-000000000001";

const factionSeeds = [
  ["bâtisseurs", "Ligue des Bâtisseurs", "Bâtisseurs", "#8f7a5a", "Architecture, ouvrages et secrets", "Architectes traditionalistes et occultistes chargés des grands ouvrages de Geb."],
  ["célébrants", "Célébrants", "Célébrants", "#a64052", "Culte public, cérémonies et propagande", "Prêtres, organisateurs et maîtres du récit public de la nation."],
  ["exportation", "Guilde de l’Exportation", "Exportation", "#4c7d73", "Commerce extérieur et diplomatie", "Gestionnaires du commerce extérieur, des cargaisons et des partenaires étrangers."],
  ["réanimateurs", "Ligue des Réanimateurs", "Réanimateurs", "#7a5d93", "Nécromancie, agriculture et main-d’œuvre", "Nécromanciens responsables de la production agricole et du travail mort-vivant."],
  ["uci", "Union des Collecteurs d’Impôts", "UCI", "#b18335", "Finance, fiscalité et contrats", "Aristocrates, banquiers et percepteurs qui transforment la richesse en influence."],
  ["charretiers", "Consortium des Charretiers", "Charretiers", "#65717c", "Transport intérieur et logistique", "Ancienne grande faction déchue, toujours indispensable aux routes et aux convois."],
] as const;

const factionIds = Object.fromEntries(factionSeeds.map((f, index) => [f[0], `00000000-0000-4000-8100-00000000010${index + 1}`]));

export const mockSettings: CampaignSettings = {
  campaign_id: CAMPAIGN_ID,
  current_volume: 1,
  jf_cap: 15,
  minor_cost: 3,
  moderate_cost: 7,
  major_cost: 12,
  liked_threshold: 5,
  admired_threshold: 15,
  revered_threshold: 30,
  carters_major_threshold: 25,
  tension_max: 4,
  tension_surcharge_level: 2,
  tension_surcharge: 1,
  admired_discount: 2,
  show_numeric_tension: false,
};

export const mockFactions: FactionOverview[] = factionSeeds.map((seed, index) => {
  const rp = seed[0] === "réanimateurs" ? 5 : 0;
  return {
    campaign_id: CAMPAIGN_ID,
    faction_id: factionIds[seed[0]],
    slug: seed[0],
    name: seed[1],
    short_name: seed[2],
    accent: seed[3],
    domain: seed[4],
    public_description: seed[5],
    public_summary: index === 3 ? "Berline Haldoli a fait connaître l’efficacité du groupe auprès de sa faction." : null,
    gm_notes: null,
    next_consequence: null,
    is_player_visible: true,
    rp,
    jf: rp,
    tension: 0,
    status: rp >= 5 ? "Appréciés" : "Indifférents",
    tension_label: "Stable",
  };
});

const serviceRows = [
  ["bâtisseurs", "Mineure", 5, 3, "Bâtiments et permis", "Inspection rapide ; petit permis ; consultation d’archives occultes.", "Ne remplace ni un achat ni une enquête complète.", "Premier service à 5 RP peut être gratuit."],
  ["bâtisseurs", "Modérée", 15, 7, "Chantier et expertise", "Équipe qualifiée ; sécurisation d’un site ; dossier technique approfondi.", "Les matériaux rares restent payants.", "Première demande modérée du volume : −2 JF."],
  ["bâtisseurs", "Majeure", 30, 12, "Projet stratégique", "Travaux majeurs ; aile dissimulée ; projet public au bénéfice du groupe.", "Le calendrier et la discrétion peuvent exiger un test.", "Une par faction et par volume."],
  ["célébrants", "Mineure", 5, 3, "Société et rumeur", "Invitation ; rumeur vérifiée ; présentation favorable du groupe.", "Une rumeur n’est pas une preuve.", "Premier service à 5 RP peut être gratuit."],
  ["célébrants", "Modérée", 15, 7, "Influence locale", "Campagne locale ; événement mondain ; préparation d’une scène d’influence.", "Ne garantit pas le vote ou l’adhésion d’un tiers.", "Première demande modérée du volume : −2 JF."],
  ["célébrants", "Majeure", 30, 12, "Mobilisation publique", "Cérémonie nationale ; étouffement d’un scandale ; mobilisation d’un réseau social.", "Les adversaires conservent leurs moyens d’action.", "Une par faction et par volume."],
  ["exportation", "Mineure", 5, 3, "Commerce", "Accès à un objet peu commun à payer ; manifeste ; route ou contact marchand.", "La faveur ouvre l’accès, elle ne paie pas la marchandise.", "Premier service à 5 RP peut être gratuit."],
  ["exportation", "Modérée", 15, 7, "Logistique commerciale", "Accès rare ; contact étranger ; cargaison prioritaire.", "Les risques de transport restent fictionnels.", "Première demande modérée du volume : −2 JF."],
  ["exportation", "Majeure", 30, 12, "Pression économique", "Import stratégique ; pression commerciale ; activation d’un réseau international.", "Ne crée pas une ressource inexistante sans contrepartie.", "Une par faction et par volume."],
  ["réanimateurs", "Mineure", 5, 3, "Travail mort-vivant", "Équipe d’ouvriers ; formalités sur un cadavre ; diagnostic nécromantique.", "Respecter les limites légales et le ton de la table.", "Premier service à 5 RP peut être gratuit."],
  ["réanimateurs", "Modérée", 15, 7, "Projet nécromantique", "Main-d’œuvre de projet ; gestion d’un désastre ; remplacement d’un compagnon selon les règles.", "Aucun contournement automatique des coûts ou des règles de création.", "Première demande modérée du volume : −2 JF."],
  ["réanimateurs", "Majeure", 30, 12, "Mobilisation exceptionnelle", "Mobilisation de masse ; reconstitution légale exceptionnelle ; réponse nécromantique stratégique.", "Ce n’est pas une résurrection garantie ni gratuite.", "Une par faction et par volume."],
  ["uci", "Mineure", 5, 3, "Finance et contrats", "Notaire ; coffre sûr ; contrat ; repérage d’actifs.", "Le service ne supprime pas les obligations écrites.", "Premier service à 5 RP peut être gratuit."],
  ["uci", "Modérée", 15, 7, "Pouvoir financier", "Audit ; gel ciblé ; prêt jusqu’à un objet permanent de niveau du groupe −1.", "Le prêt doit avoir une échéance et une garantie.", "Première demande modérée du volume : −2 JF."],
  ["uci", "Majeure", 30, 12, "Action institutionnelle", "Financement stratégique ; saisie ; patronage bancaire ou politique.", "Une réaction des concurrents est probable.", "Une par faction et par volume."],
  ["charretiers", "Mineure", 5, 3, "Transport", "Messager ; petit convoi ; itinéraire ; manifeste de passage.", "Le service ne neutralise pas tous les dangers de route.", "Premier service à 5 RP peut être gratuit."],
  ["charretiers", "Modérée", 15, 7, "Convoi tactique", "Convoi blindé ; extraction ; franchissement préparé d’un point de contrôle.", "La cargaison et les pertes restent à assumer.", "Première demande modérée du volume : −2 JF."],
  ["charretiers", "Majeure", 25, 12, "Logistique stratégique", "Grand mouvement logistique, restauration d’un axe ou extraction à l’échelle de la campagne.", "Usage exceptionnel, à cadrer avec une dette ou une conséquence majeure.", "Une seule fois sur toute la campagne."],
] as const;

export const mockServices: Service[] = serviceRows.map((row, index) => ({
  id: `00000000-0000-4000-8200-${String(index + 1).padStart(12, "0")}`,
  faction_id: factionIds[row[0]],
  faction_name: factionSeeds.find((f) => f[0] === row[0])![2],
  scale: row[1],
  required_rp: row[2],
  base_cost: row[3],
  domain: row[4],
  examples: row[5],
  safeguard: row[6],
  frequency: row[7],
  player_visible: true,
}));

const relationshipRows = [
  ["bâtisseurs", "célébrants", "Défiance informationnelle", "Secrets et passages cachés contre maîtrise du récit public.", "S", "tension"],
  ["bâtisseurs", "exportation", "Hostilité stratégique", "Les étrangers et leur richesse menacent le contrôle des secrets.", "E", "hostility"],
  ["bâtisseurs", "réanimateurs", "Alliance productive", "La main-d’œuvre morte-vivante rend possibles les grands ouvrages.", "E/S", "alliance"],
  ["bâtisseurs", "uci", "Partenaire traditionnel", "Coffres, financement et ouvrages secrets se renforcent mutuellement.", "S", "cooperation"],
  ["bâtisseurs", "charretiers", "Infrastructure contre flux", "Le Consortium est utile mais facilement traité comme un exécutant remplaçable.", "S/H", "cooperation"],
  ["célébrants", "bâtisseurs", "Ennemi déclaré", "Chaque secret est un récit abandonné à un rival.", "E", "hostility"],
  ["célébrants", "exportation", "Partenaire d’accueil", "La diplomatie commerciale a besoin de cérémonies et d’une image maîtrisée.", "E/S", "alliance"],
  ["célébrants", "réanimateurs", "Légitimation utile", "Le récit public normalise la non-vie mais peut aussi cacher le sale travail.", "S", "cooperation"],
  ["célébrants", "uci", "Dépendance budgétaire", "Rivalité d’ascension, de prestige et de contrôle des dépenses.", "E", "hostility"],
  ["célébrants", "charretiers", "Réhabilitation ou discrédit", "La propagande peut restaurer le Consortium ou raviver son scandale.", "S/H", "tension"],
  ["exportation", "bâtisseurs", "Blocages traditionnels", "Les contrôles et les secrets ralentissent l’expansion commerciale.", "S", "tension"],
  ["exportation", "célébrants", "Allié de vitrine", "Alliance utile, avec une concurrence permanente pour l’influence.", "E/S", "alliance"],
  ["exportation", "réanimateurs", "Ennemi nécessaire", "L’image extérieure dépend pourtant de la production cadavérique.", "E", "hostility"],
  ["exportation", "uci", "Capital et contrôle", "Expansion rapide contre prudence, garanties et surveillance.", "S", "cooperation"],
  ["exportation", "charretiers", "Sous-traitant intérieur", "Partenaire logistique et rival de juridiction sur les cargaisons.", "S", "cooperation"],
  ["réanimateurs", "bâtisseurs", "Partenaire de chantier", "Travail et corps contre ouvrages, permis et infrastructures.", "S", "alliance"],
  ["réanimateurs", "célébrants", "Symbole national utile", "La légitimité publique s’accompagne de la peur d’être sacrifié lors d’un scandale.", "S", "cooperation"],
  ["réanimateurs", "exportation", "Allié officiel sous pression", "Les débouchés commerciaux sont vitaux malgré le mépris de la Guilde.", "E", "alliance"],
  ["réanimateurs", "uci", "Ennemi déclaré", "Taxes lourdes et mépris du travail productif.", "E", "hostility"],
  ["réanimateurs", "charretiers", "Distribution vitale", "Les cargaisons sensibles exigent fiabilité et confiance.", "S", "cooperation"],
  ["uci", "bâtisseurs", "Allié déclaré", "Coffres impénétrables, tradition et propriété institutionnelle.", "E", "alliance"],
  ["uci", "célébrants", "Ennemi déclaré", "Budget, prestige et ascension menacent le statu quo financier.", "E", "hostility"],
  ["uci", "exportation", "Investit et surveille", "Le rendement commercial doit rester contrôlable.", "S", "cooperation"],
  ["uci", "réanimateurs", "Taxe et méprise", "L’immense force de travail est une richesse à prélever et une puissance à contenir.", "E/S", "hostility"],
  ["uci", "charretiers", "Régulateur et créancier", "Péages, saisies et prêts maintiennent le Consortium sous tutelle.", "S/H", "tension"],
  ["charretiers", "bâtisseurs", "Dépendance routière", "Chaque route abandonnée nourrit le ressentiment envers les Grandes Factions.", "S", "tension"],
  ["charretiers", "célébrants", "Réhabilitation risquée", "Le Consortium veut retrouver sa place sans exposer son passé.", "S/H", "tension"],
  ["charretiers", "exportation", "Partenaire et rival", "Relais intérieur indispensable, mais concurrence sur les marges et la juridiction.", "S", "cooperation"],
  ["charretiers", "réanimateurs", "Client majeur", "Transporter corps et travailleurs expose le Consortium à des risques singuliers.", "S", "cooperation"],
  ["charretiers", "uci", "Contrôle mal accepté", "Le crédit est nécessaire, les péages et la tutelle restent humiliants.", "S/H", "tension"],
] as const;

export const mockRelationships: Relationship[] = relationshipRows.map((row, index) => ({
  id: `00000000-0000-4000-8300-${String(index + 1).padStart(12, "0")}`,
  campaign_id: CAMPAIGN_ID,
  source_faction_id: factionIds[row[0]],
  source_name: factionSeeds.find((f) => f[0] === row[0])![2],
  target_faction_id: factionIds[row[1]],
  target_name: factionSeeds.find((f) => f[0] === row[1])![2],
  headline: row[2],
  detail: row[3],
  evidence: row[4],
  tone: row[5],
  visibility: "gm_only",
}));

const dossierRows = [
  ["bâtisseurs", "célébrants", "Bâtisseurs ↔ Célébrants", "Célébrants : ennemi déclaré. Secrets et passages cachés contre maîtrise du récit public.", "La Ligue traite la communication comme une fuite et cherche à contrôler plans et accès.", "Les Célébrants voient chaque secret comme un récit abandonné à un rival.", "Monuments, processions, inaugurations et restauration prestigieuse.", "Qui décide ce que le public voit et ce que l’ouvrage dissimule ?", "Salle cachée ; fuite de plans ; cérémonie retardée ; faiblesse révélée.", "Inaugurer un monument dont la Ligue veut condamner la crypte et que les Célébrants veulent ouvrir.", "Explicite côté Célébrants ; synthèse côté Ligue."],
  ["bâtisseurs", "exportation", "Bâtisseurs ↔ Exportation", "La Ligue nomme la Guilde ennemie : étrangers et richesse menacent ses secrets.", "Contre-espionnage, permis, contrôle des plans et des infrastructures.", "La Guilde subit retards et coûts imposés par des traditionalistes.", "Ports, entrepôts, routes, quarantaine et production déplacée hors de vue.", "Vitesse et capacité contre contrôle et secret.", "Inspecteur étranger ; autorisation bloquée ; tunnel ; sabotage attribué.", "Concevoir un complexe souterrain : la Guilde impose le délai, la Ligue conserve les plans.", "Hostilité explicite ; coopération pragmatique synthétique."],
  ["bâtisseurs", "réanimateurs", "Bâtisseurs ↔ Réanimateurs", "Alliance explicite côté Bâtisseurs ; la main-d’œuvre morte-vivante est indispensable aux grands travaux.", "La Ligue contrôle plans, permis, accès et affectation du chantier.", "Les Réanimateurs veulent que leur travail, leurs corps et leurs pertes soient reconnus.", "Chantiers, infrastructures agricoles, sécurisation et récupération d’ouvriers.", "Responsabilité, propriété des corps et accès aux zones secrètes.", "Accident ; ouvriers détournés ; ossuaire découvert ; ordres contradictoires.", "Un effondrement révèle des corps réclamés sous un ouvrage que la Ligue veut cacher.", "Alliance explicite et synthèse de leurs domaines."],
  ["bâtisseurs", "uci", "Bâtisseurs ↔ UCI", "L’UCI nomme la Ligue alliée ; tradition, caveaux et structures impénétrables.", "La Ligue conçoit, autorise et garde les secrets techniques.", "L’UCI finance, possède, taxe et saisit.", "Banques, coffres, immobilier, péages et reconstruction.", "Propriété du projet, copie des plans et dépassement de coût.", "Défaut ; audit ; titre ancien ; plan copié ; permis lié à un prêt.", "Deux contrats concurrents rouvrent une banque : propriété à l’UCI ou contrôle technique à la Ligue.", "Alliance explicite côté UCI."],
  ["bâtisseurs", "charretiers", "Bâtisseurs ↔ Charretiers", "Routes et relais bâtis par la Ligue ; transport intérieur assuré par le Consortium.", "La Ligue traite facilement la faction déchue comme exécutant remplaçable.", "Les Charretiers vivent chaque route abandonnée comme le mépris des Grandes Factions.", "Ponts, relais, convois, réparations et déviations.", "Priorité des travaux, sécurité, péages et responsabilité.", "Pont fermé ; route vendue ; relais réquisitionné ; village oublié.", "Rouvrir la route de Pakged : permis complet ou réparation illégale avant la nuit.", "Synthèse des domaines ; ressentiment optionnel."],
  ["célébrants", "exportation", "Célébrants ↔ Exportation", "Partenariat officiel de vitrine ; la Guilde nomme les Célébrants alliés.", "Les Célébrants contrôlent le récit, la cérémonie et la visibilité.", "La Guilde contrôle invités, cargaisons et coût diplomatique.", "Délégations, cérémonies portuaires, captifs informés et promotion nationale.", "Spectacle contre discrétion et pragmatisme marchand.", "Invité offensé ; captif disputé ; cargaison indigne ; vérité gênante.", "Accueillir un émissaire : accord discret ou procession qui expose tout.", "Alliance explicite et arrangement fonctionnel."],
  ["célébrants", "réanimateurs", "Célébrants ↔ Réanimateurs", "Normalisation de la non-vie par le récit d’un côté, production de l’autre.", "Les Célébrants peuvent glorifier ou cacher le travail nécromantique.", "Les Réanimateurs gagnent en légitimité mais refusent d’être le fusible d’un scandale.", "Fêtes des récoltes, cérémonies d’animation et démonstrations de prospérité.", "Réalité industrielle macabre contre récit héroïque.", "Corps mal acquis ; accident visible ; pénurie ; dispute doctrinale.", "Banquet de récolte pendant un problème de contrôle des travailleurs exposé au public.", "Synthèse forte seulement."],
  ["célébrants", "uci", "Célébrants ↔ UCI", "Ennemis déclarés ; accès autonome aux coffres, dépenses et ascension contre statu quo.", "Les Célébrants convertissent l’argent en visibilité et influence.", "L’UCI voit gaspillage, perte de contrôle et menace sur le prestige ancien.", "Cérémonies, démonstrations de richesse et taxes sur événements.", "Budget, autonomie, audit et ancienneté.", "Dépassement ; don ostentatoire ; contrôle surprise ; saisie d’accessoires.", "Financer une procession : crédit immédiat contre audit public humiliant.", "Inimitié explicite."],
  ["célébrants", "charretiers", "Célébrants ↔ Charretiers", "Faction déchue après le scandale pharasméen ; les Célébrants contrôlent l’image publique.", "Les Célébrants peuvent réhabiliter le Consortium ou raviver le scandale.", "Les Charretiers offrent mobilisation, courrier et transport, mais craignent la publicité.", "Processions, déplacement de foules, matériel et rumeurs.", "Passé pharasméen et secret logistique contre visibilité.", "Vieille preuve ; conducteur indiscret ; convoi retardé ; loyauté exigée.", "Le manifeste d’une procession révèle une ancienne route liée au scandale.", "Disgrâce explicite ; réhabilitation optionnelle."],
  ["exportation", "réanimateurs", "Exportation ↔ Réanimateurs", "Asymétrie officielle : ennemi côté Exportation, allié côté Réanimateurs ; dépendance économique majeure.", "La Guilde veut cacher ou déplacer ce qui effraie ses partenaires.", "Les Réanimateurs ont besoin des débouchés mais refusent d’être traités comme une honte.", "Récoltes, travail, transport de masse, revenus et grands projets.", "Image, emplacement des fermes, conditions et partage de la valeur.", "Visite étrangère ; boycott ; cargaison contaminée ; déplacement forcé.", "Déplacer la production hors de vue, avec financement, chantier et propagande.", "Relation pivot explicitement détaillée."],
  ["exportation", "uci", "Exportation ↔ UCI", "Flux et profits rencontrent financement, taxes et surveillance.", "La Guilde investit vite et accepte le risque commercial.", "L’UCI veut rendement garanti, perception et stabilité.", "Crédit commercial, assurance, douanes et investissement portuaire.", "Ouverture contre prudence ; liquidité contre thésaurisation.", "Défaut ; saisie ; crédit refusé ; taxe nouvelle ; capital étranger.", "Importer un bien stratégique : ouverture décisive contre garantie impossible.", "Synthèse de leurs actifs et orientations."],
  ["exportation", "charretiers", "Exportation ↔ Charretiers", "Commerce extérieur et transport intérieur forment une chaîne sans alliance déclarée.", "La Guilde contrôle port, client étranger et documents d’entrée.", "Les Charretiers contrôlent le dernier trajet, les routes et la discrétion intérieure.", "Transbordement, manifestes, entrepôts et convois.", "Juridiction, marges, contrebande et responsabilité.", "Faux manifeste ; embargo ; route secrète ; cargaison suspecte.", "Une cargaison légale au port devient compromettante à l’intérieur.", "Synthèse des domaines et de la juridiction."],
  ["réanimateurs", "uci", "Réanimateurs ↔ UCI", "Ennemis déclarés côté Réanimateurs : taxes lourdes et mépris du travail productif.", "Les Réanimateurs revendiquent la richesse créée et la continuité de l’approvisionnement.", "L’UCI taxe, surveille et peut redouter cette immense force de travail.", "Revenus agricoles, inventaires, contrats et infrastructure rurale.", "Taxation, statut des corps, valeur du travail et saisie d’actifs.", "Audit ; saisie d’ouvriers ; taxe d’urgence ; fraude ; pénurie.", "Saisir une équipe pour arriérés fiscaux pendant une récolte critique.", "Inimitié explicite et synthèse économique."],
  ["réanimateurs", "charretiers", "Réanimateurs ↔ Charretiers", "Production cadavérique et agricole contre transport intérieur.", "Les Réanimateurs exigent conformité, fiabilité et respect de la propriété des corps.", "Les Charretiers assument un risque qu’ils ne comprennent pas toujours, sous soupçon pharasméen.", "Convois agricoles, corps, matériel et travailleurs.", "Propriété, manifestes, cargaisons animées et confiance.", "Corps volé ; cargaison animée ; chauffeur ignorant ; sabotage religieux.", "Un manifeste dit « outils agricoles » mais une partie est juridiquement une dépouille.", "Synthèse des domaines et du passé du Consortium."],
  ["uci", "charretiers", "UCI ↔ Charretiers", "Taxes, crédit, transport et relais contre ancienne Grande Faction déchue.", "L’UCI traite le Consortium comme débiteur, contribuable et outil logistique.", "Les Charretiers ressentent péages et tutelle mais ont besoin de crédit et de reconnaissance.", "Péages, financement, assurance, saisies et relais.", "Dette, autonomie et contrôle des flux.", "Hausse de péage ; saisie ; audit ; dette ancienne ; reprise de contrôle.", "Financer un relais contre l’abandon de l’autonomie sur la meilleure route.", "Statut et actifs explicites ; créancier optionnel."],
] as const;

export const mockDossiers: BilateralDossier[] = dossierRows.map((row, index) => ({
  id: `00000000-0000-4000-8400-${String(index + 1).padStart(12, "0")}`,
  campaign_id: CAMPAIGN_ID,
  faction_a_id: factionIds[row[0]],
  faction_b_id: factionIds[row[1]],
  pair_name: row[2],
  canon_core: row[3],
  a_to_b: row[4],
  b_to_a: row[5],
  common_interest: row[6],
  fracture: row[7],
  triggers: row[8],
  scene_hook: row[9],
  evidence_note: row[10],
}));

export const mockContacts: Contact[] = factionSeeds.map((faction, index) => {
  const values = [
    ["Représentant lié à la banque", "Inspection, permis et chantiers"],
    ["Se-Maut-Get", "Rumeurs, réception et influence"],
    ["Altinmered", "Commerce, cargaisons et accès"],
    ["Berline Haldoli", "Main-d’œuvre et nécromancie"],
    ["Vaskish", "Contrats, crédit et actifs"],
    ["Mauldor Gavvik", "Convois, routes et extraction"],
  ][index];
  const isBerline = faction[0] === "réanimateurs";
  return {
    id: `00000000-0000-4000-8500-${String(index + 1).padStart(12, "0")}`,
    campaign_id: CAMPAIGN_ID,
    faction_id: factionIds[faction[0]],
    faction_name: faction[2],
    name: values[0],
    role: values[1],
    state: isBerline ? "Actif" : "À introduire",
    attitude: isBerline ? "Favorable" : "Neutre",
    promise_debt: null,
    due_text: null,
    gm_notes: isBerline ? "Patronne du groupe à Griseplainte." : "Contact suggéré par l’aventure.",
    next_consequence: null,
    visibility: isBerline ? "players" : "gm_only",
    is_primary: true,
  };
});

export const mockJournal: JournalEntry[] = [{
  id: "00000000-0000-4000-8600-000000000001",
  campaign_id: CAMPAIGN_ID,
  faction_id: factionIds["réanimateurs"],
  faction_name: "Réanimateurs",
  occurred_on: "2026-05-10",
  volume: 1,
  title: "Crise de la ferme du vieux Hergag résolue",
  details: "Berline Haldoli fait connaître l’efficacité du groupe auprès de la Ligue des Réanimateurs.",
  rp_delta: 5,
  jf_delta: 5,
  tension_delta: 0,
  visibility: "players",
  source_reference: "Zombie Feast, p. 20",
}];

const milestoneRows = [
  ["Résoudre la crise de la ferme", "réanimateurs", 5, null, 0, "Récompense prévue par l’aventure."],
  ["Secourir Se-Maut-Get", "célébrants", 4, null, 0, "Se-Maut-Get doit survivre à l’aventure."],
  ["Libérer Altinmered", "exportation", 4, null, 0, "Libérer Altinmered."],
  ["Choisir la branche UCI de la banque", "uci", 8, "bâtisseurs", -4, "Choix exclusif avec la branche des Bâtisseurs."],
  ["Choisir la branche des Bâtisseurs", "bâtisseurs", 8, "uci", -4, "Choix exclusif avec la branche UCI."],
] as const;

export const mockMilestones: Milestone[] = milestoneRows.map((row, index) => ({
  id: `00000000-0000-4000-8700-${String(index + 1).padStart(12, "0")}`,
  campaign_id: CAMPAIGN_ID,
  volume: 1,
  chapter: null,
  title: row[0],
  beneficiary_faction_id: factionIds[row[1]],
  beneficiary_name: factionSeeds.find((f) => f[0] === row[1])![2],
  rp_gain: row[2],
  harmed_faction_id: row[3] ? factionIds[row[3]] : null,
  harmed_name: row[3] ? factionSeeds.find((f) => f[0] === row[3])![2] : null,
  rp_loss: row[4],
  condition: row[5],
  source_reference: "Blood Lords #1 — Zombie Feast",
  applied: index === 0,
  gm_notes: null,
}));

export const mockCampaignData: CampaignData = {
  settings: mockSettings,
  factions: mockFactions,
  journal: mockJournal,
  contacts: mockContacts,
  services: mockServices,
  relationships: mockRelationships,
  dossiers: mockDossiers,
  milestones: mockMilestones,
};

export const factionIdBySlug = factionIds;
