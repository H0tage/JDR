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

it("charge le registre puis conserve un ordre de hooks stable", async () => {
  await act(async () => {
    root.render(<LootManager campaignId="00000000-0000-4000-8000-000000000001" demo onNotice={() => undefined} onError={() => undefined} />);
  });

  const title = await waitFor(() => Array.from(container.querySelectorAll("h2")).find((heading) => heading.textContent === "Butins"));
  expect(title).toBeTruthy();
  expect(container.textContent).toContain("Trésors du récit");
});
