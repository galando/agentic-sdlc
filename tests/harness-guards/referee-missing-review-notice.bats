#!/usr/bin/env bats
#
# Gate 22 guard — the "one review missing" notice must agree with itself about HOW MANY
# reviews were lost.
#
# THE LESSON. The notice was built by splicing a noun into a fixed sentence:
#
#     MISSING="the judge-role review"
#     [ both missing ] && MISSING="BOTH reviews"
#     echo "::warning::Referee found only one review - $MISSING did not reach this PR."
#     echo "That did not happen: **$MISSING** is not on this pull request"
#     echo "Treat this pull request as having had **one reviewer at most**."
#
# When both reviews were missing that rendered three contradictions at once, seen live:
# a plural spliced into a sentence written for a singular ("**BOTH reviews** is not on this
# pull request"); a log line claiming one review was found when none were; and "one reviewer
# at most" used to describe ZERO, which reads as one.
#
# WHY IT MATTERS MORE THAN A TYPO. This notice is the ONLY thing telling a reader that a
# green check does not mean "reviewed twice". Its entire job is to be right about the count.
# A reader who skims "one reviewer at most" on an unreviewed pull request has been told the
# opposite of the truth by the safety net itself.
#
# THE FIX is a whole sentence per case rather than a noun in a hole — which is also why this
# guard runs the real code instead of matching strings: the failure was in how three
# fragments composed, and every fragment was individually fine.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"

# The notice block, from the missing-review test to the end of its `{ ... }` group.
#
# The terminator rule comes FIRST on purpose. awk applies rules in order against a `$0` that
# earlier rules may already have rewritten, so dedenting before testing made the terminator
# never match — and the extraction then ran on to the end of the step and swallowed the
# steward handoff as part of the notice.
extract_notice() {
  awk '
    /if \[ "\$JUDGE_BYTES" -le 1 \] \|\| \[ "\$CHALLENGE_BYTES" -le 1 \]; then/ { inblock = 1 }
    inblock && /^            } > \.review-artifacts\/referee-comment\.md/ {
      sub(/^          /, ""); print; exit
    }
    inblock { sub(/^          /, ""); print }
  ' "$REVIEW"
}

setup() {
  WORK="$(mktemp -d)"
  export WORK
  mkdir -p "$WORK/.review-artifacts"
  extract_notice > "$WORK/notice.sh"
  [ -s "$WORK/notice.sh" ]
  grep -q 'Reviewer comparison - not available' "$WORK/notice.sh"
}

teardown() { rm -rf "$WORK"; }

# $1 judge bytes, $2 challenge bytes. >1 means "this review landed".
run_notice() {
  ( cd "$WORK" \
    && JUDGE_BYTES="$1" CHALLENGE_BYTES="$2" \
       RUN_URL="https://example.invalid/run/1" \
       GITHUB_OUTPUT="$WORK/gh-output" \
       bash -c "set -euo pipefail"$'\n'"$(cat "$WORK/notice.sh")"$'\n'"fi" )
  # The trailing `fi` closes the extracted `if`, on its OWN line: command substitution
  # strips the trailing newline, so appending " fi" put it on the same line as the block's
  # closing brace and bash rejected the whole script.
}

body() { cat "$WORK/.review-artifacts/referee-comment.md"; }

@test "notice: neither review landed — the body never says 'one reviewer'" {
  # The exact live failure. Zero reviews described as "one reviewer at most".
  run run_notice 1 1
  [ "$status" -eq 0 ]
  run body
  [[ "$output" == *"Neither review"* ]]
  [[ "$output" == *"no automated review at all"* ]]
  [[ "$output" != *"one reviewer at most"* ]]
  [[ "$output" != *"one reviewer,"* ]]
}

@test "notice: neither review landed — the log line does not claim one was found" {
  run run_notice 1 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" != *"found only one review"* ]]
  [[ "$output" == *"neither review reached this PR"* ]]
}

@test "notice: neither review landed — no plural is spliced into a singular sentence" {
  # "**BOTH reviews** is not on this pull request" — the sentence that gave this away.
  run run_notice 1 1
  [ "$status" -eq 0 ]
  run body
  [[ "$output" != *"reviews** is not"* ]]
  [[ "$output" != *"reviews is not"* ]]
}

@test "notice: only the challenge review is missing — it is named, and the count is one" {
  run run_notice 500 1
  [ "$status" -eq 0 ]
  run body
  [[ "$output" == *"The challenge-role review"* ]]
  [[ "$output" == *"one reviewer"* ]]
  [[ "$output" != *"Neither review"* ]]
  [[ "$output" != *"no automated review at all"* ]]
}

@test "notice: only the judge review is missing — it is named, and the count is one" {
  run run_notice 1 500
  [ "$status" -eq 0 ]
  run body
  [[ "$output" == *"The judge-role review"* ]]
  [[ "$output" == *"one reviewer"* ]]
  [[ "$output" != *"Neither review"* ]]
}

@test "notice: every case names which review is missing, and says it in one sentence" {
  # Whichever branch runs, the reader must learn WHICH one is gone. A notice that says only
  # "a review is missing" sends them to compare two comment threads by hand.
  for pair in "1 1" "500 1" "1 500"; do
    # shellcheck disable=SC2086
    run run_notice $pair
    [ "$status" -eq 0 ]
    run body
    [[ "$output" == *"nothing to compare"* ]]
    [[ "$output" == *"nobody caught"* ]]
  done
}

@test "notice: the count words come from whole sentences, not a spliced noun" {
  # The construct itself. A single MISSING= variable dropped into a fixed sentence is what
  # made three different renderings wrong at once, and it reads perfectly in the file.
  run grep -q 'MISSING=' "$REVIEW"
  [ "$status" -ne 0 ]
  run grep -c 'SENTENCE=' "$REVIEW"
  [ "$output" -eq 3 ]
  run grep -c 'REMAINS=' "$REVIEW"
  [ "$output" -eq 3 ]
}
