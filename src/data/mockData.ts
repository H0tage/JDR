import type { CampaignData } from "../lib/types";

const CAMPAIGN_ID = "00000000-0000-4000-8000-000000000001";
const FACTION_1 = "00000000-0000-4000-8100-000000000001";
const FACTION_2 = "00000000-0000-4000-8100-000000000002";

/** Jeu de données public de démonstration, conçu pour n’exposer aucun scénario réel. */
export const mockCampaignData: CampaignData = {
  settings: { campaign_id: CAMPAIGN_ID, current_volume: 1, jf_cap: 20, minor_cost: 1, moderate_cost: 6, major_cost: 10, liked_threshold: 5, admired_threshold: 15, revered_threshold: 30, carters_major_threshold: 25, tension_max: 4, tension_surcharge_level: 2, tension_surcharge: 1, admired_discount: 1, show_numeric_tension: false, player_display_mode: "intuitive", show_all_player_balances: true },
  sessionPrep: { campaign_id: CAMPAIGN_ID, objective: "Objectif de démonstration.", scenes: "• Scène de démonstration", reminders: "Rappel de démonstration.", notes: "Notes de démonstration." },
  bestiary: [{ id: "demo-creature-1", campaign_id: CAMPAIGN_ID, name: "Créature 1", resistances: null, weaknesses: null, notes: "Notes de démonstration.", image_path: null }],
  questEntries: [{ id: "demo-quest-1", campaign_id: CAMPAIGN_ID, title: "Quête 1", notes: "Notes de démonstration.", status: "Actif", category: "Objectifs", sort_order: 1 }],
  questJournalPage: { campaign_id: CAMPAIGN_ID, content: "Contenu de démonstration." },
  questJournalRevisions: [],
  factions: [
    { campaign_id: CAMPAIGN_ID, faction_id: FACTION_1, slug: "faction-1", name: "Faction 1", short_name: "Faction 1", accent: "#9e7c35", domain: "Domaine 1", public_description: "Description de démonstration.", public_summary: null, gm_notes: "Notes MJ de démonstration.", is_player_visible: true, rp: 2, jf: 2, tension: 0, status: "Indifférents", tension_label: "Calme" },
    { campaign_id: CAMPAIGN_ID, faction_id: FACTION_2, slug: "faction-2", name: "Faction 2", short_name: "Faction 2", accent: "#6f8c86", domain: "Domaine 2", public_description: "Description de démonstration.", public_summary: null, gm_notes: "Notes MJ de démonstration.", is_player_visible: true, rp: 1, jf: 1, tension: 0, status: "Indifférents", tension_label: "Calme" },
  ],
  journal: [{ id: "demo-journal-1", campaign_id: CAMPAIGN_ID, faction_id: FACTION_1, faction_name: "Faction 1", occurred_on: "2026-01-01", volume: 1, title: "Événement 1", details: "Description de démonstration.", rp_delta: 1, jf_delta: 1, tension_delta: 0, visibility: "players", source_reference: null }],
  contacts: [{ id: "demo-contact-1", campaign_id: CAMPAIGN_ID, faction_id: FACTION_1, faction_name: "Faction 1", name: "Prénom1 Nom1", first_name: "Prénom1", last_name: "Nom1", role: "Contact de démonstration", public_description: "Description de démonstration.", image_path: null, avatar_x: 50, avatar_y: 50, avatar_zoom: 1, state: "Actif", attitude: "Neutre", promise_debt: null, due_text: null, gm_notes: "Notes MJ de démonstration.", player_character_notes: null, player_debt_notes: null, player_notes: null, visibility: "players", is_primary: true }],
  services: [
    { id: "demo-service-1", faction_id: FACTION_1, faction_name: "Faction 1", scale: "Mineure", required_rp: 1, base_cost: 1, domain: "Service de démonstration", examples: "Exemple de démonstration.", safeguard: "Condition de démonstration.", frequency: "Selon le MJ", player_visible: true },
    { id: "demo-service-2", faction_id: FACTION_1, faction_name: "Faction 1", scale: "Modérée", required_rp: 15, base_cost: 6, domain: "Service de démonstration", examples: "Exemple de démonstration.", safeguard: "Condition de démonstration.", frequency: "Selon le MJ", player_visible: true },
  ],
  relationships: [{ id: "demo-relationship-1", campaign_id: CAMPAIGN_ID, source_faction_id: FACTION_1, source_name: "Faction 1", target_faction_id: FACTION_2, target_name: "Faction 2", headline: "Relation 1", detail: "Description de démonstration.", color: "uncertain", evidence: "S", tone: "unclear", visibility: "players" }],
  dossiers: [],
  milestones: [{ id: "demo-milestone-1", campaign_id: CAMPAIGN_ID, volume: 1, chapter: "Étape 1", title: "Jalon 1", beneficiary_faction_id: FACTION_1, beneficiary_name: "Faction 1", rp_gain: 1, harmed_faction_id: null, harmed_name: null, rp_loss: 0, condition: "Condition de démonstration.", source_reference: "Référence de démonstration.", applied: false, gm_notes: null, sort_order: 1, status: "pending", resolution_note: null, choice_group: null, reward_effects: [{ label: "Effet 1", faction_id: FACTION_1, amount: 1 }], resolved_effects: null, resolved_at: null, excluded_by_milestone_id: null, status_before_exclusion: null }],
};

export const mockSettings = mockCampaignData.settings;
export const mockFactions = mockCampaignData.factions;
export const mockServices = mockCampaignData.services;
