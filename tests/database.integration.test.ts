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

  await db.exec(`select set_config('request.jwt.claim.sub', '${first}', false); set role authenticated;`);
  const cancelledRequest = (await db.query<{ request_campaign_item: string }>(`select public.request_campaign_item('${item}')`)).rows[0].request_campaign_item;
  await db.exec(`select public.cancel_campaign_item_request('${cancelledRequest}')`);
  const repeatedRequest = (await db.query<{ request_campaign_item: string }>(`select public.request_campaign_item('${item}')`)).rows[0].request_campaign_item;
  expect(repeatedRequest).not.toBe(cancelledRequest);
  await db.exec('reset role;');
  expect((await db.query<{ pending: number; cancelled: number }>(`select count(*) filter (where status = 'pending')::int pending, count(*) filter (where status = 'cancelled')::int cancelled from public.campaign_item_requests where item_id = '${item}' and requester_user_id = '${first}'`)).rows[0]).toEqual({ pending: 1, cancelled: 1 });

  await db.exec(`select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated;`);
  const potions = (await db.query<{ create_manual_campaign_item: string }>(`select public.create_manual_campaign_item('${campaign.campaign_id}', 'Potion test', 3, 400, '${first}', null, null, null, false)`)).rows[0].create_manual_campaign_item;
  await db.exec(`select set_config('request.jwt.claim.sub', '${first}', false); set role authenticated; select public.assign_campaign_item('${potions}', '${second}', null, 2); reset role;`);
  const potionTransfer = (await db.query<{ id: string; item_id: string }>(`select id, item_id from public.campaign_item_events where campaign_id = '${campaign.campaign_id}' and event_type = 'transferred' and related_item_id = '${potions}' order by created_at desc limit 1`)).rows[0];
  expect((await db.query<{ quantity: number; owner_user_id: string }>(`select quantity::int quantity, owner_user_id from public.campaign_inventory_items where id = '${potionTransfer.item_id}'`)).rows[0]).toEqual({ quantity: 2, owner_user_id: second });
  await db.exec(`select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated; select public.cancel_campaign_item_event('${potionTransfer.id}', 'Mauvaise quantité'); reset role;`);
  expect((await db.query<{ quantity: number; owner_user_id: string }>(`select quantity::int quantity, owner_user_id from public.campaign_inventory_items where id = '${potions}'`)).rows[0]).toEqual({ quantity: 3, owner_user_id: first });
  expect((await db.query<{ status: string }>(`select status from public.campaign_inventory_items where id = '${potionTransfer.item_id}'`)).rows[0].status).toBe('merged');

  await db.exec(`select set_config('request.jwt.claim.sub', '${first}', false); set role authenticated; select public.assign_campaign_item('${potions}', '${second}', null, 1); reset role;`);
  const changedTransfer = (await db.query<{ id: string; item_id: string }>(`select id, item_id from public.campaign_item_events where campaign_id = '${campaign.campaign_id}' and event_type = 'transferred' and related_item_id = '${potions}' and reversed_event_id is null order by created_at desc limit 1`)).rows[0];
  await db.exec(`select set_config('request.jwt.claim.sub', '${second}', false); set role authenticated; select public.set_campaign_item_terminal('${changedTransfer.item_id}', 'consumed', null, null);`);
  await expect(db.exec(`select set_config('request.jwt.claim.sub', '${gm}', false); select public.cancel_campaign_item_event('${changedTransfer.id}', 'Trop tard');`)).rejects.toThrow(/objet a été modifié depuis cette action/);

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
  const reversibleIncome = (await db.query<{ record_personal_money: string }>(`select public.record_personal_money('${campaign.campaign_id}', 'income', 2000, null, 'Revenu annulable')`)).rows[0].record_personal_money;
  expect((await db.query<{ total_entered_cp: number; total_exited_cp: number }>(`select total_entered_cp::int, total_exited_cp::int from public.player_economy_totals where campaign_id = '${campaign.campaign_id}'`)).rows[0]).toEqual({ total_entered_cp: 6400, total_exited_cp: 0 });
  await db.exec(`select public.cancel_campaign_money_transaction('${reversibleIncome}', 'Erreur de saisie')`);
  expect((await db.query<{ total_entered_cp: number; total_exited_cp: number }>(`select total_entered_cp::int, total_exited_cp::int from public.player_economy_totals where campaign_id = '${campaign.campaign_id}'`)).rows[0]).toEqual({ total_entered_cp: 4400, total_exited_cp: 0 });
  expect((await db.query<{ actor_display_name: string }>(`select actor_display_name from public.player_item_history where item_id = '${item}' and event_type = 'created'`)).rows[0].actor_display_name).toBe('Le Maître du Jeu');

  const wealthBefore = (await db.query<{ current_wealth_cp: number }>(`select current_wealth_cp::int from public.player_economy_totals where campaign_id = '${campaign.campaign_id}'`)).rows[0].current_wealth_cp;
  await db.exec(`select public.transfer_campaign_money('${campaign.campaign_id}', '${first}', null, 123, 'Transfert interne')`);
  const wealthAfter = (await db.query<{ current_wealth_cp: number }>(`select current_wealth_cp::int from public.player_economy_totals where campaign_id = '${campaign.campaign_id}'`)).rows[0].current_wealth_cp;
  expect(wealthAfter).toBe(wealthBefore);

  const purchased = (await db.query<{ purchase_campaign_item: string }>(`select public.purchase_campaign_item('${campaign.campaign_id}', 'Dague dupliquée', 2, 1000, 1000, 0, null, 9999, null, null, null)`)).rows[0].purchase_campaign_item;
  await db.exec('reset role;');
  expect((await db.query<{ unit_value_cp: number; purchase_price_cp: number }>(`select unit_value_cp::int, purchase_price_cp::int from public.campaign_inventory_items where id = '${purchased}'`)).rows[0]).toEqual({ unit_value_cp: 500, purchase_price_cp: 1000 });

  await db.exec(`select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated;`);
  await db.exec(`select public.create_manual_campaign_item('${campaign.campaign_id}', 'Même nom', 1, 10, null, null, null, null); select public.create_manual_campaign_item('${campaign.campaign_id}', 'Même nom', 1, 20, null, null, null, null);`);
  await db.exec('reset role;');
  expect((await db.query<{ count: number }>(`select count(*)::int count from public.campaign_inventory_items where campaign_id = '${campaign.campaign_id}' and name = 'Même nom'`)).rows[0].count).toBe(2);

  await db.close();
}, 30_000);

it("calcule séparément les gains, les dépenses cash et le patrimoine", async () => {
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
  const gm = '25000000-0000-4000-8000-000000000001';
  const player = '25000000-0000-4000-8000-000000000002';
  await db.exec(`insert into auth.users values ('${gm}', 'economy-gm@example.test'), ('${player}', 'economy-player@example.test'); select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated;`);
  const campaign = (await db.query<{ campaign_id: string }>("select * from public.create_campaign('Sémantique économique', null)")).rows[0];
  await db.exec(`reset role; insert into public.campaign_members (campaign_id, user_id, role) values ('${campaign.campaign_id}', '${player}', 'player'); insert into public.user_profiles (user_id, display_name) values ('${player}', 'Joueur économie'); select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated;`);

  const totals = async () => (await db.query<{ gains: number; expenses: number; wealth: number }>(`
    select total_entered_cp::int gains, total_exited_cp::int expenses, current_wealth_cp::int wealth
    from public.player_economy_totals where campaign_id = '${campaign.campaign_id}'
  `)).rows[0];

  const cashIncome = (await db.query<{ record_common_income: string }>(`select public.record_common_income('${campaign.campaign_id}', 10000, 'Argent trouvé')`)).rows[0].record_common_income;
  expect(await totals()).toEqual({ gains: 10000, expenses: 0, wealth: 10000 });

  const foundItem = (await db.query<{ create_manual_campaign_item: string }>(`select public.create_manual_campaign_item('${campaign.campaign_id}', 'Objet trouvé', 1, 30000, null, null, null, null, true)`)).rows[0].create_manual_campaign_item;
  expect(await totals()).toEqual({ gains: 40000, expenses: 0, wealth: 40000 });

  const correctionItem = (await db.query<{ create_manual_campaign_item: string }>(`select public.create_manual_campaign_item('${campaign.campaign_id}', 'Correction sans gain', 1, 1000, null, null, null, null, false)`)).rows[0].create_manual_campaign_item;
  expect(await totals()).toEqual({ gains: 40000, expenses: 0, wealth: 41000 });

  await db.exec(`select set_config('request.jwt.claim.sub', '${player}', false); set role authenticated;`);
  const purchased = (await db.query<{ purchase_campaign_item: string }>(`select public.purchase_campaign_item('${campaign.campaign_id}', 'Objet acheté', 1, 20000, 20000, 0, null, null, null, null, null)`)).rows[0].purchase_campaign_item;
  expect(await totals()).toEqual({ gains: 40000, expenses: 20000, wealth: 41000 });

  await db.exec(`select public.record_personal_money('${campaign.campaign_id}', 'expense', 2000, null, 'Auberge')`);
  expect(await totals()).toEqual({ gains: 40000, expenses: 22000, wealth: 39000 });

  await db.exec(`select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated; select public.set_campaign_item_terminal('${foundItem}', 'consumed', null, null);`);
  expect(await totals()).toEqual({ gains: 40000, expenses: 22000, wealth: 9000 });
  await db.exec(`select public.set_campaign_item_terminal('${correctionItem}', 'lost', null, null); select public.set_campaign_item_terminal('${purchased}', 'donated', null, null);`);
  expect(await totals()).toEqual({ gains: 40000, expenses: 22000, wealth: -12000 });

  const saleAtCost = (await db.query<{ create_manual_campaign_item: string }>(`select public.create_manual_campaign_item('${campaign.campaign_id}', 'Vente neutre', 1, 20000, null, null, null, null, false)`)).rows[0].create_manual_campaign_item;
  await db.exec(`select public.sell_campaign_item('${saleAtCost}', 1, 20000, null)`);
  expect(await totals()).toEqual({ gains: 40000, expenses: 22000, wealth: 8000 });

  const profitableItem = (await db.query<{ create_manual_campaign_item: string }>(`select public.create_manual_campaign_item('${campaign.campaign_id}', 'Vente bénéficiaire', 1, 20000, null, null, null, null, false)`)).rows[0].create_manual_campaign_item;
  const profitableSale = (await db.query<{ sell_campaign_item: string }>(`select public.sell_campaign_item('${profitableItem}', 1, 30000, null)`)).rows[0].sell_campaign_item;
  expect(await totals()).toEqual({ gains: 50000, expenses: 22000, wealth: 38000 });

  const discountedItem = (await db.query<{ create_manual_campaign_item: string }>(`select public.create_manual_campaign_item('${campaign.campaign_id}', 'Vente à perte', 1, 20000, null, null, null, null, false)`)).rows[0].create_manual_campaign_item;
  await db.exec(`select public.sell_campaign_item('${discountedItem}', 1, 15000, null)`);
  expect(await totals()).toEqual({ gains: 50000, expenses: 22000, wealth: 53000 });

  await db.exec(`select public.transfer_campaign_money('${campaign.campaign_id}', null, '${player}', 500, null)`);
  expect(await totals()).toEqual({ gains: 50000, expenses: 22000, wealth: 53000 });

  await db.exec(`select public.cancel_campaign_item_event('${profitableSale}', 'Vente annulée')`);
  expect(await totals()).toEqual({ gains: 40000, expenses: 22000, wealth: 43000 });
  await db.exec(`select public.cancel_campaign_money_transaction('${cashIncome}', 'Entrée annulée')`);
  expect(await totals()).toEqual({ gains: 30000, expenses: 22000, wealth: 33000 });

  const freeItem = (await db.query<{ create_manual_campaign_item: string }>(`select public.create_manual_campaign_item('${campaign.campaign_id}', 'Objet sans valeur', 1, null, null, null, null, null, false)`)).rows[0].create_manual_campaign_item;
  await db.exec(`select public.sell_campaign_item('${freeItem}', 1, 10000, null)`);
  expect(await totals()).toEqual({ gains: 40000, expenses: 22000, wealth: 43000 });

  await db.exec(`select set_config('request.jwt.claim.sub', '${player}', false); set role authenticated;`);
  const tinyBundle = (await db.query<{ purchase_campaign_item: string }>(`select public.purchase_campaign_item('${campaign.campaign_id}', 'Lot minimal', 3, 1, 1, 0, null, null, null, null, null)`)).rows[0].purchase_campaign_item;
  await db.exec('reset role;');
  expect((await db.query<{ unit_value_cp: number }>(`select unit_value_cp::int from public.campaign_inventory_items where id = '${tinyBundle}'`)).rows[0].unit_value_cp).toBe(1);
  await db.exec(`select set_config('request.jwt.claim.sub', '${player}', false); set role authenticated;`);
  expect(await totals()).toEqual({ gains: 40000, expenses: 22001, wealth: 43002 });
  await db.close();
}, 30_000);

it("partage les fiches publiques sans exposer Pathbuilder ni les notes privées", async () => {
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
  const gm = '30000000-0000-4000-8000-000000000001';
  const first = '30000000-0000-4000-8000-000000000002';
  const second = '30000000-0000-4000-8000-000000000003';
  await db.exec(`insert into auth.users values ('${gm}', 'gm3@example.test'), ('${first}', 'alpha@example.test'), ('${second}', 'beta@example.test'); select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated;`);
  const campaign = (await db.query<{ campaign_id: string }>("select * from public.create_campaign('Fiches de test', null)")).rows[0];
  await db.exec(`reset role;
    insert into public.campaign_members (campaign_id, user_id, role) values ('${campaign.campaign_id}', '${first}', 'player'), ('${campaign.campaign_id}', '${second}', 'player');
    insert into public.user_profiles (user_id, display_name) values ('${first}', 'Alpha'), ('${second}', 'Bêta');
    insert into public.player_pages (campaign_id, user_id, character_name, character_summary, pathbuilder_url, notes, objectives) values
      ('${campaign.campaign_id}', '${first}', 'Aster', 'Présentation A', 'https://pathbuilder2e.com/app.html', 'Secret A', 'Objectif A'),
      ('${campaign.campaign_id}', '${second}', 'Boreal', 'Présentation B', 'https://pathbuilder2e.com/app.html', 'Secret B', 'Objectif B');
    select set_config('request.jwt.claim.sub', '${first}', false); set role authenticated;`);
  const playerPages = (await db.query<{ user_id: string; is_own: boolean; pathbuilder_url: string | null; notes: string | null }>(`select user_id, is_own, pathbuilder_url, notes from public.list_campaign_player_pages('${campaign.campaign_id}') order by user_id`)).rows;
  expect(playerPages).toHaveLength(2);
  expect(playerPages.find((page) => page.user_id === first)).toMatchObject({ is_own: true, pathbuilder_url: 'https://pathbuilder2e.com/app.html', notes: 'Secret A' });
  expect(playerPages.find((page) => page.user_id === second)).toMatchObject({ is_own: false, pathbuilder_url: null, notes: null });
  await db.exec(`select public.update_my_player_relationship_note('${campaign.campaign_id}', '${second}', 'Note strictement privée')`);
  expect((await db.query<{ notes: string }>(`select notes from public.list_my_player_relationship_notes('${campaign.campaign_id}')`)).rows[0].notes).toBe('Note strictement privée');

  await db.exec(`reset role; select set_config('request.jwt.claim.sub', '${second}', false); set role authenticated;`);
  expect((await db.query(`select * from public.list_my_player_relationship_notes('${campaign.campaign_id}')`)).rows).toHaveLength(0);
  await db.exec(`reset role; delete from public.campaign_members where campaign_id = '${campaign.campaign_id}' and user_id = '${second}'; select set_config('request.jwt.claim.sub', '${first}', false); set role authenticated;`);
  expect((await db.query(`select * from public.list_campaign_player_pages('${campaign.campaign_id}')`)).rows).toHaveLength(1);

  await db.exec(`reset role; select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated;`);
  const gmPages = (await db.query<{ user_id: string; active: boolean; notes: string | null }>(`select user_id, active, notes from public.list_campaign_player_pages('${campaign.campaign_id}') order by user_id`)).rows;
  expect(gmPages).toHaveLength(2);
  expect(gmPages.find((page) => page.user_id === second)).toMatchObject({ active: false, notes: 'Secret B' });
  await db.close();
}, 30_000);

it("limite les participants et sécurise le cycle collaboratif du bestiaire", async () => {
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
  const gm = '40000000-0000-4000-8000-000000000001';
  const first = '40000000-0000-4000-8000-000000000002';
  const second = '40000000-0000-4000-8000-000000000003';
  const invite = '40000000-0000-4000-8000-000000000010';
  const hiddenCreature = '40000000-0000-4000-8000-000000000020';
  const playerCreature = '40000000-0000-4000-8000-000000000021';
  await db.exec(`insert into auth.users values ('${gm}', 'gm4@example.test'), ('${first}', 'one@example.test'), ('${second}', 'two@example.test'); select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated;`);
  const campaign = (await db.query<{ campaign_id: string }>("select * from public.create_campaign('Capacité et bestiaire', null)")).rows[0];
  await db.exec(`select public.update_campaign_capacity('${campaign.campaign_id}', 2); reset role; insert into public.campaign_invites (id, campaign_id, token, created_by) values ('${invite}', '${campaign.campaign_id}', '${invite}', '${gm}'); select set_config('request.jwt.claim.sub', '${first}', false); set role authenticated; select * from public.accept_campaign_invitation('${invite}');`);
  await expect(db.exec(`reset role; select set_config('request.jwt.claim.sub', '${second}', false); set role authenticated; select * from public.accept_campaign_invitation('${invite}');`)).rejects.toThrow(/campagne que vous cherchez à rejoindre est pleine/);
  await db.exec(`reset role; select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated;`);
  await expect(db.exec(`select public.update_campaign_capacity('${campaign.campaign_id}', 1)`)).rejects.toThrow(/inférieure au nombre actuel/);
  expect((await db.query<{ max_participants: number; current_participants: number }>(`select * from public.get_campaign_capacity('${campaign.campaign_id}')`)).rows[0]).toEqual({ max_participants: 2, current_participants: 2 });

  await db.exec(`select public.save_bestiary_entry('${hiddenCreature}', '${campaign.campaign_id}', 'Liche cachée', null, null, 'Secret MJ', null);`);
  expect((await db.query(`select * from public.list_campaign_bestiary('${campaign.campaign_id}')`)).rows).toHaveLength(1);
  await db.exec(`reset role; select set_config('request.jwt.claim.sub', '${first}', false); set role authenticated;`);
  expect((await db.query(`select * from public.list_campaign_bestiary('${campaign.campaign_id}')`)).rows).toHaveLength(0);
  await expect(db.exec(`select public.save_bestiary_entry('${hiddenCreature}', '${campaign.campaign_id}', 'Nom volé', null, null, null, null)`)).rejects.toThrow(/propres créatures/);
  await db.exec(`select public.save_bestiary_entry('${playerCreature}', '${campaign.campaign_id}', 'Zombie aperçu', null, 'Feu', null, null); select public.save_bestiary_entry('${playerCreature}', '${campaign.campaign_id}', 'Zombie reconnu', null, 'Feu', null, null);`);
  await expect(db.exec(`select public.delete_bestiary_entry('${playerCreature}')`)).rejects.toThrow(/Accès refusé/);
  expect((await db.query<{ name: string; is_visible: boolean }>(`select name, is_visible from public.list_campaign_bestiary('${campaign.campaign_id}')`)).rows).toEqual([{ name: 'Zombie reconnu', is_visible: true }]);

  await db.exec(`reset role; select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated; select public.set_bestiary_entry_visibility('${hiddenCreature}', true);`);
  const visibleNames = (await db.query<{ name: string }>(`select name from public.list_campaign_bestiary('${campaign.campaign_id}')`)).rows.map((row) => row.name);
  expect(visibleNames).toEqual(['Zombie reconnu', 'Liche cachée']);
  await db.exec(`select public.set_bestiary_entry_visibility('${hiddenCreature}', false); select public.set_bestiary_entry_visibility('${hiddenCreature}', true);`);
  expect((await db.query<{ event_type: string }>(`select event_type from public.gm_bestiary_history where campaign_id = '${campaign.campaign_id}' and entry_id = '${hiddenCreature}' order by created_at`)).rows.map((row) => row.event_type)).toEqual(['created', 'revealed', 'hidden', 'revealed']);

  await db.exec(`reset role; delete from auth.users where id = '${first}'; select set_config('request.jwt.claim.sub', '${gm}', false); set role authenticated;`);
  expect((await db.query<{ created_by: string | null }>(`select created_by from public.bestiary_entries where id = '${playerCreature}'`)).rows[0].created_by).toBeNull();
  expect((await db.query<{ actor_display_name: string }>(`select actor_display_name from public.gm_bestiary_history where entry_id = '${playerCreature}' and event_type = 'created'`)).rows[0].actor_display_name).toBe('Joueur parti');
  await db.close();
}, 30_000);
