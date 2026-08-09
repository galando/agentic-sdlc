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
  # is open unless a test says otherwise.
  cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# The token is recorded alongside the call, because WHICH token files the issue is the
# whole difference between "wake the steward" and "leave the pull request alone".
printf '[%s] %s\n' "${GH_TOKEN:-unset}" "$*" >> "$GH_CALLS"
case "$1 $2" in
  "issue list") printf '%s\n' "${STUB_OPEN_TITLES:-}" ;;
  "issue create") [ "${STUB_ISSUE_FAILS:-false}" = true ] && exit 1 ;;
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
  # ...but the findings are still filed. Dropping them is the stranded-finding failure
  # this machinery exists to prevent, arriving through the front door.
  [[ "$output" == *"[review-followup]"* ]]
}

@test "handoff decision: THE TOKEN IS THE SWITCH — the follow-up is filed with the inert one" {
  # GitHub does not start workflow runs from events created with GITHUB_TOKEN, and the
  # steward auto-invokes on `issues.opened`. Filing this with the PAT instead would wake it
  # for exactly the findings the verdict just said not to wake it for — and nothing else
  # in the workflow would look any different.
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" non-blocking
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"[inert-github-token] issue create"* ]]
  [[ "$output" != *"[elevated-pat] issue create"* ]]
  # The dedupe read has to use it too, or the step leaks the elevated token to a call it
  # does not need it for.
  [[ "$output" != *"[elevated-pat] issue list"* ]]
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
  export STUB_OPEN_TITLES="[review-followup] Non-blocking findings on PR #12"
  run run_handoff "$REVIEW_BODY" "$REVIEW_BODY" non-blocking
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"issue create"* ]]
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
