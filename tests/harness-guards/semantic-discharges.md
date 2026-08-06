# Semantic-manual pin discharges

_Companion to `pins.json` and `lesson-inventory.md`. **Committed, deliberately** — see
"Why this is in the tree" below._

`pins.json` carries two kinds of entry.

- **`regex`** — the load-bearing string survives genericisation unchanged, so the rest of
  the gate-22 suite asserts it mechanically. Delete the string, the suite goes red.
- **`semantic-manual`** — the string itself HAD to change. A repository-standards path, a
  metric name, a mention phrase, an account login: each one names something that belongs
  to the source and cannot appear here. There is nothing to pin. What survives is the
  CONCEPT, and only a human comparing source and target can say whether it did.

This file is that comparison, written down. One row per `semantic-manual` entry, all 23.

## Why this is in the tree

The first version of this record was written to `.temper/evidence/extraction-diff.md`,
which `.gitignore` excludes. That was wrong in a way worth stating plainly, because the
reasoning that produced it was reasonable: the reconciliation is build evidence, evidence
is not product, and the source repository is named all over it.

But the source repository is reachable **exactly once**. After the extraction it is gone —
not deleted, just out of reach of anyone who reads this template. From that moment the
shipped tree asserted 23 obligations and carried the proof for none of them, and no reader
could tell an obligation that was carefully discharged from one nobody looked at.

That is not hypothetical. Row 12 below, the comment collector, was recorded as fully
discharged in the untracked version. It was not: the endpoints were merged and the
identity filter was silently absent, which disarmed the lost-review detector in both
directions at once. The reviewer who found it had to reconstruct the claim from the
workflow because the claim itself was unreachable. **An unverifiable discharge is worth
less than an honest `null`** — `null` at least tells you where to look.

So the record ships, with every source identity removed, and it is swept by
`tools/check-deidentified.sh` like any other tracked file. Source files appear under the
same redactions `pins.json` uses (`<VENDOR-REVIEW-WORKFLOW>.yml` and so on); `source_head`
plus `source_line` plus the quoted string still locate every original exactly, for anyone
who has the source.

## How to read the state column

| State | Meaning |
|---|---|
| **discharged** | The concept is present in the target, at the named path. `discharged_in` in `pins.json` is filled in. |
| **partial** | Something landed and something has not. `discharged_in` stays **`null`** and `partial_discharge` says what is missing. Half a discharge is an open obligation with a head start; rounding it up to done is how row 12 survived a review that had already looked at it. |
| **variant** | Discharged by a mechanism stronger than the pin's literal wording, with the difference stated. Never quietly. |

The invariant, and the only reason the field is readable at all:

> **`discharged_in: null` means GENUINELY OPEN. Never merely unrecorded.**

`tests/harness-guards/pins-discharge.bats` holds that invariant mechanically: every
`semantic-manual` id must appear here, every non-null `discharged_in` must name a path
that exists, and a null one must carry a `partial_discharge`.

---

## `<VENDOR-REVIEW-WORKFLOW>.yml` → `.github/workflows/review.yml`

| # | Pin | State | How |
|---|---|---|---|
| 1 | `review-model-pinned-not-floating-alias` | discharged | Reviewer A step comment in `.github/workflows/review.yml`: the model comes from `models.judge` and is pinned by exact id, with the reason stated — an alias "resolves to whatever the platform default is that week and drifts with no diff". |
| 2 | `review-standards-doc-paths` | discharged | Same comment block in `.github/workflows/review.yml`: the reviewer is "anchored to THIS REPOSITORY'S OWN STANDARDS, by path — `AGENTS.md` at the root and `docs/runbooks/` — not to generic best practice". The source's paths were its own; the concept is that they are named, not which they were. |
| 3 | `handoff-files-issue-not-comment` | discharged | `.github/workflows/review.yml`, "Hand blocking findings to the steward": `issues: [opened]` is named as the ONE auto-invoke path carrying no sender check, with the loop-guard reasoning intact — a review posts as a bot, and the bot-sender gate in `steward.yml` makes commenting structurally unreachable. |
| 4 | `handoff-warns-loudly-when-elevated-token-absent` | discharged | `.github/workflows/review.yml`: both channels present — a `::warning::` annotation AND a `> [!WARNING]` block inside the filed issue, each naming `STEWARD_HANDOFF_PAT`. Nothing may read as "handed off" when it was not. |
| 5 | `carveout-silences-both-reviewers` | discharged | `.github/workflows/review.yml`, the supply-chain carve-out notice: "**Both reviewers are affected** — `review` and `challenge-review` run the same way, so neither produced an opinion." The carve-out is a skip, not a pass, and it says so on the pull request rather than in a log. |
| 6 | `review-clean-phrase-literal` | discharged | `.github/workflows/review.yml`: `grep -qF 'No issues found'` — fixed-string, keyed on the CLEAN phrase so that unrecognised output escalates instead of being dropped. Wrong in the direction of one spurious issue, never toward another stranded finding. |
| 7 | `reviewer-b-gate-warning-one-reviewer` | **partial** | The credential gate and the degrade-never-fail branch are in `.github/workflows/review.yml` now. **Not landed:** the literal "one reviewer, not two" sentence, which belongs in `tools/run-agent.sh` so the wording exists in one place — and `run-agent.sh` is not written yet. `discharged_in` stays `null`. |
| 8 | `reviewer-b-must-not-read-first-review` | discharged | `.github/workflows/review.yml`, reviewer B step comment states the prohibition and its reason: agreement it copied is noise, and the whole value of a second family is that it did not see the first opinion. Enforced again in the prompt file when prompts land. |
| 9 | `reviewer-marker-required-first-line` | discharged | `.github/workflows/review.yml`: both reviewer step comments state the exact first-line marker (`<!-- reviewer: judge -->`, `<!-- reviewer: challenge -->`) as a non-optional part of the contract. Constrain the producer; do not only parse defensively. |
| 10 | `reviewer-marker-same-bot-account` | discharged | `.github/workflows/review.yml`: "Every role posts from the SAME bot account, so nothing downstream can tell two reviews apart by author; the marker is the only discriminator." This is also why the source's author filter could not be ported as an author filter — see row 12. |
| 11 | `referee-gated-on-b-having-run` | discharged | `.github/workflows/review.yml`: the referee's `if:` requires `needs.challenge-review.outputs.ran == 'true'`, so an absent optional credential skips the comparison rather than failing the pull request. |
| 12 | `collector-single-endpoint-must-merge-both` | discharged — **and this row is the reason the file is committed** | Both collectors in `.github/workflows/review.yml` — the steward handoff and the referee — read the issue-comments endpoint AND the pull-request review-comments endpoint, slurp before filtering, merge, **filter by the `<!-- reviewer: … -->` role marker**, and sort by `created_at` before taking the last. See the correction note below; the marker filter was missing on the first pass. |
| 13 | `review-selection-must-not-use-exclusion` | variant — tightened | The source selected role A by EXCLUDING role B's marker, which makes any unmarked comment count as A's review. In `.github/workflows/review.yml` both roles emit their own marker and both are selected by a positive match. Stronger than the source; recorded as a change, not slipped in. |

### Correction to row 12, recorded rather than rewritten

The untracked version of this record claimed row 12 was fully discharged, in two places,
and called it "the pin doing its most valuable work". Half of that was true. Both
endpoints were read and merged. But the source's filter had **two** clauses — created
since the job started, AND authored by the review bot — and only the first survived. The
author clause was dropped during genericisation (a template cannot know the adopter's bot
account) and replaced with nothing.

The consequences, both confirmed against the real `jq`:

- A review that posted nothing, plus any unrelated human comment in the window, produced a
  non-empty body. The lost-review detector fires only on an empty body, so it never fired
  — for the exact incident it exists to catch.
- A human replying "looks fine to me" on a code line outranked the reviewer's blocking
  findings, because the merged list is a CONCATENATION of two endpoints and `last` over it
  always returns the final inline comment whatever its timestamp. The clean-phrase check
  then passed and the steward handoff was suppressed, stranding the findings — which is
  precisely the failure the handoff step was built to fix.

Fixed by adding the role-marker filter (the portable form of the author filter, and the
stronger one, since every role posts from the same account) and an explicit
`sort_by(.created_at)` in both collectors. `tests/harness-guards/review-collector.bats`
runs the workflow's own extracted `jq` programs against crafted comment fixtures, so both
failure directions are asserted behaviourally rather than text-pinned.

The lesson worth keeping is not about `jq`. **A filter with two clauses, one of which
cannot survive genericisation, is a place where "genericise" silently means "delete".** The
remaining clause still reads like a filter, so the code looks finished. Everywhere a
`semantic-manual` pin exists, ask what the source's version of that string was doing that
the replacement is not.

---

## `<VENDOR-STEWARD-WORKFLOW>.yml` → `.github/workflows/steward.yml`

| # | Pin | State | How |
|---|---|---|---|
| 14 | `steward-mention-required-on-every-other-trigger` | discharged | `.github/workflows/steward.yml`: `contains(…, vars.AGENT_MENTION \|\| '@agent')` ANDed with `github.event.sender.type != 'Bot'` on all three comment and review triggers. The mention phrase is the adopter's, so the literal string could not port; the requirement that one exists did. |
| 15 | `steward-agent-invocation-step` | discharged | `.github/workflows/steward.yml`: one `tools/run-agent.sh steward` step replaces the vendor action block. The gates, job-level concurrency, visible-outcome check and eviction reporter are unchanged around it — the invocation is the only thing that moved. |

---

## `nightly-alert.yml` → `.github/workflows/nightly-alert.yml`

| # | Pin | State | How |
|---|---|---|---|
| 16 | `notifier-secondary-channel-degrades-to-summary` | discharged | `.github/workflows/nightly-alert.yml`: a missing webhook writes a `$GITHUB_STEP_SUMMARY` block and exits 0, and a delivery failure gets the same treatment, so a notifier fault can never bury the gate failure it was sent to report. |

---

## `pr-tests.yml` → `.github/workflows/pr-tests.yml`

| # | Pin | State | How |
|---|---|---|---|
| 17 | `pr-tests-changes-outputs-per-stack` | discharged | `.github/workflows/pr-tests.yml`: `changes.outputs.backend` and `.frontend`, consumed at BOTH job level and step level. The doubling is what makes a stack-absent gate report `skipped` rather than never reporting. |
| 18 | `runner-selection-switchable-variable` | discharged | `.github/workflows/pr-tests.yml`: `runs-on: ${{ vars.PR_RUNNER \|\| 'ubuntu-latest' }}` on every gate job, so an adopter can move the whole gauntlet onto their own runner with one repository variable. **Not universal, and the exception is a rule:** `ci-health-watch.yml` and the notifier it calls are pinned hosted, because a watchdog on the fleet it watches reports nothing when the fleet dies. |
| 19 | `pr-tests-required-job-names` | variant — stronger | The twelve frozen context strings are in place. The pin's wording asks for a `name:` field character-identical to its id; the target uses **no `name:` key at all**, which makes the context the id by the same GitHub rule and removes the possibility of divergence entirely rather than merely discouraging it. |

---

## `pr-validation.yml` → `.github/workflows/pr-validation.yml`

| # | Pin | State | How |
|---|---|---|---|
| 20 | `validation-workflow-paths-filter-must-be-converted` | discharged — correction made | `.github/workflows/pr-validation.yml` carries no workflow-level `paths:`. A `migration-scope` detector job feeds a job-level `if:`. Correct upstream where the check was not required; fatal here, where it will be. |
| 21 | `validation-required-set-is-named` | discharged | `.github/workflows/pr-validation.yml`: both tiers' context strings are enumerated inline at the `cancel-in-progress` justification, alongside a note marking the two whose workflows are not in the tree yet. A decision that depends on a list is worthless without the list next to it. |

---

## `secret-scan.yml` → `.github/workflows/secret-scan.yml`

| # | Pin | State | How |
|---|---|---|---|
| 22 | `secret-scan-job-name-differs-from-id` | discharged — defect fixed | `.github/workflows/secret-scan.yml`: the job is `fast-secret-scan` with NO `name:` key, so the id and the branch-protection context can never diverge. Upstream they had, which is the defect the pin describes. |

---

## `<CI-HEALTH-WATCH>.yml` → `.github/workflows/ci-health-watch.yml`

| # | Pin | State | How |
|---|---|---|---|
| 23 | `ci-health-finding-must-reach-a-human-outside-the-actions-tab` | discharged | `.github/workflows/ci-health-watch.yml`, job `notify-ci-health`, calls the shared notifier at S2, gated on `needs.watch-ci-health.result == 'failure'`. **Amended:** it now also passes `runner: 'ubuntu-latest'` explicitly. A called workflow's `runs-on` cannot be overridden by its caller, so without that the notifier followed `NIGHTLY_RUNNER` — and the alarm for "the self-hosted runner is dead" queued on the dead runner. Reaching a human is the whole content of this pin, so a delivery path that cannot run does not discharge it. |

---

## Summary

**23 entries: 20 discharged, 2 variant (rows 13 and 19, both stronger than the pin's
literal wording, both stated), 1 partial (row 7, wording deferred to `tools/run-agent.sh`).**

Rows 12, 13 and 22 are cases where the extraction **closed a gap or fixed a defect in the
source** rather than copying it. Those three are the clearest evidence that writing the
inventory before the substitution was worth its cost: read after the fact, all three would
have been pinned in their broken state and reported green permanently.

Row 12 is the counter-example that keeps this honest — the pin existed, the discharge was
recorded, and the discharge was still half wrong. A pin makes a lesson auditable. It does
not make an audit correct.
