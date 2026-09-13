#!/usr/bin/env bats
#
# tools/check-heartbeat.sh — the fleet watched from OUTSIDE the fleet.
#
# The watcher ring runs inside an agent run, so a scheduler that stops every agent
# at once cannot make the ring report anything; upstream, five agents missed ten runs
# before a human noticed. This script reads two things that exist whether or not any
# agent is alive — the schedules in .agents/config.yml and the newest ledger entry
# per agent — and its exit code answers only "did the watch work?". These tests drive
# it against fixtures with a frozen clock, and pin the property that matters most: a
# BROKEN watch never reads as a healthy fleet.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
CHECK="$REPO_ROOT/tools/check-heartbeat.sh"

# 2026-09-16 12:00:00Z, a Wednesday.
NOW=1789560000

setup() {
  WORK="$(mktemp -d)"
  export WORK
  mkdir -p "$WORK/ledger"
  cat > "$WORK/config.yml" <<'EOF'
schema: 1
ledger:
  branch: agent-ledger
  agents:
    - id: daily
      schedule: "17 6 * * *"
      enabled: true
    - id: weekly
      schedule: "7 9 * * 1"
      enabled: true
    - id: monthly
      schedule: "53 9 1 * *"
      enabled: true
    - id: off
      schedule: "23 7 * * *"
      enabled: false
EOF
  export AGENTS_CONFIG="$WORK/config.yml"
  export AGENTS_CONFIG_READER=awk
  export LEDGER_DIR="$WORK/ledger"
  export FROZEN_NOW="$NOW"
  export REPORT_FILE="$WORK/report.txt"
}

teardown() { rm -rf "$WORK"; }

entry() { # <agent> <date>
  printf '{"date":"%s","verdict":"ok","summary":"run"}\n' "$2" >> "$WORK/ledger/$1.jsonl"
}

@test "every enabled agent on time: exit 0, empty report, a line that says how many were checked" {
  entry daily 2026-09-16      # 06:17 today, matured at 12:00 with a 6h grace? no: 06:17+6h = 12:17 > now, so yesterday's slot is the due one
  entry weekly 2026-09-14     # Monday
  entry monthly 2026-09-01
  run bash "$CHECK" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 enabled agent(s) wrote a ledger entry"* ]]
  [ ! -s "$REPORT_FILE" ]
}

@test "a disabled agent is never watched, even with no ledger file at all" {
  entry daily 2026-09-16; entry weekly 2026-09-14; entry monthly 2026-09-01
  run bash "$CHECK" check
  [ "$status" -eq 0 ]
  [[ "$output" != *"off"* ]]
}

@test "the grace period is honoured: a slot due less than GRACE_HOURS ago is not yet overdue" {
  # Today's 06:17 slot is 5h43m old at 12:00 — inside the 6h grace — so the due
  # slot is yesterday's, and an entry dated yesterday is on time.
  entry daily 2026-09-15; entry weekly 2026-09-14; entry monthly 2026-09-01
  run bash "$CHECK" check
  [ "$status" -eq 0 ]
  [ ! -s "$REPORT_FILE" ]
  # With a 1h grace, today's slot is due and yesterday's entry is overdue.
  GRACE_HOURS=1 run bash "$CHECK" check
  [ "$status" -eq 0 ]
  grep -q '^daily is overdue' "$REPORT_FILE"
}

@test "an overdue daily agent is a FINDING: exit 0, one report line naming the missed slot and the quiet days" {
  entry daily 2026-09-12; entry weekly 2026-09-14; entry monthly 2026-09-01
  run bash "$CHECK" check
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$REPORT_FILE")" -eq 1 ]
  grep -q 'daily is overdue — newest ledger entry 2026-09-12, missed the 2026-09-15 slot, quiet 4d' "$REPORT_FILE"
}

@test "a weekly agent is judged against its own weekday slot, not a daily one" {
  # Newest entry last Monday (09-07): the 09-14 Monday slot was missed.
  entry daily 2026-09-15; entry weekly 2026-09-07; entry monthly 2026-09-01
  run bash "$CHECK" check
  [ "$status" -eq 0 ]
  grep -q 'weekly is overdue — newest ledger entry 2026-09-07, missed the 2026-09-14 slot' "$REPORT_FILE"
  # An entry from the Monday itself is on time for the whole week.
  rm "$WORK/ledger/weekly.jsonl"; entry weekly 2026-09-14
  run bash "$CHECK" check
  [ "$status" -eq 0 ]
  ! grep -q weekly "$REPORT_FILE"
}

@test "a monthly agent (numeric day-of-month) finds its slot up to a month back" {
  entry daily 2026-09-15; entry weekly 2026-09-14; entry monthly 2026-08-01
  run bash "$CHECK" check
  [ "$status" -eq 0 ]
  grep -q 'monthly is overdue — newest ledger entry 2026-08-01, missed the 2026-09-01 slot' "$REPORT_FILE"
}

@test "an enabled agent that has never written is a finding, not a fault" {
  entry daily 2026-09-15; entry weekly 2026-09-14
  run bash "$CHECK" check
  [ "$status" -eq 0 ]
  grep -q 'monthly has no ledger entry yet — missed the 2026-09-01 slot' "$REPORT_FILE"
}

@test "no enabled agent at all: nothing to watch, exit 0, and the ledger directory is not even needed" {
  sed -i.bak 's/enabled: true/enabled: false/' "$WORK/config.yml"
  rm -rf "$WORK/ledger"
  run bash "$CHECK" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"no enabled agent"* ]]
}

@test "a missing ledger directory with an enabled agent is a BROKEN watch: exit 2, empty report" {
  rm -rf "$WORK/ledger"
  run bash "$CHECK" check
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR: cannot read ledger directory"* ]]
  [ ! -s "$REPORT_FILE" ]
}

@test "a cron outside the accepted grammar is a BROKEN watch, never a guess" {
  sed -i.bak 's/"17 6 \* \* \*"/"17 6 * * 1-5"/' "$WORK/config.yml"
  entry daily 2026-09-16; entry weekly 2026-09-14; entry monthly 2026-09-01
  run bash "$CHECK" check
  [ "$status" -eq 2 ]
  [[ "$output" == *"unsupported day-of-week field"* ]]
}

@test "a ledger file whose newest line is not JSON is a BROKEN watch" {
  entry daily 2026-09-16; entry weekly 2026-09-14; entry monthly 2026-09-01
  echo "garbage" >> "$WORK/ledger/daily.jsonl"
  run bash "$CHECK" check
  [ "$status" -eq 2 ]
  [[ "$output" == *"newest line is not JSON"* ]]
}

@test "a stale report from an earlier run is emptied before any check can fail" {
  echo "old finding" > "$REPORT_FILE"
  rm -rf "$WORK/ledger"
  run bash "$CHECK" check
  [ "$status" -eq 2 ]
  [ ! -s "$REPORT_FILE" ]
}

@test "an enabled agent with no schedule is a BROKEN watch" {
  sed -i.bak '/schedule: "17 6 \* \* \*"/d' "$WORK/config.yml"
  entry weekly 2026-09-14; entry monthly 2026-09-01
  run bash "$CHECK" check
  [ "$status" -eq 2 ]
  [[ "$output" == *"has no schedule"* ]]
}

@test "list prints every configured agent with its cron and enabled flag" {
  run bash "$CHECK" list
  [ "$status" -eq 0 ]
  [[ "$output" == *$'daily\t17 6 * * *\ttrue'* ]]
  [[ "$output" == *$'off\t23 7 * * *\tfalse'* ]]
}

@test "the shipped config's every schedule parses — the watch is armed for the real ring" {
  unset AGENTS_CONFIG
  run bash "$CHECK" list
  [ "$status" -eq 0 ]
  while IFS=$'\t' read -r agent cron enabled; do
    [ -n "$cron" ] || { echo "# $agent has no schedule"; false; }
  done <<<"$output"
  # Every enabled:false in the shipped tree, so the shipped watch has nothing to say.
  run bash "$CHECK" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"no enabled agent"* ]]
}
