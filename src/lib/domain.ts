import type { CampaignSettings, FactionStatus, Service, ServiceScale } from "./types";

export function reputationStatus(rp: number, settings: CampaignSettings): FactionStatus {
  if (rp >= settings.revered_threshold) return "Révérés";
  if (rp >= settings.admired_threshold) return "Admirés";
  if (rp >= settings.liked_threshold) return "Appréciés";
  return "Indifférents";
}

export function tensionLabel(tension: number): string {
  if (tension <= 0) return "Stable";
  if (tension === 1) return "Signes de froid";
  if (tension === 2) return "Relations tendues";
  if (tension === 3) return "Accès limité";
  return "Rupture";
}

export function unlockedServices(rp: number, factionSlug: string, settings: CampaignSettings): string {
  const majorThreshold = factionSlug === "charretiers" ? settings.carters_major_threshold : settings.revered_threshold;
  if (rp >= majorThreshold) return factionSlug === "charretiers" ? "Mineure, modérée et majeure unique" : "Mineure, modérée et majeure";
  if (rp >= settings.admired_threshold) return "Mineure et modérée";
  if (rp >= settings.liked_threshold) return "Mineure";
  return "Aucun service de faveur";
}

export interface ServiceQuote {
  allowed: boolean;
  reason: string;
  cost: number;
  balanceAfter: number;
}

export function quoteService(
  service: Service,
  faction: { slug: string; rp: number; jf: number; tension: number },
  settings: CampaignSettings,
  advantage: "none" | "first_liked" | "admired_discount" = "none",
): ServiceQuote {
  const threshold = service.scale === "Majeure" && faction.slug === "charretiers"
    ? settings.carters_major_threshold
    : service.required_rp;
  let cost = service.base_cost;
  if (faction.tension === settings.tension_surcharge_level) cost += settings.tension_surcharge;
  if (advantage === "first_liked" && service.scale === "Mineure") cost = 0;
  if (advantage === "admired_discount" && service.scale === "Modérée") cost = Math.max(0, cost - settings.admired_discount);

  if (faction.tension >= settings.tension_max) return { allowed: false, reason: "Relation rompue", cost, balanceAfter: faction.jf };
  if (faction.tension >= 3 && service.scale !== "Mineure") return { allowed: false, reason: "Accès limité aux demandes mineures", cost, balanceAfter: faction.jf };
  if (faction.rp < threshold) return { allowed: false, reason: `Il faut ${threshold} RP`, cost, balanceAfter: faction.jf };
  if (faction.jf < cost) return { allowed: false, reason: "JF insuffisants", cost, balanceAfter: faction.jf };
  return { allowed: true, reason: "Demande autorisée", cost, balanceAfter: faction.jf - cost };
}

export const scaleRank: Record<ServiceScale, number> = { Mineure: 1, Modérée: 2, Majeure: 3 };
