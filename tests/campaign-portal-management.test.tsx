import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { CampaignPortal } from "../src/components/CampaignPortal";
import { createCampaign, deleteOwnedCampaign, updateOwnedCampaign } from "../src/lib/campaignPortalApi";

vi.mock("../src/lib/api", () => ({
  currentSession: vi.fn().mockResolvedValue({ user: { id: "owner" } }),
  signInWithPassword: vi.fn(),
  signOut: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("../src/lib/supabase", () => ({
  hasSupabaseConfig: true,
  supabase: { auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: vi.fn() } } }) } },
}));

vi.mock("../src/lib/profileApi", () => ({
  getMyProfile: vi.fn().mockResolvedValue({ user_id: "owner", display_name: "Maître Test" }),
  updateMyProfile: vi.fn(),
}));

vi.mock("../src/lib/campaignPortalApi", () => ({
  listMyCampaigns: vi.fn().mockResolvedValue([
    { campaign_id: "owned", slug: "vampire-bonegolem", name: "Campagne possédée", description: null, role: "gm", joined_at: "2026-01-01", is_owner: true, created_at: "2026-08-30T12:00:00Z" },
    { campaign_id: "shared", slug: "ghost-zombie", name: "Campagne partagée", description: null, role: "gm", joined_at: "2026-01-01", is_owner: false, created_at: "2026-08-29T12:00:00Z" },
    { campaign_id: "played", slug: "wight-wraith", name: "Campagne jouée", description: null, role: "player", joined_at: "2026-01-01", is_owner: false, created_at: "2026-08-28T12:00:00Z" },
  ]),
  listCampaignMembers: vi.fn().mockImplementation((campaignId: string) => Promise.resolve(campaignId === "owned" ? [
    { user_id: "owner", display_name: "Maître Test", role: "gm", joined_at: "2026-08-30" },
    { user_id: "player", display_name: "Joueuse Test", role: "player", joined_at: "2026-08-30" },
  ] : [])),
  createCampaign: vi.fn().mockResolvedValue({ campaign_id: "new", slug: "liche-goule", name: "Nouvelle campagne", description: null }),
  updateOwnedCampaign: vi.fn().mockResolvedValue({ campaign_id: "owned", slug: "vampire-bonegolem", name: "Nouveau nom", description: "Nouvelle description", created_at: "2026-08-30T12:00:00Z" }),
  deleteOwnedCampaign: vi.fn().mockResolvedValue("vampire-bonegolem"),
  leaveCampaign: vi.fn(),
  signUp: vi.fn(),
  sendPasswordRecovery: vi.fn(),
  updatePassword: vi.fn(),
  invitationDetails: vi.fn(),
  acceptInvitation: vi.fn(),
}));

let root: Root;
let container: HTMLDivElement;

beforeEach(() => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  vi.mocked(createCampaign).mockClear();
  vi.mocked(deleteOwnedCampaign).mockClear();
  vi.mocked(updateOwnedCampaign).mockClear();
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

function buttonContaining(text: string) {
  return [...container.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent?.includes(text));
}

function enterText(element: HTMLInputElement | HTMLTextAreaElement, value: string) {
  const prototype = element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(prototype, "value")?.set?.call(element, value);
  element.dispatchEvent(new Event("input", { bubbles: true }));
}

it("crée une campagne et réserve la suppression définitive au propriétaire", async () => {
  await act(async () => { root.render(<CampaignPortal />); });
  await waitFor(() => buttonContaining("Créer une campagne"));

  expect(container.textContent).toContain("Vous êtes propriétaire");
  expect(container.textContent).toContain("Joueuse Test");
  expect(container.textContent).toContain("30 août 2026");
  expect([...container.querySelectorAll(".campaign-delete-link")]).toHaveLength(1);
  expect([...container.querySelectorAll(".campaign-card")].find((card) => card.textContent?.includes("Campagne partagée"))?.textContent).not.toContain("Supprimer");

  const ownedCardBeforeEdit = [...container.querySelectorAll<HTMLElement>(".campaign-card")].find((card) => card.textContent?.includes("Campagne possédée"))!;
  act(() => [...ownedCardBeforeEdit.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent?.includes("Modifier"))?.click());
  const editModal = await waitFor(() => container.querySelector<HTMLElement>(".campaign-edit-modal"));
  const editFields = editModal.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>("input, textarea");
  act(() => { enterText(editFields[0], "Nouveau nom"); enterText(editFields[1], "Nouvelle description"); });
  await act(async () => { editModal.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true })); await Promise.resolve(); });
  expect(updateOwnedCampaign).toHaveBeenCalledWith("owned", "Nouveau nom", "Nouvelle description");

  act(() => buttonContaining("Créer une campagne")?.click());
  const createPanel = await waitFor(() => container.querySelector<HTMLElement>(".campaign-create-panel"));
  vi.mocked(createCampaign).mockImplementationOnce(() => new Promise(() => undefined));
  act(() => {
    enterText(createPanel.querySelector<HTMLInputElement>("input")!, "Nouvelle campagne");
    enterText(createPanel.querySelector<HTMLTextAreaElement>("textarea")!, "Description de test");
  });
  await act(async () => { createPanel.querySelector("form")?.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true })); await Promise.resolve(); });
  expect(createCampaign).toHaveBeenCalledWith("Nouvelle campagne", "Description de test");

  const ownedCard = [...container.querySelectorAll<HTMLElement>(".campaign-card")].find((card) => card.textContent?.includes("Nouveau nom"))!;
  act(() => [...ownedCard.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent?.includes("Supprimer"))?.click());
  const modal = await waitFor(() => container.querySelector<HTMLElement>(".campaign-delete-modal"));
  const confirmButton = [...modal.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent?.includes("Supprimer définitivement"))!;
  expect(confirmButton.disabled).toBe(true);
  act(() => enterText(modal.querySelector<HTMLInputElement>("input")!, "Nouveau nom"));
  expect(confirmButton.disabled).toBe(false);
  await act(async () => { confirmButton.click(); await Promise.resolve(); });
  expect(deleteOwnedCampaign).toHaveBeenCalledWith("owned");
});
