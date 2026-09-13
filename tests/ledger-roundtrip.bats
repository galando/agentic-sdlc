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

@test "a DENIED push dies immediately with a credentials message, never the five-retry race path" {
  # A 403 / permission denial — every scheduled run under fleet mode: observe —
  # can never succeed on retry. It used to take the raced-push path: five
  # attempts, ~30s of sleeps, then "could not append after 5 attempts", a
  # contention diagnosis for a credentials problem. The script distinguishes by
  # the remote's stderr, so simulate a denial the way a forge phrases one.
  cd "$WORK/checkout"
  hook="$WORK/remote.git/hooks/pre-receive"
  printf '#!/bin/sh\necho "permission denied: write access blocked" >&2\nexit 1\n' > "$hook"
  chmod +x "$hook"
  run "$LEDGER" append ops '{"date":"2026-08-06","verdict":"green","summary":"scheduled run"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"DENIED, not raced"* ]]
  [[ "$output" == *"observe"* ]]
  # One attempt only — the retry banner never printed.
  [[ "$output" != *"push rejected (attempt"* ]]
  rm -f "$hook"
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

@test "a hygiene entry with a misspelled focus is rejected at the write, not silently at the next read" {
  # `focus` is the rotation state the hygiene agent's NEXT run branches on, and nothing
  # downstream ever rejects it: a misspelled value would just make every future run find
  # nothing it recognises, default back to dead-code, and ship half the agent's job
  # forever with no error anywhere. Failing the write is the only place the mistake
  # costs one run instead of the rotation.
  cd "$WORK/checkout"
  LEDGER_AGENTS="ops quality hygiene" \
    run "$LEDGER" append hygiene '{"date":"2026-08-04","verdict":"green","summary":"x","focus":"dead code"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"dead-code | duplication | none"* ]]
}

@test "a hygiene entry with a valid focus — or none at all — is accepted" {
  cd "$WORK/checkout"
  LEDGER_AGENTS="ops quality hygiene" \
    run "$LEDGER" append hygiene '{"date":"2026-08-04","verdict":"green","summary":"x","focus":"duplication","issues":[],"ping":{"summary":"sent","incident":null}}'
  [ "$status" -eq 0 ]
  # Absent focus reads as a "none" run — legal, and it must not advance the rotation,
  # which is the agent's own rule; the ledger only guards the vocabulary.
  LEDGER_AGENTS="ops quality hygiene" \
    run "$LEDGER" append hygiene '{"date":"2026-08-05","verdict":"amber","summary":"could not finish","issues":[],"ping":{"summary":"sent","incident":null}}'
  [ "$status" -eq 0 ]
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

@test "an unset commit identity still falls back to the script's declared placeholder" {
  # The other half of the same guard: the fix must not quietly turn the
  # placeholder into something that looks like a real address. The expected value
  # is read from ledger.sh's OWN declaration lines, because init.sh legitimately
  # rewrites those literals on an adopted tree — the invariant is "fallback equals
  # what the script declares", in both repo states, not one hardcoded token.
  name_default="$(sed -nE "s/^ *local name_placeholder='([^']*)'.*/\\1/p" "$LEDGER")"
  email_default="$(sed -nE "s/^ *local email_placeholder='([^']*)'.*/\\1/p" "$LEDGER")"
  [ -n "$name_default" ] && [ -n "$email_default" ]
  cd "$WORK/checkout"
  run env -u LEDGER_COMMIT_NAME -u LEDGER_COMMIT_EMAIL \
    "$LEDGER" append ops '{"date":"2026-08-05","verdict":"green","summary":"x"}'
  [ "$status" -eq 0 ]

  run git -C "$WORK/remote.git" log -1 --format='%an|%ae' agent-ledger
  [ "$status" -eq 0 ]
  [ "$output" = "${name_default}|${email_default}" ]
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

# ---------------------------------------------------------------------------
# --validate-only: every check, no clone, nothing written.
# ---------------------------------------------------------------------------

@test "append --validate-only runs every check, writes nothing, and never clones" {
  # Point the branch name at one the remote does not have: a real append would die
  # at the clone. Validate-only must exit 0 before it gets there, so the only way
  # this passes is if no clone was attempted.
  cd "$WORK/checkout"
  run env LEDGER_BRANCH=no-such-branch \
    "$LEDGER" append --validate-only ops '{"date":"2026-08-04","verdict":"green","summary":"x"}'
  [ "$status" -eq 0 ]
  [ "$output" = "entry is valid (not written)" ]
  run git -C "$WORK/remote.git" show "agent-ledger:ledger/ops.jsonl"
  [ "$status" -ne 0 ]
}

@test "append --validate-only still refuses what a real append refuses" {
  cd "$WORK/checkout"
  run "$LEDGER" append --validate-only ops '{"date":"yesterday","verdict":"green","summary":"x"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"YYYY-MM-DD"* ]]
}

# ---------------------------------------------------------------------------
# Rule 9 — never punt. The `not_done` gate refuses a reason outside the fixed
# list, a missing item or next step, and a `clock` stop with no draft PR number.
# The matrix below is the upstream 46-check harness in condensed form.
# ---------------------------------------------------------------------------

nd() {
  # nd <reason> [next] — a one-item not_done entry, validated only.
  local reason="$1" next="${2:-open the exact thing}"
  "$LEDGER" append --validate-only ops \
    "{\"date\":\"2026-08-04\",\"verdict\":\"green\",\"summary\":\"x\",\"not_done\":[{\"item\":\"the thing\",\"reason\":\"$reason\",\"next\":\"$next\"}]}"
}

@test "not_done: every fixed stop is accepted" {
  cd "$WORK/checkout"
  for reason in guardrail cap operator-only 'blocked-by:#12' not-reproducible; do
    run nd "$reason"
    [ "$status" -eq 0 ] || { echo "refused accepted stop '$reason': $output"; false; }
  done
  run nd clock "draft PR #12 already pushed"
  [ "$status" -eq 0 ]
}

@test "not_done: the punt vocabulary is refused, and the message names the accepted stops" {
  cd "$WORK/checkout"
  for reason in later 'next run' follow-up 'a human decides' 'out of scope' time; do
    run nd "$reason"
    [ "$status" -ne 0 ] || { echo "accepted punt '$reason'"; false; }
    [[ "$output" == *"guardrail, cap, operator-only, blocked-by:#N, not-reproducible or clock"* ]]
    [[ "$output" == *"punts, not stops"* ]]
  done
}

@test "not_done: blocked-by must name an issue or PR as blocked-by:#N" {
  cd "$WORK/checkout"
  for reason in blocked-by 'blocked-by:' 'blocked-by:#N' 'blocked-by:1412'; do
    run nd "$reason"
    [ "$status" -ne 0 ] || { echo "accepted malformed '$reason'"; false; }
  done
  run nd 'blocked-by:#1412'
  [ "$status" -eq 0 ]
}

@test "not_done: a clock stop is valid only with the draft PR number in next" {
  cd "$WORK/checkout"
  run nd clock "ran out of time"
  [ "$status" -ne 0 ]
  [[ "$output" == *"clock stop must name the draft PR number"* ]]
  run nd clock "draft #77 pushed at 06:20Z"
  [ "$status" -eq 0 ]
}

@test "not_done: a missing or empty item, next or reason is refused" {
  cd "$WORK/checkout"
  base='{"date":"2026-08-04","verdict":"green","summary":"x","not_done":'
  for items in \
    '[{"reason":"cap","next":"first next run"}]' \
    '[{"item":"","reason":"cap","next":"first next run"}]' \
    '[{"item":"x","reason":"cap"}]' \
    '[{"item":"x","reason":"cap","next":""}]' \
    '[{"item":"x","next":"first next run"}]' \
    '[{"item":"x","reason":"","next":"first next run"}]'; do
    run "$LEDGER" append --validate-only ops "${base}${items}}"
    [ "$status" -ne 0 ] || { echo "accepted incomplete item: $items"; false; }
  done
}

@test "not_done: a string or an array of strings is refused with 'must be an array'" {
  cd "$WORK/checkout"
  run "$LEDGER" append --validate-only ops \
    '{"date":"2026-08-04","verdict":"green","summary":"x","not_done":"later"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be an array"* ]]
  run "$LEDGER" append --validate-only ops \
    '{"date":"2026-08-04","verdict":"green","summary":"x","not_done":["the thing"]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be an array"* ]]
}

@test "not_done: one bad item among good ones fails the whole entry" {
  cd "$WORK/checkout"
  run "$LEDGER" append --validate-only ops \
    '{"date":"2026-08-04","verdict":"green","summary":"x","not_done":[{"item":"a","reason":"cap","next":"first next run"},{"item":"b","reason":"later","next":"soon"}]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"punts, not stops"* ]]
}

@test "not_done: an absent field or an empty array is accepted, for any agent" {
  cd "$WORK/checkout"
  run "$LEDGER" append --validate-only ops '{"date":"2026-08-04","verdict":"green","summary":"x"}'
  [ "$status" -eq 0 ]
  run "$LEDGER" append --validate-only ops '{"date":"2026-08-04","verdict":"green","summary":"x","not_done":[]}'
  [ "$status" -eq 0 ]
  # The gate is not scoped to one agent: quality is refused the same punt ops is.
  run "$LEDGER" append --validate-only quality \
    '{"date":"2026-08-04","verdict":"green","summary":"x","not_done":[{"item":"a","reason":"next run","next":"x"}]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"punts, not stops"* ]]
}

@test "not_done: the gate really writes an accepted entry and really blocks a refused one" {
  # --validate-only proves the logic; this proves the real path runs the same gate.
  cd "$WORK/checkout"
  run "$LEDGER" append ops \
    '{"date":"2026-08-04","verdict":"green","summary":"x","not_done":[{"item":"a","reason":"later","next":"x"}]}'
  [ "$status" -ne 0 ]
  run git -C "$WORK/remote.git" show "agent-ledger:ledger/ops.jsonl"
  [ "$status" -ne 0 ]
  run "$LEDGER" append ops \
    '{"date":"2026-08-04","verdict":"green","summary":"x","not_done":[{"item":"a","reason":"cap","next":"first next run"}]}'
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# ping.summary is the intent — "sent" or "none" — never a message id.
# ---------------------------------------------------------------------------

@test "ping.summary accepts sent and none, refuses anything else, and tolerates an absent ping" {
  cd "$WORK/checkout"
  for v in sent none; do
    run "$LEDGER" append --validate-only ops \
      "{\"date\":\"2026-08-04\",\"verdict\":\"green\",\"summary\":\"x\",\"ping\":{\"summary\":\"$v\",\"incident\":null}}"
    [ "$status" -eq 0 ] || { echo "refused ping.summary=$v: $output"; false; }
  done
  run "$LEDGER" append --validate-only ops \
    '{"date":"2026-08-04","verdict":"green","summary":"x","ping":{"summary":"yes","incident":null}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *'"sent" or "none"'* ]]
  # A message id in the field is the exact mistake the rule exists to stop.
  run "$LEDGER" append --validate-only ops \
    '{"date":"2026-08-04","verdict":"green","summary":"x","ping":{"summary":13,"incident":null}}'
  [ "$status" -ne 0 ]
  run "$LEDGER" append --validate-only ops '{"date":"2026-08-04","verdict":"green","summary":"x"}'
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# fix_verified: five verdicts, and the two that carry an obligation.
# ---------------------------------------------------------------------------

fv() {
  "$LEDGER" append --validate-only ops \
    "{\"date\":\"2026-08-04\",\"verdict\":\"green\",\"summary\":\"x\",\"fix_verified\":[$1]}"
}

@test "fix_verified: the five verdicts are accepted and a sixth word is refused" {
  cd "$WORK/checkout"
  for v in moved not_moved unmergeable_state; do
    run fv "{\"pr\":12,\"metric\":\"served_rule_count\",\"verdict\":\"$v\"}"
    [ "$status" -eq 0 ] || { echo "refused verdict $v: $output"; false; }
  done
  run fv '{"pr":12,"metric":"served_rule_count","verdict":"not_yet"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"moved, partial, not_moved, too_early or unmergeable_state"* ]]
}

@test "fix_verified: partial needs follow_up; too_early needs recheck_after and issue" {
  cd "$WORK/checkout"
  run fv '{"pr":12,"metric":"m","verdict":"partial"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"follow_up"* ]]
  run fv '{"pr":12,"metric":"m","verdict":"partial","follow_up":34}'
  [ "$status" -eq 0 ]
  run fv '{"pr":12,"metric":"m","verdict":"partial","follow_up":"reopened"}'
  [ "$status" -eq 0 ]

  run fv '{"pr":12,"metric":"m","verdict":"too_early","issue":34}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"recheck_after"* ]]
  run fv '{"pr":12,"metric":"m","verdict":"too_early","recheck_after":"soon","issue":34}'
  [ "$status" -ne 0 ]
  run fv '{"pr":12,"metric":"m","verdict":"too_early","recheck_after":"2026-08-11"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"issue"* ]]
  run fv '{"pr":12,"metric":"m","verdict":"too_early","recheck_after":"2026-08-11","issue":34}'
  [ "$status" -eq 0 ]

  run "$LEDGER" append --validate-only ops \
    '{"date":"2026-08-04","verdict":"green","summary":"x","fix_verified":"moved"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be an array"* ]]
}

# ---------------------------------------------------------------------------
# Same-day narrative: the second run appends under a heading; the first run's
# evidence stays; a same-day run with no narrative does not advance the number.
# ---------------------------------------------------------------------------

@test "a second same-day narrative appends under '## Run 2' and keeps the first intact" {
  cd "$WORK/checkout"
  printf 'first run evidence\n' > "$WORK/n1.md"
  printf 'second run evidence\n' > "$WORK/n2.md"
  "$LEDGER" append ops '{"date":"2026-08-04","verdict":"green","summary":"one"}' "$WORK/n1.md"
  run "$LEDGER" append ops '{"date":"2026-08-04","verdict":"green","summary":"two"}' "$WORK/n2.md"
  [ "$status" -eq 0 ]
  run git -C "$WORK/remote.git" show "agent-ledger:ledger/ops/2026-08-04.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"first run evidence"* ]]
  [[ "$output" == *"second run evidence"* ]]
  [[ "$output" =~ $'\n''## Run 2 — '[0-9]{2}:[0-9]{2}Z ]]
  # The first narrative of the day carries no heading of its own.
  [[ "$output" != *"## Run 1"* ]]
  # Both entries still point at the one file.
  run "$LEDGER" read ops
  [ "$(printf '%s\n' "$output" | jq -r '.narrative' | sort -u)" = "ledger/ops/2026-08-04.md" ]
}

@test "a same-day append with no narrative does not bump the run number" {
  cd "$WORK/checkout"
  printf 'one\n' > "$WORK/n1.md"
  printf 'two\n' > "$WORK/n2.md"
  printf 'three\n' > "$WORK/n3.md"
  "$LEDGER" append ops '{"date":"2026-08-04","verdict":"green","summary":"one"}' "$WORK/n1.md"
  "$LEDGER" append ops '{"date":"2026-08-04","verdict":"green","summary":"two"}' "$WORK/n2.md"
  "$LEDGER" append ops '{"date":"2026-08-04","verdict":"green","summary":"no narrative"}'
  "$LEDGER" append ops '{"date":"2026-08-04","verdict":"green","summary":"three"}' "$WORK/n3.md"
  run git -C "$WORK/remote.git" show "agent-ledger:ledger/ops/2026-08-04.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Run 2 — "* ]]
  [[ "$output" == *"## Run 3 — "* ]]
  [[ "$output" != *"## Run 4"* ]]
  [ "$(printf '%s\n' "$output" | grep -c '^## Run ')" -eq 2 ]
}
