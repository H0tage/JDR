import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it } from "vitest";
import { PlayerApp } from "../src/components/PlayerApp";

let root: Root;
let container: HTMLDivElement;

beforeEach(() => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  window.history.replaceState(null, "", "/playerscreen/?demo=1");
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

function setRangeValue(input: HTMLInputElement, value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
  setter?.call(input, value);
  input.dispatchEvent(new Event("input", { bubbles: true }));
}

it("ouvre la page personnelle depuis Pages des joueurs et rappelle sa confidentialité", async () => {
  await act(async () => { root.render(<PlayerApp campaignId="00000000-0000-4000-8000-000000000001" viewerRole="player" />); });
  const shell = await waitFor(() => container.querySelector<HTMLElement>(".player-shell"));
  expect(shell.querySelector(".player-dashboard")).toBeTruthy();
  expect([...shell.querySelectorAll(".player-tabs button")].map((button) => button.textContent)).toContain("Accueil");
  expect([...shell.querySelectorAll(".player-theme-picker label")].map((label) => label.textContent?.trim())).toEqual(["Clair", "Original", "Sombre"]);
  expect(shell.querySelector(".print-button")).toBeNull();
  const themeInputs = shell.querySelectorAll<HTMLInputElement>("input[name='player-theme']");
  await act(async () => { themeInputs[2]?.click(); });
  expect(shell.className).toContain("player-theme-github-dark");
  await act(async () => { themeInputs[1]?.click(); });
  expect(shell.className).toContain("player-theme-dark");
  expect(shell.className).not.toContain("player-theme-github-dark");
  const button = shell.querySelector<HTMLButtonElement>(".player-pages-menu > button");
  expect(button).toBeTruthy();
  expect(button?.textContent).toContain("Pages des joueurs");
  await act(async () => { button?.click(); });
  const page = await waitFor(() => container.querySelector<HTMLElement>(".player-page-tab"));
  expect(page.textContent).toContain("Les autres joueurs peuvent la consulter en lecture seule");
  expect(page.textContent).toContain("uniquement par vous et le MJ");
  expect(page.querySelector(".player-character-sheet")).toBeTruthy();
  expect(page.querySelector("textarea")).toBeNull();
  expect(page.querySelector("iframe")).toBeNull();
  const partyRelations = await waitFor(() => page.querySelector<HTMLElement>(".player-party-relations"));
  expect(partyRelations.textContent).toContain("Les autres personnages");
  expect(partyRelations.textContent).toContain("Prénom2 Nom2");
  const portraitButton = page.querySelector<HTMLButtonElement>(".player-character-portrait-button");
  await act(async () => { portraitButton?.click(); });
  expect(document.querySelector(".character-lightbox-card")).toBeTruthy();
  await act(async () => { document.querySelector<HTMLButtonElement>(".character-lightbox-card .icon-button")?.click(); });
  const pathbuilderButton = [...page.querySelectorAll<HTMLButtonElement>(".player-page-view-tabs button")].find((candidate) => candidate.textContent?.includes("Page Pathbuilder2e"));
  expect(pathbuilderButton).toBeTruthy();
  await act(async () => { pathbuilderButton?.click(); });
  const pathbuilderFrame = page.querySelector<HTMLIFrameElement>(".pathbuilder-embed iframe");
  expect(pathbuilderFrame?.getAttribute("src")).toBe("https://pathbuilder2e.com/app.html");
  expect(pathbuilderFrame?.getAttribute("title")).toBe("Fiche de personnage dans Pathbuilder 2e");
  expect(page.querySelector(".pathbuilder-embed > header")).toBeNull();
  expect(page.querySelector(".pathbuilder-possessions")?.textContent).toContain("Item anonymisé 2");
  const focusButton = [...page.querySelectorAll<HTMLButtonElement>(".player-page-view-controls > button")].find((candidate) => candidate.textContent?.includes("Cadrer Pathbuilder"));
  await act(async () => { focusButton?.click(); });
  expect(page.classList.contains("pathbuilder-focus-mode")).toBe(true);
  expect(document.body.style.overflowY).toBe("hidden");
  expect(window.localStorage.getItem("blood-lords-pathbuilder-focused")).toBe("1");
  const registerButton = [...page.querySelectorAll<HTMLButtonElement>(".player-page-view-tabs button")].find((candidate) => candidate.textContent?.includes("Page Registre"));
  await act(async () => { registerButton?.click(); });
  expect(document.body.style.overflowY).toBe("");
  expect(page.querySelector(".player-page-pathbuilder-view")?.hasAttribute("hidden")).toBe(true);
  expect(page.querySelector(".pathbuilder-embed iframe")).toBe(pathbuilderFrame);
  await act(async () => { pathbuilderButton?.click(); });
  expect(page.querySelector(".player-page-pathbuilder-view")?.hasAttribute("hidden")).toBe(false);
  expect(page.querySelector(".pathbuilder-embed iframe")).toBe(pathbuilderFrame);
  const journalButton = [...shell.querySelectorAll<HTMLButtonElement>(".player-tabs button")].find((candidate) => candidate.textContent?.includes("Journal de quête"));
  await act(async () => { journalButton?.click(); });
  expect(document.body.style.overflowY).toBe("");
  expect(page.closest(".persistent-player-page")?.hasAttribute("hidden")).toBe(true);
  expect(page.querySelector(".pathbuilder-embed iframe")).toBe(pathbuilderFrame);
  await act(async () => { button?.click(); });
  expect(page.closest(".persistent-player-page")?.hasAttribute("hidden")).toBe(false);
  expect(page.querySelector(".pathbuilder-embed iframe")).toBe(pathbuilderFrame);
  expect(page.classList.contains("pathbuilder-focus-mode")).toBe(true);
  expect(document.body.style.overflowY).toBe("hidden");
  const releaseButton = [...page.querySelectorAll<HTMLButtonElement>(".player-page-view-controls > button")].find((candidate) => candidate.textContent?.includes("Libérer la page"));
  await act(async () => { releaseButton?.click(); });
  expect(window.localStorage.getItem("blood-lords-pathbuilder-focused")).toBe("0");
  await act(async () => { registerButton?.click(); });
  const editButton = [...page.querySelectorAll<HTMLButtonElement>("button")].find((candidate) => candidate.textContent?.includes("Modifier ma page"));
  await act(async () => { editButton?.click(); });
  expect(page.querySelector(".player-page-edit textarea")).toBeTruthy();
});

it("ne montre pas Ma page au MJ dans la vue joueurs", async () => {
  await act(async () => { root.render(<PlayerApp campaignId="00000000-0000-4000-8000-000000000001" campaignSlug="vampire-bonegolem" viewerRole="gm" />); });
  const shell = await waitFor(() => container.querySelector<HTMLElement>(".player-shell"));
  const gmShortcut = shell.querySelector<HTMLAnchorElement>(".player-gm-shortcut");
  expect(gmShortcut?.getAttribute("href")).toBe("/campaign/vampire-bonegolem/mj");
  expect(gmShortcut?.hasAttribute("target")).toBe(false);
  expect(shell.querySelector(".player-gm-shortcut")?.textContent).toContain("Vue MJ");
  const tabLabels = [...shell.querySelectorAll(".player-tabs button")].map((button) => button.textContent);
  expect(tabLabels).not.toContain("Ma page");
  expect(tabLabels).toContain("Pages des joueurs");
  await act(async () => { await shell.querySelector<HTMLButtonElement>(".player-pages-menu > button")?.click(); });
  const playerChoice = await waitFor(() => [...document.querySelectorAll<HTMLButtonElement>("[role='menuitem']")].find((button) => button.textContent?.includes("Prénom1 Nom1")));
  expect(playerChoice).toBeTruthy();
  await act(async () => { playerChoice?.click(); });
  const page = await waitFor(() => container.querySelector<HTMLElement>(".player-pages-readonly"));
  expect(page.textContent).toContain("Lecture seule");
  expect(page.textContent).toContain("En tant que MJ, vous voyez aussi ses notes privées");
  expect(page.querySelector("textarea")).toBeNull();
});

it("permet de cadrer puis de réinitialiser le portrait du personnage", async () => {
  await act(async () => { root.render(<PlayerApp campaignId="00000000-0000-4000-8000-000000000001" viewerRole="player" />); });
  const shell = await waitFor(() => container.querySelector<HTMLElement>(".player-shell"));
  await act(async () => { shell.querySelector<HTMLButtonElement>(".player-pages-menu > button")?.click(); });
  const page = await waitFor(() => container.querySelector<HTMLElement>(".player-page-tab"));
  const editButton = [...page.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent?.includes("Modifier ma page"));
  await act(async () => { editButton?.click(); });
  const zoom = page.querySelector<HTMLInputElement>('input[aria-label="Zoom du portrait"]');
  const horizontal = page.querySelector<HTMLInputElement>('input[aria-label="Centrage horizontal du portrait"]');
  const vertical = page.querySelector<HTMLInputElement>('input[aria-label="Centrage vertical du portrait"]');
  expect(page.querySelector(".player-page-portrait-preview > .player-page-crop-controls")).toBeNull();
  expect(page.querySelector(".player-page-portrait-preview > img")).toBeTruthy();
  expect([zoom?.type, horizontal?.type, vertical?.type]).toEqual(["range", "range", "range"]);
  expect([zoom?.value, horizontal?.value, vertical?.value]).toEqual(["1", "50", "50"]);
  await act(async () => {
    if (zoom) setRangeValue(zoom, "2");
    if (horizontal) setRangeValue(horizontal, "25");
  });
  expect(page.querySelector<HTMLImageElement>('.player-page-edit-portrait img')?.style.transform).toContain("scale(2)");
  const reset = [...page.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent?.includes("Réinitialiser le cadrage"));
  expect(reset).toBeTruthy();
  await act(async () => { reset?.click(); });
  expect([zoom?.value, horizontal?.value, vertical?.value]).toEqual(["1", "50", "50"]);
});

it("permet à un joueur de consulter les autres fiches sans Pathbuilder ni notes privées", async () => {
  await act(async () => { root.render(<PlayerApp campaignId="00000000-0000-4000-8000-000000000001" viewerRole="player" />); });
  const shell = await waitFor(() => container.querySelector<HTMLElement>(".player-shell"));
  const menuButton = shell.querySelector<HTMLButtonElement>(".player-pages-menu > button");
  await act(async () => { menuButton?.focus(); });
  const choices = await waitFor(() => {
    const entries = [...document.querySelectorAll<HTMLButtonElement>("[role='menuitem']")];
    return entries.length >= 4 ? entries : null;
  });
  expect(choices[0]?.textContent).toContain("Ma page");
  const otherPlayer = choices.find((choice) => choice.textContent?.includes("Prénom2 Nom2"));
  await act(async () => { otherPlayer?.click(); });
  const readonly = await waitFor(() => container.querySelector<HTMLElement>(".player-pages-readonly"));
  expect(readonly.textContent).toContain("Personnage 2");
  expect(readonly.textContent).toContain("Ses notes privées et Pathbuilder restent masqués");
  expect(readonly.textContent).not.toContain("Notes privées");
  expect(readonly.textContent).not.toContain("Ouvrir la fiche Pathbuilder");
  expect(readonly.querySelector("iframe")).toBeNull();
});

it("ne propose pas la vue MJ à un joueur", async () => {
  await act(async () => { root.render(<PlayerApp campaignId="00000000-0000-4000-8000-000000000001" campaignSlug="vampire-bonegolem" viewerRole="player" />); });
  const shell = await waitFor(() => container.querySelector<HTMLElement>(".player-shell"));
  expect(shell.querySelector(".player-gm-shortcut")).toBeNull();
});

it("affiche les raccourcis du journal sous le navigateur", async () => {
  await act(async () => { root.render(<PlayerApp campaignId="00000000-0000-4000-8000-000000000001" viewerRole="player" />); });
  const shell = await waitFor(() => container.querySelector<HTMLElement>(".player-shell"));
  const journalButton = [...shell.querySelectorAll<HTMLButtonElement>(".player-tabs button")].find((button) => button.textContent?.includes("Journal de quête"));
  await act(async () => { journalButton?.click(); });
  const shortcuts = await waitFor(() => container.querySelector<HTMLElement>(".journal-shortcuts"));
  expect(shortcuts.textContent).toContain("Alt+Entrée");
  expect(shortcuts.textContent).toContain("Ctrl+Entrée");
  expect(shortcuts.textContent).toContain("Ctrl+Maj+Z");
});

it("affiche les contacts en liste alphabétique avec leur faction", async () => {
  await act(async () => { root.render(<PlayerApp campaignId="00000000-0000-4000-8000-000000000001" viewerRole="player" />); });
  const shell = await waitFor(() => container.querySelector<HTMLElement>(".player-shell"));
  const relations = [...shell.querySelectorAll<HTMLButtonElement>(".player-tabs button")].find((button) => button.textContent?.includes("Relations"));
  await act(async () => { relations?.click(); });
  const listButton = await waitFor(() => [...shell.querySelectorAll<HTMLButtonElement>(".relations-heading nav button")].find((button) => button.textContent?.includes("Liste")));
  await act(async () => { listButton.click(); });
  const rows = [...shell.querySelectorAll<HTMLElement>(".player-contact-list > button")];
  const names = rows.map((row) => row.querySelector("strong")?.textContent ?? "");
  expect(names).toEqual([...names].sort((left, right) => left.localeCompare(right, "fr", { sensitivity: "base" })));
  expect(rows.every((row) => Boolean(row.querySelector("em")?.textContent))).toBe(true);
});
