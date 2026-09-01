import type { ArchiveCharacter, ArchivePlace, ArchivesData, CampaignData, LootEntry } from "../lib/types";

const redacted = (value: string | null | undefined, replacement: string) => value ? replacement : null;

export function demoPerson(index: number) {
  const number = index + 1;
  return { firstName: `Prénom${number}`, lastName: `Nom${number}`, fullName: `Prénom${number} Nom${number}` };
}

export function anonymizeDemoCampaignData(source: CampaignData): CampaignData {
  const data = structuredClone(source);
  const factionNames = new Map(data.factions.map((faction, index) => [faction.faction_id, `Faction ${index + 1}`]));
  const milestoneTitles = new Map(data.milestones.map((milestone, index) => [milestone.id, `Jalon ${index + 1}`]));
  const choiceGroups = new Map<string, string>();

  data.sessionPrep = {
    ...data.sessionPrep,
    objective: redacted(data.sessionPrep.objective, "Objectif anonymisé."),
    scenes: redacted(data.sessionPrep.scenes, "• Scène anonymisée 1\n• Scène anonymisée 2\n• Scène anonymisée 3"),
    reminders: redacted(data.sessionPrep.reminders, "Rappel anonymisé."),
    notes: redacted(data.sessionPrep.notes, "Notes anonymisées."),
  };

  data.bestiary = data.bestiary.map((entry, index) => ({
    ...entry,
    name: `Créature ${index + 1}`,
    resistances: redacted(entry.resistances, "Résistances anonymisées"),
    weaknesses: redacted(entry.weaknesses, "Faiblesses anonymisées"),
    notes: redacted(entry.notes, "Notes anonymisées."),
    image_path: null,
  }));
  data.questEntries = data.questEntries.map((entry, index) => ({
    ...entry,
    title: `Quête ${index + 1}`,
    notes: redacted(entry.notes, "Notes anonymisées."),
  }));
  data.questJournalPage = { ...data.questJournalPage, content: data.questJournalPage.content ? "Contenu de démonstration anonymisé." : "" };
  data.questJournalRevisions = data.questJournalRevisions.map((revision) => ({ ...revision, content: "Contenu de démonstration anonymisé." }));

  data.factions = data.factions.map((faction, index) => ({
    ...faction,
    name: `Faction ${index + 1}`,
    short_name: `Faction ${index + 1}`,
    domain: `Domaine ${index + 1}`,
    public_description: "Description anonymisée.",
    public_summary: redacted(faction.public_summary, "Résumé anonymisé."),
    gm_notes: redacted(faction.gm_notes, "Notes MJ anonymisées."),
  }));
  data.journal = data.journal.map((entry, index) => ({
    ...entry,
    faction_name: factionNames.get(entry.faction_id),
    title: `Événement ${index + 1}`,
    details: redacted(entry.details, "Description anonymisée."),
    source_reference: redacted(entry.source_reference, "Référence anonymisée"),
  }));
  data.contacts = data.contacts.map((contact, index) => {
    const person = demoPerson(index);
    return {
      ...contact,
      faction_name: factionNames.get(contact.faction_id),
      name: person.fullName,
      first_name: person.firstName,
      last_name: person.lastName,
      role: `Rôle anonymisé ${index + 1}`,
      public_description: redacted(contact.public_description, "Description anonymisée."),
      image_path: null,
      promise_debt: redacted(contact.promise_debt, "Promesse anonymisée."),
      due_text: redacted(contact.due_text, "Échéance anonymisée."),
      gm_notes: redacted(contact.gm_notes, "Notes MJ anonymisées."),
      player_character_notes: redacted(contact.player_character_notes, "Repères anonymisés."),
      player_debt_notes: redacted(contact.player_debt_notes, "Dette anonymisée."),
      player_notes: redacted(contact.player_notes, "Notes anonymisées."),
    };
  });
  data.services = data.services.map((service, index) => ({
    ...service,
    faction_name: factionNames.get(service.faction_id),
    domain: `Service anonymisé ${index + 1}`,
    examples: "Exemples anonymisés.",
    safeguard: "Condition anonymisée.",
    frequency: "Fréquence anonymisée.",
  }));
  data.relationships = data.relationships.map((relationship, index) => ({
    ...relationship,
    source_name: factionNames.get(relationship.source_faction_id) ?? "Faction",
    target_name: factionNames.get(relationship.target_faction_id) ?? "Faction",
    headline: `Relation ${index + 1}`,
    detail: "Description anonymisée.",
    default_headline: relationship.default_headline === undefined ? undefined : `Relation ${index + 1}`,
    default_detail: relationship.default_detail === undefined ? undefined : "Description anonymisée.",
    headline_override: redacted(relationship.headline_override, `Relation ${index + 1}`),
    detail_override: redacted(relationship.detail_override, "Description anonymisée."),
  }));
  data.dossiers = data.dossiers.map((dossier, index) => ({
    ...dossier,
    pair_name: `${factionNames.get(dossier.faction_a_id) ?? "Faction"} ↔ ${factionNames.get(dossier.faction_b_id) ?? "Faction"}`,
    canon_core: `Dossier anonymisé ${index + 1}.`,
    a_to_b: "Point de vue anonymisé.",
    b_to_a: "Point de vue anonymisé.",
    common_interest: "Intérêt commun anonymisé.",
    fracture: "Point de friction anonymisé.",
    triggers: "Déclencheurs anonymisés.",
    scene_hook: "Accroche de scène anonymisée.",
    evidence_note: "Référence anonymisée.",
  }));
  data.milestones = data.milestones.map((milestone, index) => {
    let choiceGroup = milestone.choice_group;
    if (choiceGroup) {
      if (!choiceGroups.has(choiceGroup)) choiceGroups.set(choiceGroup, `choix-demo-${choiceGroups.size + 1}`);
      choiceGroup = choiceGroups.get(choiceGroup) ?? null;
    }
    return {
      ...milestone,
      chapter: milestone.chapter ? `Étape ${index + 1}` : null,
      title: `Jalon ${index + 1}`,
      beneficiary_name: milestone.beneficiary_faction_id ? factionNames.get(milestone.beneficiary_faction_id) ?? null : null,
      harmed_name: milestone.harmed_faction_id ? factionNames.get(milestone.harmed_faction_id) ?? null : null,
      condition: "Condition anonymisée.",
      source_reference: "Référence anonymisée",
      gm_notes: redacted(milestone.gm_notes, "Notes MJ anonymisées."),
      resolution_note: redacted(milestone.resolution_note, "Résolution anonymisée."),
      choice_group: choiceGroup,
      reward_effects: milestone.reward_effects.map((effect, effectIndex) => ({ ...effect, label: `Effet ${effectIndex + 1}` })),
      resolved_effects: milestone.resolved_effects?.map((effect, effectIndex) => ({ ...effect, label: `Effet ${effectIndex + 1}` })) ?? null,
      excluded_by_title: milestone.excluded_by_milestone_id ? milestoneTitles.get(milestone.excluded_by_milestone_id) ?? null : null,
    };
  });
  return data;
}

export function anonymizeDemoArchives(characters: ArchiveCharacter[], places: ArchivePlace[]): ArchivesData {
  return {
    characters: structuredClone(characters).map((entry, index) => {
      const person = demoPerson(index);
      return {
        ...entry,
        first_name: person.firstName,
        last_name: person.lastName,
        translated_name: null,
        translation_origin: "none",
        role_text: redacted(entry.role_text, `Rôle anonymisé ${index + 1}`),
        first_page: null,
      };
    }),
    places: structuredClone(places).map((entry, index) => ({
      ...entry,
      original_name: `Lieu ${index + 1}`,
      translated_name: null,
      translation_origin: "none",
      place_type: redacted(entry.place_type, "Type anonymisé"),
      function_text: redacted(entry.function_text, "Description anonymisée."),
      first_page: null,
    })),
    show_translations: false,
  };
}

export function anonymizeDemoLoot(entries: LootEntry[]): LootEntry[] {
  const locations = new Map<string, string>();
  return structuredClone(entries).map((entry, index) => {
    let locationName: string | null = null;
    if (entry.location_name) {
      if (!locations.has(entry.location_name)) locations.set(entry.location_name, `Lieu ${locations.size + 1}`);
      locationName = locations.get(entry.location_name) ?? null;
    }
    return {
      ...entry,
      item_name: `Item anonymisé ${index + 1}`,
      source_text: redacted(entry.source_text, "Extrait anonymisé."),
      location_name: locationName,
      area_code: null,
      area_title: redacted(entry.area_title, "Zone anonymisée"),
      source_page: null,
      pdf_page: null,
      stat_block_page: null,
      source_owner: redacted(entry.source_owner, `Créature ${index + 1}`),
      aon_legacy_name: redacted(entry.aon_legacy_name, "Référence AoN de démonstration"),
      aon_legacy_url: entry.aon_legacy_url ? "https://2e.aonprd.com/Weapons.aspx?ID=43&NoRedirect=1" : null,
      acquisition_condition: redacted(entry.acquisition_condition, "Condition de récupération anonymisée."),
      availability_rule: redacted(entry.availability_rule, "Règle de disponibilité anonymisée."),
      pricing_basis: redacted(entry.pricing_basis, "Base de prix anonymisée."),
    };
  });
}
