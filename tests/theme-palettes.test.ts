import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

const themes = readFileSync("src/themes.css", "utf8");
const styles = readFileSync("src/styles.css", "utf8");

it("les trois thèmes MJ et joueurs possèdent une palette complète et centralisée", () => {
  for (const selector of [".player-shell.player-theme-light", ".player-shell.player-theme-dark", ".player-shell.player-theme-github-dark", ".gm-theme-light", ".gm-shell.gm-theme-original", ".gm-shell.gm-theme-github-dark"]) {
    const block = themes.split(selector + " {")[1]?.split("}")[0];
    expect(block, selector).toBeTruthy();
    for (const token of ["page", "panel", "panel-strong", "panel-soft", "line", "text", "heading", "muted", "image-well"]) {
      expect(block, `${selector}: ${token}`).toContain(`--theme-${token}:`);
    }
  }
  expect(styles).toContain('@import "./themes.css"');
  expect(styles).not.toMatch(/--theme-(?:page|panel|heading)\s*:/);
});

it("les agrandissements gardent une palette pour chacun des trois thèmes hors de la page", () => {
  for (const theme of ["light", "original", "dark"]) {
    expect(themes).toContain(`.image-viewer-theme-${theme}`);
  }
});
