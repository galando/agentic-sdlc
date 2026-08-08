#!/usr/bin/env bats
#
# tools/check-upstream-drift.sh — the maintainer's "did I miss anything?" command.
#
# WHY THIS IS TESTED AT ALL. The tool's whole value is that an EMPTY result means
# something. Every bug it can have produces a short, calm, reassuring list — which is
# indistinguishable from being up to date, and is read exactly the same way. It had one
# such bug before it was ever committed: it defaulted to the local `HEAD`, and `git fetch`
# does not move a local branch, so a clone that had been fetched five minutes earlier
# reported one commit to read while four were waiting.
#
# So the assertions below are about the failure directions, not the happy path:
#   - an unresolvable sync point FAILS rather than reporting nothing
#   - a stale local ref WARNS rather than under-reporting quietly
#   - product-only commits are excluded, and surface commits are not

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
TOOL="$REPO_ROOT/tools/check-upstream-drift.sh"

setup() {
  UP="$(mktemp -d)"
  export UP
  git -C "$UP" init -q -b main
  git -C "$UP" config user.email t@t.invalid
  git -C "$UP" config user.name  T

  mkdir -p "$UP/.github/workflows" "$UP/docs/runbooks" "$UP/src"

  echo one > "$UP/src/app.js"
  git -C "$UP" add -A && git -C "$UP" commit -qm "product: the sync point"
  BASE="$(git -C "$UP" rev-parse HEAD)"
  export BASE

  echo two > "$UP/src/app.js"
  git -C "$UP" add -A && git -C "$UP" commit -qm "product: a change that teaches nothing"

  echo w > "$UP/.github/workflows/review.yml"
  git -C "$UP" add -A && git -C "$UP" commit -qm "fix(review): a carried lesson"

  echo r > "$UP/docs/runbooks/agent-modes.md"
  git -C "$UP" add -A && git -C "$UP" commit -qm "docs(agents): a standing decision"
}

teardown() { rm -rf "$UP"; }

@test "drift: the tool exists and is executable" {
  [ -x "$TOOL" ]
}

@test "drift: surface commits are reported, product-only commits are not" {
  run "$TOOL" "$UP" --since "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 commit(s) to READ"* ]]
  [[ "$output" == *"a carried lesson"* ]]
  [[ "$output" == *"a standing decision"* ]]
  [[ "$output" != *"teaches nothing"* ]]
}

@test "drift: an up-to-date tree says so, and says why product commits were excluded" {
  head="$(git -C "$UP" rev-parse HEAD)"
  run "$TOOL" "$UP" --since "$head"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to carry"* ]]
  [[ "$output" == *"teach this template nothing"* ]]
}

@test "drift: an unresolvable sync point FAILS — never an empty, reassuring list" {
  # The dangerous direction. A typo'd or unfetched sha must not read as "all clear".
  run "$TOOL" "$UP" --since 0000000000000000000000000000000000000000
  [ "$status" -eq 4 ]
  [[ "$output" == *"not a commit"* ]]
  [[ "$output" != *"Nothing to carry"* ]]
}

@test "drift: no sync point at all FAILS with the reason" {
  run env AGENTS_ROOT="$(mktemp -d)" "$TOOL" "$UP"
  [ "$status" -eq 4 ]
  [[ "$output" == *"no sync point"* ]]
}

@test "drift: a path that is not a git checkout FAILS with the clone command" {
  run "$TOOL" "$UP/not-a-repo" --since "$BASE"
  [ "$status" -eq 3 ]
  [[ "$output" == *"git clone"* ]]
}

@test "drift: reading a LOCAL ref warns that it may under-report" {
  # The bug this tool shipped with. `git fetch` updates remote-tracking refs and leaves the
  # local branch alone, so a freshly-fetched clone still has a stale HEAD — and the tool
  # then reports a short list produced by the very staleness it exists to detect.
  # This fixture has no remote, so the fallback path is what runs.
  run "$TOOL" "$UP" --since "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNDER-REPORT"* ]]
  [[ "$output" == *"fetch"* ]]
}

@test "drift: the ref actually read is always named in the output" {
  # "2 commits" means nothing without "…as of which ref, how fresh".
  run "$TOOL" "$UP" --since "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reading HEAD"* ]]
  [[ "$output" == *"newest commit"* ]]
}

@test "drift: the recorded sync point in .agents/upstream-sync.json is a real sha" {
  # A placeholder or an empty string here makes the default invocation fail confusingly.
  sha="$(jq -r '.last_synced_upstream_sha' "$REPO_ROOT/.agents/upstream-sync.json")"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]]
}

@test "drift: every not-carried entry records a sha AND a reason" {
  # "Checked and not carried" is only useful if the reason survives — otherwise the next
  # sync re-reads the same commit and re-derives the same conclusion.
  bad="$(jq -r '.not_carried // [] | .[]
                | select((.sha // "" | length) != 40 or (.why // "" | length) < 40)
                | .sha // "(no sha)"' "$REPO_ROOT/.agents/upstream-sync.json")"
  [ -z "$bad" ]
}
