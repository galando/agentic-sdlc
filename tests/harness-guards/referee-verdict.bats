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

@test "workflow: the referee is given the code, by a plain script step" {
  # It settles disagreements against the code, so it has to be able to SEE the code — and
  # fetching it in a script rather than letting the agent do it keeps the agent unable to
  # choose WHICH code it rules on.
  #
  # This assertion has been narrowed twice rather than deleted, and both times it got
  # stricter. First when the diff was PINNED to the reviewed commit; then when the fetch
  # moved into tools/fetch-pinned-diff.sh so all three review jobs share one copy. What it
  # holds now is the invariant that survives both moves: a plain step hands the referee a
  # diff, and the prompt tells it to read that file. The pinning behaviour itself is
  # guarded behaviourally in referee-diff-pin.bats.
  run grep -q 'tools/fetch-pinned-diff.sh' "$REVIEW"
  [ "$status" -eq 0 ]
  run grep -q -- '--out .review-artifacts/diff.patch' "$REVIEW"
  [ "$status" -eq 0 ]
  run grep -q 'diff.patch' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "workflow: a failed diff fetch degrades, never fails the job" {
  # Same rule as every other optional input in this system: degrade loudly, never cancel.
  # The sentence lives in the shared script now, with the fetch it describes.
  run grep -q 'verify against the checked-out tree instead' \
    "$REPO_ROOT/tools/fetch-pinned-diff.sh"
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

# ---------------------------------------------------------------------------
# The punt check, EXECUTED. The blocklist half is asserted above by running its pattern;
# this runs the whole step, because the half that matters now is a positive assertion
# about structure and there is no pattern to test in isolation.
# ---------------------------------------------------------------------------

extract_punt_step() {
  awk '
    /^      - name: Check the referee actually ruled/ { instep = 1; next }
    instep && !inrun && /^      [^ ]/ { exit }
    instep && /^        run: \|/ { inrun = 1; next }
    inrun && NF && !/^          / { exit }
    inrun { sub(/^          /, ""); print }
  ' "$REVIEW"
}

# PUNTWORK is created in setup(), NOT inside the function bats calls through `run`.
#
# It was, and that made the negative assertions pass for the wrong reason: `run` executes
# in a subshell, so the variable never came back, `annotated` cat'd a path that did not
# exist, and every `[[ "$output" != *"broke its own rule"* ]]` passed against an error
# message. Three tests were green while asserting nothing — the exact failure this whole
# directory exists to prevent, in the directory that exists to prevent it.
setup() {
  PUNTWORK="$(mktemp -d)"
  export PUNTWORK
  mkdir -p "$PUNTWORK/.review-artifacts"
  extract_punt_step > "$PUNTWORK/step.sh"
  # If the extraction ever yields nothing, every assertion below would pass vacuously.
  [ -s "$PUNTWORK/step.sh" ]
  grep -q 'PUNTS=' "$PUNTWORK/step.sh"
}

teardown() { rm -rf "$PUNTWORK"; }

# $1 = the comparison body to feed it. Leaves the (possibly annotated) comment at
# $PUNTWORK/.review-artifacts/referee-comment.md
run_punt_check() {
  printf '%s\n' "$1" > "$PUNTWORK/.review-artifacts/referee-comment.md"
  ( cd "$PUNTWORK" && RUN_URL="https://e.invalid/run" bash step.sh )
}

annotated() {
  # Fail loudly rather than returning an error string that a `!=` assertion would swallow.
  [ -f "$PUNTWORK/.review-artifacts/referee-comment.md" ] || { echo "MISSING COMMENT FILE"; return 1; }
  cat "$PUNTWORK/.review-artifacts/referee-comment.md"
}

@test "punt check: a properly ruled comparison passes through untouched" {
  body='## Reviewer comparison

### Settled disagreements

- Both claimed different things about src/a.js:10.
  Verdict: the challenge role is right — src/a.js:12 closes the handle.'
  run run_punt_check "$body"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no punt language found"* ]]
  run annotated
  [[ "$output" != *"broke its own rule"* ]]
}

@test "punt check: a settled section with NO Verdict line is caught — no banned words needed" {
  # The whole point of the positive check. This wording appears in no blocklist and never
  # will; a model can invent a new way to hesitate every time. What it cannot do is write
  # a ruling without writing a ruling.
  body='## Reviewer comparison

### Settled disagreements

- The two reviewers take different views on src/a.js:10. Both positions are reasonable
  and the right call depends on what the team wants from this module.'
  run run_punt_check "$body"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no Verdict: line"* ]]
  run annotated
  [[ "$output" == *"broke its own rule"* ]]
}

@test "punt check: an EMPTY settled section is fine — nothing to rule on" {
  # Omitting the section when it is genuinely empty is what the prompt asks for. Treating
  # "no disagreements" as "refused to rule" would put a warning on every clean comparison,
  # and a warning on everything is a warning on nothing.
  body='## Reviewer comparison

### Both reviewers found this

- src/a.js:10 leaks a handle.

### Settled disagreements

### Only the judge role found this

- src/b.js:4 is unreachable.'
  run run_punt_check "$body"
  [ "$status" -eq 0 ]
  run annotated
  [[ "$output" != *"broke its own rule"* ]]
}

@test "punt check: the blocklist still fires on the sentence that started this" {
  body='## Reviewer comparison

Neither review is authoritative. A human decides.'
  run run_punt_check "$body"
  [ "$status" -eq 0 ]
  run annotated
  [[ "$output" == *"broke its own rule"* ]]
}

@test "punt check: a Verdict line survives bullet and emphasis markers" {
  # The referee writes markdown. Requiring a bare line start would fail on "- **Verdict:**",
  # which is a correctly ruled disagreement, and put a bug warning on good output.
  body='## Reviewer comparison

### Settled disagreements

- **Verdict:** the judge role is right, src/a.js:10.'
  run run_punt_check "$body"
  [ "$status" -eq 0 ]
  run annotated
  [[ "$output" != *"broke its own rule"* ]]
}

@test "punt check: an annotated comparison still contains the original comparison" {
  # Never suppress. The warning goes on top; everything the referee wrote follows it.
  body='## Reviewer comparison

### Settled disagreements

- Someone should decide this.'
  run run_punt_check "$body"
  [ "$status" -eq 0 ]
  run annotated
  [[ "$output" == *"broke its own rule"* ]]
  [[ "$output" == *"Someone should decide this."* ]]
  [[ "$output" == *"## Reviewer comparison"* ]]
}

# ---------------------------------------------------------------------------
# THE MERGE VERDICT: the value has a PRODUCER, and these tests are what say so.
#
# The verdict file decides whether the steward is woken. Everything that reads it is
# guarded — the decision script by tests/handoff-decision.bats, the step that acts on it
# by steward-handoff-decision.bats. All of that guards the CONSUMER.
#
# Nothing guarded the PRODUCER, and the bug this whole change fixes is what happens when
# a consumer reads a value nothing emits. `review-clean-phrase-literal` pinned a `grep`
# for "No issues found" and matched it on every run for months; no prompt in this
# repository ever asked a reviewer to write that phrase, so the branch behind it had
# never once been taken and every agent pull request woke the steward.
#
# Delete the verdict instruction from the referee's prompt and the identical failure
# returns through a different door: no file is ever written, the fail-safe fires on every
# pull request, and all 574 tests stay green while the steward is woken every time.
#
# So the rule recorded in semantic-discharges.md — "name what PRODUCES the value it
# reads, not only what consumes it" — is applied to itself here. The path is read OUT of
# the workflow rather than written twice, so renaming it on one side alone fails.
# ---------------------------------------------------------------------------

# The path the workflow hands to the decision script as --verdict.
verdict_path() {
  grep -oE -- '--verdict[[:space:]]+[^[:space:]]+' "$REVIEW" | head -n1 | awk '{print $2}'
}

@test "verdict: the workflow reads a verdict path at all (else every test below is vacuous)" {
  path="$(verdict_path)"
  [ -n "$path" ]
  [[ "$path" == .review-artifacts/* ]]
}

@test "verdict: THE PROMPT WRITES THE FILE THE WORKFLOW READS — same path, not two literals" {
  # The producer/consumer link. Extracted from the workflow so that renaming the file on
  # one side and not the other cannot pass.
  path="$(verdict_path)"
  run grep -qF "$path" "$PROMPT"
  [ "$status" -eq 0 ]
  # And it must be an instruction to WRITE it, not a passing mention.
  run grep -qiE "write[^.]*$(printf '%s' "$path" | sed 's/[.[\*^$]/\\&/g')" "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "verdict: the workflow actually runs the prompt file these tests inspect" {
  # Without this, the two tests above could both pass while the referee ran some other
  # prompt entirely.
  run grep -qF -- "--prompt-file .agents/prompts/review-referee.md" "$REVIEW"
  [ "$status" -eq 0 ]
}

@test "verdict: the prompt defines all three words, and only those three" {
  for word in blocking non-blocking undecided; do
    run grep -qF "$word" "$PROMPT"
    [ "$status" -eq 0 ] || { echo "prompt never defines '$word'"; return 1; }
  done
  # The vocabulary the decision script recognises must be the vocabulary the prompt
  # teaches. A word in one and not the other is a verdict that always fails safe.
  DECIDE="$REPO_ROOT/tools/review-handoff-decide.sh"
  run grep -q 'blocking|non-blocking|undecided' "$DECIDE"
  [ "$status" -eq 0 ]
}

@test "verdict: the prompt says WHICH verdicts wake an agent, so the meaning cannot invert" {
  # The referee is choosing whether to wake a fixer, not grading the change. A prompt that
  # asks only for a label gets `blocking` used to mean "interesting", which is the
  # over-waking this change exists to end.
  # Backticks are optional in the pattern: the prompt marks the words up as code, and a
  # guard that breaks when someone adds or removes a backtick teaches people to delete it.
  run grep -qiE '`?blocking`? and `?undecided`? both wake' "$PROMPT"
  [ "$status" -eq 0 ]
  run grep -qiE '`?non-blocking`? files a follow-up' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "verdict: the prompt tells the referee an unusable verdict still wakes the agent" {
  # It must know the fail-safe exists — otherwise "write nothing when unsure" looks like
  # the cautious choice, and it is the opposite.
  run grep -qiE 'also wakes the agent|missing input must never read' "$PROMPT"
  [ "$status" -eq 0 ]
}

@test "verdict: the runbook documents the verdict and the token that makes it work" {
  # A rule whose reason lives only in a workflow comment is a rule the next person deletes.
  run grep -qi 'merge verdict' "$RUNBOOK"
  [ "$status" -eq 0 ]
  run grep -qi 'token is the switch' "$RUNBOOK"
  [ "$status" -eq 0 ]
}

@test "verdict: the workflow does NOT keep its own copy of the normalisation" {
  # The reporting step and the acting step must get the word from one place. When they had
  # a pipeline each, the comment above them claimed the log and the decision could not
  # disagree — which two copies is exactly how they eventually would, with the operator
  # reading the log the last to find out.
  step="$(awk '
    /^      - name: Read the referee.s merge verdict/ { instep = 1; next }
    instep && !inrun && /^      [^ ]/ { exit }
    instep && /^        run: \|/ { inrun = 1; next }
    inrun && NF && !/^          / { exit }
    inrun { print }
  ' "$REVIEW")"
  [ -n "$step" ]

  # It asks the decision script for the word...
  run grep -q -- '--verdict-only' <<<"$step"
  [ "$status" -eq 0 ]
  # ...and does not re-derive it. `tr -cd` and `head -n1` are the tell.
  run grep -qE 'tr -cd|head -n1' <<<"$step"
  [ "$status" -ne 0 ]
}
