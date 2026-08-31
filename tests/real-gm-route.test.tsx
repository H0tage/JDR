import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { mockCampaignData } from "../src/data/mockData";

vi.mock("../src/lib/api", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/lib/api")>();
  return {
    ...actual,
    currentSession: vi.fn().mockResolvedValue({ user: { id: "gm-user" } }),
    loadGmData: vi.fn().mockResolvedValue(structuredClone(mockCampaignData)),
  };
});

vi.mock("../src/lib/campaignPortalApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/lib/campaignPortalApi")>();
  return {
    ...actual,
    listMyCampaigns: vi.fn().mockResolvedValue([{
      campaign_id: mockCampaignData.settings.campaign_id,
      slug: "blood-lords",
      name: "Campagne de test",
      description: null,
      role: "gm",
      joined_at: "2026-01-01T00:00:00.000Z",
      is_owner: true,
      created_at: "2026-01-01T00:00:00.000Z",
    }]),
  };
});

import { App } from "../src/App";
import { listMyCampaigns } from "../src/lib/campaignPortalApi";

let root: Root;
let container: HTMLDivElement;

beforeEach(() => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  window.history.replaceState(null, "", `/campaign/${mockCampaignData.settings.campaign_id}/mj`);
  window.localStorage.clear();
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

async function waitFor<T>(read: () => T | null | undefined): Promise<T> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const value = read();
    if (value) return value;
    await act(async () => { await new Promise((resolve) => window.setTimeout(resolve, 5)); });
  }
  throw new Error("Élément attendu introuvable.");
}

it("monte l’écran MJ sur l’URL réelle avec une session MJ", async () => {
  await act(async () => { root.render(<App />); });
  const shell = await waitFor(() => container.querySelector<HTMLElement>(".gm-shell"));
  expect(shell.textContent).toContain("Tableau de bord");
  expect(shell.querySelector("input[name='gm-theme']")).toBeTruthy();
});

it("résout aussi l’écran MJ avec le slug court de la campagne", async () => {
  window.history.replaceState(null, "", "/campaign/blood-lords/mj");
  await act(async () => { root.render(<App />); });
  const shell = await waitFor(() => container.querySelector<HTMLElement>(".gm-shell"));
  expect(shell.textContent).toContain("Tableau de bord");
});

it("ne confirme pas l’existence d’une campagne inaccessible", async () => {
  vi.mocked(listMyCampaigns).mockResolvedValueOnce([]);
  window.history.replaceState(null, "", "/campaign/slug-secret/playerscreen");
  await act(async () => { root.render(<App />); });
  const state = await waitFor(() => container.querySelector<HTMLElement>(".state-screen"));
  expect(state.textContent).toContain("Cette campagne est inaccessible ou n’existe pas.");
  expect(state.textContent).not.toContain("Vous n’appartenez pas");
});
