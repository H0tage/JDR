import { PGlite } from "@electric-sql/pglite";
import { readFileSync, readdirSync } from "node:fs";
import { beforeAll, afterAll, expect, it } from "vitest";

// Real PostgreSQL permissions and RPCs, not mocked authorization functions.
const db = new PGlite();
const gm = "30000000-0000-4000-8000-000000000001";
const alice = "30000000-0000-4000-8000-000000000002";
const bob = "30000000-0000-4000-8000-000000000003";
const outsider = "30000000-0000-4000-8000-000000000004";
let campaign: string;
let hidden: string;

async function as(user: string | null) {
  await db.exec("reset role");
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [user ?? ""]);
  await db.exec(user ? "set role authenticated" : "set role anon");
}
const pages = () => db.query<{ user_id: string; notes: string | null; pathbuilder_url: string | null }>(
  "select * from public.list_campaign_player_pages($1)", [campaign]);

beforeAll(async () => {
  await db.exec(`
    create role anon; create role authenticated; create schema auth;
    create table auth.users (id uuid primary key, email text unique);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create schema extensions; create publication supabase_realtime; create schema storage;
    create table storage.buckets (id text primary key, name text not null, public boolean not null default false, file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text not null, name text not null);
    alter table storage.objects enable row level security;
    create function storage.foldername(object_name text) returns text[] language sql stable as $$ select string_to_array(object_name, '/') $$;
  `);
  for (const file of readdirSync("supabase/migrations").filter(name => name.endsWith(".sql")).sort()) {
    await db.exec(readFileSync(`supabase/migrations/${file}`, "utf8").replace(
      "create extension if not exists pgcrypto with schema extensions;", "-- Supabase extension"));
  }
  for (const user of [gm, alice, bob, outsider]) {
    await db.query("insert into auth.users values ($1, $2)", [user, `${user}@example.test`]);
  }
  await as(gm);
  campaign = (await db.query<{ campaign_id: string }>("select * from public.create_campaign('Permissions', null)")).rows[0].campaign_id;
  await db.exec("reset role");
  for (const user of [alice, bob]) {
    await db.query("insert into public.campaign_members (campaign_id, user_id, role) values ($1, $2, 'player')", [campaign, user]);
    await db.query(`insert into public.player_pages (campaign_id, user_id, character_name, notes, pathbuilder_url)
      values ($1, $2, 'Personnage public', 'Secret personnel', 'https://pathbuilder2e.com/test')
      on conflict (campaign_id, user_id) do update set notes = excluded.notes, pathbuilder_url = excluded.pathbuilder_url`, [campaign, user]);
  }
  hidden = (await db.query<{ id: string }>("insert into public.bestiary_entries (campaign_id, name, is_visible) values ($1, 'Secret MJ', false) returning id", [campaign])).rows[0].id;
  await db.query("insert into public.bestiary_entries (campaign_id, name, is_visible) values ($1, 'Créature révélée', true)", [campaign]);
}, 30000);
afterAll(async () => { await db.close(); });

it("le joueur consulte sa fiche privée mais reçoit les fiches des autres sans notes ni lien Pathbuilder", async () => {
  await as(alice);
  const result = (await pages()).rows;
  expect(result.find(row => row.user_id === alice)).toMatchObject({ notes: "Secret personnel", pathbuilder_url: "https://pathbuilder2e.com/test" });
  expect(result.find(row => row.user_id === bob)).toMatchObject({ notes: null, pathbuilder_url: null });
});

it("le MJ peut consulter les notes personnelles mais pas le lien Pathbuilder du joueur", async () => {
  await as(gm);
  expect((await pages()).rows.find(row => row.user_id === alice)).toMatchObject({ notes: "Secret personnel", pathbuilder_url: null });
});

it("un utilisateur extérieur ne peut pas appeler les lectures de campagne protégées", async () => {
  await as(outsider);
  await expect(pages()).rejects.toThrow(/Accès refusé/);
  await expect(db.query("select * from public.list_campaign_bestiary($1)", [campaign])).rejects.toThrow(/Accès refusé/);
  expect((await db.query("select * from public.bestiary_entries where campaign_id = $1", [campaign])).rows).toEqual([]);
});

it("un visiteur anonyme ne peut pas appeler la lecture des fiches privées", async () => {
  await as(null);
  await expect(pages()).rejects.toMatchObject({ code: "42501" });
});

it("le bestiaire masque les créatures secrètes aux joueurs mais les montre au MJ", async () => {
  await as(alice);
  expect((await db.query("select name from public.bestiary_entries where campaign_id = $1", [campaign])).rows).toEqual([{ name: "Créature révélée" }]);
  await as(gm);
  expect((await db.query("select name from public.bestiary_entries where campaign_id = $1", [campaign])).rows).toHaveLength(2);
});

it("un joueur ne peut pas révéler une créature secrète ni se promouvoir MJ", async () => {
  await as(alice);
  await expect(db.query("select public.set_bestiary_entry_visibility($1, true)", [hidden])).rejects.toThrow(/Accès refusé/);
  // Both a privilege error and zero updated rows are valid PostgreSQL denials.
  try {
    expect((await db.query("update public.campaign_members set role = 'gm' where campaign_id = $1 and user_id = $2 returning user_id", [campaign, alice])).rows).toEqual([]);
  } catch (error) { expect(error).toMatchObject({ code: "42501" }); }
  await db.exec("reset role");
  expect((await db.query("select role from public.campaign_members where campaign_id = $1 and user_id = $2", [campaign, alice])).rows).toEqual([{ role: "player" }]);
});

it("l’accès direct aux fiches ne permet pas de contourner la confidentialité des RPC", async () => {
  await as(alice);
  await expect(db.query("select * from public.player_pages where user_id = $1", [bob])).rejects.toMatchObject({ code: "42501" });
  await expect(db.query("update public.player_pages set notes = 'Intrusion' where user_id = $1", [bob])).rejects.toMatchObject({ code: "42501" });
});

it("les notes de relation restent privées à leur auteur, même vis-à-vis du MJ", async () => {
  await as(alice);
  await db.query("select public.update_my_player_relationship_note($1, $2, 'Relation privée')", [campaign, bob]);
  expect((await db.query("select notes from public.list_my_player_relationship_notes($1)", [campaign])).rows).toEqual([{ notes: "Relation privée" }]);
  await as(bob);
  expect((await db.query("select * from public.list_my_player_relationship_notes($1)", [campaign])).rows).toEqual([]);
  await as(gm);
  await expect(db.query("select * from public.list_my_player_relationship_notes($1)", [campaign])).rejects.toThrow(/Accès refusé/);
  await expect(db.query("select * from public.player_relationship_notes")).rejects.toMatchObject({ code: "42501" });
});

it("être MJ d’une autre campagne ne donne aucun droit sur celle-ci", async () => {
  await as(outsider);
  await db.query("select * from public.create_campaign('Autre campagne', null)");
  await expect(pages()).rejects.toThrow(/Accès refusé/);
  await expect(db.query("select public.set_bestiary_entry_visibility($1, true)", [hidden])).rejects.toThrow(/Accès refusé/);
});

it("un joueur retiré perd l’accès sans que sa fiche personnelle soit supprimée", async () => {
  await db.exec("reset role; begin");
  try {
    await db.query("delete from public.campaign_members where campaign_id = $1 and user_id = $2", [campaign, bob]);
    await as(bob);
    await db.exec("savepoint denied_read");
    await expect(pages()).rejects.toThrow(/Accès refusé/);
    await db.exec("rollback to savepoint denied_read; reset role");
    expect((await db.query("select notes from public.player_pages where campaign_id = $1 and user_id = $2", [campaign, bob])).rows).toEqual([{ notes: "Secret personnel" }]);
  } finally { await db.exec("rollback; reset role"); }
});
