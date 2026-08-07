#!/usr/bin/env bats
#
# Scenario "An unverified adapter disables the agents, not the gauntlet" (intent.md,
# SC11b). steward.yml and review.yml each read the SAME ADAPTER_STATUS line
# tools/init.sh reads, at run time, and go inert (not red) when it is unverified — see
# the "Check whether the harness is enabled for this provider" step in each file.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
STEWARD="$REPO_ROOT/.github/workflows/steward.yml"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"

@test "steward.yml checks adapter_status before running the agent" {
  grep -q 'harness-gate' "$STEWARD"
  grep -q 'adapter_status "\$provider"' "$STEWARD"
  grep -q "if: steps.harness-gate.outputs.enabled == 'true'" "$STEWARD"
}

@test "steward.yml's visible-outcome check does not fire when the harness is disabled" {
  # Otherwise an unverified provider would make the FIRST issue fail loudly instead of
  # going quietly inert — the exact regression SC11b exists to prevent.
  block="$(awk '/name: Require a visible outcome on auto-triage runs/{f=1} f{print} f && /if:/{exit}' "$STEWARD")"
  [[ "$block" == *"harness-gate.outputs.enabled"* ]]
}

@test "review.yml checks adapter_status before running reviewer A" {
  grep -q 'harness-gate' "$REVIEW"
  grep -q 'adapter_status "\$provider"' "$REVIEW"
  grep -q "if: steps.harness-gate.outputs.enabled == 'true'" "$REVIEW"
}

@test "review.yml's referee is also gated on the harness being enabled" {
  grep -q 'harness_enabled' "$REVIEW"
  grep -q "needs.review.outputs.harness_enabled == 'true'" "$REVIEW"
}

@test "both gates print the docs URL and the re-run-init recovery step when disabled" {
  for f in "$STEWARD" "$REVIEW"; do
    grep -q 'UNVERIFIED STUB' "$f"
    grep -q 're-run tools/init.sh' "$f"
  done
}
