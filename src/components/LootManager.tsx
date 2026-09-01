import {
  BookOpen,
  CircleCheck,
  CircleDot,
  CircleX,
  Eye,
  EyeOff,
  ExternalLink,
  Gem,
  Pencil,
  Plus,
  Save,
  Search,
  Skull,
  Trash2,
  X,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState, type FormEvent, type ReactNode } from "react";
import {
  deleteLootEntry,
  loadLoot,
  saveLootEntry,
  setLootPlayerVisibility,
} from "../lib/referenceApi";
import {
  formatGoldValue,
  formatLootValue,
  lootLaneKind,
  lootTotalValueInGp,
} from "../lib/lootMonitoring";
import type { LootCurrency, LootDiscoveryStatus, LootEntry, LootLaneKind, LootSourceKind } from "../lib/types";
import { EmptyState, LoadingScreen, SectionHeading } from "./ui";

type LootManagerProps = {
  campaignId: string;
  demo: boolean;
  onNotice: (message: string) => void;
  onError: (message: string | null) => void;
};

type StatusFilter = "all" | LootDiscoveryStatus;
const volumes = [0, 1, 2, 3, 4, 5, 6];

function clean(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed || null;
}

function nextOrder(items: LootEntry[]) {
  return Math.max(0, ...items.map((item) => item.sort_order)) + 1;
}

function newLoot(campaignId: string, volume: number, items: LootEntry[]): LootEntry {
  return {
    id: crypto.randomUUID(),
    campaign_id: campaignId,
    reference_id: null,
    sort_order: nextOrder(items),
    volume: volume || 1,
    chapter: null,
    source_page: null,
    pdf_page: null,
    stat_block_page: null,
    area_code: null,
    area_title: null,
    location_name: null,
    source_kind: "treasure",
    source_owner: null,
    source_text: null,
    item_name: "",
    quantity_initial: "1",
    quantity_recoverable: "1",
    loot_category: null,
    acquisition_condition: null,
    consumable_during_encounter: false,
    availability_rule: null,
    book_unit_value_amount: null,
    book_unit_value_currency: null,
    book_total_value_amount: null,
    book_total_value_currency: null,
    aon_legacy_name: null,
    aon_legacy_unit_value_amount: null,
    aon_legacy_unit_value_currency: null,
    aon_legacy_total_value_amount: null,
    aon_legacy_total_value_currency: null,
    aon_legacy_url: null,
    pricing_basis: null,
    pricing_status: null,
    verification_status: null,
    discovery_status: "pending",
    player_visible: false,
    is_custom: true,
  };
}

function statusLabel(status: LootDiscoveryStatus) {
  if (status === "found") return "Acquis";
  if (status === "missed") return "Manqué";
  return "À découvrir";
}

function StatusIcon({ status, size = 15 }: { status: LootDiscoveryStatus; size?: number }) {
  if (status === "found") return <CircleCheck size={size} />;
  if (status === "missed") return <CircleX size={size} />;
  return <CircleDot size={size} />;
}

export function LootManager({ campaignId, demo, onNotice, onError }: LootManagerProps) {
  const [items, setItems] = useState<LootEntry[] | null>(null);
  const [volume, setVolume] = useState(0);
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<StatusFilter>("all");
  const [editing, setEditing] = useState<{ original: LootEntry | null; draft: LootEntry } | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      setItems(await loadLoot(campaignId, demo));
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : "Chargement des butins impossible.");
    }
  }, [campaignId, demo, onError]);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => { setEditing(null); setExpandedId(null); }, [volume]);

  const scopedItems = useMemo(() => (items ?? []).filter((item) => !volume || item.volume === volume), [items, volume]);
  const filtered = useMemo(() => scopedItems.filter((item) => {
    if (status !== "all" && item.discovery_status !== status) return false;
    const needle = query.trim().toLocaleLowerCase("fr");
    if (!needle) return true;
    return [
      item.item_name, item.source_text, item.location_name, item.area_code, item.area_title,
      item.loot_category, item.source_owner, item.aon_legacy_name, item.acquisition_condition,
      item.availability_rule, item.pricing_basis, item.volume, item.chapter, item.source_page,
    ].some((value) => String(value ?? "").toLocaleLowerCase("fr").includes(needle));
  }).sort((a, b) => a.sort_order - b.sort_order), [query, scopedItems, status]);

  const metrics = useMemo(() => {
    const found = scopedItems.filter((item) => item.discovery_status === "found");
    const missed = scopedItems.filter((item) => item.discovery_status === "missed");
    const pending = scopedItems.filter((item) => item.discovery_status === "pending");
    const knownValue = scopedItems.reduce((sum, item) => sum + (lootTotalValueInGp(item) ?? 0), 0);
    const missedValue = missed.reduce((sum, item) => sum + (lootTotalValueInGp(item) ?? 0), 0);
    return { found, missed, pending, knownValue, missedValue };
  }, [scopedItems]);

  if (!items) return <LoadingScreen label="Ouverture du registre des butins…" />;

  async function persist(draftInput = editing?.draft, original = editing?.original) {
    if (!draftInput) return;
    const draft: LootEntry = {
      ...draftInput,
      item_name: draftInput.item_name.trim(),
      quantity_initial: draftInput.quantity_initial.trim() || "1",
      quantity_recoverable: draftInput.quantity_recoverable.trim() || "1",
      area_code: clean(draftInput.area_code),
      area_title: clean(draftInput.area_title),
      location_name: clean(draftInput.location_name),
      source_text: clean(draftInput.source_text),
      loot_category: clean(draftInput.loot_category),
      source_owner: clean(draftInput.source_owner),
      aon_legacy_name: clean(draftInput.aon_legacy_name),
      aon_legacy_url: clean(draftInput.aon_legacy_url),
      acquisition_condition: clean(draftInput.acquisition_condition),
      availability_rule: clean(draftInput.availability_rule),
      pricing_basis: clean(draftInput.pricing_basis),
      pricing_status: clean(draftInput.pricing_status),
      verification_status: clean(draftInput.verification_status),
    };
    if (!draft.item_name) return onError("Le nom de l’objet est obligatoire.");
    setBusyId(draft.id);
    onError(null);
    try {
      if (!demo) await saveLootEntry(draft);
      setItems((current) => original
        ? current!.map((item) => item.id === draft.id ? draft : item)
        : [...current!, draft]);
      setEditing(null);
      setExpandedId(draft.id);
      onNotice(original ? "Butin mis à jour." : "Butin ajouté.");
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : "Enregistrement impossible.");
    } finally {
      setBusyId(null);
    }
  }

  async function setDiscovery(item: LootEntry, nextStatus: LootDiscoveryStatus) {
    const updated = { ...item, discovery_status: nextStatus };
    setBusyId(item.id);
    onError(null);
    try {
      if (!demo) await saveLootEntry(updated);
      setItems((current) => current!.map((entry) => entry.id === item.id ? updated : entry));
      onNotice(`« ${item.item_name} » : ${statusLabel(nextStatus).toLocaleLowerCase("fr")}.`);
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : "Mise à jour impossible.");
    } finally {
      setBusyId(null);
    }
  }

  async function toggleVisibility(item: LootEntry) {
    const playerVisible = !Boolean(item.player_visible);
    setBusyId(item.id);
    onError(null);
    try {
      if (!demo) await setLootPlayerVisibility(item.id, playerVisible);
      setItems((current) => current!.map((entry) => entry.id === item.id ? {
        ...entry,
        player_visible: playerVisible,
        discovery_status: playerVisible ? "found" : entry.discovery_status,
      } : entry));
      onNotice(playerVisible ? "Butin transmis aux joueurs." : "Butin masqué aux joueurs.");
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : "Modification de visibilité impossible.");
    } finally {
      setBusyId(null);
    }
  }

  async function remove(item: LootEntry) {
    if (!window.confirm(`Supprimer « ${item.item_name} » du registre des butins ?`)) return;
    try {
      if (!demo) await deleteLootEntry(item.id);
      setItems((current) => current!.filter((entry) => entry.id !== item.id));
      setExpandedId(null);
      onNotice("Butin supprimé.");
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : "Suppression impossible.");
    }
  }

  const treasureItems = filtered.filter((item) => lootLaneKind(item) === "treasure");
  const carriedItems = filtered.filter((item) => lootLaneKind(item) === "carried");
  const unlocatedItems = filtered.filter((item) => lootLaneKind(item) === "unlocated");

  return <div className="page-stack loot-monitor">
    <SectionHeading
      eyebrow="Poste de distribution"
      title="Butins"
      actions={<button className="button primary" onClick={() => setEditing({ original: null, draft: newLoot(campaignId, volume, items) })}><Plus size={17} />Ajouter un objet</button>}
    />

    <section className="loot-monitor-metrics" aria-label="Résumé des butins">
      <article><span>À découvrir</span><strong>{metrics.pending.length}</strong><small>objets encore possibles</small></article>
      <article className="found"><span>Acquis</span><strong>{metrics.found.length}</strong><small>{scopedItems.length ? Math.round(metrics.found.length / scopedItems.length * 100) : 0}% du registre</small></article>
      <article className="missed"><span>Manqués</span><strong>{metrics.missed.length}</strong><small>{metrics.missedValue ? formatGoldValue(metrics.missedValue) : "aucune valeur chiffrée"}</small></article>
      <article className="value"><span>Valeur recensée</span><strong>{formatGoldValue(metrics.knownValue)}</strong><small>hors objets sans prix fixe</small></article>
    </section>

    <section className="loot-monitor-toolbar panel">
      <div className="loot-volume-filter" role="group" aria-label="Filtrer par volume">
        {volumes.map((itemVolume) => <button key={itemVolume} type="button" className={volume === itemVolume ? "active" : ""} onClick={() => setVolume(itemVolume)}>{itemVolume ? `V${itemVolume}` : "Tous"}</button>)}
      </div>
      <label className="loot-monitor-search"><Search size={16} /><input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Objet, créature, zone, position…" /></label>
      <div className="loot-status-filter" role="group" aria-label="Filtrer par état">
        {(["all", "pending", "found", "missed"] as StatusFilter[]).map((itemStatus) => <button key={itemStatus} type="button" className={status === itemStatus ? "active" : ""} onClick={() => setStatus(itemStatus)}>{itemStatus === "all" ? "Tous les états" : statusLabel(itemStatus)}</button>)}
      </div>
    </section>

    {editing && !editing.original && <LootEditor draft={editing.draft} busy={busyId === editing.draft.id} onChange={(draft) => setEditing({ ...editing, draft })} onSave={() => void persist()} onCancel={() => setEditing(null)} />}

    <section className="loot-source-board">
      <LootLane
        kind="treasure"
        title="Trésors du récit"
        subtitle="Coffres, récompenses, objets placés et découvertes décrites dans l’aventure."
        icon={<Gem size={20} />}
        items={treasureItems}
        expandedId={expandedId}
        editing={editing}
        busyId={busyId}
        onExpand={setExpandedId}
        onBeginEdit={(item) => { setEditing({ original: item, draft: structuredClone(item) }); setExpandedId(item.id); }}
        onEditChange={(draft) => setEditing((current) => current ? { ...current, draft } : current)}
        onSave={() => void persist()}
        onCancelEdit={() => setEditing(null)}
        onDiscovery={(item, nextStatus) => void setDiscovery(item, nextStatus)}
        onVisibility={(item) => void toggleVisibility(item)}
        onDelete={(item) => void remove(item)}
      />
      <LootLane
        kind="carried"
        title="Sur les créatures"
        subtitle="Équipement, objets portés et consommables encore présents après la rencontre."
        icon={<Skull size={20} />}
        items={carriedItems}
        expandedId={expandedId}
        editing={editing}
        busyId={busyId}
        onExpand={setExpandedId}
        onBeginEdit={(item) => { setEditing({ original: item, draft: structuredClone(item) }); setExpandedId(item.id); }}
        onEditChange={(draft) => setEditing((current) => current ? { ...current, draft } : current)}
        onSave={() => void persist()}
        onCancelEdit={() => setEditing(null)}
        onDiscovery={(item, nextStatus) => void setDiscovery(item, nextStatus)}
        onVisibility={(item) => void toggleVisibility(item)}
        onDelete={(item) => void remove(item)}
      />
    </section>

    {unlocatedItems.length > 0 && <section className="loot-unlocated panel">
      <header><div><p className="eyebrow">Contrôle de source</p><h3>À localiser dans le livre</h3></div><span>{unlocatedItems.length}</span></header>
      <p>Ces objets apparaissent dans un récapitulatif, mais leur scène précise reste à retrouver.</p>
      <div>{unlocatedItems.map((item) => <button key={item.id} type="button" onClick={() => setExpandedId(expandedId === item.id ? null : item.id)}><BookOpen size={16} /><strong>{item.item_name}</strong><small>V{item.volume} · p. {item.source_page ?? "—"}</small></button>)}</div>
    </section>}

    <footer className="loot-monitor-footer">
      <span>{filtered.length} objet{filtered.length > 1 ? "s" : ""} affiché{filtered.length > 1 ? "s" : ""} · cliquer sur une fiche pour les détails.</span>
    </footer>
  </div>;
}

type LootLaneProps = {
  kind: Exclude<LootLaneKind, "unlocated">;
  title: string;
  subtitle: string;
  icon: ReactNode;
  items: LootEntry[];
  expandedId: string | null;
  editing: { original: LootEntry | null; draft: LootEntry } | null;
  busyId: string | null;
  onExpand: (id: string | null) => void;
  onBeginEdit: (item: LootEntry) => void;
  onEditChange: (draft: LootEntry) => void;
  onSave: () => void;
  onCancelEdit: () => void;
  onDiscovery: (item: LootEntry, status: LootDiscoveryStatus) => void;
  onVisibility: (item: LootEntry) => void;
  onDelete: (item: LootEntry) => void;
};

function LootLane(props: LootLaneProps) {
  const laneValue = props.items.reduce((sum, item) => sum + (lootTotalValueInGp(item) ?? 0), 0);
  return <section className={`loot-lane loot-lane-${props.kind}`}>
    <header><span>{props.icon}</span><div><h3>{props.title}</h3><p>{props.subtitle}</p></div><aside><strong>{props.items.length}</strong><small>{formatGoldValue(laneValue)}</small></aside></header>
    <div className="loot-lane-list">
      {props.items.map((item) => {
        const isEditing = props.editing?.original?.id === item.id;
        if (isEditing) return <LootEditor key={item.id} draft={props.editing!.draft} busy={props.busyId === item.id} onChange={props.onEditChange} onSave={props.onSave} onCancel={props.onCancelEdit} />;
        return <LootCard
          key={item.id}
          item={item}
          expanded={props.expandedId === item.id}
          busy={props.busyId === item.id}
          onExpand={() => props.onExpand(props.expandedId === item.id ? null : item.id)}
          onEdit={() => props.onBeginEdit(item)}
          onDiscovery={(nextStatus) => props.onDiscovery(item, nextStatus)}
          onVisibility={() => props.onVisibility(item)}
          onDelete={() => props.onDelete(item)}
        />;
      })}
      {props.items.length === 0 && <EmptyState title={props.kind === "treasure" ? "Aucun trésor ici" : "Aucun objet porté ici"}>Les filtres actuels ne renvoient aucun objet dans cette catégorie.</EmptyState>}
    </div>
  </section>;
}

function LootCard({ item, expanded, busy, onExpand, onEdit, onDiscovery, onVisibility, onDelete }: {
  item: LootEntry;
  expanded: boolean;
  busy: boolean;
  onExpand: () => void;
  onEdit: () => void;
  onDiscovery: (status: LootDiscoveryStatus) => void;
  onVisibility: () => void;
  onDelete: () => void;
}) {
  const itemStatus = item.discovery_status;
  const location = [item.area_code, item.location_name || item.area_title].filter(Boolean).join(" · ");
  const bookUnit = formatLootValue(item.book_unit_value_amount, item.book_unit_value_currency);
  const bookTotal = formatLootValue(item.book_total_value_amount, item.book_total_value_currency);
  const aonUnit = formatLootValue(item.aon_legacy_unit_value_amount, item.aon_legacy_unit_value_currency);
  const aonTotal = formatLootValue(item.aon_legacy_total_value_amount, item.aon_legacy_total_value_currency);
  const displayedTotal = bookTotal !== "—" ? bookTotal : aonTotal;
  const aonUrls = item.aon_legacy_url?.split(";").map((url) => url.trim()).filter(Boolean) ?? [];
  return <article className={`loot-monitor-card status-${itemStatus} ${expanded ? "expanded" : ""}`}>
    <button type="button" className="loot-card-summary" onClick={onExpand} aria-expanded={expanded}>
      <span className="loot-card-status"><StatusIcon status={itemStatus} /><small>{statusLabel(itemStatus)}</small></span>
      <span className="loot-card-main"><span className="loot-name-line"><strong>{item.item_name}</strong>{aonUrls.length > 0 && <img src="/nethys-mask.png" alt="Référence Archives of Nethys" />}</span><small>{location || `Volume ${item.volume} · localisation non renseignée`}</small></span>
      <span className="loot-card-value"><strong>{displayedTotal}</strong><small>{item.quantity_recoverable === "1" ? "1 objet" : `Qté ${item.quantity_recoverable}`}</small></span>
    </button>
    {expanded && <div className="loot-card-details">
      <div className="loot-detail-grid">
        {item.source_owner && <div><span>Sur / auprès de</span><strong>{item.source_owner}</strong></div>}
        <div><span>Source</span><strong>V{item.volume}{item.chapter ? ` · ch. ${item.chapter}` : ""} · p. {item.source_page ?? "—"}{item.area_code ? ` · ${item.area_code}` : ""}</strong></div>
        <div><span>Quantité</span><strong>{item.quantity_recoverable}{item.quantity_initial !== item.quantity_recoverable ? ` récupérable sur ${item.quantity_initial}` : ""}</strong></div>
        <div><span>Prix du livre</span><strong>{bookUnit} / unité · {bookTotal} total</strong></div>
        <div><span>Prix AoN Legacy</span><strong>{aonUnit} / unité · {aonTotal} total</strong></div>
        <div><span>Partage joueurs</span><strong>{item.player_visible ? "Visible" : "Masqué"}</strong></div>
      </div>
      {item.source_text && <details className="loot-source-proof"><summary>Extrait source</summary><p>{item.source_text}</p></details>}
      {item.acquisition_condition && <p className="loot-card-condition"><CircleDot size={14} />{item.acquisition_condition}</p>}
      {item.availability_rule && <p className="loot-card-notes">{item.availability_rule}</p>}
      {item.pricing_basis && <p className="loot-card-notes">Prix : {item.pricing_basis}</p>}
      <div className="loot-card-actions">
        <div className="loot-quick-status" role="group" aria-label={`État de ${item.item_name}`}>
          {(["pending", "found", "missed"] as LootDiscoveryStatus[]).map((nextStatus) => <button key={nextStatus} type="button" className={itemStatus === nextStatus ? `active ${nextStatus}` : nextStatus} disabled={busy} onClick={() => onDiscovery(nextStatus)}><StatusIcon status={nextStatus} />{statusLabel(nextStatus)}</button>)}
        </div>
        <span className="loot-action-spacer" />
        {aonUrls.map((url, index) => <a key={url} className="loot-aon-link" href={url} target="_blank" rel="noreferrer"><img src="/nethys-mask.png" alt="" /><span>{index === 0 ? item.aon_legacy_name || "Voir sur AoN" : `Référence AoN ${index + 1}`}</span><ExternalLink size={13} /></a>)}
        <button type="button" className={item.player_visible ? "icon-button is-visible" : "icon-button"} title={item.player_visible ? "Masquer aux joueurs" : "Transmettre aux joueurs"} aria-label={item.player_visible ? "Masquer aux joueurs" : "Transmettre aux joueurs"} disabled={busy} onClick={onVisibility}>{item.player_visible ? <Eye size={16} /> : <EyeOff size={16} />}</button>
        <button type="button" className="icon-button" title="Modifier" aria-label="Modifier" disabled={busy} onClick={onEdit}><Pencil size={16} /></button>
        <button type="button" className="icon-button danger" title="Supprimer" aria-label="Supprimer" disabled={busy} onClick={onDelete}><Trash2 size={16} /></button>
      </div>
    </div>}
  </article>;
}

function LootEditor({ draft, busy, onChange, onSave, onCancel }: {
  draft: LootEntry;
  busy: boolean;
  onChange: (draft: LootEntry) => void;
  onSave: () => void;
  onCancel: () => void;
}) {
  const patch = (value: Partial<LootEntry>) => onChange({ ...draft, ...value });
  const numberOrNull = (value: string) => value === "" ? null : Number(value);
  const currencyOrNull = (value: string) => value ? value as LootCurrency : null;
  function submit(event: FormEvent) { event.preventDefault(); onSave(); }
  return <form className="loot-editor panel" onSubmit={submit}>
    <header><div><p className="eyebrow">{draft.is_custom ? "Saisie MJ" : "Fiche de référence"}</p><h3>{draft.item_name || "Nouvel objet"}</h3></div><button type="button" className="icon-button" aria-label="Annuler" onClick={onCancel}><X size={16} /></button></header>
    <div className="loot-editor-grid">
      <label className="span-2">Nom de l’objet<input required value={draft.item_name} onChange={(event) => patch({ item_name: event.target.value })} /></label>
      <label>Type de source<select value={draft.source_kind} onChange={(event) => patch({ source_kind: event.target.value as LootSourceKind })}><option value="treasure">Treasure</option><option value="reward">Reward</option><option value="narrative">Narration</option><option value="carried">Porté</option><option value="infused_carried">Objet infusé porté</option><option value="chapter_checklist_only">Checklist à localiser</option></select></label>
      <label>État<select value={draft.discovery_status} onChange={(event) => patch({ discovery_status: event.target.value as LootDiscoveryStatus })}><option value="pending">À découvrir</option><option value="found">Acquis</option><option value="missed">Manqué</option></select></label>
      <label>Quantité initiale<input value={draft.quantity_initial} onChange={(event) => patch({ quantity_initial: event.target.value })} /></label>
      <label>Quantité récupérable<input value={draft.quantity_recoverable} onChange={(event) => patch({ quantity_recoverable: event.target.value })} /></label>
      <label>Volume<select value={draft.volume} onChange={(event) => patch({ volume: Number(event.target.value) })}>{[1,2,3,4,5,6].map((itemVolume) => <option key={itemVolume} value={itemVolume}>Volume {itemVolume}</option>)}</select></label>
      <label>Chapitre<input type="number" min="1" value={draft.chapter ?? ""} onChange={(event) => patch({ chapter: event.target.value ? Number(event.target.value) : null })} /></label>
      <label>Page livre<input type="number" min="1" value={draft.source_page ?? ""} onChange={(event) => patch({ source_page: event.target.value ? Number(event.target.value) : null })} /></label>
      <label>Zone<input placeholder="ex. D4" value={draft.area_code ?? ""} onChange={(event) => patch({ area_code: event.target.value })} /></label>
      <label>Titre de zone<input value={draft.area_title ?? ""} onChange={(event) => patch({ area_title: event.target.value })} /></label>
      <label>Lieu<input value={draft.location_name ?? ""} onChange={(event) => patch({ location_name: event.target.value })} /></label>
      <label>Créature / porteur<input value={draft.source_owner ?? ""} onChange={(event) => patch({ source_owner: event.target.value })} /></label>
      <label>Catégorie<input value={draft.loot_category ?? ""} onChange={(event) => patch({ loot_category: event.target.value })} /></label>
      <label className="span-2">Condition de récupération<textarea value={draft.acquisition_condition ?? ""} onChange={(event) => patch({ acquisition_condition: event.target.value })} /></label>
      <label className="span-2">Règle de disponibilité<textarea value={draft.availability_rule ?? ""} onChange={(event) => patch({ availability_rule: event.target.value })} /></label>
      <label className="loot-editor-check"><input type="checkbox" checked={draft.consumable_during_encounter} onChange={(event) => patch({ consumable_during_encounter: event.target.checked })} />Peut être consommé pendant la rencontre</label>
      <label>Prix unitaire du livre<input type="number" min="0" step="any" value={draft.book_unit_value_amount ?? ""} onChange={(event) => patch({ book_unit_value_amount: numberOrNull(event.target.value) })} /></label>
      <label>Devise livre<select value={draft.book_unit_value_currency ?? ""} onChange={(event) => patch({ book_unit_value_currency: currencyOrNull(event.target.value) })}><option value="">—</option><option value="pp">pp</option><option value="gp">gp</option><option value="sp">sp</option><option value="cp">cp</option></select></label>
      <label>Prix total du livre<input type="number" min="0" step="any" value={draft.book_total_value_amount ?? ""} onChange={(event) => patch({ book_total_value_amount: numberOrNull(event.target.value) })} /></label>
      <label>Devise total livre<select value={draft.book_total_value_currency ?? ""} onChange={(event) => patch({ book_total_value_currency: currencyOrNull(event.target.value) })}><option value="">—</option><option value="pp">pp</option><option value="gp">gp</option><option value="sp">sp</option><option value="cp">cp</option></select></label>
      <label>Nom de la fiche AoN Legacy<input value={draft.aon_legacy_name ?? ""} onChange={(event) => patch({ aon_legacy_name: event.target.value })} /></label>
      <label>Lien(s) AoN Legacy<input placeholder="https://2e.aonprd.com/…" value={draft.aon_legacy_url ?? ""} onChange={(event) => patch({ aon_legacy_url: event.target.value })} /></label>
      <label>Prix unitaire AoN<input type="number" min="0" step="any" value={draft.aon_legacy_unit_value_amount ?? ""} onChange={(event) => patch({ aon_legacy_unit_value_amount: numberOrNull(event.target.value) })} /></label>
      <label>Devise AoN<select value={draft.aon_legacy_unit_value_currency ?? ""} onChange={(event) => patch({ aon_legacy_unit_value_currency: currencyOrNull(event.target.value) })}><option value="">—</option><option value="pp">pp</option><option value="gp">gp</option><option value="sp">sp</option><option value="cp">cp</option></select></label>
      <label>Prix total AoN<input type="number" min="0" step="any" value={draft.aon_legacy_total_value_amount ?? ""} onChange={(event) => patch({ aon_legacy_total_value_amount: numberOrNull(event.target.value) })} /></label>
      <label>Devise total AoN<select value={draft.aon_legacy_total_value_currency ?? ""} onChange={(event) => patch({ aon_legacy_total_value_currency: currencyOrNull(event.target.value) })}><option value="">—</option><option value="pp">pp</option><option value="gp">gp</option><option value="sp">sp</option><option value="cp">cp</option></select></label>
      <label className="span-2">Base du prix<textarea value={draft.pricing_basis ?? ""} onChange={(event) => patch({ pricing_basis: event.target.value })} /></label>
      <label className="span-2">Extrait source<textarea value={draft.source_text ?? ""} onChange={(event) => patch({ source_text: event.target.value })} /></label>
    </div>
    <footer><button type="button" className="button secondary" onClick={onCancel}>Annuler</button><button className="button primary" disabled={busy}><Save size={16} />{busy ? "Enregistrement…" : "Enregistrer"}</button></footer>
  </form>;
}
