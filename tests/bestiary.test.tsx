import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { BestiaryTab } from "../src/components/BestiaryTab";
import type { BestiaryEntry } from "../src/lib/types";

let root: Root;
let container: HTMLDivElement;

const visibleEntry: BestiaryEntry = {
  id: "10000000-0000-4000-8000-000000000001",
  campaign_id: "10000000-0000-4000-8000-000000000010",
  name: "Zombie connu",
  resistances: null,
  weaknesses: "Feu",
  notes: null,
  image_path: null,
  created_by: "10000000-0000-4000-8000-000000000002",
  is_visible: true,
  revealed_at: "2026-01-01T12:00:00Z",
  created_at: "2026-01-01T10:00:00Z",
  can_edit: true,
  can_delete: false,
};

beforeEach(() => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
});

it("permet au joueur d’ajouter et modifier sans afficher suppression ni visibilité", async () => {
  await act(async () => root.render(<BestiaryTab campaignId={visibleEntry.campaign_id} entries={[visibleEntry]} demo viewerRole="player" onChanged={() => undefined} onNotice={() => undefined} onError={() => undefined} />));
  expect(container.querySelector('[aria-label="Masquer Zombie connu"]')).toBeNull();
  expect(container.querySelector('[aria-label="Supprimer Zombie connu"]')).toBeNull();
  expect(container.querySelector('[aria-label="Modifier Zombie connu"]')).toBeTruthy();
  const add = container.querySelector<HTMLButtonElement>(".bestiary-add-card");
  expect(add?.textContent).toContain("immédiatement visible");
  await act(async () => add?.click());
  const input = container.querySelector<HTMLInputElement>('.bestiary-editor input[required]');
  await act(async () => {
    if (input) {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set?.call(input, "Goule ajoutée");
      input.dispatchEvent(new Event("input", { bubbles: true }));
    }
  });
  await act(async () => container.querySelector<HTMLFormElement>(".bestiary-editor")?.requestSubmit());
  expect([...container.querySelectorAll(".bestiary-card h3")].map((node) => node.textContent)).toContain("Goule ajoutée");
});

it("donne au MJ le contrôle de visibilité et de suppression", async () => {
  const hiddenEntry = { ...visibleEntry, is_visible: false, revealed_at: null, can_delete: true };
  await act(async () => root.render(<BestiaryTab campaignId={visibleEntry.campaign_id} entries={[hiddenEntry]} demo viewerRole="gm" onChanged={() => undefined} onNotice={() => undefined} onError={() => undefined} />));
  expect(container.querySelector(".bestiary-card")?.classList.contains("is-hidden")).toBe(true);
  const reveal = container.querySelector<HTMLButtonElement>('[aria-label="Révéler Zombie connu"]');
  expect(reveal).toBeTruthy();
  expect(container.querySelector('[aria-label="Supprimer Zombie connu"]')).toBeTruthy();
  await act(async () => reveal?.click());
  expect(container.querySelector(".bestiary-card")?.classList.contains("is-hidden")).toBe(false);
  expect(container.querySelector('[aria-label="Masquer Zombie connu"]')).toBeTruthy();
});
