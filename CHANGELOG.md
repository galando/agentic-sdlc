# Changelog

This is a **template repository**: adopters copy it once, at instantiation time, and
never `git pull` from it again. There is no ongoing merge relationship. That is why the
harness stays confined to `.agents/`, `.github/`, `tools/`, `floors.yml` and the docs at
the repo root — if you ever want to catch up with a later release, this file is what you
diff against, and keeping the surface small keeps that diff readable.

`tools/init.sh` reads the most recent `## x.y.z` heading below to derive
`{{TEMPLATE_VERSION}}` <!-- placeholder: the released template version this fork started from, derived from this file's newest heading --> wherever it appears in the tree (a P2
placeholder — see `ADOPTING.md`). Every release therefore needs a heading in exactly this
shape.

## [0.2.0] - 2026-08-07

The first repository-wide audit release: a static explainer site, a batch of real bug
fixes the audit surfaced, and the tool the escalation runbook always promised.

### Added

- `site/` and `.github/workflows/pages.yml` — a self-contained GitHub Pages explainer
  ("what this is, the loop it runs, quickstart"). One-time setting to activate:
  Settings → Pages → Source: **GitHub Actions**.
- `tools/alert.sh` — the pushed-alert sender `docs/runbooks/agent-escalation.md` has
  mandated since 0.1.0 but which never shipped. Reads `alerts.*` from the config,
  supports `none | webhook | command`, exempts the S0 heartbeat from the severity
  floor, and exits 4 (never silently) on an undeliverable configured push. Covered by
  `tests/alert.bats`.

### Fixed

- **The steward's issue→PR handoff could never fire**: its condition read a
  `branch_name` output nothing ever set, while the triage prompt told the agent the
  workflow would open the pull request. The pushed branch is now detected by diffing
  the remote's `agent/*` heads before and after the agent run.
- **`tools/measure-floors.sh` could never measure anything**: its guard requires
  `examples/` to be deleted while every measurement path pointed inside `examples/`.
  Measurement now targets the adopter layout (`backend/`, `frontend/`);
  `tools/render-floors.sh` probes both layouts, and its calibrated output no longer
  embeds the render date (which broke idempotency and the drift gate after
  calibration). Backend "line" coverage now reads JaCoCo's LINE counters, not
  INSTRUCTION.
- **`tools/check-liveness.sh` reported `ok` when the liveness thresholds were missing
  from the config** — a green produced by the very misconfiguration it exists to catch.
- **Locale-dependent em-dash parsing** mangled gate 21's declared-unavailable reason
  and ADOPTING.md regeneration under a POSIX locale (`[—–-]` brackets match bytes, not
  characters — now dash alternations).
- `VALIDATE_DB_PASSWORD` no longer appears in `mvn`'s argv in
  `full-migration-validation` (Flyway reads the `FLYWAY_*` env vars natively).
- `nightly-dependency-scan` now skips at job level when neither stack is present,
  instead of reporting green having scanned nothing.
- A named `workflow_dispatch` of `agents-scheduled.yml` on a pre-init tree now gets
  the announced-skip every other workflow gives that state, not a red run.
- `spec-artifacts.yml` dropped its `workflow_dispatch` trigger (a dispatch run had no
  PR context and could only ever go red); `actionlint.yml` pins its installer script
  to a release tag instead of piping `main` into bash.
- `tools/run-agent.sh`: config-supplied secret *names* are validated and resolved via
  bash indirection instead of `eval`; the credential scrub anchors on the variable
  name so a value merely containing `_API_KEY=` is no longer unset.
- `tools/mutation-scope.sh` fails loudly on an unresolvable base ref instead of
  reporting an empty scope ("nothing to mutate").
- Smaller: `record-gate.sh` no longer copies the pass value into an omitted detail;
  `floor_get`'s two readers now agree that a missing key is a failure (not the string
  `null`); the de-identification sweep always prints the file name for a hit; the
  adapters' header comments no longer parse as malformed shellcheck directives;
  `README.md` is titled statically (the `{{PRODUCT_NAME}}` H1 rendered as a broken
  placeholder on every uninitialised template) and its quickstart points at the real
  mention-phrase location; `docs/QUALITY-GATES.md` lists gate 15's per-PR job in the
  blocking table; `.agents/config.yml` no longer inverts the severity ladder in its
  `severity_floor` comment and no longer documents `compatible-endpoint` as a legal
  top-level provider.

## [0.1.0] - 2026-08-06

Initial public release.

### Added

- The 22-gate quality gauntlet (`docs/QUALITY-GATES.md`), tiered FAST/FULL, with every
  numeric floor shipped as an explicit `unset` sentinel in `floors.yml` — never a number,
  never a silent zero.
- `steward.yml` and `review.yml`: the mention-triggered agent loop and the two-reviewer
  (judge/challenge) PR review workflow, with the harness-guard test suite (gate 22) that
  text-pins their load-bearing strings against the incidents that shaped them.
- `tools/run-agent.sh` and four provider adapters (`claude-code`, `compatible-endpoint`
  verified; `codex`, `gemini-cli` unverified stubs) addressed by role
  (`judge`/`execute`/`challenge`), never by task.
- `tools/init.sh` — the offline, idempotent adoption interview — and
  `tools/measure-floors.sh` — the explicitly-online, explicitly-slow ratchet calibrator
  that refuses to run against the bundled example.
- `tools/spec-pipeline/`, the fallback spec scaffold, and gate 21
  (`spec-artifacts.yml`), which fails a fix/feature PR carrying no spec directory and no
  declared-unavailable reason.
- `tools/ledger.sh` and the orphan-branch agent ledger (`docs/runbooks/agent-ledgers.md`).
- `examples/`: a minimal reference-stack product (Java/Spring Boot + React/TypeScript)
  that arms all twelve stack-specific gates end to end, deletable by `tools/init.sh`.
- `tools/check-deidentified.sh` and `tools/check-placeholders.sh`, the two sweeps that
  keep a fork honest about what it still names and what it has not yet filled in.
- `ADOPTING.md`, generated by `tools/gen-adopting.sh` from the tree's own placeholder
  occurrences, so a placeholder without a row cannot be merged.

### Known limitations

See the PR history and `README.md`'s troubleshooting section for the full list. In
short: two of four provider adapters are unverified stubs; Routine schedules and branch
protection cannot be committed and are manual, ordered, one-line setup steps; gate 18
(live API contract) ships as a documented, unarmed contract; the deploy-time
backup-restore gate is documented but not wired to any real environment.

## Config schema changes

`.agents/config.yml` and `floors.yml` each carry a `schema:` integer. A tool refuses to
read a schema it does not support (`tools/lib/config.sh`'s `cfg_assert_schema`) rather
than silently reinterpreting an old file under a new shape. When a schema bump ships, its
migration note goes here, keyed as "Config schema N → M", together with the
`tools/migrate-config-N-to-M.sh` script that performs it. No such bump has shipped yet.
