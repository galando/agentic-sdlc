#!/usr/bin/env bats
#
# Gate 22 guard — WHO gets woken, and when. The handoff decision, executed.
#
# `steward-handoff-order.bats` pins the SHAPE of this step (which job it lives in, that it
# reads both review files, that the dedupe and the token contract survived the move). That
# is text matching, and text matching is what let the bug below through: every string it
# checks was present and correct while the step still exited quietly on the one path that
# matters.
#
# THE HOLE IT MISSED. The "no review landed" branch treats an empty judge.md and
# challenge.md as "there was nothing to collect", and defers to the review job's
# lost-review check. But the collector can also FAIL — a transient API error under `set -e`
# is enough — and then the files are missing for a completely different reason: the reviews
# ARE on the pull request, with real findings, and the lost-review check saw them and
# correctly filed nothing. This step then read "no reviews", exited 0, and woke nobody.
#
# Two states, identical on disk, opposite meanings. The stranded finding this whole
# machinery exists to prevent, arriving through a different door — and a text pin cannot
# tell them apart, because the difference is a branch, not a string.
#
# So this file runs the real decision block against a stubbed `gh` and asserts what it
# DOES: which issue it files, which comment it posts, and — the point — when it stays
# silent.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"

# The `run:` body of the handoff step, dedented. Terminator: the first non-blank line not
# indented into the block scalar — NOT the next `- name:`, which a comment banner at that
# indent would sail straight past.
extract_handoff() {
  awk '
    /^      - name: Hand blocking findings to the steward/ { instep = 1; next }
    instep && !inrun && /^      [^ ]/ { exit }
    instep && /^        run: \|/ { inrun = 1; next }
    inrun && NF && !/^          / { exit }
    inrun { sub(/^          /, ""); print }
  ' "$REVIEW"
}

setup() {
  WORK="$(mktemp -d)"
  export WORK
  extract_handoff > "$WORK/handoff.sh"
  [ -s "$WORK/handoff.sh" ]
  grep -q 'steward-handoff' "$WORK/handoff.sh"

  mkdir -p "$WORK/bin" "$WORK/run/.review-artifacts"

  # The step now calls tools/review-handoff-decide.sh by repo-relative path, so the
  # fixture has to look like the checkout the step runs in. Symlinked rather than copied:
  # the point is to exercise the REAL decision script alongside the real step, so an edit
  # to either one is felt here immediately.
  ln -s "$REPO_ROOT/tools" "$WORK/run/tools"

  # A stubbed `gh` recording every call. `issue list` returns nothing, so the dedupe path
  # is open unless a test says otherwise. `pr view` answers the state the test sets
  # (OPEN by default), `pr edit` adds the label unless the test says it fails.
  cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# The token is recorded alongside the call, because WHICH token files the issue is the
# whole difference between "wake the steward" and "leave the pull request alone".
printf '[%s] %s\n' "${GH_TOKEN:-unset}" "$*" >> "$GH_CALLS"
case "$1 $2" in
  "issue list") printf '%s\n' "${STUB_OPEN_TITLES:-}" ;;
  "issue create") [ "${STUB_ISSUE_FAILS:-false}" = true ] && exit 1 ;;
  "pr view") printf '%s %s\n' "${STUB_PR_STATE:-OPEN}" "${STUB_MERGED_AT:-}" ;;
  "pr edit") [ "${STUB_LABEL_FAILS:-false}" = true ] && exit 1 ;;
esac
exit 0
STUB
  chmod +x "$WORK/bin/gh"
}

teardown() { rm -rf "$WORK"; }

# judge-body, challenge-body, verdict, collect-outcome, head-ref
#
# The verdict is argument 3 because it is now the thing that DECIDES; the review bodies
# only establish that there was something to rule on. Pass "" for "the referee wrote no
# verdict file at all".
run_handoff() {
  : > "$WORK/calls.txt"
  [ -n "${1:-}" ] && printf '%s\n' "$1" > "$WORK/run/.review-artifacts/judge.md" \
                  || rm -f "$WORK/run/.review-artifacts/judge.md"
  [ -n "${2:-}" ] && printf '%s\n' "$2" > "$WORK/run/.review-artifacts/challenge.md" \
                  || rm -f "$WORK/run/.review-artifacts/challenge.md"
  [ -n "${3:-}" ] && printf '%s\n' "$3" > "$WORK/run/.review-artifacts/referee-verdict.txt" \
                  || rm -f "$WORK/run/.review-artifacts/referee-verdict.txt"
  # RUNNER_TEMP must EXIST and be writable, or the step falls back to its own `mktemp -d`
  # and the body files land somewhere this test cannot find — which is the step behaving
  # correctly, and the fixture being wrong.
  mkdir -p "$WORK/tmp"
  ( cd "$WORK/run" \
    && PATH="$WORK/bin:$PATH" GH_CALLS="$WORK/calls.txt" \
       RUNNER_TEMP="$WORK/tmp" \
       COLLECT_OUTCOME="${4:-success}" \
       HEAD_REF="${5:-agent/fix-1}" \
       LOST_REVIEWER="${LOST_REVIEWER:-}" QUOTA_LINE_FROM_LOG="${QUOTA_LINE_FROM_LOG:-}" \
       PR=12 REPO=o/r SERVER=https://e.invalid PR_TITLE="T" PR_AUTHOR="bot" \
       RUN_URL=https://e.invalid/run TOKEN_TRIGGERS=true \
       GH_TOKEN=elevated-pat GH_TOKEN_INERT=inert-github-token \
       bash "$WORK/handoff.sh" )
}

calls() { cat "$WORK/calls.txt"; }

REVIEW_BODY="Looks mostly fine. One thing: src/a.js:10 drops the error."

@test "handoff decision: a BLOCKING verdict files a handoff with the elevated token" {
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" blocking
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"issue create"* ]]
  [[ "$output" == *"[steward-handoff]"* ]]
  # The elevated token is what makes filing it wake anyone at all.
  [[ "$output" == *"[elevated-pat] issue create"* ]]
}

@test "handoff decision: a NON-BLOCKING verdict wakes nobody, and does not drop the findings" {
  # THE DEFECT THIS REPLACED. The step used to grep the review bodies for the literal
  # "No issues found" — a plugin's clean marker that neither reviewer prompt asks for. Two
  # reviews of ordinary prose therefore counted as findings on EVERY agent pull request,
  # and the steward pushed commits onto pull requests both reviewers had approved.
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" non-blocking
  [ "$status" -eq 0 ]
  run calls
  # Not a handoff...
  [[ "$output" != *"[steward-handoff]"* ]]
  # ...and on an OPEN pull request not an issue either: the pull request is MARKED and
  # the findings are posted on it. The merge decides whether they become an issue.
  [[ "$output" != *"issue create"* ]]
  [[ "$output" == *"pr edit 12 --repo o/r --add-label review-followup-pending"* ]]
  [[ "$output" == *"pr comment"* ]]
}

@test "handoff decision: the mark comment has the exact heading, three choices, and the findings" {
  printf '## Reviewer comparison\n\nFINDING-MARKER-7\n' > "$WORK/run/.review-artifacts/referee-comment.md"
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" non-blocking
  [ "$status" -eq 0 ]
  body="$(cat "$WORK"/tmp/review-followup-marker.md)"
  [[ "$body" == "### Review follow-up: clear these before you merge"* ]]
  [[ "$body" == *"review-followup-pending"* ]]
  # Fix and remove the label; leave it and the sweep files at merge; disagree and remove it.
  [[ "$body" == *"remove the label before you merge"* ]]
  [[ "$body" == *"Leave the label on"* ]]
  [[ "$body" == *"merge-time sweep files"* ]]
  [[ "$body" == *"Disagree with a finding"* ]]
  # The findings are embedded, not linked.
  [[ "$body" == *"<details>"* ]]
  [[ "$body" == *"FINDING-MARKER-7"* ]]
}

@test "handoff decision: THE TOKEN IS THE SWITCH — the mark and the follow-up use the inert one" {
  # GitHub does not start workflow runs from events created with GITHUB_TOKEN, and the
  # steward auto-invokes on `issues.opened`. Filing or commenting with the PAT instead
  # would wake it for exactly the findings the verdict just said not to wake it for — and
  # nothing else in the workflow would look any different.
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" non-blocking
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"[inert-github-token] pr edit"* ]]
  [[ "$output" == *"[inert-github-token] pr comment"* ]]
  [[ "$output" != *"[elevated-pat] pr comment"* ]]

  export STUB_PR_STATE=MERGED STUB_MERGED_AT=2026-09-01T10:00:00Z
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" non-blocking
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"[inert-github-token] issue create"* ]]
  [[ "$output" != *"[elevated-pat] issue create"* ]]
  # The dedupe read has to use it too, or the step leaks the elevated token to a call it
  # does not need it for.
  [[ "$output" != *"[elevated-pat] issue list"* ]]
}

@test "handoff decision: when the label cannot be added, the follow-up is filed at once" {
  # No label means no merge-time catch. Filing now beats dropping.
  export STUB_LABEL_FAILS=true
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" non-blocking
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Could not mark PR #12"* ]]
  run calls
  [[ "$output" == *"[inert-github-token] issue create --repo o/r --title [review-followup] Non-blocking findings on PR #12"* ]]
  [[ "$output" != *"[steward-handoff]"* ]]
  body="$(cat "$WORK"/tmp/review-followup-body.md)"
  [[ "$body" == *"could not be labelled"* ]]
}

@test "handoff decision: non-blocking on an already-MERGED pull request files now, titled for the merge" {
  export STUB_PR_STATE=MERGED STUB_MERGED_AT=2026-09-01T10:00:00Z
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" non-blocking
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"pr edit"* ]]
  [[ "$output" == *"--title [review-followup] Non-blocking findings on merged PR #12"* ]]
  body="$(cat "$WORK"/tmp/review-followup-body.md)"
  [[ "$body" == *"already merged"* ]]
  [[ "$body" == *"2026-09-01T10:00:00Z"* ]]
}

@test "handoff decision: the re-aimed title states the verdict it actually read" {
  # It used to say "Blocking findings" whatever the verdict was; an issue filed that way
  # was closed with "there is nothing to land". `Blocking` only for `blocking`.
  export STUB_PR_STATE=MERGED STUB_MERGED_AT=2026-09-01T10:00:00Z
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" blocking
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"--title [review-followup] Blocking findings on merged PR #12"* ]]
  [[ "$output" != *"[steward-handoff]"* ]]
  [[ "$output" == *"[inert-github-token] issue create"* ]]

  for raw in undecided "" merge; do
    run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" "$raw"
    [ "$status" -eq 0 ]
    run calls
    [[ "$output" == *"--title [review-followup] Unsettled findings on merged PR #12"* ]] \
      || { echo "[$raw]: $output"; return 1; }
    [[ "$output" != *"Blocking findings"* ]]
  done

  # A closed, unmerged pull request has no branch to push to either, and says so.
  export STUB_PR_STATE=CLOSED STUB_MERGED_AT=
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" blocking
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"--title [review-followup] Blocking findings on closed PR #12"* ]]
}

@test "handoff decision: UNDECIDED wakes the steward" {
  # A missing answer must never read as "nothing to do".
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" undecided
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"[steward-handoff]"* ]]
}

@test "handoff decision: a MISSING verdict file wakes the steward" {
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" ""
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"[steward-handoff]"* ]]
}

@test "handoff decision: an UNRECOGNISED verdict wakes the steward" {
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" "merge"
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"[steward-handoff]"* ]]
}

@test "handoff decision: the issue says WHICH verdict woke the steward" {
  # A deliberate "this must be fixed before merge" and the fail-safe firing on a referee
  # that wrote nothing call for very different amounts of trust in what follows. A reader
  # who cannot tell them apart learns to treat every handoff as noise.
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" blocking
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK"/tmp/steward-handoff-body.md)" == *"merge verdict was **blocking**"* ]]

  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" ""
  [ "$status" -eq 0 ]
  [[ "$(cat "$WORK"/tmp/steward-handoff-body.md)" == *"no usable merge verdict"* ]]
}

@test "handoff decision: a human-authored branch gets no handoff" {
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" blocking success "feature/mine"
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]
}

@test "handoff decision: nothing collected AND the collector succeeded — silent, by design" {
  # The lost-review check in the review job owns this case and has already filed for it.
  # A second issue here would be a duplicate pointing at the same cause.
  run run_handoff "" "" blocking success
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]
  [[ "$output" != *"pr comment"* ]]
}

@test "handoff decision: nothing collected because the collector FAILED — says so ON THE PR" {
  # THE HOLE. Identical on disk to the case above, opposite meaning: the reviews are on the
  # pull request with real findings, the lost-review check saw them and correctly filed
  # nothing, and this step used to exit 0 and wake nobody.
  run run_handoff "" "" "" failure
  [ "$status" -eq 0 ]
  [[ "$output" == *"::error::"* ]]
  run calls
  [[ "$output" == *"pr comment"* ]]
  [[ "$output" != *"issue create"* ]]
}

@test "handoff decision: the broken-handoff notice says the findings have no listener" {
  # A notice that only says "a step failed" reads as infrastructure noise and gets skipped.
  # It has to say what the reader now owns.
  run run_handoff "" "" "" failure
  [ "$status" -eq 0 ]
  body="$(cat "$WORK"/tmp/handoff-broken.md)"
  [[ "$body" == *"not a verdict on the change"* ]]
  [[ "$body" == *"Read them"* ]]
  [[ "$body" == *"before merging"* ]]
}

@test "handoff decision: an already-open handoff issue is not filed twice" {
  export STUB_OPEN_TITLES="[steward-handoff] Review findings on PR #12"
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" blocking
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]
}

@test "handoff decision: a near-miss title does NOT suppress a real handoff" {
  # The dedupe is exact and whole-line for this reason: GitHub's search tokenises, so
  # "PR #1" can match "PR #12" and silently suppress the handoff this step exists to file.
  export STUB_OPEN_TITLES="[steward-handoff] Review findings on PR #1"
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" blocking
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"issue create"* ]]
}

@test "handoff decision: an already-open FOLLOW-UP issue is not filed twice either" {
  # The non-blocking branch needs its own dedupe: `ready_for_review` re-fires this whole
  # job, and a second identical follow-up is noise on an issue tracker the operator reads.
  export STUB_PR_STATE=MERGED STUB_MERGED_AT=2026-09-01T10:00:00Z
  export STUB_OPEN_TITLES="[review-followup] Non-blocking findings on merged PR #12"
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" non-blocking
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]
}

# ---------------------------------------------------------------------------
# THE SPENT-ALLOWANCE CARVE-OUT, executed. The job log was read ONCE in the step above
# this one and arrives as QUOTA_LINE_FROM_LOG; this step never fetches it again.
# ---------------------------------------------------------------------------

@test "handoff decision: a spent allowance on the missing reviewer posts a notice, files nothing, wakes nobody" {
  export LOST_REVIEWER=challenge
  export QUOTA_LINE_FROM_LOG="Usage limit reached, resets at 04:00 UTC"
  run run_handoff "$REVIEW_BODY" "" ""
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]
  [[ "$output" == *"pr comment"* ]]
  body="$(cat "$WORK"/tmp/handoff-skipped-body.md)"
  [[ "$body" == "## The steward was not woken, and no issue was filed"* ]]
  [[ "$body" == *"challenge-role"* ]]
  [[ "$body" == *"Usage limit reached, resets at 04:00 UTC"* ]]
  [[ "$body" == *"A spent allowance refuses a re-run the same way until it resets. Waiting is the"* ]]
  [[ "$body" == *"not another run"* ]]
  [[ "$body" == *"reviewed once, not twice"* ]]
  [[ "$body" == *"draft and ready for review again"* ]]
}

@test "handoff decision: ANTI-VACUITY — an empty quota line files the handoff and says the cause is unknown" {
  # Both log fetches came back empty. The carve-out must not fire on nothing, and the
  # body has to tell the reader why this was filed rather than skipped.
  export LOST_REVIEWER=challenge
  export QUOTA_LINE_FROM_LOG=""
  run run_handoff "$REVIEW_BODY" "" ""
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"[elevated-pat] issue create"* ]]
  [[ "$output" == *"[steward-handoff]"* ]]
  body="$(cat "$WORK"/tmp/steward-handoff-body.md)"
  [[ "$body" == *"did"$'\n'"> not name a cause"* || "$body" == *"did not name a cause"* ]]
  [[ "$body" == *"cause is unknown"* ]]
}

@test "handoff decision: the literal verdict 'undecided' is never quota-skipped" {
  export LOST_REVIEWER=challenge
  export QUOTA_LINE_FROM_LOG="Usage limit reached"
  run run_handoff "$REVIEW_BODY" "" undecided
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"[steward-handoff]"* ]]
}

# ---------------------------------------------------------------------------
# EVERY FILED BODY EMBEDS THE FINDINGS and ends with the do-not-edit line. A body that
# only linked to the pull request cost one agent session per issue just to read them.
# ---------------------------------------------------------------------------

KEEP='**Do not edit this body** — comment instead, so the filed record survives.'

@test "bodies: the handoff embeds the referee comparison in a details block, and keeps the record" {
  printf '## Reviewer comparison\n\n- src/a.js:10 drops the error.\n' \
    > "$WORK/run/.review-artifacts/referee-comment.md"
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" blocking
  [ "$status" -eq 0 ]
  body="$(cat "$WORK"/tmp/steward-handoff-body.md)"
  [[ "$body" == *"<details><summary>"* ]]
  [[ "$body" == *"src/a.js:10 drops the error."* ]]
  [[ "$body" == *"</details>"* ]]
  [[ "$body" == *"$KEEP" ]]
}

@test "bodies: an unreadable comparison becomes a warning block, never a silent omission" {
  rm -f "$WORK/run/.review-artifacts/referee-comment.md"
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" blocking
  [ "$status" -eq 0 ]
  body="$(cat "$WORK"/tmp/steward-handoff-body.md)"
  [[ "$body" == *"> [!WARNING]"* ]]
  [[ "$body" == *"could not be read"* ]]
  [[ "$body" == *"$KEEP" ]]
}

@test "bodies: the follow-up and the re-aimed follow-up embed the findings too" {
  printf '## Reviewer comparison\n\nFINDING-MARKER-42\n' > "$WORK/run/.review-artifacts/referee-comment.md"
  export STUB_PR_STATE=MERGED STUB_MERGED_AT=2026-09-01T10:00:00Z
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" non-blocking
  [ "$status" -eq 0 ]
  body="$(cat "$WORK"/tmp/review-followup-body.md)"
  [[ "$body" == *"FINDING-MARKER-42"* ]]
  [[ "$body" == *"$KEEP" ]]

  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" blocking
  [ "$status" -eq 0 ]
  body="$(cat "$WORK"/tmp/review-reaim-body.md)"
  [[ "$body" == *"FINDING-MARKER-42"* ]]
  [[ "$body" == *"merge verdict was **blocking**"* ]]
  [[ "$body" == *"$KEEP" ]]
}

@test "bodies: the handoff lists every inline thread the fixer has to resolve" {
  printf '[{"reviewer":"judge","id":501,"html_url":"https://e.invalid/pr/12#discussion_r501","path":"src/a.js","line":10}]\n' \
    > "$WORK/run/.review-artifacts/inline-threads.json"
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" blocking
  [ "$status" -eq 0 ]
  body="$(cat "$WORK"/tmp/steward-handoff-body.md)"
  [[ "$body" == *"Inline review threads to resolve"* ]]
  [[ "$body" == *'`src/a.js:10`'* ]]
  [[ "$body" == *"discussion_r501"* ]]
  [[ "$body" == *"thread 501"* ]]
}

@test "bodies: no inline threads means no thread section — the body does not promise what is not there" {
  rm -f "$WORK/run/.review-artifacts/inline-threads.json"
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" blocking
  [ "$status" -eq 0 ]
  body="$(cat "$WORK"/tmp/steward-handoff-body.md)"
  [[ "$body" != *"Inline review threads to resolve"* ]]
}

@test "handoff decision: a review that posted nothing is not counted as a review" {
  # The collector writes an empty result as a lone newline. Counting that as a review that
  # landed would let a pull request nobody reviewed reach the verdict branch at all.
  printf '\n' > "$WORK/run/.review-artifacts/challenge.md"
  run run_handoff "$REVIEW_BODY" "" blocking
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"issue create"* ]]
}
