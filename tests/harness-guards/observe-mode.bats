#!/usr/bin/env bats
#
# Fleet mode (config.yml `mode: active | observe`) — the trial week, enforced
# by write PERMISSION, not by prompt text. These guards pin the wiring that
# makes that true in steward.yml; the scheduled-fleet half lives in
# agents-scheduled.bats ("fleet mode: the observe caller is the read-only
# one"), and the prompt half is executed in tests/run-agent-dryrun.bats.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
STEWARD="$REPO_ROOT/.github/workflows/steward.yml"
CONFIG="$REPO_ROOT/.agents/config.yml"

@test "observe: the shipped fleet mode is active" {
  # The quickstart's promise is a first merged loop in 30 minutes; observe is
  # the opt-in trial, one line away. A shipped observe default would break
  # that promise silently for every adopter following the README.
  run bash -c ". '$REPO_ROOT/tools/lib/config.sh'; cfg_get mode"
  [ "$status" -eq 0 ]
  [ "$output" = "active" ]
}

@test "observe: steward's event filter lives on the mode job, and the acting job gates through it" {
  # A workflow `if:` cannot read a file, so the mode is a job output. The
  # acting job must depend on it (needs) and gate on it — that skip is the
  # enforcement: in observe, the only job holding contents write never runs.
  mode_block="$(awk '/^  mode:/,/^  steward:/' "$STEWARD")"
  printf '%s' "$mode_block" | grep -q "sender.type != 'Bot'"
  printf '%s' "$mode_block" | grep -q 'cfg_get mode'
  steward_block="$(awk '/^  steward:/,/^  observe-notice:/' "$STEWARD")"
  printf '%s' "$steward_block" | grep -q 'needs: mode'
  printf '%s' "$steward_block" | grep -q "fleet != 'observe'"
}

@test "observe: the notice job can only comment, and answers only in observe" {
  notice_file="$BATS_TEST_TMPDIR/notice-block"
  awk '/^  observe-notice:/,0' "$STEWARD" > "$notice_file"
  [ -s "$notice_file" ]
  grep -q "fleet == 'observe'" "$notice_file"
  grep -q 'issues: write' "$notice_file"
  # No contents permission of any kind on the notice job — commenting is its
  # entire capability envelope. (run + status, never a bare `! grep`: bash
  # exempts negated pipelines from errexit, so that form cannot fail a test.)
  run grep -E 'contents: (read|write)' "$notice_file"
  [ "$status" -ne 0 ]
  # And it names the exit so the human reading it knows the one-line fix.
  grep -q 'mode: active' "$notice_file"
}

@test "observe: the report-only sheet exists and run-agent.sh appends it from the same config key" {
  [ -f "$REPO_ROOT/.agents/observe.md" ]
  grep -qi 'no branch' "$REPO_ROOT/.agents/observe.md"
  grep -q 'agent-report' "$REPO_ROOT/.agents/observe.md"
  grep -q 'observe.md' "$REPO_ROOT/tools/run-agent.sh"
  grep -q 'cfg_get mode' "$REPO_ROOT/tools/run-agent.sh"
}
