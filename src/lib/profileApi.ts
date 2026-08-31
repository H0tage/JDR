import { supabase } from "./supabase";

export interface UserProfile {
  user_id: string;
  display_name: string | null;
}

export interface CampaignPlayer {
  user_id: string;
  display_name: string;
}

function client() {
  if (!supabase) throw new Error("Configuration Supabase absente.");
  return supabase;
}

export async function getMyProfile(): Promise<UserProfile> {
  const result = await client().rpc("get_my_profile");
  if (result.error) throw new Error(`Profil : ${result.error.message}`);
  if (!result.data?.[0]) throw new Error("Profil introuvable.");
  return result.data[0] as UserProfile;
}

export async function updateMyProfile(displayName: string): Promise<UserProfile> {
  const result = await client().rpc("update_my_profile", { p_display_name: displayName });
  if (result.error) throw new Error(`Profil : ${result.error.message}`);
  if (!result.data?.[0]) throw new Error("Profil introuvable.");
  return result.data[0] as UserProfile;
}

export async function listCampaignPlayers(campaignId: string, demo = false): Promise<CampaignPlayer[]> {
  if (demo) return [
    { user_id: "demo-arsene", display_name: "Prénom1 Nom1" },
    { user_id: "demo-morrigan", display_name: "Prénom2 Nom2" },
    { user_id: "demo-silas", display_name: "Prénom3 Nom3" },
  ];
  const result = await client().rpc("list_campaign_players", { p_campaign_id: campaignId });
  if (result.error) throw new Error(`Joueurs : ${result.error.message}`);
  return (result.data ?? []) as CampaignPlayer[];
}
