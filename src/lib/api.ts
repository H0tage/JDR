import { mockCampaignData } from "../data/mockData";
import { anonymizeDemoCampaignData } from "../data/demoAnonymization";
import { supabase } from "./supabase";
import type {
  CampaignData,
  CampaignSettings,
  BestiaryEntry,
  Contact,
  JournalEntry,
  MilestoneEffect,
  MilestoneStatus,
  QuestEntry,
  QuestJournalDocument,
  QuestJournalPage,
  QuestJournalRevision,
  Relationship,
  SessionPrep,
  Visibility,
} from "./types";

const BESTIARY_BUCKET = "bestiary-images";
const JOURNAL_IMAGE_BUCKET = "quest-journal-images";
const CONTACT_PORTRAIT_BUCKET = "contact-portraits";

/** Une version plus récente existe : le navigateur doit demander quoi conserver. */
export class QuestJournalVersionConflictError extends Error {
  constructor() {
    super("Le Journal a été modifié dans une autre fenêtre. Votre texte local est conservé et attend votre choix.");
    this.name = "QuestJournalVersionConflictError";
  }
}

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

export async function loadGmData(campaignId: string, demo = false): Promise<CampaignData> {
  if (demo) return anonymizeDemoCampaignData(mockCampaignData);
  const client = requireClient();

  const [settings, sessionPrep, bestiary, questEntries, questJournalPage, questJournalRevisions, factions, journal, contacts, services, relationships, dossiers, milestones] = await Promise.all([
    client.from("campaign_settings").select("*").eq("campaign_id", campaignId).single(),
    client.from("campaign_session_preps").select("*").eq("campaign_id", campaignId).maybeSingle(),
    client.rpc("list_campaign_bestiary", { p_campaign_id: campaignId }),
    client.from("quest_entries").select("*").eq("campaign_id", campaignId).order("sort_order").order("created_at"),
    client.from("quest_journal_pages").select("*").eq("campaign_id", campaignId).maybeSingle(),
    client.from("quest_journal_revisions").select("*").eq("campaign_id", campaignId).order("created_at", { ascending: false }).limit(20),
    client.from("gm_faction_overview").select("*").eq("campaign_id", campaignId).order("sort_order"),
    client.from("gm_journal_entries").select("*").eq("campaign_id", campaignId).order("occurred_on", { ascending: false }).order("created_at", { ascending: false }),
    client.from("gm_contacts").select("*").eq("campaign_id", campaignId).order("is_primary", { ascending: false }).order("name"),
    client.from("gm_services").select("*").eq("campaign_id", campaignId).order("faction_sort_order").order("scale_sort"),
    client.from("gm_relationships").select("*").eq("campaign_id", campaignId).order("source_sort_order").order("target_sort_order"),
    client.from("gm_bilateral_dossiers").select("*").eq("campaign_id", campaignId).order("pair_name"),
    client.from("gm_milestones").select("*").eq("campaign_id", campaignId).order("volume").order("sort_order"),
  ]);

  if (sessionPrep.error) throw new Error(`Préparation de séance : ${sessionPrep.error.message}`);

  return {
    settings: unwrap(settings, "Configuration") as CampaignSettings,
    sessionPrep: (sessionPrep.data ?? { campaign_id: campaignId, objective: null, scenes: null, reminders: null, notes: null }) as SessionPrep,
    bestiary: unwrap(bestiary, "Bestiaire") as BestiaryEntry[],
    questEntries: unwrap(questEntries, "Journal de quête") as QuestEntry[],
    questJournalPage: (questJournalPage.data ?? { campaign_id: campaignId, content: "" }) as QuestJournalPage,
    questJournalRevisions: unwrap(questJournalRevisions, "Historique du journal") as QuestJournalRevision[],
    factions: unwrap(factions, "Factions") as CampaignData["factions"],
    journal: normalizeVisibility(unwrap(journal, "Journal") as CampaignData["journal"]),
    contacts: normalizeVisibility(unwrap(contacts, "Contacts") as CampaignData["contacts"]),
    services: unwrap(services, "Services") as CampaignData["services"],
    relationships: normalizeVisibility(unwrap(relationships, "Relations") as CampaignData["relationships"]),
    dossiers: unwrap(dossiers, "Dossiers") as CampaignData["dossiers"],
    milestones: unwrap(milestones, "Progression") as CampaignData["milestones"],
  };
}

export async function loadPlayerData(campaignId: string, demo = false, viewerRole: "gm" | "player" = "player"): Promise<CampaignData> {
  if (demo) {
    const data = anonymizeDemoCampaignData(mockCampaignData);
    if (viewerRole !== "gm") data.bestiary = data.bestiary.filter((entry) => entry.is_visible);
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
    await client.from("player_campaign").select("*").eq("campaign_id", campaignId).single(),
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
    player_display_mode: "numeric" | "intuitive";
    show_all_player_balances?: boolean;
  };
  const selectedCampaignId = campaign.campaign_id as string;
  const [bestiary, questEntries, questJournalPage, questJournalRevisions, factions, journal, contacts, services, relationships] = await Promise.all([
    client.rpc("list_campaign_bestiary", { p_campaign_id: selectedCampaignId }),
    client.from("quest_entries").select("*").eq("campaign_id", selectedCampaignId).order("sort_order").order("created_at"),
    client.from("quest_journal_pages").select("*").eq("campaign_id", selectedCampaignId).maybeSingle(),
    client.from("quest_journal_revisions").select("*").eq("campaign_id", selectedCampaignId).order("created_at", { ascending: false }).limit(20),
    client.from("player_faction_overview").select("*").eq("campaign_id", selectedCampaignId).order("sort_order"),
    client.from("player_journal").select("*").eq("campaign_id", selectedCampaignId).order("occurred_on", { ascending: false }),
    client.from("player_contacts").select("*").eq("campaign_id", selectedCampaignId).order("is_primary", { ascending: false }).order("name"),
    client.from("player_services").select("*").eq("campaign_id", selectedCampaignId).order("faction_sort_order").order("scale_sort"),
    client.from("player_relationships").select("*").eq("campaign_id", selectedCampaignId).order("source_sort_order").order("target_sort_order"),
  ]);

  return {
    settings: {
      campaign_id: selectedCampaignId,
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
      player_display_mode: campaign.player_display_mode,
      show_all_player_balances: campaign.show_all_player_balances ?? false,
    },
    sessionPrep: { campaign_id: selectedCampaignId, objective: null, scenes: null, reminders: null, notes: null },
    bestiary: unwrap(bestiary, "Bestiaire") as BestiaryEntry[],
    questEntries: unwrap(questEntries, "Journal de quête") as QuestEntry[],
    questJournalPage: (questJournalPage.data ?? { campaign_id: campaignId, content: "" }) as QuestJournalPage,
    questJournalRevisions: unwrap(questJournalRevisions, "Historique du journal") as QuestJournalRevision[],
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
    first_name: contact.first_name?.trim() || null,
    last_name: contact.last_name?.trim() || null,
    role: contact.role,
    public_description: contact.public_description?.trim() || null,
    image_path: contact.image_path,
    avatar_x: contact.avatar_x,
    avatar_y: contact.avatar_y,
    avatar_zoom: contact.avatar_zoom,
    state: contact.state,
    attitude: contact.attitude,
    promise_debt: contact.promise_debt,
    due_text: contact.due_text,
    gm_notes: contact.gm_notes,
    visibility: contact.visibility,
    is_primary: contact.is_primary,
  };
  const { error } = await client.from("contacts").upsert({ id: contact.id, ...payload });
  if (error) throw new Error(`Contact : ${error.message}`);
}

export async function savePlayerContactNotes(input: {
  contactId: string;
  characterNotes: string;
  debtNotes: string;
  notes: string;
}): Promise<void> {
  const client = requireClient();
  const { error } = await client.rpc("save_player_contact_notes", {
    target_contact_id: input.contactId,
    next_character_notes: input.characterNotes,
    next_debt_notes: input.debtNotes,
    next_notes: input.notes,
  });
  if (error) throw new Error(`Notes du contact : ${error.message}`);
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
  patch: { public_summary?: string | null; gm_notes?: string | null; is_player_visible?: boolean },
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

export async function saveSessionPrep(prep: SessionPrep): Promise<void> {
  const client = requireClient();
  const payload = {
    campaign_id: prep.campaign_id,
    objective: prep.objective,
    scenes: prep.scenes,
    reminders: prep.reminders,
    notes: prep.notes,
  };
  const { error } = await client.from("campaign_session_preps").upsert(payload);
  if (error) throw new Error(`Préparation de séance : ${error.message}`);
}

export async function saveBestiaryEntry(entry: BestiaryEntry): Promise<void> {
  const client = requireClient();
  const { error } = await client.rpc("save_bestiary_entry", {
    p_id: entry.id,
    p_campaign_id: entry.campaign_id,
    p_name: entry.name.trim(),
    p_resistances: entry.resistances?.trim() || null,
    p_weaknesses: entry.weaknesses?.trim() || null,
    p_notes: entry.notes?.trim() || null,
    p_image_path: entry.image_path,
  });
  if (error) throw new Error(`Bestiaire : ${error.message}`);
}

export async function deleteBestiaryEntry(entry: BestiaryEntry): Promise<void> {
  const client = requireClient();
  const { error } = await client.rpc("delete_bestiary_entry", { p_entry_id: entry.id });
  if (error) throw new Error(`Bestiaire : ${error.message}`);
  if (entry.image_path && !entry.image_path.startsWith("blob:")) {
    const { error: imageError } = await client.storage.from(BESTIARY_BUCKET).remove([entry.image_path]);
    if (imageError) throw new Error(`Image du bestiaire : ${imageError.message}`);
  }
}

export async function setBestiaryEntryVisibility(entryId: string, visible: boolean): Promise<void> {
  const client = requireClient();
  const { error } = await client.rpc("set_bestiary_entry_visibility", { p_entry_id: entryId, p_visible: visible });
  if (error) throw new Error(`Bestiaire : ${error.message}`);
}

export async function uploadBestiaryImage(campaignId: string, file: File): Promise<string> {
  if (!file.type.startsWith("image/")) throw new Error("Choisissez un fichier image.");
  if (file.size > 5 * 1024 * 1024) throw new Error("L’image ne doit pas dépasser 5 Mo.");
  const client = requireClient();
  const extension = file.name.split(".").pop()?.toLocaleLowerCase().replace(/[^a-z0-9]/g, "") || "image";
  const path = `${campaignId}/${crypto.randomUUID()}.${extension}`;
  const { error } = await client.storage.from(BESTIARY_BUCKET).upload(path, file, { contentType: file.type, upsert: false });
  if (error) throw new Error(`Image du bestiaire : ${error.message}`);
  return path;
}

export async function deleteBestiaryImage(path: string): Promise<void> {
  if (!path || path.startsWith("blob:")) return;
  const client = requireClient();
  const { error } = await client.storage.from(BESTIARY_BUCKET).remove([path]);
  if (error) throw new Error(`Image du bestiaire : ${error.message}`);
}

export async function uploadContactPortrait(campaignId: string, file: File): Promise<string> {
  if (!file.type.startsWith("image/")) throw new Error("Choisissez un fichier image.");
  if (file.size > 5 * 1024 * 1024) throw new Error("L’image ne doit pas dépasser 5 Mo.");
  const client = requireClient();
  const extension = file.name.split(".").pop()?.toLocaleLowerCase().replace(/[^a-z0-9]/g, "") || "image";
  const path = `${campaignId}/${crypto.randomUUID()}.${extension}`;
  const { error } = await client.storage.from(CONTACT_PORTRAIT_BUCKET).upload(path, file, { contentType: file.type, upsert: false });
  if (error) throw new Error(`Portrait du contact : ${error.message}`);
  return path;
}

export async function deleteContactPortrait(path: string): Promise<void> {
  if (!path || path.startsWith("blob:")) return;
  const client = requireClient();
  const { error } = await client.storage.from(CONTACT_PORTRAIT_BUCKET).remove([path]);
  if (error) throw new Error(`Portrait du contact : ${error.message}`);
}

export async function uploadQuestJournalImage(campaignId: string, file: File): Promise<string> {
  if (!file.type.startsWith("image/")) throw new Error("Choisissez un fichier image.");
  if (file.size > 8 * 1024 * 1024) throw new Error("L’image ne doit pas dépasser 8 Mo.");
  const client = requireClient();
  const extension = file.name.split(".").pop()?.toLocaleLowerCase().replace(/[^a-z0-9]/g, "") || "image";
  const path = `${campaignId}/${crypto.randomUUID()}.${extension}`;
  const { error } = await client.storage.from(JOURNAL_IMAGE_BUCKET).upload(path, file, { contentType: file.type, upsert: false });
  if (error) throw new Error(`Image du journal : ${error.message}`);
  return client.storage.from(JOURNAL_IMAGE_BUCKET).getPublicUrl(path).data.publicUrl;
}

export async function saveQuestEntry(entry: QuestEntry): Promise<void> {
  const client = requireClient();
  const { error } = await client.from("quest_entries").upsert({
    id: entry.id,
    campaign_id: entry.campaign_id,
    title: entry.title.trim(),
    notes: entry.notes?.trim() || null,
    status: entry.status,
    category: entry.category,
    sort_order: entry.sort_order,
  });
  if (error) throw new Error(`Journal de quête : ${error.message}`);
}

export async function deleteQuestEntry(id: string): Promise<void> {
  const client = requireClient();
  const { error } = await client.from("quest_entries").delete().eq("id", id);
  if (error) throw new Error(`Journal de quête : ${error.message}`);
}

export async function saveQuestJournalDocument(document: QuestJournalDocument, removedBlockIds: string[] = []): Promise<void> {
  const client = requireClient();
  const { error: documentError } = await client.from("quest_journal_documents").upsert({
    id: document.id,
    campaign_id: document.campaign_id,
    title: document.title.trim(),
    occurred_on: document.occurred_on,
    sort_order: document.sort_order,
    is_collapsed: document.is_collapsed,
  });
  if (documentError) throw new Error(`Journal de quête : ${documentError.message}`);

  if (document.blocks.length > 0) {
    const { error: blocksError } = await client.from("quest_journal_blocks").upsert(document.blocks.map((block, index) => ({
      id: block.id,
      campaign_id: document.campaign_id,
      document_id: document.id,
      kind: block.kind,
      content: block.content,
      label: block.label?.trim() || null,
      sort_order: index,
      is_locked: block.is_locked,
      is_collapsed: block.is_collapsed,
    })));
    if (blocksError) throw new Error(`Blocs du journal de quête : ${blocksError.message}`);
  }
  if (removedBlockIds.length > 0) {
    const { error: deletionError } = await client.from("quest_journal_blocks").delete().in("id", removedBlockIds);
    if (deletionError) throw new Error(`Blocs du journal de quête : ${deletionError.message}`);
  }
}

export async function deleteQuestJournalDocument(id: string): Promise<void> {
  const client = requireClient();
  const { error } = await client.from("quest_journal_documents").delete().eq("id", id);
  if (error) throw new Error(`Journal de quête : ${error.message}`);
}

export async function saveQuestJournalPage(page: QuestJournalPage): Promise<number> {
  const client = requireClient();
  const { data, error } = await client.rpc("save_quest_journal_page", {
    target_campaign_id: page.campaign_id,
    expected_revision: page.revision ?? 0,
    next_content: page.content,
  });
  if (error?.code === "40001") throw new QuestJournalVersionConflictError();
  if (error) throw new Error(`Journal de quête : ${error.message}`);
  const revision = Array.isArray(data) ? data[0] : data;
  if (typeof revision !== "number") throw new Error("Journal de quête : réponse de sauvegarde invalide.");
  return revision;
}

export async function loadQuestJournalPage(campaignId: string): Promise<QuestJournalPage> {
  const client = requireClient();
  const { data, error } = await client.from("quest_journal_pages").select("*").eq("campaign_id", campaignId).maybeSingle();
  if (error) throw new Error(`Journal de quête : ${error.message}`);
  return (data ?? { campaign_id: campaignId, content: "", revision: 0 }) as QuestJournalPage;
}

export async function restoreQuestJournalRevision(campaignId: string, revisionId: string, expectedRevision: number): Promise<number> {
  const client = requireClient();
  const revision = unwrap(
    await client.from("quest_journal_revisions").select("content").eq("campaign_id", campaignId).eq("id", revisionId).single(),
    "Historique du journal",
  ) as unknown as Pick<QuestJournalRevision, "content">;
  return saveQuestJournalPage({ campaign_id: campaignId, content: revision.content, revision: expectedRevision });
}

export function bestiaryImageUrl(path: string | null): string | null {
  if (!path) return null;
  if (path.startsWith("blob:")) return path;
  if (!supabase) return null;
  return supabase.storage.from(BESTIARY_BUCKET).getPublicUrl(path).data.publicUrl;
}

export function contactPortraitUrl(path: string | null): string | null {
  if (!path) return null;
  if (path.startsWith("blob:")) return path;
  if (!supabase) return null;
  return supabase.storage.from(CONTACT_PORTRAIT_BUCKET).getPublicUrl(path).data.publicUrl;
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
    .on("postgres_changes", { event: "*", schema: "public", table: "campaign_settings", filter: `campaign_id=eq.${campaignId}` }, onChange)
    .on("postgres_changes", { event: "*", schema: "public", table: "bestiary_entries", filter: `campaign_id=eq.${campaignId}` }, onChange)
    .on("postgres_changes", { event: "*", schema: "public", table: "quest_entries", filter: `campaign_id=eq.${campaignId}` }, onChange)
    .on("postgres_changes", { event: "*", schema: "public", table: "quest_journal_pages", filter: `campaign_id=eq.${campaignId}` }, onChange)
    .subscribe();
  return () => { void supabase?.removeChannel(channel); };
}

export function relationVisibilityLabel(relationship: Relationship): string {
  if (relationship.visibility === "players") return "Visible des joueurs";
  return "MJ uniquement";
}
