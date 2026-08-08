# Agentic SDLC

**Agents propose, a human merges, CI decides.**

*A GitHub template for running your software delivery lifecycle with autonomous
agents — guarded, gated, provider-neutral, and always merged by a human. Guided
tour: **[the project site](https://galando.github.io/agentic-sdlc/)**. Proof it
works: **[agentic-sdlc-demo](https://github.com/galando/agentic-sdlc-demo)** — a
real product adopted from this template, its adoption logged step by step in
its `ADOPTION-LOG.md`.*

```
  issue opened  ──▶  steward triages  ──▶  PR opened  ──▶  two reviews
                                                                │
        ┌───────────────────────────────────────────────────────┘
        ▼
  22-gate gauntlet  ──▶  YOU merge  ──▶  filing agent verifies the fix landed
```

> **Just created a repo from this template? Start here — one command, re-run it
> until done:**
> ```bash
> tools/adopt.sh
> ```
> It walks the entire adoption with you and never acts without your yes.
> Details: section 3. Lost later? `tools/status.sh`.

Every step an agent takes is reviewable in a diff, gated by 22 automated checks, and
merged by a human. This repository is a **GitHub template**: the process scaffolding —
guardrails, ledger, gauntlet, agent prompts — with no product code of yours in it yet.
Use it, then delete the bundled example and wire in your own.

---

## 1. What this is, and the loop it runs

One line: **agents propose, a human merges, CI decides.** The diagram above is the whole
system. Nothing an agent does reaches your default branch without passing the gauntlet
(`docs/QUALITY-GATES.md`) and a human's explicit merge click.

## 2. Who this is for

- You have a GitHub repository (or are about to create one from this template).
- You have one agent-CLI subscription — Claude Code, Codex, or Gemini CLI. (A second,
  *optional*, API key for a different model family unlocks the adversarial second
  review — see the cost section below and `docs/runbooks/multi-model-review.md`.)
- **Prerequisites, concretely:** the GitHub repository, the agent CLI installed
  wherever your workflows run it from, and — for the two working adapters
  (`claude-code`, `compatible-endpoint`) — nothing else to install. `codex` and
  `gemini-cli` ship as unverified stubs (see `tools/providers/`); finishing one is a
  short, documented task, not a rewrite.
- **Rough cost:** the normal case is your existing subscription's flat monthly price —
  see section 8, "Cost, honestly," below before you budget anything else.

### Any language? Three layers, three answers

- **The agent process — any repo, any language, zero changes.** The steward, both
  reviews and the referee, the spec-artifact gate, secret scanning, actionlint, the
  harness guards, the ledger and alerting know nothing about your stack: they operate
  on issues, diffs and workflows. An automated review of a Rust or Python diff works
  on day one.
- **The measured gates ship as reference implementations** for two stacks
  (Java/Spring/Maven and React/TypeScript/Vite): tests, coverage and mutation
  ratchets, architecture rules, migrations, e2e, bundle budget. On any other stack
  they are **swap points, not assumptions** — the table in section 8 lists exactly
  which commands and config files to replace, and `docs/QUALITY-GATES.md` states each
  gate's stack-agnostic *claim* to keep while you swap the tool that proves it.
  Until you swap them, keep your product outside `backend/`/`frontend/` — the gates
  skip cleanly when those paths are absent, but a different stack placed *at* them
  would run the reference commands and fail honestly rather than adapt.
- **The ratchet machinery is already tool-neutral.** `floors.yml` stores plain
  ratios; `tools/measure-floors.sh` announces a clean skip when it finds no
  instrument it knows, and a ported stack's own guard test reads `floors.yml`
  directly, exactly as the reference ratchet-guard tests do.

The porting move worth knowing: once the process layer is live, **open an issue
asking the agent to port the gauntlet to your stack** and merge its pull request —
the system wiring its own gates, under its own review, is the same loop as any other
change.

## 3. Quickstart (target: under 30 minutes)

1. Click **Use this template** on GitHub, or `git clone` and re-point the remote.
2. Run the **guided adoption** — one command, resumable, safe to re-run at any
   point; it detects what is already done and offers the next step:
   ```bash
   tools/adopt.sh
   ```
   It runs the interview (product name, provider, model ids per role — offline,
   seconds), retires the bundled example, writes your product's README, creates
   the ledger branch, offers to commit and push, and then walks the
   GitHub-side steps with you: the `AGENT_CLI_TOKEN` secret, floor calibration
   as your first pull request, branch protection (it can apply the exact rule
   via `gh` with your yes), and the first agent-run issue. **Nothing happens
   without an explicit yes**; every declined offer prints the manual command.
   Pause whenever you like (e.g. to add your product code at `backend/` /
   `frontend/`) and run it again — it picks up where you are. The read-only
   version of the same map is `tools/status.sh`.

   Prefer the steps individually? The interview alone is `tools/init.sh`; it
   asks your answers, rewrites every `{{PLACEHOLDER}}` they resolve, offers the
   example retirement, your product README (`tools/write-product-readme.sh`)
   and the ledger branch, and prints exactly what is left.
3. Add the credentials it lists — at minimum `AGENT_CLI_TOKEN`, which is your agent
   CLI's **subscription token, not an API key** (run
   `tools/run-agent.sh --check-credentials <agent>` and it prints the exact command to
   mint one for the provider you just chose). `CHALLENGE_API_KEY` is a real API key and
   is optional — it buys the adversarial second review. Full table in section 8.
4. Open **issue #1** against the bundled example (`examples/`) and mention your agent —
   the trigger phrase is the `AGENT_MENTION` repository variable, default `@agent`
   (see the `mention:` block in `.agents/config.yml`). Watch the steward triage it,
   open a PR, and watch two reviews and the gauntlet fire.
5. Make your **first human merge.**

That is the whole loop, once, before any of your own code exists. If you are past 30
minutes, section 9 (troubleshooting) is written for exactly this moment.

## 4. The operating loop you now live in

```
issue → steward triages → PR opened → two reviews (judge + challenge) → 22 gates → YOU merge → the filing agent verifies the fix landed
```

| Step | Automated | Yours |
|---|---|---|
| Triage a new issue | ✅ the steward (`.github/workflows/steward.yml`) | — |
| Write the fix / feature | ✅ the mentioned agent | Review the diff before it goes further, if you want to |
| First review (judge) | ✅ always runs | — |
| Second review (challenge, different model family) | ✅ when `CHALLENGE_API_KEY` is set; degrades to one opinion otherwise | — |
| The 22-gate gauntlet | ✅ every check in `docs/QUALITY-GATES.md` | — |
| **The merge itself** | ❌ never automated | **✅ always you** |
| Verifying a fix actually landed | ✅ the agent that filed the original issue, on your next comment/mention | Spot-check the ones that matter to you |

**Budget about 10 minutes a week** once this is running: reading review summaries, merging,
and glancing at `agent-modes.md` if something needs steering. That is the entire
operator burden this system is designed around — see
`docs/runbooks/agent-operator-guide.md` for the fuller version.

## 5. Steering

- **`docs/runbooks/agent-modes.md`** is the *only* channel agents obey for behavior
  changes — mode (`FULL` / `REPORT-ONLY` / `ACTIVE`), per-run PR caps, temporary
  exceptions. Editing a prompt file for a one-off is the wrong lever; this file is the
  right one.
- **Ledgers are history, not configuration.** Every scheduled agent appends one line
  per run to an orphan branch (`docs/runbooks/agent-ledgers.md`) — read it to see what
  happened; do not expect it to change what happens next.
- **Pausing one agent:** set `enabled: false` for that agent in `.agents/config.yml`'s
  `ledger.agents` list. **Pausing everything:** disable
  `.github/workflows/agents-scheduled.yml`'s schedule (it ships disabled by default —
  see section 6) and, if it is mid-incident, flip `agent-modes.md` to `REPORT-ONLY`.

## 6. Turning on the routines, one at a time

The five scheduled agents (health checker, quality analyst, data/output auditor, chief
of staff, challenger) ship **disabled** — nobody should meet this system as five crons
and an alert firehose on day one. Turn each one on only after you have dry-run it:

```bash
tools/run-agent.sh <agent> --dry-run   # prints the exact command; invokes nothing
```

Then flip `enabled: true` for that one agent in `.agents/config.yml`'s `ledger.agents`
list, and re-run the dry-run once more against the real invocation before its first
scheduled fire. Do this one agent at a time, not all five at once.

**GitHub disables scheduled workflows automatically after about 60 days of repository
inactivity.** A quiet template repo is exactly the low-activity case this hits. If your
routines stop firing and every ledger entry has gone stale, this is almost always why —
re-enable the workflow's schedule from the Actions tab (any manual `workflow_dispatch`
run also re-arms it). See `docs/runbooks/agent-routines.md` for the full liveness story
and why the escalation tolerance is what it is.

## 7. Customization map

Every `{{PLACEHOLDER}}` in this tree, the file it lives in, and what belongs there is
generated mechanically into **`ADOPTING.md`** — read that file rather than grepping the
tree yourself; a placeholder without a row there is exactly the failure mode
`tools/gen-adopting.sh` exists to prevent. Most of them, `tools/init.sh` already
resolved for you in the quickstart above.

## 8. The gauntlet

Full detail, the complete gate inventory and the ratchet policy live in
**`docs/QUALITY-GATES.md`** — read that file for the "what each layer is FOR" argument
and the exact rules. The short version:

- **22 gates**, tiered FAST (green in about two minutes, safe to require on day one) and
  FULL (containers/browsers/mutation, live and reporting from day one, promoted to
  required in one documented step within the first week — see
  `docs/runbooks/branch-protection.md`).
- **Every numeric floor ships as the literal `unset` sentinel.** Nothing is calibrated
  against anyone else's code, ever. Run `tools/measure-floors.sh` against **your own**
  product (explicitly online, explicitly slow — the opposite contract to `init.sh`) to
  arm the ratchet against your own measured baseline. It refuses to run while
  `examples/` still exists, so a floor can never be calibrated to the bundled toy
  service. When you are ready, `tools/adopt-layout.sh` retires the example **and**
  re-points the whole harness (workflows, tools, `.gitignore`) at your product's
  root layout — `backend/` and `frontend/` — in one idempotent step; the harness
  guards detect the layout themselves and need no editing.
- **Your floors are your measured baseline; they only move up from there.** Never
  someone else's finish line — see the worked-example numbers in
  `docs/QUALITY-GATES.md`, which are one team's result after months of ratcheting, not
  a default.

### Gate → tool → config → floor (the swap points)

Replacing the reference stack (Java/Spring Boot + React/TypeScript) with your own means
replacing exactly these files — the gate identity, tier and everything else in
`docs/QUALITY-GATES.md` stays put.

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

Everything else in the 22-gate inventory (secret scan, actionlint, the nightly-only
gates, the operational watchdog) is stack-agnostic — see `docs/QUALITY-GATES.md` for the
full table.

### Secrets — what each one is for, and what happens without it

| Secret | Enables | If it is missing |
|---|---|---|
| `AGENT_CLI_TOKEN` | The steward, PR review's judge, and every scheduled routine — the agent CLI's own auth. **This is normally a SUBSCRIPTION TOKEN, not an API key** (see below) | **Required.** The job fails loudly (exit 5) — never a silent no-op, and the message tells you how to mint one |
| `CHALLENGE_API_KEY` | Reviewer B (the adversarial second opinion, a *different* model family) and the challenger routine | Optional. Reviewer B and the referee skip with a `::warning::`; reviewer A's review stands and the PR is never failed for it (see "Missing second-reviewer credential degrades, never fails" in the spec) |
| `STEWARD_HANDOFF_PAT` | Lets a lost-review handoff issue actually retrigger the steward | Optional. Falls back to the default `GITHUB_TOKEN`, which GitHub will not let start a new workflow run — the filed issue says so explicitly and tells you to mention the agent by hand |
| `ALERT_WEBHOOK_URL` | The push side of a nightly-failure alert (chat/webhook ping) | Optional. The GitHub issue — the primary channel — still opens; only the push is skipped, and the run's summary says so |
| `CI_HEALTH_PAT` | The optional CI-health watchdog (self-hosted runner liveness, hosted-minutes) | Optional. The watchdog announces it checked nothing and exits 0 — never a silent skip |
| `DEIDENT_TERMS` | The de-identification sweep in `fast-repo-hygiene`, for your own fork's naming hygiene | Optional, adopter-supplied. The sweep announces it is unarmed and skips — never a false "clean" |
| `VALIDATE_DB_PASSWORD` | `full-migration-validation`'s scratch Postgres service | Optional — defaults to a fixed password scoped to that ephemeral CI container |
| `IT_DB_PASSWORD` | `full-integration-tests`'s scratch Postgres service | Optional — same default-password pattern as above |

#### Subscription token or API key? The two are not interchangeable

This trips people up, so it is worth being blunt. `AGENT_CLI_TOKEN` is a **name**, not a
kind. What belongs in it is decided by `auth.<provider>.mode` in `.agents/config.yml`:

| `mode` | What `AGENT_CLI_TOKEN` holds | Billing |
|---|---|---|
| `subscription` *(the default)* | An **OAuth token minted from your existing plan** — the thing your agent CLI's own "set up a token" command prints. **Not** the key from a developer console. | Covered by your flat monthly plan. A run costs nothing extra. |
| `api-key` | A real API key. | Per token. |

Ask the repository itself rather than guessing — it prints the exact command for the
provider *you* configured, and prints nothing vendor-specific for one you did not:

```bash
tools/run-agent.sh --check-credentials <agent>
```

With the credential missing, that exits 5 and tells you which secret is absent, which
mode it is in, how to mint it, and where to paste it. With it present, it exits 0.

`CHALLENGE_API_KEY` is the one place a **per-token API key is genuinely required**: it
reaches a second model family, and no subscription covers somebody else's model. It is
optional by design — without it the adversarial second opinion degrades to one reviewer
and says so, and a pull request is never failed for its absence.

### Cost, honestly

**Lead with the subscription model, because it is the normal case.** One flat monthly
agent-CLI subscription runs the steward, both scheduled reviews' judge role, and every
routine — the marginal cost of one more run is zero, and nothing surprises you at the
end of the month.

The only place real per-token spend can enter is the **optional** `challenge` role
(`CHALLENGE_API_KEY`, a different model family via `compatible-endpoint`). Losing that
key costs you a second opinion on reviews — never the system; see the secrets table
above. If you
must run on API keys throughout instead of a subscription, the pieces that spend tokens,
roughly in ramp order, are: each steward run, two reviews per pull request (one if the
challenge key is absent), and each enabled routine once per day. Turn routines on one at
a time (section 6) precisely so spend stays proportional to the value you are actually
getting, rather than jumping straight to five daily agents plus two reviews per PR.

## 9. Troubleshooting, written as symptoms

| Symptom | Cause |
|---|---|
| My pull request hangs waiting on a check that never reports | A required status check is sitting behind a workflow-level `paths:` filter instead of a job-level `if:` — the workflow never even runs, so no check run is ever created. See `docs/runbooks/branch-protection.md`. |
| I mentioned the agent and nothing happened | Either the comment came from a bot account (the steward's job-level `if:` refuses any `sender.type == 'Bot'`), or a third event landed in the same concurrency group and evicted the pending run — GitHub keeps one running plus one pending per group. |
| The referee says a review is missing, but I can see it in the PR | The collector is reading the wrong comment endpoint. A review can land as a top-level issue comment or as an inline PR review comment — the collector must query both and merge them; if you changed a prompt's output shape, check it still lands where the collector looks. |
| A review comment isn't picked up even though it's clearly there | Check that its first line is the exact marker `<!-- reviewer: <role> -->` — selection is by marker, never by ordering or exclusion, so a comment without one is invisible to the collector on purpose. |
| A gate I expected to run says "skipped" | That is very likely correct, not a bug — a stack-absent gate (e.g. no `frontend/` present) is supposed to report `skipped`, which GitHub counts as satisfying a required check. If you expected it to actually run, check the `changes` job's paths-filter output. |
| My PR failed a coverage/mutation gate on a brand-new repo | You have not run `tools/measure-floors.sh` yet — floors ship as the `unset` sentinel and print "floor not yet calibrated" rather than gating anything, so a hard failure here means something else regressed, not the floor itself. |
| The steward triaged an issue but posted nothing and the run is red | That is the intended failure mode, not a bug: a run that produced no visible outcome (no comment, no pushed branch) fails deliberately with a marker comment, rather than reporting green having done nothing. |
| An agent's scheduled routine just stopped running | Check whether GitHub auto-disabled the schedule after ~60 days of inactivity (section 6) before assuming the agent itself broke. |
| The gauntlet fails on a fresh clone with no code changes of mine | Run `tools/check-placeholders.sh` — a leftover `{{PLACEHOLDER}}` in a file `tools/init.sh` didn't reach is far more likely than a real regression. |

## 10. Upgrading, license, contributing

**Upgrading.** This is a template repository, not a library — your fork copies it once
and there is no ongoing pull relationship after that. To catch up with a later release,
diff your fork against `CHANGELOG.md`'s release notes. That is also why the harness stays
confined to `.agents/`, `.github/`, `tools/` and the docs at the repo root: keeping the
surface small keeps that diff readable.

**License.** [MIT](LICENSE).

**Contributing.** See `CONTRIBUTING.md` — it routes each new incident-derived rule back
here, so a lesson learned in one fork accumulates upstream instead of dying there.

---

## The setup order, explicitly

*(Lost at any point? `tools/status.sh` prints this whole map with your position
on it and the one next command — read-only, seconds. `tools/adopt.sh` walks the
same map with you, verifying each item where it can and offering to do the
automatable ones.)*

Some of this cannot be committed to a repository at all — a vendor scheduler and an
admin setting are not files. Do these **in this order**, last item last:

1. Create the ledger orphan branch — the agents' run diary — with one idempotent
   command: `tools/create-ledger-branch.sh` (`tools/init.sh` offers to run it for
   you at the end of the interview; `docs/runbooks/agent-ledgers.md` explains it).
2. Add the secrets from the table above that your setup needs.
3. Grant read-only observability access if you have a health-signal source
   (`docs/runbooks/agent-access-setup.md`), then fill in `.agents/health-signals.yml`.
4. Install the agent's GitHub App / CLI integration for this repository.
5. Dry-run each agent prompt interactively before scheduling it (section 6).
6. Calibrate the ratchet against **your** product: `tools/measure-floors.sh`.
7. Enable the scheduled routines one at a time (section 6).
8. **Enable branch protection last**, once the FAST tier has been seen green at least
   once — `docs/runbooks/branch-protection.md` has the exact context strings.

`tools/init.sh` prints this same list at the end of the interview. Nothing above it
touches your repository's settings, secrets, or any external service — it is local text
substitution only.
