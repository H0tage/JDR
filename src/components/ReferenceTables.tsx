import {
  Check,
  Feather,
  Languages,
  Pencil,
  Plus,
  RotateCcw,
  Search,
  Trash2,
  X,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  deleteArchiveCharacter,
  deleteArchivePlace,
  deleteLootEntry,
  loadArchives,
  loadLoot,
  resetReferenceData,
  saveArchiveCharacter,
  saveArchivePlace,
  saveLootEntry,
  saveTranslationPreference,
} from "../lib/referenceApi";
import type { ArchiveCharacter, ArchivePlace, ArchivesData, LootEntry, TranslationOrigin } from "../lib/types";
import { EmptyState, LoadingScreen, SectionHeading } from "./ui";

type ReferenceProps = {
  campaignId: string;
  demo: boolean;
  onNotice: (message: string) => void;
  onError: (message: string | null) => void;
};

type ArchiveEdit =
  | { kind: "character"; original: ArchiveCharacter | null; draft: ArchiveCharacter }
  | { kind: "place"; original: ArchivePlace | null; draft: ArchivePlace };

const volumes = [0, 1, 2, 3, 4, 5, 6];

function clean(value: string): string | null {
  const trimmed = value.trim();
  return trimmed || null;
}

function matchesSearch(values: Array<string | number | null | undefined>, query: string) {
  if (!query.trim()) return true;
  const needle = query.trim().toLocaleLowerCase("fr");
  return values.some((value) => String(value ?? "").toLocaleLowerCase("fr").includes(needle));
}

function nextOrder(items: Array<{ sort_order: number }>) {
  return Math.max(0, ...items.map((item) => item.sort_order)) + 1;
}

function translationOrigin(original: { translated_name: string | null; translation_origin: TranslationOrigin } | null, translated: string | null): TranslationOrigin {
  if (!translated) return "none";
  if (!original || translated !== original.translated_name) return "custom";
  return original.translation_origin;
}

function Translation({ value, origin }: { value: string | null; origin: TranslationOrigin }) {
  if (!value) return <span className="muted-dash">—</span>;
  return (
    <span className={`translated-name translation-${origin}`}>
      {value}
      {origin === "custom" && <Feather size={12} aria-label="Traduction personnalisée par le MJ" />}
    </span>
  );
}

function VolumeFilter({ value, onChange }: { value: number; onChange: (volume: number) => void }) {
  return (
    <div className="volume-filter" role="group" aria-label="Filtrer par volume">
      {volumes.map((volume) => (
        <button
          key={volume}
          type="button"
          className={value === volume ? "active" : ""}
          aria-pressed={value === volume}
          onClick={() => onChange(volume)}
        >
          {volume === 0 ? "Tous" : `V${volume}`}
        </button>
      ))}
    </div>
  );
}

function RowActions({ editing, busy, onEdit, onSave, onCancel, onDelete }: {
  editing: boolean;
  busy: boolean;
  onEdit: () => void;
  onSave: () => void;
  onCancel: () => void;
  onDelete: () => void;
}) {
  return (
    <div className="reference-row-actions">
      {editing ? (
        <>
          <button type="button" className="icon-button confirm" title="Enregistrer" aria-label="Enregistrer" disabled={busy} onClick={onSave}><Check size={16} /></button>
          <button type="button" className="icon-button" title="Annuler" aria-label="Annuler" disabled={busy} onClick={onCancel}><X size={16} /></button>
        </>
      ) : (
        <>
          <button type="button" className="icon-button" title="Modifier" aria-label="Modifier" onClick={onEdit}><Pencil size={15} /></button>
          <button type="button" className="icon-button danger" title="Supprimer" aria-label="Supprimer" onClick={onDelete}><Trash2 size={15} /></button>
        </>
      )}
    </div>
  );
}

function ConfirmReset({ scope, onCancel, onConfirm, busy }: {
  scope: "archives" | "loot";
  onCancel: () => void;
  onConfirm: () => void;
  busy: boolean;
}) {
  const label = scope === "archives" ? "les archives" : "les butins";
  return (
    <div className="modal-backdrop" role="presentation">
      <section className="modal-card reset-dialog" role="dialog" aria-modal="true" aria-labelledby="reset-title">
        <div className="modal-head"><div><p className="eyebrow">Action irréversible</p><h3 id="reset-title">Restaurer {label} ?</h3></div><button type="button" className="icon-button" onClick={onCancel}><X /></button></div>
        <p className="modal-prose"><strong>Attention : en restaurant, vous supprimerez toutes vos modifications, créations et suppressions.</strong> Les données seront remises exactement dans leur état d’origine.</p>
        <div className="modal-actions"><button type="button" className="button secondary" disabled={busy} onClick={onCancel}>Annuler</button><button type="button" className="button danger-solid" disabled={busy} onClick={onConfirm}>{busy ? "Restauration…" : "Restaurer définitivement"}</button></div>
      </section>
    </div>
  );
}

export function ArchivesTab(props: ReferenceProps) {
  const { campaignId, demo, onNotice, onError } = props;
  const [data, setData] = useState<ArchivesData | null>(null);
  const [kind, setKind] = useState<"character" | "place">("character");
  const [volume, setVolume] = useState(0);
  const [query, setQuery] = useState("");
  const [editing, setEditing] = useState<ArchiveEdit | null>(null);
  const [busy, setBusy] = useState(false);
  const [confirmReset, setConfirmReset] = useState(false);

  const refresh = useCallback(async () => {
    try {
      setData(await loadArchives(campaignId, demo));
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : "Chargement des archives impossible.");
    }
  }, [campaignId, demo, onError]);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => { setEditing(null); }, [kind, volume]);

  const characters = useMemo(() => (data?.characters ?? []).filter((item) =>
    (!volume || item.first_volume === volume) && matchesSearch([
      item.first_name, item.last_name, item.translated_name, item.role_text, item.first_volume, item.first_page,
    ], query)), [data?.characters, query, volume]);
  const places = useMemo(() => (data?.places ?? []).filter((item) =>
    (!volume || item.first_volume === volume) && matchesSearch([
      item.original_name, item.translated_name, item.place_type, item.function_text, item.first_volume, item.first_page,
    ], query)), [data?.places, query, volume]);

  if (!data) return <LoadingScreen label="Ouverture des archives…" />;

  function beginCharacter(original: ArchiveCharacter | null) {
    setEditing({
      kind: "character",
      original,
      draft: original ? structuredClone(original) : {
        id: crypto.randomUUID(), campaign_id: campaignId, template_key: null,
        sort_order: nextOrder(data!.characters), first_name: "", last_name: null,
        translated_name: null, translation_origin: "none", role_text: null,
        first_volume: volume || 1, first_page: null, is_custom: true,
      },
    });
  }

  function beginPlace(original: ArchivePlace | null) {
    setEditing({
      kind: "place",
      original,
      draft: original ? structuredClone(original) : {
        id: crypto.randomUUID(), campaign_id: campaignId, template_key: null,
        sort_order: nextOrder(data!.places), original_name: "", translated_name: null,
        translation_origin: "none", place_type: null, function_text: null,
        first_volume: volume || 1, first_page: null, is_custom: true,
      },
    });
  }

  async function persistEdit() {
    if (!editing) return;
    if (editing.kind === "character") {
      const draft: ArchiveCharacter = { ...editing.draft };
      draft.first_name = draft.first_name.trim();
      draft.last_name = clean(draft.last_name ?? "");
      draft.translated_name = clean(draft.translated_name ?? "");
      draft.role_text = clean(draft.role_text ?? "");
      draft.translation_origin = translationOrigin(editing.original, draft.translated_name);
      if (!draft.first_name && !draft.last_name) return onError("Indiquez au moins un prénom ou un nom.");
      setBusy(true);
      onError(null);
      try {
        if (!demo) await saveArchiveCharacter(draft);
        setData((current) => current ? { ...current, characters: editing.original ? current.characters.map((item) => item.id === draft.id ? draft : item) : [...current.characters, draft] } : current);
        setEditing(null);
        onNotice(editing.original ? "Entrée mise à jour." : "Entrée ajoutée aux archives.");
      } catch (caught) {
        onError(caught instanceof Error ? caught.message : "Enregistrement impossible.");
      } finally {
        setBusy(false);
      }
    } else {
      const draft: ArchivePlace = { ...editing.draft };
      draft.original_name = draft.original_name.trim();
      draft.translated_name = clean(draft.translated_name ?? "");
      draft.place_type = clean(draft.place_type ?? "");
      draft.function_text = clean(draft.function_text ?? "");
      draft.translation_origin = translationOrigin(editing.original, draft.translated_name);
      if (!draft.original_name) return onError("Le nom original du lieu est obligatoire.");
      setBusy(true);
      onError(null);
      try {
        if (!demo) await saveArchivePlace(draft);
        setData((current) => current ? { ...current, places: editing.original ? current.places.map((item) => item.id === draft.id ? draft : item) : [...current.places, draft] } : current);
        setEditing(null);
        onNotice(editing.original ? "Entrée mise à jour." : "Entrée ajoutée aux archives.");
      } catch (caught) {
        onError(caught instanceof Error ? caught.message : "Enregistrement impossible.");
      } finally {
        setBusy(false);
      }
    }
  }

  async function removeCharacter(item: ArchiveCharacter) {
    if (!window.confirm(`Supprimer ${[item.first_name, item.last_name].filter(Boolean).join(" ")} des archives ?`)) return;
    try {
      if (!demo) await deleteArchiveCharacter(item.id);
      setData((current) => current ? { ...current, characters: current.characters.filter((entry) => entry.id !== item.id) } : current);
      onNotice("Personnage supprimé.");
    } catch (caught) { onError(caught instanceof Error ? caught.message : "Suppression impossible."); }
  }

  async function removePlace(item: ArchivePlace) {
    if (!window.confirm(`Supprimer « ${item.original_name} » des archives ?`)) return;
    try {
      if (!demo) await deleteArchivePlace(item.id);
      setData((current) => current ? { ...current, places: current.places.filter((entry) => entry.id !== item.id) } : current);
      onNotice("Lieu supprimé.");
    } catch (caught) { onError(caught instanceof Error ? caught.message : "Suppression impossible."); }
  }

  async function toggleTranslations() {
    const show = !data!.show_translations;
    setData({ ...data!, show_translations: show });
    try {
      if (!demo) await saveTranslationPreference(campaignId, show);
      onNotice(show ? "Traductions françaises affichées." : "Traductions françaises masquées.");
    } catch (caught) {
      setData({ ...data!, show_translations: !show });
      onError(caught instanceof Error ? caught.message : "Modification impossible.");
    }
  }

  async function restore() {
    setBusy(true);
    try {
      if (!demo) await resetReferenceData(campaignId, "archives");
      await refresh();
      setEditing(null);
      setConfirmReset(false);
      onNotice("Archives restaurées dans leur état d’origine.");
    } catch (caught) { onError(caught instanceof Error ? caught.message : "Restauration impossible."); }
    finally { setBusy(false); }
  }

  const shownCount = kind === "character" ? characters.length : places.length;
  return (
    <div className="page-stack reference-page">
      <SectionHeading eyebrow="Noms propres de la campagne" title="Archives" actions={<button className="button primary" onClick={() => kind === "character" ? beginCharacter(null) : beginPlace(null)}><Plus size={17} />Ajouter</button>} />
      <div className="reference-kind-tabs" role="tablist">
        <button role="tab" aria-selected={kind === "character"} className={kind === "character" ? "active" : ""} onClick={() => setKind("character")}>Personnages <span>{data.characters.length}</span></button>
        <button role="tab" aria-selected={kind === "place"} className={kind === "place" ? "active" : ""} onClick={() => setKind("place")}>Lieux <span>{data.places.length}</span></button>
      </div>
      <div className="reference-toolbar">
        <VolumeFilter value={volume} onChange={setVolume} />
        <label className="reference-search"><Search size={16} /><input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder={kind === "character" ? "Rechercher un personnage…" : "Rechercher un lieu…"} /></label>
        <span className="reference-count">{shownCount} résultat{shownCount > 1 ? "s" : ""}</span>
      </div>

      {kind === "character" ? (
        <CharacterTable rows={characters} showTranslations={data.show_translations} editing={editing?.kind === "character" ? editing : null} setEditing={setEditing} busy={busy} onBegin={beginCharacter} onSave={() => void persistEdit()} onDelete={(item) => void removeCharacter(item)} />
      ) : (
        <PlaceTable rows={places} showTranslations={data.show_translations} editing={editing?.kind === "place" ? editing : null} setEditing={setEditing} busy={busy} onBegin={beginPlace} onSave={() => void persistEdit()} onDelete={(item) => void removePlace(item)} />
      )}

      <div className="reference-footer">
        <label className="reference-translation-toggle"><input type="checkbox" checked={data.show_translations} onChange={() => void toggleTranslations()} /><Languages size={17} /><span><strong>Afficher les traductions françaises</strong><small>Décochez pour utiliser les archives entièrement en version originale.</small></span></label>
        <button type="button" className="text-button danger-text" onClick={() => setConfirmReset(true)}><RotateCcw size={15} />Restaurer la base d’origine</button>
      </div>
      {confirmReset && <ConfirmReset scope="archives" busy={busy} onCancel={() => setConfirmReset(false)} onConfirm={() => void restore()} />}
    </div>
  );
}

function CharacterTable({ rows, showTranslations, editing, setEditing, busy, onBegin, onSave, onDelete }: {
  rows: ArchiveCharacter[];
  showTranslations: boolean;
  editing: Extract<ArchiveEdit, { kind: "character" }> | null;
  setEditing: (value: ArchiveEdit | null) => void;
  busy: boolean;
  onBegin: (item: ArchiveCharacter) => void;
  onSave: () => void;
  onDelete: (item: ArchiveCharacter) => void;
}) {
  const rendered = editing && !editing.original ? [editing.draft, ...rows] : rows;
  return <div className="table-wrap"><table className="data-table reference-table character-table"><thead><tr><th>Ordre</th><th>Prénom</th><th>Nom</th>{showTranslations && <th>Nom traduit</th>}<th>Nature / rôle</th><th>Première apparition</th><th /></tr></thead><tbody>
    {rendered.map((item) => {
      const active = editing?.draft.id === item.id;
      const draft = active ? editing.draft : item;
      return <tr key={item.id} className={active ? "editing-row" : ""}>
        <td>{active ? <input className="cell-input order-input" type="number" min="1" value={draft.sort_order} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, sort_order: Number(event.target.value) } })} /> : item.sort_order}</td>
        <td>{active ? <input className="cell-input" value={draft.first_name} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, first_name: event.target.value } })} /> : item.first_name || "—"}</td>
        <td>{active ? <input className="cell-input" value={draft.last_name ?? ""} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, last_name: event.target.value } })} /> : item.last_name || "—"}</td>
        {showTranslations && <td>{active ? <input className="cell-input" value={draft.translated_name ?? ""} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, translated_name: event.target.value } })} /> : <Translation value={item.translated_name} origin={item.translation_origin} />}</td>}
        <td className="wide-cell">{active ? <textarea className="cell-input" value={draft.role_text ?? ""} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, role_text: event.target.value } })} /> : item.role_text || "—"}</td>
        <td>{active ? <div className="appearance-inputs"><select value={draft.first_volume} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, first_volume: Number(event.target.value) } })}>{[1,2,3,4,5,6].map((v) => <option key={v} value={v}>V{v}</option>)}</select><input type="number" min="1" placeholder="Page" value={draft.first_page ?? ""} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, first_page: event.target.value ? Number(event.target.value) : null } })} /></div> : <>V{item.first_volume} · p. {item.first_page ?? "—"}</>}</td>
        <td><RowActions editing={active} busy={busy} onEdit={() => onBegin(item)} onSave={onSave} onCancel={() => setEditing(null)} onDelete={() => onDelete(item)} /></td>
      </tr>;
    })}
    {rendered.length === 0 && <tr><td colSpan={showTranslations ? 7 : 6}><EmptyState title="Aucun personnage">Modifiez les filtres ou ajoutez une entrée.</EmptyState></td></tr>}
  </tbody></table></div>;
}

function PlaceTable({ rows, showTranslations, editing, setEditing, busy, onBegin, onSave, onDelete }: {
  rows: ArchivePlace[];
  showTranslations: boolean;
  editing: Extract<ArchiveEdit, { kind: "place" }> | null;
  setEditing: (value: ArchiveEdit | null) => void;
  busy: boolean;
  onBegin: (item: ArchivePlace) => void;
  onSave: () => void;
  onDelete: (item: ArchivePlace) => void;
}) {
  const rendered = editing && !editing.original ? [editing.draft, ...rows] : rows;
  return <div className="table-wrap"><table className="data-table reference-table place-table"><thead><tr><th>Ordre</th><th>Nom original</th>{showTranslations && <th>Nom traduit</th>}<th>Type</th><th>Fonction</th><th>Première apparition</th><th /></tr></thead><tbody>
    {rendered.map((item) => {
      const active = editing?.draft.id === item.id;
      const draft = active ? editing.draft : item;
      return <tr key={item.id} className={active ? "editing-row" : ""}>
        <td>{active ? <input className="cell-input order-input" type="number" min="1" value={draft.sort_order} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, sort_order: Number(event.target.value) } })} /> : item.sort_order}</td>
        <td><strong>{active ? <input className="cell-input" value={draft.original_name} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, original_name: event.target.value } })} /> : item.original_name}</strong></td>
        {showTranslations && <td>{active ? <input className="cell-input" value={draft.translated_name ?? ""} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, translated_name: event.target.value } })} /> : <Translation value={item.translated_name} origin={item.translation_origin} />}</td>}
        <td>{active ? <input className="cell-input" value={draft.place_type ?? ""} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, place_type: event.target.value } })} /> : item.place_type || "—"}</td>
        <td className="wide-cell">{active ? <textarea className="cell-input" value={draft.function_text ?? ""} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, function_text: event.target.value } })} /> : item.function_text || "—"}</td>
        <td>{active ? <div className="appearance-inputs"><select value={draft.first_volume} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, first_volume: Number(event.target.value) } })}>{[1,2,3,4,5,6].map((v) => <option key={v} value={v}>V{v}</option>)}</select><input type="number" min="1" placeholder="Page" value={draft.first_page ?? ""} onChange={(event) => setEditing({ ...editing!, draft: { ...draft, first_page: event.target.value ? Number(event.target.value) : null } })} /></div> : <>V{item.first_volume} · p. {item.first_page ?? "—"}</>}</td>
        <td><RowActions editing={active} busy={busy} onEdit={() => onBegin(item)} onSave={onSave} onCancel={() => setEditing(null)} onDelete={() => onDelete(item)} /></td>
      </tr>;
    })}
    {rendered.length === 0 && <tr><td colSpan={showTranslations ? 7 : 6}><EmptyState title="Aucun lieu">Modifiez les filtres ou ajoutez une entrée.</EmptyState></td></tr>}
  </tbody></table></div>;
}

export function LootTab(props: ReferenceProps) {
  const { campaignId, demo, onNotice, onError } = props;
  const [items, setItems] = useState<LootEntry[] | null>(null);
  const [volume, setVolume] = useState(0);
  const [query, setQuery] = useState("");
  const [editing, setEditing] = useState<{ original: LootEntry | null; draft: LootEntry } | null>(null);
  const [busy, setBusy] = useState(false);
  const [confirmReset, setConfirmReset] = useState(false);

  const refresh = useCallback(async () => {
    try { setItems(await loadLoot(campaignId, demo)); }
    catch (caught) { onError(caught instanceof Error ? caught.message : "Chargement des butins impossible."); }
  }, [campaignId, demo, onError]);
  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => { setEditing(null); }, [volume]);

  const filtered = useMemo(() => (items ?? []).filter((item) =>
    (!volume || item.volume === volume) && matchesSearch([
      item.original_name, item.description, item.location_name, item.position, item.nature, item.notes, item.volume, item.page,
    ], query)), [items, query, volume]);

  if (!items) return <LoadingScreen label="Inventaire des trésors…" />;

  function begin(original: LootEntry | null) {
    setEditing({ original, draft: original ? structuredClone(original) : {
      id: crypto.randomUUID(), campaign_id: campaignId, template_key: null,
      sort_order: nextOrder(items!), original_name: "", quantity: "1", description: null,
      unit_value: null, total_value: null, location_name: null, position: null,
      volume: volume || 1, page: null, nature: null, notes: null, is_custom: true,
    } });
  }

  async function persist() {
    if (!editing) return;
    const draft = { ...editing.draft, original_name: editing.draft.original_name.trim(), quantity: editing.draft.quantity.trim() || "1" };
    draft.description = clean(draft.description ?? "");
    draft.unit_value = clean(draft.unit_value ?? "");
    draft.total_value = clean(draft.total_value ?? "");
    draft.location_name = clean(draft.location_name ?? "");
    draft.position = clean(draft.position ?? "");
    draft.nature = clean(draft.nature ?? "");
    draft.notes = clean(draft.notes ?? "");
    if (!draft.original_name) return onError("Le nom original de l’objet est obligatoire.");
    setBusy(true); onError(null);
    try {
      if (!demo) await saveLootEntry(draft);
      setItems((current) => editing.original ? current!.map((item) => item.id === draft.id ? draft : item) : [...current!, draft]);
      setEditing(null);
      onNotice(editing.original ? "Butin mis à jour." : "Butin ajouté.");
    } catch (caught) { onError(caught instanceof Error ? caught.message : "Enregistrement impossible."); }
    finally { setBusy(false); }
  }

  async function remove(item: LootEntry) {
    if (!window.confirm(`Supprimer « ${item.original_name} » de la liste des butins ?`)) return;
    try {
      if (!demo) await deleteLootEntry(item.id);
      setItems((current) => current!.filter((entry) => entry.id !== item.id));
      onNotice("Butin supprimé.");
    } catch (caught) { onError(caught instanceof Error ? caught.message : "Suppression impossible."); }
  }

  async function restore() {
    setBusy(true);
    try {
      if (!demo) await resetReferenceData(campaignId, "loot");
      await refresh(); setEditing(null); setConfirmReset(false);
      onNotice("Butins restaurés dans leur état d’origine.");
    } catch (caught) { onError(caught instanceof Error ? caught.message : "Restauration impossible."); }
    finally { setBusy(false); }
  }

  const rendered = editing && !editing.original ? [editing.draft, ...filtered] : filtered;
  return (
    <div className="page-stack reference-page">
      <SectionHeading eyebrow="Trésors dans l’ordre de découverte" title="Butins" actions={<button className="button primary" onClick={() => begin(null)}><Plus size={17} />Ajouter</button>} />
      <div className="reference-toolbar">
        <VolumeFilter value={volume} onChange={setVolume} />
        <label className="reference-search"><Search size={16} /><input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Objet, lieu, position, nature…" /></label>
        <span className="reference-count">{filtered.length} résultat{filtered.length > 1 ? "s" : ""}</span>
      </div>
      <div className="table-wrap"><table className="data-table reference-table loot-table"><thead><tr><th>Ordre</th><th>Nom original</th><th>Qté</th><th>Description</th><th>Valeur unitaire</th><th>Valeur totale</th><th>Lieu</th><th>Position</th><th>Volume</th><th>Page</th><th>Nature</th><th>Conditions / remarques</th><th /></tr></thead><tbody>
        {rendered.map((item) => {
          const active = editing?.draft.id === item.id;
          const draft = active ? editing.draft : item;
          const patch = (value: Partial<LootEntry>) => setEditing({ ...editing!, draft: { ...draft, ...value } });
          return <tr key={item.id} className={active ? "editing-row" : ""}>
            <td>{active ? <input className="cell-input order-input" type="number" min="1" value={draft.sort_order} onChange={(e) => patch({ sort_order: Number(e.target.value) })} /> : item.sort_order}</td>
            <td><strong>{active ? <input className="cell-input" value={draft.original_name} onChange={(e) => patch({ original_name: e.target.value })} /> : item.original_name}</strong></td>
            <td>{active ? <input className="cell-input quantity-input" value={draft.quantity} onChange={(e) => patch({ quantity: e.target.value })} /> : item.quantity}</td>
            <td className="description-cell">{active ? <textarea className="cell-input" value={draft.description ?? ""} onChange={(e) => patch({ description: e.target.value })} /> : item.description || "—"}</td>
            <td>{active ? <input className="cell-input value-input" value={draft.unit_value ?? ""} onChange={(e) => patch({ unit_value: e.target.value })} /> : item.unit_value || "—"}</td>
            <td>{active ? <input className="cell-input value-input" value={draft.total_value ?? ""} onChange={(e) => patch({ total_value: e.target.value })} /> : item.total_value || "—"}</td>
            <td>{active ? <input className="cell-input" value={draft.location_name ?? ""} onChange={(e) => patch({ location_name: e.target.value })} /> : item.location_name || "—"}</td>
            <td>{active ? <input className="cell-input position-input" value={draft.position ?? ""} onChange={(e) => patch({ position: e.target.value })} /> : item.position || "—"}</td>
            <td>{active ? <select className="cell-input" value={draft.volume} onChange={(e) => patch({ volume: Number(e.target.value) })}>{[1,2,3,4,5,6].map((v) => <option key={v} value={v}>V{v}</option>)}</select> : `V${item.volume}`}</td>
            <td>{active ? <input className="cell-input page-input" type="number" min="1" value={draft.page ?? ""} onChange={(e) => patch({ page: e.target.value ? Number(e.target.value) : null })} /> : item.page ?? "—"}</td>
            <td>{active ? <input className="cell-input" value={draft.nature ?? ""} onChange={(e) => patch({ nature: e.target.value })} /> : item.nature || "—"}</td>
            <td className="notes-cell">{active ? <textarea className="cell-input" value={draft.notes ?? ""} onChange={(e) => patch({ notes: e.target.value })} /> : item.notes || "—"}</td>
            <td><RowActions editing={active} busy={busy} onEdit={() => begin(item)} onSave={() => void persist()} onCancel={() => setEditing(null)} onDelete={() => void remove(item)} /></td>
          </tr>;
        })}
        {rendered.length === 0 && <tr><td colSpan={13}><EmptyState title="Aucun butin">Modifiez les filtres ou ajoutez une entrée.</EmptyState></td></tr>}
      </tbody></table></div>
      <div className="reference-footer single-action"><span>Les objets sont classés selon leur ordre d’apparition dans la campagne.</span><button type="button" className="text-button danger-text" onClick={() => setConfirmReset(true)}><RotateCcw size={15} />Restaurer la base d’origine</button></div>
      {confirmReset && <ConfirmReset scope="loot" busy={busy} onCancel={() => setConfirmReset(false)} onConfirm={() => void restore()} />}
    </div>
  );
}
