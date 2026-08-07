# Headless playbook — every unattended agent

<!-- placeholder: {{BUILD_PIPELINE}} is the name of the spec pipeline your agents build
     through — either a plugin your agent CLI provides, or the built-in fallback in
     tools/spec-pipeline/. tools/init.sh asks for it once. -->

**Who this binds:** any agent running the `{{BUILD_PIPELINE}}` spec pipeline with **no
human present** — the steward in CI, the scheduled routines, and any agent added later.
The pipeline is the default way every agent builds a fix or a feature (`AGENTS.md`
guardrail 7, `docs/runbooks/agent-routines.md`), so this file is not steward-only. Read it
**before** starting a pipeline, not after a gate stops you.

**How this file becomes binding.** `tools/run-agent.sh` passes it to every adapter as
`AGENT_SYSTEM_PROMPT_FILE`, so it is injected into the agent's system prompt rather than
being a document the agent is trusted to remember to read.

Pipeline orchestrators are written for interactive sessions: they stop at gates and ask
the human a question. In this environment **never ask a question** — every decision an
orchestrator would put to a human has a deterministic rule below. Follow the orchestrator
exactly *except* where this playbook overrides an interactive step. `$PIPELINE_CLI` means
the pipeline's own command-line entry point.

Sections 1 and 3 below are written for a CI workspace (a runner, and a branch created for
you by the workflow). If you are a scheduled routine or another kind of runner, apply them
to your own equivalent: your own workspace, your own `agent/<purpose>-<date>` branch
(`AGENTS.md` guardrail 2). Everything in sections 2 and 4 applies to you unchanged.

## Availability is a finding, not an excuse

**If the pipeline is not installed or `$PIPELINE_CLI` is missing — try to make it work
before falling back.** The fallback is real, but reach for it second, not first.

*Enabled* is not the same as *present*. A repository can enable a pipeline in its agent
settings and still hand a fresh container an empty installed-tool map — enabled, never
fetched. That failure is quiet, and it is easy to mistake for a fact of the environment:
one agent fleet ran for a full day declaring the pipeline unavailable on every pull
request before anyone asked *why*, and the answer was that the tooling had simply never
been fetched into that container. One fetch fixed it.

So, in order:

1. **Check what is actually missing.** Read the session's own startup line and the
   installed-tool list. An empty plugin map means "not installed", not "not available".
2. **Try to obtain it.** Most pipeline CLIs are self-contained scripts with no install
   step, so fetching the tooling and pointing `$PIPELINE_CLI` at it is usually enough.
   Then run the pipeline normally.
3. **When the pipeline is genuinely absent, drive `tools/spec-pipeline/` directly.** The
   contract is the ARTIFACTS, not the tool: `tools/spec-pipeline/CONTRACT.md` says exactly
   which files gate 21 requires, and `tools/spec-pipeline/new-spec.sh <slug>` creates them.
   An agent on any provider can satisfy gate 21 this way, which is the point of having a
   fallback at all.
4. **Only if even that fails**, fall back to a careful test-first change and say so once —
   in your pull request body, and in your ledger entry as
   `"temper":"unavailable — <reason>"`.

Give the **real** reason in that field. "unavailable" alone is what let the case above go
unexamined for a day: it reads as a fact of the environment when it was a fixable gap.
Write `"unavailable — tooling fetch failed: <error>"`, not `"unavailable"`.

## 0a. Verify the premise before you build anything

**Binding, and it comes before choosing a pipeline.** An issue is a report, not a fact.
Re-derive the defect from primary evidence — the run log, the metric, the row in the
database — before writing a line of code. If you cannot reproduce the premise, say so on
the issue and **do not open a pull request**.

This is not hypothetical caution. In one review of a batch of open agent-filed issues,
three of them had premises that were simply false:

| Class of report | Claimed | Actually |
|---|---|---|
| A quality metric "went hollow" | Tests execute code without asserting on it, so the score is meaningless | No score was ever produced. The job was killed out of memory on one night, and the runner shut down mid-run on the other. There were no surviving mutants to chase. |
| A deployment "failed" | A deploy failed | The run was **cancelled** by its concurrency group. Nothing failed. |
| Five separate lost reviews | Five independent review-delivery defects | One benign supply-chain guard, reported five times. |

An automated issue→pull-request loop pointed at those would have produced fixes for
defects that did not exist — and a plausible, well-tested, entirely pointless pull request
is harder to catch in review than an obviously broken one.

Cheap checks that would have caught all three, in under a minute each:

- **A failing gate:** grep the job log for `Killed`, `exit code 137`, `received a shutdown
  signal`, `The operation was canceled`. A process that died reports the same as a gate
  that failed.
- **A "no data" finding:** confirm the query returned zero rows because the condition is
  absent, not because the instrument is broken. `agent-modes.md` already says a `no data`
  is not a pass.
- **A repeat report:** check whether the same cause is already filed. Five issues for one
  guard is a duplicate-detection failure, not five problems.

When the premise does not hold, the deliverable is a comment closing the issue with the
evidence — that IS the work, and it is worth more than a pull request.

## 0. Choosing the pipeline

| What you are doing | Pipeline |
|---|---|
| Bug, regression, "X is broken", a metric that stopped moving | The **fix** pipeline: root cause → fix → review → check |
| Feature, enhancement, new capability | The **feature** pipeline: plan → design? → build → review → check → eval? |
| Answering a question, reviewing a diff, filing an issue, a docs-only change | No pipeline. Just do it. |
| One-line mechanical edit (typo, dead link, version bump) | Direct edit is fine. |

If the pipeline is missing or broken, fall back to a plain, careful, test-first direct fix
and say prominently in your comment that the pipeline was unavailable and why.

## 1. Before starting

1. **Stale lock:** a runner's workspace can persist between jobs. If the pipeline's
   autonomy lock file exists at job start, it is residue from a crashed run — delete it.
   (The workflow's `concurrency` group guarantees no live parallel steward run.)
2. **Dirty tree:** the checkout step owns this workspace; if `git status --porcelain` is
   non-empty at start, the residue is disposable — `git checkout -- . && git clean -fd`,
   then proceed. Do not ask.
3. **A human's saved session:** the pipeline's repo-global state files (build state, the
   gate ledger, overrides, metrics, feedback loops, evidence) are tracked in git and may
   hold the operator's own in-progress run for a different feature. If build state exists
   for a feature that is not yours: copy each to `<name>.human-backup` (outside git's
   index — do NOT commit the backups), then clear the pipeline state and initialise fresh.
   You MUST restore them before you finish (step 2 of section 3). Never "resume" or
   "overwrite" the human's session.
4. **Branch:** stay on the branch the workflow created for you. Skip any orchestrator
   instruction to create a new feature branch — the branch you are on IS the feature
   branch.

## 2. Gate decisions (replaces every question the orchestrator would ask)

| Orchestrator asks | You do |
|---|---|
| Plan gate PASS: continuation choice | Set the run mode to autonomous, print the summary box, continue. |
| Any post-plan gate PASS | Print the summary box, advance the stage, continue. |
| Any gate FAIL, loop budget available | Loop back automatically, per the feedback-loop rules. |
| Any gate FAIL, budget exhausted | **Park** (section 3). Never override on your own authority — an override is a human act. |
| Build judges the plan infeasible | **Park immediately.** This loop is human-only by design; do not attempt it, do not stall waiting. |
| Design stage offer | Follow the deterministic rule: run design iff the complexity is medium or complex and the design phase is enabled. Otherwise it is skipped — there is nothing to decide. |
| "Review config suggestions" | Defer all of them. Leave the suggestions file in the spec directory untouched for the operator. Never edit the guardrail files unattended. |
| Any interactive teaching, walk-through or challenge mode | Never. These are human-education options. |
| Resume prompts ("resume or overwrite?", stale-state warnings) | Covered by section 1.3 — back up, then initialise fresh. |
| Final commit gate | **Always park.** Autonomy never performs the final feature commit; the per-stage work-in-progress commits are what the pull-request-opening step picks up. |

## 3. Parking / finishing (always runs, success or not)

1. Write an autonomy report at `.temper/autonomy-reports/<slug>.md` — the **same `<slug>`
   as your `.temper/specs/<slug>/` directory** — in the orchestrator's park format
   (`SHIP-PENDING-COMMIT` if everything passed, `PARKED-NEEDS-DECISION` otherwise, with
   the gate ledger).

   **One file per run, never a shared one.** This was once a single report file that every
   run overwrote, which made it a guaranteed merge conflict between any two open agent
   pull requests — and resolving that conflict always means discarding one run's report. A
   single overwritten file also cannot be "the record" it is meant to be: the last writer
   wins. Per-run files accumulate the way `.temper/specs/<slug>/` already does, and two
   pull requests touching different slugs merge cleanly.
2. **Restore the human's state:** check the repo-global pipeline state files back out from
   the default branch (only the paths that exist there), delete your `.human-backup`
   copies, and commit the restore. Your branch must merge cleanly without clobbering the
   operator's session. Keep your `.temper/specs/<slug>/` artifacts and your autonomy
   report — they are the record, and gate 21 requires the spec directory in the diff.
3. Push. Your per-stage work-in-progress commits plus the restore commit are what the
   workflow's pull-request-opening step picks up.
4. Update your comment: verdict, the gate ledger verbatim, what parked and why (if
   parked), and what a human should do next. The comment is the operator's only window
   into the run — **never end silently**.

   **Write it in plain language** (`AGENTS.md` guardrail 6,
   `docs/runbooks/agent-communication-style.md`). Open with a few short, simple sentences:
   what was wrong, what you changed, and why. Everyday words, jargon expanded on first use,
   no filler. Then say what you did *not* do — what parked, what you could not verify, what
   a human must run. Only call something fixed if you verified it. The gate ledger stays
   verbatim underneath; this rule shortens the prose, never the evidence.

## 4. Guardrails (unchanged)

`AGENTS.md` still binds: production is read-only, changes go only through this branch and
its pull request, never merge your own, escalate per `docs/runbooks/agent-escalation.md`,
secrets stay out of commits, comments, logs and ledgers, and every comment, pull-request
body and commit message is written in plain language (guardrail 6).
