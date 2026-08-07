# Tasks: Autonomous-Agent SDLC Template Repository

## Prerequisites

- [x] Read `.temper/specs/agent-sdlc-template/intent.md` (success criteria + 22 scenarios)
- [x] Read `.temper/specs/agent-sdlc-template/plan.md` (the 30-row extraction inventory —
      it names, per file, which of the three buckets it falls in)
- [x] Read `agentsdlcrepoprompt.md` at the repo root (the acceptance checklist)

## Standing rules for every task below

1. **`{{SOURCE_REPO}}` is READ-ONLY.** Read files. Never write, never
   `git` anything there, never create a temp file inside it. Task 0 takes the checksum
   that proves this; Task 32 re-verifies it.
2. **Extraction over regeneration.** If the plan's inventory says bucket A or B, `cp` the
   file first, then edit. Never open a blank buffer for a file that exists upstream.
3. **Rewrite incident comments; never delete them.** "A review posted as an inline
   comment was reported missing…" — the lesson survives, the specifics do not.
4. **Every PR ends** with a plain-language summary: extracted unchanged / genericized /
   new / stubbed.

---

# PR (a) — Extraction + genericization

## [x] Task 0: Checksum the source repository [SEQUENTIAL]

**Action:** CREATE
**File:** `.temper/evidence/source-manifest.sha256` (never committed to the template)
**Traced to:** Scenario: "The source repository is never written to"
**Validate:** `cd {{SOURCE_REPO}} && git status --porcelain | wc -l` → `0`
**Notes:** Record `git rev-parse HEAD` too. This is the guard for the highest-consequence
risk in the plan. Take it before touching anything.

## [x] Task 1: Extract the four zero-brand-hit files nearly as-is [SEQUENTIAL: after Task 0]

**Action:** CREATE
**File:** `docs/runbooks/agent-ledgers.md`, `.github/agent-temper-headless.md`,
`.github/pull_request_template.md`, `docs/runbooks/multi-model-review.md`
**Traced to:** Infrastructure: the ledger schema, headless contract, gate-integrity
attestation and adversary-model rationale that every later task references
**Validate:** `grep -ricf .temper/evidence/deident-terms.txt docs/runbooks/agent-ledgers.md .github/agent-temper-headless.md .github/pull_request_template.md docs/runbooks/multi-model-review.md` → all `0`
**Notes:** These four measured 0 brand hits at survey time — the lowest-risk extraction,
so it goes first and establishes the genericization idiom. Changes needed: agent keys →
config-driven; pipeline names → `{{BUILD_PIPELINE}}`; the dated false-premise incident
table in the headless file → neutral lesson; vendor/model names in multi-model-review →
the `challenge` role. Source note: the headless file is named `steward-temper-headless.md`
upstream and lands as `agent-temper-headless.md` here.

## [x] Task 2: Extract `tools/ledger.sh` and prove it round-trips [SEQUENTIAL: after Task 1]

**Action:** CREATE
**File:** `tools/ledger.sh`
**Traced to:** Scenario: "Ledger round-trips on a fresh orphan branch"
**Test:** `tests/ledger-roundtrip.bats` + a captured transcript for the PR body
**Validate:** in a scratch repo with a remote: create the orphan branch, then
`tools/ledger.sh append ops '{"date":"2026-08-04","verdict":"green","summary":"first run","metrics":{"disk_pct":41}}' && tools/ledger.sh read ops && tools/ledger.sh latest && tools/ledger.sh trend ops disk_pct`
**Notes:** One brand hit — the commit identity `<project>-agent@<project>.local` →
placeholder. Hard-code nothing else: the `AGENTS` list becomes config-driven. Preserve
verbatim: the clone-the-REMOTE comment (cloning the local checkout makes the push land on
a local ref and report success while nothing reaches the server), the 5-attempt
fetch-append-replay-never-force loop, and the derive-the-destination-path reasoning in
`cmd_append`. The prompt asks to *see the transcript* — capture it.

## [x] Task 3: Extract `AGENTS.md` + the three pointer files [PARALLEL: with Task 4]

**Action:** CREATE
**File:** `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`
**Traced to:** Scenario: "No vendor name leaks into workflows, runbooks or prompts"
**Validate:** `wc -l CLAUDE.md GEMINI.md .github/copilot-instructions.md` → each ≤ 3 lines
**Notes:** Upstream `AGENTS.md` is only 37 lines and carries all seven guardrails as
shapes. Add the prompt's guardrail 7 wording about the build pipeline and its three
exceptions. The pointer files contain ONE line each — a second copy of the rules is a
second source of truth that will drift.

## [x] Task 4: Extract the operator-facing runbooks [PARALLEL: with Task 3]

**Action:** CREATE
**File:** `docs/runbooks/agent-modes.md`, `agent-escalation.md`, `agent-operator-guide.md`,
`agent-communication-style.md`, `qa-procedures.md`, `branch-protection.md`
**Traced to:** Scenarios: "A nightly failure reaches a human automatically",
"A gate whose stack is absent reports skipped, not missing"
**Validate:** `tools/check-deidentified.sh docs/runbooks/` (written in Task 12; until then,
grep manually)
**Notes:** `agent-modes.md` has 0 brand hits — the mechanism (`FULL`/`REPORT-ONLY`/
`ACTIVE`, per-run PR caps, the expiring exception table, mode history) ports whole; only
the numerics are examples. `branch-protection.md` carries the load-bearing lesson: a
context string is the job `name:` or id, a required check that never reports blocks
forever, job-level `if:` counts as passing and workflow-level `paths:` does not. Keep the
Option A (UI) / Option B (one API call) split.

## [x] Task 5: Rewrite `agent-access-setup.md` from its shape only [SEQUENTIAL: after Task 4]

**Action:** CREATE
**File:** `docs/runbooks/agent-access-setup.md`
**Traced to:** Infrastructure: guardrail 1 (production is read-only)
**Validate:** zero hits for any source domain, host or secret name
**Notes:** Highest brand density measured (7 hits in 64 lines) — this is the one runbook
where regeneration beats extraction. Keep only the shape: network allowlist → read-only
observability token → agent env secrets → VCS access → the HTTPS-only / no-SSH / no-DB /
no-log-mirror access pattern → dry-run before scheduling. Keep the principle that the
edge-bypass credential must be distinct from the human admin credential.

## [x] Task 6: Genericize `agent-routines.md` — the largest single job [SEQUENTIAL: after Task 5]

**Action:** CREATE
**File:** `docs/runbooks/agent-routines.md`
**Traced to:** Scenario: "Scheduled agents ship disabled by default"
**Validate:** `grep -c '{{HEALTH_SIGNAL' docs/runbooks/agent-routines.md` > 0; zero brand
hits; five agents documented with schedules
**Notes:** 672 L / 18 brand hits, and raw grep understates it badly — the domain leaks
through nouns and dated incident narratives, not just the project name. Semantic
de-identification, not `sed`. KEEP: the model policy (pinned exact ids, never floating
aliases; split judge / execute / challenge; challenge from a DIFFERENT family), the 7
binding efficiency rules, the UTC/DST reasoning, the watcher-ring — **RE-BASED, see Task 19b:
"did the agent before me run TODAY" becomes "within the last N hours", because the
substitute scheduler is not punctual** — the fix-verification
rules (the FILING agent verifies; verify the END STATE not the mechanism; never invent an
unobservable proxy; reopen at 24h; record `fix_verified`), the arithmetic-trend-not-vibes
pattern, the retired-metric tombstone pattern, the kill switch. REDUCE from 8 agents to
the prompt's 5: health checker, quality analyst, data/output auditor, chief of staff,
challenger (the source's event-driven agent is the steward, and its two
coverage/incident agents fold into the quality analyst). Every metric name and query
becomes a `{{HEALTH_SIGNAL}}` slot.

## [x] Task 6b: Write the lesson inventory BEFORE any workflow is touched [SEQUENTIAL: after Task 6, BLOCKS Tasks 7–10]

**Action:** CREATE
**File:** `tests/harness-guards/lesson-inventory.md` (committed) +
`tests/harness-guards/pins.json` (the machine-readable pin list)
**Traced to:** Scenario: "A lost extraction lesson fails the build" (new — add to intent.md)
**Validate:** every entry has `id`, `source_file`, `source_line`, `quoted_source_string`,
`why` (the neutral lesson), `expected_in` (target file), and `pin_kind`
(`literal` | `regex` | `semantic-manual`). Entry count >= 25.
**Notes:** THIS IS THE FIX FOR THE ORDERING HOLE. Gate 22's guards were previously written
in Task 20, i.e. *after* Tasks 7–10 had already substituted the workflows — so they would
have pinned whatever survived, and reported green on a lesson that was silently dropped.
A net woven after the fall.

Inverted: read the SOURCE workflows (`claude.yml` 455 L, `claude-review.yml` 605 L,
`pr-tests.yml`, `pr-mutation.yml`, `nightly-alert.yml`, `secret-scan.yml`) and enumerate
every load-bearing string BEFORE substitution begins. Quote each one verbatim from the
source with its line number. This file is the ACCEPTANCE CRITERION that Tasks 7–10 must
then satisfy — substitution is judged against an assertion that already existed, not the
other way round.

Two pin kinds matter and they are not the same job:
- `literal` / `regex` — survives substitution unchanged (e.g. `sender.type != 'Bot'`,
  `--paginate --slurp`, `<!-- reviewer:`, `cancel-in-progress: false`). Gate 22 pins these
  mechanically.
- `semantic-manual` — the string itself MUST change during genericization (a repo-standards
  path, a metric name, the mention phrase), so no literal pin is possible. Record what the
  concept is and what its replacement must preserve. These get a checklist entry in Task
  10b, not an assertion — and the inventory must say so, so nobody later mistakes an
  unpinnable lesson for a pinned one.

Minimum coverage — the six `review.yml` lessons, the four `steward.yml` lessons, the
notifier's `permissions:` requirement, the required-check context strings, and the
supply-chain carve-out. Where a lesson exists only as a comment in the source, pin the
comment: a rule without its reason gets deleted by the next person, and that deletion is
exactly what this catches.

## [x] Task 10b: Extraction accounting — prove nothing was dropped [SEQUENTIAL: after Task 10, BLOCKS Task 11]

**Action:** CREATE
**File:** `.temper/evidence/extraction-diff.md` (evidence, not shipped)
**Traced to:** Scenario: "A lost extraction lesson fails the build"
**Validate:** for every bucket-B file, a line-accounted reconciliation:
`source_lines = kept + placeholdered + deleted_as_domain_specific`, with EVERY deleted
line listed and one-line-justified. Then: run the Task 6b pin list against the extracted
tree and require 100% of `literal`/`regex` pins present; walk every `semantic-manual`
entry by hand and record the replacement.
**Notes:** The source repo is reachable NOW and may not be later — this reconciliation is
only possible during PR (a). Deleting a line because it names the source product is
correct; deleting it because it was inconvenient is the failure. Making every deletion
explicit is what separates the two. A pin that is absent here means Task 7–10 lost a
lesson: go back and restore it, do not weaken the pin.

## [x] Task 7: Extract `steward.yml` from `claude.yml` [SEQUENTIAL: after Task 6b]

**Action:** CREATE
**File:** `.github/workflows/steward.yml`
**Traced to:** Scenarios: "A bot sender cannot start the loop",
"Auto-triage that produced nothing fails on purpose"
**Test:** `tests/harness-guards/steward.*` (Task 20)
**Validate:** `actionlint .github/workflows/steward.yml`
**Notes:** 455 L. Copy first. PRESERVE EXACTLY: auto-triage on `issues:[opened]` with no
tag needed; every other trigger requiring the mention AND `github.event.sender.type != 'Bot'`;
concurrency at JOB level with group `…-${{ github.event.issue.number || github.event.pull_request.number }}`
and `cancel-in-progress: false` (job-level so a skipped job never enters the group and
cannot evict a pending run); the visible-outcome step (paginated comment scan since the
recorded job start + a real pushed branch, else a marker comment and a deliberate
`setFailed`); the eviction reporter. REPLACE: the vendor action with `tools/run-agent.sh`
(Task 15 — until then leave a clearly-marked TODO that fails loudly, never one that
no-ops); the mention phrase with `vars.AGENT_MENTION || '@agent'`; every repo-standards
doc path with the template's own.

## [x] Task 8: Extract `review.yml` from `claude-review.yml` [SEQUENTIAL: after Task 7]

**Action:** CREATE
**File:** `.github/workflows/review.yml`
**Traced to:** Scenarios: "Reviewer identity comes from a marker",
"The comment collector reads both comment homes", "Paginated reads slurp before filtering",
"Missing second-reviewer credential degrades, never fails"
**Test:** `tests/harness-guards/review.*` (Task 20)
**Validate:** `actionlint .github/workflows/review.yml`
**Notes:** 605 L — the single densest incident file in the plan; budget real time. Six
lessons must survive: (1) the `<!-- reviewer: <role> -->` exact first-line marker and
selection by marker, never by ordering or exclusion; (2) `--paginate --slurp` then
`jq add` then filter, with the per-page-filter comment intact; (3) reading BOTH the
issue-comments and the PR review-comments endpoints and merging; (4) reviewer B gated on
its optional credential with `::warning::` degradation, referee skipped when B did not
run, PR never failed; (5) the handoff FILES AN ISSUE rather than commenting, because the
bot-sender gate in `steward.yml` makes commenting unreachable, and says loudly when the
elevated token is absent; (6) the workflow-file supply-chain carve-out. Also preserve:
per-PR-number concurrency, never triggering on `synchronize`, the exact-literal dedupe
that deliberately avoids `--search in:title`, and the escalate-on-unrecognised-format
branch. Reviewer A / B / referee become the `judge` and `challenge` roles.

## [x] Task 9: Extract the blocking-gate workflows [SEQUENTIAL: after Task 8]

**Action:** CREATE
**File:** `.github/workflows/pr-tests.yml`, `pr-mutation.yml`, `pr-validation.yml`,
`secret-scan.yml`
**Traced to:** Scenario: "A gate whose stack is absent reports skipped, not missing"
**Validate:** `actionlint .github/workflows/`
**Notes:** `pr-tests.yml` (235 L) is the clean-skip reference: a `changes` paths-filter
job whose outputs gate each job AND each step. Preserve that doubling — it is what makes
SC3 true. Freeze the job `name:`/id strings: they are the branch-protection context
strings, and renaming one silently breaks every downstream adopter.

**Do the FAST/FULL tier split HERE, at extraction time** (design.md contradiction 3): job
names are frozen the moment they are written, so splitting the tiers later in Task 23b would
mean renaming them afterwards — the exact act the freeze rule forbids. Use design.md's
frozen context strings verbatim: FAST — `fast-unit-tests`, `fast-frontend-checks`,
`fast-harness-guards`, `fast-repo-hygiene`, `fast-actionlint`, `fast-secret-scan`,
`fast-spec-artifacts`; FULL — `full-integration-tests`, `full-migration-validation`,
`full-mutation-on-diff`, `full-e2e-accessibility`, `full-bundle-budget`. Each job's `name:`
equals its id, so there is one string per gate rather than two that can drift.

`pr-validation.yml` and `pr-mutation.yml` arrive WITH workflow-level `paths:` filters —
correct upstream because neither is a required check, but they cannot stay: both are
FULL-tier and therefore promotable, and a required check behind a workflow-level `paths:`
filter never reports at all, leaving the PR waiting forever on a status that will never
arrive. Convert both to a `changes`-fed job-level `if:`, which is the conversion the
source's own `branch-protection.md` prescribes. Keep the incident comment — it survives as
the lesson that explains the conversion, not as the defect it describes.

## [x] Task 10: Extract the nightly workflows + the reusable notifier [SEQUENTIAL: after Task 9]

**Action:** CREATE
**File:** `.github/workflows/nightly.yml`, `.github/workflows/nightly-alert.yml`
**Traced to:** Scenario: "A nightly failure reaches a human automatically"
**Validate:** `actionlint`; every caller declares `permissions: {contents: read, issues: write}`
**Notes:** The source has NO single `nightly.yml` — gates 5, 15, 16, 18 and 20 live in five
separate workflows (`mutation-tests`, `e2e-tests`, `security-scan`,
`live-api-contract-tests`, `flaky-test-detection`). Consolidate into one `nightly.yml`
with per-gate jobs, each cleanly skippable, and keep the odd-minute cron convention.
**One notifier job PER GATE, never one that ORs the gate results together** (design.md
contradiction 4). The five source workflows each opened their own
`[nightly] <gate> is failing` issue; consolidating them into one workflow with a single
OR-ing `notify-failure` job would collapse five distinct issues into one, so a second gate
going red while the first is still red produces no new signal at all — and the issue title
would name the wrong gate. `nightly-alert.yml` (198 L) ports nearly as-is; the alert push
becomes an `{{ALERT_CHANNEL}}` step. Keep the postmortem comment on the caller `permissions:` block:
a reusable workflow cannot hold more permission than its caller, and a caller that forgets
is rejected at STARTUP — its gate jobs do not run either, so the gate goes quiet rather
than red. Gate 18 is informative/non-blocking; its body is fully domain-specific upstream
and becomes a documented shell.

## [x] Task 11: Extract `docs/QUALITY-GATES.md` and extend it to 22 gates [SEQUENTIAL: after Task 10]

**Action:** CREATE
**File:** `docs/QUALITY-GATES.md`
**Traced to:** Scenario: "A fresh instantiation is green on day one"
**Validate:** every gate row names a job that exists under `.github/workflows/`; every
numeric floor is a `{{PLACEHOLDER}}`, not a number
**Notes:** Lead with the gauntlet framing quote and the "nobody reads every line — trust
comes from what a change survived" premise. Keep verbatim-in-spirit: the full ratchet
policy (floors move one way; never lower one to make a PR pass; suppression is not
passing; the only two honest reasons a number may drop are a changed measuring instrument
or a widened scope, and the config comment and PR must say which, every time; agents may
never lower one), the 10-item "what each layer is FOR" ladder in the prompt's order, the
required-check-vs-`paths:`-filter rule, and the notifier-shipped-broken postmortem. ADD
gate 21 (spec-artifacts-present) and gate 22 (harness guards) to the inventory. **Every
floor ships as a placeholder** — the upstream numbers (line ≥92 / branch ≥84, PIT ≥89,
Stryker ≥96, stmts ≥96 / branch ≥89 / funcs ≥98 / lines ≥97, bundle ≤400 KiB) are the
SOURCE product's measured baselines; shipping them makes every adopter's first PR
permanently red. Also document the deploy-time gate (restore the latest backup into a
scratch container and validate migrations before restarting).

## [x] Task 12: Write the de-identification sweep and run it [SEQUENTIAL: after Task 11]

**Action:** CREATE
**File:** `tools/check-deidentified.sh`
**Traced to:** Scenarios: "De-identification sweep finds zero source-project traces",
"No vendor name leaks into workflows, runbooks or prompts"
**Test:** `tests/deidentified.bats`
**Validate:** `tools/check-deidentified.sh --terms .temper/evidence/deident-terms.txt` →
exit 0, zero hits; AND `grep -rf .temper/evidence/deident-terms.txt` over the tracked tree
→ zero hits INCLUDING the scanner itself (no self-exclusion anywhere)
**Notes:** Must sweep file CONTENT, file NAMES and COMMIT MESSAGES.

**The term list must never enter the tree.** The original spec had the scanner carrying the
project name, domain, owner handle and domain nouns inline — which means the shipped
template would contain a curated enumeration of precisely what it claims to have removed.
Self-excluding the scanner does not fix that; it just makes the leak invisible to its own
check, and it is the first file a reader opens to audit the extraction.

Split in two:
- `.temper/evidence/deident-terms.txt` — the real terms. **Gitignored, build-time only,
  never committed.** Add it to `.gitignore` in the same commit that creates it.
- `tools/check-deidentified.sh` — SHIPPED, and generic: it takes `--terms <file>` and names
  nothing itself. Defaults to `.deident-terms` in the repo root, which the adopter writes
  for their own forks. Useful to them for exactly the reason it is useful here. The CI
  wiring the prompt asks for stays, and skips cleanly when no term file exists.

The scanner is then subject to its own sweep with no carve-out — which is the only version
of this check that means anything.

## [x] Task 12b: The list-free residual pass [SEQUENTIAL: after Task 12, BLOCKS Task 13]

**Action:** CREATE
**File:** `.temper/evidence/deident-review.md` (evidence, not shipped)
**Traced to:** Scenario: "De-identification sweep finds zero source-project traces"
**Validate:** every bucket-A and bucket-B file has a recorded verdict and a named reviewer
pass; any residual-flavour finding is either fixed or justified in writing
**Notes:** Task 12 is a proof of absence from a list we wrote, so it goes green on
everything nobody thought to enumerate — the template's own named failure mode, a green run
with a wrong answer. `plan.md` already records that raw grep understates the leak badly:
the domain survives in PromQL metric names, agency names, dated incident narratives and
ordinary nouns, none of which a term list catches.

So read every extracted file once more, without a list, asking only: could a stranger infer
what this product does? Specific things to hunt that greps structurally cannot find —
metric and query names that describe the domain; example values and test fixtures; issue
and PR numbers in prose; date-stamped incident narratives specific enough to identify an
event; anything in a language other than the template's; and the shape of a business rule
in an acceptance-spec example. Record a verdict per file, because an unrecorded pass is
indistinguishable from a skipped one.

## [x] Task 13: PR (a) summary [SEQUENTIAL: after Task 12]

**Action:** CREATE
**File:** PR body
**Traced to:** Infrastructure: the prompt requires a per-PR plain-language summary
**Validate:** the body names, in four lists, what was extracted unchanged, what was
genericized, what is new, and what is stubbed

---

# PR (b) — New plumbing

## [x] Task 14: `.agents/config.yml` + the five prompts [SEQUENTIAL: after Task 13]

**Action:** CREATE
**File:** `.agents/config.yml`, `.agents/prompts/{health,quality,audit,chief-of-staff,challenger}.md`
**Traced to:** Scenario: "Dry-run prints the exact command for every provider"
**Validate:** `yq . .agents/config.yml` parses; every prompt references only repo files
**Notes:** The config holds: provider name; model id per ROLE (`judge`, `execute`,
`challenge`) — never per task; AUTH MODE per provider (subscription token vs API key,
subscription first); the mention trigger; the alert channel. Prompts are plain markdown so
they are reviewable in a diff and readable by any runner — and so a vendor scheduler can
replace `agents-scheduled.yml` one-for-one without touching them.

## [x] Task 15: `tools/run-agent.sh` [SEQUENTIAL: after Task 14]

**Action:** CREATE
**File:** `tools/run-agent.sh`
**Traced to:** Scenario: "Dry-run prints the exact command for every provider"
**Test:** `tests/run-agent-dryrun.bats`
**Validate:** `tools/run-agent.sh health --dry-run` prints the full argv and invokes
nothing
**Notes:** Reads the config, resolves the prompt file, shells out to
`tools/providers/<name>.sh`. `--dry-run` is the explicitly-requested smoke test and must
work with no agent CLI installed at all.

## [x] Task 16: The four provider adapters [SEQUENTIAL: after Task 15]

**Action:** CREATE
**File:** `tools/providers/{claude-code,codex,gemini-cli,compatible-endpoint}.sh`
**Traced to:** Scenario: "Dry-run prints the exact command for every provider"
**Test:** `tests/run-agent-dryrun.bats`
**Validate:** each prints its exact command under `--dry-run`; each stub exits non-zero
with an `UNVERIFIED STUB` banner and a docs URL when actually executed; every adapter
declares `ADAPTER_STATUS=verified|unverified` as a machine-readable line, and
`tools/run-agent.sh --adapter-status <provider>` prints it
**Notes:** Adapters own exactly the four things that genuinely differ: the headless flag,
model selection, tool-permission granting, and how the working tree is handed over.

The `ADAPTER_STATUS` declaration is what Task 21 reads to decide whether the event-driven
agents may ship live — see Decision 8. Keep it a single greppable line per adapter, not a
lookup table in init.sh: a second list of which adapters are verified is a second source of
truth, and it will drift the moment someone finishes one.
**TWO ship working, two ship as stubs** — classified by evidence, not by count:

- `claude-code.sh` — `ADAPTER_STATUS=verified`. Flags verified by the source's production use.
- `compatible-endpoint.sh` — `ADAPTER_STATUS=verified`. Its mechanic (override base URL and
  auth token in a subprocess with the original credentials UNSET — unsetting matters, or the
  original credential wins and the "different family" second opinion is silently the same
  model) is extracted from the source's `multi-model-review.md` and review workflow, where it
  is how the second reviewer actually runs. Same evidentiary standard as claude-code.sh.
- `codex.sh`, `gemini-cli.sh` — `ADAPTER_STATUS=unverified`. Stubs. A stub a maintainer fills
  in beats a plausible invocation that silently does nothing, and a stub that exits 0 is
  worse than no stub.

Do not demote compatible-endpoint to a stub for symmetry. It is the ONLY delivery path for
the `challenge` role, so a stub there means reviewer B never runs for anyone, SC10's
degradation branch becomes the only branch ever taken, and the `challenger` scheduled agent
has no execution path — turning the different-family adversarial review into documentation
about a feature nobody can switch on. Its optional API key stays optional: absent, the
system degrades to one opinion and says so, exactly as SC10 specifies. Verified means the
invocation is known-good, not that the credential is mandatory.

## [x] Task 17: `tools/spec-pipeline/` [SEQUENTIAL: after Task 16]

**Action:** CREATE
**File:** `tools/spec-pipeline/`
**Traced to:** Scenario: "Gate 21 fails a fix PR with no spec artifacts"
**Validate:** running it produces a spec directory and a gate ledger from templates
**Notes:** The contract is the ARTIFACTS, not the plugin. Each adapter delegates to the
build plugin when present and drives this scaffold when not — so any agent on any vendor
produces the same artifacts and faces the same gate 21.

## [x] Task 18: Gate 21 — `spec-artifacts.yml` [SEQUENTIAL: after Task 17]

**Action:** CREATE
**File:** `.github/workflows/spec-artifacts.yml`
**Traced to:** Scenarios: "Gate 21 fails a fix PR with no spec artifacts",
"Gate 21 accepts a declared-unavailable pipeline"
**Test:** `tests/spec-artifacts.bats`
**Validate:** `actionlint`; both scenarios pass
**Notes:** A standalone workflow, deliberately not a step inside `pr-tests.yml` — see
plan.md Decision 5: `pr-tests.yml`'s jobs are gated on the `changes` outputs, so a
spec-only or docs-only PR would skip exactly the check that matters. Fail when a PR
labelled fix/feature carries no spec directory AND no `temper: unavailable — …` line;
pass with a warning annotation when the line is present, recording the stated reason.

## [x] Task 19: `agents-scheduled.yml` + `actionlint.yml` [PARALLEL: with Task 20]

**Action:** CREATE
**File:** `.github/workflows/agents-scheduled.yml`, `.github/workflows/actionlint.yml`
**Traced to:** Scenarios: "Scheduled agents ship disabled by default",
"actionlint passes on every workflow"
**Validate:** `actionlint .github/workflows/` → zero findings
**Notes:** One workflow, a matrix over agent names, each entry calling
`tools/run-agent.sh`. Ships DISABLED with a one-line documented enable — nobody should
meet this system as five crons and an alert firehose on day one. It also carries
`workflow_dispatch`, which is both the dry-run path the README requires before scheduling
an agent, and the manual recovery path when a scheduled run is skipped.

## [x] Task 19b: Re-base the watcher-ring for a best-effort scheduler [SEQUENTIAL: after Task 19]

**Action:** MODIFY
**File:** `docs/runbooks/agent-routines.md`, `.agents/config.yml`,
`.agents/prompts/*.md`, `.github/workflows/agents-scheduled.yml`, `README.md`
**Traced to:** Scenario: "Liveness survives a late scheduler and catches a stopped one"
**Validate:** a ledger whose predecessor entry is 3 h old on a 12 h tolerance produces NO
escalation; one 30 h old DOES escalate; the staleness check fires when the newest entry
across ALL agents exceeds its window
**Notes:** The ring was calibrated against a scheduler that fires when it says it will. The
substitute — GitHub Actions cron — is best-effort and routinely delayed, so porting the rule
verbatim breaks it in both directions: false alarms in the common case, silence in the case
that matters. This is the general extraction risk made concrete — a rule correct in the
source and wrong here because an assumption underneath it changed. Note it as such in the
runbook, because the next person to move this system somewhere else needs the same warning.

Three changes:

1. **Elapsed time, not calendar day.** "Did the agent before me write TODAY's entry" becomes
   "did it write within the last `liveness.max-age-hours`" (config, default comfortably past
   normal cron drift — start at 12 h for a daily agent). Delay is tolerated; death is still
   caught. Escalate on the AGE of the newest entry, never on the count of consecutive
   misses, since a miss is now an ordinary event.
2. **Name the ring's blind spot.** Every agent stopping together is invisible to a ring —
   there is nobody left to notice the absence. That is not hypothetical here: **GitHub
   disables scheduled workflows automatically after ~60 days without repository activity**,
   and a template repo is precisely the low-activity case. Add an external staleness check
   over the whole ledger (newest entry across ALL agents older than its window ⇒ S2), and
   state the auto-disable in the README's "turning on the routines" section with the manual
   re-enable step, since no in-repo mechanism can restore it.
3. **Say why the alert may be noisy.** An escalation an operator learns to ignore is worse
   than no escalation. The runbook must state the tolerance, why it is that number, and that
   tightening it below the scheduler's real drift converts liveness detection into alert
   fatigue — which ends with the check switched off and nothing watching.

## [x] Task 20: Gate 22 — the harness guard tests [PARALLEL: with Task 19]

**Action:** CREATE
**File:** `tests/harness-guards/`
**Traced to:** Scenarios: "Reviewer identity comes from a marker", "The comment collector
reads both comment homes", "Paginated reads slurp before filtering", "Concurrency groups
are scoped per issue or pull request", "A bot sender cannot start the loop", "A nightly
failure reaches a human automatically", "Auto-triage that produced nothing fails on purpose"
**Validate:** the suite fails when any pinned string is removed from a workflow file; the
count of `literal`/`regex` assertions EQUALS the count of such entries in Task 6b's
`pins.json` — a guard suite smaller than the inventory is a silently dropped lesson
**Notes:** This task now EXECUTES the pin list written in Task 6b; it does not author it.
That inversion is deliberate: authoring the pins here, after Tasks 7–10 had already
substituted the workflows, would pin whatever survived and report green on anything lost.
Read `tests/harness-guards/pins.json` and turn each `literal`/`regex` entry into an
assertion over the extracted workflow file, carrying its `why` verbatim as the test's own
comment — the incident is the reason the assertion exists and a rule without its reason
gets deleted by the next person.

These text-pin the load-bearing strings inside the agent workflows themselves. Everything
else tests the product; nothing else tests the machine that builds it. Verify each guard
by deleting the pinned string and watching the test go red — a guard never seen red is a
guard not known to work. `semantic-manual` entries get no assertion here; they were
discharged by hand in Task 10b and the suite must state that in a comment rather than
silently omitting them.

## [x] Task 21: `tools/init.sh` — the adoption interview [SEQUENTIAL: after Task 20]

**Action:** CREATE
**File:** `tools/init.sh`
**Traced to:** Scenarios: "init.sh is idempotent", "init.sh leaves no unresolved placeholder"
**Test:** `tests/init-idempotent.bats`
**Validate:** run twice with identical answers → second run yields an empty diff; then
`grep -r '{{' .` → zero hits outside `ADOPTING.md`
**Notes:** Asks the adopter's questions once (product, health-read access, alert channel,
runner type, model ids per role, subscription-or-API-key per provider), rewrites every
placeholder, offers to delete the example, and prints what remains manual (secrets, app
install, ledger orphan branch, dry-runs, **floor calibration**, branch protection LAST).
Idempotent, re-runnable, no network calls, completes in seconds.

**It gates the event-driven agents on adapter status.** After the provider question, read
that adapter's `ADAPTER_STATUS`. If `verified`, minimal mode is as specified: steward and
review live, routines disabled. If `unverified`, `steward.yml` and `review.yml` ALSO ship
disabled, and init prints the honest version:

    Provider 'codex' is an UNVERIFIED STUB — its flags have never been run.
    The steward and PR review are disabled so your first pull request is green.
    The 22 gates are live now and do not depend on any agent CLI.
    To finish: tools/providers/codex.sh  (docs: <URL>)  -> set ADAPTER_STATUS=verified
               then re-run tools/init.sh to enable the steward and review.

This is Decision 8. Without it the quickstart walks a Codex adopter straight into a red
first issue — the steward fires, the stub exits non-zero, and the very action the README
opens with fails. Disabling is the honest branch: the gauntlet genuinely does work on day
one for every provider, because no gate calls an agent CLI. Only the two agent-driven
workflows are held back, and the adopter is told exactly why and exactly what unlocks them.
Re-running init after finishing an adapter is the documented enable path, which is also why
init must be idempotent.

**It does NOT measure anything.** That was the original spec and it was self-contradictory:
measuring a coverage baseline on the reference stack means `mvn test` plus `npm ci`, and a
mutation baseline means PIT and Stryker — all network, all slow, in a script required to be
offline and instant. It also measured the wrong thing, since the example it measures is the
example it then offers to delete. Floors are written as the `unset` SENTINEL (Task 21b),
never as a number and never as `0` — a zero floor reads in the config exactly like a gate
someone switched off, and the adopter never learns the gauntlet is unarmed.

## [x] Task 21b: `tools/measure-floors.sh` — arm the ratchet against the adopter's own code [SEQUENTIAL: after Task 21]

**Action:** CREATE
**File:** `tools/measure-floors.sh` + the `unset`-sentinel handling in each ratchet gate
**Traced to:** Scenario: "Uncalibrated floors pass loudly, then arm against the adopter's own baseline"
**Test:** `tests/floors-sentinel.bats`
**Validate:** with floors `unset`, every ratchet gate exits 0 and prints
`floor not yet calibrated — run tools/measure-floors.sh against your product`; after a run
on a project with known coverage, each floor sits just under the measured value; running it
while `examples/` still exists REFUSES with a clear message
**Notes:** Explicitly online and explicitly slow — the opposite contract to init.sh, and the
README says so in those words. Covers line, branch, mutation and the bundle CEILING (which
ratchets the other way: freely down, justified up). Refusing to run while the example is
present is the mechanical guarantee behind SC12b; without it the easiest path — run it right
after init — silently calibrates to the toy service. Every floor it writes carries a comment
recording the date, the tool version and the measured value, because the ratchet policy's
"the measuring instrument changed" exemption is unusable without knowing which instrument
produced the number.

## [x] Task 22: PR (b) summary [SEQUENTIAL: after Task 21]

**Action:** CREATE
**File:** PR body
**Traced to:** Infrastructure: the prompt requires a per-PR plain-language summary
**Validate:** the body names what is new and what is stubbed, and says plainly that two of
four adapters are unverified stubs (Codex, Gemini CLI) while claude-code and
compatible-endpoint ship working

---

# PR (c) — Example product + README/docs polish

## [x] Task 23: The example product [SEQUENTIAL: after Task 22]

**Action:** CREATE
**File:** `examples/`
**Traced to:** Scenario: "A fresh instantiation is green on day one"
**Test:** the example's own unit, integration and acceptance tests
**Validate:** the full blocking gauntlet runs green against `examples/` on this repo's CI
**Notes:** ~200 lines plus tests, on the reference stack, so the gauntlet demonstrably
runs and the adopter can open issue #1, watch the steward triage it, see two reviews and
the gates fire, and perform their first human merge — the whole loop before their real
product is wired in. It must carry enough shape to exercise each gate: a migration, an
architecture boundary, a Gherkin acceptance spec, a frontend component. `init.sh` offers
to delete it.

**Budget the config surface separately and say so.** The ~200-line cap is the prompt's, and
it applies to the PRODUCT. Arming 12 gates across two toolchains needs a `pom.xml` carrying
Surefire, Failsafe, JaCoCo, ArchUnit + freeze store, PIT, Cucumber, Flyway and
maven-enforcer, plus `package.json`, `stryker.conf`, `playwright.config`, vitest thresholds,
eslint and a bundle budget — hundreds of lines the adopter must read and adapt. That
scaffolding, not the toy service, is the real adoption cost, and it was unowned. Count it,
report the figure in the PR (c) summary, and give every config file a header comment naming
which gate it arms and where the same gate's contract is documented for other stacks.

## [x] Task 23b: Document the gate tiers and the promotion step [SEQUENTIAL: after Task 23, BLOCKS Task 24]

> **Scope reduced** (design.md contradiction 3): the tier SPLIT now happens in Task 9, at
> extraction time, because job names are branch-protection context strings and are frozen
> the moment they are written — splitting later would mean renaming them, which is the one
> thing the freeze rule forbids. What remains here is documentation and verification: the
> two tiers' context strings in `branch-protection.md`, the promotion step in
> `QUALITY-GATES.md` with its one-week expectation, and the timing measurement.

**Action:** MODIFY
**File:** `.github/workflows/pr-tests.yml`, `docs/QUALITY-GATES.md`,
`docs/runbooks/branch-protection.md`
**Traced to:** Scenario: "The fast tier is green in minutes; the full tier is opt-in"
**Validate:** on a fresh instantiation the FAST tier completes in ≈2 minutes with no
container pull and no browser download; the FULL tier runs, reports, and is documented as
not-yet-required; branch-protection.md lists the exact context strings for each tier
**Notes:** Two tiers, both LIVE — the difference is which are marked required, not which
run. Nothing is descoped and no gate becomes advisory permanently.

- **FAST** (day one, safe to require immediately): unit tests, lint, secret scan, build
  hygiene, the ratchet guards (gate 9), the harness guards (gate 22), gate 21. No
  Testcontainers, no browsers, no network beyond dependency resolution.
- **FULL** (enabled, reporting, promoted by the adopter in one documented step):
  integration against the real dependency, migration validation, e2e + axe, diff-scoped
  mutation, bundle budget.

Why tier rather than trim: a cold first run on this stack pulls Maven Central, `npm ci`, a
Postgres image and a Playwright browser — slow, and every one is a network dependency that
can flake on the adopter's first impression. A first PR that goes red because an image pull
timed out teaches them the gauntlet is unreliable, which is the opposite of the intended
lesson. Promotion is a documented one-liner in `branch-protection.md`, listed in the README's
setup order immediately before branch protection itself, so the full set becomes binding as
soon as the adopter has seen it pass once.

The tier split must NOT become a place to hide a slow gate forever: `QUALITY-GATES.md`
states that FULL-tier promotion is expected within the first week, and every gate keeps its
"what a failure means" row unchanged in the inventory.

## [x] Task 24: Ship every floor as an `unset` sentinel and prove day-one green [SEQUENTIAL: after Task 23]

**Action:** MODIFY
**File:** `docs/QUALITY-GATES.md`, the reference-stack gate configs
**Traced to:** Scenarios: "A fresh instantiation is green on day one",
"Uncalibrated floors pass loudly, then arm against the adopter's own baseline"
**Validate:** every blocking gate reports success or skipped on a fresh PR; no gate fails;
`grep` finds no numeric floor anywhere in the shipped configs — every one is the sentinel
**Notes:** The ratchet's promise is "floors only move up from where YOU are", not "start at
someone else's finish line" — and not "start at the toy example's finish line" either. The
source product's measured numbers (line ≥92%, branch ≥84%, PIT ≥89%, Stryker ≥96%, bundle
≤400 KiB) are recorded in `docs/QUALITY-GATES.md` as a WORKED EXAMPLE of what a calibrated
gauntlet looks like after months of ratcheting — clearly labelled as one team's result and
never as a default. Shipping them as defaults is what makes every first PR permanently red.

Day-one green is therefore achieved by floors being *uncalibrated*, not by floors being
*low* — and the difference is visible to the adopter, because an uncalibrated gate says so
in its own output on every run until they calibrate it.

## [x] Task 25: `README.md` to the 10-point outline [SEQUENTIAL: after Task 24]

**Action:** CREATE
**File:** `README.md`
**Traced to:** Scenario: "Non-extractable setup steps are documented, not simulated"
**Validate:** all ten sections present; the two required tables present; the setup order
stated explicitly with branch protection LAST
**Notes:** The two tables the prompt demands: (1) each gate → its tool, its config file,
where its floor lives; (2) every secret → which feature needs it → what happens when it
is missing. Lead the cost section with the subscription model, because it is the normal
case; the only per-token spend is the optional second-reviewer key, and losing it costs a
second opinion, not the system. Write troubleshooting as SYMPTOMS: "my PR hangs waiting on
a check" → required check behind a `paths:` filter; "I tagged the agent and nothing
happened" → bot sender or a concurrency eviction; "the referee says a review is missing
but I can see it" → wrong comment endpoint. State that Routine schedules live in a vendor
scheduler and branch protection is an admin setting, and point at the runbooks.

## [x] Task 26: `ADOPTING.md` — the placeholder map [SEQUENTIAL: after Task 25]

**Action:** CREATE
**File:** `ADOPTING.md`
**Traced to:** Scenario: "init.sh leaves no unresolved placeholder"
**Validate:** every distinct `{{PLACEHOLDER}}` token in the tree has a row naming its
file and what goes there
**Notes:** A placeholder without a row is invisible — the adopter never learns it needed a
value. Generate the row list mechanically from a grep so it cannot drift.

## [x] Task 27: `LICENSE`, `CHANGELOG.md`, `CONTRIBUTING.md` [PARALLEL: with Task 26]

**Action:** CREATE
**File:** `LICENSE`, `CHANGELOG.md`, `CONTRIBUTING.md`
**Traced to:** Infrastructure: standard plumbing + the upgrade path
**Validate:** files exist; CHANGELOG has a v0.1.0 entry
**Notes:** MIT or Apache-2.0. The upgrade note tells the truth: template repos copy once,
so adopters upgrade by diffing against release notes — which is why the harness stays
confined to `.agents/`, `.github/` and `tools/`, so that diff stays small.
`CONTRIBUTING.md` routes each new incident-derived rule upstream, so lessons accumulate
here instead of dying in forks.

## [x] Task 28: Retire the build prompt from the tree [SEQUENTIAL: after Task 27]

**Action:** MODIFY
**File:** `agentsdlcrepoprompt.md`
**Traced to:** Scenario: "De-identification sweep finds zero source-project traces"
**Validate:** `tools/check-deidentified.sh` → exit 0
**Notes:** It is the build input, not a template artifact, and it names the source
project. Delete it or move it out of the published tree.

## [x] Task 29: Full-tree de-identification sweep [SEQUENTIAL: after Task 28]

**Action:** MODIFY
**File:** whatever the sweep flags
**Traced to:** Scenario: "De-identification sweep finds zero source-project traces"
**Validate:** `tools/check-deidentified.sh` over content, file names AND commit messages
→ zero hits, INCLUDING `.temper/specs/**`

**RESOLVED during PR (a) — kept here as the record of what was done and why.** An
independent sweep after PR (a) found the shipped tree clean but **10 hits inside
`.temper/specs/agent-sdlc-template/*.md`** — `plan.md` (3), `tasks.md` (4), and one each in
`intent.md`, `design.md`, `quickstart.md`. They were the build record of the template
itself, naming the source repository by absolute path because that is what they describe.

Resolution taken: **sanitized in place**, not retired. The absolute path became
`{{SOURCE_REPO}}`, the commit-identity example became `<project>-agent@<project>.local`, and
Task 1's validate line — which spelled both brand terms literally in order to grep for them,
the same self-referential trap as the scanner in Task 12 — now reads
`grep -ricf .temper/evidence/deident-terms.txt`. The real path is recorded once, in
`.temper/evidence/source-repo-path.txt`, which is gitignored; build agents receive it in
their prompt instead. Sanitizing rather than retiring keeps the spec directory as a worked
example of what a Temper spec looks like, which is the only one an adopter has on day one.

This task's remaining job is to re-run the sweep over the whole tree at the end and confirm
it is still zero — including `.temper/specs/**`.

They are also committed, and `.temper/specs/` is a directory the template genuinely ships,
since gate 21 requires a spec directory in the diff of every fix/feature PR. So this leaks
unless it is handled deliberately. Decide and record which:
- **Sanitize in place** — rewrite every source reference to `{{SOURCE_REPO}}` / "the source
  repository". Keeps the build record, which is itself a worked example of what a Temper
  spec directory looks like — useful to an adopter, and the only one they will have on
  day one.
- **Retire alongside the build prompt** (Task 28) — move to an untracked archive and ship
  `.temper/specs/` holding only the pipeline's own templates.

Do not resolve it by adding `.temper/specs/` to the sweep's exclude list. An exclude added
to turn a red check green is exactly what the ratchet policy calls suppression, and this is
the one check whose entire value is that it has no carve-outs.

## [x] Task 30: actionlint over every workflow [SEQUENTIAL: after Task 29]

**Action:** MODIFY
**File:** `.github/workflows/*`
**Traced to:** Scenario: "actionlint passes on every workflow"
**Validate:** `actionlint .github/workflows/` → zero findings
**Notes:** The only mechanical proof that ~3,100 lines of extracted YAML survived
substitution. A placeholder dropped inside an expression is a startup failure, and startup
failures do not create status checks — they go quiet rather than red.

## [x] Task 31: End-to-end fresh-instantiation rehearsal [SEQUENTIAL: after Task 30]

**Action:** MODIFY
**File:** whatever the rehearsal breaks
**Traced to:** Scenarios: "A fresh instantiation is green on day one", "init.sh is
idempotent", "A gate whose stack is absent reports skipped, not missing"
**Validate:** clone to a scratch dir → run `init.sh` → open a PR → every blocking gate
reports success or skipped; then delete the frontend and confirm its gates report
"skipped", not missing
**Notes:** This is the adoption path, and the adoption path is the product. Under 30
minutes is the target.

## [x] Task 32: Verify the source repository is untouched [SEQUENTIAL: after Task 31]

**Action:** VERIFY
**File:** `.temper/evidence/source-manifest.sha256`
**Traced to:** Scenario: "The source repository is never written to"
**Validate:** re-checksum matches Task 0 exactly; `git status --porcelain` in the source
repo is empty; `git rev-parse HEAD` unchanged

## [x] Task 33: PR (c) summary + the honest closing statement [SEQUENTIAL: after Task 32]

**Action:** CREATE
**File:** PR body
**Traced to:** Infrastructure: the prompt's final quality-bar item
**Validate:** the body states plainly what was NOT built and what the adopter must do by
hand
**Notes:** At minimum: two of four provider adapters are unverified stubs (Codex, Gemini CLI);
Routine
schedules and branch protection cannot be committed and are manual; secrets, the GitHub
app install and the ledger orphan branch are manual; gate 18's body is a documented shell;
the deploy-time backup-restore gate is documented but not wired to any real environment.
