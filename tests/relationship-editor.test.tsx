import { expect, it } from "vitest";
import { anonymizeDemoCampaignData } from "../src/data/demoAnonymization";
import { mockCampaignData } from "../src/data/mockData";

it("présente des relations de démonstration génériques", () => {
  const data = anonymizeDemoCampaignData(mockCampaignData);
  expect(data.relationships).toHaveLength(1);
  expect(data.relationships[0]).toMatchObject({ headline: "Relation 1", source_name: "Faction 1", target_name: "Faction 2", color: "uncertain" });
});
