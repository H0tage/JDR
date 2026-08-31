import { supabase } from "./supabase";

export type CampaignRole = "gm" | "player";

export interface CampaignMembership {
  campaign_id: string;
  slug: string;
  name: string;
  description: string | null;
  role: CampaignRole;
  joined_at: string;
  is_owner: boolean;
  created_at: string;
}

export interface CreatedCampaign {
  campaign_id: string;
  slug: string;
  name: string;
  description: string | null;
}

export interface CampaignInvite {
  id: string;
  token: string;
  expires_at: string | null;
  revoked_at: string | null;
  created_at: string;
}

export interface CampaignMember {
  user_id: string;
  display_name: string;
  role: CampaignRole;
  joined_at: string;
}

export interface InvitationDetails {
  campaign_id: string;
  campaign_name: string;
  status: "valid" | "revoked" | "expired";
}

function client() {
  if (!supabase) throw new Error("Configuration Supabase absente.");
  return supabase;
}

function throwError(error: { message: string } | null, label: string) {
  if (error) throw new Error(`${label} : ${error.message}`);
}

export async function listMyCampaigns(): Promise<CampaignMembership[]> {
  const result = await client().rpc("list_my_campaigns");
  throwError(result.error, "Campagnes");
  return (result.data ?? []) as CampaignMembership[];
}

export async function signUp(email: string, password: string): Promise<void> {
  const result = await client().auth.signUp({
    email,
    password,
    options: { emailRedirectTo: `${window.location.origin}/auth/callback` },
  });
  throwError(result.error, "Création du compte");
}

export async function sendPasswordRecovery(email: string): Promise<void> {
  const result = await client().auth.resetPasswordForEmail(email, {
    redirectTo: `${window.location.origin}/auth/callback`,
  });
  throwError(result.error, "Récupération du mot de passe");
}

export async function updatePassword(password: string): Promise<void> {
  const result = await client().auth.updateUser({ password });
  throwError(result.error, "Mot de passe");
}

export async function invitationDetails(token: string): Promise<InvitationDetails | null> {
  const result = await client().rpc("get_campaign_invitation", { p_token: token });
  throwError(result.error, "Invitation");
  return (result.data?.[0] ?? null) as InvitationDetails | null;
}

export async function acceptInvitation(token: string): Promise<{ campaign_id: string; campaign_name: string; role: CampaignRole; already_member: boolean }> {
  const result = await client().rpc("accept_campaign_invitation", { p_token: token });
  throwError(result.error, "Invitation");
  if (!result.data?.[0]) throw new Error("Invitation : aucune campagne reçue.");
  return result.data[0] as { campaign_id: string; campaign_name: string; role: CampaignRole; already_member: boolean };
}

export async function createCampaign(name: string, description: string): Promise<CreatedCampaign> {
  const result = await client().rpc("create_campaign", {
    p_name: name,
    p_description: description || null,
  });
  throwError(result.error, "Création de la campagne");
  if (!result.data?.[0]) throw new Error("Création de la campagne : aucune donnée reçue.");
  return result.data[0] as CreatedCampaign;
}

export async function updateOwnedCampaign(campaignId: string, name: string, description: string): Promise<Pick<CampaignMembership, "campaign_id" | "slug" | "name" | "description" | "created_at">> {
  const result = await client().rpc("update_owned_campaign", {
    p_campaign_id: campaignId,
    p_name: name,
    p_description: description || null,
  });
  throwError(result.error, "Modification de la campagne");
  if (!result.data?.[0]) throw new Error("Modification de la campagne : aucune donnée reçue.");
  return result.data[0] as Pick<CampaignMembership, "campaign_id" | "slug" | "name" | "description" | "created_at">;
}

const CAMPAIGN_STORAGE_BUCKETS = ["bestiary-images", "contact-portraits", "quest-journal-images", "player-character-images"] as const;

async function clearCampaignStorage(campaignId: string): Promise<void> {
  for (const bucket of CAMPAIGN_STORAGE_BUCKETS) {
    while (true) {
      const listed = await client().storage.from(bucket).list(campaignId, { limit: 1000, offset: 0 });
      throwError(listed.error, `Suppression des fichiers (${bucket})`);
      const paths = (listed.data ?? []).filter((item) => item.id).map((item) => `${campaignId}/${item.name}`);
      if (paths.length === 0) break;
      const removed = await client().storage.from(bucket).remove(paths);
      throwError(removed.error, `Suppression des fichiers (${bucket})`);
      if (paths.length < 1000) break;
    }
  }
}

export async function deleteOwnedCampaign(campaignId: string): Promise<string> {
  // Vérification avant toute suppression Storage : si l'appel provient d'une
  // interface périmée ou manipulée, aucun fichier ne doit disparaître avant
  // que la propriété de la campagne ait été confirmée.
  const ownedCampaign = (await listMyCampaigns()).find((campaign) => campaign.campaign_id === campaignId && campaign.is_owner);
  if (!ownedCampaign) throw new Error("Suppression de la campagne : seul le propriétaire peut effectuer cette action.");
  // Les politiques Storage exigent encore l’appartenance à la campagne : les
  // fichiers doivent donc être retirés avant la suppression transactionnelle.
  await clearCampaignStorage(campaignId);
  const result = await client().rpc("delete_owned_campaign", { p_campaign_id: campaignId });
  throwError(result.error, "Suppression de la campagne");
  if (typeof result.data !== "string") throw new Error("Suppression de la campagne : réponse invalide.");
  return result.data;
}

export async function leaveCampaign(campaignId: string): Promise<void> {
  const result = await client().rpc("leave_campaign", { p_campaign_id: campaignId });
  throwError(result.error, "Départ de la campagne");
}

export async function listCampaignMembers(campaignId: string): Promise<CampaignMember[]> {
  const result = await client().rpc("list_campaign_members", { p_campaign_id: campaignId });
  throwError(result.error, "Membres");
  return (result.data ?? []) as CampaignMember[];
}

export async function listCampaignInvites(campaignId: string): Promise<CampaignInvite[]> {
  const result = await client().rpc("list_campaign_invites", { p_campaign_id: campaignId });
  throwError(result.error, "Invitations");
  return (result.data ?? []) as CampaignInvite[];
}

export async function createCampaignInvite(campaignId: string, expiresAt: string | null): Promise<CampaignInvite> {
  const result = await client().rpc("create_campaign_invite", {
    p_campaign_id: campaignId,
    p_expires_at: expiresAt,
  });
  throwError(result.error, "Invitation");
  if (!result.data?.[0]) throw new Error("Invitation : aucune donnée reçue.");
  return result.data[0] as CampaignInvite;
}

export async function revokeCampaignInvite(inviteId: string): Promise<void> {
  const result = await client().rpc("revoke_campaign_invite", { p_invite_id: inviteId });
  throwError(result.error, "Invitation");
}

export async function removeCampaignPlayer(campaignId: string, userId: string): Promise<void> {
  const result = await client().rpc("remove_campaign_player", { p_campaign_id: campaignId, p_user_id: userId });
  throwError(result.error, "Membre");
}
