import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it } from "vitest";
import { PlayerEconomyTab } from "../src/components/PlayerEconomyTab";

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
  for (let attempt = 0; attempt < 80; attempt += 1) {
    const value = read();
    if (value) return value;
    await act(async () => { await new Promise((resolve) => window.setTimeout(resolve, 5)); });
  }
  throw new Error("Élément attendu introuvable.");
}

it("présente la trésorerie, le pot commun et les demandes sans alourdir l’écran", async () => {
  await act(async () => {
    root.render(<PlayerEconomyTab campaignId="demo" demo viewerRole="player" />);
  });
  const economy = await waitFor(() => container.querySelector<HTMLElement>(".player-economy"));
  expect(economy.textContent).toContain("128 po 5 pa");
  expect(economy.textContent).toContain("les soldes négatifs sont autorisés");
  expect(economy.textContent).toContain("Prénom2 Nom2");
  expect(economy.textContent).toContain("Item anonymisé 1");
  expect(economy.textContent).toContain("Demandes d’objets");
  expect(economy.textContent).toContain("Entré depuis le début");
  expect(economy.textContent).toContain("Sorti depuis le début");
  expect(economy.querySelectorAll(".economy-metrics article")).toHaveLength(6);
});

it("ouvre l’achat et l’historique d’un objet à la volée", async () => {
  await act(async () => {
    root.render(<PlayerEconomyTab campaignId="demo" demo viewerRole="player" />);
  });
  const economy = await waitFor(() => container.querySelector<HTMLElement>(".player-economy"));
  const purchase = [...economy.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent?.includes("Achat boutique"));
  await act(async () => { purchase?.click(); });
  expect(economy.querySelector(".economy-action-panel")?.textContent).toContain("Part payée par le pot commun");
  expect(economy.querySelector(".economy-action-panel")?.textContent).toContain("Valeur de référence unitaire");
  expect(economy.querySelector(".economy-action-panel")?.textContent).toContain("Archive of Nethys");

  const close = economy.querySelector<HTMLButtonElement>(".economy-action-panel .icon-button");
  await act(async () => { close?.click(); });
  const details = economy.querySelector<HTMLDetailsElement>(".economy-item-card details");
  await act(async () => { details?.setAttribute("open", ""); });
  const history = [...(details?.querySelectorAll<HTMLButtonElement>("button") ?? [])].find((button) => button.textContent === "Historique");
  await act(async () => { history?.click(); });
  expect(economy.querySelector(".economy-item-history")?.textContent).toContain("Histoire de Item anonymisé 1");
});

it("permet de sélectionner plusieurs objets pour une action groupée", async () => {
  await act(async () => {
    root.render(<PlayerEconomyTab campaignId="demo" demo viewerRole="player" />);
  });
  const economy = await waitFor(() => container.querySelector<HTMLElement>(".player-economy"));
  const selector = economy.querySelector<HTMLInputElement>(".economy-item-selector input");
  await act(async () => { selector?.click(); });
  expect(economy.querySelector(".economy-batch-bar")?.textContent).toContain("1 objet sélectionné");
  expect(economy.querySelector(".economy-batch-bar")?.textContent).toContain("Appliquer");
});

it("range les inventaires des autres joueurs dans des colonnes distinctes", async () => {
  await act(async () => {
    root.render(<PlayerEconomyTab campaignId="demo" demo viewerRole="player" />);
  });
  const economy = await waitFor(() => container.querySelector<HTMLElement>(".player-economy"));
  const groupTab = [...economy.querySelectorAll<HTMLButtonElement>(".economy-sections button")].find((button) => button.textContent?.includes("Inventaires du groupe"));
  await act(async () => { groupTab?.click(); });

  const columns = [...economy.querySelectorAll<HTMLElement>(".economy-player-inventory")];
  expect(columns).toHaveLength(2);
  expect(columns.map((column) => column.querySelector("h2")?.textContent)).toEqual(["Prénom2 Nom2", "Prénom3 Nom3"]);
  expect(columns[0]?.textContent).toContain("Item anonymisé 3");
  expect(columns[1]?.textContent).toContain("Inventaire vide");
  expect(economy.querySelectorAll(".economy-group-mobile-picker option")).toHaveLength(2);
});

it("montre au MJ une colonne pour chacun des joueurs", async () => {
  await act(async () => {
    root.render(<PlayerEconomyTab campaignId="demo" demo viewerRole="gm" />);
  });
  const economy = await waitFor(() => container.querySelector<HTMLElement>(".player-economy"));
  const groupTab = [...economy.querySelectorAll<HTMLButtonElement>(".economy-sections button")].find((button) => button.textContent?.includes("Inventaires du groupe"));
  await act(async () => { groupTab?.click(); });
  expect(economy.querySelectorAll(".economy-player-inventory")).toHaveLength(3);
});
