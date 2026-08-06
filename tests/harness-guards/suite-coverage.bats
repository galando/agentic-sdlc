#!/usr/bin/env bats
#
# Scenario: "The gauntlet tests the machine that builds it" (intent.md).
#
# WHY THIS FILE EXISTS.
#
# For the whole of this branch's history up to the commit that added it, CI ran
# exactly one bats invocation — `bats tests/harness-guards/`. The 142 tests sitting
# directly under tests/ ran on contributors' laptops and nowhere else: the config
# reader's two-reader agreement, adapter hygiene, the de-identification sweep, init
# idempotency, the ledger round-trip, the run-agent dry run. Load-bearing scripts
# name those files in their own header comments as the thing that makes them
# trustworthy, and none of it was ever executed by a pull request.
#
# It hid because the LOCAL number looked complete. 212 guards plus 142 tests is the
# "354/354" quoted in this branch's commit messages, so every report said the suite
# was whole while CI was running 212 of it. The cost was the ordinary one: a test in
# the unrun half had been failing since the first commit and no pull request said so.
#
# THE RULE: a test file that exists is a test file CI runs. Adding one to tests/ must
# not require anybody to remember to wire it up — which is why these guards check the
# INVOCATIONS rather than a count. A count would need updating on every new test and
# would be "fixed" by whoever it annoyed.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WORKFLOWS="$REPO_ROOT/.github/workflows"

@test "CI runs the harness-guards suite" {
  run grep -rn 'bats tests/harness-guards/' "$WORKFLOWS"
  [ "$status" -eq 0 ]
}

@test "CI runs the tests/ root suite too — not only the guards" {
  # The regression this whole file exists for. `bats tests/` (no -r) is exactly the
  # root suite; the guards are covered by their own invocation above.
  run grep -rnE 'bats (-r )?tests/$' "$WORKFLOWS"
  [ "$status" -eq 0 ]
}

@test "every .bats file in the repository sits under a directory some workflow runs" {
  # Catches a THIRD location — tests/integration/foo.bats, say — added with no
  # invocation, which is the same mistake one level down and just as quiet.
  # Both shipped homes are covered by the two guards above; anything else is new.
  local f rel
  while IFS= read -r f; do
    rel="${f#"$REPO_ROOT"/}"
    case "$rel" in
      tests/*/*) # a subdirectory of tests/
        [[ "$rel" == tests/harness-guards/* ]] || {
          echo "# $rel is in no directory any workflow runs — add an invocation to .github/workflows/pr-tests.yml"
          false
        }
        ;;
      tests/*) : ;;  # the root suite, run by `bats tests/`
      *)
        echo "# $rel sits outside tests/ entirely and no workflow runs it"
        false
        ;;
    esac
  done < <(find "$REPO_ROOT/tests" -name '*.bats' -type f)
}

# The `fast-harness-guards:` job block alone, first line to the line before the next
# job. A function rather than an awk program embedded in a quoted `bash -c` string:
# the quoting was its own bug surface, and every caller wants the same block.
harness_guards_job() {
  awk '
    /^  fast-harness-guards:/ { injob = 1; print; next }
    injob && /^  [^ ]/        { exit }
    injob                     { print }
  ' "$WORKFLOWS/pr-tests.yml"
}

@test "the two invocations live in the same job, so neither can be skipped alone" {
  # They share fast-harness-guards' rationale — a required check that skips reports
  # "passing" — so they must share its no-`needs: changes` exemption as well. Split
  # across two jobs, the new one could acquire a path filter and go quiet on exactly
  # the docs-only pull requests the guards were kept unconditional for.
  #
  # Anchored on `run:` because the surrounding comments quote the commands they
  # explain, and a guard that counts prose is a guard that breaks on a reword.
  local n
  n="$(harness_guards_job | grep -cE '^\s*run: bats tests/')"
  [ "$n" -eq 2 ]
}

@test "fast-harness-guards still carries no needs: changes gate" {
  # Pinned here as well as in spirit: the job now carries strictly more, so the
  # reason it must never be path-filtered got strictly stronger.
  local n
  n="$(harness_guards_job | grep -cE '^\s*needs:' || true)"
  [ "$n" -eq 0 ]
}
