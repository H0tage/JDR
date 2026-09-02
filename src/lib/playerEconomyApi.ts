import { currentSession } from "./api";
import { supabase } from "./supabase";
import type {
  CampaignInventoryItem,
  CampaignEconomyTotals,
  CampaignItemEvent,
  CampaignItemRequest,
  CampaignMoneyBalance,
  CampaignMoneyDebt,
  CampaignMoneyTransaction,
  PlayerEconomyData,
} from "./types";

export type MoneyUnit = "gp" | "sp" | "cp";

function client() {
  if (!supabase) throw new Error("Configuration Supabase absente.");
  return supabase;
}

function check(error: { message: string } | null, label: string) {
  if (error) throw new Error(`${label} : ${error.message}`);
}

const demoItems: CampaignInventoryItem[] = [
  { id: "demo-item-1", campaign_id: "demo", origin_loot_id: "demo-loot-1", parent_item_id: null, created_by: null, owner_user_id: null, owner_display_name: null, created_by_display_name: null, name: "Item anonymisé 1", quantity: 3, source_quantity_label: "3", unit_value_cp: 400, purchase_price_cp: null, aon_legacy_name: null, aon_legacy_url: null, source_kind: "loot", player_visible: true, status: "active", acquired_on: "2026-08-10", created_at: "2026-08-10T18:00:00Z", updated_at: "2026-08-10T18:00:00Z", pending_request_count: 0, requested_by_me: false },
  { id: "demo-item-2", campaign_id: "demo", origin_loot_id: "demo-loot-2", parent_item_id: null, created_by: null, owner_user_id: "demo-arsene", owner_display_name: "Prénom1 Nom1", created_by_display_name: null, name: "Item anonymisé 2", quantity: 1, source_quantity_label: "1", unit_value_cp: 3500, purchase_price_cp: null, aon_legacy_name: null, aon_legacy_url: null, source_kind: "loot", player_visible: true, status: "active", acquired_on: "2026-08-10", created_at: "2026-08-10T18:05:00Z", updated_at: "2026-08-10T18:05:00Z", pending_request_count: 1, requested_by_me: false },
  { id: "demo-item-3", campaign_id: "demo", origin_loot_id: null, parent_item_id: null, created_by: "demo-arsene", owner_user_id: "demo-morrigan", owner_display_name: "Prénom2 Nom2", created_by_display_name: "Prénom1 Nom1", name: "Item anonymisé 3", quantity: 2, source_quantity_label: "2", unit_value_cp: 1200, purchase_price_cp: 2400, aon_legacy_name: null, aon_legacy_url: null, source_kind: "purchase", player_visible: true, status: "active", acquired_on: "2026-08-12", created_at: "2026-08-12T18:00:00Z", updated_at: "2026-08-12T18:00:00Z", pending_request_count: 0, requested_by_me: false },
  { id: "demo-item-4", campaign_id: "demo", origin_loot_id: null, parent_item_id: null, created_by: null, owner_user_id: "demo-nox", owner_display_name: "Prénom4 Nom4", created_by_display_name: "MaîtreDuJeu", name: "Item anonymisé 4", quantity: 1, source_quantity_label: "1", unit_value_cp: 1800, purchase_price_cp: null, aon_legacy_name: null, aon_legacy_url: null, source_kind: "gm", player_visible: true, status: "active", acquired_on: "2026-08-14", created_at: "2026-08-14T18:00:00Z", updated_at: "2026-08-14T18:00:00Z", pending_request_count: 0, requested_by_me: false },
];

function demoEconomy(): PlayerEconomyData {
  return {
    viewer_user_id: "demo-arsene",
    items: demoItems,
    balances: [
      { campaign_id: "demo", account_user_id: null, display_name: "Pot commun", is_common: true, balance_cp: 12_850 },
      { campaign_id: "demo", account_user_id: "demo-arsene", display_name: "Prénom1 Nom1", is_common: false, balance_cp: 3_400 },
      { campaign_id: "demo", account_user_id: "demo-morrigan", display_name: "Prénom2 Nom2", is_common: false, balance_cp: -800 },
      { campaign_id: "demo", account_user_id: "demo-silas", display_name: "Prénom3 Nom3", is_common: false, balance_cp: 2_250 },
      { campaign_id: "demo", account_user_id: "demo-nox", display_name: "Prénom4 Nom4", is_common: false, balance_cp: 1_500 },
    ],
    totals: { campaign_id: "demo", total_entered_cp: 42_750, total_exited_cp: 8_600 },
    money_history: [],
    item_history: [],
    requests: [{ id: "demo-request-1", campaign_id: "demo", item_id: "demo-item-2", item_name: "Item anonymisé 2", requester_user_id: "demo-morrigan", requester_display_name: "Prénom2 Nom2", owner_user_id: "demo-arsene", owner_display_name: "Prénom1 Nom1", status: "pending", created_at: "2026-08-13T18:00:00Z", resolved_at: null }],
    debts: [],
  };
}

export async function loadPlayerEconomy(campaignId: string, demo = false): Promise<PlayerEconomyData> {
  if (demo) return demoEconomy();
  const session = await currentSession();
  if (!session) throw new Error("Connexion requise.");
  const api = client();
  const [items, balances, totals, moneyHistory, itemHistory, requests, debts] = await Promise.all([
    api.from("player_inventory_items").select("*").eq("campaign_id", campaignId).order("acquired_on", { ascending: false }).order("created_at", { ascending: false }),
    api.from("player_money_balances").select("*").eq("campaign_id", campaignId).order("is_common", { ascending: false }).order("display_name"),
    api.from("player_economy_totals").select("*").eq("campaign_id", campaignId).maybeSingle(),
    api.from("player_money_history").select("*").eq("campaign_id", campaignId).order("created_at", { ascending: false }).limit(200),
    api.from("player_item_history").select("*").eq("campaign_id", campaignId).order("created_at", { ascending: false }).limit(500),
    api.from("player_item_request_overview").select("*").eq("campaign_id", campaignId).order("created_at", { ascending: false }),
    api.from("player_money_debt_overview").select("*").eq("campaign_id", campaignId).order("created_at", { ascending: false }),
  ]);
  check(items.error, "Inventaire");
  check(balances.error, "Soldes");
  check(totals.error, "Totaux historiques");
  check(moneyHistory.error, "Historique financier");
  check(itemHistory.error, "Historique des objets");
  check(requests.error, "Demandes d’objets");
  check(debts.error, "Dettes");
  return {
    viewer_user_id: session.user.id,
    items: (items.data ?? []) as CampaignInventoryItem[],
    balances: (balances.data ?? []) as CampaignMoneyBalance[],
    totals: (totals.data ?? { campaign_id: campaignId, total_entered_cp: 0, total_exited_cp: 0 }) as CampaignEconomyTotals,
    money_history: (moneyHistory.data ?? []) as CampaignMoneyTransaction[],
    item_history: (itemHistory.data ?? []) as CampaignItemEvent[],
    requests: (requests.data ?? []) as CampaignItemRequest[],
    debts: (debts.data ?? []) as CampaignMoneyDebt[],
  };
}

async function rpc(name: string, params: Record<string, unknown>, label: string) {
  const result = await client().rpc(name, params);
  check(result.error, label);
  return result.data;
}

export const assignInventoryItem = (itemId: string, targetUserId: string, comment?: string) => rpc("assign_campaign_item", { p_item_id: itemId, p_target_user_id: targetUserId, p_comment: comment || null }, "Attribution");
export const returnInventoryItem = (itemId: string, comment?: string) => rpc("return_campaign_item_to_common", { p_item_id: itemId, p_comment: comment || null }, "Retour au pot commun");
export const splitInventoryItem = (itemId: string, quantity: number) => rpc("split_campaign_item", { p_item_id: itemId, p_quantity: quantity }, "Fractionnement");
export const mergeInventoryItems = (targetItemId: string, sourceItemId: string) => rpc("merge_campaign_items", { p_target_item_id: targetItemId, p_source_item_id: sourceItemId }, "Fusion");
export const batchUpdateInventoryItems = (itemIds: string[], action: "assign" | "return" | "consumed" | "lost" | "donated", targetUserId?: string | null, comment?: string) => rpc("batch_update_campaign_items", { p_item_ids: itemIds, p_action: action, p_target_user_id: targetUserId ?? null, p_comment: comment || null }, "Action groupée");
export const setInventoryItemTerminal = (itemId: string, status: "consumed" | "lost" | "donated", quantity?: number, comment?: string) => rpc("set_campaign_item_terminal", { p_item_id: itemId, p_status: status, p_quantity: quantity ?? null, p_comment: comment || null }, "État de l’objet");
export const sellInventoryItem = (itemId: string, quantity: number, amountCp: number, comment?: string) => rpc("sell_campaign_item", { p_item_id: itemId, p_quantity: quantity, p_amount_cp: amountCp, p_comment: comment || null }, "Vente");
export const cancelItemEvent = (eventId: string, comment?: string) => rpc("cancel_campaign_item_event", { p_event_id: eventId, p_comment: comment || null }, "Annulation");
export const dismantleInventoryItem = (itemId: string, outputs: Array<{ name: string; quantity: number; unit_value_cp: number | null; aon_legacy_name?: string; aon_legacy_url?: string }>, comment?: string) => rpc("dismantle_campaign_item", { p_item_id: itemId, p_outputs: outputs, p_comment: comment || null }, "Démontage");
export const requestInventoryItem = (itemId: string) => rpc("request_campaign_item", { p_item_id: itemId }, "Demande d’objet");
export const resolveItemRequest = (requestId: string, accept: boolean) => rpc("resolve_campaign_item_request", { p_request_id: requestId, p_accept: accept }, "Réponse à la demande");
export const cancelItemRequest = (requestId: string) => rpc("cancel_campaign_item_request", { p_request_id: requestId }, "Annulation de la demande");

export const recordPersonalMoney = (campaignId: string, kind: "income" | "expense", amountCp: number, comment?: string, userId?: string) => rpc("record_personal_money", { p_campaign_id: campaignId, p_kind: kind, p_amount_cp: amountCp, p_user_id: userId ?? null, p_comment: comment || null }, "Opération personnelle");
export const recordCommonIncome = (campaignId: string, amountCp: number, comment?: string) => rpc("record_common_income", { p_campaign_id: campaignId, p_amount_cp: amountCp, p_comment: comment || null }, "Entrée commune");
export const transferMoney = (campaignId: string, sourceUserId: string | null, destinationUserId: string | null, amountCp: number, comment?: string) => rpc("transfer_campaign_money", { p_campaign_id: campaignId, p_source_user_id: sourceUserId, p_destination_user_id: destinationUserId, p_amount_cp: amountCp, p_comment: comment || null }, "Transfert");
export const cancelMoneyTransaction = (transactionId: string, comment?: string) => rpc("cancel_campaign_money_transaction", { p_transaction_id: transactionId, p_comment: comment || null }, "Annulation");

export const purchaseInventoryItem = (input: { campaignId: string; name: string; quantity: number; priceCp: number; personalAmountCp: number; commonAmountCp: number; ownerUserId?: string; unitValueCp?: number | null; aonName?: string; aonUrl?: string; comment?: string }) => rpc("purchase_campaign_item", { p_campaign_id: input.campaignId, p_name: input.name, p_quantity: input.quantity, p_price_cp: input.priceCp, p_personal_amount_cp: input.personalAmountCp, p_common_amount_cp: input.commonAmountCp, p_owner_user_id: input.ownerUserId ?? null, p_unit_value_cp: input.unitValueCp ?? null, p_aon_legacy_name: input.aonName || null, p_aon_legacy_url: input.aonUrl || null, p_comment: input.comment || null }, "Achat");
export const createManualInventoryItem = (input: { campaignId: string; name: string; quantity: number; unitValueCp?: number | null; ownerUserId?: string | null; aonName?: string; aonUrl?: string; comment?: string }) => rpc("create_manual_campaign_item", { p_campaign_id: input.campaignId, p_name: input.name, p_quantity: input.quantity, p_unit_value_cp: input.unitValueCp ?? null, p_owner_user_id: input.ownerUserId ?? null, p_aon_legacy_name: input.aonName || null, p_aon_legacy_url: input.aonUrl || null, p_comment: input.comment || null }, "Création de l’objet");

export const createMoneyDebt = (campaignId: string, debtorUserId: string, creditorUserId: string, amountCp: number, comment?: string) => rpc("create_campaign_money_debt", { p_campaign_id: campaignId, p_debtor_user_id: debtorUserId, p_creditor_user_id: creditorUserId, p_amount_cp: amountCp, p_comment: comment || null }, "Création de la dette");
export const payMoneyDebt = (debtId: string, amountCp: number, comment?: string) => rpc("pay_campaign_money_debt", { p_debt_id: debtId, p_amount_cp: amountCp, p_comment: comment || null }, "Remboursement");
export const cancelMoneyDebt = (debtId: string) => rpc("cancel_campaign_money_debt", { p_debt_id: debtId }, "Annulation de la dette");

export function moneyToCp(amount: number, unit: MoneyUnit): number {
  return Math.round(amount * (unit === "gp" ? 100 : unit === "sp" ? 10 : 1));
}

export function formatCopper(value: number | null): string {
  if (value === null) return "—";
  const sign = value < 0 ? "−" : "";
  let remaining = Math.abs(Math.trunc(value));
  const gp = Math.floor(remaining / 100);
  remaining %= 100;
  const sp = Math.floor(remaining / 10);
  const cp = remaining % 10;
  const parts = [];
  if (gp) parts.push(`${gp} po`);
  if (sp) parts.push(`${sp} pa`);
  if (cp || parts.length === 0) parts.push(`${cp} pc`);
  return sign + parts.join(" ");
}
