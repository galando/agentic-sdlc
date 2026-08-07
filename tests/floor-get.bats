#!/usr/bin/env bats
#
# tools/floor-get.sh — the CLI over config.sh's floor_get that pr-mutation.yml calls.
# It was referenced by the workflow behind an `[ -x ... ]` guard while not existing at
# all, so gate 17's floor read silently never happened — the guard turned a missing
# tool into an unenforced floor. These tests pin its existence and its contract.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FLOOR_GET="$REPO_ROOT/tools/floor-get.sh"

@test "floor-get.sh exists and is executable — the -x guard in pr-mutation.yml must find it" {
  [ -x "$FLOOR_GET" ]
}

@test "prints the unset sentinel for an uncalibrated floor" {
  # A fixture floors file, not the live one: on an adopted tree the live floors
  # are legitimately calibrated numbers.
  cat > "$BATS_TEST_TMPDIR/floors.yml" <<'EOF'
schema: 1
floors:
  backend.mutation.score: { value: unset, direction: up, tool: pit }
EOF
  FLOORS_CONFIG="$BATS_TEST_TMPDIR/floors.yml" run "$FLOOR_GET" backend.mutation.score
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

@test "prints the calibrated value once a floor is armed" {
  cat > "$BATS_TEST_TMPDIR/floors.yml" <<'EOF'
schema: 1
floors:
  backend.mutation.score:
    value: 0.86
    direction: up
    tool: pit
EOF
  FLOORS_CONFIG="$BATS_TEST_TMPDIR/floors.yml" run "$FLOOR_GET" backend.mutation.score
  [ "$status" -eq 0 ]
  [ "$output" = "0.86" ]
}

@test "fails on a key that does not exist in floors.yml" {
  printf 'schema: 1\nfloors:\n' > "$BATS_TEST_TMPDIR/floors.yml"
  FLOORS_CONFIG="$BATS_TEST_TMPDIR/floors.yml" run "$FLOOR_GET" no.such.floor.key
  [ "$status" -ne 0 ]
}

@test "usage error without exactly one argument" {
  run "$FLOOR_GET"
  [ "$status" -eq 2 ]
  run "$FLOOR_GET" a b
  [ "$status" -eq 2 ]
}
