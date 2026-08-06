# QA procedures — running the gauntlet and reading a red gate

The operating premise: **nobody reads every line.** Most {{PRODUCT_NAME}} code
is written by agents, and confidence comes from the gauntlet a change survives,
not from an author's assurance. This runbook is the human-facing half of that
— what to run, how to read a red gate, and what is never an acceptable fix.

<!-- placeholder: {{PRODUCT_NAME}} — the product this repo builds. -->

The gate inventory and thresholds live in
[docs/QUALITY-GATES.md](../QUALITY-GATES.md). This document is the procedure.

## 1. Before opening a PR

Run the same gates CI will run. Local green is not proof (CI is the
authority), but local red saves a round trip.

The commands below are for the **reference stack** (Java/Maven + React/npm),
which is what `examples/` and `.github/workflows/pr-tests.yml` are wired for.
On another stack, replace the commands and keep the three claims.

```bash
# Fast tier — unit tests, coverage ratchet, architecture rules, build hygiene
cd examples/backend  && mvn clean verify -DskipITs
cd examples/frontend && npm run lint -- --max-warnings 0 && npm run test:coverage -- --run

# Full tier — integration tests against the real dependency, with the whole
# migration chain applied from scratch. Run this if you touched persistence,
# migrations, or wiring.
cd examples/backend  && mvn clean verify -Dgroups=docker -DexcludedGroups=live
```

Whatever the commands are in your stack, the rule is that these are the *same*
gates CI runs, invoked the same way. A local shortcut that runs a subset is how
"it passed locally" stops meaning anything — and the failure it produces is the
worst kind, because it arrives after review rather than before it.

**A local wrapper script that hard-codes a path is a trap worth naming.** A
convenience wrapper carrying, say, a hard-coded toolchain path that exists on
one person's laptop and nowhere else fails instantly everywhere else — and it
fails in a way that *looks* like a toolchain-version problem rather than a wrong
path, so the next person spends an hour on the wrong question. Invoke the build
tool directly, or make the wrapper resolve the toolchain rather than assert it.

**Check your toolchain version before planning any work that needs a test run.**
Gate 13 (build hygiene) runs *before* compile precisely so a wrong toolchain
fails loudly with a version message instead of producing a confusing downstream
error — but that only helps if you read the message. A too-old toolchain is
something to **install past, not to work around**: relaxing the minimum-version
rule to get a green local run is lowering a gate (§4), and it is self-defeating
anyway, because CI has the right version and your "fix" breaks the build for
everyone else.

Then fill in the PR template honestly. The "gate integrity" checkbox is the
one that matters most; see §4.

## 2. The one test that counts

For every behaviour change, there must be at least one test that **fails
without the production change**. Verify it: stash the production edit, run
the test, watch it go red, restore.

A test that passes both with and without your change proves nothing — it is
coverage theatre, and the nightly mutation run will eventually expose it as a
survived mutant anyway. Cheaper to catch it now.

Assertions must be on real outcomes: rendered text, exact payloads, exact
call arguments, returned values. An assertion that a mock returned what the
test told it to return is worth nothing.

## 3. Reading a red gate

| Gate | Red means | First move |
|---|---|---|
| Unit / integration tests | Behaviour regression | Read the failure. Do not re-run hoping it passes. |
| Coverage ratchet | New code landed without tests | Write the missing tests. Coverage is measured over the whole module, not your diff, so a large untested addition can trip it even when your own changes have tests. |
| Architecture rules | A **new** structural violation (existing ones are frozen) | Fix the structure — go through the layer that owns it, inject instead of reaching. Never hand-edit the freeze store to admit it. |
| Lint at zero warnings | Dead code, or a framework-contract bug | Fix the code. The correctness rules catch real defects (a state update inside an effect, an impure render) that otherwise only appear as production flakes. |
| Frontend coverage ratchet | Frontend code added without tests | Same as above. |
| Migration validation | A migration is malformed, collides on version, or has checksum drift | Fix the migration file. Never edit an already-applied migration's checksum. |
| Secret scan | A credential is about to be committed | Rotate the credential — it is already compromised — then remove it from history. Removing it from the diff alone is not a fix. |
| Ratchet guards / harness guards | A floor, threshold, exclude, freeze store, or a load-bearing string inside an agent workflow was changed | Almost always: put it back. These gates have exactly one job, which is to fail when the gauntlet itself is weakened. Editing the guard to match the change is the thing they exist to prevent. |
| Diff-scoped mutation check | The tests execute your new code without asserting on it | Read the surviving mutants, add the assertions that kill them. |
| Nightly mutation run | The same, over the whole codebase | Open the report artifact, find surviving mutants, add the killing assertions. Treat as S2. |
| Nightly dependency scan | A dependency has a known advisory at or above the threshold | Upgrade the dependency. If no fix exists, escalate with the advisory id and a written exposure assessment. |
| Nightly live external API contract tests | An upstream provider changed its response shape | Not a merge blocker, but it *is* a production risk. Investigate before the data goes stale. |
| Nightly flaky-test detection | A test is nondeterministic | Fix the test, not the schedule. A flaky test means some share of every other gate's green runs was luck. |

### When a check hangs `in_progress`

The table above assumes a gate is green or red. There is a third state: the
check reports **nothing**, sits `in_progress` forever, and — because the PR
gates are *required* checks (see
[branch-protection.md](branch-protection.md)) — leaves the PR permanently
un-mergeable. The PR page shows only a spinner, which is exactly what a slow
job looks like, so the instinct is to wait. Waiting does not fix two of the
three causes.

| Cause | Distinguishing signal | Fix |
|---|---|---|
| **Genuinely slow / queued** — a small runner pool, often one job at a time | The run has a step still `in_progress`, or the job has no steps at all (never dispatched to a runner) | Wait. Check the runner pool before blaming the job: a queue that is deep for capacity reasons looks identical to a hang from the PR page. |
| **Never started** — a required context string that no job ever reports (a typo, or a workflow-level `paths:` filter that skipped the whole workflow) | No run exists for that check at all | Config bug, and it will never clear on its own. Fix per [branch-protection.md](branch-protection.md). |
| **Stalled** — the job ran to completion and never reported a conclusion | **Every step is `success`, including `Complete job`, but the job itself is still `status: in_progress` with `conclusion: null`** | Re-run the run (below). |

Seen in practice: a required integration-test check finished every one of its
steps in about two minutes, and then sat `in_progress` for the next fifty
minutes. Nothing was wrong with the code, the tests, or the configuration — the
run simply never published its conclusion. Anyone reading the PR page would have
waited, because that is precisely what a slow job looks like.

The per-step statuses are the whole diagnostic, and the PR page cannot show
them — only the jobs API can:

```bash
# Needs a token with actions:read — see the note below.
gh api repos/{{REPO_SLUG}}/actions/runs/<RUN_ID>/jobs \
  --jq '.jobs[] | select(.conclusion == null)
        | {job: .name, status, conclusion,
           steps: [.steps[] | {name, status, conclusion}]}'
```

<!-- placeholder: {{REPO_SLUG}} — `owner/repo` on GitHub. -->

All steps `success` + job `conclusion: null` → stalled. Any step still
`in_progress` → it is merely slow; leave it alone. Re-running clears a stall:

```bash
gh run rerun <RUN_ID>       # or: "Re-run all jobs" on the run page
gh run rerun --job <JOB_ID> # just the stalled job

# The two forms are MUTUALLY EXCLUSIVE — `gh run rerun <RUN_ID> --job <JOB_ID>`
# is rejected with "specify only one of `<run-id>` or `--job`". The --job form
# derives the run itself, so the run id is not needed alongside it.
#
# <JOB_ID> is the job's databaseId, NOT the number in the browser URL
# (.../runs/<run-id>/jobs/<number>) — passing that one returns 404:
gh run view <RUN_ID> --json jobs --jq '.jobs[] | {name, databaseId}'
```

**This is human-only, and agents cannot triage it.** The steward's GitHub App
token gets `403 Resource not accessible by integration` on `/actions/runs`,
`/actions/runs/{id}/jobs`, `/actions/runners`, `/commits/{sha}/check-runs`,
`/commits/{sha}/status` and `gh pr checks` alike — this was measured, not
assumed, and the whole list fails the same way. So an agent cannot see check
state at all, let alone re-run a job. An agent that suspects a stalled check
should say so plainly and stop, per [AGENTS.md](../../AGENTS.md).
`mergeStateStatus` *is* readable and reports `BLOCKED`, but it says nothing
about which of the three causes applies, so it must never be used to guess one.

## 4. What is never an acceptable fix

These make a gate green while making the codebase worse. **Suppression is not
passing.** They are prohibited for agents outright, and require an explicit
human decision (recorded in the PR) for anyone else:

- Lowering a coverage, mutation, or lint threshold.
- Adding an exclusion — a coverage exclude, a mutation exclusion, a lint-ignore
  entry, a warnings budget above zero — to route around a failure.
- Skipping or disabling a test that is failing for a real reason.
- Hand-editing the architecture-rules freeze store to admit a new violation.
- Deleting or weakening an assertion so a test stops noticing a regression.
- Editing a ratchet-guard or harness-guard test so it accepts the weakened
  value. That is the same act as the ones above, one level up, and it is exactly
  what the guards were written to make visible.
- Re-running CI until a flaky test passes. A flaky gate is a broken gate:
  fix the flake (make the assertion relative, control the clock, await the
  state) or the gate stops meaning anything. *Narrow exception:* re-running a
  **stalled** check (§3 — every step succeeded, the job never reported a
  conclusion) is not this. There is no verdict to re-roll; the job never
  produced one. Re-rolling a gate that *did* report is what this rule
  prohibits.

Two honest reasons a number may drop, and only two: the measuring instrument
changed, or the scope got wider. Say which one, in the config comment and in the
PR, every time.

If a gate genuinely looks wrong, that is an escalation, not a workaround —
see [agent-escalation.md](agent-escalation.md).

## 5. Ratcheting (when you make things better)

Floors only move up. After landing work that lifts a measured number by a
meaningful margin, raise the floor to just under the new measurement **in the
same PR**, and update the baseline note in
[docs/QUALITY-GATES.md](../QUALITY-GATES.md). That is what stops the codebase
from quietly sliding back.

A declared ceiling — a bundle-size budget, a p99 latency budget — ratchets in
reverse: lower it freely after a win, and raising it needs the same written
justification as lowering a floor.

**Calibrate from a real measurement, never from a guess.** That is what
`tools/measure-floors.sh` is for: it runs the coverage and mutation tools
against your own product, writes each floor just under the measured value, and
records the measurement, the date and the tool version alongside it — because
the ratchet policy's "the measuring instrument changed" exemption is unusable
without knowing which instrument produced the number.

Raising a floor to a number nobody measured is how a gate ends up red on the
next unrelated PR, which is how gates get quietly relaxed.

**Until it has been run, every floor reads `unset` in `floors.yml`** and each
ratchet gate passes while printing `floor not yet calibrated — run
tools/measure-floors.sh against your product`. That is a deliberate state, and
it is loud on purpose: a floor of `0` would be indistinguishable in the config
from a gate somebody switched off.

## 6. Release verification

After a deploy:

1. Health check — the endpoints answer, and the counts they report are sane.
2. The running build reports the version and build time you just shipped. If it
   reports the previous one, the deploy did not take, however green it looked.
3. Your metrics dashboard shows no new error-rate or latency step change in the
   thirty minutes after.
4. The next scheduled `health` run is the real acceptance test — read its ledger
   entry and its `{{ALERT_CHANNEL}}` line rather than assuming silence means
   success.

<!-- placeholder: {{ALERT_CHANNEL}} — where operational pings go (a chat channel,
     an email list, a pager). -->

Production is read-only for agents (see [AGENTS.md](../../AGENTS.md)); any
remediation is described in an escalation for a human to execute.
