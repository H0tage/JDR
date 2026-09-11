import { useEffect, useMemo, useState } from "react";
import { loadEquipmentCatalog, type EquipmentReference } from "../lib/equipmentCatalog";
import { formatCopper } from "../lib/playerEconomyApi";

const tabs = [["manual", "Créer un objet"], ["weapon", "Choisir une arme"], ["armor", "Choisir une armure"], ["consumable", "Choisir un élixir / une potion"]] as const;
export function ShopCatalog({ onSelect }: { onSelect: (item: EquipmentReference) => void }) {
  const [tab, setTab] = useState<string>("manual");
  const [items, setItems] = useState<EquipmentReference[] | null>(null);
  const [offline, setOffline] = useState(false);
  const [error, setError] = useState(false);
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState("");
  const [selected, setSelected] = useState("");
  useEffect(() => {
    if (tab === "manual" || items) return;
    let active = true;
    loadEquipmentCatalog().then(result => { if (active) { setItems(result.items); setOffline(result.offline); } }).catch(() => { if (active) setError(true); });
    return () => { active = false; };
  }, [tab, items]);
  const categoryItems = useMemo(() => (items ?? []).filter(item => tab === "armor" ? ["armor", "shield"].includes(item.equipment_kind) : item.equipment_kind === tab), [items, tab]);
  const choices = tab === "weapon" ? [["melee", "Corps à corps"], ["ranged", "Distance"]] : tab === "consumable" ? [["Potion", "Potions"], ["Élixir", "Élixirs"], ["Huile", "Huiles"]] : [...new Set(categoryItems.map(item => item.category || (item.equipment_kind === "shield" ? "Boucliers" : "Autres")))].sort().map(value => [value, value]);
  const normalize = (value: string) => value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  const results = categoryItems.filter(item => normalize(item.name_en).includes(normalize(search)) && (!filter || (tab === "weapon" ? item.weapon_range_type : tab === "consumable" ? item.item_type : item.category || (item.equipment_kind === "shield" ? "Boucliers" : "Autres")) === filter)).sort((a, b) => a.name_en.localeCompare(b.name_en));
  return <section className="shop-catalog" aria-label="Choix de l’objet à acheter">
    <nav className="shop-tabs" aria-label="Mode d’achat">{tabs.map(([key, label]) => <button type="button" key={key} aria-pressed={tab === key} onClick={() => { setTab(key); setFilter(""); setSearch(""); }}>{label}</button>)}</nav>
    <small className="shop-availability">Disponibilité selon la scène jouée et l’accord du MJ.</small>
    {tab !== "manual" && <div className="shop-picker">
      <div className="shop-filters"><label>Rechercher par nom<input type="search" value={search} onChange={event => setSearch(event.target.value)} placeholder="Nom anglais de l’objet" /></label><label>Filtrer<select value={filter} onChange={event => setFilter(event.target.value)}><option value="">Tous</option>{choices.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label></div>
      {offline && <small>Catalogue de secours du 12 septembre 2026 — connexion au catalogue en ligne indisponible.</small>}
      {error ? <p role="alert">Catalogue indisponible. La création manuelle reste accessible.</p> : !items ? <p role="status">Chargement du catalogue…</p> : <><small aria-live="polite">{results.length} référence(s)</small><div className="shop-results">{results.map(item => <button type="button" key={item.id} aria-pressed={selected === item.id} onClick={() => { setSelected(item.id); onSelect(item); }}><span><strong>{item.name_en}</strong><small>{[item.category || item.item_type, item.level !== null ? `Niveau ${item.level}` : null, item.rarity].filter(Boolean).join(" · ")}</small></span><span>{item.price_cp === null ? "Prix à renseigner" : formatCopper(item.price_cp)}</span></button>)}{results.length === 0 && <p>Aucun objet correspondant.</p>}</div></>}
      <small>Sélectionnez une référence, puis vérifiez le formulaire ci-dessous avant de confirmer l’achat.</small>
    </div>}
  </section>;
}
