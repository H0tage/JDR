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
