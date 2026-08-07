// frontend/vitest.config.js — kept SEPARATE from vite.config.ts (rather than a merged
// `test:` block in the Vite config, which Vitest also supports) because
// tools/render-floors.sh targets this exact filename when it rewrites the
// FLOORS:BEGIN/END block below from ../floors.yml — see design.md section 7.2 and
// docs/QUALITY-GATES.md's "Floors ship UNCALIBRATED". Vitest merges this file with
// vite.config.ts automatically; nothing else needs to know it exists.
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    // e2e/ holds Playwright specs (gate 15), not Vitest ones — its default include
    // pattern (**/*.spec.ts) would otherwise also match them and fail at collection
    // time, since a Playwright test() call outside Playwright's own runner throws.
    exclude: ["**/node_modules/**", "**/dist/**", "e2e/**"],
    setupFiles: ["./src/setupTests.ts"],
    coverage: {
      provider: "v8",
      reporter: ["text", "json-summary", "html"],
      include: ["src/**/*.{ts,tsx}"],
      exclude: ["src/main.tsx", "src/**/*.test.{ts,tsx}"],
      // FLOORS:BEGIN frontend.coverage.*
      // floors.yml says `unset` — no thresholds enforced yet. An empty object is
      // vitest's own "measure but do not gate"; run tools/measure-floors.sh to arm it.
      thresholds: {},
      // FLOORS:END
    },
  },
});
