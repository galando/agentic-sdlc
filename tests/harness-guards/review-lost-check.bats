#!/usr/bin/env bats
#
# Gate 22 guard — a reviewer that DIED is not a review that was LOST, executed.
#
# THE LESSON. Both lost-review steps in `.github/workflows/review.yml` used to treat every
# "no comment landed" the same way: file a `[review-lost]` issue whose body said the review
# "ran and reported success, but posted no comment". But a reviewer job that ends in
# FAILURE never wrote an opinion — the model refused the request, or the runner died — so
# there is nothing in its log to recover and nothing to investigate. When a spent
# allowance killed every reviewer of the day the same way, an issue per pull request held
# up every merge until a human closed each one, and not one of them named a finding.
#
# Same symptom, opposite answers:
#   - the reviewer step ended `failure`  -> a notice on the pull request, NO issue, exit 0
#   - the reviewer step ended green and posted nothing -> `[review-lost]`, as before
#
# Two smaller lessons ride along, and both are branches rather than strings, which is why
# this file runs the real step bodies against a stubbed `gh` and a stubbed collector:
#   - a benign skip exports `skipped_reason`, so the referee never has to infer it
#   - the `[review-lost]` dedupe matches EVERY wording for the pull request (anchored
#     regex), not only the step's own title — the two steps word theirs differently

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"

# The `run:` body of a named step, dedented. Terminator: the first non-blank line not
# indented into the block scalar.
extract_step() { # step name
  awk -v name="      - name: $1" '
    $0 == name { instep = 1; next }
    instep && !inrun && /^      [^ ]/ { exit }
    instep && /^        run: \|/ { inrun = 1; next }
    inrun && NF && !/^          / { exit }
    inrun { sub(/^          /, ""); print }
  ' "$REVIEW"
}

# The workflow-level alternation of refusal wordings, read OUT of the YAML so the test
# exercises the one the workflow actually ships.
quota_wordings() {
  grep -E '^  REVIEW_QUOTA_WORDINGS: ' "$REVIEW" | sed "s/^  REVIEW_QUOTA_WORDINGS: '//; s/'$//"
}

setup() {
  WORK="$(mktemp -d)"
  export WORK
  extract_step "Report a lost or skipped review" > "$WORK/judge-step.sh"
  extract_step "Report a lost challenge review"  > "$WORK/challenge-step.sh"
  [ -s "$WORK/judge-step.sh" ]
  [ -s "$WORK/challenge-step.sh" ]
  grep -q 'review-lost' "$WORK/judge-step.sh"
  grep -q 'review-lost' "$WORK/challenge-step.sh"
  QUOTA_WORDINGS="$(quota_wordings)"
  export QUOTA_WORDINGS
  [ -n "$QUOTA_WORDINGS" ]

  mkdir -p "$WORK/bin" "$WORK/run/tools" "$WORK/tmp"

  cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '[%s] %s\n' "${GH_TOKEN:-unset}" "$*" >> "$GH_CALLS"
case "$1 $2" in
  "issue list") printf '%s\n' "${STUB_OPEN_TITLES:-}" ;;
  "api repos/o/r/pulls/12/files") printf '%s\n' "${STUB_WORKFLOW_FILES:-}" ;;
esac
exit 0
STUB
  chmod +x "$WORK/bin/gh"

  # The collector is stubbed by NAME at the path the step calls: what it returns is the
  # test's input. review-collector.bats proves the real collector.
  cat > "$WORK/run/tools/collect-review-comment.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${STUB_BODY:-}"
STUB
  chmod +x "$WORK/run/tools/collect-review-comment.sh"
}

teardown() { rm -rf "$WORK"; }

# $1 which step (judge|challenge), $2 reviewer outcome (success|failure|""), $3 rc,
# $4 log text ("" = no log file)
run_step() {
  : > "$WORK/calls.txt"
  local log=""
  if [ -n "${4:-}" ]; then
    log="$WORK/tmp/reviewer.log"
    printf '%s\n' "$4" > "$log"
  fi
  ( cd "$WORK/run" \
    && PATH="$WORK/bin:$PATH" GH_CALLS="$WORK/calls.txt" \
       RUNNER_TEMP="$WORK/tmp" GITHUB_OUTPUT="$WORK/gh-output" \
       REVIEW_OUTCOME="${2:-success}" REVIEW_RC="${3:-0}" REVIEW_LOG="$log" \
       REVIEW_QUOTA_WORDINGS="$QUOTA_WORDINGS" \
       SINCE=2026-08-05T10:00:00Z PR=12 REPO=o/r SERVER=https://e.invalid \
       PR_TITLE="T" PR_AUTHOR="bot" HEAD_REF="agent/fix-1" \
       RUN_URL=https://e.invalid/run TOKEN_TRIGGERS=true GH_TOKEN=elevated-pat \
       bash "$WORK/$1-step.sh" )
}

calls() { cat "$WORK/calls.txt"; }
outputs() { cat "$WORK/gh-output" 2>/dev/null || true; }

@test "lost check: the steps can be extracted and the wordings read (else everything below is vacuous)" {
  grep -q 'REVIEW_OUTCOME' "$WORK/judge-step.sh"
  grep -q 'REVIEW_OUTCOME' "$WORK/challenge-step.sh"
  [[ "$QUOTA_WORDINGS" == *"usage limit reached"* ]]
  [[ "$QUOTA_WORDINGS" == *"|"* ]]
}

# --- the reviewer DIED -------------------------------------------------------

@test "died: the judge step posts a notice, files NO issue, exports reviewer-failed, exits 0" {
  : > "$WORK/gh-output"
  STUB_BODY="" run run_step judge failure 1 "some log line"
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]
  [[ "$output" == *"pr comment 12"* ]]
  run outputs
  [[ "$output" == *"skipped_reason=reviewer-failed"* ]]
  body="$(cat "$WORK"/tmp/review-unavailable-body.md)"
  [[ "$body" == "## The judge-role review did not run"* ]]
  [[ "$body" == *"There are no findings in its log to recover"* ]]
  [[ "$body" == *"No issue was opened for this, deliberately"* ]]
  [[ "$body" == *"Before merging:"* ]]
  [[ "$body" == *"read the diff yourself"* ]]
  [[ "$body" == *"draft"* ]]
  [[ "$body" == *"ready for review again"* ]]
}

@test "died: the challenge step does the same — and does NOT exit 1 for a job that already failed" {
  : > "$WORK/gh-output"
  STUB_BODY="" run run_step challenge failure 1 "some log line"
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]
  [[ "$output" == *"pr comment 12"* ]]
  run outputs
  [[ "$output" == *"skipped_reason=reviewer-failed"* ]]
  body="$(cat "$WORK"/tmp/challenge-unavailable-body.md)"
  [[ "$body" == "## The challenge-role review did not run"* ]]
  [[ "$body" == *"reviewed once, not twice"* ]]
  [[ "$body" == *"No issue was opened for this, deliberately"* ]]
}

@test "died: a non-zero exit code alone is enough, whatever the outcome field says" {
  # The exit code is a step output; the outcome is a step field. Either says "died".
  : > "$WORK/gh-output"
  STUB_BODY="" run run_step judge "" 124 ""
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]
  run outputs
  [[ "$output" == *"skipped_reason=reviewer-failed"* ]]
  [[ "$(cat "$WORK"/tmp/review-unavailable-body.md)" == *'exit code `124`'* ]]
}

@test "died: the cause is NAMED when the reviewer's own log states a refusal" {
  for step in judge challenge; do
    STUB_BODY="" run run_step "$step" failure 1 $'starting...\nError: Usage limit reached for this period, resets 04:00\nexit'
    [ "$status" -eq 0 ]
    body="$(cat "$WORK"/tmp/*-unavailable-body.md)"
    [[ "$body" == *"The run log names the cause:"* ]] || { echo "[$step] $body"; return 1; }
    [[ "$body" == *"Usage limit reached for this period, resets 04:00"* ]]
    [[ "$body" == *"A spent allowance refuses a re-run the same way until it resets"* ]]
    [[ "$body" == *"Waiting is the"* ]]
    rm -f "$WORK"/tmp/*-unavailable-body.md
  done
}

@test "died: every refusal wording in the workflow's list is recognised" {
  IFS='|' read -r -a wordings <<<"$QUOTA_WORDINGS"
  [ "${#wordings[@]}" -ge 5 ]
  for w in "${wordings[@]}"; do
    STUB_BODY="" run run_step judge failure 1 "provider said: ${w} (code 429)"
    [ "$status" -eq 0 ]
    body="$(cat "$WORK"/tmp/review-unavailable-body.md)"
    [[ "$body" == *"names the cause"* ]] || { echo "not recognised: [$w]"; return 1; }
    rm -f "$WORK"/tmp/review-unavailable-body.md
  done
}

@test "died: with no cause in the log the notice says it does not know, and still files nothing" {
  STUB_BODY="" run run_step judge failure 1 $'nothing useful here\nexit 1'
  [ "$status" -eq 0 ]
  body="$(cat "$WORK"/tmp/review-unavailable-body.md)"
  [[ "$body" == *"The log does not say which of two causes it was"* ]]
  [[ "$body" != *"names the cause"* ]]
  run calls
  [[ "$output" != *"issue create"* ]]
}

@test "died: a missing REQUIRED credential (exit 5) is a no-credential skip, not a lost review" {
  : > "$WORK/gh-output"
  STUB_BODY="" run run_step judge failure 5 ""
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]
  [[ "$output" == *"pr comment 12"* ]]
  run outputs
  [[ "$output" == *"skipped_reason=no-credential"* ]]
  body="$(cat "$WORK"/tmp/review-nocred-body.md)"
  [[ "$body" == *"no credential"* ]]
  [[ "$body" == *"This is not a lost review"* ]]
}

@test "died: the notice never claims the OTHER reviewer is affected" {
  STUB_BODY="" run run_step judge failure 1 ""
  [ "$status" -eq 0 ]
  body="$(cat "$WORK"/tmp/review-unavailable-body.md)"
  [[ "$body" == *"challenge-role reviewer runs after this one on its own credential"* ]]
  [[ "$body" != *"Both reviewers"* ]]
  [[ "$body" != *"neither"* ]]
}

# --- the reviewer ran green and posted nothing: still a lost review --------------

@test "lost: a green run with no comment still files [review-lost] — the detector is intact" {
  STUB_BODY="" run run_step judge success 0 ""
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"issue create --repo o/r --title [review-lost] Automated review posted nothing on PR #12"* ]]
  body="$(cat "$WORK"/tmp/review-lost-body.md)"
  [[ "$body" == *"ran to completion (exit 0) but posted no comment"* ]]
  [[ "$body" != *"ran and reported success"* ]]
  # The re-run advice: the toggle, a push starts nothing, a re-run replays the event.
  [[ "$body" == *"draft and ready for review again"* ]]
  [[ "$body" == *"a push starts nothing"* ]]
  [[ "$body" == *"replays the original event"* ]]
}

@test "lost: the challenge step files [review-lost] and exits 1 — a lost review is not a success" {
  STUB_BODY="" run run_step challenge success 0 ""
  [ "$status" -eq 1 ]
  run calls
  [[ "$output" == *"--title [review-lost] The challenge review posted nothing on PR #12"* ]]
}

@test "lost: the phrase 'ran and reported success' is gone from the workflow" {
  run grep -n 'ran and reported success' "$REVIEW"
  [ "$status" -ne 0 ]
}

@test "lost: a review that landed files nothing and exports no skip" {
  : > "$WORK/gh-output"
  STUB_BODY=$'<!-- reviewer: judge -->\nLooks fine.' run run_step judge success 0 ""
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]
  [[ "$output" != *"pr comment"* ]]
  run outputs
  [[ "$output" != *"skipped_reason"* ]]
  STUB_BODY=$'<!-- reviewer: challenge -->\nLooks fine.' run run_step challenge success 0 ""
  [ "$status" -eq 0 ]
}

# --- dedupe across every [review-lost] wording ----------------------------------

@test "dedupe: an open [review-lost] with the OTHER step's wording suppresses a second filing" {
  # The challenge step files "[review-lost] The challenge review posted nothing on PR #N",
  # the review job "[review-lost] Automated review posted nothing on PR #N". An exact
  # match on the step's own title could not see the other one, and two issues were open
  # for one cause.
  export STUB_OPEN_TITLES="[review-lost] The challenge review posted nothing on PR #12"
  STUB_BODY="" run run_step judge success 0 ""
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]

  export STUB_OPEN_TITLES="[review-lost] Automated review posted nothing on PR #12"
  STUB_BODY="" run run_step challenge success 0 ""
  [ "$status" -eq 1 ]
  run calls
  [[ "$output" != *"issue create"* ]]
}

@test "dedupe: a near-miss pull-request number does NOT suppress a real filing" {
  # Anchored at the end, so PR #12 is not matched by an issue for PR #123 — the
  # tokenising search would have.
  export STUB_OPEN_TITLES="[review-lost] Automated review posted nothing on PR #123"
  STUB_BODY="" run run_step judge success 0 ""
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"issue create"* ]]
}

@test "dedupe: both steps use the anchored regex, and neither an exact match on its own title" {
  for f in judge challenge; do
    grep -q 'grep -cE "^\\\[review-lost\\\] .\* on PR #\$PR\\$"' "$WORK/$f-step.sh"
    ! grep -q 'grep -cFx "\$TITLE"' "$WORK/$f-step.sh"
  done
}

# --- the supply-chain carve-out is honest and not symmetric ---------------------

@test "carve-out: a workflow-editing pull request gets a notice, no issue, and skipped_reason=supply-chain" {
  : > "$WORK/gh-output"
  export STUB_WORKFLOW_FILES=".github/workflows/review.yml"
  STUB_BODY="" run run_step judge success 0 ""
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]
  [[ "$output" == *"pr comment 12"* ]]
  run outputs
  [[ "$output" == *"skipped_reason=supply-chain"* ]]
}

@test "carve-out: the notice never claims both reviewers are affected, and admits it may be a lost review" {
  export STUB_WORKFLOW_FILES=".github/workflows/review.yml"
  STUB_BODY="" run run_step judge success 0 ""
  [ "$status" -eq 0 ]
  body="$(cat "$WORK"/tmp/review-skipped-body.md)"
  [[ "$body" != *"Both reviewers are affected"* ]]
  [[ "$body" != *"none is coming"* ]]
  [[ "$body" == *"may also be a review that was lost"* ]]
  [[ "$body" == *"challenge-role reviewer runs after this one"* ]]
  [[ "$body" == *"may"$'\n'"still post"* || "$body" == *"may still post"* ]]
  [[ "$body" == *"draft and ready for review again"* ]]
}

@test "carve-out: the challenge step says its own piece rather than deferring to reviewer A" {
  : > "$WORK/gh-output"
  export STUB_WORKFLOW_FILES=".github/workflows/review.yml"
  STUB_BODY="" run run_step challenge success 0 ""
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"pr comment 12"* ]]
  [[ "$output" != *"issue create"* ]]
  run outputs
  [[ "$output" == *"skipped_reason=supply-chain"* ]]
  body="$(cat "$WORK"/tmp/challenge-skipped-body.md)"
  [[ "$body" == *"challenge-role reviewer produced no opinion"* ]]
}

@test "carve-out: the workflow admits the guard is the provider's, not run-agent.sh's" {
  # The template's own runner has no such guard; an adopter must not read the carve-out
  # as a promise the harness makes.
  run grep -q 'tools/run-agent.sh has no such guard of its own' "$REVIEW"
  [ "$status" -eq 0 ]
  ! grep -rqi 'workflow files differ\|supply.chain' "$REPO_ROOT/tools/run-agent.sh"
}

# --- the exported skip reason reaches the referee -------------------------------

@test "wiring: both reviewer jobs export skipped_reason, and the referee reads both plus needs.*.result" {
  run grep -c 'skipped_reason: ${{ steps.lost.outputs.skipped_reason }}' "$REVIEW"
  [ "$output" -eq 2 ]
  grep -q 'REVIEW_SKIPPED: ${{ needs.review.outputs.skipped_reason }}' "$REVIEW"
  grep -q 'CHALLENGE_SKIPPED: ${{ needs.challenge-review.outputs.skipped_reason }}' "$REVIEW"
  grep -q 'REVIEW_RESULT: ${{ needs.review.result }}' "$REVIEW"
  grep -q 'CHALLENGE_RESULT: ${{ needs.challenge-review.result }}' "$REVIEW"
}

@test "wiring: both reviewer steps carry an id, capture the exit code, and keep the log" {
  run grep -c '^        id: reviewer$' "$REVIEW"
  [ "$output" -eq 2 ]
  run grep -c 'rc=${PIPESTATUS\[0\]}' "$REVIEW"
  [ "$output" -eq 2 ]
  run grep -c 'echo "rc=$rc" >> "$GITHUB_OUTPUT"' "$REVIEW"
  [ "$output" -eq 2 ]
  run grep -c 'REVIEW_RC: ${{ steps.reviewer.outputs.rc }}' "$REVIEW"
  [ "$output" -eq 2 ]
  run grep -c 'REVIEW_OUTCOME: ${{ steps.reviewer.outcome }}' "$REVIEW"
  [ "$output" -eq 2 ]
}

@test "wiring: the header states the re-run rule — toggle, push starts nothing, re-run replays" {
  header="$(sed -n '1,/^name: review$/p' "$REVIEW")"
  [[ "$header" == *"HOW TO RE-RUN THE REVIEWERS"* ]]
  [[ "$header" == *"draft and ready"* ]]
  [[ "$header" == *"starts nothing"* ]]
  [[ "$header" == *"replays the ORIGINAL event payload"* ]]
}
