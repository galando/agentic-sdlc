#!/usr/bin/env bats
#
# Gate 22 guard — an outside contribution is SKIPPED and announced, never failed.
#
# THE LESSON. A pull request from a fork receives no repository secrets. That is the
# platform's rule, not a misconfiguration — but it means the reviewer's required credential
# is absent, `run-agent.sh` exits 5 as it correctly does for a missing REQUIRED credential,
# and the job goes red.
#
# So every outside contribution landed with a red check that says nothing about the change.
# Two costs, and the second is the one that lasts: it greets a first-time contributor with a
# failure they did not cause and cannot fix, and it teaches the maintainer that a red review
# check is normal — which is the one signal in this pipeline that has to keep meaning
# something.
#
# The fix is not to hide it. A skipped review is still "nobody reviewed this", so it is
# announced ON THE PULL REQUEST, exactly as the supply-chain carve-out and the
# unconfigured-provider path already are. Silence and green would be worse than red.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"

job_block() {
  awk -v job="  $1:" '
    $0 == job          { injob = 1; print; next }
    injob && /^  [^ ]/ { exit }
    injob              { print }
  ' "$REVIEW"
}

@test "fork: the reviewer job detects a fork before deciding it is enabled" {
  block="$(job_block review)"
  run grep -q 'id: fork-gate' <<<"$block"
  [ "$status" -eq 0 ]
  # It compares the head repository against this one — `head.repo.fork` is absent on some
  # payload shapes, and an absent field would silently read as "not a fork".
  run grep -q 'github.event.pull_request.head.repo.full_name' <<<"$block"
  [ "$status" -eq 0 ]
}

@test "fork: the harness gate short-circuits to disabled on a fork" {
  # Without this the job still tries to authenticate, and the red check comes back.
  block="$(job_block review)"
  run grep -q "steps.fork-gate.outputs.fork" <<<"$block"
  [ "$status" -eq 0 ]
}

@test "fork: the CHALLENGE reviewer skips on a fork too" {
  # Its own credential check would degrade quietly on a missing key, which is the right
  # shape for the wrong reason — and would leave a second job running that cannot work.
  block="$(job_block challenge-review)"
  run grep -q 'HEAD_REPO' <<<"$block"
  [ "$status" -eq 0 ]
  run grep -q 'run=false' <<<"$block"
  [ "$status" -eq 0 ]
}

@test "fork: the skip is announced ON THE PULL REQUEST, not only in the run log" {
  # A workflow-log notice is invisible to whoever merges. If nothing reviewed this change,
  # the place to say so is where the decision gets made.
  block="$(job_block review)"
  run grep -q 'Say on the pull request that no review is coming' <<<"$block"
  [ "$status" -eq 0 ]
  run grep -q 'gh pr comment' <<<"$block"
  [ "$status" -eq 0 ]
}

@test "fork: the notice says nobody reviewed it, and that this is not about the change" {
  # "Skipped" alone reads as "fine". The reader has to learn both halves: no review
  # happened, and that says nothing about the code.
  block="$(job_block review)"
  [[ "$block" == *"neither of them looked at this change"* ]]
  [[ "$block" == *"says nothing about the change itself"* ]]
}

@test "fork: a failure to post the notice does not re-introduce the red check" {
  # A fork token may not permit commenting. Failing here would put back exactly the red
  # check this whole path exists to remove.
  block="$(job_block review)"
  [[ "$block" == *"Could not post the fork notice"* ]]
}

@test "fork: the fork path writes no file to a fixed /tmp name" {
  # Same shared-runner hazard as every other body file in this workflow.
  block="$(job_block review)"
  [[ "$block" == *'${RUNNER_TEMP:-/tmp}/fork-notice.md'* ]]
}
