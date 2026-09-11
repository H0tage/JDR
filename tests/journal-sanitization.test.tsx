import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it } from "vitest";
import { QuestWritingTab, sanitizeContent } from "../src/components/QuestWritingTab";
import type { QuestJournalPage } from "../src/lib/types";

it("retire les scripts, événements et liens dangereux sans perdre les séances du journal", () => {
  const html = sanitizeContent('<details data-session-id="a" open><summary>Séance</summary><p onclick="alert(1)">Texte</p><img src="https://example.test/a.png" onerror="alert(1)"><a href="javascript:alert(1)">lien</a><script>alert(1)</script></details>');
  expect(html).not.toMatch(/onclick|onerror|javascript:|<script/);
  expect(html).toContain('data-session-id="a"');
  expect(html).toContain("Texte");
});

it("neutralise les espaces de noms SVG et MathML et les URL encodées dangereuses", () => {
  for (const payload of [
    '<svg><a xlink:href="javascript:alert(1)">attaque</a></svg>',
    '<math><mtext><img src=x onerror=alert(1)></mtext></math>',
    '<a href="java&#x09;script:alert(1)">attaque</a><iframe srcdoc="test"></iframe>',
  ]) {
    const result = sanitizeContent(payload);
    expect(result).not.toMatch(/onerror|javascript:|xlink|<svg|<math|<iframe/);
  }
});

it("conserve les marqueurs nécessaires aux séances et aux encadrés après nettoyage", () => {
  const html = '<details data-session-id="session-1" data-locked="true" open><summary>Séance</summary><span class="journal-session-date" data-session-date="2026-09-10" contenteditable="false">Date</span><div class="journal-callout" data-callout-id="note-1"><p data-indent="2">Note</p></div></details>';
  const result = sanitizeContent(html);
  expect(result).toContain('data-locked="true"');
  expect(result).toContain('data-session-date="2026-09-10"');
  expect(result).toContain('data-callout-id="note-1"');
  expect(result).toContain('data-indent="2"');
  expect(sanitizeContent(result)).toBe(result);
});

it("nettoie le HTML reçu avant le premier affichage du journal", async () => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  const container = document.createElement("div");
  document.body.append(container);
  const root = createRoot(container);
  try {
    const page = { campaign_id: "test", content: '<p>Bonjour</p><img src="https://example.test/a.png" onerror="alert(1)">', revision: 0 } as QuestJournalPage;
    await act(async () => root.render(<QuestWritingTab page={page} demo onChanged={() => undefined} onNotice={() => undefined} onError={() => undefined} />));
    expect(container.querySelector("[onerror]")).toBeNull();
    expect(container.textContent).toContain("Bonjour");
  } finally { act(() => root.unmount()); container.remove(); }
});
