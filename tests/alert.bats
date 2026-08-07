#!/usr/bin/env bats
#
# tools/alert.sh — the pushed-alert sender docs/runbooks/agent-escalation.md mandates.
# The contract under test, stated there and in .agents/config.yml's alerts block:
#   - channel `none` and the pre-init placeholder are announced skips, exit 0
#   - S0 is the heartbeat and is NEVER suppressed by the severity floor
#   - severities below alerts.severity_floor are announced skips (issue-only tiers)
#   - a CONFIGURED push that cannot be delivered exits 4 and says so — the caller
#     records the undelivered ping; nothing here may fail silently

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
ALERT="$REPO_ROOT/tools/alert.sh"

# A minimal config fixture obeying the documented format constraints
# (two-space indent, `- key: value` lists, comments at col 0 or after two spaces).
write_config() { # $1 = channel line content, extra lines via stdin appended under alerts:
  cat > "$BATS_TEST_TMPDIR/config.yml" <<EOF
schema: 1
alerts:
  channel: $1
  webhook_secret: TEST_ALERT_WEBHOOK
  command: "$2"
  severity_floor: ${3:-S2}
EOF
}

setup() {
  export AGENTS_CONFIG="$BATS_TEST_TMPDIR/config.yml"
}

@test "usage: wrong arg count exits 2" {
  run "$ALERT" S2
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "usage: unknown severity exits 2" {
  write_config none ""
  run "$ALERT" S9 "message"
  [ "$status" -eq 2 ]
}

@test "channel none: announced skip, exit 0" {
  write_config none ""
  run "$ALERT" S3 "prod down"
  [ "$status" -eq 0 ]
  [[ "$output" == *"'none'"* ]]
}

@test "pre-init placeholder channel: announced skip, exit 0 — a fresh template must not go red" {
  write_config '"{{ALERT_CHANNEL}}"' ""
  run "$ALERT" S2 "message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tools/init.sh"* ]]
}

@test "S1 below the default floor: announced skip, exit 0" {
  write_config command "cat > $BATS_TEST_TMPDIR/delivered.txt"
  run "$ALERT" S1 "needs eventual attention"
  [ "$status" -eq 0 ]
  [[ "$output" == *"below alerts.severity_floor"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/delivered.txt" ]
}

@test "S0 heartbeat is exempt from the floor and delivers" {
  write_config command "cat > $BATS_TEST_TMPDIR/heartbeat.txt"
  run "$ALERT" S0 "✅ [health] all clear"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/heartbeat.txt" ]
  grep -qF "all clear" "$BATS_TEST_TMPDIR/heartbeat.txt"
}

@test "command channel: S2 delivers the message on stdin" {
  write_config command "cat > $BATS_TEST_TMPDIR/ping.txt"
  run "$ALERT" S2 "🔶 [audit] quota near limit"
  [ "$status" -eq 0 ]
  grep -qF "quota near limit" "$BATS_TEST_TMPDIR/ping.txt"
}

@test "command channel: failing command exits 4 and names the undelivered-ping duty" {
  write_config command "false"
  run "$ALERT" S2 "message"
  [ "$status" -eq 4 ]
  [[ "$output" == *"UNDELIVERED PING"* ]]
}

@test "command channel: empty command is a config error, exit 3" {
  write_config command ""
  run "$ALERT" S2 "message"
  [ "$status" -eq 3 ]
}

@test "webhook channel: missing secret env var exits 4 and names the variable" {
  write_config webhook ""
  unset TEST_ALERT_WEBHOOK || true
  run "$ALERT" S2 "message"
  [ "$status" -eq 4 ]
  [[ "$output" == *"TEST_ALERT_WEBHOOK"* ]]
  [[ "$output" == *"UNDELIVERED PING"* ]]
}

@test "unknown channel is a config error, exit 3" {
  write_config carrier-pigeon ""
  run "$ALERT" S2 "message"
  [ "$status" -eq 3 ]
}
