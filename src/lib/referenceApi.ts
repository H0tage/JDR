import { archiveCharacterSeeds, archivePlaceSeeds, lootSeeds } from "../data/referenceSeed";
import { supabase } from "./supabase";
import type { ArchiveCharacter, ArchivePlace, ArchivesData, LootEntry } from "./types";

function requireClient() {
  if (!supabase) throw new Error("Configuration Supabase absente.");
  return supabase;
}

function check(error: { message: string } | null, label: string) {
  if (error) throw new Error(`${label} : ${error.message}`);
}

export async function loadArchives(campaignId: string, demo = false): Promise<ArchivesData> {
  if (demo) {
    return {
      characters: structuredClone(archiveCharacterSeeds),
      places: structuredClone(archivePlaceSeeds),
      show_translations: true,
    };
  }
  const client = requireClient();
  const [characters, places, settings] = await Promise.all([
    client.from("archive_characters").select("*").eq("campaign_id", campaignId).order("first_volume").order("sort_order"),
    client.from("archive_places").select("*").eq("campaign_id", campaignId).order("first_volume").order("sort_order"),
    client.from("campaign_settings").select("show_archive_translations").eq("campaign_id", campaignId).single(),
  ]);
  check(characters.error, "Personnages");
  check(places.error, "Lieux");
  check(settings.error, "Préférences des archives");
  return {
    characters: (characters.data ?? []) as ArchiveCharacter[],
    places: (places.data ?? []) as ArchivePlace[],
    show_translations: Boolean(settings.data?.show_archive_translations),
  };
}

export async function loadLoot(campaignId: string, demo = false): Promise<LootEntry[]> {
  if (demo) return structuredClone(lootSeeds);
  const result = await requireClient()
    .from("campaign_loot")
    .select("*")
    .eq("campaign_id", campaignId)
    .order("volume")
    .order("sort_order");
  check(result.error, "Butins");
  return (result.data ?? []) as LootEntry[];
}

export async function saveArchiveCharacter(entry: ArchiveCharacter): Promise<void> {
  const result = await requireClient().from("archive_characters").upsert(entry);
  check(result.error, "Personnage");
}

export async function deleteArchiveCharacter(id: string): Promise<void> {
  const result = await requireClient().from("archive_characters").delete().eq("id", id);
  check(result.error, "Suppression du personnage");
}

export async function saveArchivePlace(entry: ArchivePlace): Promise<void> {
  const result = await requireClient().from("archive_places").upsert(entry);
  check(result.error, "Lieu");
}

export async function deleteArchivePlace(id: string): Promise<void> {
  const result = await requireClient().from("archive_places").delete().eq("id", id);
  check(result.error, "Suppression du lieu");
}

export async function saveLootEntry(entry: LootEntry): Promise<void> {
  const result = await requireClient().from("campaign_loot").upsert(entry);
  check(result.error, "Butin");
}

export async function deleteLootEntry(id: string): Promise<void> {
  const result = await requireClient().from("campaign_loot").delete().eq("id", id);
  check(result.error, "Suppression du butin");
}

export async function saveTranslationPreference(campaignId: string, show: boolean): Promise<void> {
  const result = await requireClient()
    .from("campaign_settings")
    .update({ show_archive_translations: show })
    .eq("campaign_id", campaignId);
  check(result.error, "Préférence de traduction");
}

export async function resetReferenceData(campaignId: string, scope: "archives" | "loot"): Promise<void> {
  const result = await requireClient().rpc("reset_campaign_reference_data", {
    p_campaign_id: campaignId,
    p_scope: scope,
  });
  check(result.error, "Restauration");
}

