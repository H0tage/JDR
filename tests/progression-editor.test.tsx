import { expect, it } from "vitest";
import { anonymizeDemoCampaignData } from "../src/data/demoAnonymization";
import { mockCampaignData } from "../src/data/mockData";

it("présente des jalons de démonstration anonymisés", () => {
  const data = anonymizeDemoCampaignData(mockCampaignData);
  expect(data.milestones).toHaveLength(1);
  expect(data.milestones[0]).toMatchObject({ title: "Jalon 1", condition: "Condition anonymisée." });
});
