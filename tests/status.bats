#!/usr/bin/env bats
#
# tools/status.sh — the "where am I, what's next" map. Born from a real adopter,
# three guard refusals deep, saying "too many scripts, it's difficult to follow":
# every guard knew its own step was out of order, and nothing showed the order.
# These tests pin that the map reads each state correctly and always names
# exactly one next command.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

make_fixture() { # $1 = state: fresh | initialised | done
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/tools/lib"
  cp "$REPO_ROOT/tools/status.sh" "$FIXTURE/tools/"
  cp "$REPO_ROOT/tools/lib/config.sh" "$FIXTURE/tools/lib/"
  chmod +x "$FIXTURE/tools/status.sh"
  mkdir -p "$FIXTURE/.agents"

  case "$1" in
    fresh)
      printf 'schema: 1\nprovider: "{{PROVIDER}}"\n' > "$FIXTURE/.agents/config.yml"
      mkdir -p "$FIXTURE/examples/backend"
      printf 'schema: 1\nfloors:\n  a.b: { value: unset, direction: up, tool: t }\n' > "$FIXTURE/floors.yml"
      ;;
    initialised)
      printf 'schema: 1\nprovider: "someprovider"\n' > "$FIXTURE/.agents/config.yml"
      mkdir -p "$FIXTURE/examples/backend"
      printf 'schema: 1\nfloors:\n  a.b: { value: unset, direction: up, tool: t }\n' > "$FIXTURE/floors.yml"
      ;;
    done)
      printf 'schema: 1\nprovider: "someprovider"\nledger:\n  branch: agent-ledger\n' > "$FIXTURE/.agents/config.yml"
      mkdir -p "$FIXTURE/backend"
      printf 'schema: 1\nfloors:\n  a.b:\n    value: 0.9\n    direction: up\n    tool: t\n' > "$FIXTURE/floors.yml"
      ;;
  esac

  ( cd "$FIXTURE" && git init -q \
    && git config user.email t@t && git config user.name t \
    && git add -A && git commit -q -m init )

  if [ "$1" = "done" ]; then
    git init -q --bare "$FIXTURE-remote.git"
    ( cd "$FIXTURE" && git remote add origin "$FIXTURE-remote.git" && git push -q origin HEAD )
    EMPTY="$(git -C "$FIXTURE" hash-object -t tree /dev/null)"
    C="$(git -C "$FIXTURE" commit-tree "$EMPTY" -m root)"
    git -C "$FIXTURE" push -q origin "$C:refs/heads/agent-ledger"
  fi
}

teardown() {
  [ -n "${FIXTURE:-}" ] && rm -rf "$FIXTURE" "$FIXTURE-remote.git"
  return 0
}

@test "fresh template: the next command is the interview, and the run exits 0" {
  make_fixture fresh
  run bash "$FIXTURE/tools/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Next command:  tools/init.sh"* ]]
}

@test "initialised but example still present: the next command is adopt-layout" {
  make_fixture initialised
  run bash "$FIXTURE/tools/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[done] 1."* ]]
  [[ "$output" == *"Next command:  tools/adopt-layout.sh"* ]]
}

@test "everything done: all four steps read [done] and the GitHub-side list prints" {
  make_fixture done
  run bash "$FIXTURE/tools/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[NEXT]"* ]]
  [[ "$output" == *"All four tool steps are done"* ]]
  [[ "$output" == *"branch protection"* ]]
}

@test "a dirty tree gets the review-commit-continue note" {
  make_fixture initialised
  echo dirty > "$FIXTURE/uncommitted.txt"
  run bash "$FIXTURE/tools/status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uncommitted changes"* ]]
  [[ "$output" == *"ON PURPOSE"* ]]
}

@test "the live template tree itself reads as step 1 next" {
  run bash "$REPO_ROOT/tools/status.sh"
  [ "$status" -eq 0 ]
  # Template repo: interview unanswered. An adopted tree legitimately differs,
  # so only assert when the tree is actually uninitialised.
  if grep -qF '{{PROVIDER}}' "$REPO_ROOT/.agents/config.yml"; then
    [[ "$output" == *"Next command:  tools/init.sh"* ]]
  fi
}
