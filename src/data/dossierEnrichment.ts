import type { BilateralDossier } from "../lib/types";

type EnrichedDossier = Pick<BilateralDossier, "canon_core" | "a_to_b" | "b_to_a" | "common_interest" | "fracture">;

/** Campaign-specific dossier prose belongs in a private campaign package. */
export const dossierEnrichment: Record<string, EnrichedDossier> = {};
