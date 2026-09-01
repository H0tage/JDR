import { describe, expect, it } from "vitest";
import { mockCampaignData } from "../src/data/mockData";
import { lootSeeds } from "../src/data/referenceSeed";
import { anonymizeDemoCampaignData, anonymizeDemoLoot } from "../src/data/demoAnonymization";
import { loadPlayerLoot } from "../src/lib/playerLootApi";

describe("anonymisation de la démonstration", () => {
  it("remplace les jalons, personnes, factions et références sans modifier la source", () => {
    const data = anonymizeDemoCampaignData(mockCampaignData);

    expect(data.milestones.map((item) => item.title)).toEqual(data.milestones.map((_, index) => `Jalon ${index + 1}`));
    expect(data.contacts[0]?.name).toBe("Prénom1 Nom1");
    expect(data.factions[0]?.name).toBe("Faction 1");
    expect(JSON.stringify(data)).not.toContain("Nom de campagne réel");
    expect(mockCampaignData.contacts[0]?.name).toBe("Prénom1 Nom1");
  });

  it("emploie la même numérotation de butin côté MJ et côté joueur", async () => {
    const gmLoot = anonymizeDemoLoot(lootSeeds);
    const playerLoot = await loadPlayerLoot("demo", true);

    expect(gmLoot[0]?.item_name).toBe("Item anonymisé 1");
    for (const item of playerLoot) {
      expect(item.original_name).toBe(gmLoot.find((candidate) => candidate.sort_order === item.sort_order)?.item_name);
    }
    expect(JSON.stringify(gmLoot)).not.toContain("Objet de campagne réel");
  });
});
