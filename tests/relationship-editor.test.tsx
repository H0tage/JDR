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

function enterText(element: HTMLInputElement | HTMLTextAreaElement, value: string) {
  const prototype = element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(prototype, "value")?.set?.call(element, value);
  element.dispatchEvent(new Event("input", { bubbles: true }));
}

it("personnalise une relation puis restaure son texte et sa couleur par défaut", async () => {
  await act(async () => { root.render(<GmApp />); });
  const politicsButton = await waitFor(() => buttonContaining("Politique"));
  act(() => politicsButton.click());

  const relationshipButton = await waitFor(() => buttonContaining("Défiance informationnelle"));
  act(() => relationshipButton.click());

  const headline = await waitFor(() => container.querySelector<HTMLInputElement>("#relationship-headline"));
  const detail = container.querySelector<HTMLTextAreaElement>("#relationship-detail")!;
  expect(headline.value).toBe("Défiance informationnelle");

  act(() => {
    enterText(headline, "Rivalité des secrets");
    enterText(detail, "La version propre à cette campagne.");
    buttonContaining("Hostile")!.click();
    buttonContaining("Visible joueurs")!.click();
  });
  await act(async () => {
    buttonContaining("Enregistrer")!.click();
    await new Promise((resolve) => window.setTimeout(resolve, 0));
  });
  const customizedButton = await waitFor(() => buttonContaining("Rivalité des secrets"));
  expect(customizedButton.closest("td")?.classList.contains("hostile")).toBe(true);

  act(() => buttonContaining("Rivalité des secrets")!.click());
  const headlineReset = await waitFor(() => container.querySelector<HTMLButtonElement>("#relationship-headline-reset"));
  const detailReset = container.querySelector<HTMLButtonElement>("#relationship-detail-reset")!;
  const colorReset = container.querySelector<HTMLButtonElement>("#relationship-color-reset")!;
  act(() => {
    headlineReset.click();
    detailReset.click();
    colorReset.click();
  });
  expect(container.querySelector<HTMLInputElement>("#relationship-headline")!.value).toBe("Défiance informationnelle");
  await act(async () => {
    buttonContaining("Enregistrer")!.click();
    await new Promise((resolve) => window.setTimeout(resolve, 0));
  });
  const restoredButton = await waitFor(() => buttonContaining("Défiance informationnelle"));
  expect(restoredButton.closest("td")?.classList.contains("uncertain")).toBe(true);
});

it("nomme les deux directions d’un dossier avec les factions concernées", async () => {
  await act(async () => { root.render(<GmApp />); });
  const politicsButton = await waitFor(() => buttonContaining("Politique"));
  act(() => politicsButton.click());

  const directions = await waitFor(() => container.querySelector<HTMLElement>(".dossier-directions"));
  const labels = Array.from(directions.querySelectorAll("span")).map((element) => element.textContent?.trim());
  expect(labels).toEqual(["Bâtisseurs → Célébrants", "Célébrants → Bâtisseurs"]);
  expect(directions.textContent).not.toContain("Première faction");
  expect(directions.textContent).not.toContain("Seconde faction");
});
