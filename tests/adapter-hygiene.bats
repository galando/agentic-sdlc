#!/usr/bin/env bats
#
# design.md section 3.2: "Every adapter begins with `set -euo pipefail` and `set +x`.
# A `set -x` anywhere in an adapter prints AGENT_AUTH_TOKEN into a public Actions log."
# This guard greps for `set -x` and for any echo/printf of $AGENT_AUTH_TOKEN and fails
# on either. Also asserts the ADAPTER_STATUS / ADAPTER_DOCS_URL contract (design.md 3.4).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PROVIDERS_DIR="$REPO_ROOT/tools/providers"

@test "adapter hygiene: exactly four adapters ship" {
  count="$(find "$PROVIDERS_DIR" -maxdepth 1 -name '*.sh' | wc -l | tr -d ' ')"
  [ "$count" -eq 4 ]
}

@test "adapter hygiene: no adapter ever enables xtrace" {
  # A real `set -x` statement starts the line (only leading whitespace before it).
  # Mentioning the string "set -x" inside a comment, to explain why the adapter avoids
  # it, is fine and expected — this checks for the statement, not the phrase.
  run grep -rnE '^[[:space:]]*set -x([[:space:]]|$)' "$PROVIDERS_DIR"
  [ "$status" -ne 0 ]
}

@test "adapter hygiene: no adapter echoes or printfs the INTERPOLATED \$AGENT_AUTH_TOKEN value" {
  # An adapter is allowed to print the literal, ESCAPED text "\$AGENT_AUTH_TOKEN" as
  # documentation (design.md 3.3's own literal-substitution idiom) — that is a string,
  # never the secret. What this guards against is an UNESCAPED $AGENT_AUTH_TOKEN or
  # ${AGENT_AUTH_TOKEN} inside an echo/printf, which the shell would interpolate to the
  # real credential value before printing it.
  for f in "$PROVIDERS_DIR"/*.sh; do
    run awk '
      /echo|printf/ {
        line = $0
        gsub(/\\\$/, "@ESCAPED@", line)
        if (line ~ /\$\{?AGENT_AUTH_TOKEN/) { print; bad = 1 }
      }
      END { exit (bad ? 1 : 0) }
    ' "$f"
    [ "$status" -eq 0 ]
  done
}

@test "adapter hygiene: every adapter begins with set -euo pipefail then set +x" {
  for f in "$PROVIDERS_DIR"/*.sh; do
    run grep -n '^set -euo pipefail$' "$f"
    [ "$status" -eq 0 ]
    run grep -n '^set +x' "$f"
    [ "$status" -eq 0 ]
  done
}

@test "adapter hygiene: each adapter declares exactly one ADAPTER_STATUS line at column 0" {
  for f in "$PROVIDERS_DIR"/*.sh; do
    n="$(grep -cE '^ADAPTER_STATUS=(verified|unverified)([[:space:]]|$)' "$f")"
    [ "$n" -eq 1 ]
  done
}

@test "adapter hygiene: each adapter declares exactly one ADAPTER_DOCS_URL line" {
  for f in "$PROVIDERS_DIR"/*.sh; do
    n="$(grep -cE '^ADAPTER_DOCS_URL=' "$f")"
    [ "$n" -eq 1 ]
  done
}

@test "adapter hygiene: run-agent.sh --adapter-status agrees with each adapter's own status verb" {
  for f in "$PROVIDERS_DIR"/*.sh; do
    name="$(basename "$f" .sh)"
    from_lib="$("$REPO_ROOT/tools/run-agent.sh" --adapter-status "$name")"
    from_self="$("$f" status)"
    [ "$from_lib" = "$from_self" ]
  done
}

@test "adapter hygiene: exactly two adapters are verified and two are unverified" {
  verified=0
  unverified=0
  for f in "$PROVIDERS_DIR"/*.sh; do
    case "$("$f" status)" in
      verified) verified=$((verified+1)) ;;
      unverified) unverified=$((unverified+1)) ;;
    esac
  done
  [ "$verified" -eq 2 ]
  [ "$unverified" -eq 2 ]
}

@test "adapter hygiene: compatible-endpoint and claude-code are the two verified adapters" {
  [ "$("$PROVIDERS_DIR/claude-code.sh" status)" = "verified" ]
  [ "$("$PROVIDERS_DIR/compatible-endpoint.sh" status)" = "verified" ]
  [ "$("$PROVIDERS_DIR/codex.sh" status)" = "unverified" ]
  [ "$("$PROVIDERS_DIR/gemini-cli.sh" status)" = "unverified" ]
}

@test "claude-code adapter bootstraps its own CLI on a hosted runner, refuses politely elsewhere" {
  # The first live review on a fresh adoption died with exit 127: hosted GitHub
  # runners do not ship the CLI, and no workflow may install it (vendor
  # neutrality), so the adapter — the one vendor-specific home — owns the
  # bootstrap. Pin both halves: the CI install path and the workstation refusal.
  adapter="$REPO_ROOT/tools/providers/claude-code.sh"
  grep -qF 'npm install -g @anthropic-ai/claude-code' "$adapter"
  grep -qF 'GITHUB_ACTIONS' "$adapter"
  # Workstation half, executed: no CLI on PATH, not CI -> exit 4 with the install command.
  run env -u GITHUB_ACTIONS -u AGENT_CLI_AUTOINSTALL \
    PATH=/usr/bin:/bin CLAUDE_CODE_BIN=definitely-not-a-real-cli \
    AGENT_WORKDIR=/tmp AGENT_PROMPT_FILE=/dev/null AGENT_AUTH_MODE=subscription \
    bash "$adapter" run
  [ "$status" -eq 4 ]
  [[ "$output" == *"npm install -g"* ]]
}
