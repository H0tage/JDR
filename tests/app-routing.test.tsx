import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it } from "vitest";
import { App } from "../src/App";

let root: Root;
let container: HTMLDivElement;

beforeEach(() => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
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

it("ouvre la démo MJ depuis la route historique, même avec ses majuscules", async () => {
  window.history.replaceState(null, "", "/MJsecretscreen/?demo=1");
  await act(async () => { root.render(<App />); });

  const shell = await waitFor(() => container.querySelector<HTMLElement>(".gm-shell"));
  expect(document.title).toBe("Écran MJ · Demo");
  expect(shell.textContent).toContain("Mode aperçu");
  expect(shell.textContent).toContain("Tableau de bord");
  expect([...shell.querySelectorAll(".gm-theme-picker label")].map((label) => label.textContent?.trim())).toEqual(["Clair", "Original", "Sombre"]);
  const themeInputs = shell.querySelectorAll<HTMLInputElement>("input[name='gm-theme']");
  await act(async () => { themeInputs[2]?.click(); });
  expect(shell.className).toContain("gm-theme-github-dark");
  expect(container.querySelector<HTMLAnchorElement>(".player-shortcut")?.getAttribute("href")).toBe("/playerscreen/?demo=1");
});

it("ouvre la démo joueurs depuis la route historique", async () => {
  window.history.replaceState(null, "", "/playerscreen/?demo=1");
  await act(async () => { root.render(<App />); });

  const shell = await waitFor(() => container.querySelector<HTMLElement>(".player-shell"));
  expect(document.title).toBe("Écran Joueurs · Demo");
  expect(shell.textContent).toContain("Registre du groupe");
  expect(shell.textContent).toContain("Comment fonctionne ce site ?");
});

it("affiche toujours les six volumes de la feuille de route au MJ", async () => {
  window.history.replaceState(null, "", "/MJsecretscreen/?demo=1");
  await act(async () => { root.render(<App />); });
  const shell = await waitFor(() => container.querySelector<HTMLElement>(".gm-shell"));
  const milestones = [...shell.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent?.trim() === "Jalons");
  await act(async () => { milestones?.click(); });
  const track = await waitFor(() => shell.querySelector<HTMLElement>(".volume-track"));
  expect(track.querySelectorAll(":scope > button")).toHaveLength(6);
  expect(shell.textContent).not.toContain("Masquer la feuille de route");
  expect(shell.textContent).not.toContain("Consulter les autres volumes");
});

it("propose les deux espaces de démonstration depuis l’accueil déconnecté", async () => {
  window.history.replaceState(null, "", "/");
  await act(async () => { root.render(<App />); });

  const demoEntry = await waitFor(() => container.querySelector<HTMLElement>(".demo-entry"));
  const gate = container.querySelector<HTMLElement>(".portal-gate");
  expect(gate?.textContent).toContain("Blood Lords");
  expect(gate?.textContent).toContain("Les Registres de Geb");
  expect(gate?.textContent).not.toContain("Regalade");
  expect(gate?.querySelector(".portal-seal")?.textContent).toBe("BL");
  expect(demoEntry.textContent).toContain("Tester le site en mode démo");
  expect(demoEntry.querySelector<HTMLAnchorElement>("a[href='/MJsecretscreen/?demo=1']")?.textContent).toBe("Demo MJ");
  expect(demoEntry.querySelector<HTMLAnchorElement>("a[href='/playerscreen/?demo=1']")?.textContent).toBe("Demo Joueur");
});
