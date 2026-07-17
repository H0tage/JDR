import { describe, expect, it } from "vitest";
import { mockFactions, mockServices, mockSettings } from "../data/mockData";
import { quoteService, reputationStatus, tensionLabel, unlockedServices } from "./domain";

describe("reputationStatus", () => {
  it("uses the configured thresholds", () => {
    expect(reputationStatus(0, mockSettings)).toBe("Indifférents");
    expect(reputationStatus(5, mockSettings)).toBe("Appréciés");
    expect(reputationStatus(15, mockSettings)).toBe("Admirés");
    expect(reputationStatus(30, mockSettings)).toBe("Révérés");
  });
});

describe("tensionLabel", () => {
  it("never reveals implementation wording", () => {
    expect(tensionLabel(0)).toBe("Stable");
    expect(tensionLabel(3)).toBe("Accès limité");
    expect(tensionLabel(4)).toBe("Rupture");
  });
});

describe("quoteService", () => {
  const faction = { ...mockFactions.find((item) => item.slug === "réanimateurs")!, jf: 15, rp: 15 };
  const minor = mockServices.find((item) => item.faction_id === faction.faction_id && item.scale === "Mineure")!;
  const moderate = mockServices.find((item) => item.faction_id === faction.faction_id && item.scale === "Modérée")!;

  it("applies the free first minor service", () => {
    expect(quoteService(minor, faction, mockSettings, "first_liked")).toMatchObject({ allowed: true, cost: 0, balanceAfter: 15 });
  });

  it("adds the tension surcharge before the admired discount", () => {
    const quote = quoteService(moderate, { ...faction, tension: 2 }, mockSettings, "admired_discount");
    expect(quote).toMatchObject({ allowed: true, cost: 6, balanceAfter: 9 });
  });

  it("blocks every service after a rupture", () => {
    expect(quoteService(minor, { ...faction, tension: 4 }, mockSettings).allowed).toBe(false);
  });
});

describe("unlockedServices", () => {
  it("uses the special Carters threshold", () => {
    expect(unlockedServices(25, "charretiers", mockSettings)).toContain("majeure unique");
    expect(unlockedServices(25, "bâtisseurs", mockSettings)).toBe("Mineure et modérée");
  });
});
