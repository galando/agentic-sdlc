#!/usr/bin/env bats
#
# Gate 22 guard — the steward handoff is filed AFTER both reviews exist, and reads BOTH.
#
# THE LESSON. The handoff issue used to be the last step of the `review` job. But
# `challenge-review` declares `needs: review`, so nothing the challenge role posts can
# exist at that point — on every pull request, always, not by bad luck. Three things
# followed:
#
#   1. The steward was woken before the second review and the referee comparison existed,
#      and then reported on a pull request it had read once, minutes before the rest of it
#      arrived.
#   2. It built its fix on one opinion out of three.
#   3. Worst, and invisible: the clean check read ONE comment body, which by that ordering
#      could only be the judge-role review. A pull request where the judge role was clean
#      and the challenge role found a bug filed NO HANDOFF AT ALL — the stranded-finding
#      failure the handoff exists to prevent, reintroduced for the second reviewer.
#
# Two consequences are guarded here as well, because each is a way of losing every handoff
# in a repository at once:
#
#   - The `referee` job must not be gated on the challenge role having run. Gated that
#     way, a missing CHALLENGE_API_KEY silently deletes the handoff for every pull request.
#   - The collector must produce the two review bodies even with no `jq` on the runner
#     (`gh` embeds its own). A missing jq must cost the COMPARISON, never the handoff.
#
# Hand-written, like review-collector.bats — this lesson arrived after the pins.json
# extraction capture, so there is no mechanical pin over a source string for it.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"
# The DECISION half moved out of the workflow into a script, so it could be run directly
# rather than carved out of YAML. This file still owns the ORDERING — which job files the
# handoff, and what it is allowed to depend on — and follows the decision to its new home
# for the three assertions that are about the decision itself.
DECIDE="$REPO_ROOT/tools/review-handoff-decide.sh"

# The named job block, first line to the line before the next job at the same indent.
job_block() { # job-name
  awk -v job="  $1:" '
    $0 == job   { injob = 1; print; next }
    injob && /^  [^ ]/ { exit }
    injob       { print }
  ' "$REVIEW"
}

@test "handoff: the job blocks can be located (otherwise every assertion below is vacuous)" {
  [ -n "$(job_block review)" ]
  [ -n "$(job_block referee)" ]
  [ -n "$(job_block challenge-review)" ]
}

@test "handoff: the ordering premise still holds — challenge-review needs review" {
  # This is WHY the handoff cannot live in `review`. If the dependency ever goes away the
  # reasoning below needs revisiting rather than silently rotting.
  run grep -q 'needs: review' <<<"$(job_block challenge-review)"
  [ "$status" -eq 0 ]
}

@test "handoff: the issue is filed from the referee job, not from the review job" {
  run grep -q 'Hand blocking findings to the steward' <<<"$(job_block referee)"
  [ "$status" -eq 0 ]
  run grep -q 'Hand blocking findings to the steward' <<<"$(job_block review)"
  [ "$status" -ne 0 ]
}

@test "handoff: the steward-handoff title is created in exactly one place" {
  run grep -c 'TITLE="\[steward-handoff\] Review findings on PR #\$PR"' "$REVIEW"
  [ "$output" -eq 1 ]
}

@test "handoff: the clean check reads BOTH review bodies, not one comment body" {
  block="$(job_block referee)"
  # Both files are handed to the decision script by the step, and the script reads both.
  run grep -q -- '--judge .review-artifacts/judge.md' <<<"$block"
  [ "$status" -eq 0 ]
  run grep -q -- '--challenge .review-artifacts/challenge.md' <<<"$block"
  [ "$status" -eq 0 ]
  block="$(cat "$DECIDE")"
  # Keyed on the CLEAN phrase, so an unrecognised format escalates rather than being
  # dropped — the same direction-of-error rule as before the move.
  run grep -q "grep -qF 'No issues found'" <<<"$block"
  [ "$status" -eq 0 ]
}

@test "handoff: a review that posted nothing is not counted as a clean review" {
  # The collector writes an empty jq result as a lone newline, so `-s` would call a missing
  # review "present and clean" and suppress the handoff. `wc -c` > 1 is the real test.
  run grep -q 'wc -c < "\$f"' "$DECIDE"
  [ "$status" -eq 0 ]
}

@test "handoff: no review at all defers to the lost-review check instead of duplicating it" {
  run grep -q 'the lost-review check owns this, not the handoff' <<<"$(job_block referee)"
  [ "$status" -eq 0 ]
}

@test "handoff: findings from EITHER reviewer file a handoff" {
  # The bug this whole move fixes: judge clean + challenge finds a bug used to file
  # nothing. The counter must be incremented per review, and the exit-early branch must
  # test the total rather than one review's verdict.
  run grep -q 'WITH_FINDINGS=\$((WITH_FINDINGS + 1))' "$DECIDE"
  [ "$status" -eq 0 ]
  # The exit-early branch must test the TOTAL, never one review's verdict.
  run grep -q 'elif \[ "\$WITH_FINDINGS" = "0" \]; then' "$DECIDE"
  [ "$status" -eq 0 ]
}

@test "handoff: the referee job is NOT gated on the challenge role having run" {
  # An AND gate here deletes every handoff in the repository the moment CHALLENGE_API_KEY
  # is unset — far worse than the bug that moved the handoff into this job.
  gate="$(grep -m1 '^    if: .*cancelled' <<<"$(job_block referee)")"
  [ -n "$gate" ]
  [[ "$gate" != *"&& needs.challenge-review.outputs.ran == 'true' &&"* ]]
  # Either reviewer is enough to enter the job.
  [[ "$gate" == *"||"* ]]
}

@test "handoff: the collector produces both review bodies without a system jq" {
  block="$(job_block referee)"
  run grep -q 'fetch_review_bodies' <<<"$block"
  [ "$status" -eq 0 ]
  # Called from the no-jq branch, before the not-available notice is written.
  run grep -A2 'jq is not installed on this runner' <<<"$block"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fetch_review_bodies"* ]]
}

@test "handoff: the issue body tells the steward nothing further is coming" {
  # The steward used to be woken mid-review and had no way to know. Saying so is what stops
  # it reporting "there is no second review" about a pull request that has one.
  run grep -q 'so nothing is still coming' <<<"$(job_block referee)"
  [ "$status" -eq 0 ]
}

@test "handoff: the elevated-token contract survived the move" {
  block="$(job_block referee)"
  run grep -q 'STEWARD_HANDOFF_PAT' <<<"$block"
  [ "$status" -eq 0 ]
  run grep -q 'NOT invoked by this issue' <<<"$block"
  [ "$status" -eq 0 ]
}

@test "handoff: the dedupe survived the move, exact and client-side" {
  run grep -q 'grep -cFx "\$TITLE"' <<<"$(job_block referee)"
  [ "$status" -eq 0 ]
}

@test "no body file is written to a fixed path under /tmp" {
  # A self-hosted runner's /tmp outlives the job and is shared: mode 1777 lets anyone
  # CREATE a file but not truncate someone else's, so `> /tmp/<fixed-name>` dies with
  # "Permission denied" under set -e — AFTER the review has posted. A red check on a green
  # review, and the handoff never filed. RUNNER_TEMP is per-job, owned and cleared.
  # Comment lines are excluded — the note explaining WHY /tmp is banned quotes it.
  run grep -nE '^[^#]*([^A-Za-z_]> ?/tmp/|--body-file /tmp/)' "$REVIEW"
  if [ "$status" -eq 0 ]; then
    echo "# fixed /tmp paths in review.yml:"
    echo "$output" | sed 's/^/#   /'
    false
  fi
  run grep -c 'RUNNER_TEMP' "$REVIEW"
  [ "$output" -ge 2 ]
}
