# Adopting this template

This is the placeholder map: every distinct `{{TOKEN}}` in the tree, every file it
appears in, what belongs there, and how it gets resolved. **A placeholder without a row
here is invisible** — the adopter never learns it needed a value — so this table is
generated mechanically by `tools/gen-adopting.sh` from a grep over the tracked tree, and
`fast-repo-hygiene` fails the pull request if the committed table drifts from what a
fresh regeneration produces. Do not hand-edit the table; edit the source annotation
(`# placeholder: ...` at the token's point of use) and re-run the generator.

Most rows are resolved for you by `tools/init.sh` — see `README.md`'s quickstart. A few
are not, and are named that way in the "Resolved by" column: they are either resolved by
a different tool (`tools/spec-pipeline/new-spec.sh`, `tools/measure-floors.sh`) or
genuinely manual (gate 18's upstream-API contract, health-signal queries).

## The placeholder syntax

A placeholder is always written `{{UPPER_SNAKE_CASE}}` — double braces, ASCII letters,
digits and underscores only. You will see it in three shapes in this tree:

1. **A live token** waiting on your answer (most rows below). `tools/init.sh` finds and
   replaces every one of these across the tracked tree in one pass.
2. **A permanently-documented example**, in this file, in `README.md`,
   `CONTRIBUTING.md` and `docs/runbooks/agent-routines.md` — showing the *syntax*, not a
   token that needs filling in. `tools/check-placeholders.sh` knows about this small,
   fixed set of files and does not flag them.
3. **A reusable micro-template token** (`{{SLUG}}`, `{{DATE}}` in
   `tools/spec-pipeline/templates/`), resolved fresh every time you run
   `tools/spec-pipeline/new-spec.sh <slug>` — not a one-time adoption step.

## The placeholder map

<!-- PLACEHOLDERS:BEGIN -->
| Token | Files | What goes there | Resolved by |
|---|---|---|---|
| `{{ALERT_CHANNEL}}` | .agents/config.yml, .agents/prompts/audit.md, .agents/prompts/backlog-groomer.md, .agents/prompts/challenger.md, .agents/prompts/dependency-steward.md, .agents/prompts/docs-freshness.md, .agents/prompts/health.md, .agents/prompts/quality.md, .agents/prompts/release-drafter.md, .agents/prompts/test-gap.md, docs/runbooks/agent-access-setup.md, docs/runbooks/agent-communication-style.md, docs/runbooks/agent-escalation.md, docs/runbooks/agent-routines.md, docs/runbooks/branch-protection.md, docs/runbooks/qa-procedures.md | none \| webhook \| command | tools/init.sh (interview) |
| `{{BUILD_PIPELINE}}` | .github/agent-temper-headless.md, .github/pull_request_template.md, AGENTS.md, docs/runbooks/agent-modes.md, docs/runbooks/agent-routines.md | {{BUILD_PIPELINE}} is the name of the spec pipeline your agents build | tools/init.sh (interview) |
| `{{CEILING_BUNDLE_KIB}}` | docs/QUALITY-GATES.md | each denotes "whatever floors.yml currently holds for that ratchet key" — the `unset` sentinel until tools/measure-floors.sh runs, then a calibrated number; rendered into the real tool configs by tools/measure-floors.sh / tools/render-floors.sh and never substituted here, by design — see "Floors ship UNCALIBRATED" below. | tools/measure-floors.sh, via floors.yml (never a live substitution — see docs/QUALITY-GATES.md) |
| `{{CHALLENGE_BASE_URL}}` | .agents/config.yml | the compatible endpoint's base URL. | tools/init.sh (interview) |
| `{{DATE}}` | tools/spec-pipeline/new-spec.sh, tools/spec-pipeline/templates/design.md, tools/spec-pipeline/templates/intent.md, tools/spec-pipeline/templates/plan.md | kebab-case spec slug (from argv), and today's date (UTC YYYY-MM-DD) — resolved fresh on every call, not a one-time init.sh substitution. | tools/spec-pipeline/new-spec.sh (per new spec directory, not by init.sh) |
| `{{DEFAULT_BRANCH}}` | docs/runbooks/branch-protection.md | the branch pull requests merge into (`main` for most repos); tools/init.sh fills it in. | tools/init.sh (derived automatically — see design.md P2) |
| `{{FLOOR_BRANCH}}` | docs/QUALITY-GATES.md | each denotes "whatever floors.yml currently holds for that ratchet key" — the `unset` sentinel until tools/measure-floors.sh runs, then a calibrated number; rendered into the real tool configs by tools/measure-floors.sh / tools/render-floors.sh and never substituted here, by design — see "Floors ship UNCALIBRATED" below. | tools/measure-floors.sh, via floors.yml (never a live substitution — see docs/QUALITY-GATES.md) |
| `{{FLOOR_LINE}}` | docs/QUALITY-GATES.md | each denotes "whatever floors.yml currently holds for that ratchet key" — the `unset` sentinel until tools/measure-floors.sh runs, then a calibrated number; rendered into the real tool configs by tools/measure-floors.sh / tools/render-floors.sh and never substituted here, by design — see "Floors ship UNCALIBRATED" below. | tools/measure-floors.sh, via floors.yml (never a live substitution — see docs/QUALITY-GATES.md) |
| `{{FLOOR_MUTATION}}` | docs/QUALITY-GATES.md | each denotes "whatever floors.yml currently holds for that ratchet key" — the `unset` sentinel until tools/measure-floors.sh runs, then a calibrated number; rendered into the real tool configs by tools/measure-floors.sh / tools/render-floors.sh and never substituted here, by design — see "Floors ship UNCALIBRATED" below. | tools/measure-floors.sh, via floors.yml (never a live substitution — see docs/QUALITY-GATES.md) |
| `{{HEALTH_SIGNAL}}` | docs/runbooks/agent-routines.md | your metrics system's query language | manual — documented example syntax only; real slots are .agents/health-signals.yml (P3, design.md section 4.3) |
| `{{LEDGER_COMMIT_EMAIL}}` | .agents/config.yml, tools/ledger.sh | commit email, e.g. "agent@example.invalid" | tools/init.sh (interview) |
| `{{LEDGER_COMMIT_NAME}}` | .agents/config.yml, tools/ledger.sh | commit author for ledger writes, e.g. "sdlc-agent" | tools/init.sh (interview) |
| `{{MODEL_CHALLENGE}}` | .agents/config.yml | a DIFFERENT MODEL FAMILY — a second draw from the same distribution shares the same blind spots. | tools/init.sh (interview) |
| `{{MODEL_EXECUTE}}` | .agents/config.yml | cheaper model. Mechanical edits, scheduled routines. | tools/init.sh (interview) |
| `{{MODEL_JUDGE}}` | .agents/config.yml | strongest available model. Reviews, referee, triage decisions. | tools/init.sh (interview) |
| `{{PLACEHOLDER}}` | docs/QUALITY-GATES.md | a floor's symbolic representation (see the four floor tokens below); this occurrence documents the convention and is not itself a live token. | n/a — documents the {{...}} syntax itself, not a real token |
| `{{PRODUCT_NAME}}` | .agents/prompts/audit.md, .agents/prompts/backlog-groomer.md, .agents/prompts/challenger.md, .agents/prompts/chief-of-staff.md, .agents/prompts/dependency-steward.md, .agents/prompts/docs-freshness.md, .agents/prompts/health.md, .agents/prompts/quality.md, .agents/prompts/release-drafter.md, .agents/prompts/test-gap.md, AGENTS.md, CHANGELOG.md, DEMO.md, docs/QUALITY-GATES.md, docs/runbooks/agent-access-setup.md, docs/runbooks/agent-escalation.md, docs/runbooks/agent-routines.md, docs/runbooks/qa-procedures.md | the system your agents watch. tools/init.sh fills it in. | tools/init.sh (interview) |
| `{{PROVIDER}}` | .agents/config.yml | claude-code \| codex \| gemini-cli. | tools/init.sh (interview) |
| `{{REPO_SLUG}}` | docs/runbooks/branch-protection.md, docs/runbooks/qa-procedures.md | `owner/repo` on GitHub. | tools/init.sh (derived automatically — see design.md P2) |
| `{{RUNNER_LABEL}}` | .github/workflows/ci-health-watch.yml | the label of the self-hosted runner you route work to | tools/init.sh (interview) |
| `{{SLUG}}` | tools/spec-pipeline/new-spec.sh, tools/spec-pipeline/templates/design.md, tools/spec-pipeline/templates/intent.md, tools/spec-pipeline/templates/plan.md, tools/spec-pipeline/templates/tasks.md | kebab-case spec slug (from argv), and today's date (UTC YYYY-MM-DD) — resolved fresh on every call, not a one-time init.sh substitution. | tools/spec-pipeline/new-spec.sh (per new spec directory, not by init.sh) |
| `{{TEMPLATE_VERSION}}` | CHANGELOG.md | the released template version this fork started from, derived from this file's newest heading | tools/init.sh (derived automatically — see design.md P2) |
| `{{UPPER_SNAKE_CASE}}` | CONTRIBUTING.md | this occurrence documents the naming convention itself, not a real token | n/a — documents the {{...}} syntax itself, not a real token |
| `{{UPSTREAM_PROVIDER}}` | .github/workflows/nightly.yml, docs/QUALITY-GATES.md | the external API your product calls at runtime | manual — write tools/live-api-contract.sh; the comment names what belongs there (gate 18 is a contract, not an implementation) |
<!-- PLACEHOLDERS:END -->

## What is not on this list, and why

- **`floors.yml`'s `unset` sentinel** is deliberately *not* a `{{...}}` token (see
  `docs/QUALITY-GATES.md`, "Floors ship UNCALIBRATED") — it is armed by
  `tools/measure-floors.sh`, never by `tools/init.sh`, and it is the one thing in this
  repository that is correct to leave alone until you have a real product to measure.
- **Test fixtures** under `tests/` construct placeholder-shaped strings on purpose, to
  exercise the substitution and detection tooling itself. They are not real tokens and
  `tools/gen-adopting.sh` does not scan them.
- **The `.temper/specs/agent-sdlc-template/` build record** is this template's own
  worked example of a spec directory (kept so you have one on day one — gate 21 needs
  every fix/feature pull request to carry a spec directory). Its placeholder-shaped
  mentions are historical prose about the build that produced this template, not live
  tokens waiting on your answer, and `tools/init.sh` never touches that directory.
