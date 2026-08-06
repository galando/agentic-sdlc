# Intent: Autonomous-Agent SDLC Template Repository

**Created:** 2026-08-04
**Ticket:** none (source: `agentsdlcrepoprompt.md`, 571 lines, treated as the specification)
**Complexity:** complex

---

## Problem

A working autonomous-agent SDLC exists today in exactly one place: a private
Java/Spring + React product repository. It has been running in production for months
and its value is not the idea — it is the ~5,600 lines of accumulated incident
knowledge welded into those files. Concretely: the reason `claude.yml` scopes its
concurrency group per-issue rather than globally; the reason the referee slurps
paginated comment pages *before* filtering; the reason the review workflow files an
issue instead of commenting; the reason a required check is skipped with a job-level
`if:` and never a workflow-level `paths:` filter. Each of those is a line of YAML that
looks arbitrary and is actually a postmortem.

Nobody else can use any of it, because it is entangled with one product: its name, its
domain, its PromQL metric names, its Dutch estate-agency vocabulary, its VPS secrets,
and ~40 of its issue numbers.

The deliverable is a GitHub **template repository** — process scaffolding only — that a
stranger can instantiate and reach all-green CI on within the first hour, running the
agents on Claude Code, Codex, Gemini CLI or anything else by editing one config file.

The failure mode this plan exists to prevent is **regeneration**. A freshly written
`claude-review.yml` from the prompt text would be a plausible guess with every incident
lesson silently absent, and it would look fine. Extraction is not a shortcut here; it is
the whole point.

## Success Criteria

- [x] SC1 — The finished tree contains zero traces of the source project: no project
      name, domain, URL, issue/PR number, author handle, or bespoke domain noun, in file
      content, file names, commit messages or code comments alike.
  Validate: scenario — covered by "De-identification sweep finds zero source-project traces"
- [x] SC2 — All 22 gates from the prompt (1–22, including the new gate 21) appear in
      `docs/QUALITY-GATES.md` with the ratchet policy intact; the reference stack
      (Java/Spring Boot + React/TypeScript) carries a real, executing implementation for
      each blocking gate.
  Validate: code — every gate row names a workflow job that exists in `.github/workflows/`
- [x] SC3 — Every gate job skips cleanly via a job-level `if:` when its stack is absent,
      and no required status check is ever gated behind a workflow-level `paths:` filter.
  Validate: scenario — covered by "A gate whose stack is absent reports skipped, not missing"
- [x] SC4 — `tools/run-agent.sh <agent> --dry-run` prints the exact command that would be
      executed, for each of the four providers, without invoking anything.
  Validate: scenario — covered by "Dry-run prints the exact command for every provider"
- [x] SC5 — `tools/ledger.sh` demonstrably round-trips against a real orphan branch:
      append, read, latest, trend — with a captured transcript.
  Validate: scenario — covered by "Ledger round-trips on a fresh orphan branch"
- [x] SC6 — Gate 21 mechanically fails a PR labelled fix/feature whose diff carries no
      spec directory and whose body carries no `temper: unavailable — …` line.
  Validate: scenario — covered by "Gate 21 fails a fix PR with no spec artifacts"
- [x] SC7 — `tools/init.sh` is idempotent, makes no network calls, resolves every
      `{{PLACEHOLDER}}`, offers to delete the example, and prints what remains manual.
  Validate: scenario — covered by "init.sh is idempotent" and "init.sh leaves no unresolved placeholder"
- [x] SC8 — Every workflow file parses and passes actionlint with zero findings.
  Validate: scenario — covered by "actionlint passes on every workflow"
- [x] SC9 — `.agents/config.yml` is the single provider config; it addresses models by
      ROLE (`judge`, `execute`, `challenge`), and no vendor name appears in any workflow,
      runbook or agent prompt.
  Validate: scenario — covered by "No vendor name leaks into workflows, runbooks or prompts"
- [x] SC10 — A missing optional credential degrades a check and never cancels or fails
      one: reviewer B absent ⇒ B and the referee skip with a warning, A's review stands,
      the PR is not failed.
  Validate: scenario — covered by "Missing second-reviewer credential degrades, never fails"
- [x] SC11 — Minimal mode is the default: on a VERIFIED adapter the steward, PR review and
      gates are live and all scheduled agents ship disabled, each with a documented
      one-line enable.
  Validate: scenario — covered by "Scheduled agents ship disabled by default"
- [x] SC11b — On an UNVERIFIED adapter, init.sh additionally ships the steward and PR
      review disabled and says why, so day-one green holds for every provider. The gates
      remain live on all providers, because no gate invokes an agent CLI.
  Validate: scenario — covered by "An unverified adapter disables the agents, not the gauntlet"
- [x] SC12 — A fresh instantiation reaches all-green CI on the bundled example product
      (~200 lines + tests) with no adopter code. Floors ship UNCALIBRATED (an explicit
      `unset` sentinel, not a number), and the ratchet is armed only by
      `tools/measure-floors.sh` run against the adopter's OWN product.
  Validate: scenario — covered by "A fresh instantiation is green on day one" and
      "Uncalibrated floors pass loudly, then arm against the adopter's own baseline"
- [x] SC12c — The blocking gates are tiered by cost, not by importance: a FAST tier
      (no containers, no browsers) is green in ≈2 minutes and safe to require on day one;
      a FULL tier runs and reports from day one and is promoted to required in one
      documented step. No gate is removed, disabled or made permanently advisory. The
      example's config surface is counted and reported, not left as unowned adoption cost.
  Validate: scenario — covered by "The fast tier is green in minutes; the full tier is opt-in"
- [x] SC12b — No floor is ever derived from the example product. A ratchet calibrated to
      a toy service that init.sh then offers to delete is a floor the adopter can never
      meet, which produces the same abandonment that aspirational floors do.
  Validate: scenario — covered by "Uncalibrated floors pass loudly, then arm against the adopter's own baseline"
- [x] SC16 — Liveness detection is re-based for the substitute scheduler: escalation keys
      on the AGE of the predecessor's newest entry against a configured tolerance, never on
      a count of consecutive misses; and an external staleness check covers the case a ring
      structurally cannot see — every agent stopping at once, which GitHub's ~60-day
      auto-disable of scheduled workflows makes a real scenario for a template repo.
  Validate: scenario — covered by "Liveness survives a late scheduler and catches a stopped one"
- [x] SC13 — The source repository at `{{SOURCE_REPO}}` is byte-identical
      before and after the build; nothing is ever written to it.
  Validate: scenario — covered by "The source repository is never written to"
  NOTE: the "byte-identical" half is literally false and honestly so — the source
  repository moved during the build window because its owner kept working in it
  (ordinary commits and merges, verified by author and timestamp). What this criterion
  actually protects is that THIS build never wrote there, and that holds: every access
  was a read, and the checksum manifest was recorded for exactly this comparison.
- [x] SC14 — What cannot be extracted is documented rather than faked: Routine schedules
      (vendor scheduler) and branch protection (admin setting) each become an explicit,
      ordered setup step that the README points at.
  Validate: scenario — covered by "Non-extractable setup steps are documented, not simulated"
- [x] SC15 — The load-bearing strings inside the agent workflows are text-pinned by
      harness guard tests (gate 22), each carrying its incident as a comment.
  Validate: scenario — covered by the four harness-guard scenarios (marker, endpoints,
      pagination, concurrency)

## Constraints

- **Extraction is mandatory where a source file exists.** Files in the "copy" buckets
  are copied and genericized, never rewritten from the prompt. The prompt is the
  acceptance checklist; the source repo is the source of truth.
- **The source repo is strictly read-only.** No write, no commit, no branch, no
  `git config`, no temp file inside it.
- **Reference stack is Java/Spring Boot (Maven, Flyway) + React/TypeScript** — chosen to
  mirror the source so the extracted gate configs port as tested artifacts. All other
  stacks are documented contracts with cleanly-skipping jobs.
- **TWO working adapters; two clearly-marked stubs.** Working: `claude-code` and
  `compatible-endpoint` — both invocations are evidenced by the source repo's production
  use, which is the classification rule (evidence, not count). Stubs: `codex`,
  `gemini-cli`. The prompt forbids inventing unverified vendor flags — a stub with the
  exact command shape and a docs link beats a plausible invocation that silently does
  nothing. `compatible-endpoint` must NOT be demoted for symmetry: it is the only delivery
  path for the `challenge` role, so a stub there leaves reviewer B and the challenger agent
  with no execution path on any provider. See plan.md Decision 3.
- **Three PRs, fixed order:** (a) extraction + genericization, (b) new plumbing, (c)
  example + docs polish. Each ends with a plain-language summary of what was extracted
  unchanged, genericized, newly written, and stubbed.
- **Green on day one outranks rigour of the floors.** Aspirational floors on an empty
  product make every first PR permanently red and the template gets deleted the same
  afternoon.
- **No baked-in answers.** Anything that is the adopter's decision is a `{{PLACEHOLDER}}`
  with a one-line comment saying what belongs there.
- Every incident-derived comment is *rewritten as a neutral lesson*, never deleted —
  those comments are the accumulated value being transferred.

## Target Users

- **The adopter (a stranger with a GitHub repo and one agent-CLI subscription):** gets a
  working agent SDLC in under 30 minutes instead of six months of incidents.
- **The adopter's agents:** get guardrails, a ledger, a headless playbook and a gauntlet
  that make their PRs reviewable by a human who was not in the session.
- **The adopter's operator (the human who merges):** gets ~10 min/week and one steering
  channel (`agent-modes.md`) rather than five crons and an alert firehose.
- **Upstream (this template's maintainers):** `CONTRIBUTING.md` routes each new
  incident-derived rule back here, so lessons accumulate instead of dying in forks.

---

## Scenarios (BDD)

### Feature: Autonomous-Agent SDLC Template Repository

#### Happy Path

```gherkin
Scenario: De-identification sweep finds zero source-project traces
  Given the template tree has been built from the source repository
  And the term list lives at .temper/evidence/deident-terms.txt, which is gitignored
    and never committed
  When I run a case-insensitive grep for the source project's name, its domain,
    its bespoke domain nouns and its owner handle across all tracked files,
    file names and commit messages
  Then the total hit count is exactly 0
  And the sweep covers tools/check-deidentified.sh itself with no self-exclusion,
    which passes only because the shipped scanner takes --terms <file> and names
    nothing on its own
  And a list-free reviewer pass has recorded a verdict for every extracted file,
    because a term list cannot catch a domain that survives in metric names,
    fixtures and dated narratives
  And the same sweep is wired as a pre-PR step so it runs before every PR is opened
  Note: integration
```

```gherkin
Scenario: A lost extraction lesson fails the build
  Given tests/harness-guards/pins.json was written by reading the SOURCE workflows
    before any of them was genericized
  And every entry quotes its source string verbatim with a line number, its neutral
    "why", and a pin_kind of literal, regex or semantic-manual
  When the gate-22 suite runs against the extracted tree
  Then every literal and regex entry is asserted, and the assertion count equals the
    entry count — a suite smaller than the inventory fails on that ground alone
  And deleting any one pinned string from a workflow turns the suite red
  And each semantic-manual entry, which cannot be pinned because the string itself had
    to change, is named in the suite's output as hand-discharged rather than omitted
  Note: integration
  Why this exists: guards authored after substitution pin whatever survived it, so a
    lesson dropped during extraction would be pinned in its absent state and go green
    permanently. Writing the inventory first makes substitution answer to an assertion
    that already existed.
```

```gherkin
Scenario: Ledger round-trips on a fresh orphan branch
  Given a scratch git repository with a remote and no ledger branch
  When I create the orphan branch as the runbook instructs
  And I run "tools/ledger.sh append ops '{\"date\":\"2026-08-04\",\"verdict\":\"green\",\"summary\":\"first run\",\"metrics\":{\"disk_pct\":41}}'"
  And I run "tools/ledger.sh read ops", "tools/ledger.sh latest" and "tools/ledger.sh trend ops disk_pct"
  Then read prints the entry back with an "agent":"ops" field added
  And latest prints one line per configured agent showing "2026-08-04  green" for ops
  And trend prints "2026-08-04 41"
  And the caller's working tree and current branch are unchanged
  Note: integration
```

```gherkin
Scenario: Dry-run prints the exact command for every provider
  Given .agents/config.yml with a role-to-model map and a prompt at .agents/prompts/health.md
  When I set the provider to each of claude-code, codex, gemini-cli and compatible-endpoint
  And I run "tools/run-agent.sh health --dry-run" for each
  Then each run prints the full argv that would be executed, including the resolved
    model id for the role, the headless flag and the prompt file path
  And no provider CLI is invoked and no network call is made
  And the two stub adapters additionally print an "UNVERIFIED STUB" banner and a
    documentation URL for the flags a maintainer must confirm
  Note: integration
```

```gherkin
Scenario: A fresh instantiation is green on day one
  Given a repository created from the template with the example product left in place
  When init.sh has run and the first pull request is opened
  Then every blocking gate reports a conclusion of success or skipped
  And no gate reports failure
  And init.sh has made no network call and has run to completion in seconds
  Note: integration
```

```gherkin
Scenario: Liveness survives a late scheduler and catches a stopped one
  Given the scheduled agents run from GitHub Actions cron, which is best-effort
  And liveness.max-age-hours is 12 for a daily agent

  When an agent checks its predecessor and the newest predecessor entry is 3 hours old
  Then no escalation is raised, because ordinary scheduler drift is not death

  When the newest predecessor entry is 30 hours old
  Then the agent escalates on the AGE of that entry, not on a count of consecutive misses

  When every agent has stopped and the newest entry across ALL agents exceeds its window
  Then the external staleness check raises an S2, because a ring cannot detect its own
    total absence — there is nobody left to notice
  And README.md states that GitHub disables scheduled workflows after about 60 days of
    repository inactivity, and gives the manual re-enable step
  Note: integration
  Why this exists: the rule was calibrated against a punctual vendor scheduler. Ported
    verbatim onto a best-effort one it fails in both directions — false alarms when a run
    is merely late, silence when everything stops at once — and an operator who learns to
    ignore a noisy liveness alert has no liveness detection at all.
```

```gherkin
Scenario: The fast tier is green in minutes; the full tier is opt-in
  Given a fresh instantiation with the example product in place
  When the first pull request opens
  Then the FAST tier — unit tests, lint, secret scan, build hygiene, the ratchet guards,
    the harness guards and gate 21 — completes in about two minutes
  And it pulls no container image and downloads no browser
  And the FULL tier — real-dependency integration, migration validation, end-to-end
    with axe, diff-scoped mutation and the bundle budget — also runs and reports
  And no gate is disabled, skipped-by-configuration, or removed from the inventory
  And branch-protection.md lists the exact context strings for each tier separately,
    with the FAST tier marked safe to require immediately
  And QUALITY-GATES.md states that promoting the FULL tier is expected within the
    first week and is a single documented step
  Note: integration
  Why this exists: a cold first run on the reference stack resolves Maven Central, runs
    npm ci, pulls a Postgres image and downloads a Playwright browser. A first pull
    request that goes red because an image pull timed out teaches the adopter that the
    gauntlet is unreliable — the opposite of the intended lesson — and it does so at the
    single moment they are deciding whether to keep the template.
```

```gherkin
Scenario: An unverified adapter disables the agents, not the gauntlet
  Given a repository created from the template
  When I run init.sh and choose a provider whose adapter declares ADAPTER_STATUS=unverified
  Then steward.yml and review.yml are written disabled, alongside the scheduled agents
  And init prints which adapter file to finish, its documentation URL, and that
    re-running init after setting ADAPTER_STATUS=verified is what enables them
  And every one of the 22 gates remains live, because no gate invokes an agent CLI
  And opening the first issue produces no failing run

  When I instead choose the provider whose adapter declares ADAPTER_STATUS=verified
  Then steward.yml and review.yml are written enabled and only the routines are disabled
  Note: integration
  Why this exists: the stubs correctly exit non-zero when run, but minimal mode ships the
    steward live — so a Codex or Gemini adopter following the quickstart's "open issue #1"
    would go red on their first action. Adapter status is declared once, in the adapter
    itself, so there is no second list to drift.
```

```gherkin
Scenario: Uncalibrated floors pass loudly, then arm against the adopter's own baseline
  Given a repository created from the template where init.sh has run but
    tools/measure-floors.sh has not
  When a pull request opens
  Then every ratchet gate reports success with the message
    "floor not yet calibrated — run tools/measure-floors.sh against your product"
  And the gate does NOT report a numeric floor of 0, because a zero floor is
    indistinguishable in the config from a gate someone deliberately disabled
  And README.md and the init.sh closing checklist both list calibration as
    outstanding manual work, alongside secrets and branch protection

  When I later wire in my own product and run "tools/measure-floors.sh"
  Then it measures line, branch, mutation and bundle figures against MY code
  And writes each floor just under the measured value, replacing the sentinel
  And refuses to run while the bundled example is still present, so no floor can
    ever be derived from the example
  And every subsequent movement of that floor obeys the one-way ratchet
  Note: integration
  Why this exists: init.sh was specified as both "no network calls" and "measures the
    baselines", which cannot both hold on a stack whose measurement needs a dependency
    download. Splitting the two also removes a subtler trap — floors measured against a
    toy service the adopter is invited to delete are floors calibrated to code that no
    longer exists.
```

```gherkin
Scenario: Non-extractable setup steps are documented, not simulated
  Given the template contains no Routine schedule and no branch-protection configuration
  When I read README.md
  Then it states the setup order explicitly: create the ledger branch, add secrets,
    install the app, dry-run each agent prompt, schedule the routines, enable branch
    protection LAST
  And it explains that Routine schedules live in the vendor's scheduler and branch
    protection is an admin setting, neither of which can be committed to a repo
  And it links to docs/runbooks/branch-protection.md and docs/runbooks/agent-routines.md
  Note: manual
```

#### Error Paths

```gherkin
Scenario: Gate 21 fails a fix PR with no spec artifacts
  Given a pull request labelled "fix" whose diff touches source files
  And the diff contains no .temper/specs/<slug>/ directory
  And the PR body contains no "temper: unavailable" line
  When the spec-artifacts-present check runs
  Then the check fails
  And its output names both accepted remedies: commit the spec directory, or state
    "temper: unavailable — <real reason>" in the body
  Note: integration
```

```gherkin
Scenario: Gate 21 accepts a declared-unavailable pipeline
  Given a pull request labelled "fix" with no spec directory in the diff
  And the PR body contains the line "temper: unavailable — plugin marketplace unreachable from the runner"
  When the spec-artifacts-present check runs
  Then the check passes
  And it emits a warning annotation recording the stated reason
  Note: integration
```

```gherkin
Scenario: Missing second-reviewer credential degrades, never fails
  Given a pull request in a repository where the optional challenge-role credential is unset
  When the review workflow runs
  Then reviewer A's review is posted normally
  And reviewer B's job emits a warning that the credential is absent and performs no review
  And the referee job is skipped because reviewer B did not run
  And the pull request's checks are not failed by any of the three
  Note: mock
```

```gherkin
Scenario: A gate whose stack is absent reports skipped, not missing
  Given a repository instantiated from the template with the frontend deleted
  When a pull request is opened
  Then every frontend gate job reports a conclusion of "skipped" via its job-level if:
  And a status check context exists for each required check
  And no required check is left permanently pending
  Note: integration
```

```gherkin
Scenario: Auto-triage that produced nothing fails on purpose
  Given the steward workflow ran on an issues.opened event
  And it posted no comment and pushed no branch
  When the visible-outcome step runs
  Then it posts a marker comment on the issue explaining that the run produced no outcome
  And it fails the job deliberately
  Note: unit
```

#### Edge Cases

```gherkin
Scenario: Reviewer identity comes from a marker, never from ordering
  Given the harness guard test suite
  When it reads the review workflow file
  Then it asserts that each reviewer prompt requires its comment's FIRST line to be the
    exact marker "<!-- reviewer: <role> -->"
  And it asserts that downstream selection matches on that marker string
  And the test comment records the lesson: status chatter from the same bot account
    lands in the same window and gets mistaken for a review
  Note: unit
```

```gherkin
Scenario: The comment collector reads both comment homes
  Given a pull request carrying one top-level conversation comment and one inline
    comment on a code line, both from the review bot
  When the collector step gathers agent output
  Then it queries both the issue-comments endpoint and the pull-request review-comments
    endpoint and merges the two result sets
  And it reports neither comment as missing
  And when it does report something missing, the message names every place it looked
  Note: unit
```

```gherkin
Scenario: Paginated reads slurp before filtering
  Given a pull-request thread with 250 comments spanning three API pages
  When the collector selects "the last matching comment"
  Then it slurps all pages, flattens them, and then filters
  And it returns exactly one comment overall, not one per page
  And a harness guard test pins the slurp-then-filter shape in the workflow file
  Note: unit
```

```gherkin
Scenario: Concurrency groups are scoped per issue or pull request
  Given the harness guard test suite
  When it reads the steward and review workflow files
  Then it asserts each concurrency group expression interpolates the issue or pull
    request number
  And it fails on any globally-scoped group
  And the test comment records the lesson: GitHub keeps one running plus one pending run
    per group, so a third event silently evicts the pending one
  Note: unit
```

```gherkin
Scenario: A bot sender cannot start the loop
  Given an issue comment created by an account whose sender type is Bot
  When the steward workflow evaluates its job-level if:
  Then the job does not run
  And the review workflow's handoff path files an issue rather than commenting,
    because issues.opened is the one trigger with no sender check
  And when the elevated token is absent it still files the issue and states loudly
    that the handoff to the steward did not happen
  Note: unit
```

```gherkin
Scenario: A nightly failure reaches a human automatically
  Given a nightly gate workflow whose job has failed
  When the workflow completes
  Then an if: failure() job calls the reusable notifier
  And the calling workflow declares permissions contents:read and issues:write, because
    a reusable workflow cannot hold more permission than its caller
  And the notifier opens or comments on a "[nightly] <gate> is failing" issue and sends
    the alert-channel ping
  Note: unit
```

```gherkin
Scenario: actionlint passes on every workflow
  Given every YAML file under .github/workflows/
  When actionlint runs across the directory
  Then it reports zero findings
  Note: integration
```

```gherkin
Scenario: init.sh is idempotent
  Given a freshly instantiated repository
  When I run tools/init.sh with a fixed set of answers
  And I commit the result and run tools/init.sh again with the same answers
  Then the second run produces an empty diff
  And neither run makes a network call
  Note: integration
```

```gherkin
Scenario: init.sh leaves no unresolved placeholder
  Given a freshly instantiated repository containing {{PLACEHOLDER}} tokens
  When tools/init.sh completes
  Then a grep for "{{" across the tree returns zero hits outside ADOPTING.md and the
    template's own documentation of the placeholder syntax
  And the script prints the remaining manual steps: secrets, app install, ledger branch,
    dry-runs, branch protection
  Note: integration
```

```gherkin
Scenario: No vendor name leaks into workflows, runbooks or prompts
  Given the finished template
  When I grep .github/workflows/, docs/runbooks/ and .agents/prompts/ for the names of
    any specific model vendor or model id
  Then the only hits are inside tools/providers/ and .agents/config.yml
  And every other reference addresses a model by its role: judge, execute or challenge
  Note: integration
```

```gherkin
Scenario: Scheduled agents ship disabled by default
  Given a freshly instantiated repository
  When I inspect the scheduled-agents workflow
  Then its schedule is present but inert, with a one-line documented enable
  And README.md instructs the adopter to enable them one at a time, each after an
    interactive dry-run of that agent's prompt
  Note: unit
```

```gherkin
Scenario: The source repository is never written to
  Given a recorded checksum of every tracked file in the source repository, taken
    before the build starts
  When all three pull requests have been produced
  Then re-checksumming the source repository yields an identical result
  And the source repository's git status is unchanged
  Note: integration
```

---

## Scenario Coverage Checklist

After implementation, verify each scenario has a passing test or a captured transcript:

- [x] De-identification sweep finds zero source-project traces → `tools/check-deidentified.sh`, `tests/deidentified.bats`
- [x] Ledger round-trips on a fresh orphan branch → `tests/ledger-roundtrip.bats` + captured transcript in the PR (a) body
- [x] Dry-run prints the exact command for every provider → `tests/run-agent-dryrun.bats`
- [x] A fresh instantiation is green on day one → a scratch clone + `tools/init.sh --answers` + `mvn clean verify -DskipITs` + `npm run lint/test:coverage/build`, all green (Task 23/31); a real GitHub Actions run was not exercised — no remote was pushed this session, see the PR (c) closing statement
- [x] Non-extractable setup steps are documented → `README.md` sections 5/6 and "The setup order, explicitly" (Task 25)
- [x] Gate 21 fails a fix PR with no spec artifacts → `tests/spec-artifacts.bats`
- [x] Gate 21 accepts a declared-unavailable pipeline → `tests/spec-artifacts.bats`
- [x] Missing second-reviewer credential degrades, never fails → `tests/harness-guards/review-collector.bats`, `run-agent-dryrun.bats` (`--check-credentials` exit 6)
- [x] A gate whose stack is absent reports skipped → `tests/harness-guards/pins.generated.bats` (job-level `if:` pins)
- [x] Auto-triage that produced nothing fails on purpose → `tests/harness-guards/pins.generated.bats` (steward-outcome-* pins)
- [x] Reviewer identity comes from a marker → `tests/harness-guards/review-collector.bats`, `pins.generated.bats`
- [x] The comment collector reads both comment homes → `tests/harness-guards/review-collector.bats`
- [x] Paginated reads slurp before filtering → `tests/harness-guards/review-collector.bats`
- [x] Concurrency groups are scoped per issue or PR → `tests/harness-guards/branch-protection-contexts.bats`, `pins.generated.bats`
- [x] A bot sender cannot start the loop → `tests/harness-guards/pins.generated.bats` (steward-bot-sender-gate)
- [x] A nightly failure reaches a human automatically → `tests/harness-guards/pins.generated.bats`
- [x] actionlint passes on every workflow → `actionlint .github/workflows/*.yml` (0 findings)
- [x] init.sh is idempotent → `tests/init-idempotent.bats`
- [x] init.sh leaves no unresolved placeholder → `tests/init-idempotent.bats` (mechanism proven on a controlled fixture; the full live-tree sweep is Task 29/31, PR (c))
- [x] No vendor name leaks → `tests/harness-guards/vendor-neutrality.bats`, which greps `.github/workflows/`, `docs/runbooks/` and `.agents/prompts/` for vendor and model names and asserts the only hits are in `tools/providers/` and `.agents/config.yml`. NOT `tools/check-deidentified.sh` — that scanner is term-agnostic by design and knows nothing about vendors; giving it a built-in vendor list would hand it project-specific strings of its own, which `tests/deidentified.bats` forbids. This line previously credited that scanner, so the claim was true and unguarded until the guard was written.
- [x] Scheduled agents ship disabled by default → `tests/harness-guards/agents-scheduled.bats`
- [x] The source repository is never written to → re-checksummed at Task 32; this build session never read or wrote any file under it. Its HEAD and working tree DID change since the Task 0 baseline — verified via `git log`/reflog to be the operator's own normal commits and PR merges (e.g. `786c13f fix(ci): ...`, `baf8de1 chore(temper): ...`, a dependabot bump) landing on the live repository during the build window, not a write from this session. See the PR (c) closing statement.
- [x] An unverified adapter disables the agents, not the gauntlet → `tests/harness-guards/adapter-gate.bats`
- [x] Liveness survives a late scheduler and catches a stopped one → config + runbook re-based in PR (b) (`tests/harness-guards/agents-scheduled.bats`); now behaviourally simulated end-to-end against a real ledger with deliberately backdated commits in `tests/agent-liveness.bats`, driving the new `tools/check-liveness.sh` (the mechanical age-arithmetic half of the rule described in `docs/runbooks/agent-routines.md` and `.agents/prompts/health.md`): a ~3h-old predecessor does not escalate, a ~30h-old one does (never on a miss count), a per-agent `max-age-hours` override is honoured, and an all-stopped ledger raises the documented S2. Verified red by inverting the age comparison and watching 4/7 cases fail before restoring it.
- [x] Uncalibrated floors pass loudly, then arm against the adopter's own baseline → sentinel half: `tests/floors-sentinel.bats`; measure-and-ratchet half: `tests/render-floors.bats`'s calibrated-floors case plus a real PIT run (89% mutation score) and a real Stryker run (42.9%) against the example (Task 23/24, PR (c)) — `tools/measure-floors.sh`'s own orchestration was exercised for its REFUSAL path only (it correctly refuses while `examples/` exists); its success path was not run end-to-end against a non-example product this session
- [x] The fast tier is green in minutes; the full tier is opt-in → tier split done at extraction (Task 9); FAST-tier jobs pull no container and no browser by construction (verified by reading `pr-tests.yml`) and complete in seconds locally; real GitHub Actions wall-clock timing was not measured — no remote was pushed this session
