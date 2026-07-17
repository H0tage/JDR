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

function rowContaining(text: string) {
  return Array.from(container.querySelectorAll<HTMLTableRowElement>("tbody tr")).find((row) => row.textContent?.includes(text)) ?? null;
}

function enterText(element: HTMLTextAreaElement, value: string) {
  Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")?.set?.call(element, value);
  element.dispatchEvent(new Event("input", { bubbles: true }));
}

it("filtre par volume et classe un jalon manqué avec sa raison", async () => {
  await act(async () => { root.render(<GmApp />); });
  act(() => buttonContaining("Progression")!.click());
  await waitFor(() => rowContaining("Libérer Altinmered"));

  act(() => buttonContaining("Volume 2")!.click());
  expect(await waitFor(() => rowContaining("Remettre le carnet de Gessamon"))).toBeTruthy();
  expect(rowContaining("Libérer Altinmered")).toBeNull();

  act(() => buttonContaining("Volume 1")!.click());
  const row = await waitFor(() => rowContaining("Libérer Altinmered"));
  act(() => row.querySelector<HTMLButtonElement>("button")!.click());
  act(() => buttonContaining("Manqué")!.click());
  const note = await waitFor(() => container.querySelector<HTMLTextAreaElement>(".milestone-note textarea"));
  act(() => enterText(note, "Les PJ l’ont confié à une tierce personne."));
  await act(async () => { buttonContaining("Enregistrer l’issue")!.click(); await new Promise((resolve) => window.setTimeout(resolve, 0)); });

  const updated = await waitFor(() => rowContaining("Libérer Altinmered"));
  expect(updated.textContent).toContain("Manqué");
  expect(updated.textContent).toContain("Les PJ l’ont confié à une tierce personne.");
});

it("écarte automatiquement l’autre branche d’un choix exclusif", async () => {
  await act(async () => { root.render(<GmApp />); });
  act(() => buttonContaining("Progression")!.click());
  const collectors = await waitFor(() => rowContaining("Confier la banque aux Percepteurs"));
  act(() => collectors.querySelector<HTMLButtonElement>("button")!.click());
  await act(async () => { buttonContaining("Enregistrer l’issue")!.click(); await new Promise((resolve) => window.setTimeout(resolve, 0)); });

  const builders = await waitFor(() => rowContaining("Confier la banque aux Bâtisseurs"));
  expect(builders.textContent).toContain("Écarté");
  expect(builders.textContent).toContain("Confier la banque aux Percepteurs");

  act(() => builders.querySelector<HTMLButtonElement>("button")!.click());
  expect(await waitFor(() => container.querySelector(".choice-warning"))).toBeTruthy();
  await act(async () => { buttonContaining("Enregistrer l’issue")!.click(); await new Promise((resolve) => window.setTimeout(resolve, 0)); });
  expect((await waitFor(() => rowContaining("Confier la banque aux Percepteurs"))).textContent).toContain("Écarté");
});
