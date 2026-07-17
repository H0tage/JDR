import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { expect, it } from "vitest";

const migrationFiles = [
  "20260717120000_initial_schema.sql",
  "20260717121000_seed_blood_lords.sql",
  "20260717122000_seed_dossiers.sql",
  "20260717130000_update_faction_names.sql",
  "20260717131000_relation_text_overrides.sql",
];

it("installe les migrations, les données et la frontière MJ/joueurs", async () => {
  const db = new PGlite();
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema auth;
    create table auth.users (id uuid primary key, email text unique);
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;
    create schema extensions;
  `);

  for (const file of migrationFiles) {
    let sql = readFileSync(resolve(process.cwd(), "supabase/migrations", file), "utf8");
    sql = sql.replace(
      "create extension if not exists pgcrypto with schema extensions;",
      "-- pgcrypto est déjà fourni dans le projet Supabase",
    );
    await db.exec(sql);
  }

  const counts = (await db.query<{
    campaigns: number;
    factions: number;
    services: number;
    relationships: number;
    dossiers: number;
    milestones: number;
  }>(`
    select
      (select count(*)::int from public.campaigns) campaigns,
      (select count(*)::int from public.factions) factions,
      (select count(*)::int from public.services) services,
      (select count(*)::int from public.faction_relationships) relationships,
      (select count(*)::int from public.bilateral_dossiers) dossiers,
      (select count(*)::int from public.reputation_milestones) milestones
  `)).rows[0];
  expect(counts).toEqual({ campaigns: 1, factions: 6, services: 18, relationships: 30, dossiers: 15, milestones: 5 });

  const factionNames = (await db.query<{ name: string; short_name: string }>(`
    select name, short_name from public.factions order by sort_order
  `)).rows;
  expect(factionNames).toEqual([
    { name: "Ligue des Bâtisseurs", short_name: "Bâtisseurs" },
    { name: "Célébrants", short_name: "Célébrants" },
    { name: "Guilde des Exportateurs", short_name: "Exportateurs" },
    { name: "Réanimateurs", short_name: "Réanimateurs" },
    { name: "Syndicats des Percepteurs d’Impôts", short_name: "Percepteurs" },
    { name: "Consortium des Convoyeurs", short_name: "Convoyeurs" },
  ]);

  const relationshipId = "00000000-0000-4000-8300-000000000001";
  const defaultRelationship = (await db.query<{
    headline: string;
    detail: string;
    default_headline: string;
    default_detail: string;
    headline_override: string | null;
    detail_override: string | null;
  }>(`select headline, detail, default_headline, default_detail, headline_override, detail_override
      from public.gm_relationships where id = '${relationshipId}'`)).rows[0];
  expect(defaultRelationship).toMatchObject({
    headline: "Défiance informationnelle",
    default_headline: "Défiance informationnelle",
    headline_override: null,
    detail_override: null,
  });

  await db.exec(`
    update public.faction_relationships
    set headline_override = 'Rivalité des secrets',
        detail_override = 'La version propre à cette campagne.',
        visibility = 'players'
    where id = '${relationshipId}';
  `);
  const customizedRelationship = (await db.query<{ headline: string; detail: string; default_headline: string }>(`
    select headline, detail, default_headline from public.gm_relationships where id = '${relationshipId}'
  `)).rows[0];
  expect(customizedRelationship).toEqual({
    headline: "Rivalité des secrets",
    detail: "La version propre à cette campagne.",
    default_headline: "Défiance informationnelle",
  });

  const reanimators = (await db.query<{ rp: number; jf: number; tension: number; status: string }>(`
    select rp, jf, tension, status from public.gm_faction_overview where slug = 'réanimateurs'
  `)).rows[0];
  expect(reanimators).toEqual({ rp: 5, jf: 5, tension: 0, status: "Appréciés" });

  const gmUserId = "10000000-0000-4000-8000-000000000001";
  await db.exec(`
    insert into auth.users (id, email) values ('${gmUserId}', 'mj@example.test');
    insert into public.campaign_members (campaign_id, user_id)
    values ('00000000-0000-4000-8000-000000000001', '${gmUserId}');
    select set_config('request.jwt.claim.sub', '${gmUserId}', false);
    set role anon;
  `);
  await expect(db.query("select * from public.journal_entries")).rejects.toThrow(/permission denied/i);
  await expect(db.query(`update public.faction_relationships set headline_override = 'Intrusion' where id = '${relationshipId}'`)).rejects.toThrow(/permission denied/i);
  expect((await db.query<{ count: number }>("select count(*)::int as count from public.player_faction_overview")).rows[0].count).toBe(6);
  expect((await db.query<{ tension: number | null }>("select tension from public.player_faction_overview where slug = 'réanimateurs'")).rows[0].tension).toBeNull();
  expect((await db.query<{ headline: string; detail: string }>(`select headline, detail from public.player_relationships where id = '${relationshipId}'`)).rows[0]).toEqual({
    headline: "Rivalité des secrets",
    detail: "La version propre à cette campagne.",
  });

  await db.exec("reset role; set role authenticated;");
  expect((await db.query<{ count: number }>("select count(*)::int as count from public.gm_faction_overview")).rows[0].count).toBe(6);

  await db.exec(`
    reset role;
    select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000099', false);
    set role authenticated;
  `);
  expect((await db.query<{ count: number }>("select count(*)::int as count from public.campaigns")).rows[0].count).toBe(0);

  await db.exec("reset role;");
  await db.close();
}, 30_000);
