import { Check, CircleHelp, ClipboardList, GripVertical, Lightbulb, Pencil, Plus, Trash2, X } from "lucide-react";
import { Fragment, useEffect, useMemo, useRef, useState, type CSSProperties, type DragEvent, type FormEvent } from "react";
import { deleteQuestEntry, saveQuestEntry } from "../lib/api";
import type { JournalEntry, QuestCategory, QuestEntry, QuestStatus } from "../lib/types";
import { SectionHeading } from "./ui";

type Props = {
  campaignId: string;
  entries: QuestEntry[];
  factionHistory: JournalEntry[];
  showFactionHistory?: boolean;
  demo: boolean;
  onChanged: () => Promise<void> | void;
  onNotice: (message: string) => void;
  onError: (message: string | null) => void;
};

const columns: Array<{ category: QuestCategory; label: string; description: string; icon: typeof Lightbulb }> = [
  { category: "Pistes", label: "Pistes", description: "Rumeurs, lieux, noms et éléments à vérifier.", icon: Lightbulb },
  { category: "Objectifs", label: "Objectifs", description: "Ce que le groupe souhaite entreprendre.", icon: ClipboardList },
  { category: "Questions", label: "Questions", description: "Mystères, doutes et affaires non résolues.", icon: CircleHelp },
  { category: "Informations", label: "Informations", description: "Faits établis à conserver en mémoire.", icon: Check },
];

const statuses: QuestStatus[] = ["Actif", "Résolu", "Abandonné"];
type DropTarget = { category: QuestCategory; index: number };
type DragLayoutItem = { id: string; top: number; height: number };

function blank(campaignId: string, order: number, category: QuestCategory): QuestEntry {
  return { id: crypto.randomUUID(), campaign_id: campaignId, title: "", notes: null, status: "Actif", category, sort_order: order };
}

function statusClass(status: QuestStatus) { return status.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("fr"); }

export function QuestJournalTab({ campaignId, entries, factionHistory, showFactionHistory = true, demo, onChanged, onNotice, onError }: Props) {
  const [demoEntries, setDemoEntries] = useState(entries);
  const [editing, setEditing] = useState<QuestEntry | null>(null);
  const [draggedId, setDraggedId] = useState<string | null>(null);
  const [dropTarget, setDropTarget] = useState<DropTarget | null>(null);
  const [dragPreviewHeight, setDragPreviewHeight] = useState(0);
  const draggedEntryRef = useRef<QuestEntry | null>(null);
  const dropTargetRef = useRef<DropTarget | null>(null);
  const dragPreviewHeightRef = useRef(0);
  const dragLayoutRef = useRef(new Map<QuestCategory, DragLayoutItem[]>());
  const [showHistory, setShowHistory] = useState(false);
  const visibleEntries = demo ? demoEntries : entries;

  useEffect(() => { if (!demo) setDemoEntries(entries); }, [demo, entries]);

  function nextOrder(category: QuestCategory) { return Math.max(-1, ...visibleEntries.filter((entry) => entry.category === category).map((entry) => entry.sort_order)) + 1; }
  function begin(category: QuestCategory, entry?: QuestEntry) { setEditing(entry ? structuredClone(entry) : blank(campaignId, nextOrder(category), category)); onError(null); }

  async function save(event: FormEvent) {
    event.preventDefault();
    if (!editing || !editing.title.trim()) return;
    const saved = { ...editing, title: editing.title.trim(), notes: editing.notes?.trim() || null };
    try {
      if (demo) setDemoEntries((current) => {
        const exists = current.some((item) => item.id === saved.id);
        return (exists ? current.map((item) => item.id === saved.id ? saved : item) : [...current, saved]).sort((a, b) => a.sort_order - b.sort_order);
      });
      else { await saveQuestEntry(saved); await onChanged(); }
      onNotice("Post-it enregistré.");
      setEditing(null);
    } catch (caught) { onError(caught instanceof Error ? caught.message : "Carnet de notes impossible à enregistrer."); }
  }

  async function remove(entry: QuestEntry) {
    if (!window.confirm(`Supprimer définitivement « ${entry.title} » ?`)) return;
    try {
      if (demo) setDemoEntries((current) => current.filter((item) => item.id !== entry.id));
      else { await deleteQuestEntry(entry.id); await onChanged(); }
      if (editing?.id === entry.id) setEditing(null);
      onNotice("Post-it supprimé.");
    } catch (caught) { onError(caught instanceof Error ? caught.message : "Suppression impossible."); }
  }

  function reorderedEntries(entry: QuestEntry, target: DropTarget) {
    const withoutDragged = visibleEntries.filter((item) => item.id !== entry.id);
    const reordered = new Map<string, QuestEntry>();
    for (const { category } of columns) {
      const items = withoutDragged.filter((item) => item.category === category).sort((a, b) => a.sort_order - b.sort_order);
      if (category === target.category) items.splice(Math.min(target.index, items.length), 0, { ...entry, category });
      items.forEach((item, sort_order) => reordered.set(item.id, { ...item, sort_order }));
    }
    return visibleEntries.map((item) => reordered.get(item.id) ?? item);
  }

  async function move(entry: QuestEntry, target: DropTarget) {
    const nextEntries = reorderedEntries(entry, target);
    const changed = nextEntries.filter((item) => {
      const previous = visibleEntries.find((current) => current.id === item.id);
      return previous && (previous.category !== item.category || previous.sort_order !== item.sort_order);
    });
    if (changed.length === 0) return;
    try {
      if (demo) setDemoEntries(nextEntries);
      else { for (const item of changed) await saveQuestEntry(item); await onChanged(); }
      onNotice(`Post-it déplacé vers « ${target.category} ».`);
    } catch (caught) { onError(caught instanceof Error ? caught.message : "Déplacement impossible."); }
  }

  function startDrag(event: DragEvent<HTMLElement>, entry: QuestEntry) {
    if (event.dataTransfer) {
      // Firefox requires data in the drag store before it will begin a native drag.
      event.dataTransfer.setData("text/plain", entry.id);
      event.dataTransfer.effectAllowed = "move";
    }
    draggedEntryRef.current = entry;
    dragPreviewHeightRef.current = Math.max(68, Math.ceil(event.currentTarget.getBoundingClientRect().height));
    const board = event.currentTarget.closest(".quest-postit-board");
    const layout = new Map<QuestCategory, DragLayoutItem[]>();
    columns.forEach(({ category }) => layout.set(category, []));
    board?.querySelectorAll<HTMLElement>(".quest-postit[data-postit-id]").forEach((card) => {
      const category = card.dataset.postitCategory as QuestCategory | undefined;
      const id = card.dataset.postitId;
      if (!category || !id || !layout.has(category)) return;
      const bounds = card.getBoundingClientRect();
      layout.get(category)?.push({ id, top: bounds.top, height: bounds.height });
    });
    layout.forEach((items) => items.sort((first, second) => first.top - second.top));
    dragLayoutRef.current = layout;

    // Do not re-render while the browser is creating its native drag image.
    // A re-render at this precise point cancels the drag in some Chromium builds.
  }

  function targetAt(event: DragEvent<HTMLElement>, category: QuestCategory): DropTarget {
    const draggedId = draggedEntryRef.current?.id;
    const cards = (dragLayoutRef.current.get(category) ?? []).filter((card) => card.id !== draggedId);
    if (cards.length === 0) return { category, index: 0 };

    // A large upper zone makes dropping before the first card easy. The stored
    // geometry does not change when the preview marker appears, preventing jitter.
    const beforeIndex = cards.findIndex((card) => event.clientY < card.top + Math.max(24, Math.min(card.height * 0.7, card.height - 10)));
    return { category, index: beforeIndex === -1 ? cards.length : beforeIndex };
  }

  function previewDrop(event: DragEvent<HTMLElement>, target: DropTarget) {
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
    const entry = draggedEntryRef.current;
    if (!entry) return;
    dropTargetRef.current = target;
    setDraggedId(entry.id);
    setDragPreviewHeight(dragPreviewHeightRef.current);
    setDropTarget((current) => current?.category === target.category && current.index === target.index ? current : target);
  }

  function previewColumn(event: DragEvent<HTMLElement>, category: QuestCategory) {
    previewDrop(event, targetAt(event, category));
  }

  function clearDrag() {
    draggedEntryRef.current = null;
    dropTargetRef.current = null;
    dragPreviewHeightRef.current = 0;
    dragLayoutRef.current = new Map();
    setDraggedId(null);
    setDropTarget(null);
    setDragPreviewHeight(0);
  }

  function drop() {
    const entry = draggedEntryRef.current;
    const target = dropTargetRef.current;
    if (entry && target) void move(entry, target);
    clearDrag();
  }

  const grouped = useMemo(() => new Map(columns.map(({ category }) => [category, visibleEntries.filter((entry) => entry.category === category).sort((a, b) => a.sort_order - b.sort_order)])), [visibleEntries]);
  const isNew = Boolean(editing && !visibleEntries.some((entry) => entry.id === editing.id));

  return <div className="page-stack quest-journal-page">
    <SectionHeading eyebrow="Registre collaboratif" title="Carnet de notes" />
    <p className="section-intro">Fonctionne comme un tableau blanc, rempli de post-it. Vous permet de structurer vos idées et objectifs.</p>
    <section className="quest-board quest-postit-board">
      {columns.map(({ category, label, description, icon: Icon }) => {
        const groupEntries = grouped.get(category) ?? [];
        const previewEntries = groupEntries;
        const sourceIndex = previewEntries.findIndex((entry) => entry.id === draggedId);
        const insertionMarker = (index: number) => {
          if (!draggedId || dropTarget?.category !== category) return null;
          const displayIndex = category === draggedEntryRef.current?.category && sourceIndex !== -1 && dropTarget.index > sourceIndex ? dropTarget.index + 1 : dropTarget.index;
          return displayIndex === index ? <DropPreview key={`drop-${category}-${index}`} height={dragPreviewHeight} /> : null;
        };
        return <section key={category} className={`quest-column quest-column-${category.toLocaleLowerCase("fr")}${dropTarget?.category === category ? " drag-target" : ""}`} onDragOver={(event) => previewColumn(event, category)} onDrop={(event) => { event.preventDefault(); drop(); }}>
          <header><span><Icon size={16} /></span><div><h3>{label}</h3><p>{description}</p></div><small>{groupEntries.length}</small></header>
          <div className="quest-postit-list">
            {previewEntries.map((entry, index) => <Fragment key={entry.id}>{insertionMarker(index)}{editing?.id === entry.id ? <PostitEditor entry={editing} onChange={setEditing} onSave={save} onCancel={() => setEditing(null)} /> : <PostitCard entry={entry} isDragging={entry.id === draggedId} onEdit={() => begin(category, entry)} onDelete={() => void remove(entry)} onDragStart={(event) => startDrag(event, entry)} onDragEnd={clearDrag} />}</Fragment>)}
            {insertionMarker(previewEntries.length)}
            {isNew && editing?.category === category && <PostitEditor entry={editing} onChange={setEditing} onSave={save} onCancel={() => setEditing(null)} />}
            {groupEntries.length === 0 && !draggedId && !(isNew && editing?.category === category) && <p className="quest-empty">Déposez un post-it ici.</p>}
            <button type="button" className="quest-add-postit" onClick={() => begin(category)}><Plus size={15} />Ajouter un post-it</button>
          </div>
        </section>;
      })}
    </section>
    <p className="quest-board-hint"><GripVertical size={15} /> Faites glisser un post-it vers une autre colonne pour le reclasser.</p>
    {showFactionHistory && factionHistory.length > 0 && <section className="quest-history panel"><button type="button" onClick={() => setShowHistory((value) => !value)}><div><p className="eyebrow">Repère automatique</p><h3>Événements de factions</h3></div><span>{showHistory ? "Masquer" : "Afficher"}</span></button>{showHistory && <div className="public-timeline">{factionHistory.map((entry) => <article key={entry.id}><time>{new Date(`${entry.occurred_on}T00:00:00`).toLocaleDateString("fr-CH", { day: "numeric", month: "long", year: "numeric" })}</time><div><span>{entry.faction_name}</span><h3>{entry.title}</h3>{entry.details && <p>{entry.details}</p>}</div></article>)}</div>}</section>}
  </div>;
}

function DropPreview({ height }: { height: number }) {
  return <div className="quest-postit-drop-preview" style={{ "--drop-preview-height": `${height || 88}px` } as CSSProperties}><span>Déposer ici</span></div>;
}

function PostitCard({ entry, isDragging, onEdit, onDelete, onDragStart, onDragEnd }: { entry: QuestEntry; isDragging: boolean; onEdit: () => void; onDelete: () => void; onDragStart: (event: DragEvent<HTMLElement>) => void; onDragEnd: () => void }) {
  return <article className={`quest-postit status-${statusClass(entry.status)}${isDragging ? " is-dragging" : ""}`} data-postit-id={entry.id} data-postit-category={entry.category} draggable onDragStart={onDragStart} onDragEnd={onDragEnd}>
    <div className="quest-postit-content"><div className="quest-postit-meta"><span>{entry.status}</span><GripVertical size={14} /></div><h4>{entry.title}</h4>{entry.notes && <p>{entry.notes}</p>}</div>
    <span className="quest-actions"><button className="icon-button" aria-label={`Modifier ${entry.title}`} onClick={onEdit}><Pencil size={14} /></button><button className="icon-button danger" aria-label={`Supprimer ${entry.title}`} onClick={onDelete}><Trash2 size={14} /></button></span>
  </article>;
}

function PostitEditor({ entry, onChange, onSave, onCancel }: { entry: QuestEntry; onChange: (entry: QuestEntry) => void; onSave: (event: FormEvent) => void; onCancel: () => void }) {
  return <form className="quest-postit quest-postit-editor" onSubmit={onSave}>
    <input autoFocus required value={entry.title} onChange={(event) => onChange({ ...entry, title: event.target.value })} placeholder="Titre du post-it" />
    <textarea value={entry.notes ?? ""} onChange={(event) => onChange({ ...entry, notes: event.target.value || null })} placeholder="Décrivez une piste, une idée ou une information…" />
    <div><label>État<select value={entry.status} onChange={(event) => onChange({ ...entry, status: event.target.value as QuestStatus })}>{statuses.map((status) => <option key={status}>{status}</option>)}</select></label><span><button type="button" className="icon-button" aria-label="Annuler" onClick={onCancel}><X size={15} /></button><button className="button primary tiny">Enregistrer</button></span></div>
  </form>;
}
