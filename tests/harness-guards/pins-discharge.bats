#!/usr/bin/env bats
#
# Gate 22 guard — the inventory's own bookkeeping, and the discharge record for the pins
# that cannot be asserted mechanically.
#
# ---------------------------------------------------------------------------
# WHY THIS FILE EXISTS.
#
# `pins.json` has two kinds of entry. `regex` entries are MEANT to be asserted against
# the extracted tree, one bats test per pin, so a lost lesson turns red — but as of this
# writing that coverage is partial, not complete, and this file does not close the gap.
# Of the eight workflows `pins.json` names, this directory today exercises
# `ci-health-watch.yml` in full (`ci-health-watch.bats`) and a handful of `review.yml`'s
# lessons behaviourally (`review-collector.bats`, ~2 of its ~29 regex pins). `steward.yml`,
# `nightly-alert.yml`, `pr-tests.yml`, `pr-mutation.yml`, `pr-validation.yml` and
# `secret-scan.yml` have no bats file at all, and most of `review.yml`'s remaining regex
# pins are unasserted too. That gap is known, scheduled work, not something this file
# should be read as having covered: Task 20 in this spec's `tasks.md` is the pin generator
# that turns every remaining `regex` entry into a real assertion — see it for the rest.
# `semantic-manual` entries CANNOT be asserted, by construction: the string itself had to
# change during genericisation, so there is nothing to pin. They are discharged by a human
# reading the source and the target side by side — which is only possible while the source
# is still reachable, and it is reachable exactly once.
#
# The discharge record was first written to a path under `.temper/evidence/`, which is
# gitignored. That made the shipped tree assert a set of open obligations whose proof did
# not exist anywhere a reader could reach — and one of those obligations was the comment
# collector, where the "discharged" claim turned out to be half true. An unverifiable
# claim of discharge is worth less than an honest `null`, because `null` at least tells
# you where to look.
#
# So: the record is COMMITTED, it names every semantic-manual entry, and `discharged_in`
# in `pins.json` is filled in for the ones that are done. The invariant these assertions
# hold is the one that makes the field readable at all:
#
#     discharged_in: null  means GENUINELY OPEN — never merely unrecorded.
#
# A partially-discharged entry keeps `discharged_in: null` and carries a
# `partial_discharge` string saying what landed and what has not. Half a discharge is an
# open obligation with a head start, and rounding it up to done is how the collector's
# gap survived a review that had already looked at it.
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
PINS="$REPO_ROOT/tests/harness-guards/pins.json"
INV="$REPO_ROOT/tests/harness-guards/lesson-inventory.md"
DISCHARGES="$REPO_ROOT/tests/harness-guards/semantic-discharges.md"

@test "pins: the inventory and the pin list both exist and parse" {
  [ -f "$INV" ]
  jq -e '.pins | length > 0' "$PINS"
}

@test "pins: the discharge record is COMMITTED, not evidence-only" {
  # The whole finding. A record under .temper/evidence/ is unreachable the moment the
  # clone leaves this machine, and the obligations it discharges ship as open.
  [ -f "$DISCHARGES" ]
  run git -C "$REPO_ROOT" ls-files --error-unmatch "tests/harness-guards/semantic-discharges.md"
  [ "$status" -eq 0 ]
}

@test "pins: every semantic-manual entry appears in the discharge record" {
  # Named, whatever its state. An entry that is merely absent from the record is
  # indistinguishable from one nobody looked at.
  missing=""
  while read -r id; do
    grep -qF "\`${id}\`" "$DISCHARGES" || missing="$missing $id"
  done < <(jq -r '.pins[] | select(.pin_kind=="semantic-manual") | .id' "$PINS")
  if [ -n "$missing" ]; then
    echo "# semantic-manual pins with no row in semantic-discharges.md:$missing"
    false
  fi
}

@test "pins: discharged_in is null only for entries that are genuinely open" {
  # An entry with no discharged_in and no stated remainder is unrecorded, not open —
  # and unrecorded is the state this guard exists to make impossible.
  bad="$(jq -r '
    .pins[]
    | select(.pin_kind=="semantic-manual")
    | select(.discharged_in == null)
    | select((.partial_discharge // "") == "")
    | .id' "$PINS")"
  if [ -n "$bad" ]; then
    echo "# semantic-manual pins that are neither discharged nor explained:"
    echo "$bad" | sed 's/^/#   /'
    false
  fi
}

@test "pins: a discharged entry names a real file in this tree" {
  # A discharge pointing at a path that does not exist is a claim, not a record.
  while read -r line; do
    [ -z "$line" ] && continue
    id="${line%%|*}"
    where="${line#*|}"
    # The first path-shaped token in the prose is the file the discharge points at.
    path="$(printf '%s' "$where" | grep -oE '(\.github|docs|tools|tests|\.agents)/[A-Za-z0-9._/-]+' | head -n1)"
    [ -n "$path" ] || { echo "# $id: discharged_in names no path"; false; }
    [ -e "$REPO_ROOT/$path" ] || { echo "# $id: discharged_in points at a missing path: $path"; false; }
  done < <(jq -r '.pins[] | select(.pin_kind=="semantic-manual") | select(.discharged_in != null) | "\(.id)|\(.discharged_in)"' "$PINS")
}

@test "pins: the inventory's stated counts match the pin list it describes" {
  # The bookkeeping drift this guard was added for. The inventory is the file a HUMAN
  # reads; pins.json is the file a machine reads. A reconciliation done against a stale
  # count silently drops whichever entries the count omits — and the omitted ten were
  # the weakest, most-recently-added ones, which is the worst possible selection.
  total="$(jq '.pins | length' "$PINS")"
  regex="$(jq '[.pins[] | select(.pin_kind=="regex")] | length' "$PINS")"
  literal="$(jq '[.pins[] | select(.pin_kind=="literal")] | length' "$PINS")"
  semantic="$(jq '[.pins[] | select(.pin_kind=="semantic-manual")] | length' "$PINS")"

  header="$(sed -n '3p' "$INV")"
  [[ "$header" == *"${total} entries"* ]]
  [[ "$header" == *"${regex}"*"regex"* ]]
  [[ "$header" == *"${literal}"*"literal"* ]]
  [[ "$header" == *"${semantic}"*"semantic-manual"* ]]
}

@test "pins: every source file in the pin list has a section in the inventory" {
  # A whole file's worth of entries can go missing from the inventory while the totals
  # elsewhere still look self-consistent. That is exactly what happened.
  missing=""
  while read -r src; do
    grep -qF "$src" "$INV" || missing="$missing $src"
  done < <(jq -r '.pins[] | .source_file' "$PINS" | sort -u)
  if [ -n "$missing" ]; then
    echo "# source files with entries in pins.json but no section in the inventory:$missing"
    false
  fi
}

@test "pins: the inventory repeats the provenance rule WITH its exception" {
  # pins.json's note already discloses that one file's entries were captured after its
  # generic counterpart existed, so their patterns were fitted to text that was already
  # there. The inventory is the file a human reads and it stated the before-substitution
  # rule with no exception — which reads as a stronger guarantee than the evidence
  # supports, on precisely the ten weakest entries.
  grep -qi 'after' "$INV"
  grep -q 'AFTER ITS GENERIC COUNTERPART EXISTED' "$INV"
}
