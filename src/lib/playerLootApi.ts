import { supabase } from "./supabase";
import { anonymizeDemoLoot } from "../data/demoAnonymization";
import { formatLootValue } from "./lootMonitoring";
import type { PlayerLootEntry, PlayerLootLifecycleStatus } from "./types";

function requireClient() {
  if (!supabase) throw new Error("Configuration Supabase absente.");
  return supabase;
}

/** Ne lit que la projection publique, jamais la table complète des butins. */
export async function loadPlayerLoot(campaignId: string, demo = false): Promise<PlayerLootEntry[]> {
  if (demo) {
    const { lootSeeds } = await import("../data/referenceSeed");
    return anonymizeDemoLoot(lootSeeds)
      .filter((entry, index) => entry.player_visible === true || (entry.player_visible === undefined && index < 3))
      .map((entry, index) => ({
        campaign_id: entry.campaign_id,
        sort_order: entry.sort_order,
        original_name: entry.item_name,
        quantity: entry.quantity_recoverable,
        unit_value: entry.book_unit_value_amount !== null
          ? formatLootValue(entry.book_unit_value_amount, entry.book_unit_value_currency)
          : formatLootValue(entry.aon_legacy_unit_value_amount, entry.aon_legacy_unit_value_currency),
        location_name: entry.location_name || entry.area_title,
        aon_legacy_name: entry.aon_legacy_name,
        aon_legacy_url: entry.aon_legacy_url,
        loot_id: `demo-${entry.sort_order}`,
        published_on: localCalendarDate(),
        owner_user_id: index === 0 ? "demo-arsene" : null,
        owner_display_name: index === 0 ? "Prénom1 Nom1" : null,
        lifecycle_status: (index === 0 ? "assigned" : "available") as PlayerLootLifecycleStatus,
        legacy_owner_label: null,
      }));
  }

  const result = await requireClient()
    .from("player_loot")
    .select("campaign_id, sort_order, original_name, quantity, unit_value, location_name, aon_legacy_name, aon_legacy_url, loot_id, published_on, owner_user_id, owner_display_name, lifecycle_status, legacy_owner_label")
    .eq("campaign_id", campaignId)
    .order("published_on")
    .order("sort_order");
  if (result.error) throw new Error(`Butins partagés : ${result.error.message}`);
  return (result.data ?? []) as PlayerLootEntry[];
}

/** Édite uniquement la métadonnée de partage, jamais la fiche de référence. */
export async function savePlayerLootPublishedOn(lootId: string, publishedOn: string): Promise<void> {
  const result = await requireClient().rpc("set_player_loot_published_on", {
    p_loot_id: lootId,
    p_published_on: publishedOn,
  });
  if (result.error) throw new Error(`Date d’ajout : ${result.error.message}`);
}

/** Édite uniquement l’état partagé du butin, jamais la fiche de référence. */
export async function savePlayerLootAssignment(lootId: string, ownerUserId: string | null, lifecycleStatus: Exclude<PlayerLootLifecycleStatus, "legacy">): Promise<void> {
  const result = await requireClient().rpc("set_player_loot_assignment", {
    p_loot_id: lootId,
    p_owner_user_id: ownerUserId,
    p_lifecycle_status: lifecycleStatus,
  });
  if (result.error) throw new Error(`État du butin : ${result.error.message}`);
}

function localCalendarDate() {
  const now = new Date();
  const offset = now.getTimezoneOffset() * 60_000;
  return new Date(now.getTime() - offset).toISOString().slice(0, 10);
}
