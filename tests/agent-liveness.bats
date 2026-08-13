#!/usr/bin/env bats
#
# Scenario: "Liveness survives a late scheduler and catches a stopped one" (intent.md,
# SC16). This is the end-to-end simulation Task 19b left open: config and the runbook
# were re-based for a best-effort scheduler, and tests/harness-guards/agents-scheduled.bats
# asserts the age-based CONFIG and the runbook WORDING exist, but nothing had driven the
# rule itself against a real ledger with entries of a known age until now.
#
# Same shape as tests/ledger-roundtrip.bats and for the same reason: a mocked git cannot
# tell a stale ref from a fresh one, and staleness/freshness is the entire thing under
# test. A scratch repo with a real bare remote and real, deliberately backdated commits
# is the only way to make "3 hours old" and "30 hours old" mean anything.
#
# AGE SOURCE: tools/check-liveness.sh measures age from the COMMIT that appended a ledger
# entry (GIT_AUTHOR_DATE/GIT_COMMITTER_DATE below), not the entry's own `date` JSON field
# — that field is validated to day granularity only (see ledger.sh) and cannot express
# "3 hours old" at all. See tools/check-liveness.sh's header for the full reasoning.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LEDGER="$REPO_ROOT/tools/ledger.sh"
CHECK_LIVENESS="$REPO_ROOT/tools/check-liveness.sh"

# now_minus_hours <N> — an ISO-8601 timestamp N hours before "now", portable across BSD
# (macOS) and GNU date, for use as GIT_AUTHOR_DATE / GIT_COMMITTER_DATE.
now_minus_hours() {
  local hours="$1"
  if date -v-1H >/dev/null 2>&1; then
    date -u -v-"${hours}"H +"%Y-%m-%dT%H:%M:%SZ"
  else
    date -u -d "${hours} hours ago" +"%Y-%m-%dT%H:%M:%SZ"
  fi
}

setup() {
  WORK="$(mktemp -d)"
  export WORK

  # The ring: two agents, "ops" then "quality", wrapping — ops's predecessor is quality
  # and quality's predecessor is ops. Fed to ledger.sh the same way
  # tests/ledger-roundtrip.bats does (LEDGER_AGENTS, no real .agents/config.yml needed for
  # writes), and fed to check-liveness.sh through a scratch AGENTS_CONFIG fixture that
  # names the same two agents plus the two liveness thresholds the scenario specifies.
  export LEDGER_AGENTS="ops quality"

  cat > "$WORK/config.yml" <<'EOF'
schema: 1
liveness:
  max-age-hours: 12
  staleness-hours: 36
ledger:
  branch: agent-ledger
  agents:
    - id: ops
    - id: quality
EOF
  export AGENTS_CONFIG="$WORK/config.yml"

  git init -q --bare "$WORK/remote.git"

  git init -q "$WORK/checkout"
  cd "$WORK/checkout"
  git config user.name  "test"
  git config user.email "test@example.invalid"
  git remote add origin "$WORK/remote.git"
  echo "scratch" > README.md
  git add README.md
  git commit -q -m "initial"
  git branch -M main
  git push -q origin main

  git checkout -q --orphan agent-ledger
  git rm -rqf . >/dev/null 2>&1 || true
  mkdir -p ledger
  echo "Agent ledger branch. Machine state only." > README.md
  git add README.md
  git commit -q -m "chore(ledger): create the agent-ledger orphan branch"
  git push -q origin agent-ledger

  git checkout -q main
  git fetch -q origin
}

teardown() {
  rm -rf "$WORK"
}

# append_backdated <agent> <hours-ago> <date-field> — appends one ledger entry whose
# commit (author AND committer date) is backdated by <hours-ago>. The JSON `date` field
# is cosmetic here — only the commit timestamp drives the age check.
append_backdated() {
  local agent="$1" hours_ago="$2" datefield="$3" ts
  ts="$(now_minus_hours "$hours_ago")"
  GIT_AUTHOR_DATE="$ts" GIT_COMMITTER_DATE="$ts" \
    "$LEDGER" append "$agent" \
    "{\"date\":\"${datefield}\",\"verdict\":\"green\",\"summary\":\"scheduled run\"}"
}

@test "a disabled predecessor is skipped, never watched into a false alarm" {
  cd "$WORK/checkout"
  # The enable-one-at-a-time rollout in miniature: audit's list-predecessor
  # quality is switched off and has (correctly) never written. Before the ring
  # learned to skip disabled agents, this escalated forever. The ring must walk
  # past quality to ops, whose fresh entry answers the actual question.
  export LEDGER_AGENTS="ops quality audit"
  cat > "$WORK/config.yml" <<'EOF'
schema: 1
liveness:
  max-age-hours: 12
  staleness-hours: 36
ledger:
  branch: agent-ledger
  agents:
    - id: ops
      enabled: true
    - id: quality
      enabled: false
    - id: audit
      enabled: true
EOF
  append_backdated ops 1 "2026-08-06"

  run "$CHECK_LIVENESS" predecessor audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok:"* ]]
  [[ "$output" == *"ops"* ]]
}

@test "a single enabled agent reports nothing-to-watch, green — never a manufactured escalation" {
  cd "$WORK/checkout"
  cat > "$WORK/config.yml" <<'EOF'
schema: 1
liveness:
  max-age-hours: 12
  staleness-hours: 36
ledger:
  branch: agent-ledger
  agents:
    - id: ops
      enabled: true
    - id: quality
      enabled: false
EOF
  run "$CHECK_LIVENESS" predecessor ops
  [ "$status" -eq 0 ]
  [[ "$output" == *"no other enabled agent"* ]]
  [[ "$output" == *"staleness check"* ]]
}

@test "a late-but-present predecessor (~3h old) does NOT escalate" {
  cd "$WORK/checkout"
  append_backdated quality 3 "2026-08-06"

  run "$CHECK_LIVENESS" predecessor ops
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok:"* ]]
  [[ "$output" == *"quality"* ]]
  [[ "$output" == *"3h"* ]]
}

@test "a genuinely stale predecessor (~30h old) DOES escalate, on age, not a miss count" {
  cd "$WORK/checkout"
  append_backdated quality 30 "2026-08-05"

  run "$CHECK_LIVENESS" predecessor ops
  [ "$status" -eq 1 ]
  [[ "$output" == *"escalate:"* ]]
  [[ "$output" == *"quality"* ]]
  [[ "$output" == *"30h"* ]]
  [[ "$output" == *"max-age-hours (12h)"* ]]
}

@test "a predecessor that has never written escalates immediately" {
  cd "$WORK/checkout"
  # ops has written; quality (ops's predecessor) never has.
  append_backdated ops 1 "2026-08-06"

  run "$CHECK_LIVENESS" predecessor ops
  [ "$status" -eq 1 ]
  [[ "$output" == *"escalate:"* ]]
  [[ "$output" == *"quality"* ]]
  [[ "$output" == *"never written"* ]]
}

@test "a per-agent max-age-hours override is honoured over the default" {
  cd "$WORK/checkout"
  cat > "$WORK/config.yml" <<'EOF'
schema: 1
liveness:
  max-age-hours: 12
  staleness-hours: 36
ledger:
  branch: agent-ledger
  agents:
    - id: ops
    - id: quality
      max-age-hours: 40
EOF
  # 30h would escalate against the 12h default, but quality's own override is 40h.
  append_backdated quality 30 "2026-08-05"

  run "$CHECK_LIVENESS" predecessor ops
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok:"* ]]
  [[ "$output" == *"max-age-hours (40h)"* ]]
}

@test "every agent stopping at once raises the documented S2" {
  cd "$WORK/checkout"
  # Both agents wrote, but their freshest entry is still well past staleness-hours (36h)
  # — the case a ring cannot see for itself, because there is nobody left to notice.
  append_backdated ops 40 "2026-08-04"
  append_backdated quality 50 "2026-08-04"

  run "$CHECK_LIVENESS" staleness
  [ "$status" -eq 2 ]
  [[ "$output" == *"S2:"* ]]
  [[ "$output" == *"40h"* ]]
  [[ "$output" == *"staleness-hours (36h)"* ]]
}

@test "the staleness check stays green while at least one agent is recently active" {
  cd "$WORK/checkout"
  append_backdated ops 3 "2026-08-06"
  append_backdated quality 50 "2026-08-04"

  run "$CHECK_LIVENESS" staleness
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok:"* ]]
  [[ "$output" == *"3h"* ]]
}

@test "an empty ledger (nobody has ever written) raises S2 rather than reporting green" {
  cd "$WORK/checkout"
  run "$CHECK_LIVENESS" staleness
  [ "$status" -eq 2 ]
  [[ "$output" == *"S2:"* ]]
  [[ "$output" == *"never written"* ]]
}
