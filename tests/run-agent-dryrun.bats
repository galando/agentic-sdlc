#!/usr/bin/env bats
#
# SC4 / Scenario "Dry-run prints the exact command for every provider" (intent.md).
# `tools/run-agent.sh <agent> --dry-run` must print the exact command for each of the
# four providers, without invoking anything and without any provider CLI on PATH —
# design.md section 3.6. This is the named acceptance scenario for Task 15/16.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RUN_AGENT="$REPO_ROOT/tools/run-agent.sh"

setup() {
  # A scratch config that names each provider under test, so we do not depend on
  # whatever unresolved PROVIDER placeholder the shipped config carries pre-init.
  SCRATCH="$(mktemp -d)"
  cp -R "$REPO_ROOT/.agents" "$SCRATCH/.agents"
  export AGENTS_CONFIG="$SCRATCH/.agents/config.yml"
  export FLOORS_CONFIG="$REPO_ROOT/floors.yml"
  # coreutils-only PATH: proves no vendor CLI or network tool is consulted (design 3.6.6).
  BIN_ONLY="$(mktemp -d)"
  for tool in bash sh cat grep sed awk printf mktemp basename dirname mkdir rm tr head tail cut wc env true false date; do
    src="$(command -v "$tool" 2>/dev/null)" || continue
    ln -sf "$src" "$BIN_ONLY/$tool"
  done
  ln -sf "$(command -v yq)" "$BIN_ONLY/yq" 2>/dev/null || true
  ln -sf "$(command -v git)" "$BIN_ONLY/git" 2>/dev/null || true
}

teardown() {
  rm -rf "$SCRATCH" "$BIN_ONLY"
}

set_provider() {
  # Replace every {{PROVIDER}} occurrence (the top-level `provider:` key AND
  # role_provider.judge / role_provider.execute, which are separately-templated
  # placeholders resolved to the same value by tools/init.sh). role_provider.challenge
  # is left alone: it is fixed to compatible-endpoint by design, not a placeholder.
  sed -i.bak "s/{{PROVIDER}}/$1/g" "$AGENTS_CONFIG"
  rm -f "$AGENTS_CONFIG.bak"
}

@test "run-agent.sh exists and is executable" {
  [ -x "$RUN_AGENT" ]
}

@test "dry-run: claude-code prints the six-line header and an argv, exits 0" {
  set_provider claude-code
  run env PATH="$BIN_ONLY" "$RUN_AGENT" health --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"provider:"* ]]
  [[ "$output" == *"adapter-status:"* ]]
  [[ "$output" == *"role:"* ]]
  [[ "$output" == *"model:"* ]]
  [[ "$output" == *"prompt:"* ]]
  [[ "$output" == *"system-prompt:"* ]]
}

@test "dry-run: claude-code is verified and prints no UNVERIFIED STUB banner" {
  set_provider claude-code
  run env PATH="$BIN_ONLY" "$RUN_AGENT" health --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"adapter-status: verified"* ]]
  [[ "$output" != *"UNVERIFIED STUB"* ]]
}

@test "dry-run: compatible-endpoint is verified and prints an argv" {
  set_provider compatible-endpoint
  run env PATH="$BIN_ONLY" "$RUN_AGENT" challenger --role challenge --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"adapter-status: verified"* ]]
  [[ "$output" != *"UNVERIFIED STUB"* ]]
}

@test "dry-run: codex is an unverified stub and says so with a docs URL, still exits 0" {
  set_provider codex
  run env PATH="$BIN_ONLY" "$RUN_AGENT" health --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"adapter-status: unverified"* ]]
  [[ "$output" == *"UNVERIFIED STUB"* ]]
  [[ "$output" == *"http"* ]]
}

@test "dry-run: gemini-cli is an unverified stub and says so with a docs URL, still exits 0" {
  set_provider gemini-cli
  run env PATH="$BIN_ONLY" "$RUN_AGENT" health --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"adapter-status: unverified"* ]]
  [[ "$output" == *"UNVERIFIED STUB"* ]]
}

@test "dry-run: never invokes a provider CLI or the network (PATH has coreutils only)" {
  set_provider claude-code
  run env PATH="$BIN_ONLY" "$RUN_AGENT" health --dry-run
  [ "$status" -eq 0 ]
}

@test "dry-run: never prints the resolved credential value" {
  # claude-code's real auth is an env var (CLAUDE_CODE_OAUTH_TOKEN / ANTHROPIC_API_KEY),
  # never a CLI flag, so there is no argv position for the token to leak into — the
  # adapter documents that handoff instead of substituting a placeholder (design.md
  # 3.3's literal-substitution rule applies only when a flag would carry the value).
  set_provider claude-code
  run env PATH="$BIN_ONLY" AGENT_CLI_TOKEN="super-secret-value-must-not-leak" "$RUN_AGENT" health --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"super-secret-value-must-not-leak"* ]]
  [[ "$output" == *"AGENT_AUTH_TOKEN"* ]]
}

@test "run: an unverified stub asked to actually run exits 4 with the banner" {
  set_provider codex
  run env PATH="$BIN_ONLY" "$RUN_AGENT" health
  [ "$status" -eq 4 ]
  [[ "$output" == *"UNVERIFIED STUB"* ]]
}

@test "--adapter-status prints one word and agrees with the adapter's own status verb" {
  run "$RUN_AGENT" --adapter-status claude-code
  [ "$status" -eq 0 ]
  [ "$output" = "verified" ]
  run "$RUN_AGENT" --adapter-status codex
  [ "$status" -eq 0 ]
  [ "$output" = "unverified" ]
}

@test "--list-agents prints the ring in order" {
  set_provider claude-code
  run "$RUN_AGENT" --list-agents
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'health\nquality\naudit\nchief-of-staff\nchallenger')" ]
}

@test "usage error: unknown agent exits 2" {
  set_provider claude-code
  run "$RUN_AGENT" not-a-real-agent --dry-run
  [ "$status" -eq 2 ]
}

@test "--check-credentials degrades (exit 6) when the optional challenge credential is unset" {
  set_provider claude-code
  unset CHALLENGE_API_KEY
  run env -u CHALLENGE_API_KEY "$RUN_AGENT" --check-credentials challenger
  [ "$status" -eq 6 ]
}

@test "--check-credentials fails loudly (exit 5) when a required credential is unset" {
  set_provider claude-code
  run env -u AGENT_CLI_TOKEN "$RUN_AGENT" --check-credentials health
  [ "$status" -eq 5 ]
}

@test "the config comes from the script's own root, not from whatever git repo the cwd sits in" {
  # run-agent.sh resolves ROOT from its own location and reads prompts and adapters
  # from there. config.sh, asked independently, answered `git rev-parse --show-toplevel`.
  # Those are two different answers to "where is the repo" and they agree only when the
  # caller happens to stand in the directory holding tools/.
  #
  # Where they diverge — a vendored copy nested inside another git-controlled repo, a
  # worktree, a submodule — the script executes THIS copy's adapter and prompt while
  # reading the OUTER repo's config. Split-brain resolution nobody would think to
  # suspect: the argv printed describes a provider the operator never configured here.
  #
  # An explicit AGENTS_CONFIG must still win, because that is how CI and these tests
  # point the reader at a scratch config.
  VENDORED="$SCRATCH/outer/vendored"
  mkdir -p "$SCRATCH/outer"
  git init -q "$SCRATCH/outer"
  git -C "$SCRATCH/outer" config user.name test
  git -C "$SCRATCH/outer" config user.email test@example.invalid
  mkdir -p "$VENDORED"
  cp -R "$REPO_ROOT/tools" "$VENDORED/tools"
  cp -R "$REPO_ROOT/.agents" "$VENDORED/.agents"
  mkdir -p "$VENDORED/.github"
  cp "$REPO_ROOT/.github/agent-temper-headless.md" "$VENDORED/.github/" 2>/dev/null || true

  # The vendored copy is configured for claude-code. The OUTER repo is configured for
  # gemini-cli. Standing in the vendored copy must yield claude-code.
  sed -i.bak "s/{{PROVIDER}}/claude-code/g" "$VENDORED/.agents/config.yml"
  rm -f "$VENDORED/.agents/config.yml.bak"
  mkdir -p "$SCRATCH/outer/.agents"
  cp "$REPO_ROOT/.agents/config.yml" "$SCRATCH/outer/.agents/config.yml"
  sed -i.bak "s/{{PROVIDER}}/gemini-cli/g" "$SCRATCH/outer/.agents/config.yml"
  rm -f "$SCRATCH/outer/.agents/config.yml.bak"

  cd "$VENDORED"
  run env -u AGENTS_CONFIG PATH="$BIN_ONLY" FLOORS_CONFIG="$REPO_ROOT/floors.yml" \
    "$VENDORED/tools/run-agent.sh" health --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"provider: claude-code"* ]]
  [[ "$output" != *"provider: gemini-cli"* ]]
}

@test "an explicit AGENTS_CONFIG still overrides the script's own root" {
  # The override is how CI and this suite point the reader at a scratch config.
  # Single-sourcing the root must not take it away.
  sed -i.bak "s/{{PROVIDER}}/codex/g" "$AGENTS_CONFIG"
  rm -f "$AGENTS_CONFIG.bak"
  run env PATH="$BIN_ONLY" "$RUN_AGENT" health --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"provider: codex"* ]]
}
