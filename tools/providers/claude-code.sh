#!/usr/bin/env bash
# shellcheck disable=SC2034  # ADAPTER_* are read from OUTSIDE this file: tools/lib/config.sh
# greps them out of the source text (adapter_status / adapter_docs_url / adapter_auth_hint)
# rather than sourcing it, precisely so reading an adapter's metadata never executes it.
# (a use that happens in another process is invisible to the linter, so it reports them unused;
# do not start this comment line with the linter's own name — that parses as a malformed
# directive and aborts analysis of the whole file.)
ADAPTER_STATUS=verified                                        # verified | unverified — THE source of truth (design.md 3.4)
ADAPTER_DOCS_URL=https://code.claude.com/docs/en/headless       # confirm flags here before changing this file
ADAPTER_AUTH_HINT='SUBSCRIPTION MODE (the default): run `claude setup-token` on a machine already signed in to a Pro or Max plan, and paste the OAuth token it prints. This is NOT an API key, it is not billed per token, and it is not the key from the developer console. API-KEY MODE: use a console API key instead, and set auth.claude-code.mode to api-key.'
#
# tools/providers/claude-code.sh — the Claude Code CLI adapter.
#
# Owns the four things an adapter owns (design.md section 3): the headless flag (`-p`
# with `--bare`, so a scheduled run gets the same result on every machine and never
# picks up a stray hook or MCP server from the runner image), model selection
# (`--model`), tool-permission granting (`--allowedTools`, fed from
# AGENT_ALLOWED_TOOLS) and the working-tree handover (`cd "$AGENT_WORKDIR"` before
# anything runs).
#
# Verified by the source repository's own production use — see
# .temper/specs/agent-sdlc-template/design.md section on Task 16's evidentiary
# standard. `--model`, `-p`/`--print`, `--bare`, `--allowedTools` and
# `--append-system-prompt-file` are confirmed current at the docs URL above;
# `CLAUDE_CODE_OAUTH_TOKEN` (subscription) and `ANTHROPIC_API_KEY` (api-key) are the
# two auth env vars Claude Code itself documents for non-interactive auth.
set -euo pipefail
set +x   # never trace: a `set -x` here would print AGENT_AUTH_TOKEN into a public log.

CLI_BIN="${CLAUDE_CODE_BIN:-claude}"

# print-argv shows the real argv shape, one token per line, but substitutes a
# placeholder for the prompt file's CONTENTS rather than inlining the whole prompt —
# the contract only requires substituting the AUTH TOKEN (design.md 3.3); this is an
# adapter-level choice so a multi-hundred-line prompt does not flood a dry-run log.
# The real invocation (the `run` verb) does read the file for real.
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
  # Auth is never a CLI argument for this CLI — it reads an env var
  # (CLAUDE_CODE_OAUTH_TOKEN for subscription, ANTHROPIC_API_KEY for api-key), set by
  # the `run` verb below and never printed. There is no argv position for
  # $AGENT_AUTH_TOKEN to appear in, so there is nothing to redact here (design.md 3.3's
  # "substitute the literal token reference" applies only when a flag would otherwise
  # carry the value; this adapter's auth model has no such flag).
  echo "(auth: \$AGENT_AUTH_TOKEN -> \$CLAUDE_CODE_OAUTH_TOKEN or \$ANTHROPIC_API_KEY env var, never a flag)"
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
    [ -n "${AGENT_WORKDIR:-}" ] || { echo "claude-code.sh: AGENT_WORKDIR is not set" >&2; exit 3; }
    [ -d "$AGENT_WORKDIR" ] || { echo "claude-code.sh: AGENT_WORKDIR does not exist: $AGENT_WORKDIR" >&2; exit 3; }
    [ -f "${AGENT_PROMPT_FILE:-}" ] || { echo "claude-code.sh: AGENT_PROMPT_FILE not found: ${AGENT_PROMPT_FILE:-}" >&2; exit 3; }
    cd "$AGENT_WORKDIR"

    case "${AGENT_AUTH_MODE:-}" in
      subscription) export CLAUDE_CODE_OAUTH_TOKEN="${AGENT_AUTH_TOKEN:-}" ;;
      api-key)      export ANTHROPIC_API_KEY="${AGENT_AUTH_TOKEN:-}" ;;
      *) echo "claude-code.sh: unknown AGENT_AUTH_MODE '${AGENT_AUTH_MODE:-}'" >&2; exit 3 ;;
    esac

    prompt_text="$(cat "$AGENT_PROMPT_FILE")"
    exec timeout "${AGENT_TIMEOUT_SECONDS:-600}" "$CLI_BIN" \
      --bare \
      -p "$prompt_text" \
      --model "$AGENT_MODEL" \
      --allowedTools "$AGENT_ALLOWED_TOOLS" \
      --append-system-prompt-file "$AGENT_SYSTEM_PROMPT_FILE" \
      --permission-mode acceptEdits
    ;;
  *)
    echo "claude-code.sh: unknown verb '$verb' (expected print-argv|run|status)" >&2
    exit 2
    ;;
esac
