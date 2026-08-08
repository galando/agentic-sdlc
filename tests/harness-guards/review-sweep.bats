#!/usr/bin/env bats
#
# Gate 22 guard — the cancelled-review sweep.
#
# THE LESSON. The steward handoff is filed at the END of the last review job, deliberately:
# filing it earlier is what once built a handoff on one opinion out of three and dropped
# every finding the second reviewer raised alone. The cost is that a run cancelled part-way
# files nothing — and cancellation is routine here, because the review is advisory rather
# than a required check and `review.yml` sets `cancel-in-progress: true`.
#
# So the reviews sit on the pull request with nobody listening, and the only trace is a
# cancelled run in a list nobody reads.
#
# WHAT THE SWEEP DELIBERATELY DOES NOT DO. It does not file a handoff of its own. It cannot
# know whether the reviews that landed carry findings — the collector that decides that is
# the very thing that was cancelled — so filing speculatively would wake the steward for
# clean pull requests, and an alarm that fires on nothing is an alarm everyone turns off.
# One comment, on the pull requests where a human now owns something.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SWEEP="$REPO_ROOT/.github/workflows/review-sweep.yml"

@test "sweep: the workflow exists and watches the review workflow finish" {
  [ -f "$SWEEP" ]
  run grep -q 'workflows: \[review\]' "$SWEEP"
  [ "$status" -eq 0 ]
  run grep -q 'types: \[completed\]' "$SWEEP"
  [ "$status" -eq 0 ]
}

@test "sweep: it acts ONLY on a cancelled conclusion" {
  # A completed run — success or failure — reached the handoff step, which carries
  # `if: !cancelled()` and owns its own reporting from there. Commenting on those too
  # would double every message the handoff already sends.
  run grep -q "workflow_run.conclusion == 'cancelled'" "$SWEEP"
  [ "$status" -eq 0 ]
}

@test "sweep: it does NOT file an issue or wake the steward" {
  # The whole judgement of this file. It cannot know whether there are findings.
  run grep -q 'gh issue create' "$SWEEP"
  [ "$status" -ne 0 ]
  run grep -q 'steward-handoff' "$SWEEP"
  [ "$status" -ne 0 ]
}

@test "sweep: it does not cancel itself in progress" {
  # This job exists precisely because cancellation loses things. Inheriting
  # cancel-in-progress would make it lose itself.
  run grep -q 'cancel-in-progress: false' "$SWEEP"
  [ "$status" -eq 0 ]
}

@test "sweep: the pull request is resolved from the head sha, not assumed on the payload" {
  # `workflow_run` does not carry a pull-request number for every event shape.
  run grep -q 'commits/\$HEAD_SHA/pulls' "$SWEEP"
  [ "$status" -eq 0 ]
}

@test "sweep: no open pull request is not an error" {
  # It may have merged or closed between the cancellation and this run.
  run grep -q 'nothing to report' "$SWEEP"
  [ "$status" -eq 0 ]
}

@test "sweep: it dedupes on a marker so one pull request gets one notice" {
  # `opened` then `ready_for_review` can produce two cancelled runs for one pull request,
  # and a repeated identical notice teaches the reader to skim past it.
  run grep -q 'review-cancelled-notice' "$SWEEP"
  [ "$status" -eq 0 ]
}

@test "sweep: the notice says what the reader now owns" {
  # "The run was cancelled" is infrastructure trivia. "No handoff was filed, so read the
  # reviews yourself" is the actionable half.
  run grep -q 'no steward handoff' "$SWEEP"
  [ "$status" -eq 0 ]
  run grep -q 'before merging' "$SWEEP"
  [ "$status" -eq 0 ]
}

@test "sweep: it writes no file to a fixed /tmp name" {
  run grep -nE '^[^#]*([^A-Za-z_]> ?/tmp/|--body-file /tmp/)' "$SWEEP"
  [ "$status" -ne 0 ]
  run grep -q 'RUNNER_TEMP' "$SWEEP"
  [ "$status" -eq 0 ]
}

@test "sweep: it holds no more permission than it needs" {
  # It comments; it does not write code, and it must not be able to.
  run grep -q 'contents: read' "$SWEEP"
  [ "$status" -eq 0 ]
  run grep -q 'contents: write' "$SWEEP"
  [ "$status" -ne 0 ]
}
