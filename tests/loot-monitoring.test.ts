import { describe, expect, it } from "vitest";
import { lootAonTotalValueInGp, lootBookTotalValueInGp, lootLaneKind, lootTotalValueInGp, lootValueInGp } from "../src/lib/lootMonitoring";
import type { LootEntry } from "../src/lib/types";

function loot(patch: Partial<LootEntry> = {}): LootEntry {
  return {
    id: "loot-1", campaign_id: "campaign-1", reference_id: "bl-test", sort_order: 1,
    volume: 1, chapter: 1, source_page: 10, pdf_page: 12, stat_block_page: null,
    area_code: "A1", area_title: "ZONE", location_name: null, source_kind: "treasure",
    source_owner: null, source_text: null, item_name: "Objet", quantity_initial: "1",
    quantity_recoverable: "1", loot_category: null, acquisition_condition: null,
    consumable_during_encounter: false, availability_rule: null,
    book_unit_value_amount: null, book_unit_value_currency: null,
    book_total_value_amount: null, book_total_value_currency: null,
    aon_legacy_name: null, aon_legacy_unit_value_amount: null,
    aon_legacy_unit_value_currency: null, aon_legacy_total_value_amount: null,
    aon_legacy_total_value_currency: null, aon_legacy_url: null, pricing_basis: null,
    pricing_status: null, verification_status: null, discovery_status: "pending",
    player_visible: false, is_custom: false, ...patch,
  };
}

describe("monitoring des butins reconstruits", () => {
  it("convertit les quatre monnaies Pathfinder en pièces d'or", () => {
    expect(lootValueInGp(2, "pp")).toBe(20);
    expect(lootValueInGp(16, "gp")).toBe(16);
    expect(lootValueInGp(5, "sp")).toBe(.5);
    expect(lootValueInGp(1, "cp")).toBe(.01);
    expect(lootValueInGp(null, null)).toBeNull();
  });

  it("conserve séparément les valeurs du livre et d'AoN", () => {
    const item = loot({
      quantity_recoverable: "3",
      book_unit_value_amount: 2, book_unit_value_currency: "gp",
      aon_legacy_unit_value_amount: 4, aon_legacy_unit_value_currency: "gp",
    });
    expect(lootBookTotalValueInGp(item)).toBe(6);
    expect(lootAonTotalValueInGp(item)).toBe(12);
    expect(lootTotalValueInGp(item)).toBe(6);
  });

  it("classe les lignes depuis les catégories neuves uniquement", () => {
    expect(lootLaneKind(loot({ source_kind: "carried" }))).toBe("carried");
    expect(lootLaneKind(loot({ source_kind: "treasure", loot_category: "objets_lootables_sur_les_corps" }))).toBe("carried");
    expect(lootLaneKind(loot({ source_kind: "chapter_checklist_only" }))).toBe("unlocated");
    expect(lootLaneKind(loot({ source_kind: "reward" }))).toBe("treasure");
  });
});
