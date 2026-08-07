#!/usr/bin/env bats
#
# Scenario: "Ledger round-trips on a fresh orphan branch" (intent.md, SC5).
#
# This is an INTEGRATION test against real git. It builds a scratch repository
# with a real (bare, on-disk) remote, creates the orphan branch the way the
# runbook instructs, and drives all four verbs.
#
# Why a real remote and not a mock: cmd_append clones the REMOTE rather than the
# local checkout, and the reason it does is the whole point of the test — cloning
# the working checkout gives the clone an `origin` pointing back at the working
# repo, so the final push lands on a LOCAL ref, reports success, and nothing ever
# reaches the server. A mocked git cannot tell those two apart.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LEDGER="$REPO_ROOT/tools/ledger.sh"

setup() {
  WORK="$(mktemp -d)"
  export WORK

  # The agent list is config-driven (never hard-coded in the script). In the
  # scratch repo there is no .agents/config.yml, so the test supplies the list
  # through the documented environment override.
  export LEDGER_AGENTS="ops quality"

  # A bare repository standing in for the forge.
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

  # Create the orphan branch exactly as docs/runbooks/agent-ledgers.md instructs.
  git checkout -q --orphan agent-ledger
  git rm -rqf . >/dev/null 2>&1 || true
  mkdir -p ledger
  echo "Agent ledger branch. Machine state only." > README.md
  git add README.md
  git commit -q -m "chore(ledger): create the agent-ledger orphan branch"
  git push -q origin agent-ledger

  # Back to main. Everything below must leave the caller here, on a clean tree.
  git checkout -q main
  git fetch -q origin
}

teardown() {
  rm -rf "$WORK"
}

@test "append writes one entry and adds the agent field" {
  cd "$WORK/checkout"
  run "$LEDGER" append ops \
    '{"date":"2026-08-04","verdict":"green","summary":"first run","metrics":{"disk_pct":41}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"appended to ledger/ops.jsonl on agent-ledger"* ]]
}

@test "read prints the entry back with an agent field added" {
  cd "$WORK/checkout"
  "$LEDGER" append ops \
    '{"date":"2026-08-04","verdict":"green","summary":"first run","metrics":{"disk_pct":41}}'
  run "$LEDGER" read ops
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.agent')"   = "ops" ]
  [ "$(printf '%s' "$output" | jq -r '.verdict')" = "green" ]
  [ "$(printf '%s' "$output" | jq -r '.summary')" = "first run" ]
}

@test "the entry is exactly one line — the file's whole contract is one JSON object per line" {
  cd "$WORK/checkout"
  "$LEDGER" append ops \
    '{"date":"2026-08-04","verdict":"green",
      "summary":"first run",
      "metrics":{"disk_pct":41}}'
  run "$LEDGER" read ops
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "latest prints one line per configured agent" {
  cd "$WORK/checkout"
  "$LEDGER" append ops \
    '{"date":"2026-08-04","verdict":"green","summary":"first run","metrics":{"disk_pct":41}}'
  run "$LEDGER" latest
  [ "$status" -eq 0 ]
  [[ "$output" == *"ops"*"2026-08-04"*"green"* ]]
  # An agent that has never written must still appear, as "(no entries)".
  # Absence is the signal; an agent silently missing from this list is the one
  # failure mode the watcher ring exists to catch.
  [[ "$output" == *"quality"*"(no entries)"* ]]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "trend prints the metric series as date and value" {
  cd "$WORK/checkout"
  "$LEDGER" append ops \
    '{"date":"2026-08-04","verdict":"green","summary":"first run","metrics":{"disk_pct":41}}'
  run "$LEDGER" trend ops disk_pct
  [ "$status" -eq 0 ]
  [ "$output" = "2026-08-04 41" ]
}

@test "trend prints nothing for a metric no entry carries" {
  cd "$WORK/checkout"
  "$LEDGER" append ops \
    '{"date":"2026-08-04","verdict":"green","summary":"first run","metrics":{"disk_pct":41}}'
  run "$LEDGER" trend ops not_a_metric
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the caller's working tree and current branch are unchanged" {
  cd "$WORK/checkout"
  before_branch="$(git rev-parse --abbrev-ref HEAD)"
  before_head="$(git rev-parse HEAD)"
  "$LEDGER" append ops \
    '{"date":"2026-08-04","verdict":"green","summary":"first run","metrics":{"disk_pct":41}}'
  [ "$(git rev-parse --abbrev-ref HEAD)" = "$before_branch" ]
  [ "$(git rev-parse HEAD)" = "$before_head" ]
  [ -z "$(git status --porcelain)" ]
}

@test "the push actually reaches the remote, not a local ref" {
  # This is the clone-the-REMOTE lesson, asserted directly: read the entry out of
  # the bare repository itself, with the working checkout out of the picture.
  cd "$WORK/checkout"
  "$LEDGER" append ops \
    '{"date":"2026-08-04","verdict":"green","summary":"first run","metrics":{"disk_pct":41}}'
  run git -C "$WORK/remote.git" show "agent-ledger:ledger/ops.jsonl"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.summary')" = "first run" ]
}

@test "a second append from a concurrently-updated remote replays instead of clobbering" {
  cd "$WORK/checkout"
  "$LEDGER" append ops \
    '{"date":"2026-08-04","verdict":"green","summary":"first run","metrics":{"disk_pct":41}}'
  "$LEDGER" append ops \
    '{"date":"2026-08-05","verdict":"amber","summary":"second run","metrics":{"disk_pct":44}}'
  run "$LEDGER" read ops
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
  run "$LEDGER" trend ops disk_pct
  [ "${lines[0]}" = "2026-08-04 41" ]
  [ "${lines[1]}" = "2026-08-05 44" ]
}

@test "a narrative file lands at the derived destination, never at the argument's path" {
  # The argument names a SOURCE file anywhere on disk; the destination is always
  # ledger/<agent>/<date>.md inside the branch. Deriving it rather than trusting
  # the argument keeps the layout uniform and stops an absolute path reaching
  # `git add`, which fails as "outside repository".
  cd "$WORK/checkout"
  printf '# a long-form note for a human\n' > "$WORK/somewhere-else.md"
  "$LEDGER" append ops \
    '{"date":"2026-08-04","verdict":"green","summary":"first run"}' \
    "$WORK/somewhere-else.md"
  run "$LEDGER" read ops
  [ "$(printf '%s' "$output" | jq -r '.narrative')" = "ledger/ops/2026-08-04.md" ]
  run git -C "$WORK/remote.git" show "agent-ledger:ledger/ops/2026-08-04.md"
  [ "$status" -eq 0 ]
}

@test "an unknown agent is rejected against the configured list" {
  cd "$WORK/checkout"
  run "$LEDGER" append growth '{"date":"2026-08-04","verdict":"green","summary":"x"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown agent"* ]]
}

@test "a malformed entry is rejected before anything is cloned" {
  cd "$WORK/checkout"
  run "$LEDGER" append ops 'not json at all'
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "a missing required field is rejected and the field is named" {
  cd "$WORK/checkout"
  run "$LEDGER" append ops '{"date":"2026-08-04","verdict":"green"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"summary"* ]]
}

@test "an out-of-vocabulary verdict is rejected" {
  cd "$WORK/checkout"
  run "$LEDGER" append ops '{"date":"2026-08-04","verdict":"ok","summary":"x"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"green, amber or red"* ]]
}

@test "a date that would escape the ledger directory is rejected, loudly" {
  # `.date` is INTERPOLATED INTO A PATH: the narrative lands at
  # ledger/<agent>/<date>.md. Validating only that the field EXISTS lets a traversal
  # value through to `cp`, which then writes outside the clone entirely. What made that
  # worth fixing rather than shrugging at is the exit code: `git add` fails on a path
  # outside the repository, the subshell's failure is swallowed by the retry loop, and
  # after five attempts the push still carries an entry whose `narrative` field points at
  # a file that is not on the branch. Wrong data, written to the one record the whole
  # system treats as authoritative, with a zero exit the whole way.
  cd "$WORK/checkout"
  printf 'a note\n' > "$WORK/note.md"
  target="$WORK/escaped"
  run "$LEDGER" append ops \
    "{\"date\":\"../../../..${target}\",\"verdict\":\"green\",\"summary\":\"x\"}" \
    "$WORK/note.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"date"* ]]
  [ ! -e "${target}.md" ]
}

@test "a date of the wrong shape is rejected even with no narrative file" {
  # The narrative argument is optional, so the validation cannot live behind it. The
  # commit message interpolates the same field.
  cd "$WORK/checkout"
  run "$LEDGER" append ops '{"date":"yesterday","verdict":"green","summary":"x"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"YYYY-MM-DD"* ]]
}

@test "a date that is not a string at all is rejected without a jq crash" {
  cd "$WORK/checkout"
  run "$LEDGER" append ops '{"date":20260805,"verdict":"green","summary":"x"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"date"* ]]
}

@test "a well-formed date is still accepted — the guard is a shape check, not a ban" {
  cd "$WORK/checkout"
  run "$LEDGER" append ops '{"date":"2026-08-05","verdict":"green","summary":"x"}'
  [ "$status" -eq 0 ]
}

@test "no subcommand prints usage and exits non-zero" {
  cd "$WORK/checkout"
  run "$LEDGER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "an adopter's configured commit identity reaches the commit intact" {
  # `${VAR:-{{PLACEHOLDER}}}` looks right and is not: bash closes the parameter
  # expansion at the FIRST `}`, so the default is `{{PLACEHOLDER` and the
  # trailing `}}` becomes literal text appended to whatever came out. The unset
  # case looks fine, which is why this survives review — it is only the adopter
  # who SET the variable, exactly as documented, whose every ledger commit is
  # authored by a malformed address.
  cd "$WORK/checkout"
  run env LEDGER_COMMIT_NAME="sdlc-agent" LEDGER_COMMIT_EMAIL="agent@example.invalid" \
    "$LEDGER" append ops '{"date":"2026-08-05","verdict":"green","summary":"x"}'
  [ "$status" -eq 0 ]

  run git -C "$WORK/remote.git" log -1 --format='%an|%ae' agent-ledger
  [ "$status" -eq 0 ]
  [ "$output" = "sdlc-agent|agent@example.invalid" ]
}

@test "an unset commit identity still falls back to the literal placeholder" {
  # The other half of the same guard: the fix must not quietly turn the
  # placeholder into something that looks like a real address. init.sh rewrites
  # `{{LEDGER_COMMIT_EMAIL}}`, so the token has to survive verbatim.
  cd "$WORK/checkout"
  run env -u LEDGER_COMMIT_NAME -u LEDGER_COMMIT_EMAIL \
    "$LEDGER" append ops '{"date":"2026-08-05","verdict":"green","summary":"x"}'
  [ "$status" -eq 0 ]

  run git -C "$WORK/remote.git" log -1 --format='%an|%ae' agent-ledger
  [ "$status" -eq 0 ]
  [ "$output" = "{{LEDGER_COMMIT_NAME}}|{{LEDGER_COMMIT_EMAIL}}" ]
}

@test "the script names no agent of its own — the list is config-driven" {
  # A hard-coded agent list here would be a second source of truth alongside
  # .agents/config.yml, and it would drift the moment someone adds an agent.
  run grep -nE '^[[:space:]]*AGENTS=("|.)[a-z]' "$LEDGER"
  [ "$status" -ne 0 ]
}

@test "a failed commit is reported, never announced as a successful append" {
  # `set -e` is SUPPRESSED inside a subshell in a condition context — as the left operand
  # of && or ||, or in an `if`. Neither an inner `set -e` nor capturing the status after
  # restores it. So a failing `git commit` fell through to `git push`, which had nothing
  # to push and exited 0, and the run printed "appended to ledger/<agent>.jsonl" and
  # returned 0 with the entry nowhere on the branch.
  #
  # For the ledger this is the worst available shape. It is the sole evidence an agent
  # ran, and liveness keys on the age of the newest entry — so the next agent in the ring
  # escalates about a predecessor that believes it reported successfully.
  cd "$WORK/checkout"
  mkdir -p "$WORK/hooks"
  printf '#!/bin/sh\nexit 1\n' > "$WORK/hooks/pre-commit"
  chmod +x "$WORK/hooks/pre-commit"

  run env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$WORK/hooks" \
    "$LEDGER" append ops '{"date":"2026-08-06","verdict":"green","summary":"must not be announced"}'
  [ "$status" -ne 0 ]
  [[ "$output" != *"appended to"* ]]      # never claim success
  [[ "$output" == *"NOTHING was written"* ]]
  [[ "$output" == *"commit"* ]]           # and name which step refused

  # And the branch must genuinely not carry it.
  run git -C "$WORK/remote.git" show "agent-ledger:ledger/ops.jsonl"
  [[ "$output" != *"must not be announced"* ]]
}

@test "a commit failure is not mistaken for a push rejection and retried five times" {
  # The old code treated every non-zero subshell as "push rejected", so an unretryable
  # failure burned five attempts and ~30s of sleeps before dying with the wrong reason.
  cd "$WORK/checkout"
  mkdir -p "$WORK/hooks"
  printf '#!/bin/sh\nexit 1\n' > "$WORK/hooks/pre-commit"
  chmod +x "$WORK/hooks/pre-commit"

  run env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$WORK/hooks" \
    "$LEDGER" append ops '{"date":"2026-08-06","verdict":"green","summary":"x"}'
  [ "$status" -ne 0 ]
  [[ "$output" != *"attempt 2"* ]]
  [[ "$output" != *"refetching and replaying"* ]]
}
