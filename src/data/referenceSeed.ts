import type { ArchiveCharacter, ArchivePlace, LootEntry } from "../lib/types";

const DEMO_CAMPAIGN_ID = "00000000-0000-4000-8000-000000000001";

/** Données de démonstration volontairement génériques, sans contenu de campagne. */
export const archiveCharacterSeeds: ArchiveCharacter[] = [
  { id: "demo-person-1", campaign_id: DEMO_CAMPAIGN_ID, template_key: "demo-person-1", sort_order: 1, first_name: "Prénom1", last_name: "Nom1", translated_name: null, translation_origin: "none", role_text: "Contact de démonstration.", first_volume: 1, first_page: null, is_custom: false },
  { id: "demo-person-2", campaign_id: DEMO_CAMPAIGN_ID, template_key: "demo-person-2", sort_order: 2, first_name: "Prénom2", last_name: "Nom2", translated_name: null, translation_origin: "none", role_text: "Contact de démonstration.", first_volume: 1, first_page: null, is_custom: false },
];

export const archivePlaceSeeds: ArchivePlace[] = [
  { id: "demo-place-1", campaign_id: DEMO_CAMPAIGN_ID, template_key: "demo-place-1", sort_order: 1, original_name: "Lieu 1", translated_name: null, translation_origin: "none", place_type: "Lieu", function_text: "Lieu de démonstration.", first_volume: 1, first_page: null, is_custom: false },
  { id: "demo-place-2", campaign_id: DEMO_CAMPAIGN_ID, template_key: "demo-place-2", sort_order: 2, original_name: "Lieu 2", translated_name: null, translation_origin: "none", place_type: "Lieu", function_text: "Lieu de démonstration.", first_volume: 2, first_page: null, is_custom: false },
];

export const lootSeeds: LootEntry[] = [
  { id: "demo-loot-1", campaign_id: DEMO_CAMPAIGN_ID, template_key: "demo-loot-1", sort_order: 1, original_name: "Item de démonstration 1", quantity: "1", description: "Description de démonstration.", unit_value: "10 gp", total_value: "10 gp", location_name: "Lieu 1", position: null, volume: 1, page: null, nature: "Objet", notes: null, is_custom: false, player_visible: true },
  { id: "demo-loot-2", campaign_id: DEMO_CAMPAIGN_ID, template_key: "demo-loot-2", sort_order: 2, original_name: "Item de démonstration 2", quantity: "2", description: "Description de démonstration.", unit_value: "5 gp", total_value: "10 gp", location_name: "Lieu 2", position: null, volume: 2, page: null, nature: "Objet", notes: null, is_custom: false, player_visible: false },
];
