# Porting to your own stack

The bundled example ships two reference stacks (Java/Spring Boot/Maven and
React/TypeScript/Vite) so the gauntlet has something real to run against on day one.
Nothing about the agent process or the gate identities is tied to them — this page is
what actually changes when you swap them out.

## Any language? Three layers, three answers

- **The agent process — any repo, any language, zero changes.** The steward, both
  reviews and the referee, the spec-artifact gate, secret scanning, actionlint, the
  harness guards, the ledger and alerting know nothing about your stack: they operate
  on issues, diffs and workflows. An automated review of a Rust or Python diff works
  on day one.
- **The measured gates ship as reference implementations** for the two bundled stacks:
  tests, coverage and mutation ratchets, architecture rules, migrations, e2e, bundle
  budget. On any other stack they are **swap points, not assumptions** — the table
  below lists exactly which commands and config files to replace, and
  `docs/QUALITY-GATES.md` states each gate's stack-agnostic *claim* to keep while you
  swap the tool that proves it. Until you swap them, keep your product outside
  `backend/`/`frontend/` — the gates skip cleanly when those paths are absent, but a
  different stack placed *at* them would run the reference commands and fail honestly
  rather than adapt.
- **The ratchet machinery is already tool-neutral.** `floors.yml` stores plain
  ratios; `tools/measure-floors.sh` announces a clean skip when it finds no
  instrument it knows, and a ported stack's own guard test reads `floors.yml`
  directly, exactly as the reference ratchet-guard tests do.

The porting move worth knowing: once the process layer is live, **open an issue
asking the agent to port the gauntlet to your stack** and merge its pull request —
the system wiring its own gates, under its own review, is the same loop as any other
change.

## Gate → tool → config → floor (the swap points)

Replacing the reference stack with your own means replacing exactly these files — the
gate identity, tier and everything else in `docs/QUALITY-GATES.md` stays put.

| Gate | Reference-stack tool | Config file | Where its floor lives |
|---|---|---|---|
| 1 — Unit tests | Surefire (JUnit 5) / Vitest | `examples/backend/pom.xml` / `examples/frontend/vitest.config.js` | — (no floor; pass/fail only) |
| 2 — Integration tests | Failsafe + a real Postgres service container | `examples/backend/pom.xml` (`docker`-tagged tests) | — |
| 3 — Backend coverage ratchet | JaCoCo | `examples/backend/pom.xml` (`FLOORS:BEGIN backend.coverage.*`) | `floors.yml` → `backend.coverage.line` / `.branch` |
| 4 — Architecture + freeze store | ArchUnit (`FreezingArchRule`) | `examples/backend/.../LayeredArchitectureTest.java` | `examples/backend/archunit_store/` (the frozen violation store itself) |
| 6 — Lint | ESLint (flat config) | `examples/frontend/eslint.config.js` | — |
| 7 — Frontend coverage ratchet | Vitest (`@vitest/coverage-v8`) | `examples/frontend/vitest.config.js` (`FLOORS:BEGIN frontend.coverage.*`) | `floors.yml` → `frontend.coverage.statements` / `.branches` / `.functions` / `.lines` |
| 8 — Acceptance specs | Cucumber | `examples/backend/src/test/resources/features/*.feature` | — |
| 9 — Ratchet guards | A plain JUnit test / a plain Vitest test | `examples/backend/.../RatchetGuardTest.java`, `examples/frontend/src/ratchetGuard.test.ts` | Reads `floors.yml` directly; nothing to render |
| 10 — Migration validation | Flyway | `examples/backend/src/main/resources/db/migration/` | — |
| 12 — Fast dependency CVE gate | `npm audit` (wrapped) | `examples/frontend/scripts/audit-ci.mjs` + `examples/frontend/audit-allowlist.json` | — (each exception is a written, reviewable allowlist entry) |
| 13 — Build hygiene | `maven-enforcer-plugin` | `examples/backend/pom.xml` | — |
| 14 — Design-system guardrail | A plain Node script | `examples/frontend/scripts/check-design-system.mjs`, `examples/frontend/src/tokens.css` | — |
| 15 — E2E + accessibility | Playwright + `@axe-core/playwright` | `examples/frontend/playwright.config.ts`, `examples/frontend/e2e/*.spec.ts` | The known-violations baseline in the spec file (ships empty) |
| 17 — Diff-scoped mutation | PIT / Stryker | `examples/backend/pom.xml` (`mutation` profile) / `examples/frontend/stryker.config.mjs` | `floors.yml` → `backend.mutation.score` / `frontend.mutation.score` |
| 19 — Bundle-size budget | A plain Node script (reads `dist/`) | `examples/frontend/scripts/check-bundle.mjs` | `floors.yml` → `frontend.bundle.total_kib` (read directly — no rendered block) |
| 21 — Spec artifacts present | `tools/spec-pipeline/validate.sh` | `.github/workflows/spec-artifacts.yml` | — |
| 22 — Harness guards | bats, text-pinning the workflows | `tests/harness-guards/pins.json` | — |

Everything else in the 23-gate inventory (secret scan, actionlint, the nightly-only
gates, the operational watchdog, the second brain's own lint) is stack-agnostic — see
`docs/QUALITY-GATES.md` for the full table.
