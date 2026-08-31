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

it("affiche Ma page au joueur et rappelle sa confidentialité", async () => {
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
  const button = [...shell.querySelectorAll("button")].find((candidate) => candidate.textContent?.includes("Ma page"));
  expect(button).toBeTruthy();
  await act(async () => { button?.click(); });
  const page = await waitFor(() => container.querySelector<HTMLElement>(".player-page-tab"));
  expect(page.textContent).toContain("Vous seul pouvez modifier cette page");
  expect(page.textContent).toContain("Le MJ peut la consulter");
  expect(page.querySelector(".player-character-sheet")).toBeTruthy();
  expect(page.querySelector("textarea")).toBeNull();
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
  expect(page.textContent).toContain("Lecture seule pour le MJ");
  expect(page.querySelector("textarea")).toBeNull();
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
