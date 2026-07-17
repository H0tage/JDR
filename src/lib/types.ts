export type Visibility = "gm_only" | "ready" | "players";
export type FactionStatus = "Indifférents" | "Appréciés" | "Admirés" | "Révérés";
export type ServiceScale = "Mineure" | "Modérée" | "Majeure";
export type Evidence = "E" | "S" | "H" | "E/S" | "S/H";
export type RelationshipColor = "favorable" | "uncertain" | "hostile";
export type MilestoneStatus = "pending" | "succeeded" | "missed" | "excluded";

export interface MilestoneEffectTemplate {
  label: string;
  faction_id?: string;
  faction_ids?: string[];
  scope?: "any" | "any_great" | "all_great" | "transfer_carters";
  exclude_faction_ids?: string[];
  amount?: number;
  amount_min?: number;
  amount_max?: number;
  jf_amount?: number;
  distinct_group?: string;
}

export interface MilestoneEffect {
  label: string;
  faction_id: string;
  amount: number;
  jf_amount?: number;
}

export interface CampaignSettings {
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
  tension_surcharge_level: number;
  tension_surcharge: number;
  admired_discount: number;
  show_numeric_tension: boolean;
}

export interface FactionOverview {
  campaign_id: string;
  faction_id: string;
  slug: string;
  name: string;
  short_name: string;
  accent: string;
  domain: string;
  public_description: string;
  public_summary: string | null;
  gm_notes: string | null;
  next_consequence: string | null;
  is_player_visible: boolean;
  rp: number;
  jf: number;
  tension: number;
  status: FactionStatus;
  tension_label: string;
}

export interface JournalEntry {
  id: string;
  campaign_id: string;
  faction_id: string;
  faction_name?: string;
  occurred_on: string;
  volume: number;
  title: string;
  details: string | null;
  rp_delta: number;
  jf_delta: number;
  tension_delta: number;
  visibility: Visibility;
  source_reference: string | null;
  milestone_id?: string | null;
  created_at?: string;
}

export interface Contact {
  id: string;
  campaign_id: string;
  faction_id: string;
  faction_name?: string;
  name: string;
  role: string;
  state: string;
  attitude: string;
  promise_debt: string | null;
  due_text: string | null;
  gm_notes: string | null;
  next_consequence: string | null;
  visibility: Visibility;
  is_primary: boolean;
}

export interface Service {
  id: string;
  faction_id: string;
  faction_name?: string;
  scale: ServiceScale;
  required_rp: number;
  base_cost: number;
  domain: string;
  examples: string;
  safeguard: string;
  frequency: string;
  player_visible: boolean;
}

export interface Relationship {
  id: string;
  campaign_id: string;
  source_faction_id: string;
  source_name: string;
  target_faction_id: string;
  target_name: string;
  headline: string;
  detail: string;
  default_headline?: string;
  default_detail?: string;
  headline_override?: string | null;
  detail_override?: string | null;
  color: RelationshipColor;
  default_color?: RelationshipColor;
  color_override?: RelationshipColor | null;
  evidence: Evidence;
  tone: "alliance" | "cooperation" | "tension" | "hostility" | "unclear";
  visibility: Visibility;
}

export interface BilateralDossier {
  id: string;
  campaign_id: string;
  faction_a_id: string;
  faction_b_id: string;
  pair_name: string;
  canon_core: string;
  a_to_b: string;
  b_to_a: string;
  common_interest: string;
  fracture: string;
  triggers: string;
  scene_hook: string;
  evidence_note: string;
}

export interface Milestone {
  id: string;
  campaign_id: string;
  volume: number;
  chapter: string | null;
  title: string;
  beneficiary_faction_id: string | null;
  beneficiary_name?: string | null;
  rp_gain: number;
  harmed_faction_id: string | null;
  harmed_name?: string | null;
  rp_loss: number;
  condition: string;
  source_reference: string;
  applied: boolean;
  gm_notes: string | null;
  sort_order: number;
  status: MilestoneStatus;
  resolution_note: string | null;
  choice_group: string | null;
  reward_effects: MilestoneEffectTemplate[];
  resolved_effects: MilestoneEffect[] | null;
  resolved_at: string | null;
  excluded_by_milestone_id: string | null;
  excluded_by_title?: string | null;
  status_before_exclusion: Exclude<MilestoneStatus, "excluded"> | null;
}

export interface CampaignData {
  settings: CampaignSettings;
  factions: FactionOverview[];
  journal: JournalEntry[];
  contacts: Contact[];
  services: Service[];
  relationships: Relationship[];
  dossiers: BilateralDossier[];
  milestones: Milestone[];
}
