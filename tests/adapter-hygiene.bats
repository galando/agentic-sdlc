#!/usr/bin/env bats
#
# design.md section 3.2: "Every adapter begins with `set -euo pipefail` and `set +x`.
# A `set -x` anywhere in an adapter prints AGENT_AUTH_TOKEN into a public Actions log."
# This guard greps for `set -x` and for any echo/printf of $AGENT_AUTH_TOKEN and fails
# on either. Also asserts the ADAPTER_STATUS / ADAPTER_DOCS_URL contract (design.md 3.4).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PROVIDERS_DIR="$REPO_ROOT/tools/providers"

# The census tests below (how many adapters ship, which are verified) guard the
# TEMPLATE's inventory: an unverified stub must never ship as verified upstream.
# An ADOPTED tree is a different animal — init.sh's own instructions tell an
# adopter who chose codex/gemini to finish the stub and flip ADAPTER_STATUS to
# verified, and a Bedrock-style shop may add an adapter of its own. Pinning the
# template's census in a required check on the adopter's repo turns the
# documented promotion path into a red X. Same template-vs-adopted discriminator
# day-one-green.bats and status.sh already use: an unresolved provider token
# means this is still the template. The per-adapter hygiene tests (xtrace,
# token echo, status contract) stay unconditional — those lessons hold for any
# adapter anyone ever adds.
adopted_tree() {
  ! grep -qF '{{PROVIDER}}' "$REPO_ROOT/.agents/config.yml"
}

@test "adapter hygiene: exactly four adapters ship" {
  adopted_tree && skip "adopted tree: the adapter inventory is the adopter's"
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
  adopted_tree && skip "adopted tree: the adapter inventory is the adopter's"
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
  adopted_tree && skip "adopted tree: the adapter inventory is the adopter's"
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

@test "compatible-endpoint passes proxy/CA vars through env -i and still scrubs credentials" {
  # The subprocess wipe (`env -i`, multi-model-review.md lesson 1) exists so an
  # inherited MODEL credential can never silently win over the challenge key. It
  # once wiped HTTPS_PROXY and the CA-bundle variables too, which killed the
  # challenge role — and only the challenge role — behind a corporate egress
  # proxy, and because the credential is optional the failure degraded to "one
  # opinion" on every run with nothing red. Proxy and trust-anchor variables are
  # credential-inert (they select the network path, not the backend), so they
  # pass through BY NAME. Executed, not grepped: run the adapter against a stub
  # CLI that dumps its environment, then assert both halves of the contract.
  # The adapter's exec line runs the CLI under timeout(1) — GNU coreutils, absent
  # on stock macOS. That is the adapter's runtime dependency, not the passthrough
  # contract under test; skip rather than fail the suite on a maintainer's laptop.
  command -v timeout >/dev/null 2>&1 || skip "timeout(1) not on PATH (stock macOS)"
  adapter="$REPO_ROOT/tools/providers/compatible-endpoint.sh"
  workdir="$(mktemp -d)"
  dump="$workdir/env-dump"
  stub="$workdir/stub-cli"
  printf '#!/bin/sh\nenv > "%s"\nexit 0\n' "$dump" > "$stub"
  chmod +x "$stub"
  echo "prompt" > "$workdir/prompt.md"

  run env \
    CLAUDE_CODE_BIN="$stub" \
    AGENT_WORKDIR="$workdir" \
    AGENT_PROMPT_FILE="$workdir/prompt.md" \
    AGENT_BASE_URL="https://challenge.example/api" \
    AGENT_AUTH_TOKEN="challenge-key-value" \
    AGENT_MODEL="stub-model" \
    AGENT_ALLOWED_TOOLS="Read" \
    AGENT_SYSTEM_PROMPT_FILE=/dev/null \
    HTTPS_PROXY="http://proxy.corp.example:3128" \
    NO_PROXY="localhost" \
    NODE_EXTRA_CA_CERTS="/etc/corp/ca.pem" \
    OPENAI_API_KEY="must-not-survive" \
    ANTHROPIC_API_KEY="parent-session-key-must-not-survive" \
    bash "$adapter" run
  [ "$status" -eq 0 ]
  [ -f "$dump" ]
  # The network path survives...
  grep -qxF 'HTTPS_PROXY=http://proxy.corp.example:3128' "$dump"
  grep -qxF 'NO_PROXY=localhost' "$dump"
  grep -qxF 'NODE_EXTRA_CA_CERTS=/etc/corp/ca.pem' "$dump"
  # ...the credential isolation does not weaken... (run + status, never a bare
  # `! grep`: bash exempts !-negated pipelines from errexit, so a bare negation
  # mid-test can never fail — verified by sabotaging the passthrough loop.)
  run grep -q 'must-not-survive' "$dump"
  [ "$status" -ne 0 ]
  # ...and the challenge backend + key are still the explicitly-set ones.
  grep -qxF 'ANTHROPIC_BASE_URL=https://challenge.example/api' "$dump"
  grep -qxF 'ANTHROPIC_API_KEY=challenge-key-value' "$dump"
  rm -rf "$workdir"
}

@test "claude-code adapter never passes --bare — it makes the subscription token invisible" {
  # The first live review to actually reach the CLI died with "Not logged in"
  # while a valid, freshly-minted token sat in the secret. The CLI's own help is
  # explicit: under --bare, "Anthropic auth is strictly ANTHROPIC_API_KEY or
  # apiKeyHelper via --settings (OAuth and keychain are never read)" — so --bare
  # and this template's DEFAULT auth mode (a subscription OAuth token in
  # CLAUDE_CODE_OAUTH_TOKEN) are mutually exclusive. Reproduced on CLI 2.1.224:
  # garbage OAuth + --bare => "Not logged in" (never read); without --bare => an
  # honest 401. Pin the flag out of BOTH the real argv and the dry-run preview,
  # and require the source to carry the reason so the flag cannot quietly return.
  adapter="$REPO_ROOT/tools/providers/claude-code.sh"
  run grep -cE '^[^#]*--bare' "$adapter"
  [ "$output" = "0" ]
  grep -qF 'OAuth and keychain are never read' "$adapter"
}
