#!/usr/bin/env bats
#
# Gate 22 guard — the lost reviewer's job log is read ONCE, with a fallback, and an
# empty read is "the log did not say", never a cause.
#
# THE LESSON. A dead runner and a spent model allowance end a reviewer job identically:
# `failure`, in seconds, no review. They have opposite remedies — waiting fixes one and
# not the other — and the only thing that tells them apart is the reviewer's own job log,
# where the refusal is worded. Three traps live in reading it:
#
#   1. The logs endpoint answers 302 to a short-lived blob URL, and `gh api` has returned
#      NOTHING for it. `curl -sSfL` follows the redirect; it is the second attempt, never
#      the only one.
#   2. The endpoint LAGS the job by a few seconds, so the first read can come back empty
#      for a log that exists. Retry, bounded.
#   3. Two independent fetches of the same log can disagree — the first one raced the
#      endpoint. So it is read once, in its own step, and every consumer gets the same
#      line through a step output.
#
# And the anti-vacuity case: when both paths return nothing, the quota line is EMPTY. The
# handoff then files (steward-handoff-decision.bats proves that half) and its body says
# the cause is unknown. A guard that only checked the happy path would pass against a
# step that never fetched anything.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"

extract_step() {
  awk '
    /^      - name: Read the lost reviewer.s job log once/ { instep = 1; next }
    instep && !inrun && /^      [^ ]/ { exit }
    instep && /^        run: \|/ { inrun = 1; next }
    inrun && NF && !/^          / { exit }
    inrun { sub(/^          /, ""); print }
  ' "$REVIEW"
}

quota_wordings() {
  grep -E '^  REVIEW_QUOTA_WORDINGS: ' "$REVIEW" | sed "s/^  REVIEW_QUOTA_WORDINGS: '//; s/'$//"
}

setup() {
  WORK="$(mktemp -d)"
  export WORK
  extract_step > "$WORK/step.sh"
  [ -s "$WORK/step.sh" ]
  grep -q 'quota_line' "$WORK/step.sh"
  QUOTA_WORDINGS="$(quota_wordings)"
  export QUOTA_WORDINGS
  [ -n "$QUOTA_WORDINGS" ]

  mkdir -p "$WORK/bin"
  # `gh api` answers the jobs listing with a fixed id, and the logs endpoint with whatever
  # the test put in STUB_GH_LOG (empty = the 302-to-blob case where gh returns nothing).
  cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
case "$*" in
  *"/actions/runs/"*"/jobs"*) echo "4242" ;;
  *"/actions/jobs/4242/logs"*) printf '%s' "${STUB_GH_LOG:-}" ;;
esac
exit 0
STUB
  chmod +x "$WORK/bin/gh"
  # `curl` is the redirect-following fallback; STUB_CURL_LOG is what the blob URL holds.
  cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$GH_CALLS"
[ -n "${STUB_CURL_LOG:-}" ] || exit 22
printf '%s' "$STUB_CURL_LOG"
STUB
  chmod +x "$WORK/bin/curl"
}

teardown() { rm -rf "$WORK"; }

run_step() { # lost reviewer role
  : > "$WORK/calls.txt"
  : > "$WORK/gh-output"
  ( PATH="$WORK/bin:$PATH" GH_CALLS="$WORK/calls.txt" GITHUB_OUTPUT="$WORK/gh-output" \
    LOST_REVIEWER="$1" REPO=o/r GITHUB_RUN_ID=99 GH_TOKEN=t \
    REVIEW_QUOTA_WORDINGS="$QUOTA_WORDINGS" \
    LOG_FETCH_ATTEMPTS="${LOG_FETCH_ATTEMPTS:-3}" LOG_FETCH_SLEEP=0 \
    bash "$WORK/step.sh" )
}

quota_line() { sed -n '/^quota_line<<QUOTA_EOF$/,/^QUOTA_EOF$/p' "$WORK/gh-output" | sed '1d;$d'; }
calls() { cat "$WORK/calls.txt"; }

@test "lost log: gh returns the log and it names a refusal — the line is exported" {
  STUB_GH_LOG=$'2026-09-12T10:00:01Z starting\n2026-09-12T10:00:02Z Error: Usage limit reached until 04:00 UTC\n' \
    run run_step judge
  [ "$status" -eq 0 ]
  [[ "$(quota_line)" == *"Usage limit reached until 04:00 UTC"* ]]
  [[ "$output" == *"names a spent allowance"* ]]
  # The judge role's job is `review`; the id came from the jobs listing.
  run calls
  [[ "$output" == *"/actions/runs/99/jobs"* ]]
  [[ "$output" == *"/actions/jobs/4242/logs"* ]]
  [[ "$output" != *"curl"* ]]
}

@test "lost log: gh returns NOTHING (the 302-to-blob case) and curl -L reads it instead" {
  STUB_GH_LOG="" STUB_CURL_LOG="provider: insufficient quota for this request" run run_step challenge
  [ "$status" -eq 0 ]
  [[ "$(quota_line)" == *"insufficient quota for this request"* ]]
  run calls
  [[ "$output" == *"curl -sSfL"* ]]
  [[ "$output" == *"/actions/jobs/4242/logs"* ]]
}

@test "lost log: ANTI-VACUITY — both paths empty, the quota line is empty, and the step still exits 0" {
  LOG_FETCH_ATTEMPTS=2 STUB_GH_LOG="" STUB_CURL_LOG="" run run_step judge
  [ "$status" -eq 0 ]
  [ -z "$(quota_line)" ]
  [[ "$output" == *"No quota cause read"* ]]
  # The heredoc output is still written, so the consumer reads an empty value rather than
  # an unset one.
  grep -q '^quota_line<<QUOTA_EOF$' "$WORK/gh-output"
}

@test "lost log: an empty endpoint is retried, bounded by LOG_FETCH_ATTEMPTS" {
  LOG_FETCH_ATTEMPTS=3 STUB_GH_LOG="" STUB_CURL_LOG="" run run_step judge
  [ "$status" -eq 0 ]
  run bash -c "grep -c '/actions/jobs/4242/logs' '$WORK/calls.txt'"
  # gh and curl each tried three times: 6 hits on the logs endpoint.
  [ "$output" -eq 6 ]
}

@test "lost log: a log with no refusal wording exports an empty line — the log did not say" {
  STUB_GH_LOG=$'2026-09-12T10:00:01Z starting\n2026-09-12T10:10:01Z runner lost contact\n' \
    run run_step judge
  [ "$status" -eq 0 ]
  [ -z "$(quota_line)" ]
}

@test "lost log: the role maps to its job name, and an unknown role reads nothing" {
  STUB_GH_LOG="usage limit reached" run run_step judge
  [[ "$(cat "$WORK/calls.txt")" == *"/jobs --jq .jobs[] | select(.name == \"review\") | .id"* ]]
  STUB_GH_LOG="usage limit reached" run run_step challenge
  [[ "$(cat "$WORK/calls.txt")" == *"select(.name == \"challenge-review\")"* ]]
  STUB_GH_LOG="usage limit reached" run run_step something-else
  [ "$status" -eq 0 ]
  [ -z "$(quota_line)" ]
  [ ! -s "$WORK/calls.txt" ]
}

@test "lost log: the quota line is read from the ONE step output by both consumers, never re-fetched" {
  # The handoff step and nothing else reads `steps.lostlog.outputs.quota_line`; no other
  # step fetches a job log.
  run grep -c 'steps.lostlog.outputs.quota_line' "$REVIEW"
  [ "$output" -ge 1 ]
  run grep -c '/actions/jobs/\$LOST_JOB_ID/logs' "$REVIEW"
  [ "$output" -eq 2 ]   # gh, then the curl fallback — inside the one step
  step="$(extract_step)"
  [ "$(printf '%s\n' "$step" | grep -c '/actions/jobs/\$LOST_JOB_ID/logs')" -eq 2 ]
}

@test "lost log: the alternation is defined once, at workflow level, and every reader uses it" {
  run grep -c '^  REVIEW_QUOTA_WORDINGS: ' "$REVIEW"
  [ "$output" -eq 1 ]
  # Three readers: the two reviewer jobs' lost-review steps and this step.
  run grep -c '"\$REVIEW_QUOTA_WORDINGS"' "$REVIEW"
  [ "$output" -eq 3 ]
  # And nobody spells a wording out a second time.
  run grep -c 'usage limit reached' "$REVIEW"
  [ "$output" -eq 1 ]
}
