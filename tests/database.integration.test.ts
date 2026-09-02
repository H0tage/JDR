import { PGlite } from "@electric-sql/pglite";
import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { expect, it } from "vitest";

const migrationsDirectory = resolve(process.cwd(), "supabase/migrations");

it("installe une base vierge et peut créer une campagne sans contenu privé", async () => {
  const db = new PGlite();
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
  for (const file of readdirSync(migrationsDirectory).filter((name) => name.endsWith('.sql')).sort()) {
    const sql = readFileSync(resolve(migrationsDirectory, file), 'utf8').replace('create extension if not exists pgcrypto with schema extensions;', '-- pgcrypto supplied by Supabase');
    await db.exec(sql);
  }
  expect((await db.query<{ count: number }>('select count(*)::int count from public.campaigns')).rows[0].count).toBe(0);
  expect((await db.query<{ count: number }>('select count(*)::int count from public.campaign_slug_words')).rows[0].count).toBe(244);
  await db.exec(`insert into auth.users values ('10000000-0000-4000-8000-000000000001', 'gm@example.test'); select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', false); set role authenticated;`);
  const campaign = (await db.query<{ campaign_id: string; slug: string; name: string }>("select * from public.create_campaign('Campagne de test', null)")).rows[0];
  expect(campaign.name).toBe('Campagne de test');
  expect(campaign.slug).toMatch(/^[a-z0-9]+-[a-z0-9]+$/);
  expect((await db.query<{ settings: number; templates: number }>(`select (select count(*)::int from public.campaign_settings where campaign_id = '${campaign.campaign_id}') settings, (select count(*)::int from public.campaign_loot where campaign_id = '${campaign.campaign_id}') templates`)).rows[0]).toEqual({ settings: 1, templates: 0 });
  await db.close();
}, 30_000);

it("sécurise les objets, transfère l’argent et restitue les biens au départ d’un joueur", async () => {
  const db = new PGlite();
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
  for (const file of readdirSync(migrationsDirectory).filter((name) => name.endsWith('.sql')).sort()) {
    const sql = readFileSync(resolve(migrationsDirectory, file), 'utf8').replace('create extension if not exists pgcrypto with schema extensions;', '-- pgcrypto supplied by Supabase');
    await db.exec(sql);
  }
  const gm = '20000000-0000-4000-8000-000000000001';
  const first = '20000000-0000-4000-8000-000000000002';
  const second = '20000000-0000-4000-8000-000000000003';
  await db.exec(`insert into auth.users values ('${gm}', 'gm2@example.test'), ('${first}', 'first@example.test'), ('${second}', 'second@example.test'); select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated;`);
  const campaign = (await db.query<{ campaign_id: string }>("select * from public.create_campaign('Économie de test', null)")).rows[0];
  await db.exec(`reset role; insert into public.campaign_members (campaign_id, user_id, role) values ('${campaign.campaign_id}', '${first}', 'player'), ('${campaign.campaign_id}', '${second}', 'player'); insert into public.user_profiles (user_id, display_name) values ('${first}', 'Premier joueur'), ('${second}', 'Second joueur'); select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated;`);
  const item = (await db.query<{ create_manual_campaign_item: string }>(`select public.create_manual_campaign_item('${campaign.campaign_id}', 'Objet de test', 1, 1200, null, null, null, null)`)).rows[0].create_manual_campaign_item;

  await db.exec(`select set_config('request.jwt.claim.sub', '${first}', false); select public.assign_campaign_item('${item}', '${first}', null); select public.record_personal_money('${campaign.campaign_id}', 'income', 2500, null, 'Service rendu');`);
  await expect(db.exec(`select set_config('request.jwt.claim.sub', '${second}', false); select public.assign_campaign_item('${item}', '${second}', null);`)).rejects.toThrow(/attribuer cet objet/);
  await db.exec(`select set_config('request.jwt.claim.sub', '${second}', false);`);
  const request = (await db.query<{ request_campaign_item: string }>(`select public.request_campaign_item('${item}')`)).rows[0].request_campaign_item;
  await db.exec(`select set_config('request.jwt.claim.sub', '${first}', false); select public.resolve_campaign_item_request('${request}', true);`);
  expect((await db.query<{ count: number }>(`select count(*)::int count from public.player_money_balances where campaign_id = '${campaign.campaign_id}'`)).rows[0].count).toBe(2);
  await db.exec(`reset role; update public.campaign_settings set show_all_player_balances = true where campaign_id = '${campaign.campaign_id}'; select set_config('request.jwt.claim.sub', '${first}', false); set role authenticated;`);
  expect((await db.query<{ count: number }>(`select count(*)::int count from public.player_money_balances where campaign_id = '${campaign.campaign_id}'`)).rows[0].count).toBe(3);
  await db.exec('reset role;');
  expect((await db.query<{ owner_user_id: string }>(`select owner_user_id from public.campaign_inventory_items where id = '${item}'`)).rows[0].owner_user_id).toBe(second);

  await db.exec(`select set_config('request.jwt.claim.sub', '${second}', false); set role authenticated; select public.record_personal_money('${campaign.campaign_id}', 'income', 700, null, null); select public.create_campaign_money_debt('${campaign.campaign_id}', '${second}', '${first}', 300, 'Dette de test'); select public.leave_campaign('${campaign.campaign_id}'); reset role;`);
  expect((await db.query<{ owner_user_id: string | null }>(`select owner_user_id from public.campaign_inventory_items where id = '${item}'`)).rows[0].owner_user_id).toBeNull();
  const balances = (await db.query<{ common_balance: number; former_balance: number }>(`
    select
      coalesce(sum(case when destination_account = 'common' then amount_cp when source_account = 'common' then -amount_cp else 0 end), 0)::int common_balance,
      coalesce(sum(case when destination_user_id = '${second}' then amount_cp when source_user_id = '${second}' then -amount_cp else 0 end), 0)::int former_balance
    from public.campaign_money_transactions where campaign_id = '${campaign.campaign_id}'
  `)).rows[0];
  expect(balances).toEqual({ common_balance: 400, former_balance: 0 });
  await db.exec(`select set_config('request.jwt.claim.sub', '${first}', false); set role authenticated;`);
  expect((await db.query<{ total_entered_cp: number; total_exited_cp: number }>(`select total_entered_cp::int, total_exited_cp::int from public.player_economy_totals where campaign_id = '${campaign.campaign_id}'`)).rows[0]).toEqual({ total_entered_cp: 4400, total_exited_cp: 0 });
  await db.close();
}, 30_000);
