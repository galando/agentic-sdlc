// frontend/stryker.config.mjs — gate 17 (diff-scoped, PR-time) and gate 5 (nightly,
// whole codebase). FLOORS:BEGIN/END block rendered from ../floors.yml by
// tools/render-floors.sh — see design.md section 7.2.
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
export default {
  packageManager: "npm",
  testRunner: "vitest",
  reporters: ["progress", "html", "json"],
  coverageAnalysis: "perTest",
  mutate: ["src/**/*.{ts,tsx}", "!src/main.tsx", "!src/**/*.test.{ts,tsx}"],
  htmlReporter: { fileName: "reports/mutation/mutation.html" },
  jsonReporter: { fileName: "reports/mutation/mutation.json" },
  // FLOORS:BEGIN frontend.mutation.score
  // `break: null` is Stryker's documented "do not fail the build". floors.yml says
  // `unset`; when calibrated this becomes an integer and only ever moves up.
  thresholds: { high: 95, low: 85, break: null },
  // FLOORS:END
};
