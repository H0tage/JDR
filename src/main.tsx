import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import "./styles.css";

if (!import.meta.env.DEV) {
  void fetch(`/build-version.json?check=${Date.now()}`, { cache: "no-store" })
    .then(async (response) => response.ok ? response.json() as Promise<{ version?: string }> : null)
    .then((release) => {
      if (!release?.version || release.version === __BUILD_VERSION__) return;
      const url = new URL(window.location.href);
      url.searchParams.set("v", release.version);
      window.location.replace(url.toString());
    })
    .catch(() => undefined);
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
