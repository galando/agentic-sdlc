#!/usr/bin/env bats
#
# GENERATED FILE — DO NOT HAND-EDIT.
#
# Produced by tests/harness-guards/gen-pin-tests.sh from pins.json. Regenerate with:
#   tests/harness-guards/gen-pin-tests.sh
# then `git diff --exit-code tests/harness-guards/pins.generated.bats` — CI's
# fast-repo-hygiene job runs exactly that, so a hand edit here, or a pin added without
# regenerating, fails the build.
#
# Committed and reviewable in a diff on purpose (design.md Decision D10): a runtime
# loop over pins.json would hide the WHY text from the diff, which is where the lesson
# has to be readable. One @test per literal/regex pin, each carrying its `why` verbatim
# as a comment — the incident is the reason the assertion exists, and a rule without
# its reason gets deleted by the next person. semantic-manual entries get no assertion
# here (the string itself had to change during genericisation, so there is nothing to
# pin); they are named below as hand-discharged instead of silently omitted.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

# WHY: The entire value of a second, differently-failing reviewer is the finding only one of 
# WHY: them raised. Any downstream step that treats disagreement as noise, or silence from one 
# WHY: reviewer as a veto on the other, destroys the reason the second reviewer exists.
@test "pin[review-lone-finding-is-the-point]: .github/workflows/review.yml" {
  run grep -E -q -- a\ finding\ only\ one\ of\ them\ raised "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: review-lone-finding-is-the-point"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:44"
    echo "  why:    The entire value of a second, differently-failing reviewer is the finding only one of them raised. Any downstream step that treats disagreement as noise, or silence from one reviewer as a veto on the other, destroys the reason the second reviewer exists."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The comparison step runs on the same model family as one of the reviews it is comparing, 
# WHY: so it is a party to the dispute and may only sort findings, never rule on them. A 
# WHY: comparator that picks winners is the first reviewer marking its own work, and the human 
# WHY: loses the disagreement that was the point.
# SUPERSEDED 2026-08-08 -> docs/runbooks/multi-model-review.md — "The referee settles 
# disagreements"; guarded by tests/harness-guards/referee-verdict.bats
# SUPERSEDED: Abstaining cost more than it saved. Every disagreement became an operator decision, and 
# SUPERSEDED: most were not disagreements at all — one reviewer's silence, the same defect at two 
# SUPERSEDED: severities, two valid fixes for one bug. The genuine ones were nearly always questions of 
# SUPERSEDED: FACT about the code, which have an answer anyone can check. The comparator now rules, and 
# SUPERSEDED: the self-grading risk this entry names is answered STRUCTURALLY rather than by 
# SUPERSEDED: abstaining: it settles questions of fact against a diff pinned to the reviewed commit, a 
# SUPERSEDED: ruling in its own side's favour requires quoted file:line evidence, a tie goes to the 
# SUPERSEDED: other reviewer, and every verdict is advice the author overrules at merge time. The 
# SUPERSEDED: pinned phrase must survive as the objection being ANSWERED — if it disappears, the 
# SUPERSEDED: reason the safeguards exist has gone with it.
@test "pin[referee-sorts-does-not-grade]: .github/workflows/review.yml" {
  run grep -E -q -- grading\ its\ own\ paper "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: referee-sorts-does-not-grade"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:55"
    echo "  why:    The comparison step runs on the same model family as one of the reviews it is comparing, so it is a party to the dispute and may only sort findings, never rule on them. A comparator that picks winners is the first reviewer marking its own work, and the human loses the disagreement that was the point."
    echo "  NOTE:   this lesson was SUPERSEDED on 2026-08-08."
    echo "          now: docs/runbooks/multi-model-review.md — \"The referee settles disagreements\"; guarded by tests/harness-guards/referee-verdict.bats"
    echo "          why: Abstaining cost more than it saved. Every disagreement became an operator decision, and most were not disagreements at all — one reviewer's silence, the same defect at two severities, two valid fixes for one bug. The genuine ones were nearly always questions of FACT about the code, which have an answer anyone can check. The comparator now rules, and the self-grading risk this entry names is answered STRUCTURALLY rather than by abstaining: it settles questions of fact against a diff pinned to the reviewed commit, a ruling in its own side's favour requires quoted file:line evidence, a tie goes to the other reviewer, and every verdict is advice the author overrules at merge time. The pinned phrase must survive as the objection being ANSWERED — if it disappears, the reason the safeguards exist has gone with it."
    echo "          The pin still holds: the string survives in its new role. Restore it"
    echo "          as that, NOT as the original rule."
    false
  fi
}

# WHY: The automatic review fires on pull request open and on draft-to-ready only. Adding 
# WHY: push-driven re-review turns one review per pull request into one per push and, combined 
# WHY: with an agent that pushes fixes, closes a loop that runs away on a single runner.
@test "pin[review-triggers-opened-and-ready-for-review]: .github/workflows/review.yml" {
  run grep -E -q -- types:\[\[:space:\]\]\*\\\[\[\[:space:\]\]\*opened\,\[\[:space:\]\]\*ready_for_review\[\[:space:\]\]\*\\\] "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: review-triggers-opened-and-ready-for-review"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:67"
    echo "  why:    The automatic review fires on pull request open and on draft-to-ready only. Adding push-driven re-review turns one review per pull request into one per push and, combined with an agent that pushes fixes, closes a loop that runs away on a single runner."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Never triggering on the push/synchronize event is what makes the fixer's push unable to 
# WHY: bounce back into a fresh review. The comment is load-bearing: without the reason written 
# WHY: down, adding the event later looks like an obvious improvement.
@test "pin[review-never-triggers-on-synchronize]: .github/workflows/review.yml" {
  run grep -E -q -- never\ on\ .synchronize. "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: review-never-triggers-on-synchronize"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:154"
    echo "  why:    Never triggering on the push/synchronize event is what makes the fixer's push unable to bounce back into a fresh review. The comment is load-bearing: without the reason written down, adding the event later looks like an obvious improvement."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The review concurrency group is scoped per pull request number. A single global group 
# WHY: means work on one pull request evicts queued work on an unrelated one, and the platform 
# WHY: gives no way to ask for a deeper queue.
@test "pin[review-concurrency-per-pr-number]: .github/workflows/review.yml" {
  run grep -E -q -- group:.\*github\\.event\\.pull_request\\.number "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: review-concurrency-per-pr-number"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:77"
    echo "  why:    The review concurrency group is scoped per pull request number. A single global group means work on one pull request evicts queued work on an unrelated one, and the platform gives no way to ask for a deeper queue."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: An advisory review that is not a required status check may be cancelled by a newer run on 
# WHY: the same pull request, because nobody reads a superseded commit's review. This is the 
# WHY: opposite setting from the queue that must never drop a request, and the two must not be 
# WHY: conflated.
@test "pin[review-concurrency-cancel-in-progress-true]: .github/workflows/review.yml" {
  run grep -E -q -- cancel-in-progress:\[\[:space:\]\]\*true "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: review-concurrency-cancel-in-progress-true"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:78"
    echo "  why:    An advisory review that is not a required status check may be cancelled by a newer run on the same pull request, because nobody reads a superseded commit's review. This is the opposite setting from the queue that must never drop a request, and the two must not be conflated."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The later comparison job must reuse the exact timestamp the first job recorded, exported 
# WHY: as a job output, rather than computing its own. A freshly computed instant is after both 
# WHY: reviews were posted, so the comparison window excludes the very comments it exists to 
# WHY: compare, and reports nothing while going green.
@test "pin[referee-window-not-recomputed]: .github/workflows/review.yml" {
  run grep -E -q -- Recomputing\ \"now\"\ in\ the\ referee "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: referee-window-not-recomputed"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:87"
    echo "  why:    The later comparison job must reuse the exact timestamp the first job recorded, exported as a job output, rather than computing its own. A freshly computed instant is after both reviews were posted, so the comparison window excludes the very comments it exists to compare, and reports nothing while going green."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: An agent that performs a review and prints it to the run log instead of posting it 
# WHY: produces a green check that reads as reviewed-and-clean. The posting flag is what makes 
# WHY: the review reach the pull request; the comment recording that is why nobody removes the 
# WHY: flag as redundant.
@test "pin[review-silent-reviewer-worse-than-none]: .github/workflows/review.yml" {
  run grep -E -q -- A\ reviewer\ that\ reviews\ and\ stays\ silent\ is\ worse\ than\ no\ reviewer "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: review-silent-reviewer-worse-than-none"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:123"
    echo "  why:    An agent that performs a review and prints it to the run log instead of posting it produces a green check that reads as reviewed-and-clean. The posting flag is what makes the review reach the pull request; the comment recording that is why nobody removes the flag as redundant."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The bot-sender exclusion on the fixer workflow is what stops a review triggering a fix 
# WHY: triggering a review without end. The exclusion looks like an accident until this sentence 
# WHY: is next to it, and removing it is a one-character change.
@test "pin[review-fix-review-loop-guard-rationale]: .github/workflows/review.yml" {
  run grep -E -q -- review-\>fix-\>review\ loop "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: review-fix-review-loop-guard-rationale"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:142"
    echo "  why:    The bot-sender exclusion on the fixer workflow is what stops a review triggering a fix triggering a review without end. The exclusion looks like an accident until this sentence is next to it, and removing it is a one-character change."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A post-run detector must be gated on not-cancelled rather than always. Deliberate 
# WHY: cancellation is routine on a constrained runner, and an always-gated detector reports 
# WHY: every cancellation as a lost result, which trains the reader to ignore the one warning 
# WHY: that matters.
@test "pin[review-handoff-not-cancelled-not-always]: .github/workflows/review.yml" {
  run grep -E -q -- NOT\ always\\\(\\\) "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: review-handoff-not-cancelled-not-always"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:159"
    echo "  why:    A post-run detector must be gated on not-cancelled rather than always. Deliberate cancellation is routine on a constrained runner, and an always-gated detector reports every cancellation as a lost result, which trains the reader to ignore the one warning that matters."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Events created with the default workflow token do not start further workflow runs. An 
# WHY: issue filed with it is visible but inert: it wakes nobody. Any automation that hands work 
# WHY: to another workflow by creating an event needs an elevated token, or it is a no-op that 
# WHY: looks like success.
@test "pin[handoff-pat-required-default-token-inert]: .github/workflows/review.yml" {
  run grep -E -q -- does\ not\ start\ workflow\ runs\ from\ events\ created\ with\ GITHUB_TOKEN "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: handoff-pat-required-default-token-inert"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:170"
    echo "  why:    Events created with the default workflow token do not start further workflow runs. An issue filed with it is visible but inert: it wakes nobody. Any automation that hands work to another workflow by creating an event needs an elevated token, or it is a no-op that looks like success."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The warning about a non-triggering token is written into the filed issue itself, not only 
# WHY: into the run log, because nobody opens run logs for a job that reported success. The 
# WHY: person reading the issue is the one who needs to know it woke nobody.
@test "pin[handoff-issue-body-warns-not-invoked]: .github/workflows/review.yml" {
  run grep -E -q -- NOT\ invoked\ by\ this\ issue "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: handoff-issue-body-warns-not-invoked"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:276"
    echo "  why:    The warning about a non-triggering token is written into the filed issue itself, not only into the run log, because nobody opens run logs for a job that reported success. The person reading the issue is the one who needs to know it woke nobody."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Whether a review actually reached the pull request is checked before any branch on who 
# WHY: authored the pull request. A lost review strands every author equally, and an 
# WHY: author-first ordering exits reporting no action needed without ever discovering that 
# WHY: nothing was posted.
@test "pin[review-body-fetched-before-author-check]: .github/workflows/review.yml" {
  run grep -E -q -- Fetched\ BEFORE\ the\ author\ check "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: review-body-fetched-before-author-check"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:190"
    echo "  why:    Whether a review actually reached the pull request is checked before any branch on who authored the pull request. A lost review strands every author equally, and an author-first ordering exits reporting no action needed without ever discovering that nothing was posted."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The supply-chain carve-out is recognised by inspecting the changed file list for 
# WHY: workflow-directory paths. This is a deliberate security control: a reviewing agent must 
# WHY: not execute under continuous integration that the same pull request is editing.
@test "pin[carveout-detects-workflow-file-edits]: .github/workflows/review.yml" {
  run grep -E -q -- startswith\\\(\"\\.github/workflows/\"\\\) "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: carveout-detects-workflow-file-edits"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:232"
    echo "  why:    The supply-chain carve-out is recognised by inspecting the changed file list for workflow-directory paths. This is a deliberate security control: a reviewing agent must not execute under continuous integration that the same pull request is editing."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A known, explained skip is distinguished from a lost result so the lost-result detector 
# WHY: does not fire repeatedly on one benign cause. Without the distinction the detector files 
# WHY: an identical issue on every run and gets muted, taking the real detections with it.
@test "pin[carveout-warning-not-a-lost-review]: .github/workflows/review.yml" {
  run grep -E -q -- supply-chain\ guard "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: carveout-warning-not-a-lost-review"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:236"
    echo "  why:    A known, explained skip is distinguished from a lost result so the lost-result detector does not fire repeatedly on one benign cause. Without the distinction the detector files an identical issue on every run and gets muted, taking the real detections with it."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The carve-out is not a pass. It fires precisely on the changes where a second pair of 
# WHY: eyes matters most, so it announces itself where the person merging will see it rather 
# WHY: than in a run log nobody opens.
@test "pin[carveout-says-so-on-the-pr]: .github/workflows/review.yml" {
  run grep -E -q -- in\ a\ run\ log\ nobody\ opens "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: carveout-says-so-on-the-pr"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:226"
    echo "  why:    The carve-out is not a pass. It fires precisely on the changes where a second pair of eyes matters most, so it announces itself where the person merging will see it rather than in a run log nobody opens."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The carve-out is scoped as narrowly as possible: every other green-run-with-no-comment 
# WHY: still escalates. Widening a known-benign exception is the standard way a detector stops 
# WHY: detecting, so the narrowness is written down as a constraint rather than left to taste.
@test "pin[carveout-deliberately-narrow]: .github/workflows/review.yml" {
  run grep -E -q -- Deliberately\ narrow "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: carveout-deliberately-narrow"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:228"
    echo "  why:    The carve-out is scoped as narrowly as possible: every other green-run-with-no-comment still escalates. Widening a known-benign exception is the standard way a detector stops detecting, so the narrowness is written down as a constraint rather than left to taste."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The clean/not-clean decision is keyed on the phrase that means clean, not on the marker 
# WHY: that means a finding. An unrecognised output format then counts as findings and gets 
# WHY: escalated rather than silently dropped: wrong in the direction of one spurious 
# WHY: escalation, never in the direction of another stranded finding. MOVED 2026-08-08: the 
# WHY: handoff decision was extracted from .github/workflows/review.yml into 
# WHY: tools/review-handoff-decide.sh so it could be exercised directly instead of by carving a 
# WHY: step body out of YAML. The pattern is unchanged — the lesson moved home, it did not 
# WHY: weaken — and it now sits beside the branch it governs. RE-KEYED 2026-08-09: the value 
# WHY: being read changed — from a clean phrase in a review body, which nothing in this 
# WHY: template emits, to the referee's one-word merge verdict. The lesson is unchanged and now 
# WHY: covers more: the test is an equality against the single word that means "leave it alone", 
# WHY: so a missing file, an empty file and an unrecognised word all escalate. Rewriting it as a 
# WHY: list of the words that WAKE the steward would let a new spelling or a typo fall through 
# WHY: to silence, which is the failure this pin exists to prevent.
@test "pin[review-escalate-unrecognised-format]: tools/review-handoff-decide.sh" {
  run grep -E -q -- unrecognised\ format "$REPO_ROOT/tools/review-handoff-decide.sh"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: review-escalate-unrecognised-format"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:325"
    echo "  why:    The clean/not-clean decision is keyed on the phrase that means clean, not on the marker that means a finding. An unrecognised output format then counts as findings and gets escalated rather than silently dropped: wrong in the direction of one spurious escalation, never in the direction of another stranded finding. MOVED 2026-08-08: the handoff decision was extracted from .github/workflows/review.yml into tools/review-handoff-decide.sh so it could be exercised directly instead of by carving a step body out of YAML. The pattern is unchanged — the lesson moved home, it did not weaken — and it now sits beside the branch it governs. RE-KEYED 2026-08-09: the value being read changed — from a clean phrase in a review body, which nothing in this template emits, to the referee's one-word merge verdict. The lesson is unchanged and now covers more: the test is an equality against the single word that means \"leave it alone\", so a missing file, an empty file and an unrecognised word all escalate. Rewriting it as a list of the words that WAKE the steward would let a new spelling or a typo fall through to silence, which is the failure this pin exists to prevent."
    echo "  Restore the string in tools/review-handoff-decide.sh. Do NOT weaken the pin."
    false
  fi
}

# WHY: Server-side title search tokenises the query, so a number in a title is not anchored and 
# WHY: a shorter number matches a longer one, while bracketed prefixes are dropped as 
# WHY: punctuation. Both directions are harmful: a false match suppresses a real handoff, a 
# WHY: false miss files a duplicate that costs another agent run.
@test "pin[dedupe-avoids-search-in-title]: .github/workflows/review.yml" {
  run grep -E -q -- in:title "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: dedupe-avoids-search-in-title"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:339"
    echo "  why:    Server-side title search tokenises the query, so a number in a title is not anchored and a shorter number matches a longer one, while bracketed prefixes are dropped as punctuation. Both directions are harmful: a false match suppresses a real handoff, a false miss files a duplicate that costs another agent run."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Deduplication is a client-side exact whole-line literal comparison: fixed-string, 
# WHY: whole-line, with the no-match exit code absorbed so a strict shell does not turn no-match 
# WHY: into a step failure. String equality has neither the false-match nor the false-miss 
# WHY: failure mode of tokenised search.
@test "pin[dedupe-exact-literal-whole-line]: .github/workflows/review.yml" {
  run grep -E -q -- grep\ -cFx "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: dedupe-exact-literal-whole-line"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:355"
    echo "  why:    Deduplication is a client-side exact whole-line literal comparison: fixed-string, whole-line, with the no-match exit code absorbed so a strict shell does not turn no-match into a step failure. String equality has neither the false-match nor the false-miss failure mode of tokenised search."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The optional second reviewer publishes whether it actually ran as a job output, so the 
# WHY: downstream comparison can skip cleanly instead of comparing against a review that does 
# WHY: not exist. Inferring it from job conclusion would read a clean skip as a successful 
# WHY: review.
@test "pin[reviewer-b-exports-ran-output]: .github/workflows/review.yml" {
  run grep -E -q -- ran:\[\[:space:\]\]\*\\\$\\\{\\\{\[\[:space:\]\]\*steps\\.gate\\.outputs\\.run "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: reviewer-b-exports-ran-output"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:427"
    echo "  why:    The optional second reviewer publishes whether it actually ran as a job output, so the downstream comparison can skip cleanly instead of comparing against a review that does not exist. Inferring it from job conclusion would read a clean skip as a successful review."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: An optional credential that is not configured degrades the pipeline to one reviewer, 
# WHY: loudly, and must never turn into a red check on every pull request in the repository. 
# WHY: Adding a second opinion may not be able to take the first one down.
@test "pin[reviewer-b-unset-secret-degrades]: .github/workflows/review.yml" {
  run grep -E -q -- An\ unset\ secret\ must\ degrade "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: reviewer-b-unset-secret-degrades"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:435"
    echo "  why:    An optional credential that is not configured degrades the pipeline to one reviewer, loudly, and must never turn into a red check on every pull request in the repository. Adding a second opinion may not be able to take the first one down."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Each reviewing role self-identifies with an HTML-comment marker as the exact first line 
# WHY: of what it posts. The marker prefix is what every downstream consumer keys on, so it must 
# WHY: survive genericisation character-for-character even though the role name inside it 
# WHY: changes.
@test "pin[reviewer-marker-html-comment-prefix]: .github/workflows/review.yml" {
  run grep -E -q -- \<\!--\ reviewer: "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: reviewer-marker-html-comment-prefix"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:470"
    echo "  why:    Each reviewing role self-identifies with an HTML-comment marker as the exact first line of what it posts. The marker prefix is what every downstream consumer keys on, so it must survive genericisation character-for-character even though the role name inside it changes."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Paged collection uses slurp to merge all pages into one document before any filtering. 
# WHY: This is the fix for the per-page filter trap, and the two flags must stay adjacent on the 
# WHY: fetch itself rather than being replaced by a per-item filter.
@test "pin[collector-paginate-slurp]: .github/workflows/review.yml" {
  run grep -E -q -- --paginate\[\[:space:\]\]+--slurp "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: collector-paginate-slurp"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:530"
    echo "  why:    Paged collection uses slurp to merge all pages into one document before any filtering. This is the fix for the per-page filter trap, and the two flags must stay adjacent on the fetch itself rather than being replaced by a per-item filter."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Combining pagination with a per-item filter applies the filter once per page and emits 
# WHY: one array per page, so any take-the-last operation silently returns one result per page 
# WHY: instead of one overall. The bug is invisible until a thread passes one page of comments, 
# WHY: which is exactly when the collector has to be right.
@test "pin[collector-per-page-filter-trap]: .github/workflows/review.yml" {
  run grep -E -q -- ONCE\ PER\ PAGE "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: collector-per-page-filter-trap"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:525"
    echo "  why:    Combining pagination with a per-item filter applies the filter once per page and emits one array per page, so any take-the-last operation silently returns one result per page instead of one overall. The bug is invisible until a thread passes one page of comments, which is exactly when the collector has to be right."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The slurped array-of-arrays is flattened back into one flat list before filtering, with a 
# WHY: shape test so a single-page response is handled identically to a multi-page one. Filter 
# WHY: after flattening, never before.
@test "pin[collector-jq-add-flattens-pages]: .github/workflows/review.yml" {
  run grep -E -q -- then\ add\ else\ \\.\ end "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: collector-jq-add-flattens-pages"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:534"
    echo "  why:    The slurped array-of-arrays is flattened back into one flat list before filtering, with a shape test so a single-page response is handled identically to a multi-page one. Filter after flattening, never before."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Reviews are separated by their role marker, never by ordering such as 
# WHY: newest-comment-wins. Ordering breaks the moment a retry, a status note or any unrelated 
# WHY: comment lands in the same window from the same account, and it breaks silently by 
# WHY: swapping two results rather than by erroring.
@test "pin[review-split-by-marker-not-ordering]: .github/workflows/review.yml" {
  run grep -E -q -- on\ a\ marker\ rather\ than\ on\ ordering "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: review-split-by-marker-not-ordering"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:542"
    echo "  why:    Reviews are separated by their role marker, never by ordering such as newest-comment-wins. Ordering breaks the moment a retry, a status note or any unrelated comment lands in the same window from the same account, and it breaks silently by swapping two results rather than by erroring."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: When one of the two expected reviews is absent, the comparison step says which one is 
# WHY: missing, on the change itself, rather than staying quiet. A green check must never read 
# WHY: as reviewed twice when it was reviewed once.
@test "pin[referee-one-missing-review-is-a-finding]: .github/workflows/review.yml" {
  run grep -E -q -- One\ review\ missing\ is\ a\ real\ finding "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: referee-one-missing-review-is-a-finding"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:555"
    echo "  why:    When one of the two expected reviews is absent, the comparison step says which one is missing, on the change itself, rather than staying quiet. A green check must never read as reviewed twice when it was reviewed once."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Publishing is done by a plain script step reading a file the agent wrote, not by the 
# WHY: agent itself. An agent that decides for itself whether to publish is an agent that can 
# WHY: quietly publish nothing and still report success.
@test "pin[referee-posts-via-plain-script-step]: .github/workflows/review.yml" {
  run grep -E -q -- quietly\ post\ nothing\ and\ still\ go\ green "$REPO_ROOT/.github/workflows/review.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: referee-posts-via-plain-script-step"
    echo "  source: .github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:595"
    echo "  why:    Publishing is done by a plain script step reading a file the agent wrote, not by the agent itself. An agent that decides for itself whether to publish is an agent that can quietly publish nothing and still report success."
    echo "  Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Workflow-level concurrency is evaluated when the run is created, before any job condition 
# WHY: runs, so an event the workflow deliberately ignores still enters the group, still evicts 
# WHY: whatever was pending, and only then skips. The group therefore has to be declared at job 
# WHY: level.
@test "pin[steward-workflow-level-concurrency-is-wrong]: .github/workflows/steward.yml" {
  run grep -E -q -- Workflow-level\ concurrency\ is\ evaluated\ when\ the\ RUN\ is\ created "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-workflow-level-concurrency-is-wrong"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:83"
    echo "  why:    Workflow-level concurrency is evaluated when the run is created, before any job condition runs, so an event the workflow deliberately ignores still enters the group, still evicts whatever was pending, and only then skips. The group therefore has to be declared at job level."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The trigger event cannot be filtered by comment author or content, so the filtering 
# WHY: happens in a job condition that is evaluated before the job reaches a runner. Filtered 
# WHY: events then show as instantly skipped instead of occupying the queue.
@test "pin[steward-gate-runs-before-the-runner]: .github/workflows/steward.yml" {
  run grep -E -q -- BEFORE\ the\ job\ reaches "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-gate-runs-before-the-runner"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:115"
    echo "  why:    The trigger event cannot be filtered by comment author or content, so the filtering happens in a job condition that is evaluated before the job reaches a runner. Filtered events then show as instantly skipped instead of occupying the queue."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Automatic triage fires on newly opened issues only, and that branch carries no mention 
# WHY: requirement and no sender requirement. It is the one unconditional path, which is also 
# WHY: what makes it usable as a cross-workflow handoff target.
@test "pin[steward-auto-triage-issues-opened-only]: .github/workflows/steward.yml" {
  run grep -E -q -- github\\.event_name\ ==\ \'issues\'\ \&\&\ github\\.event\\.action\ ==\ \'opened\' "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-auto-triage-issues-opened-only"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:123"
    echo "  why:    Automatic triage fires on newly opened issues only, and that branch carries no mention requirement and no sender requirement. It is the one unconditional path, which is also what makes it usable as a cross-workflow handoff target."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The comment records that the newly-opened-issue path is deliberately the only 
# WHY: unconditional trigger and that reassignment of an existing issue stays gated. Without it, 
# WHY: someone tidying the condition adds a mention requirement and the handoff path goes dark.
@test "pin[steward-auto-triage-needs-no-tag]: .github/workflows/steward.yml" {
  run grep -E -q -- the\ one\ unconditional\ case "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-auto-triage-needs-no-tag"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:119"
    echo "  why:    The comment records that the newly-opened-issue path is deliberately the only unconditional trigger and that reassignment of an existing issue stays gated. Without it, someone tidying the condition adds a mention requirement and the handoff path goes dark."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Every comment-driven and review-driven trigger requires that the sender is not a bot. 
# WHY: Without it the reviewer's own output wakes the fixer, which pushes, which triggers 
# WHY: another review, forever, on a runner that executes one job at a time.
@test "pin[steward-bot-sender-gate]: .github/workflows/steward.yml" {
  run grep -E -q -- github\\.event\\.sender\\.type\ \!=\ \'Bot\' "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-bot-sender-gate"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:125"
    echo "  why:    Every comment-driven and review-driven trigger requires that the sender is not a bot. Without it the reviewer's own output wakes the fixer, which pushes, which triggers another review, forever, on a runner that executes one job at a time."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The bot-sender exclusion is applied to the inline-code-comment trigger too, not only to 
# WHY: the top-level conversation trigger. A single unguarded event type is enough to reopen the 
# WHY: loop, so the guard is repeated on every one of them.
@test "pin[steward-review-comment-trigger-bot-gate]: .github/workflows/steward.yml" {
  run grep -E -q -- pull_request_review_comment\'\ \&\&\ github\\.event\\.sender\\.type\ \!=\ \'Bot\' "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-review-comment-trigger-bot-gate"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:126"
    echo "  why:    The bot-sender exclusion is applied to the inline-code-comment trigger too, not only to the top-level conversation trigger. A single unguarded event type is enough to reopen the loop, so the guard is repeated on every one of them."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The bot-sender exclusion is applied to the submitted-review trigger as well. Reviews 
# WHY: submitted by an automated reviewer are the exact events that would otherwise wake the 
# WHY: fixer and close the loop.
@test "pin[steward-review-submitted-trigger-bot-gate]: .github/workflows/steward.yml" {
  run grep -E -q -- pull_request_review\'\ \&\&\ github\\.event\\.sender\\.type\ \!=\ \'Bot\' "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-review-submitted-trigger-bot-gate"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:127"
    echo "  why:    The bot-sender exclusion is applied to the submitted-review trigger as well. Reviews submitted by an automated reviewer are the exact events that would otherwise wake the fixer and close the loop."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The queue is scoped per issue or pull request number, using a fallback because the two 
# WHY: event families carry the number in different places. A single global group means a 
# WHY: request on one thread silently evicts a pending request on an unrelated thread.
@test "pin[steward-concurrency-group-per-issue-or-pr]: .github/workflows/steward.yml" {
  run grep -E -q -- github\\.event\\.issue\\.number\ \\\|\\\|\ github\\.event\\.pull_request\\.number "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-concurrency-group-per-issue-or-pr"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:137"
    echo "  why:    The queue is scoped per issue or pull request number, using a fallback because the two event families carry the number in different places. A single global group means a request on one thread silently evicts a pending request on an unrelated thread."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A request that is already executing must not be killed by a newer request on the same 
# WHY: thread, because the running job is doing real work with side effects. This is the 
# WHY: opposite setting from an advisory check and the two must not be unified for consistency.
@test "pin[steward-cancel-in-progress-false]: .github/workflows/steward.yml" {
  run grep -E -q -- cancel-in-progress:\[\[:space:\]\]\*false "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-cancel-in-progress-false"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:138"
    echo "  why:    A request that is already executing must not be killed by a newer request on the same thread, because the running job is doing real work with side effects. This is the opposite setting from an advisory check and the two must not be unified for consistency."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The concurrency group is declared at job level so the job condition is evaluated first: a 
# WHY: skipped job never enters the group and therefore can never displace a pending request. 
# WHY: Declared at workflow level, the workflow reliably generates its own evictions from events 
# WHY: it then ignores.
@test "pin[steward-concurrency-at-job-level]: .github/workflows/steward.yml" {
  run grep -E -q -- skipped\ job\ never\ enters\ the\ group "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-concurrency-at-job-level"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:130"
    echo "  why:    The concurrency group is declared at job level so the job condition is evaluated first: a skipped job never enters the group and therefore can never displace a pending request. Declared at workflow level, the workflow reliably generates its own evictions from events it then ignores."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The platform keeps one running plus exactly one pending run per concurrency group, and a 
# WHY: third event evicts the pending one with no run, no comment and no notification. The queue 
# WHY: cannot be made deeper, which is why the residual eviction has to be reported instead of 
# WHY: prevented.
@test "pin[steward-one-running-one-pending]: .github/workflows/steward.yml" {
  run grep -E -q -- One\ running\ \\+\ one\ pending\ per\ group "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-one-running-one-pending"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:133"
    echo "  why:    The platform keeps one running plus exactly one pending run per concurrency group, and a third event evicts the pending one with no run, no comment and no notification. The queue cannot be made deeper, which is why the residual eviction has to be reported instead of prevented."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A timestamp is recorded before the agent runs so later steps can distinguish something 
# WHY: this run produced from something already present. Without a recorded start instant, any 
# WHY: after-the-fact scan either misses new output or counts old output as new.
@test "pin[steward-record-job-start-instant]: .github/workflows/steward.yml" {
  run grep -E -q -- date\ -u\ \\+%Y-%m-%dT%H:%M:%SZ "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-record-job-start-instant"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:151"
    echo "  why:    A timestamp is recorded before the agent runs so later steps can distinguish something this run produced from something already present. Without a recorded start instant, any after-the-fact scan either misses new output or counts old output as new."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Multi-line instruction text is written as a folded block scalar because in a plain scalar 
# WHY: a space followed by a hash opens a YAML comment, which truncates the value mid-expression 
# WHY: and makes the whole file unparseable. The failure appears as zero-job runs named by file 
# WHY: path, not as a syntax error at the offending line.
@test "pin[steward-prompt-folded-block-scalar]: .github/workflows/steward.yml" {
  run grep -E -q -- opens\ a\ YAML\ comment "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-prompt-folded-block-scalar"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:165"
    echo "  why:    Multi-line instruction text is written as a folded block scalar because in a plain scalar a space followed by a hash opens a YAML comment, which truncates the value mid-expression and makes the whole file unparseable. The failure appears as zero-job runs named by file path, not as a syntax error at the offending line."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: User-supplied titles and bodies are passed through environment variables rather than 
# WHY: interpolated into a shell command or a template expression. Interpolation puts 
# WHY: attacker-controlled text into the command line, and the same mistake also reintroduces 
# WHY: the YAML truncation hazard.
@test "pin[steward-env-var-indirection-untrusted-input]: .github/workflows/steward.yml" {
  run grep -E -q -- untrusted\ issue\ titles\ out\ of\ the\ shell "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-env-var-indirection-untrusted-input"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:201"
    echo "  why:    User-supplied titles and bodies are passed through environment variables rather than interpolated into a shell command or a template expression. Interpolation puts attacker-controlled text into the command line, and the same mistake also reintroduces the YAML truncation hazard."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A branch is only turned into a pull request when it actually carries commits ahead of the 
# WHY: base. The agent reports a branch name whether or not anything was committed, so the 
# WHY: branch name alone is not evidence that work happened.
@test "pin[steward-open-pr-only-when-commits-exist]: .github/workflows/steward.yml" {
  run grep -E -q -- git\ log\ origin/main\\.\\.origin/\\\$BRANCH "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-open-pr-only-when-commits-exist"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:218"
    echo "  why:    A branch is only turned into a pull request when it actually carries commits ahead of the base. The agent reports a branch name whether or not anything was committed, so the branch name alone is not evidence that work happened."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A red run is recoverable because someone re-runs it; a green run that produced nothing is 
# WHY: not, because nobody knows to look. That asymmetry is the whole reason a visible-outcome 
# WHY: check exists and deliberately fails the job.
@test "pin[steward-green-silent-run-unrecoverable]: .github/workflows/steward.yml" {
  run grep -E -q -- nobody\ knows\ to\ look "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-green-silent-run-unrecoverable"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:260"
    echo "  why:    A red run is recoverable because someone re-runs it; a green run that produced nothing is not, because nobody knows to look. That asymmetry is the whole reason a visible-outcome check exists and deliberately fails the job."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Automatic triage must leave something a human can see. A dedicated step asserts that, 
# WHY: rather than trusting the agent to have spoken, because in the automatic path there is no 
# WHY: tracking comment for it to update and posting depends on the model choosing to shell out.
@test "pin[steward-visible-outcome-step]: .github/workflows/steward.yml" {
  run grep -E -q -- Require\ a\ visible\ outcome "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-visible-outcome-step"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:266"
    echo "  why:    Automatic triage must leave something a human can see. A dedicated step asserts that, rather than trusting the agent to have spoken, because in the automatic path there is no tracking comment for it to update and posting depends on the model choosing to shell out."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The visible-outcome check scans comments with full pagination rather than reading the 
# WHY: first page. On a long thread an unpaginated read misses exactly the newest comments, 
# WHY: which are the only ones this check is about.
@test "pin[steward-outcome-paginated-comment-scan]: .github/workflows/steward.yml" {
  run grep -E -q -- paginate\\\(github\\.rest\\.issues\\.listComments "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-outcome-paginated-comment-scan"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:280"
    echo "  why:    The visible-outcome check scans comments with full pagination rather than reading the first page. On a long thread an unpaginated read misses exactly the newest comments, which are the only ones this check is about."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The comment scan is bounded by the instant recorded before the agent ran, so a comment 
# WHY: that was already on the thread cannot be mistaken for output this run produced. Any 
# WHY: comment inside the window counts, including a human reply, because the point is that the 
# WHY: thread is not silently unanswered.
@test "pin[steward-outcome-window-from-job-start]: .github/workflows/steward.yml" {
  run grep -E -q -- steps\\.jobstart\\.outputs\\.iso "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-outcome-window-from-job-start"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:271"
    echo "  why:    The comment scan is bounded by the instant recorded before the agent ran, so a comment that was already on the thread cannot be mistaken for output this run produced. Any comment inside the window counts, including a human reply, because the point is that the thread is not silently unanswered."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The second acceptable outcome is a branch that genuinely exists on the remote, checked by 
# WHY: querying it, not a branch name reported by the agent. The name is populated even when 
# WHY: nothing was committed, so trusting it turns a silent run into a false pass.
@test "pin[steward-outcome-branch-must-exist-remotely]: .github/workflows/steward.yml" {
  run grep -E -q -- existence\ on\ the\ remote\ is\ the\ real\ signal "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-outcome-branch-must-exist-remotely"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:289"
    echo "  why:    The second acceptable outcome is a branch that genuinely exists on the remote, checked by querying it, not a branch name reported by the agent. The name is populated even when nothing was committed, so trusting it turns a silent run into a false pass."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: When neither visible outcome is present the workflow posts a marker comment keyed by run 
# WHY: identifier, so the notice is both machine-detectable and non-duplicating. The marker also 
# WHY: states that no conclusion about the request should be drawn from the silence.
@test "pin[steward-outcome-marker-comment]: .github/workflows/steward.yml" {
  run grep -E -q -- \<\!--\ steward-no-outcome: "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-outcome-marker-comment"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:316"
    echo "  why:    When neither visible outcome is present the workflow posts a marker comment keyed by run identifier, so the notice is both machine-detectable and non-duplicating. The marker also states that no conclusion about the request should be drawn from the silence."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: After posting the notice the step deliberately fails the run. Leaving it green would 
# WHY: preserve the exact condition being detected, a run that looks successful and produced 
# WHY: nothing, which is unrecoverable because nobody knows to look.
@test "pin[steward-outcome-deliberate-failure]: .github/workflows/steward.yml" {
  run grep -E -q -- core\\.setFailed\\\( "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-outcome-deliberate-failure"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:331"
    echo "  why:    After posting the notice the step deliberately fails the run. Leaving it green would preserve the exact condition being detected, a run that looks successful and produced nothing, which is unrecoverable because nobody knows to look."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The outcome check runs on not-cancelled rather than always, so a run an operator killed 
# WHY: on purpose is not reported as a lost result. It still fires when the agent step fails, 
# WHY: which is a genuine silent-outcome case.
@test "pin[steward-outcome-not-cancelled-not-always]: .github/workflows/steward.yml" {
  run grep -E -q -- rather\ than\ .always\\\(\\\) "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-outcome-not-cancelled-not-always"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:261"
    echo "  why:    The outcome check runs on not-cancelled rather than always, so a run an operator killed on purpose is not reported as a lost result. It still fires when the agent step fails, which is a genuine silent-outcome case."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The residual eviction cannot be prevented, so the run that took the slot reports on the 
# WHY: ones it displaced. An evicted run executes nothing and therefore cannot report itself; 
# WHY: the requester otherwise sees no run, no comment and no notification, indistinguishable 
# WHY: from the trigger never working.
@test "pin[steward-eviction-reporter-exists]: .github/workflows/steward.yml" {
  run grep -E -q -- evicted\ from\ the\ queue "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-eviction-reporter-exists"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:354"
    echo "  why:    The residual eviction cannot be prevented, so the run that took the slot reports on the ones it displaced. An evicted run executes nothing and therefore cannot report itself; the requester otherwise sees no run, no comment and no notification, indistinguishable from the trigger never working."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: An evicted run has a precise signature: cancelled with zero jobs ever created, meaning it 
# WHY: never reached a runner. A cancellation that left jobs behind was a deliberate human act 
# WHY: and must not be reported, or the notice becomes noise.
@test "pin[steward-eviction-signature-zero-jobs]: .github/workflows/steward.yml" {
  run grep -E -q -- total_count\ \>\ 0 "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-eviction-signature-zero-jobs"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:410"
    echo "  why:    An evicted run has a precise signature: cancelled with zero jobs ever created, meaning it never reached a runner. A cancellation that left jobs behind was a deliberate human act and must not be reported, or the notice becomes noise."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Eviction notices are deduplicated by a marker keyed on the evicted run identifier, so 
# WHY: repeated scans over the same recent window do not post the same notice again. 
# WHY: Marker-based dedupe is also what makes a misdirected notice permanent, which is why the 
# WHY: target selection has to be right first.
@test "pin[steward-eviction-marker-dedupe]: .github/workflows/steward.yml" {
  run grep -E -q -- \<\!--\ steward-eviction: "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-eviction-marker-dedupe"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:420"
    echo "  why:    Eviction notices are deduplicated by a marker keyed on the evicted run identifier, so repeated scans over the same recent window do not post the same notice again. Marker-based dedupe is also what makes a misdirected notice permanent, which is why the target selection has to be right first."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The issue listing endpoint also returns pull requests, and a last-wins lookup keyed on 
# WHY: title would let a pull request that copied the issue title overwrite the issue. The 
# WHY: notice would then land somewhere the requester is not watching, and marker dedupe would 
# WHY: make that permanent rather than self-correcting.
@test "pin[steward-eviction-filters-pull-requests]: .github/workflows/steward.yml" {
  run grep -E -q -- is\ load-bearing\,\ not\ defensive "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-eviction-filters-pull-requests"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:388"
    echo "  why:    The issue listing endpoint also returns pull requests, and a last-wins lookup keyed on title would let a pull request that copied the issue title overwrite the issue. The notice would then land somewhere the requester is not watching, and marker dedupe would make that permanent rather than self-correcting."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Reporting is best-effort by design: bookkeeping about dropped requests must never be able 
# WHY: to fail the run that is doing the actual work. A reporter that can turn a successful run 
# WHY: red will be deleted the first time it does.
@test "pin[steward-eviction-best-effort]: .github/workflows/steward.yml" {
  run grep -E -q -- continue-on-error:\[\[:space:\]\]\*true "$REPO_ROOT/.github/workflows/steward.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: steward-eviction-best-effort"
    echo "  source: .github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:356"
    echo "  why:    Reporting is best-effort by design: bookkeeping about dropped requests must never be able to fail the run that is doing the actual work. A reporter that can turn a successful run red will be deleted the first time it does."
    echo "  Restore the string in .github/workflows/steward.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The primary alert channel is the one that needs no configuration beyond the token every 
# WHY: workflow already has. Any chat or paging integration is additive, so a rotated or missing 
# WHY: secret degrades the extra channel rather than the alert itself.
@test "pin[notifier-issue-is-primary-channel]: .github/workflows/nightly-alert.yml" {
  run grep -E -q -- PRIMARY\ channel "$REPO_ROOT/.github/workflows/nightly-alert.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: notifier-issue-is-primary-channel"
    echo "  source: .github/workflows/nightly-alert.yml:19"
    echo "  why:    The primary alert channel is the one that needs no configuration beyond the token every workflow already has. Any chat or paging integration is additive, so a rotated or missing secret degrades the extra channel rather than the alert itself."
    echo "  Restore the string in .github/workflows/nightly-alert.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The notifier must not be the component that breaks when a credential is rotated, or you 
# WHY: lose the alert about losing the alert. Ordering the channels so the zero-configuration 
# WHY: one runs first and unconditionally is what enforces that.
@test "pin[notifier-must-not-break-on-rotated-secret]: .github/workflows/nightly-alert.yml" {
  run grep -E -q -- lose\ the\ alert\ about\ losing\ the "$REPO_ROOT/.github/workflows/nightly-alert.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: notifier-must-not-break-on-rotated-secret"
    echo "  source: .github/workflows/nightly-alert.yml:23"
    echo "  why:    The notifier must not be the component that breaks when a credential is rotated, or you lose the alert about losing the alert. Ordering the channels so the zero-configuration one runs first and unconditionally is what enforces that."
    echo "  Restore the string in .github/workflows/nightly-alert.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Every caller of the reusable notifier has to declare the write permission at workflow 
# WHY: level. This instruction is addressed to a file that does not exist yet, which is why it 
# WHY: lives here in capitals rather than in a document nobody opens when adding a caller.
@test "pin[notifier-callers-must-declare-issues-write]: .github/workflows/nightly-alert.yml" {
  run grep -E -q -- CALLERS\ MUST\ DECLARE "$REPO_ROOT/.github/workflows/nightly-alert.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: notifier-callers-must-declare-issues-write"
    echo "  source: .github/workflows/nightly-alert.yml:26"
    echo "  why:    Every caller of the reusable notifier has to declare the write permission at workflow level. This instruction is addressed to a file that does not exist yet, which is why it lives here in capitals rather than in a document nobody opens when adding a caller."
    echo "  Restore the string in .github/workflows/nightly-alert.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A reusable workflow can never hold more permission than its caller; token permissions 
# WHY: narrow down a call chain and never widen. A caller that declares nothing, or declares 
# WHY: only read, turns the notifier's write permission into an escalation request.
@test "pin[notifier-permissions-capped-by-caller]: .github/workflows/nightly-alert.yml" {
  run grep -E -q -- capped\ by\ the\ caller "$REPO_ROOT/.github/workflows/nightly-alert.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: notifier-permissions-capped-by-caller"
    echo "  source: .github/workflows/nightly-alert.yml:27"
    echo "  why:    A reusable workflow can never hold more permission than its caller; token permissions narrow down a call chain and never widen. A caller that declares nothing, or declares only read, turns the notifier's write permission into an escalation request."
    echo "  Restore the string in .github/workflows/nightly-alert.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The rejected escalation is refused when the run graph is built, so the entire calling 
# WHY: workflow never starts, gate job included. The gate therefore goes quiet rather than red, 
# WHY: which is the worst possible failure mode for a check: absent, not failing.
@test "pin[notifier-startup-failure-kills-whole-caller]: .github/workflows/nightly-alert.yml" {
  run grep -E -q -- startup_failure "$REPO_ROOT/.github/workflows/nightly-alert.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: notifier-startup-failure-kills-whole-caller"
    echo "  source: .github/workflows/nightly-alert.yml:32"
    echo "  why:    The rejected escalation is refused when the run graph is built, so the entire calling workflow never starts, gate job included. The gate therefore goes quiet rather than red, which is the worst possible failure mode for a check: absent, not failing."
    echo "  Restore the string in .github/workflows/nightly-alert.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The exact permission block a new caller needs is written out literally, together with the 
# WHY: instruction to dispatch it once and confirm the run actually starts. A rule stated only 
# WHY: in the abstract gets applied wrongly; a copyable block plus a verification step does not.
@test "pin[notifier-new-caller-permissions-recipe]: .github/workflows/nightly-alert.yml" {
  run grep -E -q -- permissions:\ \\\{contents:\ read\,\ issues:\ write\\\} "$REPO_ROOT/.github/workflows/nightly-alert.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: notifier-new-caller-permissions-recipe"
    echo "  source: .github/workflows/nightly-alert.yml:35"
    echo "  why:    The exact permission block a new caller needs is written out literally, together with the instruction to dispatch it once and confirm the run actually starts. A rule stated only in the abstract gets applied wrongly; a copyable block plus a verification step does not."
    echo "  Restore the string in .github/workflows/nightly-alert.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The notifier job itself declares the write permission it needs, which is what makes the 
# WHY: caller's declaration mandatory and the mismatch detectable. Removing it would make the 
# WHY: caller requirement disappear along with the ability to file anything.
@test "pin[notifier-job-declares-issues-write]: .github/workflows/nightly-alert.yml" {
  run grep -E -q -- issues:\[\[:space:\]\]\*write "$REPO_ROOT/.github/workflows/nightly-alert.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: notifier-job-declares-issues-write"
    echo "  source: .github/workflows/nightly-alert.yml:84"
    echo "  why:    The notifier job itself declares the write permission it needs, which is what makes the caller's declaration mandatory and the mismatch detectable. Removing it would make the caller requirement disappear along with the ability to file anything."
    echo "  Restore the string in .github/workflows/nightly-alert.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The tracking issue title is a fixed prefix plus the gate name, which is what makes the 
# WHY: open-or-update lookup work. Change the shape of the title and every recurring failure 
# WHY: starts a new thread instead of joining the existing one.
@test "pin[notifier-issue-title-per-gate]: .github/workflows/nightly-alert.yml" {
  run grep -E -q -- \\\[nightly\\\]\ \\\$\\\{gate\\\}\ is\ failing "$REPO_ROOT/.github/workflows/nightly-alert.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: notifier-issue-title-per-gate"
    echo "  source: .github/workflows/nightly-alert.yml:100"
    echo "  why:    The tracking issue title is a fixed prefix plus the gate name, which is what makes the open-or-update lookup work. Change the shape of the title and every recurring failure starts a new thread instead of joining the existing one."
    echo "  Restore the string in .github/workflows/nightly-alert.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: One issue per gate, commented on rather than duplicated. A gate that stays red for a week 
# WHY: should be one thread with seven comments, not seven issues nobody closes, because a flood 
# WHY: of duplicates is functionally the same as no alert.
@test "pin[notifier-opens-or-updates-one-issue]: .github/workflows/nightly-alert.yml" {
  run grep -E -q -- One\ issue\ per\ gate "$REPO_ROOT/.github/workflows/nightly-alert.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: notifier-opens-or-updates-one-issue"
    echo "  source: .github/workflows/nightly-alert.yml:102"
    echo "  why:    One issue per gate, commented on rather than duplicated. A gate that stays red for a week should be one thread with seven comments, not seven issues nobody closes, because a flood of duplicates is functionally the same as no alert."
    echo "  Restore the string in .github/workflows/nightly-alert.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Each caller must supply, as a required input, one line saying what a human should 
# WHY: conclude from this gate being red. An alert that names a failing job without saying what 
# WHY: it implies is an alert people learn to skim past.
@test "pin[notifier-what-red-means-input]: .github/workflows/nightly-alert.yml" {
  run grep -E -q -- what_red_means "$REPO_ROOT/.github/workflows/nightly-alert.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: notifier-what-red-means-input"
    echo "  source: .github/workflows/nightly-alert.yml:50"
    echo "  why:    Each caller must supply, as a required input, one line saying what a human should conclude from this gate being red. An alert that names a failing job without saying what it implies is an alert people learn to skim past."
    echo "  Restore the string in .github/workflows/nightly-alert.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A cheap paths-filter job publishes which parts of the tree changed, and everything 
# WHY: downstream reads its outputs. Centralising the decision in one job is what allows both 
# WHY: jobs and steps to gate on the same answer.
@test "pin[pr-tests-changes-detector-job]: .github/workflows/pr-tests.yml" {
  run grep -E -q -- \^\[\[:space:\]\]\*changes: "$REPO_ROOT/.github/workflows/pr-tests.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: pr-tests-changes-detector-job"
    echo "  source: .github/workflows/pr-tests.yml:17"
    echo "  why:    A cheap paths-filter job publishes which parts of the tree changed, and everything downstream reads its outputs. Centralising the decision in one job is what allows both jobs and steps to gate on the same answer."
    echo "  Restore the string in .github/workflows/pr-tests.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The change detection gates jobs and steps, both. The doubling is what makes a gate whose 
# WHY: stack is absent report skipped rather than missing, and what stops a partially-relevant 
# WHY: job from paying for toolchains it will not use.
@test "pin[pr-tests-changes-gates-jobs-and-steps]: .github/workflows/pr-tests.yml" {
  run grep -E -q -- jobs/steps "$REPO_ROOT/.github/workflows/pr-tests.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: pr-tests-changes-gates-jobs-and-steps"
    echo "  source: .github/workflows/pr-tests.yml:14"
    echo "  why:    The change detection gates jobs and steps, both. The doubling is what makes a gate whose stack is absent report skipped rather than missing, and what stops a partially-relevant job from paying for toolchains it will not use."
    echo "  Restore the string in .github/workflows/pr-tests.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Jobs are gated by a condition on the change-detector outputs, at job level. A job skipped 
# WHY: this way still reports a conclusion, which satisfies a required status check; a job that 
# WHY: never triggers reports nothing and blocks merging forever.
@test "pin[clean-skip-job-level-gate]: .github/workflows/pr-tests.yml" {
  run grep -E -q -- \^\[\[:space:\]\]\{4\}if:.\*needs\\.changes\\.outputs\\. "$REPO_ROOT/.github/workflows/pr-tests.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: clean-skip-job-level-gate"
    echo "  source: .github/workflows/pr-tests.yml:52"
    echo "  why:    Jobs are gated by a condition on the change-detector outputs, at job level. A job skipped this way still reports a conclusion, which satisfies a required status check; a job that never triggers reports nothing and blocks merging forever."
    echo "  Restore the string in .github/workflows/pr-tests.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Steps inside a job are gated on the same change-detector outputs as the job itself. 
# WHY: Without the step-level half, a job that runs for one stack still installs and executes 
# WHY: the toolchain of every other stack, and the clean-skip guarantee only half holds.
@test "pin[clean-skip-step-level-gate]: .github/workflows/pr-tests.yml" {
  run grep -E -q -- \^\[\[:space:\]\]\{8\}if:.\*needs\\.changes\\.outputs\\. "$REPO_ROOT/.github/workflows/pr-tests.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: clean-skip-step-level-gate"
    echo "  source: .github/workflows/pr-tests.yml:74"
    echo "  why:    Steps inside a job are gated on the same change-detector outputs as the job itself. Without the step-level half, a job that runs for one stack still installs and executes the toolchain of every other stack, and the clean-skip guarantee only half holds."
    echo "  Restore the string in .github/workflows/pr-tests.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Change detection uses a dedicated paths-filter action rather than hand-rolled diff 
# WHY: parsing, so the filter semantics match what the platform's own path matching does and 
# WHY: there is one place to read the rules.
@test "pin[pr-tests-paths-filter-action]: .github/workflows/pr-tests.yml" {
  run grep -E -q -- dorny/paths-filter "$REPO_ROOT/.github/workflows/pr-tests.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: pr-tests-paths-filter-action"
    echo "  source: .github/workflows/pr-tests.yml:38"
    echo "  why:    Change detection uses a dedicated paths-filter action rather than hand-rolled diff parsing, so the filter semantics match what the platform's own path matching does and there is one place to read the rules."
    echo "  Restore the string in .github/workflows/pr-tests.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Routing a required check to a runner label that no runner offers does not fail; it queues 
# WHY: forever, and the change becomes unmergeable. Any switchable runner selection needs this 
# WHY: warning written next to it, because the failure looks like slowness rather than 
# WHY: misconfiguration.
@test "pin[pr-tests-runner-label-must-exist]: .github/workflows/pr-tests.yml" {
  run grep -E -q -- queues\ forever\ and\ this\ is\ a\ required\ check "$REPO_ROOT/.github/workflows/pr-tests.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: pr-tests-runner-label-must-exist"
    echo "  source: .github/workflows/pr-tests.yml:22"
    echo "  why:    Routing a required check to a runner label that no runner offers does not fail; it queues forever, and the change becomes unmergeable. Any switchable runner selection needs this warning written next to it, because the failure looks like slowness rather than misconfiguration."
    echo "  Restore the string in .github/workflows/pr-tests.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Superseded runs on the same reference are cancelled, because nobody reads the test result 
# WHY: of a commit that has already been replaced. This is only safe where cancelling cannot 
# WHY: strand a required check that branch protection is waiting on.
@test "pin[pr-tests-concurrency-cancel-true]: .github/workflows/pr-tests.yml" {
  run grep -E -q -- cancel-in-progress:\[\[:space:\]\]\*true "$REPO_ROOT/.github/workflows/pr-tests.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: pr-tests-concurrency-cancel-true"
    echo "  source: .github/workflows/pr-tests.yml:11"
    echo "  why:    Superseded runs on the same reference are cancelled, because nobody reads the test result of a commit that has already been replaced. This is only safe where cancelling cannot strand a required check that branch protection is waiting on."
    echo "  Restore the string in .github/workflows/pr-tests.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Scope filtering belongs in a job condition, never in a workflow-level path trigger. The 
# WHY: two look equivalent and are not, and the comment is the only thing standing between a 
# WHY: future tidy-up and a repository where every unrelated change is permanently unmergeable.
@test "pin[mutation-filter-in-job-never-in-trigger]: .github/workflows/pr-mutation.yml" {
  run grep -E -q -- Filter\ inside\ the\ job\;\ never\ in\ the\ trigger "$REPO_ROOT/.github/workflows/pr-mutation.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: mutation-filter-in-job-never-in-trigger"
    echo "  source: .github/workflows/pr-mutation.yml:21"
    echo "  why:    Scope filtering belongs in a job condition, never in a workflow-level path trigger. The two look equivalent and are not, and the comment is the only thing standing between a future tidy-up and a repository where every unrelated change is permanently unmergeable."
    echo "  Restore the string in .github/workflows/pr-mutation.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A required check that never reports does not fail; it waits for a status that can never 
# WHY: arrive, and with bypass disabled the change can never merge. Absent is strictly worse 
# WHY: than red, because red is visible and absent looks like pending.
@test "pin[mutation-required-check-never-reports]: .github/workflows/pr-mutation.yml" {
  run grep -E -q -- A\ required\ check\ that\ never\ reports\ does\ not\ fail "$REPO_ROOT/.github/workflows/pr-mutation.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: mutation-required-check-never-reports"
    echo "  source: .github/workflows/pr-mutation.yml:35"
    echo "  why:    A required check that never reports does not fail; it waits for a status that can never arrive, and with bypass disabled the change can never merge. Absent is strictly worse than red, because red is visible and absent looks like pending."
    echo "  Restore the string in .github/workflows/pr-mutation.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A job skipped by its own condition still reports a conclusion, and that conclusion 
# WHY: satisfies a required check. This is the mechanism that makes clean-skip work, and it is 
# WHY: the difference between a gate that is absent and one that is honestly not applicable.
@test "pin[mutation-skipped-satisfies-required-check]: .github/workflows/pr-mutation.yml" {
  run grep -E -q -- reports\ conclusion\ \"skipped\" "$REPO_ROOT/.github/workflows/pr-mutation.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: mutation-skipped-satisfies-required-check"
    echo "  source: .github/workflows/pr-mutation.yml:38"
    echo "  why:    A job skipped by its own condition still reports a conclusion, and that conclusion satisfies a required check. This is the mechanism that makes clean-skip work, and it is the difference between a gate that is absent and one that is honestly not applicable."
    echo "  Restore the string in .github/workflows/pr-mutation.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Two workflows must not publish check runs under the same name, because branch protection 
# WHY: matches required checks by name string and duplicate names make that matching ambiguous. 
# WHY: Check names are a global namespace across the repository, not per file.
@test "pin[mutation-scope-job-name-must-be-unique]: .github/workflows/pr-mutation.yml" {
  run grep -E -q -- Deliberately\ NOT\ named "$REPO_ROOT/.github/workflows/pr-mutation.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: mutation-scope-job-name-must-be-unique"
    echo "  source: .github/workflows/pr-mutation.yml:55"
    echo "  why:    Two workflows must not publish check runs under the same name, because branch protection matches required checks by name string and duplicate names make that matching ambiguous. Check names are a global namespace across the repository, not per file."
    echo "  Restore the string in .github/workflows/pr-mutation.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Branch protection matches required checks by name string. That single fact is why job 
# WHY: identifiers cannot be renamed casually, why two jobs may not share a name, and why a name 
# WHY: field that differs from its identifier is a trap.
@test "pin[mutation-branch-protection-matches-by-name]: .github/workflows/pr-mutation.yml" {
  run grep -E -q -- branch\ protection\ matches\ required\ checks\ by\ name\ string "$REPO_ROOT/.github/workflows/pr-mutation.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: mutation-branch-protection-matches-by-name"
    echo "  source: .github/workflows/pr-mutation.yml:56"
    echo "  why:    Branch protection matches required checks by name string. That single fact is why job identifiers cannot be renamed casually, why two jobs may not share a name, and why a name field that differs from its identifier is a trap."
    echo "  Restore the string in .github/workflows/pr-mutation.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A ratio computed over a handful of samples is noise, so the gate only enforces its 
# WHY: threshold once the sample is large enough and reports without failing below that. 
# WHY: Otherwise one unkillable but harmless case fails an otherwise good change.
@test "pin[mutation-min-sample-before-gating]: .github/workflows/pr-mutation.yml" {
  run grep -E -q -- MINIMUM\ number\ of\ mutants\ before\ enforcing\ a\ score "$REPO_ROOT/.github/workflows/pr-mutation.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: mutation-min-sample-before-gating"
    echo "  source: .github/workflows/pr-mutation.yml:22"
    echo "  why:    A ratio computed over a handful of samples is noise, so the gate only enforces its threshold once the sample is large enough and reports without failing below that. Otherwise one unkillable but harmless case fails an otherwise good change."
    echo "  Restore the string in .github/workflows/pr-mutation.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The minimum sample size is a named constant next to the threshold it protects, so both 
# WHY: numbers are visible and adjustable in one place rather than being buried in a formula.
@test "pin[mutation-min-sample-constant]: .github/workflows/pr-mutation.yml" {
  run grep -E -q -- MIN_MUTANTS= "$REPO_ROOT/.github/workflows/pr-mutation.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: mutation-min-sample-constant"
    echo "  source: .github/workflows/pr-mutation.yml:234"
    echo "  why:    The minimum sample size is a named constant next to the threshold it protects, so both numbers are visible and adjustable in one place rather than being buried in a formula."
    echo "  Restore the string in .github/workflows/pr-mutation.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A missing analysis report, at a point where the run should have produced one, fails the 
# WHY: job rather than being treated as nothing to check. Treating a missing artefact as a pass 
# WHY: is precisely how a gate stops gating while still reporting green.
@test "pin[mutation-missing-report-fails]: .github/workflows/pr-mutation.yml" {
  run grep -E -q -- Fail\,\ do\ not\ skip "$REPO_ROOT/.github/workflows/pr-mutation.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: mutation-missing-report-fails"
    echo "  source: .github/workflows/pr-mutation.yml:221"
    echo "  why:    A missing analysis report, at a point where the run should have produced one, fails the job rather than being treated as nothing to check. Treating a missing artefact as a pass is precisely how a gate stops gating while still reporting green."
    echo "  Restore the string in .github/workflows/pr-mutation.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The enforcement step depends on nothing beyond the shell, because it previously relied on 
# WHY: an interpreter this job never installs and died with command-not-found after the 
# WHY: expensive work had already passed. Depending on a toolchain the job does not install is 
# WHY: how a gate goes quietly missing.
@test "pin[mutation-gate-needs-no-extra-toolchain]: .github/workflows/pr-mutation.yml" {
  run grep -E -q -- toolchain\ the\ job\ does\ not\ install "$REPO_ROOT/.github/workflows/pr-mutation.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: mutation-gate-needs-no-extra-toolchain"
    echo "  source: .github/workflows/pr-mutation.yml:216"
    echo "  why:    The enforcement step depends on nothing beyond the shell, because it previously relied on an interpreter this job never installs and died with command-not-found after the expensive work had already passed. Depending on a toolchain the job does not install is how a gate goes quietly missing."
    echo "  Restore the string in .github/workflows/pr-mutation.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The script that decides what the gate examines is tested on every run, before it is 
# WHY: trusted. A silently broken scope computation narrows the gate to nothing and reports 
# WHY: success over an empty set, which is indistinguishable from passing.
@test "pin[mutation-scope-script-is-self-tested]: .github/workflows/pr-mutation.yml" {
  run grep -E -q -- report\ a\ green\ mutation\ check\ over\ an\ empty "$REPO_ROOT/.github/workflows/pr-mutation.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: mutation-scope-script-is-self-tested"
    echo "  source: .github/workflows/pr-mutation.yml:155"
    echo "  why:    The script that decides what the gate examines is tested on every run, before it is trusted. A silently broken scope computation narrows the gate to nothing and reports success over an empty set, which is indistinguishable from passing."
    echo "  Restore the string in .github/workflows/pr-mutation.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Cancelling superseded runs is only safe for checks branch protection is not waiting on. 
# WHY: Cancelling a required check leaves it reported as cancelled and the change unmergeable, 
# WHY: so the decision has to be made per workflow against the current required set.
@test "pin[validation-cancel-safe-only-for-non-required]: .github/workflows/pr-validation.yml" {
  run grep -E -q -- would\ leave\ the\ PR\ unmergeable "$REPO_ROOT/.github/workflows/pr-validation.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: validation-cancel-safe-only-for-non-required"
    echo "  source: .github/workflows/pr-validation.yml:22"
    echo "  why:    Cancelling superseded runs is only safe for checks branch protection is not waiting on. Cancelling a required check leaves it reported as cancelled and the change unmergeable, so the decision has to be made per workflow against the current required set."
    echo "  Restore the string in .github/workflows/pr-validation.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Failures emit an error annotation that names the likely causes, so the reason surfaces in 
# WHY: the checks user interface rather than only in scrolled-past log output. A gate that fails 
# WHY: without saying what it means gets re-run rather than fixed.
@test "pin[validation-error-annotation-on-failure]: .github/workflows/pr-validation.yml" {
  run grep -E -q -- ::error:: "$REPO_ROOT/.github/workflows/pr-validation.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: validation-error-annotation-on-failure"
    echo "  source: .github/workflows/pr-validation.yml:92"
    echo "  why:    Failures emit an error annotation that names the likely causes, so the reason surfaces in the checks user interface rather than only in scrolled-past log output. A gate that fails without saying what it means gets re-run rather than fixed."
    echo "  Restore the string in .github/workflows/pr-validation.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A persistent runner keeps temporary files between runs, so a leftover file from a 
# WHY: previous run makes the next scan fail on a path collision. The cleanup reads the 
# WHY: operating system's temporary directory variable rather than assuming a hard-coded path, 
# WHY: and runs only where the runner is persistent.
@test "pin[secret-scan-stale-temp-on-persistent-runner]: .github/workflows/secret-scan.yml" {
  run grep -E -q -- TMPDIR:-/tmp "$REPO_ROOT/.github/workflows/secret-scan.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: secret-scan-stale-temp-on-persistent-runner"
    echo "  source: .github/workflows/secret-scan.yml:39"
    echo "  why:    A persistent runner keeps temporary files between runs, so a leftover file from a previous run makes the next scan fail on a path collision. The cleanup reads the operating system's temporary directory variable rather than assuming a hard-coded path, and runs only where the runner is persistent."
    echo "  Restore the string in .github/workflows/secret-scan.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Secret scanning needs the full history, not a shallow checkout, because a credential 
# WHY: committed earlier and removed later is still in the history and still leaked. A shallow 
# WHY: clone makes the scan pass on exactly the repositories that most need it to fail.
@test "pin[secret-scan-full-history-required]: .github/workflows/secret-scan.yml" {
  run grep -E -q -- fetch-depth:\[\[:space:\]\]\*0 "$REPO_ROOT/.github/workflows/secret-scan.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: secret-scan-full-history-required"
    echo "  source: .github/workflows/secret-scan.yml:30"
    echo "  why:    Secret scanning needs the full history, not a shallow checkout, because a credential committed earlier and removed later is still in the history and still leaked. A shallow clone makes the scan pass on exactly the repositories that most need it to fail."
    echo "  Restore the string in .github/workflows/secret-scan.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: A watchdog scheduled onto the runner it watches goes down with that runner, and its 
# WHY: silence is then indistinguishable from health. Pinning it to the hosted runner is the 
# WHY: only thing that makes it survive the failure it exists to report. It reads as an 
# WHY: inconsistency to anyone standardising runners across the repository, which is exactly why 
# WHY: the reason must stay written next to it.
@test "pin[ci-health-watchdog-must-not-run-on-the-runner-it-watches]: .github/workflows/ci-health-watch.yml" {
  run grep -E -q -- cannot\ report\ that\ runner\ dead "$REPO_ROOT/.github/workflows/ci-health-watch.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: ci-health-watchdog-must-not-run-on-the-runner-it-watches"
    echo "  source: .github/workflows/<CI-HEALTH-WATCH>.yml:9"
    echo "  why:    A watchdog scheduled onto the runner it watches goes down with that runner, and its silence is then indistinguishable from health. Pinning it to the hosted runner is the only thing that makes it survive the failure it exists to report. It reads as an inconsistency to anyone standardising runners across the repository, which is exactly why the reason must stay written next to it."
    echo "  Restore the string in .github/workflows/ci-health-watch.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The runner is a hard-coded hosted label, not one of the switchable runner variables every 
# WHY: other job here uses. Routing this job through a runner variable is a one-line change that 
# WHY: silently converts the watchdog into part of the thing it watches.
@test "pin[ci-health-runs-on-the-hosted-runner-literally]: .github/workflows/ci-health-watch.yml" {
  run grep -E -q -- \^\ +runs-on:\ ubuntu-latest "$REPO_ROOT/.github/workflows/ci-health-watch.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: ci-health-runs-on-the-hosted-runner-literally"
    echo "  source: .github/workflows/<CI-HEALTH-WATCH>.yml:56"
    echo "  why:    The runner is a hard-coded hosted label, not one of the switchable runner variables every other job here uses. Routing this job through a runner variable is a one-line change that silently converts the watchdog into part of the thing it watches."
    echo "  Restore the string in .github/workflows/ci-health-watch.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: An expired credential, a provider 5xx or a rate-limit blip mean the watch is BLIND, not 
# WHY: that something is wrong. Collapsing those into the alert path pages several times a day 
# WHY: about a problem that is not there, and the channel learns to skim past the alert that 
# WHY: matters. The accepted cost is stated openly: a silently broken credential stops the 
# WHY: paging entirely.
@test "pin[ci-health-could-not-check-is-not-an-incident]: .github/workflows/ci-health-watch.yml" {
  run grep -E -q -- COULD\ NOT\ CHECK\"\ IS\ NOT\ AN\ INCIDENT "$REPO_ROOT/.github/workflows/ci-health-watch.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: ci-health-could-not-check-is-not-an-incident"
    echo "  source: .github/workflows/<CI-HEALTH-WATCH>.yml:27"
    echo "  why:    An expired credential, a provider 5xx or a rate-limit blip mean the watch is BLIND, not that something is wrong. Collapsing those into the alert path pages several times a day about a problem that is not there, and the channel learns to skim past the alert that matters. The accepted cost is stated openly: a silently broken credential stops the paging entirely."
    echo "  Restore the string in .github/workflows/ci-health-watch.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The warning path and the alert path are two separate accumulators on purpose. Merging 
# WHY: them is the mechanical way the rule above gets undone: one variable means one severity, 
# WHY: and every could-not-check becomes an incident.
@test "pin[ci-health-two-accumulators-alerts-versus-warnings]: .github/workflows/ci-health-watch.yml" {
  run grep -E -q -- Two\ accumulators\,\ deliberately\ separate "$REPO_ROOT/.github/workflows/ci-health-watch.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: ci-health-two-accumulators-alerts-versus-warnings"
    echo "  source: .github/workflows/<CI-HEALTH-WATCH>.yml:81"
    echo "  why:    The warning path and the alert path are two separate accumulators on purpose. Merging them is the mechanical way the rule above gets undone: one variable means one severity, and every could-not-check becomes an incident."
    echo "  Restore the string in .github/workflows/ci-health-watch.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Without curl's fail-on-HTTP-error flag the client exits 0 and hands the JSON error body 
# WHY: to the parser, which makes an expired credential indistinguishable from a real finding. 
# WHY: The whole warning-versus-alert split above depends on this one flag being present.
@test "pin[ci-health-curl-must-fail-on-http-error]: .github/workflows/ci-health-watch.yml" {
  run grep -E -q -- makes\ curl\ fail\ \\\(exit\ 22\\\) "$REPO_ROOT/.github/workflows/ci-health-watch.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: ci-health-curl-must-fail-on-http-error"
    echo "  source: .github/workflows/<CI-HEALTH-WATCH>.yml:72"
    echo "  why:    Without curl's fail-on-HTTP-error flag the client exits 0 and hands the JSON error body to the parser, which makes an expired credential indistinguishable from a real finding. The whole warning-versus-alert split above depends on this one flag being present."
    echo "  Restore the string in .github/workflows/ci-health-watch.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: Until its credential exists the watch checks nothing, and it must say so rather than exit 
# WHY: green in silence. A check that quietly did nothing looks exactly like a check that found 
# WHY: nothing, and an unarmed watchdog that reports green is the most expensive kind of false 
# WHY: confidence available.
@test "pin[ci-health-unarmed-announces-that-it-checked-nothing]: .github/workflows/ci-health-watch.yml" {
  run grep -E -q -- ::notice\ title=CI\ health\ watch\ not\ armed:: "$REPO_ROOT/.github/workflows/ci-health-watch.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: ci-health-unarmed-announces-that-it-checked-nothing"
    echo "  source: .github/workflows/<CI-HEALTH-WATCH>.yml:24"
    echo "  why:    Until its credential exists the watch checks nothing, and it must say so rather than exit green in silence. A check that quietly did nothing looks exactly like a check that found nothing, and an unarmed watchdog that reports green is the most expensive kind of false confidence available."
    echo "  Restore the string in .github/workflows/ci-health-watch.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: When the hosted-minutes allowance runs out, every hosted job dies within seconds with no 
# WHY: runner assigned. That is a perfectly predictable state, but with nothing naming it in 
# WHY: advance it gets debugged as a mystery infrastructure fault. Alerting at a threshold, with 
# WHY: the remediation written into the alert text, turns a cliff into a planned move onto your 
# WHY: own runner.
@test "pin[ci-health-quota-exhaustion-is-a-known-state-not-a-mystery]: .github/workflows/ci-health-watch.yml" {
  run grep -E -q -- At\ 100%\ every\ hosted\ job\ dies\ within\ seconds\ with\ no\ runner\ assigned "$REPO_ROOT/.github/workflows/ci-health-watch.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: ci-health-quota-exhaustion-is-a-known-state-not-a-mystery"
    echo "  source: .github/workflows/<CI-HEALTH-WATCH>.yml:112"
    echo "  why:    When the hosted-minutes allowance runs out, every hosted job dies within seconds with no runner assigned. That is a perfectly predictable state, but with nothing naming it in advance it gets debugged as a mystery infrastructure fault. Alerting at a threshold, with the remediation written into the alert text, turns a cliff into a planned move onto your own runner."
    echo "  Restore the string in .github/workflows/ci-health-watch.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The job exits non-zero on a real finding rather than only writing a summary, so the 
# WHY: finding is red where people already look and not only in whatever channel the notifier 
# WHY: reaches. A watchdog whose only output is a step summary is a watchdog nobody reads.
@test "pin[ci-health-failure-is-red-in-the-actions-tab-too]: .github/workflows/ci-health-watch.yml" {
  run grep -E -q -- red\ in\ the\ Actions\ tab "$REPO_ROOT/.github/workflows/ci-health-watch.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: ci-health-failure-is-red-in-the-actions-tab-too"
    echo "  source: .github/workflows/<CI-HEALTH-WATCH>.yml:145"
    echo "  why:    The job exits non-zero on a real finding rather than only writing a summary, so the finding is red where people already look and not only in whatever channel the notifier reaches. A watchdog whose only output is a step summary is a watchdog nobody reads."
    echo "  Restore the string in .github/workflows/ci-health-watch.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The watchdog consumes the very allowance it is watching, and the header says how much. An 
# WHY: optional scheduled job whose cost is not written down is one an adopter cannot make an 
# WHY: informed decision about keeping, and the cadence is the only dial they have.
@test "pin[ci-health-states-its-own-running-cost]: .github/workflows/ci-health-watch.yml" {
  run grep -E -q -- Cost\,\ stated\ because\ an\ inert\ watchdog\ is\ not\ a\ free\ one "$REPO_ROOT/.github/workflows/ci-health-watch.yml"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: ci-health-states-its-own-running-cost"
    echo "  source: .github/workflows/<CI-HEALTH-WATCH>.yml:18"
    echo "  why:    The watchdog consumes the very allowance it is watching, and the header says how much. An optional scheduled job whose cost is not written down is one an adopter cannot make an informed decision about keeping, and the cadence is the only dial they have."
    echo "  Restore the string in .github/workflows/ci-health-watch.yml. Do NOT weaken the pin."
    false
  fi
}

# WHY: The second brain (docs/knowledge/) only pays for itself if every agent actually reads the 
# WHY: index at session start, cheaply, before doing its own work. Losing this checklist step 
# WHY: silently turns every card the fleet writes into dead weight nobody ever reads, while the 
# WHY: write path (the chief of staff's retrospective) keeps right on producing cards.
@test "pin[second-brain-read-path-checklist-step]: AGENTS.md" {
  run grep -F -q -- 4.\ Read\ \`docs/knowledge/INDEX.md\`.\ If\ a\ line\'s\ symptoms\ match\ your\ task\,\ read\ those "$REPO_ROOT/AGENTS.md"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: second-brain-read-path-checklist-step"
    echo "  source: AGENTS.md:136"
    echo "  why:    The second brain (docs/knowledge/) only pays for itself if every agent actually reads the index at session start, cheaply, before doing its own work. Losing this checklist step silently turns every card the fleet writes into dead weight nobody ever reads, while the write path (the chief of staff's retrospective) keeps right on producing cards."
    echo "  Restore the string in AGENTS.md. Do NOT weaken the pin."
    false
  fi
}

# WHY: The chief of staff is the ONLY agent that writes knowledge cards, in its self-gated 
# WHY: retrospective. Losing this line from its prompt silently removes the fleet's only write 
# WHY: path to docs/knowledge/ — the index and read path would keep working, but nothing would 
# WHY: ever add to them, and a system nobody feeds looks identical to one nobody built, from the 
# WHY: outside.
@test "pin[second-brain-distiller-two-questions]: .agents/prompts/chief-of-staff.md" {
  run grep -F -q -- -\ \*\*You\ are\ also\ the\ second\ brain\'s\ distiller\ —\ two\ added\ questions\,\ same\ evidence "$REPO_ROOT/.agents/prompts/chief-of-staff.md"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: second-brain-distiller-two-questions"
    echo "  source: .agents/prompts/chief-of-staff.md:63"
    echo "  why:    The chief of staff is the ONLY agent that writes knowledge cards, in its self-gated retrospective. Losing this line from its prompt silently removes the fleet's only write path to docs/knowledge/ — the index and read path would keep working, but nothing would ever add to them, and a system nobody feeds looks identical to one nobody built, from the outside."
    echo "  Restore the string in .agents/prompts/chief-of-staff.md. Do NOT weaken the pin."
    false
  fi
}

# WHY: The operator-facing standing decision is what makes docs/knowledge/'s write ownership 
# WHY: (chief-of-staff only, human-merged) an instruction rather than a convention an agent 
# WHY: could quietly drift from. This file is the only source of operator instructions 
# WHY: (AGENTS.md), so a rule that exists only in a plan document or a runbook prose paragraph 
# WHY: elsewhere is not binding on any agent until it is also stated here.
@test "pin[second-brain-standing-decision-ownership]: docs/runbooks/agent-modes.md" {
  run grep -F -q -- \ \ written\ by\ exactly\ one.\*\*\ Every\ agent\ reads\ \`docs/knowledge/INDEX.md\`\ after\ its\ ledger "$REPO_ROOT/docs/runbooks/agent-modes.md"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: second-brain-standing-decision-ownership"
    echo "  source: docs/runbooks/agent-modes.md:347"
    echo "  why:    The operator-facing standing decision is what makes docs/knowledge/'s write ownership (chief-of-staff only, human-merged) an instruction rather than a convention an agent could quietly drift from. This file is the only source of operator instructions (AGENTS.md), so a rule that exists only in a plan document or a runbook prose paragraph elsewhere is not binding on any agent until it is also stated here."
    echo "  Restore the string in docs/runbooks/agent-modes.md. Do NOT weaken the pin."
    false
  fi
}

# WHY: Docs freshness only gets full coverage by sweeping every file every run and fixing in 
# WHY: small batches, never by scoping to a sample. Losing the sweep-all requirement turns this 
# WHY: into an agent that only ever notices the files it happened to look at last time, which is 
# WHY: indistinguishable from no coverage guarantee at all.
@test "pin[docs-freshness-sweep-all-fix-batched]: .agents/prompts/docs-freshness.md" {
  run grep -F -q -- 1.\ \*\*Sweep\ ALL\ tracked\ markdown\*\*\,\ every\ run\ —\ never\ a\ sample\ and\ never\ a\ subset\ chosen "$REPO_ROOT/.agents/prompts/docs-freshness.md"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: docs-freshness-sweep-all-fix-batched"
    echo "  source: .agents/prompts/docs-freshness.md:16"
    echo "  why:    Docs freshness only gets full coverage by sweeping every file every run and fixing in small batches, never by scoping to a sample. Losing the sweep-all requirement turns this into an agent that only ever notices the files it happened to look at last time, which is indistinguishable from no coverage guarantee at all."
    echo "  Restore the string in .agents/prompts/docs-freshness.md. Do NOT weaken the pin."
    false
  fi
}

# WHY: Closing on a merge alone re-creates the exact failure agent-modes.md's standing decision 
# WHY: exists to prevent: an issue marked done while production has not moved. Losing this line 
# WHY: from the groomer's own prompt would let its per-run close cap keep working while the 
# WHY: closes themselves stopped meaning anything.
@test "pin[backlog-groomer-evidence-only-closes]: .agents/prompts/backlog-groomer.md" {
  run grep -F -q -- 2.\ \*\*Evidence-only\ closes.\*\*\ Close\ an\ issue\ only\ on\ a\ recorded\ \`fix_verified\`\ entry\ from "$REPO_ROOT/.agents/prompts/backlog-groomer.md"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: backlog-groomer-evidence-only-closes"
    echo "  source: .agents/prompts/backlog-groomer.md:20"
    echo "  why:    Closing on a merge alone re-creates the exact failure agent-modes.md's standing decision exists to prevent: an issue marked done while production has not moved. Losing this line from the groomer's own prompt would let its per-run close cap keep working while the closes themselves stopped meaning anything."
    echo "  Restore the string in .agents/prompts/backlog-groomer.md. Do NOT weaken the pin."
    false
  fi
}

# WHY: This is the one agent with standing write access to floors.yml's neighbourhood, so the 
# WHY: one-directional constraint has to live in its own prompt and not only in 
# WHY: docs/QUALITY-GATES.md's policy — an agent that can propose both directions is an agent 
# WHY: that can eventually make the ratchet mean nothing.
@test "pin[test-gap-ratchet-only-tightens]: .agents/prompts/test-gap.md" {
  run grep -F -q -- 1.\ \*\*The\ ratchet\ only\ tightens.\*\*\ Every\ floor\ in\ \`floors.yml\`\ may\ only\ ever\ move\ up "$REPO_ROOT/.agents/prompts/test-gap.md"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: test-gap-ratchet-only-tightens"
    echo "  source: .agents/prompts/test-gap.md:16"
    echo "  why:    This is the one agent with standing write access to floors.yml's neighbourhood, so the one-directional constraint has to live in its own prompt and not only in docs/QUALITY-GATES.md's policy — an agent that can propose both directions is an agent that can eventually make the ratchet mean nothing."
    echo "  Restore the string in .agents/prompts/test-gap.md. Do NOT weaken the pin."
    false
  fi
}

# WHY: A batched dependency-upgrade pull request is unreviewable and untraceable when something 
# WHY: breaks — nobody can tell which of ten bumps caused the regression. Losing the 
# WHY: one-per-run cap would let this agent silently regress into exactly the kind of change 
# WHY: nothing else in the gauntlet is built to review well.
@test "pin[dependency-steward-one-upgrade-per-run]: .agents/prompts/dependency-steward.md" {
  run grep -F -q -- 2.\ \*\*One\ bounded\ upgrade\ pull\ request\ per\ run\*\*\,\ never\ a\ batch.\ Pick\ the\ single\ upgrade "$REPO_ROOT/.agents/prompts/dependency-steward.md"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: dependency-steward-one-upgrade-per-run"
    echo "  source: .agents/prompts/dependency-steward.md:20"
    echo "  why:    A batched dependency-upgrade pull request is unreviewable and untraceable when something breaks — nobody can tell which of ten bumps caused the regression. Losing the one-per-run cap would let this agent silently regress into exactly the kind of change nothing else in the gauntlet is built to review well."
    echo "  Restore the string in .agents/prompts/dependency-steward.md. Do NOT weaken the pin."
    false
  fi
}

# WHY: Every other agent in this fleet is barred from merging its own work; the release 
# WHY: drafter's equivalent boundary is that it drafts and a human tags. Losing this line is the 
# WHY: one way this agent's job description could silently expand into the one irreversible 
# WHY: action nothing else in the fleet is allowed to take either.
@test "pin[release-drafter-never-tags-or-publishes]: .agents/prompts/release-drafter.md" {
  run grep -F -q -- human\ can\ read\ and\ decide\ about.\ \*\*You\ never\ tag\,\ publish\,\ or\ otherwise\ perform\ a "$REPO_ROOT/.agents/prompts/release-drafter.md"
  if [ "$status" -ne 0 ]; then
    echo "PIN LOST: release-drafter-never-tags-or-publishes"
    echo "  source: .agents/prompts/release-drafter.md:12"
    echo "  why:    Every other agent in this fleet is barred from merging its own work; the release drafter's equivalent boundary is that it drafts and a human tags. Losing this line is the one way this agent's job description could silently expand into the one irreversible action nothing else in the fleet is allowed to take either."
    echo "  Restore the string in .agents/prompts/release-drafter.md. Do NOT weaken the pin."
    false
  fi
}

# --- semantic-manual entries: hand-discharged, not asserted by this file ---
# SEMANTIC-MANUAL (hand-discharged, not asserted): review-model-pinned-not-floating-alias
#   concept: The model that performs a judgement task is selected by an exact, versioned identifier and the reason for pinning is written down next to it.
#   discharged: .github/workflows/review.yml — reviewer A step comment: the model is taken from `models.judge` and pinned by exact id, with the drift reason stated next to it. See tests/harness-guards/semantic-discharges.md row 1.
# SEMANTIC-MANUAL (hand-discharged, not asserted): review-standards-doc-paths
#   concept: Reviewer instructions cite the repository's own standards documents by path instead of relying on the model's general taste.
#   discharged: .github/workflows/review.yml — same comment block: the reviewer is anchored to this repository's own standards by path (AGENTS.md, docs/runbooks/), not to generic best practice. See tests/harness-guards/semantic-discharges.md row 2.
# SEMANTIC-MANUAL (hand-discharged, not asserted): handoff-files-issue-not-comment
#   concept: Cross-workflow handoff from a read-only reviewer to a write-capable fixer travels by filing an issue, precisely because the comment path is deliberately unreachable for bot senders.
#   discharged: .github/workflows/review.yml — the handoff step files an issue because `issues: [opened]` is the one steward trigger with no bot-sender check, which is stated inline with the loop-guard reasoning. See tests/harness-guards/semantic-discharges.md row 3.
# SEMANTIC-MANUAL (hand-discharged, not asserted): handoff-warns-loudly-when-elevated-token-absent
#   concept: Degradation to the non-triggering default token is announced in both channels a human might read, rather than being absorbed silently.
#   discharged: .github/workflows/review.yml — a `::warning::` annotation AND a `> [!WARNING]` block in the issue body, both naming STEWARD_HANDOFF_PAT. See tests/harness-guards/semantic-discharges.md row 4.
# SEMANTIC-MANUAL (hand-discharged, not asserted): carveout-silences-both-reviewers
#   concept: A shared execution path means a single guard trip removes the whole reviewing capability, not one of two opinions.
#   discharged: .github/workflows/review.yml — the supply-chain carve-out notice states that both reviewers are affected and that the green check means the job exited cleanly, not that anything was reviewed. See tests/harness-guards/semantic-discharges.md row 5.
# SEMANTIC-MANUAL (hand-discharged, not asserted): review-clean-phrase-literal
#   concept: Exactly one literal phrase means clean; everything else, including malformed output, means escalate.
#   discharged: .github/workflows/review.yml + tools/review-handoff-decide.sh — the single-value test moved from a phrase in a review body to the referee's one-word merge verdict: `elif [ "$VERDICT" = "non-blocking" ]`, with every other value — blocking, undecided, empty, missing, unrecognised — waking the steward. See tests/harness-guards/semantic-discharges.md row 6.
#   SUPERSEDED 2026-08-09 -> docs/runbooks/multi-model-review.md — "The merge verdict — who wakes the steward"; guarded by tests/harness-guards/steward-handoff-decision.bats and tests/harness-guards/steward-handoff-order.bats
#   SUPERSEDED why: The clean phrase was a code-review PLUGIN's marker, and this template does not run that plugin. Neither .agents/prompts/review-judge.md nor review-challenge.md asks for the phrase, and prose never contains it, so EVERY review that landed counted as findings and every agent pull request woke the steward — which pushed commits onto pull requests both reviewers had approved and reset CI. Upstream measured 46 such issues before finding the same defect. The decision now belongs to the referee, which already reads both reviews and the pinned diff: it writes one word to .review-artifacts/referee-verdict.txt and that word decides. THE CONCEPT THIS ENTRY NAMES SURVIVES INTACT and must not be lost — exactly one value (`non-blocking`) means "leave it alone", and everything else, including malformed output, a missing file and a word nobody recognises, escalates. Only the thing being read changed: a phrase in prose an agent was never asked to emit, for a single word it is. The direction-of-error rule is the part to defend in any future replacement.
# SEMANTIC-MANUAL (hand-discharged, not asserted): reviewer-b-gate-warning-one-reviewer
#   concept: Missing optional credential produces a warning annotation naming the secret and stating the reduced level of assurance, then continues.
#   discharged: OPEN — not yet discharged
# SEMANTIC-MANUAL (hand-discharged, not asserted): reviewer-b-must-not-read-first-review
#   concept: Independence of the second opinion is enforced in the instructions, not merely hoped for.
#   discharged: .github/workflows/review.yml — reviewer B step comment states the prohibition and the reason: agreement it copied is noise. See tests/harness-guards/semantic-discharges.md row 8.
# SEMANTIC-MANUAL (hand-discharged, not asserted): reviewer-marker-required-first-line
#   concept: A mandatory, machine-readable, first-line role marker on every posted review.
#   discharged: .github/workflows/review.yml — both reviewer step comments state the exact first-line marker as a non-optional part of the contract. See tests/harness-guards/semantic-discharges.md row 9.
# SEMANTIC-MANUAL (hand-discharged, not asserted): reviewer-marker-same-bot-account
#   concept: Author identity cannot discriminate between agent roles; the marker is the only discriminator, and the reason is recorded next to the requirement.
#   discharged: .github/workflows/review.yml — 'Every role posts from the SAME bot account, so nothing downstream can tell two reviews apart by author; the marker is the only discriminator.' See tests/harness-guards/semantic-discharges.md row 10.
# SEMANTIC-MANUAL (hand-discharged, not asserted): referee-gated-on-b-having-run
#   concept: A dependent aggregation job is gated on an explicit did-it-actually-run output from its dependency, and skips rather than fails when the dependency degraded.
#   discharged: .github/workflows/review.yml — the referee's `if:` requires needs.challenge-review.outputs.ran == 'true', so an absent optional credential skips rather than fails. See tests/harness-guards/semantic-discharges.md row 11.
# SEMANTIC-MANUAL (hand-discharged, not asserted): collector-single-endpoint-must-merge-both
#   concept: Complete comment collection requires both the issue-comments endpoint and the pull-request review-comments endpoint, merged into one list before filtering.
#   discharged: .github/workflows/review.yml — both collectors read the issue-comments AND pull-request review-comments endpoints, slurp before filtering, merge, filter by the `<!-- reviewer: ... -->` role marker, and sort_by(.created_at) before `last`. The marker filter was MISSING on the first pass and this pin was wrongly recorded as discharged; behaviourally asserted now by tests/harness-guards/review-collector.bats. See tests/harness-guards/semantic-discharges.md row 12.
# SEMANTIC-MANUAL (hand-discharged, not asserted): review-selection-must-not-use-exclusion
#   concept: Positive per-role marker matching, not exclusion of the other role and not recency.
#   discharged: .github/workflows/review.yml — VARIANT, tightened: both roles emit their own marker and both are selected by positive match, where the source selected role A by excluding role B's marker. See tests/harness-guards/semantic-discharges.md row 13.
# SEMANTIC-MANUAL (hand-discharged, not asserted): steward-mention-required-on-every-other-trigger
#   concept: Mention-gating on every non-auto-triage trigger, alongside the bot-sender exclusion.
#   discharged: .github/workflows/steward.yml — contains(..., vars.AGENT_MENTION || '@agent') ANDed with sender.type != 'Bot' on all three comment and review triggers. See tests/harness-guards/semantic-discharges.md row 14.
# SEMANTIC-MANUAL (hand-discharged, not asserted): steward-agent-invocation-step
#   concept: A single, replaceable agent-invocation step with all policy expressed outside it.
#   discharged: .github/workflows/steward.yml — one `tools/run-agent.sh steward` step replaces the vendor action block; gates, concurrency, outcome check and eviction reporter are unchanged around it. See tests/harness-guards/semantic-discharges.md row 15.
# SEMANTIC-MANUAL (hand-discharged, not asserted): notifier-secondary-channel-degrades-to-summary
#   concept: Optional secondary alert channel degrades to an explicit, visible note without failing the notifier or burying the original failure.
#   discharged: .github/workflows/nightly-alert.yml — a missing webhook writes a $GITHUB_STEP_SUMMARY block and exits 0, and a delivery failure gets the same treatment. See tests/harness-guards/semantic-discharges.md row 16.
# SEMANTIC-MANUAL (hand-discharged, not asserted): pr-tests-changes-outputs-per-stack
#   concept: One named per-stack boolean output on the change-detector job, consumed by every gate.
#   discharged: .github/workflows/pr-tests.yml — changes.outputs.backend / .frontend consumed at BOTH job level and step level, which is what makes a stack-absent gate report skipped rather than never report. See tests/harness-guards/semantic-discharges.md row 17.
# SEMANTIC-MANUAL (hand-discharged, not asserted): runner-selection-switchable-variable
#   concept: Runner placement is configuration with a safe hosted fallback, not a hard-coded label.
#   discharged: .github/workflows/pr-tests.yml — runs-on: ${{ vars.PR_RUNNER || 'ubuntu-latest' }} on every gate job. Deliberate exception: ci-health-watch.yml and the notifier it calls are pinned hosted. See tests/harness-guards/semantic-discharges.md row 18.
# SEMANTIC-MANUAL (hand-discharged, not asserted): pr-tests-required-job-names
#   concept: Job identifiers double as required-check context strings and are part of the repository's public configuration surface.
#   discharged: .github/workflows/pr-tests.yml — VARIANT, stronger: the twelve frozen ids are in place with NO `name:` key at all, so the context IS the id and the two cannot diverge. See tests/harness-guards/semantic-discharges.md row 19.
# SEMANTIC-MANUAL (hand-discharged, not asserted): validation-workflow-paths-filter-must-be-converted
#   concept: Trigger-level path filtering is replaced by a change-detector job feeding a job-level condition, so the check can be made required.
#   discharged: .github/workflows/pr-validation.yml — no workflow-level paths:; a migration-scope detector job feeds a job-level if:. See tests/harness-guards/semantic-discharges.md row 20.
# SEMANTIC-MANUAL (hand-discharged, not asserted): validation-required-set-is-named
#   concept: Any decision that depends on which checks are required names those checks inline, next to the decision.
#   discharged: .github/workflows/pr-validation.yml — both tiers' context strings enumerated inline at the cancel-in-progress justification, with the two not-yet-in-the-tree contexts marked. See tests/harness-guards/semantic-discharges.md row 21.
# SEMANTIC-MANUAL (hand-discharged, not asserted): secret-scan-job-name-differs-from-id
#   concept: The reported check context is the job name when present, otherwise the identifier; a mismatch between the two silently orphans branch protection.
#   discharged: .github/workflows/secret-scan.yml — the job is fast-secret-scan with no `name:` key, so id and context can never diverge. Upstream defect fixed. See tests/harness-guards/semantic-discharges.md row 22.
# SEMANTIC-MANUAL (hand-discharged, not asserted): ci-health-finding-must-reach-a-human-outside-the-actions-tab
#   concept: An operational watchdog's finding reaches a human through the repository's own notifier, not only through a red square in the Actions tab.
#   discharged: .github/workflows/ci-health-watch.yml — job `notify-ci-health` calls ./.github/workflows/nightly-alert.yml with gate 'CI health — runner liveness and hosted minutes' at S2, gated on needs.watch-ci-health.result == 'failure', and passes runner: 'ubuntu-latest' explicitly. The explicit runner is part of the discharge, not decoration: a called workflow's runs-on cannot be overridden by its caller, so without it the alarm for a dead self-hosted runner queued on the dead runner. See tests/harness-guards/semantic-discharges.md row 23.
