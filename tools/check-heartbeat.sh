#!/usr/bin/env bash
# tools/check-heartbeat.sh — is every ENABLED scheduled agent still writing its ledger?
#
# The watcher ring (tools/check-liveness.sh, run by the agents themselves) cannot
# notice the one failure that stops every agent at once: a dead scheduler, a runner
# label that points at nothing, a provider refusing every run, the fleet's own model
# budget spent. Upstream, the scheduler stopped and five agents missed ten runs before
# anyone was told, because the only check was inside the fleet. This script runs from
# OUTSIDE it — .github/workflows/fleet-heartbeat.yml, on a hosted runner — and reads
# two things that exist whether or not any agent is alive: each agent's `schedule:` in
# .agents/config.yml, and the newest `date` in ledger/<agent>.jsonl.
#
# Writes nothing anywhere. Reads the config through tools/lib/config.sh, never a copy.
#
#   check (default)  the decision: which enabled agents are overdue.
#   list             prints "<agent>\t<cron>\t<enabled>" per configured agent.
#
# Exit codes answer ONE question — did the watch work?
#   0  it worked. Findings (possibly none) are on stdout and in $REPORT_FILE, one
#      line per overdue agent. "No enabled agent" is also 0, and says so.
#   2  the watch itself is broken: an unreadable ledger directory, a cron the grammar
#      below does not accept, a ledger file whose newest line is not JSON or has no
#      real date. Prints "ERROR: ..." on stderr. The report file is emptied BEFORE
#      any check, so a fault is never counted as "zero overdue agents".
#
# Tunables are ${VAR:-default} so tests/check-heartbeat.bats can drive this against
# fixtures with FROZEN_NOW instead of the real clock:
#   LEDGER_DIR    directory holding ledger/<agent>.jsonl (required for `check`)
#   FROZEN_NOW    epoch seconds to treat as "now"
#   GRACE_HOURS   how late a run may be before it is overdue (default 6)
#   REPORT_FILE   where to write the findings, one per line (optional)
set -uo pipefail

ROOT="${AGENTS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export AGENTS_ROOT="$ROOT"
# shellcheck source=lib/config.sh
. "$ROOT/tools/lib/config.sh"

LEDGER_DIR="${LEDGER_DIR:-}"
FROZEN_NOW="${FROZEN_NOW:-$(date -u +%s)}"
GRACE_HOURS="${GRACE_HOURS:-6}"
REPORT_FILE="${REPORT_FILE:-}"
VERB="${1:-check}"

err() { printf 'ERROR: %s\n' "$1" >&2; exit 2; }

# date helpers, portable across GNU and BSD date: an epoch for a date string, and
# a date string for an epoch. Every calendar question below goes through these two.
epoch_of() { # <YYYY-MM-DD> [HH:MM]
  local d="$1" t="${2:-00:00}"
  if date -u -d "2000-01-01 00:00" +%s >/dev/null 2>&1; then
    date -u -d "$d $t:00" +%s 2>/dev/null
  else
    date -u -j -f '%Y-%m-%d %H:%M:%S' "$d $t:00" +%s 2>/dev/null
  fi
}
date_of() { # <epoch> <format>
  if date -u -d "@0" +%s >/dev/null 2>&1; then
    date -u -d "@$1" +"$2"
  else
    date -u -r "$1" +"$2"
  fi
}

# parse_cron <cron> <agent> — the grammar the shipped config actually uses, and
# nothing more: a numeric minute; a numeric hour or a comma list; day-of-month `*`,
# `*/N` or a number; month `*`; day-of-week `*` or a number. Anything else is a
# malfunction, not a guess: a parser that silently reinterprets an unfamiliar field
# is how a watch reports a healthy fleet that is dead.
CRON_MIN="" CRON_HOURS=() CRON_DOM="" CRON_DOM_STEP="" CRON_DOW=""
parse_cron() {
  local cron="$1" agent="$2" fields
  read -r -a fields <<<"$cron"
  [ "${#fields[@]}" -eq 5 ] || err "agent '${agent}': cron '${cron}' does not have five fields"
  local min="${fields[0]}" hour="${fields[1]}" dom="${fields[2]}" month="${fields[3]}" dow="${fields[4]}"
  [[ "$min" =~ ^[0-9]+$ ]] || err "agent '${agent}': unsupported minute field '${min}' in cron '${cron}'"
  CRON_MIN="$min"
  if [[ "$hour" =~ ^[0-9]+$ ]]; then
    CRON_HOURS=("$hour")
  elif [[ "$hour" =~ ^[0-9]+(,[0-9]+)+$ ]]; then
    IFS=',' read -r -a CRON_HOURS <<<"$hour"
  else
    err "agent '${agent}': unsupported hour field '${hour}' in cron '${cron}'"
  fi
  [ "$month" = '*' ] || err "agent '${agent}': unsupported month field '${month}' in cron '${cron}'"
  CRON_DOM="" CRON_DOM_STEP=""
  if [ "$dom" = '*' ]; then :;
  elif [[ "$dom" =~ ^\*/[0-9]+$ ]]; then CRON_DOM_STEP="${dom#\*/}"
  elif [[ "$dom" =~ ^[0-9]+$ ]]; then CRON_DOM="$dom"
  else err "agent '${agent}': unsupported day-of-month field '${dom}' in cron '${cron}'"
  fi
  if [ "$dow" = '*' ]; then CRON_DOW=""
  elif [[ "$dow" =~ ^[0-9]$ ]]; then CRON_DOW="$dow"; [ "$CRON_DOW" = 7 ] && CRON_DOW=0
  else err "agent '${agent}': unsupported day-of-week field '${dow}' in cron '${cron}'"
  fi
}

# day_matches <day-of-month> <day-of-week 0-6> — cron's rule: when BOTH fields are
# restricted a day matches if EITHER does. The shipped config never restricts both;
# the rule is written down rather than left to chance.
day_matches() {
  local dom="$1" dow="$2" dom_ok=1 dow_ok=1 restricted_dom=0 restricted_dow=0
  if [ -n "$CRON_DOM_STEP" ]; then restricted_dom=1; [ $(( (10#$dom - 1) % 10#$CRON_DOM_STEP )) -eq 0 ] && dom_ok=0; fi
  if [ -n "$CRON_DOM" ]; then restricted_dom=1; [ "$((10#$dom))" -eq "$((10#$CRON_DOM))" ] && dom_ok=0; fi
  if [ -n "$CRON_DOW" ]; then restricted_dow=1; [ "$((10#$dow))" -eq "$((10#$CRON_DOW))" ] && dow_ok=0; fi
  if [ "$restricted_dom" -eq 1 ] && [ "$restricted_dow" -eq 1 ]; then [ "$dom_ok" -eq 0 ] || [ "$dow_ok" -eq 0 ]
  elif [ "$restricted_dom" -eq 1 ]; then [ "$dom_ok" -eq 0 ]
  elif [ "$restricted_dow" -eq 1 ]; then [ "$dow_ok" -eq 0 ]
  else return 0
  fi
}

# most_recent_due_slot <cron> <agent> — SLOT_DATE: the most recent slot at or before
# (now - GRACE_HOURS), walking back day by day for at most 45 days, so a monthly
# schedule always finds one. None in that window means the schedule is unreachable —
# a malfunction, never a quiet-but-healthy agent.
SLOT_DATE=""
most_recent_due_slot() {
  local cron="$1" agent="$2" threshold offset day dom dow hour hh mm cand
  parse_cron "$cron" "$agent"
  threshold=$((FROZEN_NOW - GRACE_HOURS * 3600))
  for offset in $(seq 0 44); do
    day="$(date_of $((FROZEN_NOW - offset * 86400)) %Y-%m-%d)"
    dom="$(date_of $((FROZEN_NOW - offset * 86400)) %d)"
    dow="$(date_of $((FROZEN_NOW - offset * 86400)) %w)"
    day_matches "$dom" "$dow" || continue
    for hour in $(printf '%s\n' "${CRON_HOURS[@]}" | sort -rn); do
      printf -v hh '%02d' "$((10#$hour))"
      printf -v mm '%02d' "$((10#$CRON_MIN))"
      cand="$(epoch_of "$day" "$hh:$mm")" || err "agent '${agent}': cannot compute a slot for '${day} ${hh}:${mm}'"
      if [ "$cand" -le "$threshold" ]; then SLOT_DATE="$day"; return 0; fi
    done
  done
  err "agent '${agent}': no due slot for cron '${cron}' within 45 days — schedule unreachable"
}

# newest_ledger_date <agent> — LEDGER_DATE from the last line of ledger/<agent>.jsonl,
# or "" when the file does not exist (never run: a finding, not a fault). A file whose
# newest line is not JSON or has no date is a fault: the watch cannot trust its read.
LEDGER_DATE=""
newest_ledger_date() {
  local file="$LEDGER_DIR/$1.jsonl" last
  LEDGER_DATE=""
  [ -f "$file" ] || return 0
  last="$(tail -n 1 "$file")"
  case "$last" in \{*\}) ;; *) err "ledger file '${file}': newest line is not JSON" ;; esac
  if [[ "$last" =~ \"date\"[[:space:]]*:[[:space:]]*\"([0-9]{4}-[0-9]{2}-[0-9]{2})\" ]]; then
    LEDGER_DATE="${BASH_REMATCH[1]}"
  else
    err "ledger file '${file}': newest entry has no \"date\" field"
  fi
}

cmd_list() {
  local agent cron enabled
  while IFS= read -r agent; do
    [ -n "$agent" ] || continue
    cron="$(cfg_agent_field "$agent" schedule 2>/dev/null || echo '')"
    enabled="$(cfg_agent_field "$agent" enabled 2>/dev/null || echo true)"
    printf '%s\t%s\t%s\n' "$agent" "$cron" "$enabled"
  done < <(cfg_agents)
}

cmd_check() {
  [[ "$FROZEN_NOW" =~ ^[0-9]+$ ]] || err "FROZEN_NOW is not a plain epoch-seconds number: '${FROZEN_NOW}'"
  [[ "$GRACE_HOURS" =~ ^[0-9]+$ ]] || err "GRACE_HOURS is not a whole number: '${GRACE_HOURS}'"
  # Emptied first, before anything can fail: a stale report from a previous run is
  # never mistaken for this run's findings.
  if [ -n "$REPORT_FILE" ]; then : > "$REPORT_FILE" || err "cannot write report file '${REPORT_FILE}'"; fi

  local agents="" agent cron enabled watched=0 findings="" ledger_epoch quiet_days
  agents="$(cfg_agents)" || err "cannot read the agent ring from $(_cfg_file)"
  [ -n "$agents" ] || err "the agent ring in $(_cfg_file) is empty"

  # Which agents are enabled is decided before the ledger is touched: a fleet with
  # every agent switched off (the shipped default) has nothing to watch, and saying
  # so is the honest report — never a broken-watch error over a branch nobody needs yet.
  local enabled_agents=""
  while IFS= read -r agent; do
    [ -n "$agent" ] || continue
    enabled="$(cfg_agent_field "$agent" enabled 2>/dev/null || echo true)"
    [ "$enabled" = "false" ] && continue
    enabled_agents="${enabled_agents}${agent}"$'\n'
  done <<<"$agents"
  if [ -z "$enabled_agents" ]; then
    echo "ok: no enabled agent in .agents/config.yml — nothing to watch (enable an agent and this watch arms itself)"
    return 0
  fi

  [ -n "$LEDGER_DIR" ] || err "LEDGER_DIR is not set — point it at a checkout of the ledger branch's ledger/ directory"
  if ! { [ -d "$LEDGER_DIR" ] && [ -r "$LEDGER_DIR" ]; }; then err "cannot read ledger directory '${LEDGER_DIR}'"; fi

  while IFS= read -r agent; do
    [ -n "$agent" ] || continue
    cron="$(cfg_agent_field "$agent" schedule 2>/dev/null || true)"
    [ -n "$cron" ] || err "agent '${agent}' is enabled but has no schedule: in $(_cfg_file)"
    most_recent_due_slot "$cron" "$agent"
    newest_ledger_date "$agent"
    watched=$((watched + 1))
    if [ -z "$LEDGER_DATE" ]; then
      findings="${findings}${agent} has no ledger entry yet — missed the ${SLOT_DATE} slot"$'\n'
    elif [[ "$LEDGER_DATE" < "$SLOT_DATE" ]]; then
      ledger_epoch="$(epoch_of "$LEDGER_DATE")" \
        || err "ledger file '${LEDGER_DIR}/${agent}.jsonl': '${LEDGER_DATE}' is not a real calendar date"
      quiet_days=$(( (FROZEN_NOW - ledger_epoch) / 86400 ))
      findings="${findings}${agent} is overdue — newest ledger entry ${LEDGER_DATE}, missed the ${SLOT_DATE} slot, quiet ${quiet_days}d"$'\n'
    fi
  done <<<"$enabled_agents"

  if [ -n "$REPORT_FILE" ]; then printf '%s' "$findings" > "$REPORT_FILE"; fi
  if [ -n "$findings" ]; then
    printf '%s' "$findings"
  else
    echo "ok: ${watched} enabled agent(s) wrote a ledger entry since their last due slot (grace ${GRACE_HOURS}h)"
  fi
}

case "$VERB" in
  list)  cmd_list ;;
  check) cmd_check ;;
  *)     err "unknown verb '${VERB}' (expected 'check' or 'list')" ;;
esac
