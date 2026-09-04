import { Eye, EyeOff, ImagePlus, Maximize2, Pencil, Plus, Trash2, X } from "lucide-react";
import { useEffect, useMemo, useState, type FormEvent } from "react";
import { bestiaryImageUrl, deleteBestiaryEntry, deleteBestiaryImage, saveBestiaryEntry, setBestiaryEntryVisibility, uploadBestiaryImage } from "../lib/api";
import type { BestiaryEntry } from "../lib/types";
import { SectionHeading } from "./ui";

type BestiaryTabProps = {
  campaignId: string;
  entries: BestiaryEntry[];
  demo: boolean;
  viewerRole: "gm" | "player";
  onChanged: () => Promise<void> | void;
  onNotice: (message: string) => void;
  onError: (message: string | null) => void;
};

function emptyEntry(campaignId: string): BestiaryEntry {
  return {
    id: crypto.randomUUID(),
    campaign_id: campaignId,
    name: "",
    resistances: null,
    weaknesses: null,
    notes: null,
    image_path: null,
    created_by: null,
    is_visible: true,
    revealed_at: null,
    can_edit: true,
    can_delete: false,
  };
}

function imageSource(path: string | null, preview: string | null = null) {
  return preview ?? bestiaryImageUrl(path);
}

export function BestiaryTab({ campaignId, entries, demo, viewerRole, onChanged, onNotice, onError }: BestiaryTabProps) {
  const [demoEntries, setDemoEntries] = useState(entries);
  const [editing, setEditing] = useState<BestiaryEntry | null>(null);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [lightbox, setLightbox] = useState<{ src: string; name: string } | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!demo) setDemoEntries(entries);
  }, [demo, entries]);
  useEffect(() => () => {
    if (imagePreview?.startsWith("blob:")) URL.revokeObjectURL(imagePreview);
  }, [imagePreview]);

  const displayedEntries = useMemo(() => [...(demo ? demoEntries : entries)].sort((left, right) => {
    if (left.is_visible !== right.is_visible) return left.is_visible ? -1 : 1;
    const leftDate = left.is_visible ? left.revealed_at ?? left.created_at : left.created_at;
    const rightDate = right.is_visible ? right.revealed_at ?? right.created_at : right.created_at;
    return String(leftDate ?? "").localeCompare(String(rightDate ?? "")) || left.name.localeCompare(right.name, "fr");
  }), [demo, demoEntries, entries]);

  function beginEdit(entry: BestiaryEntry | null) {
    setEditing(entry ? structuredClone(entry) : emptyEntry(campaignId));
    setImageFile(null);
    setImagePreview(null);
    onError(null);
  }

  function closeEditor() {
    setEditing(null);
    setImageFile(null);
    setImagePreview(null);
  }

  function chooseImage(file: File | null) {
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      onError("Choisissez un fichier image.");
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      onError("L’image ne doit pas dépasser 5 Mo.");
      return;
    }
    if (imagePreview?.startsWith("blob:")) URL.revokeObjectURL(imagePreview);
    setImageFile(file);
    setImagePreview(URL.createObjectURL(file));
    onError(null);
  }

  async function save(event: FormEvent) {
    event.preventDefault();
    if (!editing || !editing.name.trim()) return;
    const original = displayedEntries.find((item) => item.id === editing.id);
    setBusy(true);
    onError(null);
    try {
      let imagePath = editing.image_path;
      if (imageFile) imagePath = demo ? imagePreview : await uploadBestiaryImage(campaignId, imageFile);
      const isNew = !original;
      const initialVisibility = viewerRole === "player";
      const saved: BestiaryEntry = {
        ...editing,
        name: editing.name.trim(),
        image_path: imagePath,
        created_by: editing.created_by ?? "demo-viewer",
        is_visible: isNew ? initialVisibility : editing.is_visible,
        revealed_at: isNew && initialVisibility ? new Date().toISOString() : editing.revealed_at,
        created_at: editing.created_at ?? new Date().toISOString(),
        can_edit: true,
        can_delete: viewerRole === "gm",
      };

      if (demo) {
        setDemoEntries((current) => {
          const exists = current.some((item) => item.id === saved.id);
          return exists ? current.map((item) => item.id === saved.id ? saved : item) : [...current, saved];
        });
      } else {
        await saveBestiaryEntry(saved);
        if (original?.image_path && original.image_path !== imagePath) await deleteBestiaryImage(original.image_path);
        await onChanged();
      }
      onNotice(original ? "Entrée du bestiaire enregistrée." : "Entrée ajoutée au bestiaire.");
      closeEditor();
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : "Enregistrement du bestiaire impossible.");
    } finally {
      setBusy(false);
    }
  }

  async function remove(entry: BestiaryEntry) {
    if (!window.confirm(`Supprimer définitivement « ${entry.name} » du bestiaire ?`)) return;
    setBusy(true);
    onError(null);
    try {
      if (demo) setDemoEntries((current) => current.filter((item) => item.id !== entry.id));
      else {
        await deleteBestiaryEntry(entry);
        await onChanged();
      }
      onNotice("Entrée supprimée du bestiaire.");
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : "Suppression du bestiaire impossible.");
    } finally {
      setBusy(false);
    }
  }

  async function toggleVisibility(entry: BestiaryEntry) {
    const nextVisible = !entry.is_visible;
    setBusy(true);
    onError(null);
    try {
      if (demo) {
        setDemoEntries((current) => current.map((item) => item.id === entry.id ? {
          ...item,
          is_visible: nextVisible,
          revealed_at: nextVisible ? new Date().toISOString() : item.revealed_at,
        } : item));
      } else {
        await setBestiaryEntryVisibility(entry.id, nextVisible);
        await onChanged();
      }
      onNotice(nextVisible ? `« ${entry.name} » est maintenant visible par les joueurs.` : `« ${entry.name} » est maintenant masquée aux joueurs.`);
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : "Changement de visibilité impossible.");
    } finally {
      setBusy(false);
    }
  }

  return <div className="page-stack bestiary-page">
    <SectionHeading eyebrow="Registre collaboratif" title="Bestiaire" />
    <p className="section-intro">Consignez les créatures rencontrées, leurs défenses et tout détail utile au groupe.</p>
    <section className="bestiary-grid">
      {displayedEntries.map((entry) => {
        const src = imageSource(entry.image_path);
        const canEdit = viewerRole === "gm" || entry.can_edit;
        const canDelete = viewerRole === "gm" && (demo || entry.can_delete !== false);
        return <article key={entry.id} className={`bestiary-card${entry.is_visible ? "" : " is-hidden"}`}>
          {viewerRole === "gm" && <button type="button" className="icon-button bestiary-visibility-toggle" disabled={busy} title={entry.is_visible ? "Masquer aux joueurs" : "Rendre visible aux joueurs"} aria-label={entry.is_visible ? `Masquer ${entry.name}` : `Révéler ${entry.name}`} onClick={() => void toggleVisibility(entry)}>{entry.is_visible ? <Eye size={17} /> : <EyeOff size={17} />}</button>}
          {src ? <button type="button" className="bestiary-image" onClick={() => setLightbox({ src, name: entry.name })} title={`Agrandir l’image de ${entry.name}`}><img src={src} alt={entry.name} /><span><Maximize2 size={16} />Agrandir</span></button> : <div className="bestiary-image placeholder"><ImagePlus size={28} /><span>Aucune image</span></div>}
          <div className="bestiary-card-body"><div className="bestiary-card-title"><h3>{entry.name}</h3><div>{canEdit && <button type="button" className="icon-button" disabled={busy} title="Modifier" aria-label={`Modifier ${entry.name}`} onClick={() => beginEdit(entry)}><Pencil size={15} /></button>}{canDelete && <button type="button" className="icon-button danger" disabled={busy} title="Supprimer" aria-label={`Supprimer ${entry.name}`} onClick={() => void remove(entry)}><Trash2 size={15} /></button>}</div></div>
            <BestiaryDetail label="Résistances" value={entry.resistances} />
            <BestiaryDetail label="Faiblesses" value={entry.weaknesses} />
            {entry.notes && <BestiaryDetail label="Notes" value={entry.notes} />}
          </div>
        </article>;
      })}
      <button type="button" className="bestiary-add-card" onClick={() => beginEdit(null)}><span><Plus size={34} /></span><strong>Ajouter une créature</strong><small>{viewerRole === "gm" ? "Elle sera masquée aux joueurs par défaut." : "Elle sera immédiatement visible par le groupe."}</small></button>
    </section>

    {editing && <div className="modal-backdrop" role="presentation"><form className="modal-card bestiary-editor" onSubmit={save}>
      <div className="modal-head"><div><p className="eyebrow">Entrée du bestiaire</p><h3>{displayedEntries.some((item) => item.id === editing.id) ? "Modifier la créature" : "Ajouter une créature"}</h3></div><button type="button" className="icon-button" onClick={closeEditor} aria-label="Fermer"><X /></button></div>
      <div className="bestiary-editor-grid"><label className="span-2">Nom de la créature<input required value={editing.name} onChange={(event) => setEditing({ ...editing, name: event.target.value })} placeholder="Ex. Zombie de la peste" /></label>
        <div className="bestiary-upload"><span>Image</span><div className="bestiary-upload-preview">{imageSource(editing.image_path, imagePreview) ? <img src={imageSource(editing.image_path, imagePreview)!} alt="Aperçu de l’image" /> : <ImagePlus size={28} />}</div><label className="button secondary tiny upload-control"><input type="file" accept="image/jpeg,image/png,image/webp,image/gif" onChange={(event) => chooseImage(event.target.files?.[0] ?? null)} />Choisir une image</label>{editing.image_path && !imageFile && <button type="button" className="text-button danger-text" onClick={() => setEditing({ ...editing, image_path: null })}>Retirer l’image</button>}<small>JPEG, PNG, WebP ou GIF · 5 Mo maximum.</small></div>
        <div className="bestiary-fields"><label>Résistances<textarea value={editing.resistances ?? ""} onChange={(event) => setEditing({ ...editing, resistances: event.target.value || null })} placeholder="Ex. feu 5, physique 5 (sauf argent)" /></label><label>Faiblesses<textarea value={editing.weaknesses ?? ""} onChange={(event) => setEditing({ ...editing, weaknesses: event.target.value || null })} placeholder="Ex. feu 5, positif 5" /></label></div>
        <label className="span-2">Notes supplémentaires<textarea value={editing.notes ?? ""} onChange={(event) => setEditing({ ...editing, notes: event.target.value || null })} placeholder="Attaques observées, comportement, provenance, tactiques…" /></label>
      </div>
      <div className="modal-actions"><button type="button" className="button secondary" disabled={busy} onClick={closeEditor}>Annuler</button><button className="button primary" disabled={busy}>{busy ? "Enregistrement…" : "Enregistrer"}</button></div>
    </form></div>}

    {lightbox && <div className="modal-backdrop bestiary-lightbox" role="presentation" onClick={() => setLightbox(null)}><section className="bestiary-lightbox-card" role="dialog" aria-modal="true" aria-label={`Image de ${lightbox.name}`} onClick={(event) => event.stopPropagation()}><header><strong>{lightbox.name}</strong><button type="button" className="icon-button" onClick={() => setLightbox(null)} aria-label="Fermer l’image"><X /></button></header><img src={lightbox.src} alt={lightbox.name} /></section></div>}
  </div>;
}

function BestiaryDetail({ label, value }: { label: string; value: string | null }) {
  if (!value) return null;
  return <div className="bestiary-detail"><span>{label}</span><p>{value}</p></div>;
}
