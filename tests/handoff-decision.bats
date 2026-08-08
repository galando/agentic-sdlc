#!/usr/bin/env bats
#
# tools/review-handoff-decide.sh — the decision, on its own.
#
# This logic was a step body inside review.yml, testable only by carving it out of YAML
# first. It is a script now, so it can simply be run — and this file is what that buys:
# the four decisions, each with the failure it protects against, and no workflow, no
# stubbed API and no extraction anywhere in sight.
#
# `steward-handoff-decision.bats` still exercises the step that CALLS this, because the
# acting half — which issue gets filed, which comment gets posted — is the workflow's.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
TOOL="$REPO_ROOT/tools/review-handoff-decide.sh"

setup() { WORK="$(mktemp -d)"; export WORK; }
teardown() { rm -rf "$WORK"; }

# $1 judge body ("" = file absent), $2 challenge body, $3 collector outcome
decide() {
  [ -n "${1:-}" ] && printf '%s\n' "$1" > "$WORK/judge.md"     || rm -f "$WORK/judge.md"
  [ -n "${2:-}" ] && printf '%s\n' "$2" > "$WORK/challenge.md" || rm -f "$WORK/challenge.md"
  "$TOOL" --judge "$WORK/judge.md" --challenge "$WORK/challenge.md" \
          --collector-outcome "${3:-success}"
}

FINDINGS="ISSUE: src/a.js:10 - a real bug"
CLEAN="No issues found."

@test "decide: findings from either reviewer means findings" {
  run decide "$FINDINGS" "$CLEAN"
  [[ "$output" == *"DECISION=findings"* ]]
  # The case that filed nothing at all before the handoff moved: judge clean, challenge
  # found a bug. A finding is never outvoted by the other reviewer's silence.
  run decide "$CLEAN" "$FINDINGS"
  [[ "$output" == *"DECISION=findings"* ]]
}

@test "decide: every landed review clean means clean" {
  run decide "$CLEAN" "$CLEAN"
  [[ "$output" == *"DECISION=clean"* ]]
  [[ "$output" == *"CLEAN_COUNT=2"* ]]
}

@test "decide: one clean review and one that never landed is still clean" {
  run decide "$CLEAN" ""
  [[ "$output" == *"DECISION=clean"* ]]
  [[ "$output" == *'REVIEWS_PRESENT="the judge role"'* ]]
}

@test "decide: an unrecognised format counts as findings, never as clean" {
  # Keyed on the CLEAN phrase for exactly this reason. Wrong in the direction of one
  # spurious issue, never in the direction of a stranded finding.
  run decide "the reviewer wrote something in a shape nobody expected" ""
  [[ "$output" == *"DECISION=findings"* ]]
}

@test "decide: nothing landed and the collector was fine means none" {
  run decide "" "" success
  [[ "$output" == *"DECISION=none"* ]]
}

@test "decide: nothing landed because the COLLECTOR FAILED is a different decision" {
  # Identical on disk to the case above, opposite meaning: the reviews are on the pull
  # request with real findings, and the lost-review check filed nothing because it saw
  # them. Collapsing these two is how the handoff came to exit quietly and wake nobody.
  run decide "" "" failure
  [[ "$output" == *"DECISION=collector-failed"* ]]
  run decide "" "" cancelled
  [[ "$output" == *"DECISION=collector-failed"* ]]
}

@test "decide: a one-byte review file is 'posted nothing', not 'clean'" {
  # The collector writes an empty result as a lone newline. Counting that as a clean
  # review would suppress the handoff for a pull request nobody actually reviewed.
  printf '\n' > "$WORK/judge.md"
  printf '%s\n' "$FINDINGS" > "$WORK/challenge.md"
  run "$TOOL" --judge "$WORK/judge.md" --challenge "$WORK/challenge.md" --collector-outcome success
  [[ "$output" == *"DECISION=findings"* ]]
  [[ "$output" == *'REVIEWS_PRESENT="the challenge role"'* ]]
}

@test "decide: a missing argument is a loud usage error" {
  run "$TOOL" --judge "$WORK/judge.md" --collector-outcome success
  [ "$status" -eq 2 ]
  [[ "$output" == *"--challenge is required"* ]]
}

@test "decide: the output is safe to source" {
  printf '%s\n' "$FINDINGS" > "$WORK/judge.md"
  printf '%s\n' "$CLEAN" > "$WORK/challenge.md"
  # shellcheck disable=SC1090
  ( set -euo pipefail
    . <("$TOOL" --judge "$WORK/judge.md" --challenge "$WORK/challenge.md" --collector-outcome success)
    [ "$DECISION" = "findings" ]
    [ "$REVIEWS_WITH_FINDINGS" = "1" ]
    [ "$CLEAN_COUNT" = "1" ] )
}
