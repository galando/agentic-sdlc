#!/usr/bin/env bats
#
# Scenarios "init.sh is idempotent" and "init.sh leaves no unresolved placeholder"
# (intent.md, SC7). Exercised against a small, HAND-BUILT fixture rather than a clone
# of this live repository: the mechanism under test is init.sh's own substitution,
# derivation and idempotency logic, and this repo's tree currently still carries known,
# out-of-scope placeholder-syntax mentions inherited from PR (a) docs and from test
# fixtures that legitimately sed-match a literal token (tests/run-agent-dryrun.bats's
# own `{{PROVIDER}}` pattern, tools/ledger.sh's fallback-value comments, and the
# spec-pipeline's own {{SLUG}}/{{DATE}} micro-templating). Resolving those is Task 29's
# full-tree sweep in PR (c); testing init.sh's MECHANISM against a controlled fixture
# here is the right scope for this suite and does not depend on that being done first.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/tools/lib" "$FIXTURE/tools/providers" "$FIXTURE/.agents/prompts" "$FIXTURE/docs/runbooks"

  cp "$REPO_ROOT/tools/init.sh" "$FIXTURE/tools/init.sh"
  cp "$REPO_ROOT/tools/check-placeholders.sh" "$FIXTURE/tools/check-placeholders.sh"
  cp "$REPO_ROOT/tools/lib/config.sh" "$FIXTURE/tools/lib/config.sh"
  cp "$REPO_ROOT/tools/providers/claude-code.sh" "$FIXTURE/tools/providers/claude-code.sh"
  cp "$REPO_ROOT/tools/providers/codex.sh" "$FIXTURE/tools/providers/codex.sh"
  chmod +x "$FIXTURE"/tools/*.sh "$FIXTURE"/tools/providers/*.sh

  cat > "$FIXTURE/.agents/config.yml" <<'CFG'
schema: 1
provider: "{{PROVIDER}}"
models:
  judge:     "{{MODEL_JUDGE}}"
  execute:   "{{MODEL_EXECUTE}}"
  challenge: "{{MODEL_CHALLENGE}}"
role_provider:
  judge:     "{{PROVIDER}}"
  execute:   "{{PROVIDER}}"
  challenge: compatible-endpoint
auth:
  claude-code:
    mode: subscription
    token_secret: AGENT_CLI_TOKEN
    required: true
  codex:
    mode: subscription
    token_secret: AGENT_CLI_TOKEN
    required: true
  compatible-endpoint:
    mode: api-key
    token_secret: CHALLENGE_API_KEY
    base_url: "{{CHALLENGE_BASE_URL}}"
    required: false
mention:
  variable: AGENT_MENTION
  default: "@agent"
alerts:
  channel: "{{ALERT_CHANNEL}}"
  webhook_secret: ALERT_WEBHOOK_URL
  command: ""
  severity_floor: S2
liveness:
  max-age-hours: 12
  staleness-hours: 36
ledger:
  branch: agent-ledger
  identity:
    name: "{{LEDGER_COMMIT_NAME}}"
    email: "{{LEDGER_COMMIT_EMAIL}}"
  agents:
    - id: health
      prompt: .agents/prompts/health.md
      role: execute
      schedule: "17 6 * * *"
      enabled: false
spec_contract: 1
CFG

  cat > "$FIXTURE/AGENTS.md" <<'MD'
# AGENTS.md
These rules bind every agent working on {{PRODUCT_NAME}}. Alerts go to {{ALERT_CHANNEL}}.
Fixes go through the {{BUILD_PIPELINE}} spec pipeline.
MD

  cat > "$FIXTURE/.agents/prompts/health.md" <<'MD'
# health
Watches {{PRODUCT_NAME}}, runner: {{RUNNER_LABEL}}.
MD

  cat > "$FIXTURE/ADOPTING.md" <<'MD'
# ADOPTING.md
Placeholder syntax looks like {{THIS}}.
MD
  cat > "$FIXTURE/README.md" <<'MD'
# README
See {{PLACEHOLDER}} syntax below.
MD
  cat > "$FIXTURE/CONTRIBUTING.md" <<'MD'
# CONTRIBUTING
MD
  cat > "$FIXTURE/docs/runbooks/agent-routines.md" <<'MD'
# agent-routines
Signals use {{HEALTH_SIGNAL}} as example syntax.
MD

  cat > "$FIXTURE/docs/runbooks/branch-protection.md" <<'MD'
# branch-protection
Settings -> Branches -> Add rule for {{DEFAULT_BRANCH}} in {{REPO_SLUG}}.
MD

  ( cd "$FIXTURE" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init )
  # An `origin` remote is what a real "Use this template" clone always has — without
  # one here, REPO_SLUG derivation fails for every test in this file, which is exactly
  # how the sed portability bug below went uncaught: no existing test exercised the
  # success path at all.
  ( cd "$FIXTURE" && git remote add origin "https://github.com/example-owner/example-repo.git" )

  cat > "$FIXTURE/answers.env" <<'ENV'
PRODUCT_NAME="Acme Widgets"
PROVIDER="claude-code"
MODEL_JUDGE="model-judge-1"
MODEL_EXECUTE="model-execute-1"
MODEL_CHALLENGE="model-challenge-1"
CHALLENGE_BASE_URL="https://compat.example.invalid"
ALERT_CHANNEL="none"
RUNNER_LABEL="ubuntu-latest"
LEDGER_COMMIT_NAME="sdlc-agent"
LEDGER_COMMIT_EMAIL="agent@example.invalid"
BUILD_PIPELINE="the built-in fallback"
ENV
}

teardown() {
  rm -rf "$FIXTURE"
}

@test "init.sh runs offline, no network tools invoked, exits 0" {
  cd "$FIXTURE"
  run bash tools/init.sh --answers answers.env
  [ "$status" -eq 0 ]
  [[ "$output" == *"No network calls"* ]]
}

@test "init.sh derives REPO_SLUG from an https origin remote" {
  cd "$FIXTURE"
  bash tools/init.sh --answers answers.env >/dev/null
  run grep -F 'example-owner/example-repo' docs/runbooks/branch-protection.md
  [ "$status" -eq 0 ]
  run grep -F '{{REPO_SLUG}}' docs/runbooks/branch-protection.md
  [ "$status" -ne 0 ]
}

# Regression test: the derivation regex originally used a non-greedy `[^/]+?` to stop
# short of a trailing ".git" — valid in GNU sed's -E dialect (what CI's Ubuntu runners
# use) but a syntax error in POSIX ERE, which is what BSD/macOS sed speaks. It failed
# with "repetition-operator operand invalid" for any adopter running init.sh locally on
# a Mac, silently for nobody (init.sh would just report the derivation failed and move
# on) — found by an end-to-end rehearsal on macOS, not by this suite, because no
# existing test before this one used an https remote with a ".git" suffix at all.
@test "init.sh derives REPO_SLUG from an origin remote ending in .git (portable sed)" {
  cd "$FIXTURE"
  git remote set-url origin "https://github.com/example-owner/example-repo.git"
  run bash tools/init.sh --answers answers.env
  [ "$status" -eq 0 ]
  [[ "$output" != *"repetition-operator"* ]]
  [[ "$output" == *"REPO_SLUG -> example-owner/example-repo"* ]]
}

@test "init.sh derives REPO_SLUG from an ssh-style origin remote" {
  cd "$FIXTURE"
  git remote set-url origin "git@github.com:example-owner/example-repo.git"
  run bash tools/init.sh --answers answers.env
  [ "$status" -eq 0 ]
  [[ "$output" == *"REPO_SLUG -> example-owner/example-repo"* ]]
}

@test "init.sh resolves every P1 placeholder it knows about" {
  cd "$FIXTURE"
  bash tools/init.sh --answers answers.env >/dev/null
  run grep -c 'Acme Widgets' AGENTS.md
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  run grep -F '{{PRODUCT_NAME}}' AGENTS.md .agents/prompts/health.md
  [ "$status" -ne 0 ]
  run grep -F '{{PROVIDER}}' .agents/config.yml
  [ "$status" -ne 0 ]
}

@test "init.sh does not self-mutate its own source on a second run" {
  cd "$FIXTURE"
  bash tools/init.sh --answers answers.env >/dev/null
  git -c user.email=t@t -c user.name=t add -A
  git -c user.email=t@t -c user.name=t commit -q -m "after run 1"
  bash tools/init.sh --answers answers.env >/dev/null
  run git diff --stat -- tools/init.sh tools/check-placeholders.sh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "init.sh is idempotent: a second run with the same answers is an empty diff" {
  cd "$FIXTURE"
  bash tools/init.sh --answers answers.env >/dev/null
  git -c user.email=t@t -c user.name=t add -A
  git -c user.email=t@t -c user.name=t commit -q -m "after run 1"
  bash tools/init.sh --answers answers.env >/dev/null
  run git status --porcelain
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "init.sh leaves no unresolved placeholder outside the allowlist" {
  cd "$FIXTURE"
  run bash tools/init.sh --answers answers.env
  [ "$status" -eq 0 ]
  run grep -rn '{{' --include="*.md" --include="*.yml" .
  # Only the allowlisted files (and .git internals, excluded by extension filters) may
  # still carry the literal syntax.
  bad=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    f="${line%%:*}"
    case "$f" in
      ./ADOPTING.md|./README.md|./CONTRIBUTING.md|./docs/runbooks/agent-routines.md) : ;;
      *) bad="$bad
$line" ;;
    esac
  done <<<"$output"
  [ -z "$bad" ] || { echo "$bad"; false; }
}

@test "init.sh prints the unverified-stub banner and does not resolve when the provider is a stub" {
  cd "$FIXTURE"
  sed -i.bak 's/PROVIDER="claude-code"/PROVIDER="codex"/' answers.env
  rm -f answers.env.bak
  run bash tools/init.sh --answers answers.env
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIED STUB"* ]]
  [[ "$output" == *"ADAPTER_STATUS=verified"* ]]
  [[ "$output" == *"re-run tools/init.sh"* ]]
}

@test "init.sh prints the closing manual checklist with branch protection LAST" {
  cd "$FIXTURE"
  run bash tools/init.sh --answers answers.env
  [ "$status" -eq 0 ]
  [[ "$output" == *"secrets"* ]]
  [[ "$output" == *"ledger orphan branch"* ]]
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" == *"measure-floors.sh"* ]]
  last_branch_protection="$(printf '%s\n' "$output" | grep -n 'branch protection' | tail -1 | cut -d: -f1)"
  last_secrets="$(printf '%s\n' "$output" | grep -n 'repository secrets' | tail -1 | cut -d: -f1)"
  [ -n "$last_branch_protection" ]
  [ -n "$last_secrets" ]
  [ "$last_branch_protection" -gt "$last_secrets" ]
}

@test "init.sh makes no network call (offline PATH, coreutils only)" {
  cd "$FIXTURE"
  BIN_ONLY="$(mktemp -d)"
  for tool in bash sh grep sed awk cat printf mktemp basename dirname mkdir rm tr head tail cut wc env true false date git; do
    src="$(command -v "$tool" 2>/dev/null)" || continue
    ln -sf "$src" "$BIN_ONLY/$tool"
  done
  run env PATH="$BIN_ONLY" bash tools/init.sh --answers answers.env
  [ "$status" -eq 0 ]
  rm -rf "$BIN_ONLY"
}

@test "check-placeholders.sh fails loudly on a real unresolved placeholder" {
  cd "$FIXTURE"
  # The interview has to run FIRST. Before it does, unresolved placeholders are the
  # expected state of a fresh template and the check passes loudly by design — failing
  # there would make the first pull request on an untouched repository red. Strictness
  # is what applies AFTERWARDS, and that is what this asserts: once the tree is
  # configured, a leftover token is an unfinished job and fails the build.
  bash tools/init.sh --answers answers.env >/dev/null
  echo 'stray {{UNRESOLVED_TOKEN}} here' >> AGENTS.md
  run bash tools/check-placeholders.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"UNRESOLVED_TOKEN"* ]]
}

@test "check-placeholders.sh passes loudly BEFORE the interview has run" {
  # The other half of the same rule, and the one a real Actions run caught: an
  # uninitialised template must not be reported as broken.
  cd "$FIXTURE"
  echo 'stray {{UNRESOLVED_TOKEN}} here' >> AGENTS.md
  run bash tools/check-placeholders.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT a failure"* ]]
}

@test "check-placeholders.sh passes on a fully-resolved tree" {
  cd "$FIXTURE"
  bash tools/init.sh --answers answers.env >/dev/null
  run bash tools/check-placeholders.sh
  [ "$status" -eq 0 ]
}

@test "init.sh removes the template's explainer site and its Pages workflow, and says so" {
  cd "$FIXTURE"
  mkdir -p site .github/workflows
  echo '<title>template site</title>' > site/index.html
  echo 'name: pages' > .github/workflows/pages.yml
  run bash tools/init.sh --answers answers.env
  [ "$status" -eq 0 ]
  [ ! -d site ]
  [ ! -f .github/workflows/pages.yml ]
  [[ "$output" == *"explainer site"* ]]
}

@test "init.sh's ledger-branch offer defaults to skip non-interactively, pointing at the tool" {
  # The interview's offline contract must hold on the DEFAULT path: with no TTY
  # and no CREATE_LEDGER_BRANCH=y, nothing network-shaped runs — the offer prints
  # the one command to run later instead.
  cd "$FIXTURE"
  run bash tools/init.sh --answers answers.env
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent ledger branch"* ]]
  [[ "$output" == *"tools/create-ledger-branch.sh"* ]]
  [[ "$output" == *"Skipped."* ]]
}

@test "init.sh removes the TEMPLATE-only files an adopter must never inherit" {
  # These deletions were unconditional-by-design and untested, which is the shape that
  # quietly stops happening: nothing here is a placeholder, so the placeholder sweep does
  # not notice, and an adopted tree just carries files describing somebody else's project
  # and a relationship (an upstream to sync from) that the adopter does not have.
  #
  # Verified by hand once during the change that added the upstream tooling; a hand
  # verification that leaves no test behind is a verification that expires.
  mkdir -p "$FIXTURE/site" "$FIXTURE/.github/workflows" "$FIXTURE/tests"
  echo x > "$FIXTURE/site/index.html"
  echo x > "$FIXTURE/.github/workflows/pages.yml"
  cp "$REPO_ROOT/tools/check-upstream-drift.sh" "$FIXTURE/tools/check-upstream-drift.sh"
  cp "$REPO_ROOT/.agents/upstream-sync.json"    "$FIXTURE/.agents/upstream-sync.json"
  echo x > "$FIXTURE/tests/upstream-drift.bats"

  cd "$FIXTURE"
  run bash tools/init.sh --answers answers.env
  [ "$status" -eq 0 ]

  for leftover in site .github/workflows/pages.yml \
                  tools/check-upstream-drift.sh .agents/upstream-sync.json \
                  tests/upstream-drift.bats; do
    if [ -e "$FIXTURE/$leftover" ]; then
      echo "# init.sh left a template-only file in the adopted tree: $leftover"
      false
    fi
  done
}

@test "init.sh is still idempotent with those files already gone" {
  # The second run must not fail trying to delete what the first run removed.
  cd "$FIXTURE"
  bash tools/init.sh --answers answers.env >/dev/null
  run bash tools/init.sh --answers answers.env
  [ "$status" -eq 0 ]
}
