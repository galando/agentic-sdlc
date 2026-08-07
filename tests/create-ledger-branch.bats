#!/usr/bin/env bats
#
# tools/create-ledger-branch.sh — the one-time, idempotent ledger-branch creation.
# The setup step used to be four hand-typed git plumbing commands behind a runbook
# reference; a real adopter reasonably asked why a required branch was manual at
# all. These tests pin the script's contract: creates once, repeats harmlessly,
# never touches the working tree, and fails with guidance rather than a stack of
# git errors when the repository is not ready for it.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  WORK="$(mktemp -d)"
  # A local bare "remote" and a checkout wired to it — no network involved.
  git init -q --bare "$WORK/remote.git"
  git init -q "$WORK/checkout"
  ( cd "$WORK/checkout" \
    && git remote add origin "$WORK/remote.git" \
    && echo hello > file.txt \
    && git add file.txt \
    && git -c user.email=t@t -c user.name=t commit -q -m init \
    && git push -q origin HEAD \
    && git config user.email t@t && git config user.name t )
  mkdir -p "$WORK/checkout/tools/lib"
  cp "$REPO_ROOT/tools/create-ledger-branch.sh" "$WORK/checkout/tools/"
  cp "$REPO_ROOT/tools/lib/config.sh" "$WORK/checkout/tools/lib/"
  chmod +x "$WORK/checkout/tools/create-ledger-branch.sh"
}

teardown() {
  rm -rf "$WORK"
}

@test "creates and pushes the empty agent-ledger branch, and explains what it is" {
  run bash -c 'cd "$0" && bash tools/create-ledger-branch.sh' "$WORK/checkout"
  [ "$status" -eq 0 ]
  [[ "$output" == *"diary"* ]]
  run git -C "$WORK/remote.git" rev-parse --verify refs/heads/agent-ledger
  [ "$status" -eq 0 ]
  # The root commit carries an EMPTY tree — nothing from the working tree leaked in.
  tree="$(git -C "$WORK/remote.git" rev-parse 'refs/heads/agent-ledger^{tree}')"
  [ "$tree" = "4b825dc642cb6eb9a060e54bf8d69288fbee4904" ]
}

@test "running it twice is a no-op that says the branch already exists" {
  ( cd "$WORK/checkout" && bash tools/create-ledger-branch.sh >/dev/null )
  run bash -c 'cd "$0" && bash tools/create-ledger-branch.sh' "$WORK/checkout"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "never switches the checked-out branch or touches the working tree" {
  before_branch="$(git -C "$WORK/checkout" rev-parse --abbrev-ref HEAD)"
  before_status="$(git -C "$WORK/checkout" status --porcelain)"
  ( cd "$WORK/checkout" && bash tools/create-ledger-branch.sh >/dev/null )
  [ "$(git -C "$WORK/checkout" rev-parse --abbrev-ref HEAD)" = "$before_branch" ]
  [ "$(git -C "$WORK/checkout" status --porcelain)" = "$before_status" ]
  [ "$(cat "$WORK/checkout/file.txt")" = "hello" ]
}

@test "respects a configured ledger.branch name" {
  mkdir -p "$WORK/checkout/.agents"
  cat > "$WORK/checkout/.agents/config.yml" <<'CFG'
schema: 1
ledger:
  branch: my-diary
CFG
  ( cd "$WORK/checkout" && bash tools/create-ledger-branch.sh >/dev/null )
  run git -C "$WORK/remote.git" rev-parse --verify refs/heads/my-diary
  [ "$status" -eq 0 ]
}

@test "fails with guidance, not a git stack trace, when origin is missing" {
  ( cd "$WORK/checkout" && git remote remove origin )
  run bash -c 'cd "$0" && bash tools/create-ledger-branch.sh' "$WORK/checkout"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no 'origin' remote"* ]]
  [[ "$output" == *"git remote add origin"* ]]
}
