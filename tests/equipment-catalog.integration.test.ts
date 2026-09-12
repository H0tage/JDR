import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

it("importe 338 consommables sans doublon, préserve les armes et distingue prix absent et prix composé", async () => {
  const db = new PGlite();
  try {
    await db.exec("create role authenticated");
    await db.exec(readFileSync("supabase/migrations/20260905120000_pf2e_equipment_references.sql", "utf8"));
    const migration = readFileSync("supabase/migrations/20260912010000_pf2e_consumable_references.sql", "utf8");
    await db.exec(migration);
    const before = (await db.query("select * from public.pf2e_equipment_references order by id")).rows;
    expect(before).toHaveLength(563);
    await db.exec(migration);
    expect((await db.query("select * from public.pf2e_equipment_references order by id")).rows).toEqual(before);
    expect((await db.query("select item_type, count(*)::int count from public.pf2e_equipment_references where equipment_kind = 'consumable' group by item_type order by count")).rows).toEqual([
      { item_type: "Huile", count: 57 }, { item_type: "Potion", count: 96 }, { item_type: "Élixir", count: 185 },
    ]);
    expect((await db.query("select price_cp::int price, level, rarity from public.pf2e_equipment_references where name_en = 'Lesser Elixir of the Peaks'")).rows).toEqual([{ price: 150, level: 4, rarity: "Rare" }]);
    expect((await db.query("select name_en from public.pf2e_equipment_references where equipment_kind = 'consumable' and price_cp is null order by name_en")).rows).toEqual([{ name_en: "Elixir of Rejuvenation" }, { name_en: "Sun Orchid Elixir" }]);
    expect((await db.query("select price_cp::int price from public.pf2e_equipment_references where name_en = 'Healing Potion (Minor)'")).rows).toEqual([{ price: 400 }]);
    expect((await db.query("select price_cp::int price, equipment_kind from public.pf2e_equipment_references where name_en = 'Dagger'")).rows).toEqual([{ price: 20, equipment_kind: "weapon" }]);
    const details = readFileSync("supabase/migrations/20260912020000_equipment_source_details.sql", "utf8");
    await db.exec(details);
    const enriched = (await db.query<{ id: string; source_data: Record<string, string> | null }>("select * from public.pf2e_equipment_references order by id")).rows;
    expect(enriched.map(row => row.id)).toEqual(before.map(row => row.id));
    expect(enriched.filter(row => row.source_data)).toHaveLength(225);
    for (const row of enriched.filter(row => row.source_data)) expect(Object.keys(row.source_data!)).toHaveLength(30);
    expect((await db.query("select weapon_range_type, damage, traits_label, source_data->>'Mains' hands from public.pf2e_equipment_references where name_en = 'Dagger'")).rows).toEqual([{ weapon_range_type: "melee", damage: "1d4 P", traits_label: "Agile, finesse, thrown 10 ft., versatile S", hands: "1" }]);
    expect((await db.query("select weapon_range_type from public.pf2e_equipment_references where name_en = 'Longbow'")).rows).toEqual([{ weapon_range_type: "ranged" }]);
    expect((await db.query("select armor_class_bonus from public.pf2e_equipment_references where name_en = 'Tower shield'")).rows).toEqual([{ armor_class_bonus: "+2 / +4 avec Take Cover" }]);
    await db.exec(details);
    expect((await db.query("select * from public.pf2e_equipment_references order by id")).rows).toEqual(enriched);
    const verifiedMigration = readFileSync("supabase/migrations/20260912030000_verified_aon_prices.sql", "utf8");
    await db.exec(verifiedMigration);
    const verifiedRows = (await db.query<{ id: string }>("select * from public.pf2e_equipment_references order by id")).rows;
    expect(verifiedRows.map(row => row.id)).toEqual(before.map(row => row.id));
    await db.exec(verifiedMigration);
    expect((await db.query("select * from public.pf2e_equipment_references order by id")).rows).toEqual(verifiedRows);
    expect((await db.query("select name_en, price_cp::int price from public.pf2e_equipment_references where name_en in ('Energy Mutagen (Lesser)', 'Merciful Balm', 'Oil of Potency (Greater)', 'Bottled Catharsis (Moderate)') order by name_en")).rows).toEqual([
      { name_en: "Bottled Catharsis (Moderate)", price: 7500 },
      { name_en: "Energy Mutagen (Lesser)", price: 40 },
      { name_en: "Merciful Balm", price: 500 },
      { name_en: "Oil of Potency (Greater)", price: 40000 },
    ]);
    expect((await db.query("select count(*)::int count from public.pf2e_equipment_references where price_cp is null")).rows).toEqual([{ count: 3 }]);
    expect((await db.query("select count(*)::int count from public.pf2e_equipment_references where aon_url like '%Category=%'")).rows).toEqual([{ count: 0 }]);
    const weaponMigration = readFileSync("supabase/migrations/20260912040000_weapon_characteristics.sql", "utf8");
    const pricesBefore = (await db.query("select id, price_cp from public.pf2e_equipment_references order by id")).rows;
    await db.exec(weaponMigration);
    const weaponRows = (await db.query("select * from public.pf2e_equipment_references order by id")).rows;
    await db.exec(weaponMigration);
    expect((await db.query("select * from public.pf2e_equipment_references order by id")).rows).toEqual(weaponRows);
    expect((await db.query("select id, price_cp from public.pf2e_equipment_references order by id")).rows).toEqual(pricesBefore);
    expect((await db.query("select count(*)::int count from public.pf2e_equipment_references where equipment_kind = 'weapon' and weapon_range_type is null")).rows).toEqual([{ count: 0 }]);
    expect((await db.query("select count(*)::int count from public.pf2e_equipment_references where weapon_range_type = 'both'")).rows).toEqual([{ count: 18 }]);
    expect((await db.query("select jsonb_array_length(weapon_details_verification->'modes') modes from public.pf2e_equipment_references where name_en = 'Triggerbrand'")).rows).toEqual([{ modes: 2 }]);
    const snapshot = JSON.parse(readFileSync("src/lib/equipmentCatalog.snapshot.json", "utf8")) as { name_en: string; price_cp: number | null; weapon_range_type: string | null }[];
    expect(snapshot).toHaveLength(563);
    const stored = (await db.query<{ name_en: string; price_cp: number | null; weapon_range_type: string | null }>("select name_en, price_cp::int price_cp, weapon_range_type from public.pf2e_equipment_references")).rows;
    for (const item of snapshot) expect(stored.find(row => row.name_en === item.name_en), item.name_en).toEqual({ name_en: item.name_en, price_cp: item.price_cp, weapon_range_type: item.weapon_range_type });
  } finally { await db.close(); }
}, 30000);
