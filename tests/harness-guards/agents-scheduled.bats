#!/usr/bin/env bats
#
# Scenario "Scheduled agents ship disabled by default" (intent.md). Guards the two
# things that make that true mechanically rather than by promise: every cron entry in
# the workflow matches the SAME schedule string configured for that agent in
# .agents/config.yml (a drift here would silently un-sync the runtime match in
# agents-scheduled.yml's "Decide whether this matrix entry runs" step), and the matrix
# is read from config at runtime rather than hard-coded (a hard-coded list is a second
# source of truth that drifts the moment an agent is added or removed).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/agents-scheduled.yml"
CONFIG="$REPO_ROOT/.agents/config.yml"

@test "agents-scheduled.yml exists and carries workflow_dispatch" {
  [ -f "$WORKFLOW" ]
  grep -q 'workflow_dispatch:' "$WORKFLOW"
}

@test "agents-scheduled.yml's cron entries match .agents/config.yml's ledger.agents schedules, one for one" {
  for id in health quality audit chief-of-staff challenger docs groomer testgap deps release; do
    schedule="$(AGENTS_CONFIG="$CONFIG" bash -c ". '$REPO_ROOT/tools/lib/config.sh'; cfg_agent_field '$id' schedule")"
    grep -qF "cron: \"$schedule\"" "$WORKFLOW" || {
      echo "# no cron entry in agents-scheduled.yml matches $id's configured schedule '$schedule'"
      false
    }
  done
}

@test "agents-scheduled.yml carries exactly ten cron entries, matching the ring size" {
  count="$(grep -cE '^\s*- cron: ' "$WORKFLOW")"
  [ "$count" -eq 10 ]
}

@test "the matrix is read from config at runtime, never hard-coded as a YAML list" {
  grep -q 'cfg_agents' "$WORKFLOW"
  # No literal `agent: [health, quality, ...]` matrix list anywhere in the file.
  run grep -E 'matrix:\s*$' "$WORKFLOW"
  [ "$status" -eq 0 ]
  run grep -E 'agent:\s*\[.*health' "$WORKFLOW"
  [ "$status" -ne 0 ]
}

@test "each matrix entry checks ledger.agents[].enabled before running" {
  # Re-homed: the run steps moved to the reusable agents-scheduled-run.yml so
  # the active/observe caller jobs (whose permissions difference IS fleet-mode
  # enforcement) can share them without a second copy. The lesson travels with
  # the logic; the caller-side assertions below keep the call itself pinned,
  # so the check cannot be lost by orphaning the callee either.
  RUN_WORKFLOW="$REPO_ROOT/.github/workflows/agents-scheduled-run.yml"
  grep -q 'cfg_agent_field "\$AGENT" enabled' "$RUN_WORKFLOW"
  grep -q 'is disabled' "$RUN_WORKFLOW"
  # Both callers delegate to the same callee — exactly two `uses:` of it.
  n="$(grep -c 'uses: ./.github/workflows/agents-scheduled-run.yml' "$WORKFLOW")"
  [ "$n" -eq 2 ]
}

@test "fleet mode: the observe caller is the read-only one and the active caller gates on mode" {
  # The permissions asymmetry between the two caller jobs is the ENFORCEMENT of
  # mode: observe (a reusable workflow's token never exceeds its caller job's
  # permissions). Assert the observe job carries contents: read, the active job
  # carries contents: write, and each is gated on the mode output — so a future
  # tidy-up cannot quietly collapse them into one always-writable job.
  awk '/^  run-agent-observe:/,0' "$WORKFLOW" | grep -q 'contents: read'
  awk '/^  run-agent-observe:/,0' "$WORKFLOW" | grep -q "mode == 'observe'"
  awk '/^  run-agent:/,/^  run-agent-observe:/' "$WORKFLOW" | grep -q 'contents: write'
  awk '/^  run-agent:/,/^  run-agent-observe:/' "$WORKFLOW" | grep -q "mode != 'observe'"
}

@test "every configured agent ships enabled: false (minimal mode, day one)" {
  for id in health quality audit chief-of-staff challenger docs groomer testgap deps release; do
    enabled="$(AGENTS_CONFIG="$CONFIG" bash -c ". '$REPO_ROOT/tools/lib/config.sh'; cfg_agent_field '$id' enabled")"
    [ "$enabled" = "false" ]
  done
}

@test "liveness is re-based for a best-effort scheduler: elapsed time, not calendar day" {
  # Task 19b. .agents/config.yml carries liveness.max-age-hours (a duration, not
  # "today"), and agent-routines.md states the rebasing explicitly — see the scenario
  # "Liveness survives a late scheduler and catches a stopped one".
  run bash -c ". '$REPO_ROOT/tools/lib/config.sh'; AGENTS_CONFIG='$CONFIG' cfg_get liveness.max-age-hours"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
  run bash -c ". '$REPO_ROOT/tools/lib/config.sh'; AGENTS_CONFIG='$CONFIG' cfg_get liveness.staleness-hours"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
  grep -qi 'best-effort' "$REPO_ROOT/docs/runbooks/agent-routines.md"
  grep -qi 'AGE of the newest entry' "$REPO_ROOT/docs/runbooks/agent-routines.md"
}

@test "the ~60-day auto-disable blind spot is named, with an external staleness check" {
  grep -qi '60 days' "$REPO_ROOT/docs/runbooks/agent-routines.md"
  grep -q 'staleness-hours' "$REPO_ROOT/.agents/config.yml"
}
