import { supabase } from "./supabase";

export type EquipmentReference = {
  id: string; name_en: string; equipment_kind: string; price_cp: number | null;
  aon_url: string; item_type: string | null; weapon_range_type: string | null;
  category: string | null; level: number | null; rarity: string | null;
};

export function matchesWeaponRange(item: Pick<EquipmentReference, "weapon_range_type">, filter: string): boolean {
  return !filter || item.weapon_range_type === filter || (item.weapon_range_type === "both" && (filter === "melee" || filter === "ranged"));
}

export async function loadEquipmentCatalog(): Promise<{ items: EquipmentReference[]; offline: boolean }> {
  if (supabase) {
    try {
      const { data, error } = await supabase.from("pf2e_equipment_references")
        .select("id,name_en,equipment_kind,price_cp,aon_url,item_type,weapon_range_type,category,level,rarity")
        .order("name_en").limit(1000);
      if (!error && data?.length) return { items: data, offline: false };
    } catch { /* The versioned catalogue remains available if the network is unavailable. */ }
  }
  const { default: items } = await import("./equipmentCatalog.snapshot.json");
  return { items, offline: true };
}
