import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it } from "vitest";
import { GmApp } from "../src/components/GmApp";

it("le menu MJ annonce son état et rend le focus à son bouton après Échap", async () => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  window.history.replaceState(null, "", "/MJsecretscreen/?demo=1");
  const container = document.createElement("div");
  document.body.append(container);
  const root = createRoot(container);
  try {
    await act(async () => root.render(<GmApp campaignId="demo" />));
    for (let attempt = 0; attempt < 100 && !container.querySelector('[aria-label="Ouvrir le menu"]'); attempt++) {
      await act(async () => { await new Promise((resolve) => setTimeout(resolve, 5)); });
    }
    const trigger = container.querySelector<HTMLButtonElement>('[aria-label="Ouvrir le menu"]')!;
    expect(trigger).toBeTruthy();
    trigger.focus();
    await act(async () => trigger.click());
    expect(trigger.getAttribute("aria-expanded")).toBe("true");
    expect(container.querySelector("#gm-navigation")?.contains(document.activeElement)).toBe(true);
    await act(async () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
    expect(trigger.getAttribute("aria-expanded")).toBe("false");
    expect(document.activeElement).toBe(trigger);
  } finally { act(() => root.unmount()); container.remove(); }
});
