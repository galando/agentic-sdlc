#!/usr/bin/env bats
#
# tools/review-handoff-decide.sh — the decision, on its own.
#
# This logic was a step body inside review.yml, testable only by carving it out of YAML
# first. It is a script now, so it can simply be run — and this file is what that buys:
# every decision, each with the failure it protects against, and no workflow, no stubbed
# API and no extraction anywhere in sight.
#
# `steward-handoff-decision.bats` still exercises the step that CALLS this, because the
# acting half — which issue gets filed, with which token — is the workflow's.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
TOOL="$REPO_ROOT/tools/review-handoff-decide.sh"

setup() { WORK="$(mktemp -d)"; export WORK; }
teardown() { rm -rf "$WORK"; }

# $1 judge body ("" = file absent), $2 challenge body, $3 verdict ("" = file absent),
# $4 collector outcome; anything after that is passed through (--merged-at, --pr-state,
# --lost-reviewer, --quota-line). With none of those the pull request reads as OPEN.
decide() {
  [ -n "${1:-}" ] && printf '%s\n' "$1" > "$WORK/judge.md"     || rm -f "$WORK/judge.md"
  [ -n "${2:-}" ] && printf '%s\n' "$2" > "$WORK/challenge.md" || rm -f "$WORK/challenge.md"
  [ -n "${3:-}" ] && printf '%s\n' "$3" > "$WORK/verdict.txt"  || rm -f "$WORK/verdict.txt"
  local outcome="${4:-success}"
  shift 4 2>/dev/null || shift $#
  "$TOOL" --judge "$WORK/judge.md" --challenge "$WORK/challenge.md" \
          --verdict "$WORK/verdict.txt" --collector-outcome "$outcome" "$@"
}

REVIEW="Looks mostly fine. One thing: src/a.js:10 drops the error."

@test "decide: a blocking verdict wakes the steward" {
  run decide "$REVIEW" "$REVIEW" blocking
  [[ "$output" == *"DECISION=findings"* ]]
  [[ "$output" == *'VERDICT="blocking"'* ]]
  [[ "$output" == *"VERDICT_RECOGNISED=true"* ]]
}

@test "decide: a non-blocking verdict on an OPEN pull request MARKS it and wakes nobody" {
  # Not `followup` any more. An issue filed while the pull request is still open is
  # stale on arrival — the author usually fixes these on the branch within hours. The
  # pull request is labelled instead, and the merge decides whether an issue is filed.
  run decide "$REVIEW" "$REVIEW" non-blocking
  [[ "$output" == *"DECISION=mark"* ]]
  [[ "$output" == *"VERDICT_RECOGNISED=true"* ]]
  [[ "$output" == *"PR_GONE="$'\n'* ]]
}

@test "decide: a non-blocking verdict on a MERGED pull request files the follow-up now" {
  # No merge is left to catch the label, so the findings are filed at once.
  run decide "$REVIEW" "$REVIEW" non-blocking success --merged-at 2026-09-01T10:00:00Z
  [[ "$output" == *"DECISION=followup"* ]]
  [[ "$output" == *"PR_GONE=merged"* ]]
  # The state alone is enough too — a merge time is not the only way to learn it.
  run decide "$REVIEW" "$REVIEW" non-blocking success --pr-state MERGED
  [[ "$output" == *"DECISION=followup"* ]]
  [[ "$output" == *"PR_GONE=merged"* ]]
  run decide "$REVIEW" "$REVIEW" non-blocking success --pr-state CLOSED
  [[ "$output" == *"DECISION=followup"* ]]
  [[ "$output" == *"PR_GONE=closed"* ]]
}

@test "decide: an UNREADABLE pull-request state reads as open" {
  # A missing input must never read as "nothing to do" — and the open path is the one
  # that still acts (marks, or files the handoff).
  run decide "$REVIEW" "$REVIEW" non-blocking success --pr-state UNREADABLE
  [[ "$output" == *"DECISION=mark"* ]]
  run decide "$REVIEW" "$REVIEW" blocking success --pr-state UNREADABLE
  [[ "$output" == *"DECISION=findings"* ]]
}

@test "decide: a waking verdict on a MERGED pull request is RE-AIMED, and the title word is the verdict read" {
  # The re-aimed follow-up used to say "Blocking findings" whatever the verdict was, and
  # an issue filed that way was closed with "there is nothing to land". `Blocking` only
  # when the verdict actually read `blocking`; everything else is `Unsettled`.
  run decide "$REVIEW" "$REVIEW" blocking success --merged-at 2026-09-01T10:00:00Z
  [[ "$output" == *"DECISION=reaim"* ]]
  [[ "$output" == *"REAIM_WORD=Blocking"* ]]
  for raw in undecided "" merge; do
    run decide "$REVIEW" "$REVIEW" "$raw" success --merged-at 2026-09-01T10:00:00Z
    [[ "$output" == *"DECISION=reaim"* ]] || { echo "not re-aimed: [$raw] -> $output"; return 1; }
    [[ "$output" == *"REAIM_WORD=Unsettled"* ]] || { echo "wrong word: [$raw] -> $output"; return 1; }
  done
  # And a closed, unmerged pull request has no branch to push to either.
  run decide "$REVIEW" "$REVIEW" blocking success --pr-state CLOSED
  [[ "$output" == *"DECISION=reaim"* ]]
  [[ "$output" == *"PR_GONE=closed"* ]]
}

@test "decide: undecided wakes the steward — a missing answer is not 'nothing to do'" {
  run decide "$REVIEW" "$REVIEW" undecided
  [[ "$output" == *"DECISION=findings"* ]]
  # A recognised word, so the caller can say the referee ruled rather than blame a defect.
  [[ "$output" == *"VERDICT_RECOGNISED=true"* ]]
}

@test "decide: PROSE ALONE NEVER DECIDES — the bug this replaced" {
  # THE DEFECT. This script used to grep both bodies for the literal "No issues found",
  # a code-review plugin's clean marker. Nothing in this repository emits it: both
  # reviewer prompts ask for prose. So every landed review counted as findings and every
  # agent pull request woke the steward. Two reviews that plainly approve must now be
  # able to reach a non-blocking outcome, and a review that plainly does not must not be
  # able to reach one — on the referee's word, not on any phrase in the prose.
  run decide "Approve. Nothing blocks merge." "Approve, no findings." non-blocking
  [[ "$output" == *"DECISION=mark"* ]]

  run decide "No issues found." "No issues found." blocking
  [[ "$output" == *"DECISION=findings"* ]]
}

@test "decide: a MISSING verdict file wakes the steward" {
  # The fail-safe. A referee that died, was skipped, or wrote nothing must never read as
  # "nothing to do" — one wasted run against a lost finding is not a close call.
  run decide "$REVIEW" "$REVIEW" ""
  [[ "$output" == *"DECISION=findings"* ]]
  [[ "$output" == *'VERDICT=""'* ]]
  [[ "$output" == *"VERDICT_RECOGNISED=false"* ]]
}

@test "decide: an UNRECOGNISED verdict wakes the steward" {
  run decide "$REVIEW" "$REVIEW" "merge"
  [[ "$output" == *"DECISION=findings"* ]]
  [[ "$output" == *"VERDICT_RECOGNISED=false"* ]]
}

@test "decide: an empty verdict file wakes the steward" {
  printf '%s\n' "$REVIEW" > "$WORK/judge.md"
  printf '%s\n' "$REVIEW" > "$WORK/challenge.md"
  : > "$WORK/verdict.txt"
  run "$TOOL" --judge "$WORK/judge.md" --challenge "$WORK/challenge.md" \
              --verdict "$WORK/verdict.txt" --collector-outcome success
  [[ "$output" == *"DECISION=findings"* ]]
  [[ "$output" == *"VERDICT_RECOGNISED=false"* ]]
}

@test "decide: the verdict is normalised, not taken literally" {
  # An agent asked for one bare word will sometimes wrap it in markdown, capitalise it,
  # bullet it, lead with a blank line, or add a trailing sentence. None of those is a
  # different answer, and treating them as unrecognised would fire the fail-safe on a
  # referee that ruled correctly — which is a wasted steward run every time.
  for raw in "Non-Blocking" '`non-blocking`' "**non-blocking**" "- non-blocking" \
             "non-blocking
and here is why" "
non-blocking"; do
    run decide "$REVIEW" "$REVIEW" "$raw"
    [[ "$output" == *"DECISION=mark"* ]] || {
      echo "not normalised: [$raw] -> $output"; return 1
    }
  done
}

@test "decide: normalisation stops well short of guessing" {
  # The other half of the rule. A fail-safe that stretches to cover near-misses is not a
  # fail-safe — each of these wakes the steward, and that is correct.
  for raw in "not blocking" "nonblocking" "no" "merge" "LGTM" "blocking?"; do
    run decide "$REVIEW" "$REVIEW" "$raw"
    [[ "$output" == *"DECISION=findings"* ]] || {
      echo "should have woken the steward: [$raw] -> $output"; return 1
    }
  done
}

# ---------------------------------------------------------------------------
# --verdict-only: ONE normalisation, shared by the step that reports the verdict and the
# step that acts on it.
#
# They used to have a copy each — the same pipeline written out twice, under a comment
# claiming the log and the decision could not disagree. Two copies is precisely how they
# would have come to disagree, and the operator reading the log would have been the last
# to find out.
# ---------------------------------------------------------------------------

@test "verdict-only: prints the verdict and nothing else" {
  printf 'non-blocking\n' > "$WORK/verdict.txt"
  run "$TOOL" --verdict "$WORK/verdict.txt" --verdict-only
  [ "$status" -eq 0 ]
  [[ "$output" == *'VERDICT="non-blocking"'* ]]
  [[ "$output" == *"VERDICT_RECOGNISED=true"* ]]
  # No decision is made in this mode — that needs the reviews, which this mode never reads.
  [[ "$output" != *"DECISION="* ]]
  [[ "$output" != *"REVIEWS_LANDED="* ]]
}

@test "verdict-only: needs no reviews, but still needs a verdict path" {
  run "$TOOL" --verdict-only
  [ "$status" -eq 2 ]
  [[ "$output" == *"--verdict is required"* ]]
}

@test "verdict-only: THE SAME WORD the full decision acts on, case for case" {
  # The property that makes one implementation worth having. If these two ever disagree,
  # the workflow logs one verdict to the operator and acts on another.
  for raw in "blocking" "non-blocking" "undecided" "**Non-Blocking**" "- undecided" \
             "merge" "not blocking" ""; do
    [ -n "$raw" ] && printf '%s\n' "$raw" > "$WORK/verdict.txt" || rm -f "$WORK/verdict.txt"
    printf '%s\n' "$REVIEW" > "$WORK/judge.md"
    printf '%s\n' "$REVIEW" > "$WORK/challenge.md"

    only="$("$TOOL" --verdict "$WORK/verdict.txt" --verdict-only | grep '^VERDICT=')"
    full="$("$TOOL" --judge "$WORK/judge.md" --challenge "$WORK/challenge.md" \
                    --verdict "$WORK/verdict.txt" --collector-outcome success \
            | grep '^VERDICT=')"
    [ "$only" = "$full" ] || {
      echo "drift on [$raw]: verdict-only=$only full=$full"; return 1
    }
  done
}

@test "decide: a verdict file cannot inject shell into the caller" {
  # Every other value here comes from counting or a fixed vocabulary. This one starts life
  # in a file an agent wrote, and the caller sources the output, so the charset reduction
  # is the boundary.
  run decide "$REVIEW" "$REVIEW" 'x";touch "$WORK/pwned";#'
  [ "$status" -eq 0 ]
  [[ "$output" == *"DECISION=findings"* ]]
  # shellcheck disable=SC1090
  ( set -euo pipefail; . <(decide "$REVIEW" "$REVIEW" 'x";touch "$WORK/pwned";#') )
  [ ! -e "$WORK/pwned" ]
}

@test "decide: one review that never landed is still judged on the verdict" {
  run decide "$REVIEW" "" non-blocking
  [[ "$output" == *"DECISION=mark"* ]]
  [[ "$output" == *'REVIEWS_PRESENT="the judge role"'* ]]
  [[ "$output" == *"REVIEWS_LANDED=1"* ]]
}

@test "decide: nothing landed and the collector was fine means none" {
  # Whatever the verdict says. No review landed, so there is nothing to rule on, and the
  # review job's lost-review check already owns this case.
  run decide "" "" blocking success
  [[ "$output" == *"DECISION=none"* ]]
}

@test "decide: nothing landed because the COLLECTOR FAILED is a different decision" {
  # Identical on disk to the case above, opposite meaning: the reviews are on the pull
  # request with real findings, and the lost-review check filed nothing because it saw
  # them. Collapsing these two is how the handoff came to exit quietly and wake nobody.
  run decide "" "" "" failure
  [[ "$output" == *"DECISION=collector-failed"* ]]
  run decide "" "" "" cancelled
  [[ "$output" == *"DECISION=collector-failed"* ]]
}

@test "decide: a one-byte review file is 'posted nothing', not 'a review that landed'" {
  # The collector writes an empty result as a lone newline. Counting that as a review
  # would let a pull request nobody reviewed reach the verdict branch at all.
  printf '\n' > "$WORK/judge.md"
  printf '%s\n' "$REVIEW" > "$WORK/challenge.md"
  printf 'blocking\n' > "$WORK/verdict.txt"
  run "$TOOL" --judge "$WORK/judge.md" --challenge "$WORK/challenge.md" \
              --verdict "$WORK/verdict.txt" --collector-outcome success
  [[ "$output" == *"REVIEWS_LANDED=1"* ]]
  [[ "$output" == *'REVIEWS_PRESENT="the challenge role"'* ]]
}

@test "decide: a missing argument is a loud usage error" {
  run "$TOOL" --judge "$WORK/judge.md" --challenge "$WORK/challenge.md" \
              --collector-outcome success
  [ "$status" -eq 2 ]
  [[ "$output" == *"--verdict is required"* ]]
}

@test "decide: the output is safe to source" {
  printf '%s\n' "$REVIEW" > "$WORK/judge.md"
  printf '%s\n' "$REVIEW" > "$WORK/challenge.md"
  printf 'non-blocking\n' > "$WORK/verdict.txt"
  # shellcheck disable=SC1090
  ( set -euo pipefail
    . <("$TOOL" --judge "$WORK/judge.md" --challenge "$WORK/challenge.md" \
                --verdict "$WORK/verdict.txt" --collector-outcome success)
    [ "$DECISION" = "mark" ]
    [ "$REVIEWS_LANDED" = "2" ]
    [ "$VERDICT" = "non-blocking" ]
    [ "$VERDICT_RECOGNISED" = "true" ]
    [ "$PR_GONE" = "" ]
    [ "$REAIM_WORD" = "Unsettled" ] )
}

# ---------------------------------------------------------------------------
# The spent-allowance carve-out. A reviewer whose allowance is spent ends its job in
# seconds and writes nothing; the referee then has no verdict, and the fail-safe would
# wake the steward for a pull request that has nothing to hand over. The carve-out is
# deliberately narrow — ALL FOUR conditions, and any lookup failure files the handoff.
# ---------------------------------------------------------------------------

QUOTA="Usage limit reached for this billing period, resets at 04:00 UTC"

@test "quota: all four conditions hold — no verdict, one reviewer silent, its log names a refusal, PR open" {
  run decide "$REVIEW" "" "" success --lost-reviewer challenge --quota-line "$QUOTA"
  [[ "$output" == *"DECISION=quota-skip"* ]]
  [[ "$output" == *"REVIEWS_LANDED=1"* ]]
}

@test "quota: the literal word 'undecided' is NOT an absent verdict" {
  # An explicit `undecided` means the referee RAN and could not decide — a real finding
  # about the review, which still wakes the steward.
  run decide "$REVIEW" "" undecided success --lost-reviewer challenge --quota-line "$QUOTA"
  [[ "$output" == *"DECISION=findings"* ]]
}

@test "quota: an EMPTY quota line files the handoff — the anti-vacuity case" {
  # Both log fetches came back empty, so the cause is unknown. A dead runner and a spent
  # allowance end a job identically and have opposite remedies; without the log saying
  # which, the safe direction is to file.
  run decide "$REVIEW" "" "" success --lost-reviewer challenge --quota-line ""
  [[ "$output" == *"DECISION=findings"* ]]
  run decide "$REVIEW" "" "" success --lost-reviewer challenge
  [[ "$output" == *"DECISION=findings"* ]]
}

@test "quota: no named lost reviewer files the handoff" {
  run decide "$REVIEW" "" "" success --quota-line "$QUOTA"
  [[ "$output" == *"DECISION=findings"* ]]
}

@test "quota: both reviews landed means nothing was refused — the handoff is filed" {
  # The quota line cannot be about a reviewer that posted. Two reviews and no verdict is
  # a referee defect, and the fail-safe wakes the steward for it.
  run decide "$REVIEW" "$REVIEW" "" success --lost-reviewer challenge --quota-line "$QUOTA"
  [[ "$output" == *"DECISION=findings"* ]]
}

@test "quota: a merged pull request is re-aimed, not quota-skipped" {
  run decide "$REVIEW" "" "" success --lost-reviewer challenge --quota-line "$QUOTA" \
      --merged-at 2026-09-01T10:00:00Z
  [[ "$output" == *"DECISION=reaim"* ]]
}

@test "quota: the quota line is never printed back — it starts life in a job log" {
  run decide "$REVIEW" "" "" success --lost-reviewer challenge --quota-line 'x";touch "$WORK/pwned";#'
  [ "$status" -eq 0 ]
  [[ "$output" != *"pwned"* ]]
  # shellcheck disable=SC1090
  ( set -euo pipefail; . <(decide "$REVIEW" "" "" success --lost-reviewer challenge --quota-line 'x";touch "$WORK/pwned";#') )
  [ ! -e "$WORK/pwned" ]
}
