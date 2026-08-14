#!/usr/bin/env bash
# tools/run-agent.sh — the ONE place a workflow reaches to run an agent.
#
# Resolves role -> model -> prompt -> adapter from .agents/config.yml (via
# tools/lib/config.sh, the only parser) and hands off to exactly one
# tools/providers/<name>.sh invocation. See design.md section 3 for the full
# run-agent.sh <-> adapter contract this file implements: the env-var contract (3.2),
# the adapter verbs (3.3), ADAPTER_STATUS (3.4), exit codes (3.5) and --dry-run (3.6).
#
# An adapter must never read config.yml itself — one parser, one place a schema change
# lands (Decision D5).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ONE answer to "where is the repo". ROOT comes from this script's own location and is
# what resolves the prompt, the adapter and the work tree; config.sh, left to itself,
# would answer `git rev-parse --show-toplevel` instead. Those agree only when the caller
# happens to stand in the directory holding tools/. Where they diverge — a vendored copy
# nested in another git-controlled repo, a worktree, a submodule — the script would run
# THIS copy's adapter against the OUTER repo's config, and the argv it printed would name
# a provider nobody configured here. Pinning AGENTS_CONFIG to ROOT closes that.
#
# AGENTS_ROOT, not AGENTS_CONFIG, because config.yml is not the only path derived from
# the root: floors.yml and tools/providers/*.sh are too, and pinning only the config
# leaves the adapter lookup still answering the other question.
#
# Explicit AGENTS_CONFIG / FLOORS_CONFIG still win over this: that is how CI and the test
# suite point the reader at a scratch config, and single-sourcing the root must not take
# it away.
export AGENTS_ROOT="$ROOT"

# shellcheck source=lib/config.sh
. "$ROOT/tools/lib/config.sh"

CONFIG_FILE="$(_cfg_file)"
SCHEMA_SUPPORTED=1

usage() {
  cat >&2 <<'EOF'
usage: tools/run-agent.sh <agent> [--role judge|execute|challenge] [--dry-run]
                           [--prompt-file PATH] [--timeout SECONDS]
       tools/run-agent.sh --check-credentials <agent>
       tools/run-agent.sh --adapter-status <provider>
       tools/run-agent.sh --list-agents
EOF
}

die_usage() {
  echo "run-agent.sh: $*" >&2
  usage
  exit 2
}

die_config() {
  echo "run-agent.sh: $*" >&2
  exit 3
}

[ -f "$CONFIG_FILE" ] || die_config "config not found: $CONFIG_FILE"

# --- top-level, config-only invocations that need no agent -----------------
case "${1:-}" in
  --list-agents)
    cfg_assert_schema "$CONFIG_FILE" "$SCHEMA_SUPPORTED" || exit 3
    cfg_agents
    exit 0
    ;;
  --adapter-status)
    provider="${2:-}"
    [ -n "$provider" ] || die_usage "missing provider name for --adapter-status"
    adapter_status "$provider"
    exit $?
    ;;
  -h|--help)
    usage
    exit 0
    ;;
esac

CHECK_CREDS_ONLY=0
if [ "${1:-}" = "--check-credentials" ]; then
  CHECK_CREDS_ONLY=1
  shift
fi

AGENT="${1:-}"
[ -n "$AGENT" ] || die_usage "missing <agent>"
shift || true

ROLE_OVERRIDE=""
DRY_RUN=0
PROMPT_FILE_OVERRIDE=""
TIMEOUT_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --role)
      ROLE_OVERRIDE="${2:-}"
      [ -n "$ROLE_OVERRIDE" ] || die_usage "--role needs a value"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --prompt-file)
      PROMPT_FILE_OVERRIDE="${2:-}"
      [ -n "$PROMPT_FILE_OVERRIDE" ] || die_usage "--prompt-file needs a value"
      shift 2
      ;;
    --timeout)
      TIMEOUT_OVERRIDE="${2:-}"
      [ -n "$TIMEOUT_OVERRIDE" ] || die_usage "--timeout needs a value"
      shift 2
      ;;
    *)
      die_usage "unknown flag '$1'"
      ;;
  esac
done

cfg_assert_schema "$CONFIG_FILE" "$SCHEMA_SUPPORTED" || exit 3

# --- resolve agent -> role -> provider -> model -> prompt -------------------
# `ledger.agents` is the scheduled ring (health, quality, audit, chief-of-staff,
# challenger). The event-driven agents — steward, reviewer, referee, invoked from
# steward.yml / review.yml — are deliberately NOT in that list (agent-routines.md:
# "Neither is a routine and neither appears in ledger.agents or in the watcher ring"),
# so they must pass --role and --prompt-file explicitly; nothing is looked up for them.
KNOWN_AGENTS="$(cfg_agents)" || die_config "cannot resolve ledger.agents from $CONFIG_FILE"
known=0
for a in $KNOWN_AGENTS; do
  [ "$a" = "$AGENT" ] && known=1
done

if [ "$known" -eq 1 ]; then
  ROLE="$ROLE_OVERRIDE"
  if [ -z "$ROLE" ]; then
    ROLE="$(cfg_agent_field "$AGENT" role)" || die_config "no role configured for agent '$AGENT'"
  fi
else
  [ -n "$ROLE_OVERRIDE" ] || die_usage "unknown agent '$AGENT' (expected one of: $(printf '%s' "$KNOWN_AGENTS" | tr '\n' ' ')) — an event-driven agent needs --role explicitly"
  ROLE="$ROLE_OVERRIDE"
fi
case "$ROLE" in
  judge|execute|challenge) ;;
  *) die_usage "invalid role '$ROLE' (expected judge, execute or challenge)" ;;
esac

PROVIDER="$(cfg_get "role_provider.${ROLE}")" || die_config "no role_provider.${ROLE} configured"
MODEL="$(cfg_get "models.${ROLE}")" || die_config "no models.${ROLE} configured"

PROMPT_FILE="$PROMPT_FILE_OVERRIDE"
if [ -z "$PROMPT_FILE" ]; then
  if [ "$known" -eq 1 ]; then
    PROMPT_FILE="$(cfg_agent_field "$AGENT" prompt)" || die_config "no prompt configured for agent '$AGENT'"
  elif [ "$CHECK_CREDS_ONLY" -eq 1 ]; then
    # A credential check invokes nothing, so it needs no prompt. Demanding one
    # here made `--check-credentials steward --role judge` impossible — and the
    # steward is precisely the agent an adopter needs the credential for FIRST,
    # which is why adopt.sh, status.sh and the setup docs all name it.
    :
  else
    die_usage "unknown agent '$AGENT' needs --prompt-file explicitly"
  fi
fi
if [ -n "$PROMPT_FILE" ]; then
  case "$PROMPT_FILE" in
    /*) : ;;
    *) PROMPT_FILE="$ROOT/$PROMPT_FILE" ;;
  esac
  [ -f "$PROMPT_FILE" ] || die_usage "prompt file not found: $PROMPT_FILE"
fi

SYSTEM_PROMPT_FILE="$ROOT/.github/agent-temper-headless.md"
[ -f "$SYSTEM_PROMPT_FILE" ] || die_config "system prompt file missing: $SYSTEM_PROMPT_FILE"

# Fleet mode (config.yml `mode:`). In observe, the report-only sheet is APPENDED
# to the system prompt here — one implementation for every provider, so no
# adapter can forget it. The prompt is the instruction; the workflow permission
# split in agents-scheduled.yml / steward.yml is the enforcement. Composed into
# a temp file because the shipped system prompt must never be edited in place.
FLEET_MODE="$(cfg_get mode active)"
case "$FLEET_MODE" in
  active) : ;;
  observe)
    OBSERVE_FILE="$ROOT/.agents/observe.md"
    [ -f "$OBSERVE_FILE" ] || die_config "mode: observe is set but $OBSERVE_FILE is missing"
    # The leak is deliberate: adapters hand off via `exec`, so an EXIT trap
    # here would delete the file before (or without) the CLI ever reading it.
    # A named template keeps the leaked files attributable in $TMPDIR, and the
    # dry-run test reads the file after this process exits.
    COMPOSED_PROMPT="$(mktemp "${TMPDIR:-/tmp}/agent-observe-prompt.XXXXXX")"
    cat "$SYSTEM_PROMPT_FILE" "$OBSERVE_FILE" > "$COMPOSED_PROMPT"
    SYSTEM_PROMPT_FILE="$COMPOSED_PROMPT"
    ;;
  *) die_config "mode must be 'active' or 'observe', not '$FLEET_MODE'" ;;
esac
export AGENT_FLEET_MODE="$FLEET_MODE"

TIMEOUT="${TIMEOUT_OVERRIDE:-600}"

ADAPTER_FILE="$ROOT/tools/providers/${PROVIDER}.sh"
[ -f "$ADAPTER_FILE" ] || die_config "unknown provider '$PROVIDER' (no $ADAPTER_FILE)"
[ -x "$ADAPTER_FILE" ] || die_config "adapter not executable: $ADAPTER_FILE"

STATUS="$(adapter_status "$PROVIDER")" || exit 3

# --- resolve auth (best-effort; enforcement is deferred below by mode) -----
AUTH_MODE="$(cfg_get "auth.${PROVIDER}.mode")" || die_config "no auth.${PROVIDER}.mode configured"
AUTH_REQUIRED_RAW="$(cfg_get "auth.${PROVIDER}.required" "false")"
case "$AUTH_REQUIRED_RAW" in
  true) AUTH_REQUIRED=1 ;;
  *) AUTH_REQUIRED=0 ;;
esac
TOKEN_SECRET_NAME="$(cfg_get "auth.${PROVIDER}.token_secret" "")"
BASE_URL="$(cfg_get "auth.${PROVIDER}.base_url" "")"

AUTH_TOKEN_VALUE=""
if [ -n "$TOKEN_SECRET_NAME" ]; then
  # Bash indirection, never eval: token_secret comes from the config file, and
  # eval on it was a shell-injection surface at workflow runtime. The name is
  # validated first so indirection cannot blow up on a malformed value either.
  case "$TOKEN_SECRET_NAME" in
    *[!A-Za-z0-9_]*|[0-9]*)
      echo "run-agent.sh: auth.${PROVIDER}.token_secret '$TOKEN_SECRET_NAME' is not a valid environment variable name" >&2
      exit 3
      ;;
  esac
  AUTH_TOKEN_VALUE="${!TOKEN_SECRET_NAME:-}"
fi

ALLOWED_TOOLS="${AGENT_ALLOWED_TOOLS_DEFAULT:-Read,Edit,Write,Bash,Grep,Glob}"

export AGENT_NAME="$AGENT"
export AGENT_ROLE="$ROLE"
export AGENT_MODEL="$MODEL"
export AGENT_PROMPT_FILE="$PROMPT_FILE"
export AGENT_SYSTEM_PROMPT_FILE="$SYSTEM_PROMPT_FILE"
export AGENT_WORKDIR="$ROOT"
export AGENT_AUTH_MODE="$AUTH_MODE"
export AGENT_AUTH_TOKEN="$AUTH_TOKEN_VALUE"
export AGENT_AUTH_REQUIRED="$AUTH_REQUIRED"
export AGENT_BASE_URL="$BASE_URL"
export AGENT_ALLOWED_TOOLS="$ALLOWED_TOOLS"
export AGENT_TIMEOUT_SECONDS="$TIMEOUT"
export AGENT_DRY_RUN="$DRY_RUN"
export SPEC_PIPELINE_DIR="tools/spec-pipeline"
# claude-code probes for the build plugin and may report "plugin"; every other adapter
# reports "fallback" unconditionally until a maintainer verifies otherwise (design.md
# section 8.4). Both paths satisfy gate 21 because the contract is the ARTIFACTS.
export SPEC_PIPELINE="fallback"

print_dry_run_header() {
  echo "provider: $PROVIDER"
  echo "adapter-status: $STATUS"
  echo "role: $ROLE"
  echo "model: $MODEL"
  echo "prompt: $PROMPT_FILE"
  echo "system-prompt: $SYSTEM_PROMPT_FILE"
  # Only in observe: the six-line header is a stable contract (run-agent-dryrun.bats),
  # and active mode is the state every existing consumer knows.
  if [ "$FLEET_MODE" = "observe" ]; then
    echo "fleet-mode: observe (report-only sheet .agents/observe.md appended to the system prompt)"
  fi
}

print_unverified_banner() {
  local docs_url
  docs_url="$(adapter_docs_url "$PROVIDER")"
  cat <<EOF

================ UNVERIFIED STUB ================
tools/providers/${PROVIDER}.sh has never been executed against a real CLI.
The command shape above is a placeholder. Confirm the headless flag,
the model flag and the tool-permission flag before enabling it:
  $docs_url
Running this adapter for real exits 4 on purpose.
=================================================
EOF
}

if [ "$DRY_RUN" -eq 1 ]; then
  # A real smoke test (design.md 3.6): every resolution error above still exits 2 or 3.
  # From here on this must succeed with NO agent CLI on PATH and NO credential set.
  print_dry_run_header
  echo
  argv="$("$ADAPTER_FILE" print-argv)"
  printf '%s\n' "$argv"
  echo
  quoted=""
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    printf -v q '%q' "$tok"
    quoted="$quoted $q"
  done <<<"$argv"
  echo "${quoted# }"
  if [ "$STATUS" = "unverified" ]; then
    print_unverified_banner
  fi
  exit 0
fi

# An unverified stub refuses to run for real before anything else — including before
# credential resolution, since its flags have never been confirmed against a live CLI.
if [ "$CHECK_CREDS_ONLY" -eq 0 ] && [ "$STATUS" = "unverified" ]; then
  print_unverified_banner >&2
  exit 4
fi

if [ -z "$AUTH_TOKEN_VALUE" ]; then
  # Say what the credential IS and how to get one. "Required credential X is not set" is
  # true and useless: the reader still has to work out whether X is a subscription token
  # or an API key, and where either comes from. That answer is vendor-specific, so it is
  # quoted from the adapter rather than duplicated into a provider-neutral runbook.
  AUTH_HINT="$(adapter_auth_hint "$PROVIDER" 2>/dev/null || true)"
  AUTH_DOCS="$(adapter_docs_url "$PROVIDER" 2>/dev/null || true)"
  if [ "$AUTH_REQUIRED" -eq 1 ]; then
    echo "run-agent.sh: required credential \$${TOKEN_SECRET_NAME} is not set for provider '$PROVIDER' (agent '$AGENT', role '$ROLE')" >&2
    echo "  auth mode: ${AUTH_MODE}" >&2
    [ -n "$AUTH_HINT" ] && echo "  how to obtain it: $AUTH_HINT" >&2
    [ -n "$AUTH_DOCS" ] && echo "  provider docs: $AUTH_DOCS" >&2
    echo "  then add it as repository secret \$${TOKEN_SECRET_NAME} (Settings > Secrets and variables > Actions)." >&2
    exit 5
  fi
  echo "::warning::run-agent.sh: optional credential \$${TOKEN_SECRET_NAME} is not set for provider '$PROVIDER' (agent '$AGENT', role '$ROLE') — degrading, this run is skipped" >&2
  [ -n "$AUTH_HINT" ] && echo "  how to obtain it: $AUTH_HINT" >&2
  exit 6
fi

if [ "$CHECK_CREDS_ONLY" -eq 1 ]; then
  exit 0
fi

# Unset any inherited vendor credential before exec: if the original credential survives
# into the subprocess it wins, and the "different family" second opinion is silently the
# same model (the compatible-endpoint lesson, generalised — design.md section 3.2).
# Both patterns are anchored on the NAME (up to the first `=`): an unanchored
# /_API_KEY=/ also matched the substring inside a VALUE, unsetting unrelated vars.
for var in $(env | LC_ALL=C awk -F= '/^(ANTHROPIC_|OPENAI_|GEMINI_)[A-Za-z0-9_]*=/ || /^[A-Za-z0-9_]*_API_KEY=/{print $1}'); do
  unset "$var" 2>/dev/null || true
done

exec "$ADAPTER_FILE" run
