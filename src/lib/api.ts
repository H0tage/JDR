import { mockCampaignData } from "../data/mockData";
import { supabase } from "./supabase";
import type {
  CampaignData,
  CampaignSettings,
  Contact,
  JournalEntry,
  MilestoneEffect,
  MilestoneStatus,
  Relationship,
  Visibility,
} from "./types";

const CAMPAIGN_SLUG = "blood-lords";

function requireClient() {
  if (!supabase) throw new Error("Configuration Supabase absente.");
  return supabase;
}

function unwrap<T>(result: { data: T | null; error: { message: string } | null }, label: string): NonNullable<T> {
  if (result.error) throw new Error(`${label} : ${result.error.message}`);
  if (result.data === null) throw new Error(`${label} : aucune donnée reçue.`);
  return result.data as NonNullable<T>;
}

function normalizeVisibility<T extends { visibility: string }>(items: T[]): T[] {
  return items.map((item) => ({
    ...item,
    visibility: item.visibility === "players" ? "players" : "gm_only",
  })) as T[];
}

export async function loadGmData(demo = false): Promise<CampaignData> {
  if (demo) return structuredClone(mockCampaignData);
  const client = requireClient();
  const campaign = unwrap(
    await client.from("campaigns").select("id").eq("slug", CAMPAIGN_SLUG).single(),
    "Campagne",
  ) as unknown as { id: string };
  const campaignId = campaign.id as string;

  const [settings, factions, journal, contacts, services, relationships, dossiers, milestones] = await Promise.all([
    client.from("campaign_settings").select("*").eq("campaign_id", campaignId).single(),
    client.from("gm_faction_overview").select("*").eq("campaign_id", campaignId).order("sort_order"),
    client.from("gm_journal_entries").select("*").eq("campaign_id", campaignId).order("occurred_on", { ascending: false }).order("created_at", { ascending: false }),
    client.from("gm_contacts").select("*").eq("campaign_id", campaignId).order("is_primary", { ascending: false }).order("name"),
    client.from("gm_services").select("*").eq("campaign_id", campaignId).order("faction_sort_order").order("scale_sort"),
    client.from("gm_relationships").select("*").eq("campaign_id", campaignId).order("source_sort_order").order("target_sort_order"),
    client.from("gm_bilateral_dossiers").select("*").eq("campaign_id", campaignId).order("pair_name"),
    client.from("gm_milestones").select("*").eq("campaign_id", campaignId).order("volume").order("sort_order"),
  ]);

  return {
    settings: unwrap(settings, "Configuration") as CampaignSettings,
    factions: unwrap(factions, "Factions") as CampaignData["factions"],
    journal: normalizeVisibility(unwrap(journal, "Journal") as CampaignData["journal"]),
    contacts: normalizeVisibility(unwrap(contacts, "Contacts") as CampaignData["contacts"]),
    services: unwrap(services, "Services") as CampaignData["services"],
    relationships: normalizeVisibility(unwrap(relationships, "Relations") as CampaignData["relationships"]),
    dossiers: unwrap(dossiers, "Dossiers") as CampaignData["dossiers"],
    milestones: unwrap(milestones, "Progression") as CampaignData["milestones"],
  };
}

export async function loadPlayerData(demo = false): Promise<CampaignData> {
  if (demo) {
    const data = structuredClone(mockCampaignData);
    data.relationships = data.relationships.filter((item) => item.visibility === "players");
    data.contacts = data.contacts.filter((item) => item.visibility === "players");
    data.journal = data.journal.filter((item) => item.visibility === "players");
    data.services = data.services.filter((service) => {
      const faction = data.factions.find((item) => item.faction_id === service.faction_id);
      return faction && faction.is_player_visible && faction.rp >= service.required_rp && faction.tension < data.settings.tension_max;
    });
    data.dossiers = [];
    data.milestones = [];
    return data;
  }
  const client = requireClient();
  const campaign = unwrap(
    await client.from("player_campaign").select("*").eq("slug", CAMPAIGN_SLUG).single(),
    "Vue joueurs",
  ) as unknown as {
    campaign_id: string;
    current_volume: number;
    jf_cap: number;
    minor_cost: number;
    moderate_cost: number;
    major_cost: number;
    liked_threshold: number;
    admired_threshold: number;
    revered_threshold: number;
    carters_major_threshold: number;
    tension_max: number;
    show_numeric_tension: boolean;
  };
  const campaignId = campaign.campaign_id as string;
  const [factions, journal, contacts, services, relationships] = await Promise.all([
    client.from("player_faction_overview").select("*").eq("campaign_id", campaignId).order("sort_order"),
    client.from("player_journal").select("*").eq("campaign_id", campaignId).order("occurred_on", { ascending: false }),
    client.from("player_contacts").select("*").eq("campaign_id", campaignId).order("is_primary", { ascending: false }).order("name"),
    client.from("player_services").select("*").eq("campaign_id", campaignId).order("faction_sort_order").order("scale_sort"),
    client.from("player_relationships").select("*").eq("campaign_id", campaignId).order("source_sort_order").order("target_sort_order"),
  ]);

  return {
    settings: {
      campaign_id: campaignId,
      current_volume: campaign.current_volume,
      jf_cap: campaign.jf_cap,
      minor_cost: campaign.minor_cost,
      moderate_cost: campaign.moderate_cost,
      major_cost: campaign.major_cost,
      liked_threshold: campaign.liked_threshold,
      admired_threshold: campaign.admired_threshold,
      revered_threshold: campaign.revered_threshold,
      carters_major_threshold: campaign.carters_major_threshold,
      tension_max: campaign.tension_max,
      tension_surcharge_level: 2,
      tension_surcharge: 1,
      admired_discount: 2,
      show_numeric_tension: campaign.show_numeric_tension,
    },
    factions: unwrap(factions, "Factions publiques") as CampaignData["factions"],
    journal: unwrap(journal, "Journal public") as CampaignData["journal"],
    contacts: unwrap(contacts, "Contacts publics") as CampaignData["contacts"],
    services: unwrap(services, "Services publics") as CampaignData["services"],
    relationships: unwrap(relationships, "Relations publiques") as CampaignData["relationships"],
    dossiers: [],
    milestones: [],
  };
}

export async function addJournalEntry(entry: Omit<JournalEntry, "id" | "faction_name" | "created_at">): Promise<void> {
  const client = requireClient();
  const { error } = await client.from("journal_entries").insert(entry);
  if (error) throw new Error(`Journal : ${error.message}`);
}

export async function deleteJournalEntry(id: string): Promise<void> {
  const client = requireClient();
  const { error } = await client.from("journal_entries").delete().eq("id", id);
  if (error) throw new Error(`Suppression : ${error.message}`);
}

export async function saveContact(contact: Contact): Promise<void> {
  const client = requireClient();
  const payload = {
    campaign_id: contact.campaign_id,
    faction_id: contact.faction_id,
    name: contact.name,
    role: contact.role,
    state: contact.state,
    attitude: contact.attitude,
    promise_debt: contact.promise_debt,
    due_text: contact.due_text,
    gm_notes: contact.gm_notes,
    next_consequence: contact.next_consequence,
    visibility: contact.visibility,
    is_primary: contact.is_primary,
  };
  const { error } = await client.from("contacts").upsert({ id: contact.id, ...payload });
  if (error) throw new Error(`Contact : ${error.message}`);
}

export async function updateRelationship(
  id: string,
  patch: {
    headline_override: string | null;
    detail_override: string | null;
    color_override: Relationship["color_override"];
    visibility: Visibility;
  },
): Promise<void> {
  const client = requireClient();
  const { error } = await client.from("faction_relationships").update(patch).eq("id", id);
  if (error) throw new Error(`Relation : ${error.message}`);
}

export async function updateJournalVisibility(id: string, visibility: Visibility): Promise<void> {
  const client = requireClient();
  const { error } = await client.from("journal_entries").update({ visibility }).eq("id", id);
  if (error) throw new Error(`Journal : ${error.message}`);
}

export async function updateFactionDetails(
  campaignId: string,
  factionId: string,
  patch: { public_summary?: string | null; gm_notes?: string | null; next_consequence?: string | null; is_player_visible?: boolean },
): Promise<void> {
  const client = requireClient();
  const { error } = await client.from("campaign_factions").update(patch).eq("campaign_id", campaignId).eq("faction_id", factionId);
  if (error) throw new Error(`Faction : ${error.message}`);
}

export async function updateSettings(settings: CampaignSettings): Promise<void> {
  const client = requireClient();
  const { error } = await client.from("campaign_settings").update(settings).eq("campaign_id", settings.campaign_id);
  if (error) throw new Error(`Configuration : ${error.message}`);
}

export async function resolveMilestone(
  id: string,
  outcome: Exclude<MilestoneStatus, "excluded">,
  note: string | null,
  effects: MilestoneEffect[] | null,
): Promise<void> {
  const client = requireClient();
  const { error } = await client.rpc("resolve_reputation_milestone", {
    p_milestone_id: id,
    p_outcome: outcome,
    p_note: note,
    p_effects: effects,
  });
  if (error) throw new Error(`Jalon : ${error.message}`);
}

export async function spendFavor(params: {
  campaignId: string;
  factionId: string;
  title: string;
  cost: number;
  volume: number;
  visibility: Visibility;
}): Promise<void> {
  await addJournalEntry({
    campaign_id: params.campaignId,
    faction_id: params.factionId,
    occurred_on: new Date().toISOString().slice(0, 10),
    volume: params.volume,
    title: params.title,
    details: "Service de faction accordé.",
    rp_delta: 0,
    jf_delta: -Math.abs(params.cost),
    tension_delta: 0,
    visibility: params.visibility,
    source_reference: null,
  });
}

export async function signInWithPassword(email: string, password: string): Promise<void> {
  const client = requireClient();
  const { error } = await client.auth.signInWithPassword({ email, password });
  if (error) throw new Error(error.message);
}

export async function signOut(): Promise<void> {
  const client = requireClient();
  const { error } = await client.auth.signOut();
  if (error) throw new Error(error.message);
}

export async function currentSession() {
  if (!supabase) return null;
  const { data } = await supabase.auth.getSession();
  return data.session;
}

export function subscribeToCampaign(campaignId: string, onChange: () => void) {
  if (!supabase) return () => undefined;
  const channel = supabase
    .channel(`campaign-${campaignId}`)
    .on("postgres_changes", { event: "*", schema: "public", table: "journal_entries", filter: `campaign_id=eq.${campaignId}` }, onChange)
    .on("postgres_changes", { event: "*", schema: "public", table: "contacts", filter: `campaign_id=eq.${campaignId}` }, onChange)
    .on("postgres_changes", { event: "*", schema: "public", table: "faction_relationships", filter: `campaign_id=eq.${campaignId}` }, onChange)
    .on("postgres_changes", { event: "*", schema: "public", table: "reputation_milestones", filter: `campaign_id=eq.${campaignId}` }, onChange)
    .subscribe();
  return () => { void supabase?.removeChannel(channel); };
}

export function relationVisibilityLabel(relationship: Relationship): string {
  if (relationship.visibility === "players") return "Visible des joueurs";
  return "MJ uniquement";
}
