import type { LootCurrency, LootEntry, LootLaneKind } from "./types";

const currencyToGp: Record<LootCurrency, number> = { pp: 10, gp: 1, sp: 0.1, cp: 0.01 };

/** Classement visuel dérivé uniquement des champs de la reconstruction neuve. */
export function lootLaneKind(item: LootEntry): LootLaneKind {
  if (item.source_kind === "chapter_checklist_only") return "unlocated";
  if (item.source_kind === "carried" || item.source_kind === "infused_carried") return "carried";
  if (item.loot_category === "objets_lootables_sur_les_corps") return "carried";
  return "treasure";
}

export function lootValueInGp(amount: number | null, currency: LootCurrency | null): number | null {
  if (amount === null || currency === null || !Number.isFinite(amount)) return null;
  return amount * currencyToGp[currency];
}

function quantityNumber(value: string): number | null {
  const parsed = Number(value.replace(",", "."));
  return Number.isFinite(parsed) ? parsed : null;
}

export function lootBookTotalValueInGp(item: LootEntry): number | null {
  const total = lootValueInGp(item.book_total_value_amount, item.book_total_value_currency);
  if (total !== null) return total;
  const unit = lootValueInGp(item.book_unit_value_amount, item.book_unit_value_currency);
  const quantity = quantityNumber(item.quantity_recoverable);
  return unit !== null && quantity !== null ? unit * quantity : null;
}

export function lootAonTotalValueInGp(item: LootEntry): number | null {
  const total = lootValueInGp(item.aon_legacy_total_value_amount, item.aon_legacy_total_value_currency);
  if (total !== null) return total;
  const unit = lootValueInGp(item.aon_legacy_unit_value_amount, item.aon_legacy_unit_value_currency);
  const quantity = quantityNumber(item.quantity_recoverable);
  return unit !== null && quantity !== null ? unit * quantity : null;
}

/** Le prix du livre prime lorsqu'il existe ; AoN complète uniquement les absences. */
export function lootTotalValueInGp(item: LootEntry): number | null {
  return lootBookTotalValueInGp(item) ?? lootAonTotalValueInGp(item);
}

export function formatLootValue(amount: number | null, currency: LootCurrency | null): string {
  if (amount === null || currency === null) return "—";
  return `${new Intl.NumberFormat("fr-CH", { maximumFractionDigits: 2 }).format(amount)} ${currency}`;
}

export function formatGoldValue(value: number) {
  return `${new Intl.NumberFormat("fr-CH", { maximumFractionDigits: 2 }).format(value)} gp`;
}
