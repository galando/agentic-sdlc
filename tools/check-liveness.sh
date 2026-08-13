#!/usr/bin/env bash
# tools/check-liveness.sh — the mechanical half of the watcher-ring liveness rule.
#
# docs/runbooks/agent-routines.md "Liveness on a best-effort scheduler" and
# .agents/prompts/health.md steps 1-2 describe two checks an agent performs: compare its
# predecessor's newest ledger entry against `liveness.max-age-hours`, and compare the
# newest entry across ALL agents against `liveness.staleness-hours`. Both are pure
# arithmetic — "how many hours old is the newest entry" — not agent judgment, so this
# script does the arithmetic instead of leaving it to be re-derived in prose on every
# run, and it is what tests/agent-liveness.bats drives end to end against a real ledger.
#
# AGE SOURCE: the ledger entry's own `date` field is validated to day granularity only
# (ledger.sh: `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`, because it is interpolated into a narrative
# file path) and cannot distinguish a run 3 hours late from one 30 hours late. The commit
# that appended the entry can: every `ledger.sh append` is its own commit on the ledger
# branch, so the commit's timestamp IS the moment the entry became visible. That is the
# same signal this repository already treats as authoritative elsewhere (git history, not
# a field inside the payload — see tools/check-deidentified.sh's commit-message sweep).
#
# Escalate on that AGE, never on a count of consecutive misses (docs/runbooks/
# agent-routines.md) — this script has no notion of "misses" at all, only of the newest
# commit's age, which is what makes ordinary scheduler drift a non-event by construction.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/config.sh
. "$ROOT/tools/lib/config.sh"

BRANCH="${LEDGER_BRANCH:-$(cfg_get ledger.branch agent-ledger)}"

die() { echo "check-liveness.sh: $*" >&2; exit 3; }

# _entry_age_hours <agent> — hours since the newest commit that touched
# ledger/<agent>.jsonl on origin/$BRANCH. Prints a non-negative integer (floored) on
# stdout and exits 0; exits 1 with nothing printed if the agent has never written.
_entry_age_hours() {
  local agent="$1" ts now
  ts="$(git log -1 --format=%ct "origin/${BRANCH}" -- "ledger/${agent}.jsonl" 2>/dev/null)"
  [ -n "$ts" ] || return 1
  now="$(date -u +%s)"
  echo $(( (now - ts) / 3600 ))
}

cmd_predecessor() {
  local agent="${1:-}" pred max_age age rc
  [ -n "$agent" ] || die "usage: check-liveness.sh predecessor <agent>"
  pred="$(cfg_predecessor "$agent")" || {
    rc=$?
    if [ "$rc" -eq 4 ]; then
      # Exactly one agent is enabled: the ring has a single live member and no
      # predecessor whose silence would mean anything. Say so and stay green —
      # the honest report is "checked nothing to check", never a manufactured
      # escalation against an agent that is switched off by design. Total
      # silence is still covered: that is cmd_staleness's job, not this one's.
      echo "ok: no other enabled agent in the ring — nothing to watch (the staleness check still covers total silence)"
      return 0
    fi
    die "cannot resolve $agent's predecessor"
  }
  max_age="$(cfg_agent_field "$pred" max-age-hours 2>/dev/null || true)"
  if [ -z "$max_age" ]; then
    # `|| die`, not a bare assignment: this file runs without -e, so a missing
    # config key would leave the threshold empty, every numeric comparison below
    # would silently evaluate false, and the check would report "ok" — a liveness
    # gate turned green by the very misconfiguration it exists to catch.
    max_age="$(cfg_get liveness.max-age-hours)" || die "liveness.max-age-hours is missing from .agents/config.yml — refusing to answer 'ok' with no threshold"
  fi

  git fetch -q origin "$BRANCH" 2>/dev/null || true
  if ! age="$(_entry_age_hours "$pred")"; then
    echo "escalate: $pred has never written a ledger entry"
    return 1
  fi
  if [ "$age" -gt "$max_age" ]; then
    echo "escalate: $pred's newest entry is ${age}h old, over liveness.max-age-hours (${max_age}h)"
    return 1
  fi
  echo "ok: $pred's newest entry is ${age}h old, within liveness.max-age-hours (${max_age}h)"
  return 0
}

cmd_staleness() {
  local staleness newest="" agent age
  # Same rule as cmd_predecessor: a missing threshold must fail, never report ok.
  staleness="$(cfg_get liveness.staleness-hours)" || die "liveness.staleness-hours is missing from .agents/config.yml — refusing to answer 'ok' with no threshold"

  git fetch -q origin "$BRANCH" 2>/dev/null || true
  while IFS= read -r agent; do
    [ -n "$agent" ] || continue
    if age="$(_entry_age_hours "$agent")"; then
      if [ -z "$newest" ] || [ "$age" -lt "$newest" ]; then newest="$age"; fi
    fi
  done < <(cfg_agents)

  if [ -z "$newest" ]; then
    echo "S2: never written — no agent in the ring has ever written a ledger entry"
    return 2
  fi
  if [ "$newest" -gt "$staleness" ]; then
    echo "S2: the freshest entry across all agents is ${newest}h old, over liveness.staleness-hours (${staleness}h) — the whole ring may have stopped"
    return 2
  fi
  echo "ok: the freshest entry across all agents is ${newest}h old, within liveness.staleness-hours (${staleness}h)"
  return 0
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    predecessor) cmd_predecessor "$@" ;;
    staleness)   cmd_staleness "$@" ;;
    *)
      cat >&2 <<'EOF'
usage:
  check-liveness.sh predecessor <agent>   escalate (exit 1) if <agent>'s predecessor in
                                           the ring is older than liveness.max-age-hours
                                           (or its own max-age-hours override)
  check-liveness.sh staleness             S2 (exit 2) if the freshest entry across every
                                           configured agent is older than
                                           liveness.staleness-hours

See docs/runbooks/agent-routines.md "Liveness on a best-effort scheduler".
EOF
      exit 3
      ;;
  esac
}

main "$@"
