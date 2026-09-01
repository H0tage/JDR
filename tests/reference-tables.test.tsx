import { expect, it } from "vitest";
import { anonymizeDemoArchives, anonymizeDemoLoot } from "../src/data/demoAnonymization";
import { archiveCharacterSeeds, archivePlaceSeeds, lootSeeds } from "../src/data/referenceSeed";

it("garde des archives et butins de démonstration sans contenu de campagne", () => {
  const archives = anonymizeDemoArchives(archiveCharacterSeeds, archivePlaceSeeds);
  const loot = anonymizeDemoLoot(lootSeeds);
  expect(archives.characters.map((entry) => entry.first_name)).toEqual(["Prénom1", "Prénom2"]);
  expect(archives.places.map((entry) => entry.original_name)).toEqual(["Lieu 1", "Lieu 2"]);
  expect(loot.map((entry) => entry.item_name)).toEqual([
    "Item anonymisé 1", "Item anonymisé 2", "Item anonymisé 3",
    "Item anonymisé 4", "Item anonymisé 5", "Item anonymisé 6",
  ]);
});
