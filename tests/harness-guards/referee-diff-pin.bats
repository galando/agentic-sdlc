#!/usr/bin/env bats
#
# Gate 22 guard — the referee judges the reviews against THE COMMIT THEY WERE WRITTEN FOR.
#
# THE LESSON. The referee fetched the diff with `gh pr diff`, which resolves the pull
# request's head at the moment the referee runs. The two reviews it compares were written
# earlier, against whatever the head was then, and nothing tied them together.
#
# So a fix pushed between a review and this job made the reviewer who found the bug look
# wrong: the referee measured the FIX and scored it against the finding that produced it.
# Observed ruling two accurate reviewers wrong at once — it read a head two commits newer
# than one review and one newer than the other, then accused a reviewer of miscounting
# lines that really were that many in the commit it had read.
#
# The window is usually seconds, which is why nobody saw it. It bites precisely when an
# author fixes findings as they arrive, so THE MORE RESPONSIVE THE AUTHOR, THE MORE LIKELY
# THEIR REVIEWERS ARE MARKED DOWN. And the referee's comment is the last word on the page,
# so a reviewer who was right is recorded as wrong.
#
# Three parts, and all three are needed:
#
#   PINNED    — the diff comes from a compare between the event payload's base and head
#               shas, which are fixed when the run is triggered.
#   DISCLOSED — when the live head has moved past the pinned one, a note says the verdicts
#               describe the reviewed commit. In its OWN step, so posting stays a plain
#               "send the file" and cannot grow a reason to send nothing.
#   TOLD      — the prompt says the diff is pinned and that a finding which looks already
#               fixed is usually a reviewer being right. Pinning the diff alone would not
#               stop the referee reaching the same conclusion from the checked-out tree,
#               which it also reads.
#
# BEHAVIOURAL, like review-collector.bats: the extracted step is run against a stubbed
# `gh`, because "asks for the pinned range" and "asks for the live head" are two API calls
# that look almost identical in the file and behave completely differently.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"
PROMPT="$REPO_ROOT/.agents/prompts/review-referee.md"

# The `run:` body of the diff-fetch step, dedented. Same terminator rule as
# steward-handoff-closure.bats: a block scalar ends at the first non-blank line that is not
# indented into it, and NOT at the next `- name:` — a comment banner at that indent would
# run the extraction on to the end of the file.
extract_fetch_step() {
  awk '
    /^      - name: Fetch the diff both reviewers were reading/ { instep = 1; next }
    instep && !inrun && /^      [^ ]/ { exit }
    instep && /^        run: \|/ { inrun = 1; next }
    inrun && NF && !/^          / { exit }
    inrun { sub(/^          /, ""); print }
  ' "$REVIEW"
}

setup() {
  WORK="$(mktemp -d)"
  export WORK
  extract_fetch_step > "$WORK/fetch.sh"
  # An empty extraction would make every assertion below pass for the wrong reason.
  [ -s "$WORK/fetch.sh" ]
  grep -q 'diff.patch' "$WORK/fetch.sh"

  mkdir -p "$WORK/bin" "$WORK/run/.review-artifacts"

  # A stubbed `gh` that records every argv line and answers the two calls the step makes.
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

# $1 live head sha the stub reports; $2/$3 optional failure switches
run_fetch() {
  ( cd "$WORK/run" \
    && PATH="$WORK/bin:$PATH" \
       GH_CALLS="$WORK/calls.txt" \
       STUB_LIVE_SHA="${1:-headsha0000000000000000000000000000000}" \
       STUB_COMPARE_FAILS="${2:-false}" \
       STUB_LIVE_FAILS="${3:-false}" \
       REPO="o/r" PR="12" \
       BASE_SHA="basesha0000000000000000000000000000000" \
       HEAD_SHA="headsha0000000000000000000000000000000" \
       bash "$WORK/fetch.sh" )
}

calls() { cat "$WORK/calls.txt"; }

@test "diff pin: the diff is fetched for the PINNED base...head range" {
  run run_fetch
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"repos/o/r/compare/basesha0000000000000000000000000000000...headsha0000000000000000000000000000000"* ]]
}

@test "diff pin: the LIVE diff is never asked for" {
  # `gh pr diff` is the bug. It resolves the head now, not the head the reviews read.
  run run_fetch
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" != *"pr diff"* ]]
}

@test "diff pin: the compare request asks for diff media type, not JSON" {
  # Without the Accept header this writes a JSON object into diff.patch and the referee
  # rules on a blob of metadata while everything still looks green.
  run run_fetch
  [ "$status" -eq 0 ]
  run calls
  [[ "$output" == *"vnd.github.v3.diff"* ]]
}

@test "diff pin: no note is written when the head has NOT moved" {
  # A note on every comparison is a note nobody reads.
  run run_fetch "headsha0000000000000000000000000000000"
  [ "$status" -eq 0 ]
  [ ! -s "$WORK/run/.review-artifacts/head-moved.md" ]
}

@test "diff pin: a note IS written when the head has moved" {
  run run_fetch "newersha000000000000000000000000000000"
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

@test "diff pin: an unreadable live head is not treated as a moved head" {
  # Guessing "moved" from a failed lookup puts a caveat on a comparison that needs none.
  run run_fetch "" false true
  [ "$status" -eq 0 ]
  [ ! -s "$WORK/run/.review-artifacts/head-moved.md" ]
}

@test "diff pin: a failed compare degrades to an empty diff, never a failed job" {
  # Same rule as every other optional input here: degrade loudly, never cancel. The referee
  # falls back to the checked-out tree.
  run run_fetch "headsha0000000000000000000000000000000" true
  [ "$status" -eq 0 ]
  [ -f "$WORK/run/.review-artifacts/diff.patch" ]
  [ ! -s "$WORK/run/.review-artifacts/diff.patch" ]
  [[ "$output" == *"::warning::"* ]]
}

@test "diff pin: the note is prepended by its OWN step, not by the posting step" {
  # Posting must stay a plain "send the file". Every time a posting step grows a condition,
  # it grows a path where it sends nothing and still goes green.
  run grep -q 'name: Note that the pull request moved after the reviews' "$REVIEW"
  [ "$status" -eq 0 ]
  post_block="$(awk '/^      - name: Post the comparison/ { p = 1 } p' "$REVIEW")"
  [[ "$post_block" != *"head-moved.md"* ]]
}

@test "diff pin: the prompt tells the referee the diff is pinned and the tree may be newer" {
  # Pinning the diff alone is not enough — the referee reads the repository too, so it can
  # reach the same wrong conclusion from the working tree.
  run grep -qi 'pinned to the exact commit' "$PROMPT"
  [ "$status" -eq 0 ]
  run grep -qi 'may be' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "diff pin: the prompt says an already-fixed finding is the reviewer being RIGHT" {
  # The actual failure. Without this the referee marks down exactly the reviewers whose
  # findings were acted on fastest.
  run grep -qi 'never evidence the reviewer was wrong' "$PROMPT"
  [ "$status" -eq 0 ]
  run grep -qi 'pinned diff itself shows the fix' "$PROMPT"
  [ "$status" -eq 0 ]
}
