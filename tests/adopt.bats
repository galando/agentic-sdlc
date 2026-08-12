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
  # A committer identity, configured in the FIXTURE repo — an adopter's machine
  # has one, a bare CI runner does not, and adopt.sh's commit offer runs plain
  # `git commit`. Without this the offer's honest [FAIL] path fires in CI and
  # the commit assertion below fails there while passing on any dev machine.
  git -C "$FIXTURE" config user.email t@t
  git -C "$FIXTURE" config user.name t
  git -C "$FIXTURE" add -A
  git -C "$FIXTURE" commit -qm seed

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

# A gh stub plus a GitHub-shaped origin that never reaches the network. The
# fetch URL must stay the https form — the slug is parsed from `git remote
# get-url`, and get-url expands url.*.insteadOf rewrites, so an insteadOf
# redirect would hand the slug parse a local path. Instead: pushes go to a
# local bare repository via pushurl (which get-url does not return), and
# fetches are strangled fast by run_adopt_gh's dead proxy below.
setup_gh_fixture() {
  git -C "$FIXTURE" init -q --bare origin.git
  git -C "$FIXTURE" remote add origin "https://github.com/acme/widget.git"
  git -C "$FIXTURE" config remote.origin.pushurl "$FIXTURE/origin.git"

  mkdir -p "$FIXTURE/stubbin"
  cat > "$FIXTURE/stubbin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_LOG:?}"
case "$*" in
  "auth status"*)               exit 0 ;;
  "secret list"*)               exit 0 ;;   # empty output: no secret is set
  "secret set"*)                exit 0 ;;
  "pr create"*)                 exit 0 ;;
  *"-X PUT"*)                   exit 0 ;;
  *actions/permissions/workflow*) echo "false"; exit 0 ;;  # the checkbox is OFF
  *branches/*/protection*)      exit 1 ;;   # not protected
esac
exit 0
GH
  chmod +x "$FIXTURE/stubbin/gh"
}

run_adopt_gh() {
  # The dead proxy makes any accidental network fetch (step 3's ls-remote
  # against the https origin) fail in milliseconds instead of hanging an
  # offline run — the degrade path is the expected result, not a hazard.
  ( cd "$FIXTURE" && GH_LOG="$FIXTURE/gh.log" \
      HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 \
      https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 NO_PROXY= no_proxy= \
      PATH="$FIXTURE/stubbin:$RESTRICTED_PATH" bash tools/adopt.sh "$@" )
}

@test "runs end to end non-interactively, exits 0, touches nothing by default" {
  run run_adopt
  [ "$status" -eq 0 ]
  # Default-No everywhere: the example survives, the tree stays committed-clean.
  [ -d "$FIXTURE/examples" ]
  [ -z "$(git -C "$FIXTURE" status --porcelain)" ]
}

@test "an unanswered interview stops the non-interactive run at step 1" {
  # sed -i.bak, never a bare sed -i: BSD sed reads the next argument as the suffix and
  # a macOS run dies with "invalid command code". The .bak is removed so the fixture's
  # working tree stays clean — adopt.sh branches on exactly that.
  sed -i.bak 's/^provider: some-provider/provider: "{{PROVIDER}}"/' "$FIXTURE/.agents/config.yml"
  rm -f "$FIXTURE/.agents/config.yml.bak"
  git -C "$FIXTURE" commit -aqm token
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

@test "no product code stops the run at step 2 rather than walking on" {
  rm -rf "$FIXTURE/examples"   # untracked-empty in the fixture: nothing to commit
  run run_adopt
  [ "$status" -eq 0 ]
  [[ "$output" == *"[YOURS] Add your product code"* ]]
  [[ "$output" == *"Stopping here"* ]]
  # The steps after it all need that code to mean anything, so none may be
  # claimed, offered, or reported on while it is missing.
  [[ "$output" != *"3/8"* ]]
  [[ "$output" != *"8/8"* ]]
}

@test "ADOPT_CONTINUE_WITHOUT_PRODUCT=y walks the rest with the code still missing" {
  rm -rf "$FIXTURE/examples"   # untracked-empty in the fixture: nothing to commit
  ADOPT_CONTINUE_WITHOUT_PRODUCT=y run run_adopt
  [ "$status" -eq 0 ]
  [[ "$output" == *"8/8"* ]]
}

@test "a product at the root layout is not asked about at all" {
  rm -rf "$FIXTURE/examples"
  mkdir -p "$FIXTURE/backend"
  echo x > "$FIXTURE/backend/pom.xml"
  git -C "$FIXTURE" add -A
  git -C "$FIXTURE" commit -qm "product"
  run run_adopt
  [ "$status" -eq 0 ]
  [[ "$output" == *"[done] product present at: backend/"* ]]
  [[ "$output" != *"Stopping here"* ]]
  [[ "$output" == *"8/8"* ]]
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
  # The Actions setting the steward dies on gets its manual path too.
  [[ "$output" == *"create and approve pull requests"* ]]
  # And never a false completion for those steps:
  [[ "$output" != *"AGENT_CLI_TOKEN is set"* ]]
  [[ "$output" != *"protection applied"* ]]
  [[ "$output" != *"workflow permissions updated"* ]]
}

@test "a missing credential is an offer; the default No changes nothing and prints the manual command" {
  setup_gh_fixture
  run run_adopt_gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"AGENT_CLI_TOKEN is not set"* ]]
  [[ "$output" == *"gh secret set AGENT_CLI_TOKEN"* ]]
  [[ "$output" == *"'Allow GitHub Actions to create and approve pull requests' is OFF"* ]]
  # Default-No: gh was only ever asked questions, never told to change anything.
  ! grep -qE '^(secret set|api -X PUT)' "$FIXTURE/gh.log"
}

@test "ADOPT_SET_TOKEN=y and ADOPT_WORKFLOW_PERMS=y drive gh, and only what was accepted" {
  setup_gh_fixture
  ADOPT_SET_TOKEN=y ADOPT_WORKFLOW_PERMS=y run run_adopt_gh
  [ "$status" -eq 0 ]
  grep -q "secret set AGENT_CLI_TOKEN --repo acme/widget" "$FIXTURE/gh.log"
  grep -q "api -X PUT repos/acme/widget/actions/permissions/workflow" "$FIXTURE/gh.log"
  # The handoff PAT was NOT accepted, so it was not set.
  ! grep -q "secret set STEWARD_HANDOFF_PAT" "$FIXTURE/gh.log"
}

@test "an unset challenge credential names its consequence (one opinion, steward woken)" {
  setup_gh_fixture
  cat >> "$FIXTURE/.agents/config.yml" <<'CFG'
role_provider:
  challenge: chal-prov
auth:
  chal-prov:
    token_secret: CHALLENGE_API_KEY
CFG
  git -C "$FIXTURE" commit -aqm challenge-config
  run run_adopt_gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHALLENGE_API_KEY is not set"* ]]
  [[ "$output" == *"wakes the steward"* ]]
  [[ "$output" == *"STEWARD_HANDOFF_PAT is not set"* ]]
}

@test "ADOPT_FLOORS_PR=y branches, commits, pushes and opens the calibration PR" {
  setup_gh_fixture
  # A calibrator stub: arms the one floor so there is a real diff to commit.
  cat > "$FIXTURE/tools/measure-floors.sh" <<'STUB'
#!/usr/bin/env bash
sed -i.bak 's/value: unset/value: 0.9/' floors.yml && rm -f floors.yml.bak
STUB
  chmod +x "$FIXTURE/tools/measure-floors.sh"
  ADOPT_MEASURE=y ADOPT_FLOORS_PR=y run run_adopt_gh
  [ "$status" -eq 0 ]
  # The branch exists on the (local, rewritten) origin with the calibration commit.
  git -C "$FIXTURE/origin.git" show-ref --verify -q refs/heads/calibrate-floors
  git -C "$FIXTURE" log calibrate-floors --oneline -1 | grep -q "calibrate the quality floors"
  grep -q "pr create" "$FIXTURE/gh.log"
  # And the one thing the tool must NOT do is claimed nowhere: the merge is human.
  [[ "$output" == *"MERGE it once green"* ]]
}

@test "uncalibrated floors are announced with the sentinel count, calibration not run by default" {
  run run_adopt
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 of 9 floors"* ]]
  [[ "$output" == *"measure-floors.sh"* ]]
}

@test "calibrated floors read as done" {
  sed -i.bak 's/value: unset/value: 0.9/' "$FIXTURE/floors.yml"   # .bak: see step 1's note
  rm -f "$FIXTURE/floors.yml.bak"
  git -C "$FIXTURE" commit -aqm armed
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
