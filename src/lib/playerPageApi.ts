import { supabase } from "./supabase";

export interface PlayerPage {
  campaign_id: string;
  user_id: string;
  display_name: string | null;
  character_name: string | null;
  character_summary: string | null;
  pathbuilder_url: string | null;
  notes: string | null;
  objectives: string | null;
  image_path: string | null;
  updated_at: string;
}

export interface CampaignPlayerPage extends PlayerPage {
  display_name: string;
  active: boolean;
}

export type PlayerPageDraft = Pick<PlayerPage, "character_name" | "character_summary" | "pathbuilder_url" | "notes" | "objectives" | "image_path">;

const demoPage: PlayerPage = {
  campaign_id: "00000000-0000-4000-8000-000000000001",
  user_id: "demo-arsene",
  display_name: "Prénom1 Nom1",
  character_name: "Aveline de la Garde-Fleur",
  character_summary: "Chevalière enthousiaste, protectrice infatigable du groupe et spécialiste des entrées remarquées. Son optimisme résiste même aux couloirs les plus sinistres de Geb.",
  pathbuilder_url: "",
  notes: "Ne pas oublier de faire réparer le bouclier après notre prochaine halte.",
  objectives: "Retrouver les archives disparues et tenir la promesse faite à Prénom2 Nom2.",
  image_path: "/demo-player-character.png",
  updated_at: new Date(0).toISOString(),
};

function client() {
  if (!supabase) throw new Error("Configuration Supabase absente.");
  return supabase;
}

export async function loadMyPlayerPage(campaignId: string, demo = false): Promise<PlayerPage> {
  if (demo) return { ...demoPage, campaign_id: campaignId };
  const result = await client().rpc("get_my_player_page", { p_campaign_id: campaignId });
  if (result.error) throw new Error(`Ma page : ${result.error.message}`);
  if (!result.data?.[0]) throw new Error("Page joueur introuvable.");
  return result.data[0] as PlayerPage;
}

export async function saveMyPlayerPage(campaignId: string, draft: PlayerPageDraft, demo = false): Promise<void> {
  if (demo) return;
  const result = await client().rpc("update_my_player_page", {
    p_campaign_id: campaignId,
    p_character_name: draft.character_name,
    p_character_summary: draft.character_summary,
    p_pathbuilder_url: draft.pathbuilder_url,
    p_notes: draft.notes,
    p_objectives: draft.objectives,
    p_image_path: draft.image_path,
  });
  if (result.error) throw new Error(`Ma page : ${result.error.message}`);
}

const PLAYER_CHARACTER_BUCKET = "player-character-images";

export async function uploadPlayerCharacterImage(campaignId: string, userId: string, file: File, demo = false): Promise<string> {
  if (!file.type.match(/^image\/(jpeg|png|webp)$/)) throw new Error("Choisissez une image JPEG, PNG ou WebP.");
  if (file.size > 8 * 1024 * 1024) throw new Error("L’image ne doit pas dépasser 8 Mo.");
  if (demo) return URL.createObjectURL(file);
  const extension = file.name.split(".").pop()?.toLocaleLowerCase().replace(/[^a-z0-9]/g, "") || "image";
  const path = `${campaignId}/${userId}/${crypto.randomUUID()}.${extension}`;
  const result = await client().storage.from(PLAYER_CHARACTER_BUCKET).upload(path, file, { contentType: file.type, upsert: false });
  if (result.error) throw new Error(`Portrait du personnage : ${result.error.message}`);
  return path;
}

export async function deletePlayerCharacterImage(path: string, demo = false): Promise<void> {
  if (demo || !path || path.startsWith("blob:") || path.startsWith("/")) return;
  const result = await client().storage.from(PLAYER_CHARACTER_BUCKET).remove([path]);
  if (result.error) throw new Error(`Portrait du personnage : ${result.error.message}`);
}

export function playerCharacterImageUrl(path: string | null): string | null {
  if (!path || path.startsWith("blob:") || path.startsWith("/")) return path;
  return client().storage.from(PLAYER_CHARACTER_BUCKET).getPublicUrl(path).data.publicUrl;
}

export async function listCampaignPlayerPages(campaignId: string, demo = false): Promise<CampaignPlayerPage[]> {
  if (demo) return [
    { ...demoPage, campaign_id: campaignId, display_name: "Prénom1 Nom1", active: true, character_name: "Personnage 1", character_summary: "Présentation anonymisée.", objectives: "Objectif anonymisé.", notes: "Notes anonymisées." },
    { ...demoPage, campaign_id: campaignId, user_id: "demo-morrigan", display_name: "Prénom2 Nom2", active: true, character_name: "Personnage 2", character_summary: "", objectives: "", notes: "" },
    { ...demoPage, campaign_id: campaignId, user_id: "demo-silas", display_name: "Prénom3 Nom3", active: true, character_name: "Personnage 3", character_summary: "", objectives: "", notes: "" },
    { ...demoPage, campaign_id: campaignId, user_id: "demo-nox", display_name: "Prénom4 Nom4", active: true, character_name: "Personnage 4", character_summary: "", objectives: "", notes: "" },
  ];
  const result = await client().rpc("list_campaign_player_pages", { p_campaign_id: campaignId });
  if (result.error) throw new Error(`Pages joueurs : ${result.error.message}`);
  return (result.data ?? []) as CampaignPlayerPage[];
}
