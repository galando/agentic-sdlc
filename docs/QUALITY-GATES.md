# Quality gates — the gauntlet

> "Surround the agents with extreme constraints. In the end, I have very high
> confidence in the code they produce because they've had to run the gauntlet."

<!-- placeholder: {{PRODUCT_NAME}} — the product this repository builds. -->

Most {{PRODUCT_NAME}} code is written by agents. The operating assumption is that
**nobody reads every line** — trust comes from the gauntlet of automated constraints
below, not from who reviewed it. **Every gate here fails a build; none are advisory.**

Adapt the tool names to your stack, but keep every gate: **each one catches something the
others structurally cannot.** The "what each layer is FOR" ladder near the bottom is the
argument for that, gate by gate.

---

## The two tiers, and why they exist

The blocking gates are tiered **by cost, not by importance**. Both tiers are LIVE and both
report from day one. The difference is which are marked *required*.

- **FAST** — no container image, no browser download, no service container. Green in about
  two minutes on a cold cache. **Safe to mark required immediately.**
- **FULL** — pulls an image, downloads a browser, or runs mutation testing. Runs and
  reports from day one; **promoted to required in one documented step**
  (`docs/runbooks/branch-protection.md`), **expected within the first week.**

**Why tier rather than trim.** The threat to a green first pull request is
*infrastructure flakiness*, not gate strictness. A cold first run resolves a dependency
repository, installs packages, pulls a database image and downloads a browser — each a
network dependency that can flake, on the adopter's very first pull request. A first pull
request that goes red because an image pull timed out teaches them the gauntlet is
unreliable, which is the opposite of the intended lesson, at the exact moment they are
deciding whether to keep this template.

**The tier split is not a place to hide a slow gate forever.** Nothing is descoped, no gate
becomes permanently advisory, and every gate keeps its "what a failure means" row below
unchanged. Promotion is expected within the first week. A tier that quietly becomes
permanent is just an advisory gate with extra vocabulary.

---

## Gate inventory

<!-- {{PLACEHOLDER}} placeholder: a floor's symbolic representation (see the four floor tokens below); this occurrence documents the convention and is not itself a live token. -->

Every floor below is a **`{{PLACEHOLDER}}`**, never a number. See "Floors ship
uncalibrated" — this is not an omission, it is the design.

<!-- {{FLOOR_LINE}} {{FLOOR_BRANCH}} {{FLOOR_MUTATION}} {{CEILING_BUNDLE_KIB}} placeholder: each denotes "whatever floors.yml currently holds for that ratchet key" — the `unset` sentinel until tools/measure-floors.sh runs, then a calibrated number; rendered into the real tool configs by tools/measure-floors.sh / tools/render-floors.sh and never substituted here, by design — see "Floors ship UNCALIBRATED" below. -->



### Blocking — every pull request

| # | Gate | Context string | Tier | What a failure means |
|---|---|---|---|---|
| 1 | Unit tests — no database, no network | `fast-unit-tests` | FAST | A behaviour regression |
| 2 | Integration tests against the REAL dependency, full migration chain applied from scratch | `full-integration-tests` | FULL | Schema, wiring and serialisation bugs an in-memory substitute cannot reproduce |
| 3 | **Backend coverage ratchet** — line ≥ `{{FLOOR_LINE}}`, branch ≥ `{{FLOOR_BRANCH}}` | `fast-unit-tests` | FAST | New code landed without tests |
| 4 | **Architecture rules + freeze store** | `fast-unit-tests` | FAST | A NEW structural violation: a layering breach, field injection, a controller reaching into a repository. Existing violations are frozen; the store shrinks as they are fixed and may never be hand-edited to admit a new one |
| 6 | Lint, zero warnings, including framework-correctness rules | `fast-frontend-checks` | FAST | Dead code and bugs that otherwise need production traffic to appear |
| 7 | **Frontend tests + coverage ratchet** — separate floors for statements, branches, functions and lines | `fast-frontend-checks` | FAST | A behaviour regression, or untested new code |
| 8 | **Executable acceptance specs**, Given-When-Then | `fast-unit-tests` | FAST | The agreed business rules changed — stated in language a non-engineer can read without opening a test file |
| 9 | **RATCHET GUARD tests, one per stack** | `fast-unit-tests`, `fast-frontend-checks`, `fast-repo-hygiene` | FAST | A floor was lowered, a threshold deleted, an exclude widened, or a freeze store removed |
| 10 | **Migration validation** — duplicate versions, and a fresh-database apply | `full-migration-validation` | FULL | Duplicate version numbers, or a migration that will not apply cleanly to a fresh database |
| 11 | Secret scan | `fast-secret-scan` | FAST | A credential about to leak |
| 12 | **Fast dependency CVE gate** — high/critical across prod AND dev | `fast-frontend-checks` | FAST | An unapproved high/critical advisory — or an allowlisted one that was fixed, so its entry is now stale |
| 13 | **Build hygiene** — banned duplicate dependencies, and a toolchain **window** (floor AND ceiling, the ceiling being the newest version CI actually tests) | `fast-unit-tests` | FAST | Runs BEFORE compile, so a wrong toolchain fails loudly instead of producing a confusing downstream error. The ceiling matters as much as the floor: an unbounded range let an untested bleeding-edge JDK pass the loud gate and die deep inside a mocking library instead |
| 14 | Design-system / brand guardrail | `fast-frontend-checks` | FAST | Visual drift away from the agreed system |
| 15 | **End-to-end in a real browser + accessibility** (WCAG 2.1 A/AA) | `full-e2e-accessibility` | FULL | Everything above can be green while the built artifact is blank. The same gate also runs nightly against the full suite — see the nightly table |
| 17 | **Diff-scoped mutation check** — floor `{{FLOOR_MUTATION}}`, skipped below ~20 mutants | `full-mutation-on-diff` | FULL | Assertions were weakened in the changed code — caught at pull-request time rather than the next morning |
| 19 | **Bundle-size budget** — ceiling `{{CEILING_BUNDLE_KIB}}` | `full-bundle-budget` | FULL | The shipped bundle grew: a heavyweight import, a barrel that defeats tree-shaking, or a large dependency landing in the entry chunk |
| 21 | **Spec artifacts present** | `fast-spec-artifacts` | FAST | A pull request labelled fix or feature carries no spec directory in its diff and no `temper: unavailable — …` line in its body |
| 22 | **HARNESS tests** — text-pin the load-bearing strings inside the agent workflows (`tests/harness-guards/`), and exercise the tooling those workflows call (`tests/`) | `fast-harness-guards` | FAST | The agents' own plumbing has no other safety net. If a collector stops reading an endpoint, or a prompt loses the line that makes an agent identifiable, **every run still goes GREEN** and the loss shows up only as a wrong conclusion later. Both halves run as separate steps of the one job: until this was fixed CI ran only the guards, and the 142 tests under `tests/` — including the check that the config reader's two readers agree — were executed on contributors' laptops and nowhere else |
| — | Workflow lint | `fast-actionlint` | FAST | A workflow will not parse. A startup failure creates no status check at all, so it goes quiet rather than red |

### Nightly — too slow or too flaky to block a merge

<!-- placeholder: {{UPSTREAM_PROVIDER}} — the external API your product calls at runtime
     and whose response shape gate 18 re-reads. `none` is a valid answer and leaves the
     gate skipping. -->

| # | Gate | Job | What a failure means |
|---|---|---|---|
| 5 | **Mutation testing, both stacks, WHOLE codebase** | `nightly-mutation-backend`, `nightly-mutation-frontend` | The gate that keeps coverage honest: it breaks the code on purpose and a real suite must notice. Cover EVERY logic-bearing package, not just the easy ones |
| 15 | **End-to-end + accessibility, nightly run** — the nightly pass of the blocking gate above | `nightly-e2e-accessibility` | Everything above can be green while the built artifact is blank. Keep the known-violations baseline EMPTY — adding an entry means shipping a known accessibility defect and needs a recorded human decision |
| 16 | **Deep dependency scan**, fail at a high CVSS score | `nightly-dependency-scan` | A dependency carries a high or critical advisory. Fires against an UNCHANGED lockfile, which is why it cannot be a pull-request gate |
| 18 | Live external API contract tests — `{{UPSTREAM_PROVIDER}}` | `nightly-api-contract` | An upstream provider changed its response shape. **Informative, non-blocking.** Ships as a fillable CONTRACT, not an implementation: one step per upstream dependency, asserting the response **shape** rather than the values, with a worked example in the workflow. Unarmed it reports **skipped and says so**, never green |
| 20 | **Flaky-test detection** — run the suite 3× and diff per-test outcomes | `nightly-flaky-detection` | A nondeterministic test means some share of every other gate's green runs was luck |

**No nightly context may EVER be marked required.** They do not run on pull requests at
all, so a required nightly check leaves every pull request waiting forever on a status that
can never arrive.

**Gate 18 ships as a contract, not a gap.** Its upstream body was two named external
providers, and inventing replacements would ship something that runs, goes green and checks
nothing — which looks armed and is worse than an empty gate. The workflow instead carries
the exact shape of what belongs there and a worked example against a fictional provider.
Two things it is easy to get wrong: assert the response **shape**, never the values (a
value assertion fails on every ordinary data change and is switched off within a week), and
treat an **unreachable** provider as an outage rather than a contract break.

### Operational watchdogs — scheduled, never required

These do not test the product. They test the machine that tests the product, which nothing
else in the gauntlet does.

| Gate | Job | What a failure means |
|---|---|---|
| **CI health watch** — self-hosted runner liveness + hosted-minutes allowance | `watch-ci-health` | CI itself is degraded. A runner **offline** means the queue has stopped draining, and no other check will go red to tell you — that silence is the whole reason this exists. **Minutes** at or above the threshold is a countdown: at 100% every hosted job dies within seconds with no runner assigned, which reads as a mystery fault rather than the predictable state it is. A `::warning::` on a **green** run is neither — that is a could-not-check, and it means the watch is blind, not that something is wrong |

Three properties of that job are load-bearing and easy to undo:

1. **It runs on the hosted runner and must never be routed through `PR_RUNNER` /
   `NIGHTLY_RUNNER` / `AGENT_RUNNER`.** A watchdog scheduled onto the runner it watches
   goes down with it, and its silence is indistinguishable from health.
2. **"Could not check" is a warning on a green run, not an alert.** An expired token that
   pages four times a day teaches the channel to skim past the alert that matters.
3. **It is OPTIONAL and ships inert.** Without the `CI_HEALTH_PAT` secret it announces
   that it checked nothing and exits 0 — the same announced-skip shape as gate 18 and
   `tools/check-deidentified.sh`. **Enable it in one step:** create a fine-grained token
   with repository *Administration: read-only* and account *Plan: read-only*, and add it as
   the `CI_HEALTH_PAT` repository secret. The alert threshold defaults to 75% and is
   overridden with the `CI_MINUTES_ALERT_PCT` repository variable.

### The deploy-time gate

Before restarting anything: **restore the latest production backup into a scratch container
and validate the new migrations against it.** That turns "production boot-loops on schema
drift" into "deploy declined, production untouched" — the difference between an outage and
a red check.

This is documented, not wired: it needs a real environment and a real backup, neither of
which a template can supply. A failed deploy should also call the notifier at S2. Read the
run before reacting: a drift-gate decline leaves production untouched on the previous
build, whereas a failed post-deploy health check means the stack was rebuilt and production
may be down. Those are different emergencies.

---

## Required checks — the rule that bites

> **A required check must ALWAYS REPORT, even when it has nothing to do.**
>
> Skip it with a **job-level `if:`** — that reports `skipped`, which GitHub counts as
> passing. **Never** with a workflow-level `paths:` filter: the workflow never triggers, no
> check run is created, and the pull request hangs on *"Expected — waiting for status to be
> reported"* forever. With "do not allow bypassing" enabled it becomes permanently
> unmergeable.
>
> Two workflows here arrived from upstream with a workflow-level `paths:` filter —
> `pr-validation.yml` and `pr-mutation.yml`. That was correct there, because neither was a
> required check. It could not stay: both are promotable FULL-tier gates now, so the filter
> moved down to a `changes`-fed job-level `if:`. Any new required check follows that
> pattern.

**A context string is the job's `name:` when it has one, and the job id otherwise.** Every
gate job in this repository therefore carries **no `name:` key at all**, so the context is
exactly the id — one string per gate rather than two that can drift. Renaming one silently
breaks branch protection in every downstream repository that already required the old
string. The exact strings are in `docs/runbooks/branch-protection.md`.

**Branch protection is what makes all of this binding.** Until it is on, with "do not allow
bypassing", every gate here is advisory. It is an admin setting, it cannot be committed to
a repository, and it is deliberately the LAST setup step.

---

## Floors ship UNCALIBRATED, and that is the design

Every floor ships as the literal `unset` sentinel in `floors.yml`. Until
`tools/measure-floors.sh` is run against **your** product, every ratchet gate **passes
while printing**:

> `floor not yet calibrated — run tools/measure-floors.sh against your product`

Three things that are easy to get wrong here:

1. **`unset` is not zero, and it is not "switched off".** A floor of `0` is
   indistinguishable in a config file from a gate somebody deliberately disabled, so the
   adopter would get a silently unarmed gauntlet and no signal that it is unarmed — the
   "green run, wrong answer" shape this whole repository opposes. The sentinel is what makes
   the unarmed state **loud**.
2. **Day-one green comes from floors being UNCALIBRATED, not from floors being LOW.** The
   difference is visible on every run until it is fixed.
3. **No floor may ever be derived from the bundled example.** `measure-floors.sh` REFUSES
   to run while `examples/` is present. A ratchet calibrated to a toy service that
   `init.sh` then offers to delete is a floor calibrated to code that no longer exists, and
   it produces the same abandonment aspirational floors do.

### A worked example — one team's result, never a default

These are the measured baselines of **one real product after months of ratcheting**. They
are here so you know what a calibrated gauntlet looks like. **They are not defaults and
must never be shipped as any adopter's starting point** — doing that makes every first pull
request permanently red and the template gets deleted the same afternoon.

| Floor | That team's calibrated value |
|---|---|
| Backend line coverage | ≥ 92% (measured 92.88%) |
| Backend branch coverage | ≥ 84% (measured 85.18%) |
| Backend mutation score | ≥ 89% (measured 91.06%, 7380 mutants) |
| Frontend mutation score | ≥ 96% (measured 97.88%) |
| Frontend statements / branches / functions / lines | ≥ 96 / 89 / 98 / 97% |
| Frontend bundle, gzipped | ≤ 400 KiB (measured 374.8 KiB) |

**The ratchet's promise is "floors only move up from where YOU are", not "start at someone
else's finish line".**

---

## The ratchet policy

Every numeric floor, freeze store and baseline list follows one rule: **it only ever moves
in the strict direction.** Gate 9 enforces this mechanically — the ratchet guards read the
live configs and fail the build if a floor was lowered, a threshold deleted, an exclude
widened, or a freeze store removed.

Lowering a floor therefore **also means editing a guard**: a visible, reviewable,
deliberate act rather than a one-line edit buried in an unrelated diff.

- **Floors sit just under the measured baseline.** After landing work that lifts the
  measured number by a meaningful margin, raise the floor to just under the new number
  **in the same pull request**.
- **Never lower a floor to make a pull request pass.** If a floor blocks you, **the missing
  tests ARE the work.** Lowering one is an explicit human decision with a written
  justification in the pull request. **Agents may never do it, ever.**
- **A declared ceiling ratchets in reverse.** The bundle budget moves down freely after a
  size win; raising it needs the same justification as lowering a coverage floor.
- **The architecture freeze store**: existing violations are frozen, new ones fail. When you
  fix a frozen violation the store shrinks on the next run — commit the shrink. **Never
  hand-edit the store to admit a new violation.**
- **The accessibility baseline** ships EMPTY. Adding an entry means shipping a known
  accessibility defect and needs a human decision recorded in the pull request.
- **The CVE allowlist**: each entry needs a **written exposure analysis**, not just "no fix
  available" — and the gate FAILS when an allowlisted advisory disappears, so stale
  exceptions cannot accumulate.
- **Suppression is not passing.** A lint-disable, a warning suppression, a disabled or
  skipped test, or a coverage/mutation exclusion added to turn a red gate green **counts as
  lowering a floor**: human sign-off, rationale in the code comment and in the pull request.
- **Exactly two honest reasons a number may drop:**
  1. **The measuring instrument changed** — a tool version that computes branches
     differently. (Real example: a coverage tool's major version switched to AST-aware
     branch remapping, and the *same* tests reported 89.3% branch instead of 94.5%.)
  2. **The scope got wider** — a mutation run that now covers twice as many packages. (Real
     example: a scope grew from 7 packages to 14, taking the score from 90.3% to 86.7% and
     the floor from 87 to 83 — while gating **1549 more mutants**. The survivors in the
     newly-gated packages were then hunted down, taking the same wide scope to 91.06% and
     the floor to 89, so the wider net now scores higher than the narrow one ever did.)

  **A lower number for a wider net is an improvement; a lower number for the same net is a
  regression.** The config comment and the pull request must say which one it is, **every
  time.** This exemption is unusable without knowing which instrument produced the number,
  which is why `measure-floors.sh` records the measured value, the date and the tool version
  alongside every floor it writes.
- **The pull-request template carries a gate-integrity attestation**: a checkbox stating
  that no floor was lowered, no rule suppressed, no exclude added — and if one had to move,
  it moved **up**.

---

## Nightly failures reach a human automatically

Every nightly gate has an `if:`-guarded notifier job calling the reusable
`.github/workflows/nightly-alert.yml`. It opens — or comments on the existing open —
`[nightly] <gate> is failing` issue, and sends the alert-channel ping. `ci-health-watch.yml`
calls the same notifier from its own workflow, with its own notifier job; being in a
different file changes nothing about the rules below.

**A red nightly visible only in the Actions tab stays red for weeks.** In the source
system, one gate had been dying on a missing interpreter for its *entire existence* and
nothing said so.

**One notifier job per gate, never one that ORs the results together.** A single OR-ing
notifier collapses distinct gates into one issue, so a second gate going red while the
first is still open produces no new signal at all — and the issue names the wrong gate.

> ### That notifier once shipped broken and took every nightly gate down with it
>
> Two independent faults, both easy to reintroduce:
>
> 1. **A reusable workflow cannot hold more permission than its caller.** Token permissions
>    narrow down a call chain and never widen. The notifier needs `issues: write`; the
>    repository default is read-only, and a caller that declares nothing — or declares only
>    `contents: read`, which is an explicit cap — makes that an escalation. GitHub rejects
>    it when it builds the run graph, so the whole workflow reports **`startup_failure`**
>    and **the gate jobs never run either.** This is not a notifier-only failure: the gate
>    goes QUIET rather than RED, which is strictly worse. Every caller must declare
>    `permissions: {contents: read, issues: write}` at workflow level.
> 2. **The notifier ran on a runner class that could not start.** The one job whose entire
>    purpose is to say a gate went red could not start. That is the failure mode the whole
>    design warns about — you lose the alert about losing the alert.
>
> Fallout worth remembering: one gate had been red every night for weeks *for that reason
> alone*. The external provider it tested had not changed anything. **A gate whose red
> means "the runner could not start" rather than "the thing under test broke" is worse than
> no gate.** After any change here, dispatch the workflow once and confirm the run reaches
> `queued`/`in_progress` rather than `startup_failure`.

---

## What each layer of the gauntlet is FOR

The gates are complementary; each catches what the previous one cannot.

1. **Tests** prove intended behaviour — but only for cases someone wrote.
2. **Coverage ratchet** proves new code arrives with tests — but an assertion-free test
   still counts.
3. **Mutation testing** proves the tests actually *assert*. This is what keeps gate 2
   honest.
4. **Acceptance specs** prove the business rules are still the agreed ones.
5. **Architecture rules** prove the code landed in the right shape — structure rots
   invisibly while every test stays green.
6. **Lint with correctness rules** proves purity and framework contracts.
7. **Real-dependency integration + migration validation** prove the schema story — the
   classic "worked on the in-memory database" failure.
8. **End-to-end + accessibility** prove what users actually receive works. Everything above
   this line can be green while the built bundle is blank.
9. **CVE gates** prove the code we did not write is still safe to ship.
10. **Ratchet guards** prove the gauntlet itself has not been quietly dismantled. Without
    them, every number above is only a convention.
11. **Harness guards** prove the agents' own plumbing still works. Everything above tests
    the product; **nothing else tests the machine that builds it.** A broken collector or a
    weakened prompt produces green runs and wrong answers, which is the worst combination
    available.

---

## Gate 22's own rule: when a guard must EXECUTE, not match text

Gate 22 (`tests/harness-guards/`) pins the lessons welded into the agent workflows. Most
guards do that by asserting a string survived — `pins.json` is the inventory, and
`gen-pin-tests.sh` turns each entry into one assertion. That is the right shape when the
value of a lesson **is the words**: a reason written next to a rule, a warning sentence a
reader has to see, a comment explaining why an idiom is what it is.

It is the wrong shape for a whole class of defect, and every one of them has now been
seen here at least once:

| The failure | Why a text pin misses it |
|---|---|
| A **wrong branch** — `posted` where `stewardPosted` was meant | Both spellings are in the file. The pin matches either. |
| A **wrong composition** — three individually correct fragments that render a contradiction together | Every fragment passes on its own. |
| A **wrong-but-plausible value** — the live diff instead of the pinned one | It is still a valid diff, still a green run, still a comment that reads correctly. |
| A **filter silently dropped** and replaced with nothing | The surrounding comment still describes the filter that is gone. |

**The rule: if the dangerous failure is a wrong branch, a wrong composition, or a
wrong-but-plausible value, the guard must run the real code.** Extract the actual script,
`jq` program or step body out of the workflow, feed it crafted inputs, and assert on what
it *does*. A copy of the logic pasted into the test does not count — it drifts from the
workflow the first time somebody edits one and not the other, and the guard then asserts
things about a program that no longer runs anywhere.

Two obligations come with a behavioural guard, and both exist because a guard that quietly
does not run is the exact failure this directory was built to prevent:

1. **Prove the extraction found something.** Assert the extracted text is non-empty and
   contains a known landmark, in `setup`. An empty extraction makes every assertion in the
   file pass for the wrong reason.
2. **Mutation-test it once, by hand, before you trust it.** Reintroduce the bug, watch the
   guard go red, put it back. Record which assertions failed in the commit message. A guard
   nobody has ever seen fail is a guard nobody has evidence about.

Worked examples in this repository: `review-collector.bats` (runs the workflow's real `jq`
programs against crafted comment fixtures), `steward-handoff-closure.bats` (runs the
workflow's real JavaScript against a stubbed API), `referee-diff-pin.bats` (runs the real
fetch script against a stubbed `gh`), and `referee-missing-review-notice.bats` (runs the
real notice block and reads what it rendered).

Prefer extracting the logic into `tools/` when it is big enough to deserve a name — a
script is easier to test than a step body, and the guard then needs no extraction at all.
`tools/fetch-pinned-diff.sh` exists for exactly that reason.

## Running the gauntlet locally

The commands are the **reference stack's**. On another stack, replace the commands and
keep the claims. The full procedure, including how to read a red gate, is in
`docs/runbooks/qa-procedures.md`.

```bash
# FAST tier — everything a pull request must pass, no containers, no browsers
cd examples/backend  && mvn clean verify -DskipITs
cd examples/frontend && npm run lint -- --max-warnings 0 && npm run test:coverage -- --run

# FULL tier — integration against the real dependency
cd examples/backend  && mvn clean verify -Dgroups=docker -DexcludedGroups=live

# Mutation testing (slow — scope it while iterating)
cd examples/backend  && mvn -Pmutation test-compile org.pitest:pitest-maven:mutationCoverage

# End-to-end + accessibility (builds, serves, drives a real browser)
cd examples/frontend && npm run build && npm run test:e2e

# Bundle-size budget (needs a build first)
cd examples/frontend && npm run build && node scripts/check-bundle.mjs

# Gate 22 — the harness suite. Text only; seconds. BOTH halves: the guards pin the
# load-bearing strings inside the agent workflows, and tests/ exercises the tooling
# those workflows call. CI runs the two as separate steps of the same job, so run
# both here too — for a while only the first of them ran anywhere but a laptop.
bats tests/harness-guards/
bats tests/

# Gate 21 — spec artifacts
tools/spec-pipeline/validate.sh
```

---

## For autonomous agents

`AGENTS.md` applies in full. Additionally, when a gate turns red on your pull request:

1. **Fix the code, or write the missing tests. That is the deliverable.**
2. If you believe the gate itself is wrong — a flaky rule, a miscalibrated floor — **stop
   and escalate** per `docs/runbooks/agent-escalation.md`. Do not adjust the gate, suppress
   the rule, or edit a baseline or store.
3. A nightly mutation failure is an S2: read the report artifact, identify the surviving
   mutants, and open a pull request adding the killing assertions. **But check first
   whether a score was ever produced** — a run killed mid-flight reports identically to one
   that scored below the floor, and building a fix for the second when it was really the
   first wastes the run.
4. **Never edit a ratchet guard, a freeze store, or the accessibility baseline to make a
   gate pass.** Those files exist precisely to make that move impossible to do quietly.
   Touching one is an escalation, not a fix.
5. Every pull request fills in `.github/pull_request_template.md`, **including the
   gate-integrity attestation**.
