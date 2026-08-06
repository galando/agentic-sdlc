import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// Build-only config. Test/coverage configuration lives in vitest.config.js instead of
// here — see that file's header comment for why the split matters to
// tools/render-floors.sh.
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      // Local dev only: `npm run dev` proxies to a backend on :8080. Production serves
      // both from the same origin, so this block does nothing outside `vite`/`vite dev`.
      "/api": "http://localhost:8080",
    },
  },
  build: {
    // Gate 19 reads dist/assets/* directly (scripts/check-bundle.mjs) — no config
    // needed here beyond Vite's default chunking.
    sourcemap: false,
  },
});
