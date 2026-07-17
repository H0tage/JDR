import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const rootDir = fileURLToPath(new URL(".", import.meta.url));

export default defineConfig({
  plugins: [react()],
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
