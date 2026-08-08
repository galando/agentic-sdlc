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

## [0.3.0] - 2026-08-08

An upstream-lessons release. Everything here landed first in the running system the
template was extracted from and is carried back: the referee stops handing the operator
decisions it can make itself, the steward stops being woken before half the evidence
exists, every review job reads the same commit, and five standing decisions the fleet
learned the hard way join `docs/runbooks/agent-modes.md`.

### If you read nothing else

This entry is long, and skimming a changelog is how a lesson gets lost. So: **four things
changed how the review loop behaves.** Everything after them is detail, fixes, and
tooling — safe to skim.

| What | Was | Is now |
|---|---|---|
| **The referee rules** | Sorted the two reviews and ended "a human decides" | Settles each real disagreement against the code, with a tie-break ladder that always terminates. Verdicts are advice; the author overrules at merge time. |
| **All three jobs read one commit** | Each asked for "the current diff" at its own start time | One pinned `base...head` range from the event payload, shared by both reviewers and the referee, with the checkout pinned to match. |
| **The handoff waits for both reviews** | Filed from the `review` job, before the second review could exist | Filed at the end of `referee`, reading both reviews — so a finding from either one reaches the steward. |
| **The handoff issue closes itself** | Stayed open, blocking the next handoff for that pull request | Closed as `completed` when the steward finishes it. |

If you have adopted an earlier version and are merging this by hand, those four are the
ones to read in full. **The one that can bite silently is the third**: before it, a pull
request where the judge role was clean and the challenge role found a bug filed no handoff
at all.

### Changed

- **The referee now settles disagreements instead of only sorting them.** It used to
  compare the two reviews and stop; its output ended "a human decides", so every
  disagreement became an operator decision — and most were not disagreements at all
  (one reviewer's silence, the same defect at two severities, two valid fixes for one
  bug). The genuine ones were nearly always questions of fact about the code, which have
  a checkable answer. `.agents/prompts/review-referee.md` now carries a strict bar for
  what counts as a contradiction, an instruction to settle each real one against the
  code, and a four-rung tie-break ladder whose last rung always terminates.

  The self-grading objection — the referee runs the same `judge` role that wrote one of
  the reviews — is answered structurally rather than by abstaining: a ruling in the judge
  role's favour requires a quoted `file:line`, a tie goes to the challenge role, and
  every verdict is advice the author overrules at merge time. `review.yml` hands it
  `.review-artifacts/diff.patch` so it can read the code it is ruling on — pinned to the
  commit the reviews were written for, see *Fixed* below.
- **The steward handoff moved from the `review` job to the end of `referee`.**
  `challenge-review` declares `needs: review`, so the handoff was filed before the second
  review and the referee comparison could exist — on every pull request, always. The
  steward was woken early, reported on a pull request it had read once, and built its fix
  on one opinion out of three. Worst and invisible: the clean check read one comment body,
  which by that ordering could only be the judge-role review, so **a pull request where
  the judge role was clean and the challenge role found a bug filed no handoff at all**.
  The handoff now reads both collected reviews and files when either carries findings.
- **The `referee` job is no longer gated on the challenge role having run.** That gate
  would have deleted every handoff behind a missing `CHALLENGE_API_KEY`, and it also made
  the missing-review notice unreachable in the one case it was written for. Either
  reviewer producing a review enters the job; neither doing so skips it silently, which is
  the untouched-template state.
- The referee's collector produces both review bodies even with no `jq` on the runner,
  using the `jq` that `gh` embeds. A missing `jq` costs the comparison, never the handoff.

### Added

- **A punt check on the referee's output.** A prompt is a request, not a guarantee, so
  `review.yml` scans the generated comment for "unresolved" headings and "a human decides"
  closing lines before posting. It **annotates, never suppresses** — a silent referee would
  lose the comparison as well as the punt — so a punt reaches the reader labelled as a
  defect to report rather than a decision they owe anyone.
- Five standing decisions in `docs/runbooks/agent-modes.md`, each with the incident that
  produced it: *merging a fix does not run anything on the server* (name what will run the
  change, and when); *`action_required` is a third colour on a pull request* and means the
  gauntlet never ran; *a contested number gets a pre-committed test, not another
  measurement*; *a pre-committed band has to be able to lose* (the three checks that make
  one able to fire); and *the nightly gates have a reader* — the chief of staff's daily
  brief, now a standing section in its prompt.
- **The handoff issue closes itself once the steward has finished it.** That issue is a
  signal shaped like a work item: filing it starts the run, and the signal is spent the
  moment the run begins — but nothing owned the ticket afterwards, so it stayed open.
  Mostly clutter, with one real cost: **the handoff dedupes on the exact issue title, and
  that title carries the pull-request number**, so a stale open issue blocks a *second*
  handoff for the same pull request — a pull request marked `ready_for_review` again after
  more commits then gets a review round that wakes nobody.

  `steward.yml`'s existing visible-outcome step now closes it as `completed`, reusing state
  it already computes instead of adding a prompt instruction an agent can ignore. Two
  load-bearing conditions: the title must start `[steward-handoff]` (the step runs on every
  opened issue, so this keeps human-filed and `[review-lost]` issues open), and the reply
  must be the **steward's own** rather than anyone's (the outcome check counts any author on
  purpose; reusing that for closing would let a human writing "hold on" close the ticket
  they were objecting to). Best-effort — a failure warns rather than reddening a run whose
  work is done.
- Five gate-22 guard files: `referee-verdict.bats`, `steward-handoff-order.bats`,
  `steward-handoff-closure.bats`, `referee-diff-pin.bats` and
  `referee-missing-review-notice.bats` — including a guard that runs the workflow's own punt
  pattern against the phrasings that caused it and against prose that must not trip it.

  Four of the five are **behavioural rather than text pins**: they extract the real script
  out of the workflow and run it against a stubbed API, because in each case the dangerous
  failure is a wrong branch or a wrong composition, not a missing string — and the file
  reads correctly in every one of them. Each was mutation-tested against the bug it exists
  to catch: restoring the live diff fetch fails 5 assertions, restoring the spliced notice
  noun fails 6, and both dangerous handoff-closure mutations fail their guards.

  The closure guard needs `node`, and a missing `node` fails it loudly rather than skipping
  it — a guard that quietly does not run is the failure this directory exists to prevent.
  `pr-tests.yml` installs node explicitly rather than relying on the hosted runner having
  one, since `runs-on` honours `vars.PR_RUNNER`.

### Fixed

- **The two reviewers could review different commits from each other.** Each asked the
  platform for "this pull request's diff" at its own start time, and `challenge-review`
  declares `needs: review`, so it starts strictly later. The referee then compared the two
  as though they had read the same code. **"Both reviewers found this" and "only one
  reviewer found this" are both meaningless when they were not** — and nothing in the
  output would look wrong, because two blind spots that overlap by accident are
  indistinguishable from two that genuinely agree.

  All three jobs now fetch through one script, `tools/fetch-pinned-diff.sh`, with the same
  `base...head` range from the event payload, and all three checkouts are pinned to the same
  `head.sha`. A `pull_request` checkout otherwise defaults to the merge ref, which is
  recomputed as the base branch moves, so even the working trees could differ. Both reviewer
  prompts now name the pinned diff as the thing to review.
- **The referee judged the reviews against the wrong commit.** It fetched the diff with the
  "give me this pull request's diff" command, which resolves the head *at the moment the
  referee runs* — while the two reviews it compares were written earlier, against whatever
  the head was then. A fix pushed in between made the reviewer who found the bug look wrong:
  the referee measured the **fix** and scored it against the finding that produced it.
  Upstream saw it rule two accurate reviewers wrong at once.

  The window is usually seconds, which is why it hid. **It bites precisely when an author
  fixes findings as they arrive, so the more responsive the author, the more likely their
  reviewers are marked down** — and the referee's comment is the last word on the page, so a
  reviewer who was right is recorded as wrong. Three parts, all needed: the diff is now
  **pinned** to the event payload's `base.sha...head.sha`; a moved head is **disclosed** in a
  note prepended by its own step (posting stays a plain "send the file"); and the referee is
  **told** in its prompt that a finding which looks already fixed is usually a reviewer being
  right, because it reads the working tree as well as the diff.
- **The missing-review notice contradicted itself when both reviews were missing.** It
  spliced a noun into a fixed sentence, so zero reviews rendered as "**BOTH reviews** is not
  on this pull request", under a log line saying one was found, above advice to treat the
  pull request as having had "one reviewer at most" — which describes zero as one. That
  notice is the only thing telling a reader a green check does not mean "reviewed twice", so
  it is now a whole sentence per case, and the zero case says "no automated review at all".
- **`review.yml` wrote five files to fixed paths under `/tmp`.** `runs-on` honours
  `vars.AGENT_RUNNER`, and a self-hosted runner's `/tmp` outlives the job and is shared:
  mode 1777 lets anyone create a file there but never lets a non-owner truncate one, so
  `> /tmp/<fixed-name>` dies with "Permission denied" and `set -e` fails the step *after*
  the review has already posted — a red check on a green review, with the handoff never
  filed. All five now use `RUNNER_TEMP`, which the runner creates, owns and clears.
- `.agents/prompts/review-judge.md` asks what will run the change and when, so the
  never-deployed fix is caught at review time rather than a day later.

### Maintainer-facing (skim unless you maintain a fork of this template)

`tools/init.sh` deletes everything in this section during adoption — it describes the
template's relationship with the system it was extracted from, which an adopter does not
have.

#### `tools/check-upstream-drift.sh` — "did I miss anything?" as a command

Three syncs in a row were done by reading `git log` by hand. This lists every upstream
commit since a recorded sync point that touches the surface this template actually carries
(workflows, runbooks, prompts, standing decisions), excluding product-only changes. It does
**not** judge portability — several upstream lessons have correctly not been carried — it
tells you what to read.

The sync point and the not-carried decisions live in `.agents/upstream-sync.json`, so
"checked, not carried, because X" survives instead of being re-derived every sync.

It shipped with a bug of exactly the kind it exists to catch, found by testing it: it read
the local `HEAD`, and `git fetch` does not move a local branch, so a freshly-fetched clone
reported one commit to read while four were waiting. It now prefers the remote-tracking ref,
names which ref it read and how fresh it is, and warns loudly when falling back to a local
one. An unresolvable sync point **fails** rather than producing an empty, reassuring list.

#### `pins.json` gained a supersession record

`referee-sorts-does-not-grade` is the first pinned lesson to be **reversed by later
evidence**, and schema 1 had no way to say so. The reversal was first recorded by rewriting
the entry's `why` — which loses the original reasoning and reads to the next person as
though the rule had always said the new thing.

Schema **2** adds `superseded_on`, `superseded_by` and `superseded_reason`. The rules that
make it worth having:

- **`why` keeps its original text.** The reason a rule existed is the most valuable thing to
  preserve when reversing it — it is the cost you are choosing to pay.
- **The pattern is not relaxed.** A superseded lesson is one whose *conclusion* changed, not
  one that stopped mattering; the string usually survives in a new role. Here the pinned
  phrase "grading its own paper" is now the objection being *answered*.
- **Deleting a pin remains the only way to say a lesson no longer applies at all**, and it
  is still not something to do quietly.
- `gen-pin-tests.sh` carries the supersession into the generated failure message, so a red
  pin never tells you to restore a rule the system has argued its way out of.

`gen-pin-tests.sh` also gained proper escaping for the generated strings. Until now every
`why` happened to contain no quote, dollar or backtick, so interpolating them raw was
silently fine; the first entry carrying a quoted phrase produced a generated file whose
`echo` arguments re-tokenised into something subtly different from the inventory.

#### Gate 22's own rule is written down

`docs/QUALITY-GATES.md` now states when a guard must **execute** rather than match text: if
the dangerous failure is a wrong branch, a wrong composition, or a wrong-but-plausible
value, the guard runs the real code. Four such failures have now been seen here, and a text
pin would have missed every one. Two obligations come with it — prove the extraction found
something, and mutation-test the guard by hand before trusting it.

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
