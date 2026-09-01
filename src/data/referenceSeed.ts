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

function demoLoot(sortOrder: number, patch: Partial<LootEntry>): LootEntry {
  return {
    id: `demo-loot-${sortOrder}`, campaign_id: DEMO_CAMPAIGN_ID, reference_id: `demo-loot-${sortOrder}`,
    sort_order: sortOrder, volume: 1, chapter: 1, source_page: null, pdf_page: null,
    stat_block_page: null, area_code: null, area_title: null, location_name: null,
    source_kind: "treasure", source_owner: null, source_text: "Extrait de démonstration anonymisé.",
    item_name: `Item de démonstration ${sortOrder}`, quantity_initial: "1", quantity_recoverable: "1",
    loot_category: null, acquisition_condition: null, consumable_during_encounter: false,
    availability_rule: null, book_unit_value_amount: null, book_unit_value_currency: null,
    book_total_value_amount: null, book_total_value_currency: null, aon_legacy_name: null,
    aon_legacy_unit_value_amount: null, aon_legacy_unit_value_currency: null,
    aon_legacy_total_value_amount: null, aon_legacy_total_value_currency: null,
    aon_legacy_url: null, pricing_basis: null, pricing_status: null, verification_status: "demo",
    discovery_status: "pending", player_visible: false, is_custom: false, ...patch,
  };
}

export const lootSeeds: LootEntry[] = [
  demoLoot(1, { area_code: "A3", location_name: "Lieu 1", book_unit_value_amount: 10, book_unit_value_currency: "gp", book_total_value_amount: 10, book_total_value_currency: "gp", aon_legacy_name: "Référence AoN", aon_legacy_url: "https://2e.aonprd.com/Weapons.aspx?ID=43&NoRedirect=1", discovery_status: "found", player_visible: true, acquisition_condition: "Visible après avoir fouillé la pièce." }),
  demoLoot(2, { area_code: "A5", location_name: "Lieu 1", quantity_initial: "2", quantity_recoverable: "2", book_unit_value_amount: 5, book_unit_value_currency: "gp", book_total_value_amount: 10, book_total_value_currency: "gp", acquisition_condition: "Nécessite une recherche réussie." }),
  demoLoot(3, { area_code: "A7", location_name: "Lieu 1", source_kind: "carried", source_owner: "Créature 1", loot_category: "objets_lootables_sur_les_corps", aon_legacy_name: "Référence AoN", aon_legacy_unit_value_amount: 8, aon_legacy_unit_value_currency: "gp", aon_legacy_total_value_amount: 8, aon_legacy_total_value_currency: "gp", aon_legacy_url: "https://2e.aonprd.com/Armor.aspx?ID=4&NoRedirect=1", acquisition_condition: "Récupérable si l’objet est encore intact." }),
  demoLoot(4, { area_code: "B2", location_name: "Lieu 2", source_kind: "carried", source_owner: "Créatures 2 à 4", loot_category: "objets_lootables_sur_les_corps", quantity_initial: "3", quantity_recoverable: "3", book_unit_value_amount: 2, book_unit_value_currency: "gp", book_total_value_amount: 6, book_total_value_currency: "gp", discovery_status: "found", player_visible: true }),
  demoLoot(5, { area_code: "B6", location_name: "Lieu 2", source_kind: "reward", book_unit_value_amount: 25, book_unit_value_currency: "gp", book_total_value_amount: 25, book_total_value_currency: "gp", discovery_status: "missed", acquisition_condition: "Disponible uniquement si une condition narrative est remplie." }),
  demoLoot(6, { volume: 2, source_page: 42, source_kind: "chapter_checklist_only", aon_legacy_name: "Référence AoN", aon_legacy_unit_value_amount: 3, aon_legacy_unit_value_currency: "gp", aon_legacy_total_value_amount: 3, aon_legacy_total_value_currency: "gp", aon_legacy_url: "https://2e.aonprd.com/Equipment.aspx?ID=245&NoRedirect=1" }),
];
