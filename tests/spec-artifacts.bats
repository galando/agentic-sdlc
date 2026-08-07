#!/usr/bin/env bats
#
# Gate 21. Scenarios "Gate 21 fails a fix PR with no spec artifacts" and "Gate 21
# accepts a declared-unavailable pipeline" (intent.md). tools/spec-pipeline/validate.sh
# is the ONE implementation the CI workflow and a local pre-flight both call — see
# tools/spec-pipeline/CONTRACT.md.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
VALIDATE="$REPO_ROOT/tools/spec-pipeline/validate.sh"
NEW_SPEC="$REPO_ROOT/tools/spec-pipeline/new-spec.sh"
RECORD_GATE="$REPO_ROOT/tools/spec-pipeline/record-gate.sh"

setup() {
  SCRATCH="$(mktemp -d)"
  BODY_FILE="$SCRATCH/body.md"
  CHANGED_FILE="$SCRATCH/changed.txt"
}

teardown() {
  rm -rf "$SCRATCH"
  # new-spec.sh writes into the REAL repo tree (.temper/specs/), since gates.json has to
  # exist on disk for validate.sh to read — clean it back out after each test.
  if [ -n "${TEST_SLUG:-}" ]; then
    rm -rf "$REPO_ROOT/.temper/specs/$TEST_SLUG"
  fi
}

@test "spec-pipeline scripts exist and are executable" {
  [ -x "$VALIDATE" ]
  [ -x "$NEW_SPEC" ]
  [ -x "$RECORD_GATE" ]
}

@test "gate 21 does not apply with no matching label" {
  echo "just a normal PR body" > "$BODY_FILE"
  echo "docs/README.md" > "$CHANGED_FILE"
  run "$VALIDATE" --pr-body-file "$BODY_FILE" --changed-files "$CHANGED_FILE" --labels docs
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "Gate 21 fails a fix PR with no spec artifacts" {
  echo "just a normal PR body, nothing special" > "$BODY_FILE"
  echo "src/app.py" > "$CHANGED_FILE"
  run "$VALIDATE" --pr-body-file "$BODY_FILE" --changed-files "$CHANGED_FILE" --labels fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"Commit the spec directory"* ]]
  [[ "$output" == *"temper: unavailable"* ]]
}

@test "Gate 21 fails a fix PR with a PARTIAL spec directory (missing gates.json)" {
  TEST_SLUG="test-partial-spec"
  "$NEW_SPEC" "$TEST_SLUG" >/dev/null
  echo "normal body" > "$BODY_FILE"
  printf '.temper/specs/%s/intent.md\n.temper/specs/%s/plan.md\n.temper/specs/%s/tasks.md\n' \
    "$TEST_SLUG" "$TEST_SLUG" "$TEST_SLUG" > "$CHANGED_FILE"
  run "$VALIDATE" --pr-body-file "$BODY_FILE" --changed-files "$CHANGED_FILE" --labels fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"gates.json"* ]]
}

@test "Gate 21 fails when the spec directory exists but is not in THIS diff" {
  # A spec directory already on the default branch proves nothing about this change —
  # validate.sh checks the diff, not the tree.
  TEST_SLUG="test-not-in-diff"
  "$NEW_SPEC" "$TEST_SLUG" >/dev/null
  "$RECORD_GATE" "$TEST_SLUG" plan PASS "artifacts exist=true:present" >/dev/null
  echo "normal body" > "$BODY_FILE"
  echo "src/unrelated.py" > "$CHANGED_FILE"
  run "$VALIDATE" --pr-body-file "$BODY_FILE" --changed-files "$CHANGED_FILE" --labels fix
  [ "$status" -eq 1 ]
}

@test "Gate 21 accepts a complete spec directory with a passing stage" {
  TEST_SLUG="test-complete-spec"
  "$NEW_SPEC" "$TEST_SLUG" >/dev/null
  "$RECORD_GATE" "$TEST_SLUG" plan PASS "artifacts exist=true:present" >/dev/null
  "$RECORD_GATE" "$TEST_SLUG" build PASS_WITH_WARNINGS "RED then GREEN=true:1 red 1 green" >/dev/null
  echo "normal body" > "$BODY_FILE"
  printf '.temper/specs/%s/intent.md\n.temper/specs/%s/plan.md\n.temper/specs/%s/tasks.md\n.temper/specs/%s/gates.json\n' \
    "$TEST_SLUG" "$TEST_SLUG" "$TEST_SLUG" "$TEST_SLUG" > "$CHANGED_FILE"
  run "$VALIDATE" --pr-body-file "$BODY_FILE" --changed-files "$CHANGED_FILE" --labels fix
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "Gate 21 fails when gates.json has no PASS or PASS_WITH_WARNINGS stage" {
  TEST_SLUG="test-all-fail-stage"
  "$NEW_SPEC" "$TEST_SLUG" >/dev/null
  "$RECORD_GATE" "$TEST_SLUG" build FAIL "RED then GREEN=false:tests never went green" >/dev/null
  echo "normal body" > "$BODY_FILE"
  printf '.temper/specs/%s/intent.md\n.temper/specs/%s/plan.md\n.temper/specs/%s/tasks.md\n.temper/specs/%s/gates.json\n' \
    "$TEST_SLUG" "$TEST_SLUG" "$TEST_SLUG" "$TEST_SLUG" > "$CHANGED_FILE"
  run "$VALIDATE" --pr-body-file "$BODY_FILE" --changed-files "$CHANGED_FILE" --labels fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"no stage with verdict PASS"* ]]
}

@test "Gate 21 accepts a declared-unavailable pipeline" {
  echo "temper: unavailable — plugin marketplace unreachable from the runner" > "$BODY_FILE"
  echo "src/app.py" > "$CHANGED_FILE"
  run "$VALIDATE" --pr-body-file "$BODY_FILE" --changed-files "$CHANGED_FILE" --labels fix
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning title=Spec pipeline declared unavailable::plugin marketplace unreachable from the runner"* ]]
  [[ "$output" == *"PASS"* ]]
}

@test "Gate 21 rejects a declared-unavailable line with a non-reason" {
  echo "temper: unavailable — n/a" > "$BODY_FILE"
  echo "src/app.py" > "$CHANGED_FILE"
  run "$VALIDATE" --pr-body-file "$BODY_FILE" --changed-files "$CHANGED_FILE" --labels fix
  [ "$status" -eq 1 ]
}

@test "Gate 21 rejects a declared-unavailable line that is too short" {
  echo "temper: unavailable — broken" > "$BODY_FILE"
  echo "src/app.py" > "$CHANGED_FILE"
  run "$VALIDATE" --pr-body-file "$BODY_FILE" --changed-files "$CHANGED_FILE" --labels fix
  [ "$status" -eq 1 ]
}

@test "new-spec.sh refuses a slug that already exists" {
  TEST_SLUG="test-dup-slug"
  "$NEW_SPEC" "$TEST_SLUG" >/dev/null
  run "$NEW_SPEC" "$TEST_SLUG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "new-spec.sh refuses a non-kebab-case slug" {
  run "$NEW_SPEC" "Not_Kebab Case"
  [ "$status" -ne 0 ]
}

@test "record-gate.sh preserves an earlier stage when recording a later one" {
  TEST_SLUG="test-preserve-stage"
  "$NEW_SPEC" "$TEST_SLUG" >/dev/null
  "$RECORD_GATE" "$TEST_SLUG" plan PASS "x=true:first" >/dev/null
  "$RECORD_GATE" "$TEST_SLUG" build PASS "y=true:second" >/dev/null
  plan_verdict="$(jq -r '.stages.plan.verdict' "$REPO_ROOT/.temper/specs/$TEST_SLUG/gates.json")"
  build_verdict="$(jq -r '.stages.build.verdict' "$REPO_ROOT/.temper/specs/$TEST_SLUG/gates.json")"
  [ "$plan_verdict" = "PASS" ]
  [ "$build_verdict" = "PASS" ]
}
