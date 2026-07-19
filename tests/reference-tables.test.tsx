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
  for (let attempt = 0; attempt < 400; attempt += 1) {
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

function enterText(element: HTMLInputElement, value: string) {
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set?.call(element, value);
  element.dispatchEvent(new Event("input", { bubbles: true }));
}

it("filtre les archives, distingue une traduction personnalisée et ouvre les butins", async () => {
  await act(async () => { root.render(<GmApp />); });
  act(() => buttonContaining("Archives")!.click());
  expect((await waitFor(() => container.querySelector(".reference-count"))).textContent).toBe("233 résultats");

  act(() => buttonContaining("Lieux")!.click());
  const graydirge = await waitFor(() => rowContaining("Graydirge"));
  expect(graydirge.querySelector(".translation-site")?.textContent).toContain("Griseplainte");

  act(() => graydirge.querySelector<HTMLButtonElement>('button[aria-label="Modifier"]')!.click());
  const editRow = await waitFor(() => container.querySelector<HTMLTableRowElement>(".editing-row"));
  const translatedInput = editRow.querySelectorAll("td")[2].querySelector<HTMLInputElement>("input")!;
  act(() => enterText(translatedInput, "Ma Griseplainte"));
  await act(async () => { editRow.querySelector<HTMLButtonElement>('button[aria-label="Enregistrer"]')!.click(); await new Promise((resolve) => window.setTimeout(resolve, 0)); });
  const customized = await waitFor(() => container.querySelector<HTMLElement>(".translation-custom"));
  expect(customized.textContent).toContain("Ma Griseplainte");
  expect(customized.querySelector("svg")).not.toBeNull();

  act(() => buttonContaining("V2")!.click());
  expect((await waitFor(() => container.querySelector(".reference-count"))).textContent).toBe("23 résultats");

  act(() => buttonContaining("Butins")!.click());
  expect((await waitFor(() => container.querySelector(".reference-count"))).textContent).toBe("406 résultats");
  act(() => buttonContaining("V6")!.click());
  expect((await waitFor(() => container.querySelector(".reference-count"))).textContent).toBe("93 résultats");
});
