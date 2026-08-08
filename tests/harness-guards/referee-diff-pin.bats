#!/usr/bin/env bats
#
# Gate 22 guard — ALL THREE REVIEW JOBS READ THE SAME COMMIT.
#
# THE FIRST LESSON. The referee fetched the diff with "give me this pull request's diff",
# which resolves the head at the moment it runs. The two reviews it compares were written
# earlier, against whatever the head was then, and nothing tied them together. So a fix
# pushed in between made the reviewer who found the bug look wrong: the referee measured
# the FIX and scored it against the finding that produced it. It bites precisely when an
# author fixes findings as they arrive — THE MORE RESPONSIVE THE AUTHOR, THE MORE LIKELY
# THEIR REVIEWERS ARE MARKED DOWN — and the referee's comment is the last word on the page.
#
# THE SECOND LESSON, which the first one exposed. The two REVIEWERS had the same problem
# with each other. `challenge-review` declares `needs: review`, so it starts strictly
# later; each reviewer asking for "the current diff" could read a different commit, and
# the referee would compare them as though they had read the same one. "Both reviewers
# found this" and "only one reviewer found this" are both meaningless in that case, and
# NOTHING IN THE OUTPUT WOULD LOOK WRONG. Two blind spots that overlap by accident are
# indistinguishable from two blind spots that genuinely agree.
#
# So the invariant is not "a fresh diff" — it is THE SAME diff, three times:
#
#   PINNED    — one shared script, one compare range, from event-payload shas that are
#               fixed when the run is triggered. The checkout is pinned to the same sha,
#               so the tree agrees with the diff.
#   DISCLOSED — when the live head has moved past the pinned one, the comparison says its
#               verdicts describe the reviewed commit. In its OWN step, so posting stays
#               a plain "send the file" and cannot grow a reason to send nothing.
#   TOLD      — all three prompts say the diff is pinned; the referee's adds that a
#               finding which looks already fixed is usually a reviewer being right.
#
# BEHAVIOURAL: the assertions below run tools/fetch-pinned-diff.sh against a stubbed `gh`,
# because "asks for the pinned range" and "asks for the live head" are two calls that look
# almost identical in a file and behave completely differently.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"
FETCH="$REPO_ROOT/tools/fetch-pinned-diff.sh"
PROMPT="$REPO_ROOT/.agents/prompts/review-referee.md"
JUDGE_PROMPT="$REPO_ROOT/.agents/prompts/review-judge.md"
CHALLENGE_PROMPT="$REPO_ROOT/.agents/prompts/review-challenge.md"

setup() {
  WORK="$(mktemp -d)"
  export WORK
  mkdir -p "$WORK/bin" "$WORK/run"

  # A stubbed `gh` that records every argv line and answers the two calls the script makes.
  cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
case "$*" in
  *"/compare/"*)
    [ "${STUB_COMPARE_FAILS:-false}" = true ] && exit 1
    echo "diff --git a/x b/x"
    ;;
  *"/pulls/"*)
    [ "${STUB_LIVE_FAILS:-false}" = true ] && exit 1
    printf '%s\n' "$STUB_LIVE_SHA"
    ;;
esac
exit 0
STUB
  chmod +x "$WORK/bin/gh"
}

teardown() { rm -rf "$WORK"; }

PINNED_HEAD="headsha0000000000000000000000000000000"
PINNED_BASE="basesha0000000000000000000000000000000"

# $1 live head the stub reports; $2 compare fails; $3 live lookup fails; $4 extra args
run_fetch() {
  ( cd "$WORK/run" \
    && PATH="$WORK/bin:$PATH" \
       GH_CALLS="$WORK/calls.txt" \
       STUB_LIVE_SHA="${1:-$PINNED_HEAD}" \
       STUB_COMPARE_FAILS="${2:-false}" \
       STUB_LIVE_FAILS="${3:-false}" \
       bash "$FETCH" \
         --repo o/r --pr 12 \
         --base "$PINNED_BASE" --head "$PINNED_HEAD" \
         --out .review-artifacts/diff.patch ${4:-} )
}

calls() { cat "$WORK/calls.txt"; }

@test "pinned diff: the script exists and is executable" {
  [ -x "$FETCH" ]
}

@test "pinned diff: the diff is fetched for the PINNED base...head range" {
  run run_fetch
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"repos/o/r/compare/${PINNED_BASE}...${PINNED_HEAD}"* ]]
}

@test "pinned diff: the LIVE diff is never asked for" {
  # `gh pr diff` is the bug: it resolves the head now, not the head the reviews read.
  run run_fetch
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"pr diff"* ]]
  run grep -c 'gh pr diff' "$REVIEW"
  [ "$output" -eq 0 ]
}

@test "pinned diff: the compare request asks for the diff media type, not JSON" {
  # Without the Accept header this writes a JSON object into diff.patch and the reviewer
  # reads a blob of metadata while everything still looks green.
  run run_fetch
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"vnd.github.v3.diff"* ]]
}

@test "pinned diff: a missing --head is a LOUD usage error, never a silent default" {
  # A default of "whatever is current" would reintroduce the bug invisibly — the output
  # file would still be a perfectly valid diff.
  run env PATH="$WORK/bin:$PATH" GH_CALLS="$WORK/calls.txt" bash "$FETCH" \
    --repo o/r --pr 12 --base "$PINNED_BASE" --out "$WORK/run/d.patch"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--head is required"* ]]
}

@test "pinned diff: no note is written when the head has NOT moved" {
  # A note on every comparison is a note nobody reads.
  run run_fetch "$PINNED_HEAD" false false "--note-file .review-artifacts/head-moved.md"
  [ "$status" -eq 0 ]
  [ ! -s "$WORK/run/.review-artifacts/head-moved.md" ]
}

@test "pinned diff: a note IS written when the head has moved" {
  run run_fetch "newersha000000000000000000000000000000" false false "--note-file .review-artifacts/head-moved.md"
  [ "$status" -eq 0 ]
  [ -s "$WORK/run/.review-artifacts/head-moved.md" ]
  run cat "$WORK/run/.review-artifacts/head-moved.md"
  [[ "$output" == *"the commit they"* ]]
  # Both shas named, short form, so the reader can check for themselves.
  [[ "$output" == *"headsha"* ]]
  [[ "$output" == *"newersh"* ]]
  # And it must say WHY a finding may look absent — otherwise the note reads as
  # "these verdicts are stale", which is the opposite of the point.
  [[ "$output" == *"because of"* ]]
}

@test "pinned diff: no note file is asked for, no live lookup happens" {
  # A reviewer does not need to know: it reviews the pinned commit and says so. Looking
  # anyway would be a needless API call on every review job in the repository.
  run run_fetch
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"/pulls/12"* ]]
}

@test "pinned diff: an unreadable live head is not treated as a moved head" {
  # Guessing "moved" from a failed lookup puts a caveat on a comparison that needs none.
  run run_fetch "" false true "--note-file .review-artifacts/head-moved.md"
  [ "$status" -eq 0 ]
  [ ! -s "$WORK/run/.review-artifacts/head-moved.md" ]
}

@test "pinned diff: a failed compare degrades to an empty diff, never a failed job" {
  # Same rule as every other optional input here: degrade loudly, never cancel.
  run run_fetch "$PINNED_HEAD" true
  [ "$status" -eq 0 ]
  [ -f "$WORK/run/.review-artifacts/diff.patch" ]
  [ ! -s "$WORK/run/.review-artifacts/diff.patch" ]
  [[ "$output" == *"::warning::"* ]]
}

# ---------------------------------------------------------------------------
# The workflow wiring: same script, same shas, three jobs.
# ---------------------------------------------------------------------------

job_block() { # job-name
  awk -v job="  $1:" '
    $0 == job          { injob = 1; print; next }
    injob && /^  [^ ]/ { exit }
    injob              { print }
  ' "$REVIEW"
}

@test "same commit: all three jobs fetch the diff through the one shared script" {
  # Three copies of the fetch is three places for one of them to drift back to the live
  # head, and the drift would be invisible in every output.
  for job in review challenge-review referee; do
    run grep -q 'tools/fetch-pinned-diff.sh' <<<"$(job_block "$job")"
    if [ "$status" -ne 0 ]; then
      echo "# job '$job' does not use tools/fetch-pinned-diff.sh"
      false
    fi
  done
}

@test "same commit: every job passes the event payload's shas, not a recomputed head" {
  # `github.event.pull_request.head.sha` is fixed when the run is triggered. Anything
  # resolved later can differ per job, which is the whole bug.
  run grep -c 'github.event.pull_request.head.sha' "$REVIEW"
  [ "$output" -ge 6 ]   # 3 checkouts + 3 fetches
  run grep -c 'github.event.pull_request.base.sha' "$REVIEW"
  [ "$output" -ge 3 ]
}

@test "same commit: every checkout is pinned to the reviewed commit, not the merge ref" {
  # A `pull_request` checkout defaults to the MERGE ref, which is recomputed as the base
  # branch moves — so two jobs in one run can check out different trees.
  run grep -c 'ref: ${{ github.event.pull_request.head.sha }}' "$REVIEW"
  [ "$output" -eq 3 ]
  # And no checkout is left on the default.
  run grep -c 'name: Checkout repository' "$REVIEW"
  [ "$output" -eq 0 ]
}

@test "same commit: caveats are prepended by their OWN step, not by the posting step" {
  # Posting must stay a plain "send the file". Every time a posting step grows a
  # condition, it grows a path where it sends nothing and still goes green.
  run grep -q 'name: Prepend any caveats the comparison has to carry' "$REVIEW"
  [ "$status" -eq 0 ]
  post_block="$(awk '/^      - name: Post the comparison/ { p = 1 } p' "$REVIEW")"
  [[ "$post_block" != *"head-moved.md"* ]]
  [[ "$post_block" != *"sha-mismatch.md"* ]]
}

@test "same commit: a caveat is never a reason to suppress the comparison" {
  # Both caveats say something IS wrong with the comparison. Neither may delete it — the
  # comparison is still the only place the two reviews are sorted, and a silenced referee
  # loses that as well as the caveat.
  block="$(awk '/^      - name: Prepend any caveats/, /^      - name: Post the comparison/' "$REVIEW")"
  [ -n "$block" ]
  [[ "$block" != *"rm "* ]]
  [[ "$block" == *"never a reason to suppress"* ]]
}

# ---------------------------------------------------------------------------
# The stamp: turning "we handed them the same diff" into "they say they read it".
# ---------------------------------------------------------------------------

@test "stamp: the fetch publishes the reviewed sha for the reviewer to copy" {
  run grep -q 'reviewed-commit.txt' "$REPO_ROOT/tools/fetch-pinned-diff.sh"
  [ "$status" -eq 0 ]
}

@test "stamp: the published sha is the short form of the PINNED head, not something re-derived" {
  # It has to be the head this script was told to fetch. Deriving it from the checkout or
  # from the API would let it drift from the diff it sits next to, which is the entire bug.
  block="$(grep -A1 'reviewed-commit.txt' "$REPO_ROOT/tools/fetch-pinned-diff.sh" || true)"
  run grep -q 'printf .%.7s. "\$HEAD".*reviewed-commit.txt' "$REPO_ROOT/tools/fetch-pinned-diff.sh"
  [ "$status" -eq 0 ]
}

@test "stamp: both reviewer prompts require the sha on the second line" {
  for p in "$JUDGE_PROMPT" "$CHALLENGE_PROMPT"; do
    run grep -q 'reviewed-commit: X' "$p"
    if [ "$status" -ne 0 ]; then
      echo "# $p does not require the reviewed-commit stamp"
      false
    fi
    run grep -q 'reviewed-commit.txt' "$p"
    [ "$status" -eq 0 ]
  done
}

@test "stamp: the referee COMPARES the two stamps rather than assuming they agree" {
  # The whole point. Pinning the fetch makes the two reviews *ought* to match; this is what
  # makes "they matched" a fact rather than an intention.
  block="$(job_block referee)"
  run grep -q 'sha_of()' <<<"$block"
  [ "$status" -eq 0 ]
  run grep -q 'JUDGE_SHA" != "\$CHALLENGE_SHA' <<<"$block"
  [ "$status" -eq 0 ]
}

@test "stamp: a MISMATCH is an error and lands on the pull request" {
  # Two reviews of two different commits produce a perfectly well-formed comparison whose
  # agreement sections are meaningless. Invisible in every other signal, so it has to be
  # said where the person merging will see it.
  block="$(job_block referee)"
  run grep -q '::error::The two reviews describe DIFFERENT commits' <<<"$block"
  [ "$status" -eq 0 ]
  run grep -q 'sha-mismatch.md' <<<"$block"
  [ "$status" -eq 0 ]
}

@test "stamp: a MISSING stamp warns but does not block the comparison" {
  # Absent is not false. An unstamped review leaves the claim unverified, which is a
  # weaker state than "these disagree" and must not be treated as the same thing.
  block="$(job_block referee)"
  run grep -q 'the same-commit check could not run' <<<"$block"
  [ "$status" -eq 0 ]
  [[ "$block" == *'elif [ -z "$JUDGE_SHA" ] || [ -z "$CHALLENGE_SHA" ]'* ]]
}

@test "stamp: the marker line the collector matches on is UNCHANGED" {
  # The stamp is a SECOND line, deliberately. Folding the sha into the role marker would
  # break every `contains("<!-- reviewer: judge -->")` selection at once — the collector,
  # the lost-review check and the referee's split all key on that exact string.
  run grep -c 'contains("<!-- reviewer: judge -->")' "$REVIEW"
  [ "$output" -ge 2 ]
  run grep -cE '<!-- reviewer: (judge|challenge) [^-]' "$REVIEW"
  [ "$output" -eq 0 ]
}

@test "same commit: only the referee asks for the moved-head note" {
  run grep -c -- '--note-file' "$REVIEW"
  [ "$output" -eq 1 ]
  run grep -q -- '--note-file' <<<"$(job_block referee)"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# The prompts: pinning the fetch is not enough if the agent reads elsewhere.
# ---------------------------------------------------------------------------

@test "told: both reviewer prompts name the pinned diff file" {
  for p in "$JUDGE_PROMPT" "$CHALLENGE_PROMPT"; do
    run grep -q '.review-artifacts/diff.patch' "$p"
    if [ "$status" -ne 0 ]; then
      echo "# $p does not tell the reviewer which diff to read"
      false
    fi
    run grep -qi 'pinned' "$p"
    [ "$status" -eq 0 ]
  done
}

@test "told: the referee prompt says the diff is pinned to the reviewed commit" {
  # Pinning the fetch alone is not enough — the referee reads the repository too.
  run grep -qi 'pinned to the exact commit' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "told: the referee prompt says an already-fixed finding is the reviewer being RIGHT" {
  # The actual failure. Without this the referee marks down exactly the reviewers whose
  # findings were acted on fastest.
  run grep -qi 'never evidence the reviewer was wrong' "$PROMPT"
  [ "$status" -eq 0 ]
  run grep -qi 'pinned diff itself shows the fix' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "told: no prompt claims the checked-out tree may be newer than the diff" {
  # It was, before the checkouts were pinned. A false statement in a prompt is worse than
  # a missing one: the next agent inherits the bad reasoning along with the rule.
  for p in "$PROMPT" "$JUDGE_PROMPT" "$CHALLENGE_PROMPT"; do
    run grep -qiE 'tree (around you |checked out )?may be (\*\*)?newer' "$p"
    if [ "$status" -eq 0 ]; then
      echo "# $p still claims the working tree may be newer than the pinned diff"
      false
    fi
  done
}
