#!/usr/bin/env bash
# shellcheck disable=SC2034  # ADAPTER_* are read from OUTSIDE this file: tools/lib/config.sh
# greps them out of the source text (adapter_status / adapter_docs_url / adapter_auth_hint)
# rather than sourcing it, precisely so reading an adapter's metadata never executes it.
# (a use that happens in another process is invisible to the linter, so it reports them unused;
# do not start this comment line with the linter's own name — that parses as a malformed
# directive and aborts analysis of the whole file.)
ADAPTER_STATUS=unverified                                   # verified | unverified — THE source of truth (design.md 3.4)
ADAPTER_DOCS_URL=https://geminicli.com/docs/cli/headless/   # confirm every flag below against this before flipping to verified
ADAPTER_AUTH_HINT='SUBSCRIPTION MODE: authenticate the CLI and store the credential it issues. Confirm the exact command at ADAPTER_DOCS_URL before relying on this — this adapter is an UNVERIFIED STUB and refuses to run.'
#
# tools/providers/gemini-cli.sh — the Gemini CLI adapter. UNVERIFIED STUB.
#
# The command shape below (`gemini -p "<prompt>" -m <model>`) is built from Gemini
# CLI's own current headless-mode documentation, but it has never been run against a
# real CLI from this repository — the evidentiary bar Task 16 sets (design.md: "flags
# verified by the source repository's own production use") is not met for this
# provider. A plausible invocation that silently does nothing is worse than an honest
# stub: this one refuses to `run` and says exactly why.
#
# To promote this adapter to ADAPTER_STATUS=verified: run it for real against a Gemini
# CLI, confirm the headless flag, the model flag, the tool-permission flag and the
# system-prompt handoff all behave as this file assumes, fix whatever is wrong, flip
# the line above, and re-run tools/init.sh so the steward and review workflows pick it
# up (Task 21's adoption interview gates on exactly this line).
set -euo pipefail
set +x   # never trace: a `set -x` here would print AGENT_AUTH_TOKEN into a public log.

CLI_BIN="${GEMINI_CLI_BIN:-gemini}"

print_argv() {
  printf '%s\n' \
    "$CLI_BIN" \
    "-p" \
    "<contents of \$AGENT_PROMPT_FILE>" \
    "-m" \
    "${AGENT_MODEL:-}"
  echo "(UNVERIFIED: tool-permission granting and the system-prompt handoff for" \
    "\$AGENT_SYSTEM_PROMPT_FILE are not yet confirmed against a real Gemini CLI" \
    "— see $ADAPTER_DOCS_URL)"
}

print_stub_banner() {
  cat >&2 <<EOF
================ UNVERIFIED STUB ================
tools/providers/gemini-cli.sh has never been executed against a real CLI.
The command shape above is a placeholder. Confirm the headless flag,
the model flag and the tool-permission flag before enabling it:
  $ADAPTER_DOCS_URL
Running this adapter for real exits 4 on purpose.
=================================================
EOF
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
    print_stub_banner
    exit 4
    ;;
  *)
    echo "gemini-cli.sh: unknown verb '$verb' (expected print-argv|run|status)" >&2
    exit 2
    ;;
esac
