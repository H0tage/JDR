import { expect, it } from "vitest";
import catalog from "../src/lib/equipmentCatalog.snapshot.json";
import { matchesWeaponRange } from "../src/lib/equipmentCatalog";

it("les 209 armes possèdent une classification et les 18 armes combinées passent les deux filtres", () => {
  const weapons = catalog.filter(item => item.equipment_kind === "weapon");
  expect(weapons).toHaveLength(209);
  expect(weapons.every(item => ["melee", "ranged", "both"].includes(item.weapon_range_type!))).toBe(true);
  const combined = weapons.filter(item => item.weapon_range_type === "both");
  expect(combined).toHaveLength(18);
  for (const item of combined) {
    expect(matchesWeaponRange(item, "melee"), item.name_en).toBe(true);
    expect(matchesWeaponRange(item, "ranged"), item.name_en).toBe(true);
  }
});

it("un poignard de mêlée avec Thrown n’est pas confondu avec une arme combinée ou un arc", () => {
  const dagger = catalog.find(item => item.name_en === "Dagger")!;
  const bow = catalog.find(item => item.name_en === "Longbow")!;
  expect(matchesWeaponRange(dagger, "melee")).toBe(true);
  expect(matchesWeaponRange(dagger, "ranged")).toBe(false);
  expect(matchesWeaponRange(bow, "ranged")).toBe(true);
  expect(matchesWeaponRange(bow, "melee")).toBe(false);
  expect(matchesWeaponRange(dagger, "")).toBe(true);
});
