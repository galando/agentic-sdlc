#!/usr/bin/env bats
#
# Guard: every credential .agents/config.yml names must actually REACH the process.
#
# WHY THIS FILE EXISTS.
#
# run-agent.sh resolves the credential by NAME, out of its own environment:
#
#     eval "AUTH_TOKEN_VALUE=\"\${${TOKEN_SECRET_NAME}:-}\""
#
# The workflows, though, forward a fixed list of names in their `env:` blocks — a
# workflow cannot read config.yml to decide what to pass. So `token_secret:` reads like a
# free knob and is not one. Point it at a name no workflow forwards and the adopter gets
# "required credential $X is not set" on a repository where they DID add secret $X, with
# nothing connecting the error to the config line that caused it.
#
# That is the worst shape a configuration bug can take: the config is right, the secret
# exists, and the failure names neither. This turns it into a red check that says which
# name is unwired, at the moment the config changes rather than on the next scheduled run.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

configured_secrets() {
  grep -oE '^[[:space:]]*token_secret:[[:space:]]*[A-Z_][A-Z0-9_]*' "$REPO_ROOT/.agents/config.yml" \
    | awk '{print $2}' | sort -u
}

forwarded_secrets() {
  grep -hoE '^[[:space:]]+[A-Z_][A-Z0-9_]*:[[:space:]]*\$\{\{[[:space:]]*secrets\.' \
    "$REPO_ROOT"/.github/workflows/*.yml \
    | sed -E 's/^[[:space:]]+([A-Z_0-9]+):.*/\1/' | sort -u
}

@test "config.yml names at least one credential, and the parser finds it" {
  # A silent empty list would make every assertion below vacuously true.
  run configured_secrets
  [ -n "$output" ]
  [[ "$output" == *"AGENT_CLI_TOKEN"* ]]
}

@test "every token_secret in config.yml is forwarded by some workflow" {
  missing=""
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    forwarded_secrets | grep -qx "$s" || missing="$missing $s"
  done < <(configured_secrets)
  [ -z "$missing" ] || {
    echo "token_secret name(s) no workflow forwards:$missing"
    echo "Add them to the env: block of every step that runs tools/run-agent.sh,"
    echo "or point token_secret at a name that is already forwarded."
    false
  }
}

@test "the challenge role's credential reaches the challenge reviewer specifically" {
  # Forwarding it SOMEWHERE is not enough. Reviewer B is the whole adversarial second
  # opinion; if its key is only forwarded to the judge's step it degrades on every run
  # and the referee compares one review against nothing, while the config looks correct.
  challenge_secret="$(grep -A4 '^  compatible-endpoint:' "$REPO_ROOT/.agents/config.yml" \
    | grep -oE 'token_secret:[[:space:]]*[A-Z_]+' | awk '{print $2}')"
  [ -n "$challenge_secret" ]
  run bash -c "grep -B12 'role challenge' '$REPO_ROOT/.github/workflows/review.yml' | grep -c '$challenge_secret'"
  [ "$output" -ge 1 ]
}

@test "the judge role's credential reaches the judge and referee steps" {
  judge_secret="$(grep -A4 '^  claude-code:' "$REPO_ROOT/.agents/config.yml" \
    | grep -oE 'token_secret:[[:space:]]*[A-Z_]+' | awk '{print $2}')"
  [ -n "$judge_secret" ]
  for call in "role judge"; do
    run bash -c "grep -B12 '$call' '$REPO_ROOT/.github/workflows/review.yml' | grep -c '$judge_secret'"
    [ "$output" -ge 1 ]
  done
}

@test "a credential is never passed as a command-line argument" {
  # argv is visible in a process listing and in any step that echoes its own command.
  # Both adapters document env-var auth for exactly this reason.
  run grep -rnE -- '--(api-key|token|auth-token)[= ]' "$REPO_ROOT"/.github/workflows/ "$REPO_ROOT"/tools/providers/
  [ "$status" -ne 0 ]
}
