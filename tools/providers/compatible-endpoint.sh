#!/usr/bin/env bash
# shellcheck disable=SC2034  # ADAPTER_* are read from OUTSIDE this file: tools/lib/config.sh
# greps them out of the source text (adapter_status / adapter_docs_url / adapter_auth_hint)
# rather than sourcing it, precisely so reading an adapter's metadata never executes it.
# (a use that happens in another process is invisible to the linter, so it reports them unused;
# do not start this comment line with the linter's own name — that parses as a malformed
# directive and aborts analysis of the whole file.)
ADAPTER_STATUS=verified                                        # verified | unverified — THE source of truth (design.md 3.4)
ADAPTER_DOCS_URL=https://code.claude.com/docs/en/headless       # confirm flags here before changing this file
ADAPTER_AUTH_HINT='API-KEY MODE (always): an API key issued by whichever backend auth.compatible-endpoint.base_url points at. This is the one place a per-token key is genuinely required, because no subscription covers a second model family. OPTIONAL BY DESIGN: without it the adversarial second opinion degrades to a single reviewer and says so — it never fails a pull request.'
ADAPTER_MODEL_HINT='whatever model ids the endpoint at base_url serves — its own GET /v1/models is the authoritative list, not any document. The endpoint must be ANTHROPIC-WIRE-COMPATIBLE: this adapter repoints the same CLI binary via ANTHROPIC_BASE_URL, so the backend has to speak the Anthropic Messages protocol (/v1/messages), NOT the OpenAI chat-completions one. z.ai serves one at its /api/anthropic path; a LiteLLM or similar internal gateway can expose an Anthropic-format route in front of other model families (DeepSeek, Moonshot/Kimi, Mistral, a local vLLM); an OpenAI-format-only endpoint will not work here. Pick a DIFFERENT family than your primary provider — a second draw from the same distribution shares the same blind spots.'
#
# tools/providers/compatible-endpoint.sh — the "different model family" adapter.
#
# This is the ONLY delivery path for the `challenge` role (design.md, Task 16 notes):
# reviewer B in .github/workflows/review.yml and the `challenger` scheduled agent both
# resolve to this adapter via role_provider.challenge. Its mechanic — override the base
# URL and the auth token in a subprocess with the ORIGINAL credentials unset — is
# extracted from docs/runbooks/multi-model-review.md and the source's own review
# workflow, where it is how the second reviewer actually runs. Same evidentiary
# standard as claude-code.sh: verified by production use, not by count.
#
# Reuses the same CLI binary as claude-code.sh (an Anthropic-compatible endpoint speaks
# the same protocol — that is what "compatible" means here), pointed at a different
# backend via ANTHROPIC_BASE_URL / ANTHROPIC_API_KEY. This is the generalised form of
# the lesson in run-agent.sh: if the parent session's own credential survives into this
# subprocess it wins, and the "different family" second opinion is silently the same
# model — the check appears to run and proves nothing.
set -euo pipefail
set +x   # never trace: a `set -x` here would print AGENT_AUTH_TOKEN into a public log.

CLI_BIN="${CLAUDE_CODE_BIN:-claude}"

print_argv() {
  printf '%s\n' \
    "$CLI_BIN" \
    "--bare" \
    "-p" \
    "<contents of \$AGENT_PROMPT_FILE>" \
    "--model" \
    "${AGENT_MODEL:-}" \
    "--allowedTools" \
    "${AGENT_ALLOWED_TOOLS:-}" \
    "--append-system-prompt-file" \
    "${AGENT_SYSTEM_PROMPT_FILE:-}" \
    "--permission-mode" \
    "acceptEdits"
  echo "(base URL and auth overridden via ANTHROPIC_BASE_URL / ANTHROPIC_API_KEY," \
    "in a fresh HOME so the subprocess cannot touch the parent session's own config;" \
    "proxy/CA variables — HTTP(S)_PROXY, NO_PROXY, SSL_CERT_*, NODE_EXTRA_CA_CERTS," \
    "AWS_CA_BUNDLE — pass through by name so the call can cross a corporate egress proxy)"
  # No argv position ever carries $AGENT_AUTH_TOKEN's value — see claude-code.sh's
  # print_argv for why (env-var auth, not a flag). Nothing to redact here.
  echo "(auth: \$AGENT_AUTH_TOKEN -> \$ANTHROPIC_API_KEY env var, never a flag)"
}

verb="${1:-}"
case "$verb" in
  status)
    echo "$ADAPTER_STATUS"
    ;;
  print-argv)
    print_argv
    ;;
  run)
    [ -n "${AGENT_WORKDIR:-}" ] || { echo "compatible-endpoint.sh: AGENT_WORKDIR is not set" >&2; exit 3; }
    [ -d "$AGENT_WORKDIR" ] || { echo "compatible-endpoint.sh: AGENT_WORKDIR does not exist: $AGENT_WORKDIR" >&2; exit 3; }
    [ -f "${AGENT_PROMPT_FILE:-}" ] || { echo "compatible-endpoint.sh: AGENT_PROMPT_FILE not found: ${AGENT_PROMPT_FILE:-}" >&2; exit 3; }
    [ -n "${AGENT_BASE_URL:-}" ] || { echo "compatible-endpoint.sh: AGENT_BASE_URL is empty — auth.compatible-endpoint.base_url is misconfigured" >&2; exit 3; }
    cd "$AGENT_WORKDIR"

    # A separate config directory (via HOME), so the subprocess cannot write over the
    # parent session's own state — multi-model-review.md lesson 2.
    alt_home="$(mktemp -d)"
    trap 'rm -rf "$alt_home"' EXIT

    # Seed workspace trust in that FRESH directory, or the CLI prints "this workspace
    # has not been trusted" and ignores every entry in the repo's permission
    # allowlist — multi-model-review.md lesson 3. This is why the fix is a seeded trust
    # record, never a blanket "skip all permissions" flag: this subprocess is handed an
    # untrusted second opinion, and the allowlist (--allowedTools) is the only thing
    # bounding it.
    printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}\n' "$AGENT_WORKDIR" \
      > "$alt_home/.claude.json"

    prompt_text="$(cat "$AGENT_PROMPT_FILE")"

    # Unset EVERY inherited provider credential explicitly — multi-model-review.md
    # lesson 1 — by wiping the environment entirely and re-adding only what this
    # subprocess needs. `env -i` is the strongest form of that: nothing survives that
    # was not just named on the line below.
    #
    # Network-path and trust-anchor variables are re-added BY NAME, never by glob, so
    # the invariant stays literally true. They are credential-inert: a proxy or a CA
    # bundle selects HOW the request travels and which TLS interception to trust — it
    # cannot re-select the backend or the credential, because ANTHROPIC_BASE_URL and
    # ANTHROPIC_API_KEY are still set explicitly after the wipe. Without this, a
    # corporate egress proxy kills ONLY the challenge role (claude-code.sh inherits
    # the full environment), and because this credential is optional the failure
    # degrades to "one opinion" on every run — the adversarial half of the review
    # silently off in exactly the environment that most needs it.
    passthrough=()
    for v in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy \
             SSL_CERT_FILE SSL_CERT_DIR NODE_EXTRA_CA_CERTS AWS_CA_BUNDLE; do
      if [ -n "${!v:-}" ]; then passthrough+=("$v=${!v}"); fi
    done
    exec env -i \
      HOME="$alt_home" \
      PATH="$PATH" \
      ${passthrough[@]+"${passthrough[@]}"} \
      ANTHROPIC_BASE_URL="$AGENT_BASE_URL" \
      ANTHROPIC_API_KEY="${AGENT_AUTH_TOKEN:-}" \
      timeout "${AGENT_TIMEOUT_SECONDS:-600}" "$CLI_BIN" \
        --bare \
        -p "$prompt_text" \
        --model "$AGENT_MODEL" \
        --allowedTools "$AGENT_ALLOWED_TOOLS" \
        --append-system-prompt-file "$AGENT_SYSTEM_PROMPT_FILE" \
        --permission-mode acceptEdits
    ;;
  *)
    echo "compatible-endpoint.sh: unknown verb '$verb' (expected print-argv|run|status)" >&2
    exit 2
    ;;
esac
