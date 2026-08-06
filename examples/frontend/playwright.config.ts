import { defineConfig } from "@playwright/test";

// Gate 15 (nightly, whole codebase) and its pull-request-time twin
// (full-e2e-accessibility). Builds and serves the real artifact — "everything above
// this line can be green while the built bundle is blank" is exactly the failure mode
// this gate exists to catch. Keep the known-violations baseline in e2e/app.spec.ts
// EMPTY: adding an entry means shipping a known accessibility defect and needs a
// recorded human decision (docs/QUALITY-GATES.md).
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  reporter: [["list"]],
  use: {
    baseURL: "http://localhost:4173",
  },
  webServer: {
    command: "npm run build && npx vite preview --port 4173",
    port: 4173,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
