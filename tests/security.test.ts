import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  resolve(process.cwd(), "supabase/migrations/20260717120000_initial_schema.sql"),
  "utf8",
);

function viewBody(name: string, nextName: string) {
  const start = migration.indexOf(`create or replace view public.${name}`);
  const end = migration.indexOf(`create or replace view public.${nextName}`, start + 1);
  expect(start).toBeGreaterThan(-1);
  expect(end).toBeGreaterThan(start);
  return migration.slice(start, end);
}

describe("player data boundary", () => {
  it("does not grant anonymous users access to base tables", () => {
    expect(migration).toContain("revoke all on all tables in schema public from anon");
    expect(migration).not.toMatch(/grant\s+(?:select|all)[^;]+on\s+public\.(?:journal_entries|contacts|campaign_factions|faction_relationships)[^;]+to\s+anon/i);
  });

  it("removes GM notes and consequences from player faction rows", () => {
    const body = viewBody("player_faction_overview", "player_journal");
    expect(body).not.toContain("gm_notes");
    expect(body).not.toContain("next_consequence");
  });

  it("removes private contact fields from the public contact view", () => {
    const body = viewBody("player_contacts", "player_relationships");
    expect(body).not.toContain("gm_notes");
    expect(body).not.toContain("next_consequence");
    expect(body).toContain("where ct.visibility = 'players'");
  });

  it("filters every revealable public collection", () => {
    expect(viewBody("player_journal", "player_contacts")).toContain("where j.visibility = 'players'");
    expect(viewBody("player_relationships", "player_services")).toContain("where r.visibility = 'players'");
  });

  it("does not expose internal sourcing or hidden numeric tension", () => {
    const factions = viewBody("player_faction_overview", "player_journal");
    const journal = viewBody("player_journal", "player_contacts");
    const relationships = viewBody("player_relationships", "player_services");
    expect(factions).toContain("case when s.show_numeric_tension then least(s.tension_max, t.tension_raw) else null end");
    expect(journal).toContain("case when s.show_numeric_tension then j.tension_delta else null end");
    expect(journal).not.toContain("source_reference");
    expect(relationships).not.toContain("r.evidence");
  });
});
