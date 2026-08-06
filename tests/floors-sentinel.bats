#!/usr/bin/env bats
#
# Scenario "Uncalibrated floors pass loudly, then arm against the adopter's own
# baseline" (intent.md, SC12b). This template instantiation has no reference-stack
# tool config yet (backend/pom.xml, frontend/vitest.config.js — those arrive with the
# example product, tasks.md Task 23/24, PR (c)), so what is testable here is the
# SENTINEL half of the scenario: every floor ships `unset`, the notice sentence is
# exact, and both hard guards (examples/ present, dirty tree) refuse before anything is
# measured. The measure-and-ratchet half needs a real backend/frontend to run against
# and is exercised by Task 31's fresh-instantiation rehearsal instead.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FLOORS="$REPO_ROOT/floors.yml"
LIB="$REPO_ROOT/tools/lib/config.sh"

setup() {
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/tools/lib"
  cp "$FLOORS" "$FIXTURE/floors.yml"
  cp "$LIB" "$FIXTURE/tools/lib/config.sh"
  cp "$REPO_ROOT/tools/measure-floors.sh" "$FIXTURE/tools/measure-floors.sh"
  cp "$REPO_ROOT/tools/render-floors.sh" "$FIXTURE/tools/render-floors.sh"
  cp "$REPO_ROOT/tools/floor-notice.sh" "$FIXTURE/tools/floor-notice.sh"
  chmod +x "$FIXTURE"/tools/*.sh
  ( cd "$FIXTURE" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init )
}

teardown() {
  rm -rf "$FIXTURE"
}

@test "floors.yml exists, schema 1, and every floor ships unset" {
  [ -f "$FLOORS" ]
  run bash -c ". '$LIB'; cfg_assert_schema '$FLOORS' 1"
  [ "$status" -eq 0 ]
  for key in backend.coverage.line backend.coverage.branch backend.mutation.score \
             frontend.coverage.statements frontend.coverage.branches \
             frontend.coverage.functions frontend.coverage.lines \
             frontend.mutation.score frontend.bundle.total_kib; do
    run bash -c ". '$LIB'; floor_get '$key'"
    [ "$status" -eq 0 ]
    [ "$output" = "unset" ]
  done
}

@test "floor_get agrees between yq and the awk fallback for every floor" {
  for key in backend.coverage.line frontend.bundle.total_kib frontend.mutation.score; do
    yq_val="$(AGENTS_CONFIG_READER=yq bash -c ". '$LIB'; floor_get '$key'")"
    awk_val="$(AGENTS_CONFIG_READER=awk bash -c ". '$LIB'; floor_get '$key'")"
    [ "$yq_val" = "$awk_val" ]
  done
}

@test "a floor is never encoded as the literal 0 — unset is not zero" {
  # design.md section 7.1: a zero floor is indistinguishable from a gate someone
  # deliberately disabled. Every floor's `value:` field must read exactly `unset`.
  run grep -cE '^  [a-z0-9_.]+:\s*\{\s*value:\s*0\b' "$FLOORS"
  [ "$status" -ne 0 ] || [ "$output" -eq 0 ]
}

@test "measure-floors.sh refuses while examples/ is present, with no --anyway escape" {
  cd "$FIXTURE"
  mkdir -p examples
  run bash tools/measure-floors.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"examples/ is still present"* ]]
  [[ "$output" == *"There is no --anyway flag"* ]]
  # No case arm actually implements a bypass flag — the prose above legitimately
  # mentions the string "--anyway" to say there is none, so check for a flag-parsing
  # case arm specifically, not the bare substring.
  run grep -qE -- '--anyway\)' tools/measure-floors.sh
  [ "$status" -ne 0 ]
}

@test "measure-floors.sh refuses on a dirty working tree" {
  cd "$FIXTURE"
  echo "dirty" >> floors.yml
  run bash tools/measure-floors.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"working tree is dirty"* ]]
}

@test "measure-floors.sh skips cleanly with no reference-stack tool config present" {
  cd "$FIXTURE"
  run bash tools/measure-floors.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing measured"* ]]
  [[ "$output" == *"SKIP:"* ]]
}

@test "measure-floors.sh is explicitly online and explicitly slow, and says so" {
  run grep -qi 'explicitly online, explicitly slow' "$REPO_ROOT/tools/measure-floors.sh"
  [ "$status" -eq 0 ]
}

@test "the ratchet refusal names the two honest reasons" {
  grep -q 'the measuring instrument changed' "$REPO_ROOT/tools/measure-floors.sh"
  grep -q 'the scope got wider' "$REPO_ROOT/tools/measure-floors.sh"
  grep -q -- '--rebaseline' "$REPO_ROOT/tools/measure-floors.sh"
}

@test "floor-notice.sh prints the exact required sentence for an uncalibrated floor" {
  cd "$FIXTURE"
  run bash tools/floor-notice.sh backend
  [ "$status" -eq 0 ]
  [[ "$output" == *"floor not yet calibrated — run tools/measure-floors.sh against your product"* ]]
}

@test "floor-notice.sh always exits 0" {
  cd "$FIXTURE"
  run bash tools/floor-notice.sh nonexistent-scope
  [ "$status" -eq 0 ]
}

@test "render-floors.sh runs cleanly with no tool config present in the tree" {
  cd "$FIXTURE"
  run bash tools/render-floors.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
}
