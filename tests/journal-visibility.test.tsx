import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it } from "vitest";
import { GmApp } from "../src/components/GmApp";

let root: Root;
let container: HTMLDivElement;

beforeEach(() => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  window.history.replaceState(null, "", "/MJsecretscreen/?demo=1");
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

function buttonContaining(text: string) {
  return Array.from(container.querySelectorAll("button")).find((button) => button.textContent?.includes(text)) ?? null;
}

it("propose seulement les deux boutons MJ et Public dans le journal", async () => {
  await act(async () => { root.render(<GmApp />); });
  act(() => buttonContaining("Journal")!.click());

  const rowToggle = await waitFor(() => container.querySelector<HTMLDivElement>(".journal-table .visibility-toggle"));
  const rowButtons = Array.from(rowToggle.querySelectorAll("button"));
  expect(rowButtons.map((button) => button.textContent)).toEqual(["MJ", "Public"]);
  expect(container.querySelector(".journal-table .visibility-select")).toBeNull();

  await act(async () => { rowButtons[0].click(); await new Promise((resolve) => window.setTimeout(resolve, 0)); });
  expect(rowButtons[0].getAttribute("aria-pressed")).toBe("true");

  act(() => buttonContaining("Ajouter")!.click());
  const modalToggle = await waitFor(() => container.querySelector<HTMLDivElement>(".modal-card .visibility-toggle"));
  expect(Array.from(modalToggle.querySelectorAll("button")).map((button) => button.textContent)).toEqual(["MJ", "Public"]);
});
