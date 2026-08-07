#!/usr/bin/env bats
#
# tools/adopt.sh — the guided adoption driver. What these tests pin is its SAFETY
# CONTRACT, not the individual steps (each step's tool has its own suite):
# nothing happens without an explicit yes, done-states are detected rather than
# redone, and a missing gh degrades to instructions — never to a false "done"
# and never to a hang. All runs here are non-interactive, so every offer reads
# its ADOPT_*/init-style env var, defaulting to No.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/tools/lib" "$FIXTURE/.agents" "$FIXTURE/examples/backend"
  cp "$REPO_ROOT/tools/adopt.sh" "$FIXTURE/tools/"
  cp "$REPO_ROOT/tools/adopt-layout.sh" "$FIXTURE/tools/"
  cp "$REPO_ROOT/tools/lib/config.sh" "$FIXTURE/tools/lib/"
  chmod +x "$FIXTURE"/tools/*.sh

  # A resolved interview (no {{PROVIDER}} token) with the keys adopt.sh reads.
  cat > "$FIXTURE/.agents/config.yml" <<'CFG'
schema: 1
provider: some-provider
ledger:
  branch: agent-ledger
mention:
  variable: AGENT_MENTION
  default: "@agent"
CFG

  # floors.yml with one armed and one sentinel floor.
  cat > "$FIXTURE/floors.yml" <<'FLR'
schema: 1
floors:
  - key: backend.coverage.line
    value: unset
FLR

  # A stub run-agent.sh so step 5's credential print never hits the real one.
  cat > "$FIXTURE/tools/run-agent.sh" <<'STUB'
#!/usr/bin/env bash
echo "credential-hint-stub"
STUB
  chmod +x "$FIXTURE/tools/run-agent.sh"

  git -C "$FIXTURE" init -q -b main
  git -C "$FIXTURE" -c user.email=t@t -c user.name=t add -A
  git -C "$FIXTURE" -c user.email=t@t -c user.name=t commit -qm seed

  # No gh on PATH for any test unless a test adds a stub itself: a restricted
  # PATH proves the degradation story instead of depending on runner state.
  RESTRICTED_PATH="/usr/bin:/bin"
}

teardown() {
  rm -rf "$FIXTURE"
}

run_adopt() {
  # No TTY (bats already provides none) -> every offer takes its env default.
  ( cd "$FIXTURE" && PATH="$RESTRICTED_PATH" bash tools/adopt.sh "$@" )
}

@test "runs end to end non-interactively, exits 0, touches nothing by default" {
  run run_adopt
  [ "$status" -eq 0 ]
  # Default-No everywhere: the example survives, the tree stays committed-clean.
  [ -d "$FIXTURE/examples" ]
  [ -z "$(git -C "$FIXTURE" status --porcelain)" ]
}

@test "an unanswered interview stops the non-interactive run at step 1" {
  sed -i 's/^provider: some-provider/provider: "{{PROVIDER}}"/' "$FIXTURE/.agents/config.yml"
  git -C "$FIXTURE" -c user.email=t@t -c user.name=t commit -aqm token
  run run_adopt
  [ "$status" -eq 0 ]
  [[ "$output" == *"tools/init.sh"* ]]
  # It must NOT have claimed later steps while step 1 is unanswered.
  [[ "$output" != *"8/8"* ]]
}

@test "DELETE_EXAMPLE=y retires the example through adopt-layout" {
  DELETE_EXAMPLE=y run run_adopt
  [ "$status" -eq 0 ]
  [ ! -d "$FIXTURE/examples" ]
}

@test "a dirty tree is offered a commit and left alone on the default No" {
  echo x > "$FIXTURE/newfile"
  run run_adopt
  [ "$status" -eq 0 ]
  [[ "$output" == *"uncommitted changes"* ]]
  [ -f "$FIXTURE/newfile" ]
  [ -n "$(git -C "$FIXTURE" status --porcelain)" ]
}

@test "ADOPT_COMMIT=y commits and reports the push failure honestly (no remote)" {
  echo x > "$FIXTURE/newfile"
  ADOPT_COMMIT=y run run_adopt
  [ "$status" -eq 0 ]
  # The commit landed...
  git -C "$FIXTURE" log --oneline -1 | grep -q "adopt the agentic-sdlc process"
  # ...and the push (no origin here) is reported as a failure, not swallowed.
  [[ "$output" == *"[FAIL]"* ]]
}

@test "without gh, GitHub-side steps degrade to instructions, never to done" {
  run run_adopt
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cannot check repository secrets"* ]]
  [[ "$output" == *"branch-protection.md"* ]]
  # And never a false completion for those steps:
  [[ "$output" != *"AGENT_CLI_TOKEN is set"* ]]
  [[ "$output" != *"protection applied"* ]]
}

@test "uncalibrated floors are announced with the sentinel count, calibration not run by default" {
  run run_adopt
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 of 9 floors"* ]]
  [[ "$output" == *"measure-floors.sh"* ]]
}

@test "calibrated floors read as done" {
  sed -i 's/value: unset/value: 0.9/' "$FIXTURE/floors.yml"
  git -C "$FIXTURE" -c user.email=t@t -c user.name=t commit -aqm armed
  run run_adopt
  [ "$status" -eq 0 ]
  [[ "$output" == *"all floors calibrated"* ]]
}

@test "the closing line names both re-entry points" {
  run run_adopt
  [ "$status" -eq 0 ]
  [[ "$output" == *"tools/adopt.sh"* ]]
  [[ "$output" == *"tools/status.sh"* ]]
}
