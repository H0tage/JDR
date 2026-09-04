export type Visibility = "gm_only" | "players";
export type FactionStatus = "Indifférents" | "Appréciés" | "Admirés" | "Révérés";
export type ServiceScale = "Mineure" | "Modérée" | "Majeure";
export type PlayerDisplayMode = "numeric" | "intuitive";
export type Evidence = "E" | "S" | "H" | "E/S" | "S/H";
export type RelationshipColor = "favorable" | "uncertain" | "hostile";
export type MilestoneStatus = "pending" | "succeeded" | "missed" | "excluded";
export type TranslationOrigin = "none" | "attested" | "site" | "custom";

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
  player_display_mode: PlayerDisplayMode;
  /** Le MJ choisit si les joueurs voient les soldes personnels du groupe. */
  show_all_player_balances: boolean;
}

export interface SessionPrep {
  campaign_id: string;
  objective: string | null;
  scenes: string | null;
  reminders: string | null;
  notes: string | null;
  updated_at?: string;
}

export interface BestiaryEntry {
  id: string;
  campaign_id: string;
  name: string;
  resistances: string | null;
  weaknesses: string | null;
  notes: string | null;
  image_path: string | null;
  created_by: string | null;
  is_visible: boolean;
  revealed_at: string | null;
  creator_display_name?: string;
  can_edit?: boolean;
  can_delete?: boolean;
  created_at?: string;
  updated_at?: string;
}

export type QuestStatus = "Actif" | "Résolu" | "Abandonné";
export type QuestCategory = "Pistes" | "Objectifs" | "Questions" | "Informations";

/** Notes libres du groupe. Elles ne modifient jamais les données de faction. */
export interface QuestEntry {
  id: string;
  campaign_id: string;
  title: string;
  notes: string | null;
  status: QuestStatus;
  category: QuestCategory;
  sort_order: number;
  created_at?: string;
  updated_at?: string;
}

export type QuestJournalBlockKind = "paragraph" | "heading" | "callout" | "quote" | "toggle" | "divider";

/**
 * Bloc de rédaction du Journal de quête. Les blocs restent séparés afin que
 * leur ordre, leur repli et leur verrou soient extensibles sans migration de
 * contenu au moindre ajout d’outil d’écriture.
 */
export interface QuestJournalBlock {
  id: string;
  campaign_id: string;
  document_id: string;
  kind: QuestJournalBlockKind;
  content: string;
  label: string | null;
  sort_order: number;
  is_locked: boolean;
  is_collapsed: boolean;
  created_at?: string;
  updated_at?: string;
}

export interface QuestJournalDocument {
  id: string;
  campaign_id: string;
  title: string;
  occurred_on: string;
  sort_order: number;
  is_collapsed: boolean;
  created_at?: string;
  updated_at?: string;
  blocks: QuestJournalBlock[];
}

/** Page de notes continue du groupe, à la manière d’un document. */
export interface QuestJournalPage {
  campaign_id: string;
  content: string;
  /** Révision serveur : empêche une sauvegarde ancienne d’écraser un texte récent. */
  revision?: number;
  updated_at?: string;
}

/** Instantané partagé du Journal, restaurable par les membres de la campagne. */
export interface QuestJournalRevision {
  id: string;
  campaign_id: string;
  content: string;
  created_at: string;
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
  first_name?: string | null;
  last_name?: string | null;
  role: string;
  public_description: string | null;
  image_path: string | null;
  avatar_x: number;
  avatar_y: number;
  avatar_zoom: number;
  state: string;
  attitude: string;
  promise_debt: string | null;
  due_text: string | null;
  gm_notes: string | null;
  player_character_notes: string | null;
  player_debt_notes: string | null;
  player_notes: string | null;
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
  sessionPrep: SessionPrep;
  bestiary: BestiaryEntry[];
  questEntries: QuestEntry[];
  questJournalPage: QuestJournalPage;
  questJournalRevisions: QuestJournalRevision[];
  factions: FactionOverview[];
  journal: JournalEntry[];
  contacts: Contact[];
  services: Service[];
  relationships: Relationship[];
  dossiers: BilateralDossier[];
  milestones: Milestone[];
}

export interface ArchiveCharacter {
  id: string;
  campaign_id: string;
  template_key: string | null;
  sort_order: number;
  first_name: string;
  last_name: string | null;
  translated_name: string | null;
  translation_origin: TranslationOrigin;
  role_text: string | null;
  first_volume: number;
  first_page: number | null;
  is_custom: boolean;
}

export interface ArchivePlace {
  id: string;
  campaign_id: string;
  template_key: string | null;
  sort_order: number;
  original_name: string;
  translated_name: string | null;
  translation_origin: TranslationOrigin;
  place_type: string | null;
  function_text: string | null;
  first_volume: number;
  first_page: number | null;
  is_custom: boolean;
}

export interface LootEntry {
  id: string;
  campaign_id: string;
  reference_id: string | null;
  sort_order: number;
  volume: number;
  chapter: number | null;
  source_page: number | null;
  pdf_page: number | null;
  stat_block_page: number | null;
  area_code: string | null;
  area_title: string | null;
  location_name: string | null;
  source_kind: LootSourceKind;
  source_owner: string | null;
  source_text: string | null;
  item_name: string;
  quantity_initial: string;
  quantity_recoverable: string;
  loot_category: string | null;
  acquisition_condition: string | null;
  consumable_during_encounter: boolean;
  availability_rule: string | null;
  book_unit_value_amount: number | null;
  book_unit_value_currency: LootCurrency | null;
  book_total_value_amount: number | null;
  book_total_value_currency: LootCurrency | null;
  aon_legacy_name: string | null;
  aon_legacy_unit_value_amount: number | null;
  aon_legacy_unit_value_currency: LootCurrency | null;
  aon_legacy_total_value_amount: number | null;
  aon_legacy_total_value_currency: LootCurrency | null;
  aon_legacy_url: string | null;
  pricing_basis: string | null;
  pricing_status: string | null;
  verification_status: string | null;
  discovery_status: LootDiscoveryStatus;
  player_visible: boolean;
  is_custom: boolean;
}

export type LootCurrency = "pp" | "gp" | "sp" | "cp";
export type LootSourceKind = "treasure" | "reward" | "carried" | "infused_carried" | "narrative" | "chapter_checklist_only";
export type LootLaneKind = "treasure" | "carried" | "unlocated";
export type LootDiscoveryStatus = "pending" | "found" | "missed";

export type InventoryItemStatus = "active" | "sold" | "dismantled" | "consumed" | "lost" | "donated" | "merged";
export type InventoryItemSource = "loot" | "gm" | "purchase" | "dismantle";

export interface CampaignInventoryItem {
  id: string;
  campaign_id: string;
  origin_loot_id: string | null;
  parent_item_id: string | null;
  created_by: string | null;
  owner_user_id: string | null;
  owner_display_name: string | null;
  created_by_display_name: string | null;
  name: string;
  quantity: number;
  source_quantity_label: string | null;
  unit_value_cp: number | null;
  purchase_price_cp: number | null;
  aon_legacy_name: string | null;
  aon_legacy_url: string | null;
  source_kind: InventoryItemSource;
  counts_as_gain: boolean;
  player_visible: boolean;
  status: InventoryItemStatus;
  acquired_on: string;
  created_at: string;
  updated_at: string;
  pending_request_count: number;
  requested_by_me: boolean;
}

export interface CampaignMoneyBalance {
  campaign_id: string;
  account_user_id: string | null;
  display_name: string;
  is_common: boolean;
  balance_cp: number;
}

export interface CampaignEconomyTotals {
  campaign_id: string;
  total_entered_cp: number;
  total_exited_cp: number;
  current_wealth_cp: number;
}

export type CampaignMoneyTransactionKind = "common_income" | "personal_income" | "personal_expense" | "transfer" | "sale" | "purchase" | "reversal" | "departure_transfer" | "gm_adjustment";

export interface CampaignMoneyTransaction {
  id: string;
  operation_id: string;
  campaign_id: string;
  actor_user_id: string | null;
  actor_display_name: string | null;
  kind: CampaignMoneyTransactionKind;
  source_account: "external" | "common" | "player";
  source_user_id: string | null;
  source_display_name: string | null;
  destination_account: "external" | "common" | "player";
  destination_user_id: string | null;
  destination_display_name: string | null;
  amount_cp: number;
  comment: string | null;
  related_item_id: string | null;
  related_item_name: string | null;
  reversed_transaction_id: string | null;
  created_at: string;
}

export interface CampaignItemEvent {
  id: string;
  campaign_id: string;
  item_id: string | null;
  item_name: string | null;
  actor_user_id: string | null;
  actor_display_name: string | null;
  event_type: "created" | "published" | "claimed" | "transferred" | "returned" | "split" | "merged" | "sold" | "sale_cancelled" | "action_cancelled" | "purchased" | "dismantled" | "consumed" | "lost" | "donated";
  previous_owner_user_id: string | null;
  previous_owner_display_name: string | null;
  next_owner_user_id: string | null;
  next_owner_display_name: string | null;
  quantity: number | null;
  value_cp: number | null;
  comment: string | null;
  related_item_id: string | null;
  related_item_name: string | null;
  money_operation_id: string | null;
  reversed_event_id: string | null;
  created_at: string;
}

export interface CampaignItemRequest {
  id: string;
  campaign_id: string;
  item_id: string;
  item_name: string;
  requester_user_id: string;
  requester_display_name: string | null;
  owner_user_id: string;
  owner_display_name: string | null;
  status: "pending" | "accepted" | "refused" | "cancelled" | "invalidated";
  created_at: string;
  resolved_at: string | null;
}

export interface CampaignMoneyDebt {
  id: string;
  campaign_id: string;
  debtor_user_id: string;
  debtor_display_name: string | null;
  creditor_user_id: string;
  creditor_display_name: string | null;
  amount_cp: number;
  remaining_cp: number;
  status: "open" | "settled" | "cancelled";
  comment: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface PlayerEconomyData {
  viewer_user_id: string;
  items: CampaignInventoryItem[];
  balances: CampaignMoneyBalance[];
  totals: CampaignEconomyTotals;
  money_history: CampaignMoneyTransaction[];
  item_history: CampaignItemEvent[];
  requests: CampaignItemRequest[];
  debts: CampaignMoneyDebt[];
}

export interface ArchivesData {
  characters: ArchiveCharacter[];
  places: ArchivePlace[];
  show_translations: boolean;
}
