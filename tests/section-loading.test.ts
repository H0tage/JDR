import { beforeEach, expect, it, vi } from "vitest";

const calls = vi.hoisted(() => [] as string[]);
vi.mock("../src/lib/supabase", () => ({ supabase: {
  from(name: string) {
    calls.push(name);
    const result = { data: [], error: null };
    const query = {
      select: () => query, eq: () => query, order: () => query, limit: () => query,
      single: async () => ({ data: { campaign_id: "campaign" }, error: null }),
      maybeSingle: async () => ({ data: null, error: null }),
      then: (resolve: (value: typeof result) => unknown) => Promise.resolve(result).then(resolve),
    };
    return query;
  },
  rpc: async (name: string) => { calls.push(name); return { data: [], error: null }; },
} }));
import { loadGmData, loadPlayerData } from "../src/lib/api";
beforeEach(() => { calls.length = 0; });

it("l’accueil MJ ne charge pas les notes, le bestiaire et les vingt versions du journal", async () => {
  await loadGmData("campaign", false, []);
  expect(calls).not.toContain("quest_journal_revisions");
  expect(calls).not.toContain("quest_entries");
  expect(calls).not.toContain("list_campaign_bestiary");
  expect(calls).toContain("campaign_settings");
});
it("ouvrir le journal joueur charge son contenu et son historique, pas le bestiaire", async () => {
  await loadPlayerData("campaign", false, "player", ["journal"]);
  expect(calls).toContain("quest_journal_pages");
  expect(calls).toContain("quest_journal_revisions");
  expect(calls).not.toContain("list_campaign_bestiary");
});
it("ouvrir le bestiaire charge ses entrées sans charger le journal", async () => {
  await loadPlayerData("campaign", false, "player", ["bestiary"]);
  expect(calls).toContain("list_campaign_bestiary");
  expect(calls).not.toContain("quest_journal_pages");
});

it("l’accueil joueur conserve les données de ses compteurs sans charger l’historique HTML", async () => {
  await loadPlayerData("campaign", false, "player", ["bestiary", "notes"]);
  expect(calls).toContain("list_campaign_bestiary");
  expect(calls).toContain("quest_entries");
  expect(calls).not.toContain("quest_journal_revisions");
});
