#!/usr/bin/env bats
#
# Gate 22 guard — the referee RULES, and the workflow checks that it did.
#
# THE LESSON. The referee used to sort the two reviews and stop. Its prompt forbade it
# from saying who was right, and its output ended "neither review is authoritative, a
# human decides". Every disagreement became an operator decision — and most of them were
# not disagreements at all: one reviewer's silence, the same defect graded at two
# severities, two valid fixes for one bug. The genuine ones were nearly always questions
# of FACT about the code, which have an answer anyone can go and check.
#
# The self-grading objection to letting it rule is real — the referee runs the same
# `judge` role that wrote one of the reviews — and it is answered STRUCTURALLY rather
# than by abstaining. Four things make that answer work, and losing any one of them
# quietly turns the referee back into either a punt machine or a party grading its own
# paper:
#
#   1. It reads the CODE. The workflow fetches the diff for it; a referee ruling without
#      the diff is ruling on which reviewer it likes.
#   2. The burden of proof is ASYMMETRIC. A ruling for the judge role needs a quoted
#      file:line; a tie goes to the challenge role. Drop the asymmetry and one party is
#      grading its own paper again.
#   3. The ladder TERMINATES. Rung 4 always answers, so "I cannot settle this" is never
#      available — which is the only thing that makes "there is no unresolved section" a
#      rule the model can actually keep.
#   4. The output is CHECKED for punt language, and annotated rather than suppressed. A
#      prompt is a request, not a guarantee; and a referee silenced for punting loses the
#      comparison as well as the punt.
#
# Hand-written, like review-collector.bats: this is a lesson that arrived AFTER the
# extraction capture in pins.json, so no mechanical pin over the source string exists for
# it. pins.json's `referee-sorts-does-not-grade` entry still holds — the phrase it pins
# ("grading its own paper") survives in review.yml as the objection being answered, which
# is the accurate form of that lesson now.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"
PROMPT="$REPO_ROOT/.agents/prompts/review-referee.md"
RUNBOOK="$REPO_ROOT/docs/runbooks/multi-model-review.md"

@test "referee: the prompt tells it to settle disagreements, not only to sort them" {
  run grep -qiE 'settle (every|their|a) ' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "referee: 'a human decides' is not the prompt's closing instruction any more" {
  # The exact sentence the old referee ended every comparison with. If it comes back into
  # the prompt, every disagreement is an operator decision again.
  run grep -qi 'a human decides the rest' "$PROMPT"
  [ "$status" -ne 0 ]
  # And the prompt must forbid it explicitly, not merely omit it.
  run grep -qi 'never to end one with' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "referee: the burden of proof is asymmetric — a ruling for the judge role needs quoted evidence" {
  run grep -qi 'asymmetric' "$PROMPT"
  [ "$status" -eq 0 ]
  run grep -qiE 'no quoted .file:line. is not allowed|rule for reviewer B' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "referee: the ladder's last rung terminates, and it rules for the OTHER side" {
  # Rung 4 is what makes "you always have a verdict" true rather than aspirational, and it
  # must fall to the challenge role — a tie decided in the referee's own favour is exactly
  # the self-grading failure the asymmetry exists to prevent.
  run grep -qi 'Rule for reviewer B' "$PROMPT"
  [ "$status" -eq 0 ]
  run grep -qi 'always terminates' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "referee: the not-a-contradiction list is present, silence first" {
  # Without this bar, one reviewer's silence gets filed as a contradiction and the operator
  # is handed a decision about two reviewers who never disagreed.
  run grep -qi 'silence, not disagreement' "$PROMPT"
  [ "$status" -eq 0 ]
  run grep -qi 'different severities' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "referee: there is no escape-hatch section, and inventing one is forbidden" {
  run grep -q 'no section for unsettled disagreements' "$PROMPT"
  [ "$status" -eq 0 ]
  run grep -q 'must not invent one' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "referee: an uncertain finding is KEPT, never dismissed" {
  run grep -qi 'a dismissed real finding costs a defect' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "referee: the lone finding is still the most valuable thing on the page" {
  # The one rule the old referee got right, and the easiest to lose while rewriting the
  # rest of the prompt.
  run grep -qi 'not outvoted by the other reviewer' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "workflow: the diff is fetched for the referee by a plain script step" {
  # It settles disagreements against the code, so it has to be able to see the code — and
  # fetching it in a script rather than letting the agent do it keeps the agent unable to
  # choose WHICH code it rules on.
  #
  # Updated rather than deleted when the diff was PINNED to the reviewed commit: this now
  # asserts the compare range too, so it is stricter than the version it replaced. The
  # pinning behaviour itself lives in referee-diff-pin.bats.
  run grep -q 'gh api "repos/\$REPO/compare/\${BASE_SHA}\.\.\.\${HEAD_SHA}"' "$REVIEW"
  [ "$status" -eq 0 ]
  run grep -q '> .review-artifacts/diff.patch' "$REVIEW"
  [ "$status" -eq 0 ]
  run grep -q 'diff.patch' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "workflow: a failed diff fetch degrades, never fails the job" {
  # Same rule as every other optional input in this system: degrade loudly, never cancel.
  run grep -q 'the referee will verify against the checked-out tree instead' "$REVIEW"
  [ "$status" -eq 0 ]
}

@test "workflow: the referee's output is scanned for punt language before posting" {
  run grep -q 'Check the referee actually ruled' "$REVIEW"
  [ "$status" -eq 0 ]
  run grep -q 'PUNTS=' "$REVIEW"
  [ "$status" -eq 0 ]
}

@test "the punt scan actually matches the phrasings that caused this" {
  # Extract the real pattern from the workflow and run it. A pattern that no longer
  # matches "a human decides" is a check that has quietly stopped checking.
  pattern="$(sed -n "s/^ *PUNTS='\(.*\)'$/\1/p" "$REVIEW")"
  [ -n "$pattern" ]

  for punt in \
    "## Unresolved" \
    "### Needs a decision" \
    "## Open questions" \
    "## For the author to judge" \
    "Neither review is authoritative. A human decides." \
    "leave this to the operator"
  do
    run grep -Eiq -- "$pattern" <<<"$punt"
    if [ "$status" -ne 0 ]; then
      echo "# the punt scan does NOT catch: $punt"
      false
    fi
  done
}

@test "the punt scan does not trip on ordinary prose about an unresolved BUG" {
  # A false positive puts a "the referee broke its own rule" warning on top of a perfectly
  # good comparison, which trains the reader to ignore the warning that matters.
  pattern="$(sed -n "s/^ *PUNTS='\(.*\)'$/\1/p" "$REVIEW")"
  [ -n "$pattern" ]

  for ok in \
    "Verdict: the challenge role is right — the leak is unresolved in this diff." \
    "Both reviewers agree the open question in the issue is out of scope here."
  do
    run grep -Eiq -- "$pattern" <<<"$ok"
    if [ "$status" -eq 0 ]; then
      echo "# the punt scan FALSELY trips on: $ok"
      false
    fi
  done
}

@test "a punted comparison is annotated, never suppressed" {
  # Deleting the referee's output would lose the comparison as well as the punt. The
  # warning goes ON TOP and the original follows it.
  run grep -q 'cat .review-artifacts/referee-comment.md' "$REVIEW"
  [ "$status" -eq 0 ]
  run grep -q 'This is a bug in the referee, not a decision you owe anyone' "$REVIEW"
  [ "$status" -eq 0 ]
}

@test "the runbook documents the ladder and the asymmetry, not just the workflow" {
  # A rule whose reason lives only in a workflow comment is a rule the next person deletes.
  run grep -q 'tie-break ladder' "$RUNBOOK"
  [ "$status" -eq 0 ]
  run grep -qi 'self-grading' "$RUNBOOK"
  [ "$status" -eq 0 ]
  run grep -qi 'Verdicts are advice' "$RUNBOOK"
  [ "$status" -eq 0 ]
}
