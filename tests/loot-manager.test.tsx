import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it } from "vitest";
import { LootManager } from "../src/components/LootManager";

let root: Root;
let container: HTMLDivElement;

beforeEach(() => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

async function waitFor<T>(read: () => T | null | undefined): Promise<T> {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    const value = read();
    if (value) return value;
    await act(async () => { await new Promise((resolve) => window.setTimeout(resolve, 5)); });
  }
  throw new Error("Élément attendu introuvable.");
}

it("charge le registre, conserve un ordre de hooks stable et révèle automatiquement un butin acquis", async () => {
  await act(async () => {
    root.render(<LootManager campaignId="00000000-0000-4000-8000-000000000001" demo onNotice={() => undefined} onError={() => undefined} />);
  });

  const title = await waitFor(() => Array.from(container.querySelectorAll("h2")).find((heading) => heading.textContent === "Butins"));
  expect(title).toBeTruthy();
  expect(container.textContent).toContain("Trésors du récit");
  const pendingCard = Array.from(container.querySelectorAll<HTMLElement>(".loot-monitor-card")).find((card) => card.classList.contains("status-pending"));
  await act(async () => { pendingCard?.querySelector<HTMLButtonElement>(".loot-card-summary")?.click(); });
  const acquired = Array.from(pendingCard?.querySelectorAll<HTMLButtonElement>(".loot-quick-status button") ?? []).find((button) => button.textContent === "Acquis");
  await act(async () => { acquired?.click(); });
  expect(pendingCard?.classList.contains("status-found")).toBe(true);
  expect(pendingCard?.textContent).toContain("Partage joueursVisible");
  expect(pendingCard?.querySelector<HTMLButtonElement>('[aria-label="Masquer aux joueurs"]')).toBeTruthy();
});

it("affiche les lieux du volume et filtre les blocs correspondants", async () => {
  await act(async () => {
    root.render(<LootManager campaignId="00000000-0000-4000-8000-000000000001" demo onNotice={() => undefined} onError={() => undefined} />);
  });

  const volumeOne = await waitFor(() => Array.from(container.querySelectorAll("button")).find((button) => button.textContent === "V1"));
  await act(async () => { volumeOne.click(); });

  const locationFilter = await waitFor(() => container.querySelector<HTMLElement>(".loot-location-filter"));
  expect(locationFilter.textContent).toContain("Tous les lieux");
  expect(locationFilter.textContent).toContain("Lieu 1");
  expect(locationFilter.textContent).toContain("Lieu 2");

  const locationTwo = Array.from(locationFilter.querySelectorAll("button")).find((button) => button.textContent === "Lieu 2");
  expect(locationTwo).toBeTruthy();
  await act(async () => { locationTwo!.click(); });

  expect(container.querySelectorAll(".loot-site-group")).toHaveLength(1);
  expect(container.querySelector(".loot-site-heading")?.textContent).toContain("Lieu 2");
});
