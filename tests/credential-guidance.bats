#!/usr/bin/env bats
#
# Guard: a missing credential must SAY WHAT IT IS and HOW TO GET ONE.
#
# WHY THIS FILE EXISTS.
#
# "required credential $AGENT_CLI_TOKEN is not set" is true and useless. The reader is
# left to work out whether that name wants a subscription token or an API key — two
# things that are not interchangeable, come from different places, and bill differently.
# The first person to read this template asked exactly that question, which is the
# clearest possible evidence that the name alone does not carry the answer.
#
# The answer is vendor-specific, so it lives in the adapter — the one place a vendor name
# is legitimate — and is quoted at the point of failure. That keeps the runbooks
# provider-neutral (tests/harness-guards/vendor-neutrality.bats enforces that) while
# still giving the adopter a concrete command to run.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  SCRATCH="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$SCRATCH/.github"
  cp -R "$REPO_ROOT/.agents" "$SCRATCH/.agents"
  cp -R "$REPO_ROOT/tools" "$SCRATCH/tools"
  cp "$REPO_ROOT/.github/agent-temper-headless.md" "$SCRATCH/.github/"
  sed -i.bak 's/{{PROVIDER}}/claude-code/g' "$SCRATCH/.agents/config.yml"
  rm -f "$SCRATCH/.agents/config.yml.bak"
  export AGENTS_CONFIG="$SCRATCH/.agents/config.yml"
}

@test "every adapter declares exactly one auth hint" {
  # Zero means the failure message silently loses its most useful line; more than one
  # means whichever the reader happens to grep is the one they believe.
  for f in "$REPO_ROOT"/tools/providers/*.sh; do
    n="$(grep -c '^ADAPTER_AUTH_HINT=' "$f")"
    [ "$n" -eq 1 ] || { echo "$f declares $n ADAPTER_AUTH_HINT lines"; false; }
  done
}

@test "every adapter declares exactly one model hint, carrying a live-list pointer" {
  # Nobody memorises exact model ids and they churn faster than any release, so
  # the interview surfaces each adapter's hint at the moment of the question.
  # The hint must point somewhere that STAYS authoritative — a vendor models URL,
  # or (compatible-endpoint) the endpoint's own /v1/models — because the ids
  # inside the hint are dated guidance by design, never a validated enum.
  for f in "$REPO_ROOT"/tools/providers/*.sh; do
    n="$(grep -c '^ADAPTER_MODEL_HINT=' "$f")"
    [ "$n" -eq 1 ] || { echo "$f declares $n ADAPTER_MODEL_HINT lines"; false; }
    grep -E '^ADAPTER_MODEL_HINT=' "$f" | grep -qE 'https?://|/v1/models' \
      || { echo "$f model hint has no live-list pointer"; false; }
  done
}

@test "adapter_model_hint reads the hint, and is silent for a provider without one" {
  . "$REPO_ROOT/tools/lib/config.sh"
  run adapter_model_hint claude-code
  [ "$status" -eq 0 ]
  [[ "$output" == *"docs.claude.com"* ]]
  run adapter_model_hint no-such-provider
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a missing REQUIRED credential names the mode, the how-to and the destination" {
  cd "$SCRATCH"
  run env -u AGENT_CLI_TOKEN tools/run-agent.sh --check-credentials health
  [ "$status" -eq 5 ]
  [[ "$output" == *"AGENT_CLI_TOKEN"* ]]
  [[ "$output" == *"auth mode: subscription"* ]]
  [[ "$output" == *"how to obtain it:"* ]]
  [[ "$output" == *"NOT an API key"* ]]   # the exact confusion this exists to end
  [[ "$output" == *"repository secret"* ]]
}

@test "a missing OPTIONAL credential still explains itself while degrading" {
  # Degrading quietly is how an adopter concludes the second reviewer 'does not work'.
  cd "$SCRATCH"
  run env -u CHALLENGE_API_KEY AGENT_CLI_TOKEN=x tools/run-agent.sh --check-credentials challenger
  [ "$status" -eq 6 ]
  [[ "$output" == *"degrading"* ]]
  [[ "$output" == *"how to obtain it:"* ]]
  [[ "$output" == *"never fails a pull request"* ]]
}

@test "a present credential is silent about how to obtain one" {
  # The guidance belongs on the failure path only. Printing it on success trains the
  # reader to skim past it, which is where a real warning goes to die.
  cd "$SCRATCH"
  run env AGENT_CLI_TOKEN=present tools/run-agent.sh --check-credentials health
  [ "$status" -eq 0 ]
  [[ "$output" != *"how to obtain it:"* ]]
}

@test "an EVENT-DRIVEN agent can be credential-checked with its role" {
  # The steward is the agent an adopter needs AGENT_CLI_TOKEN for first, so it is the
  # one adopt.sh, status.sh and the setup docs all name. It is deliberately absent from
  # ledger.agents, which used to make this exact command die on a missing --prompt-file
  # — a prompt a credential check never opens, because it invokes nothing.
  cd "$SCRATCH"
  run env -u AGENT_CLI_TOKEN tools/run-agent.sh --check-credentials steward --role judge
  [ "$status" -eq 5 ]
  [[ "$output" == *"AGENT_CLI_TOKEN"* ]]
  [[ "$output" == *"agent 'steward', role 'judge'"* ]]
  [[ "$output" != *"prompt-file"* ]]
}

@test "an event-driven agent with no role is still refused, and says which flag is missing" {
  # Roles may map to different providers, so guessing one would answer about a
  # credential the adopter did not ask about.
  cd "$SCRATCH"
  run env -u AGENT_CLI_TOKEN tools/run-agent.sh --check-credentials steward
  [ "$status" -eq 2 ]
  [[ "$output" == *"--role"* ]]
}

@test "the guided-adoption tools invoke the credential check in a form that resolves" {
  # adopt.sh step 5 and status.sh both print this command's output to the adopter.
  # If it degrades to a usage error, the one step that explains the required secret
  # explains nothing instead.
  grep -q -- '--check-credentials steward --role judge' "$REPO_ROOT/tools/adopt.sh"
  grep -q -- '--check-credentials steward --role judge' "$REPO_ROOT/tools/status.sh"
}

@test "the hint never leaks the credential's value" {
  cd "$SCRATCH"
  run env AGENT_CLI_TOKEN="super-secret-must-not-appear" tools/run-agent.sh --check-credentials health
  [[ "$output" != *"super-secret-must-not-appear"* ]]
}
