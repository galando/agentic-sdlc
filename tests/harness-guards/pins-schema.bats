#!/usr/bin/env bats
#
# Validates pins.json's own record schema — design.md section 5.1. This is separate
# from pins-discharge.bats (which validates the semantic-manual discharge bookkeeping)
# and from pins.generated.bats (which asserts the pinned strings themselves): this file
# only asks "is the inventory well-formed", so a malformed entry fails here with a
# specific reason instead of surfacing as a confusing failure somewhere downstream.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
PINS="$REPO_ROOT/tests/harness-guards/pins.json"

@test "pins.json exists and parses" {
  [ -f "$PINS" ]
  jq -e . "$PINS" >/dev/null
}

@test "pins.json declares schema: 1" {
  [ "$(jq -r '.schema' "$PINS")" = "1" ]
}

@test "pins.json has at least 25 entries (tasks.md Task 6b's floor)" {
  n="$(jq '.pins | length' "$PINS")"
  [ "$n" -ge 25 ]
}

@test "every pin id is unique" {
  total="$(jq '.pins | length' "$PINS")"
  distinct="$(jq '[.pins[].id] | unique | length' "$PINS")"
  [ "$total" -eq "$distinct" ]
}

@test "every entry has the required fields, non-empty" {
  bad="$(jq -r '
    .pins[]
    | select(
        (.id // "" | length) == 0 or
        (.source_file // "" | length) == 0 or
        (.source_line // 0) <= 0 or
        (.quoted_source_string // "" | length) == 0 or
        (.why // "" | length) == 0 or
        (.expected_in // "" | length) == 0 or
        ((.pin_kind // "") as $k | ($k != "literal" and $k != "regex" and $k != "semantic-manual"))
      )
    | .id' "$PINS")"
  if [ -n "$bad" ]; then
    echo "# entries with a missing/invalid required field:"
    echo "$bad" | sed 's/^/#   /'
    false
  fi
}

@test "every 'why' is at least 40 characters (a rule without its reason gets deleted)" {
  bad="$(jq -r '.pins[] | select((.why // "" | length) < 40) | .id' "$PINS")"
  if [ -n "$bad" ]; then
    echo "# entries whose 'why' is under 40 characters:$bad"
    false
  fi
}

@test "every regex entry carries a pattern field" {
  bad="$(jq -r '.pins[] | select(.pin_kind == "regex") | select((.pattern // "" | length) == 0) | .id' "$PINS")"
  if [ -n "$bad" ]; then
    echo "# regex entries with no pattern:$bad"
    false
  fi
}

@test "every regex entry's pattern is valid POSIX ERE (grep -E accepts it)" {
  bad=""
  # One JSON object per line (`jq -c`), each field pulled out with its own `jq -r`
  # call — NOT `@tsv`, which doubles backslashes for TSV-escaping and would turn a
  # perfectly valid pattern like `paginate\(github\.rest` into an invalid one
  # (`paginate\\(github\\.rest`, an unbalanced group) purely as an artifact of this
  # check's own encoding. That cost an hour the first time this test was written.
  while IFS= read -r entry; do
    id="$(jq -r '.id' <<<"$entry")"
    pattern="$(jq -r '.pattern' <<<"$entry")"
    # rc 0 = matched (impossible on empty input for most patterns) or 1 = no match are
    # both fine; 2 means grep itself rejected the pattern as invalid. The `if` context
    # keeps this out of bats' errexit — a bare rc-1 pipeline would otherwise abort the
    # test on the first "no match", which is the expected, non-error case here.
    if printf '' | grep -E -q -- "$pattern" 2>/dev/null; then
      rc=0
    else
      rc=$?
    fi
    [ "$rc" -eq 2 ] && bad="$bad $id"
  done < <(jq -c '.pins[] | select(.pin_kind=="regex")' "$PINS")
  if [ -n "$bad" ]; then
    echo "# regex entries whose pattern is not valid ERE:$bad"
    false
  fi
}

@test "every semantic-manual entry carries concept, replacement_must_preserve and the discharged_in key" {
  bad="$(jq -r '
    .pins[]
    | select(.pin_kind == "semantic-manual")
    | select(
        (.concept // "" | length) == 0 or
        (.replacement_must_preserve // "" | length) == 0 or
        (has("discharged_in") | not)
      )
    | .id' "$PINS")"
  if [ -n "$bad" ]; then
    echo "# semantic-manual entries missing concept/replacement_must_preserve/discharged_in:$bad"
    false
  fi
}

@test "pin_kind counts: schema field totals match reality" {
  total="$(jq '.pins | length' "$PINS")"
  literal="$(jq '[.pins[] | select(.pin_kind=="literal")] | length' "$PINS")"
  regex="$(jq '[.pins[] | select(.pin_kind=="regex")] | length' "$PINS")"
  semantic="$(jq '[.pins[] | select(.pin_kind=="semantic-manual")] | length' "$PINS")"
  [ "$((literal + regex + semantic))" -eq "$total" ]
}
