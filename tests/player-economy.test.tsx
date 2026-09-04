import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it } from "vitest";
import { PlayerEconomyTab } from "../src/components/PlayerEconomyTab";

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
  for (let attempt = 0; attempt < 80; attempt += 1) {
    const value = read();
    if (value) return value;
    await act(async () => { await new Promise((resolve) => window.setTimeout(resolve, 5)); });
  }
  throw new Error("Élément attendu introuvable.");
}

it("présente la trésorerie, le compte commun et les demandes sans alourdir l’écran", async () => {
  await act(async () => {
    root.render(<PlayerEconomyTab campaignId="demo" demo viewerRole="player" />);
  });
  const economy = await waitFor(() => container.querySelector<HTMLElement>(".player-economy"));
  expect(economy.textContent).toContain("128 po 5 pa");
  expect(economy.textContent).toContain("les soldes négatifs sont autorisés");
  expect(economy.textContent).toContain("Prénom2 Nom2");
  expect(economy.textContent).toContain("Item anonymisé 1");
  expect(economy.textContent).toContain("Demandes d’objets");
  expect(economy.textContent).toContain("Gains cumulés");
  expect(economy.textContent).toContain("Dépenses cumulées");
  expect(economy.querySelectorAll(".economy-metrics article")).toHaveLength(6);
  expect(economy.querySelector(".economy-summary-large")).toBeTruthy();
  const compact = [...economy.querySelectorAll<HTMLButtonElement>(".economy-display-picker button")].find((button) => button.textContent?.includes("Compact"));
  await act(async () => { compact?.click(); });
  expect(economy.querySelector(".economy-summary-compact")).toBeTruthy();
  expect(window.localStorage.getItem("blood-lords-economy-summary-display")).toBe("compact");
});

it("sépare le gestionnaire de butins de ses explications détaillées", async () => {
  await act(async () => { root.render(<PlayerEconomyTab campaignId="demo" demo viewerRole="player" />); });
  const economy = await waitFor(() => container.querySelector<HTMLElement>(".player-economy"));
  const views = [...economy.querySelectorAll<HTMLButtonElement>(".economy-view-tabs button")];
  expect(views.map((button) => button.textContent)).toEqual(["Butins", "Explications détaillées"]);
  expect(economy.querySelector(".economy-summary")).toBeTruthy();
  await act(async () => { views[1]?.click(); });
  expect(economy.querySelector(".economy-guide")?.textContent).toContain("Seule la plus-value compte comme nouveau gain");
  expect(economy.querySelector(".economy-summary")).toBeNull();
  expect(economy.querySelector(".economy-sections")).toBeNull();
  await act(async () => { views[0]?.click(); });
  expect(economy.querySelector(".economy-summary")).toBeTruthy();
});

it("ouvre l’achat et l’historique d’un objet à la volée", async () => {
  await act(async () => {
    root.render(<PlayerEconomyTab campaignId="demo" demo viewerRole="player" />);
  });
  const economy = await waitFor(() => container.querySelector<HTMLElement>(".player-economy"));
  const purchase = [...economy.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent?.includes("Achat boutique"));
  await act(async () => { purchase?.click(); });
  expect(economy.querySelector(".economy-action-panel")?.textContent).toContain("Part payée par le compte commun");
  expect(economy.querySelector(".economy-action-panel")?.textContent).toContain("La valeur de l’objet sera égale au prix payé");
  expect(economy.querySelector(".economy-action-panel")?.textContent).not.toContain("Valeur de référence unitaire");
  expect(economy.querySelector(".economy-action-panel")?.textContent).toContain("Archive of Nethys");
  const purchaseNumbers = economy.querySelectorAll<HTMLInputElement>(".economy-action-panel input[type=number]");
  const setNumber = (input: HTMLInputElement, value: string) => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set?.call(input, value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
  };
  await act(async () => { setNumber(purchaseNumbers[0]!, "3"); });
  await act(async () => { setNumber(purchaseNumbers[1]!, "12"); });
  expect(economy.querySelector(".purchase-price-field")?.textContent).toContain("Soit 4 po par objet.");

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

it("retire immédiatement une demande annulée de l’écran", async () => {
  await act(async () => { root.render(<PlayerEconomyTab campaignId="demo" demo viewerRole="player" />); });
  const economy = await waitFor(() => container.querySelector<HTMLElement>(".player-economy"));
  const outgoing = [...economy.querySelectorAll<HTMLElement>(".economy-requests article")].find((entry) => entry.textContent?.includes("demande envoyée à Prénom4 Nom4"));
  const cancel = outgoing?.querySelector<HTMLButtonElement>("button");
  expect(cancel?.textContent).toBe("Annuler");
  await act(async () => { cancel?.click(); });
  expect(economy.textContent).not.toContain("demande envoyée à Prénom4 Nom4");
});

it("maintient le joueur connecté dans toute dette qu’il déclare", async () => {
  await act(async () => { root.render(<PlayerEconomyTab campaignId="demo" demo viewerRole="player" />); });
  const economy = await waitFor(() => container.querySelector<HTMLElement>(".player-economy"));
  const debtButton = [...economy.querySelectorAll<HTMLButtonElement>(".economy-actions button")].find((button) => button.textContent?.includes("Déclarer une dette"));
  await act(async () => { debtButton?.click(); });
  const accounts = economy.querySelectorAll<HTMLSelectElement>(".economy-action-panel select");
  expect(accounts[0]?.value).toBe("demo-arsene");
  accounts[0]!.value = "demo-morrigan";
  await act(async () => { accounts[0]!.dispatchEvent(new Event("change", { bubbles: true })); });
  expect(accounts[1]?.value).toBe("demo-arsene");
});

it("range les inventaires des autres joueurs dans des colonnes distinctes", async () => {
  await act(async () => {
    root.render(<PlayerEconomyTab campaignId="demo" demo viewerRole="player" />);
  });
  const economy = await waitFor(() => container.querySelector<HTMLElement>(".player-economy"));
  const groupTab = [...economy.querySelectorAll<HTMLButtonElement>(".economy-sections button")].find((button) => button.textContent?.includes("Inventaires du groupe"));
  await act(async () => { groupTab?.click(); });

  const columns = [...economy.querySelectorAll<HTMLElement>(".economy-player-inventory")];
  expect(columns).toHaveLength(3);
  expect(columns.map((column) => column.querySelector("h2")?.textContent)).toEqual(["Prénom2 Nom2", "Prénom3 Nom3", "Prénom4 Nom4"]);
  expect(columns[0]?.textContent).toContain("Item anonymisé 3");
  expect(columns[1]?.textContent).toContain("Inventaire vide");
  expect(columns[2]?.textContent).toContain("Item anonymisé 4");
  expect(economy.querySelectorAll(".economy-group-mobile-picker option")).toHaveLength(3);
});

it("montre au MJ une colonne pour chacun des joueurs", async () => {
  await act(async () => {
    root.render(<PlayerEconomyTab campaignId="demo" demo viewerRole="gm" />);
  });
  const economy = await waitFor(() => container.querySelector<HTMLElement>(".player-economy"));
  expect(economy.textContent).not.toContain("Achat boutique");
  expect(economy.textContent).toContain("Créer un objet");
  const transfer = [...economy.querySelectorAll<HTMLButtonElement>(".economy-actions button")].find((button) => button.textContent?.includes("Transférer"));
  await act(async () => { transfer?.click(); });
  const transferAccounts = economy.querySelectorAll<HTMLSelectElement>(".economy-action-panel select");
  expect(transferAccounts[0]?.value).toBe("common");
  expect(transferAccounts[1]?.value).toBe("demo-arsene");
  const createItem = [...economy.querySelectorAll<HTMLButtonElement>(".economy-actions button")].find((button) => button.textContent?.includes("Créer un objet"));
  await act(async () => { createItem?.click(); });
  const gainCheckbox = economy.querySelector<HTMLInputElement>('.economy-action-panel input[type="checkbox"]');
  expect(gainCheckbox?.checked).toBe(true);
  expect(gainCheckbox?.parentElement?.textContent).toContain("Compter comme nouveau gain");
  const groupTab = [...economy.querySelectorAll<HTMLButtonElement>(".economy-sections button")].find((button) => button.textContent?.includes("Inventaires du groupe"));
  await act(async () => { groupTab?.click(); });
  expect(economy.querySelectorAll(".economy-player-inventory")).toHaveLength(4);
});
