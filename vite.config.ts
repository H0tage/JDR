import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";

const rootDir = fileURLToPath(new URL(".", import.meta.url));
const buildVersion = process.env.GITHUB_SHA?.slice(0, 12) ?? `local-${Date.now()}`;

function buildVersionPlugin(): Plugin {
  return {
    name: "build-version",
    generateBundle() {
      this.emitFile({
        type: "asset",
        fileName: "build-version.json",
        source: JSON.stringify({ version: buildVersion }),
      });
    },
  };
}

export default defineConfig({
  plugins: [react(), buildVersionPlugin()],
  define: { __BUILD_VERSION__: JSON.stringify(buildVersion) },
  base: "/",
  build: {
    rollupOptions: {
      input: {
        landing: resolve(rootDir, "index.html"),
        mj: resolve(rootDir, "MJsecretscreen/index.html"),
        players: resolve(rootDir, "playerscreen/index.html"),
      },
    },
  },
});
