#!/usr/bin/env bash
# tests/harness-guards/gen-pin-tests.sh — pins.json -> tests/harness-guards/pins.generated.bats
#
# Deterministic generator, one @test per literal/regex entry in pins.json, each carrying
# its `why` verbatim as a comment. This is what makes gate 22 EXECUTE the inventory
# instead of re-authoring it: the inventory (pins.json, Task 6b) was written by reading
# the source workflows before substitution began, so a lesson lost during extraction
# shows up as a missing string here, not as a suite that was simply never told to check
# for it. See design.md section 5.2 (Decision D10) and tools/spec-pipeline is unrelated
# — this is the gate-22 harness, not the spec pipeline.
#
# The output is COMMITTED and reviewable in a diff. CI's fast-repo-hygiene job re-runs
# this script and diffs the result — a hand edit, or a pin added without regenerating,
# fails the build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS="$SCRIPT_DIR/pins.json"
OUT="$SCRIPT_DIR/pins.generated.bats"

command -v jq >/dev/null 2>&1 || { echo "gen-pin-tests.sh: jq is required" >&2; exit 1; }
[ -f "$PINS" ] || { echo "gen-pin-tests.sh: $PINS not found" >&2; exit 1; }

# Escape a value for interpolation into a DOUBLE-QUOTED bash string in the generated
# file. Backslash, dollar, backtick and double-quote all have meaning there. Until
# supersession landed, every `why` in the inventory happened to contain none of them and
# this was silently fine — the first entry carrying a quoted phrase produced a generated
# file whose `echo` arguments re-tokenised into something subtly different from the text
# in pins.json, and a `$(...)` in a future entry would have gone further than that.
esc() { printf '%s' "$1" | sed -e 's/[\\`$"]/\\&/g'; }

emit_literal_and_regex() {
  jq -c '.pins[] | select(.pin_kind=="literal" or .pin_kind=="regex")' "$PINS" |
  while IFS= read -r entry; do
    id="$(jq -r '.id' <<<"$entry")"
    kind="$(jq -r '.pin_kind' <<<"$entry")"
    expected_in="$(jq -r '.expected_in' <<<"$entry")"
    source_file="$(jq -r '.source_file' <<<"$entry")"
    source_line="$(jq -r '.source_line' <<<"$entry")"
    why="$(jq -r '.why' <<<"$entry")"
    # Supersession (schema 2). An entry whose CONCLUSION was later reversed keeps its
    # pattern and its original `why` — the string usually survives in a new role, and the
    # old reasoning is the cost the reversal chose to pay. But a reader who trips this
    # assertion must not be told to restore a rule the system has since argued its way out
    # of, so the reversal travels with the failure message.
    superseded_on="$(jq -r '.superseded_on // ""' <<<"$entry")"
    superseded_by="$(jq -r '.superseded_by // ""' <<<"$entry")"
    superseded_reason="$(jq -r '.superseded_reason // ""' <<<"$entry")"

    printf '%s\n' "$why" | fold -s -w 90 | sed 's/^/# WHY: /'
    if [ -n "$superseded_on" ]; then
      printf '%s\n' "SUPERSEDED $superseded_on -> $superseded_by" | fold -s -w 90 | sed 's/^/# /'
      printf '%s\n' "$superseded_reason" | fold -s -w 90 | sed 's/^/# SUPERSEDED: /'
    fi

    if [ "$kind" = "literal" ]; then
      needle="$(jq -r '.quoted_source_string' <<<"$entry")"
      grep_cmd="grep -F -q -- $(printf '%q' "$needle")"
    else
      pattern="$(jq -r '.pattern' <<<"$entry")"
      grep_cmd="grep -E -q -- $(printf '%q' "$pattern")"
    fi

    if [ -n "$superseded_on" ]; then
      supersession_lines="$(cat <<EOF
    echo "  NOTE:   this lesson was SUPERSEDED on $superseded_on."
    echo "          now: $(esc "$superseded_by")"
    echo "          why: $(esc "$superseded_reason")"
    echo "          The pin still holds: the string survives in its new role. Restore it"
    echo "          as that, NOT as the original rule."
EOF
)"
    else
      supersession_lines='    echo "  Restore the string in '"$expected_in"'. Do NOT weaken the pin."'
    fi

    cat <<EOF
@test "pin[$id]: $expected_in" {
  run $grep_cmd "\$REPO_ROOT/$expected_in"
  if [ "\$status" -ne 0 ]; then
    echo "PIN LOST: $id"
    echo "  source: $source_file:$source_line"
    echo "  why:    $(esc "$why")"
$supersession_lines
    false
  fi
}

EOF
  done
}

emit_semantic_manual() {
  jq -c '.pins[] | select(.pin_kind=="semantic-manual")' "$PINS" |
  while IFS= read -r entry; do
    id="$(jq -r '.id' <<<"$entry")"
    concept="$(jq -r '.concept' <<<"$entry")"
    discharged="$(jq -r '.discharged_in // "OPEN — not yet discharged"' <<<"$entry")"
    echo "# SEMANTIC-MANUAL (hand-discharged, not asserted): $id"
    echo "#   concept: $concept"
    echo "#   discharged: $discharged"
    # A superseded entry has to SAY SO here. Without this the generated inventory reads a
    # replaced lesson back as current guidance, which is how the reason for a safeguard
    # outlives the safeguard and then gets deleted as redundant. The literal/regex emitter
    # has always printed this; semantic-manual did not, because until 2026-08-09 no
    # semantic-manual entry had ever been superseded.
    superseded_on="$(jq -r '.superseded_on // ""' <<<"$entry")"
    if [ -n "$superseded_on" ]; then
      echo "#   SUPERSEDED $superseded_on -> $(jq -r '.superseded_by // ""' <<<"$entry")"
      echo "#   SUPERSEDED why: $(jq -r '.superseded_reason // ""' <<<"$entry")"
    fi
  done
}

{
  cat <<'HEADER'
#!/usr/bin/env bats
#
# GENERATED FILE — DO NOT HAND-EDIT.
#
# Produced by tests/harness-guards/gen-pin-tests.sh from pins.json. Regenerate with:
#   tests/harness-guards/gen-pin-tests.sh
# then `git diff --exit-code tests/harness-guards/pins.generated.bats` — CI's
# fast-repo-hygiene job runs exactly that, so a hand edit here, or a pin added without
# regenerating, fails the build.
#
# Committed and reviewable in a diff on purpose (design.md Decision D10): a runtime
# loop over pins.json would hide the WHY text from the diff, which is where the lesson
# has to be readable. One @test per literal/regex pin, each carrying its `why` verbatim
# as a comment — the incident is the reason the assertion exists, and a rule without
# its reason gets deleted by the next person. semantic-manual entries get no assertion
# here (the string itself had to change during genericisation, so there is nothing to
# pin); they are named below as hand-discharged instead of silently omitted.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
HEADER
  echo
  emit_literal_and_regex
  echo "# --- semantic-manual entries: hand-discharged, not asserted by this file ---"
  emit_semantic_manual
} > "$OUT"

echo "wrote $OUT"
