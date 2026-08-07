#!/usr/bin/env bats
#
# The count assertion the intent scenario literally demands ("A lost extraction lesson
# fails the build"): the number of `literal`/`regex` entries in pins.json must equal the
# number of @test assertions in the generated suite. A suite smaller than the inventory
# is a silently dropped lesson, and this is the belt to pins.generated.bats's braces —
# it does not re-check the strings themselves, only that nothing was left out.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
PINS="$REPO_ROOT/tests/harness-guards/pins.json"
GENERATED="$REPO_ROOT/tests/harness-guards/pins.generated.bats"
GEN_SCRIPT="$REPO_ROOT/tests/harness-guards/gen-pin-tests.sh"

@test "pins.generated.bats exists and is committed" {
  [ -f "$GENERATED" ]
  run git -C "$REPO_ROOT" ls-files --error-unmatch "tests/harness-guards/pins.generated.bats"
  [ "$status" -eq 0 ]
}

@test "assertion count equals the literal/regex entry count" {
  expected="$(jq '[.pins[] | select(.pin_kind=="literal" or .pin_kind=="regex")] | length' "$PINS")"
  actual="$(grep -c '^@test "pin\[' "$GENERATED")"
  [ "$expected" -eq "$actual" ]
}

@test "every semantic-manual entry is named as hand-discharged in the generated output" {
  expected="$(jq '[.pins[] | select(.pin_kind=="semantic-manual")] | length' "$PINS")"
  actual="$(grep -c '^# SEMANTIC-MANUAL' "$GENERATED")"
  [ "$expected" -eq "$actual" ]
}

@test "no semantic-manual entry is silently undischarged (discharged_in is null only when genuinely open)" {
  # This mirrors pins-discharge.bats's own check; restated here because it is exactly
  # what makes the hand-discharged roll call above trustworthy — a null discharged_in
  # that IS genuinely open is fine and expected to show up as "OPEN — not yet
  # discharged" in the generated output, never silently as if it were done.
  jq -r '.pins[] | select(.pin_kind=="semantic-manual" and .discharged_in==null) | .id' "$PINS" \
    > "$BATS_TEST_TMPDIR/open.txt"
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    grep -qF "OPEN — not yet discharged" "$GENERATED" || {
      echo "# $id has discharged_in: null but the generator did not mark it OPEN"
      false
    }
  done < "$BATS_TEST_TMPDIR/open.txt"
}

@test "every expected_in file exists (a pin pointing at a deleted file FAILS, not vanishes)" {
  missing=""
  while IFS= read -r f; do
    [ -e "$REPO_ROOT/$f" ] || missing="$missing $f"
  done < <(jq -r '.pins[] | .expected_in' "$PINS" | sort -u)
  if [ -n "$missing" ]; then
    echo "# expected_in files that do not exist in this tree:$missing"
    false
  fi
}

@test "regenerating pins.generated.bats from pins.json produces no diff (CI's fast-repo-hygiene check)" {
  [ -x "$GEN_SCRIPT" ]
  cp "$GENERATED" "$BATS_TEST_TMPDIR/before.bats"
  "$GEN_SCRIPT" >/dev/null
  run diff -u "$BATS_TEST_TMPDIR/before.bats" "$GENERATED"
  if [ "$status" -ne 0 ]; then
    echo "# pins.generated.bats is stale — regenerate with tests/harness-guards/gen-pin-tests.sh and commit it"
    echo "$output"
    false
  fi
}
