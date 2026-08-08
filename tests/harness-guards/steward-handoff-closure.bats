#!/usr/bin/env bats
#
# Gate 22 guard — the steward closes the handoff issue it finished, and closes NOTHING
# else.
#
# THE LESSON. The handoff issue that wakes the steward is a SIGNAL SHAPED LIKE A WORK
# ITEM: filing it starts the run, and the signal is spent the moment the run begins. But
# nothing owned the ticket afterwards, so it stayed open. Upstream had 8 of the 42 ever
# filed still open, one of them for a fix that had been pushed and replied to hours
# earlier.
#
# That is mostly clutter, with one real cost. review.yml's handoff dedupes on the EXACT
# issue title, and the title carries the pull-request number — so a stale open issue
# BLOCKS A SECOND HANDOFF for that same pull request. A pull request marked
# ready_for_review again after more commits then gets a review round that wakes nobody:
# the stranded-finding failure, one level up.
#
# WHY THIS GUARD IS BEHAVIOURAL AND NOT A TEXT PIN. Every dangerous failure here is a
# wrong branch taken, not a missing string. The two conditions guarding the close read
# almost identically to the ones guarding the outcome check directly above it, and
# swapping either — `posted` for `stewardPosted`, or dropping the title prefix — leaves a
# workflow whose text still looks right and whose behaviour closes issues nobody meant to
# close. So this extracts the REAL script out of the workflow and runs it against a
# stubbed API, the same way review-collector.bats runs the real jq programs.
#
# The three scenarios that must never close are the point of the file: a human's own
# issue, a [review-lost] issue, and a handoff where only a human replied.
#
# Requires node. That is a real dependency and it is declared loudly rather than skipped
# — a guard that quietly does not run is the failure mode this whole directory exists to
# prevent.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
STEWARD="$REPO_ROOT/.github/workflows/steward.yml"

setup() {
  command -v node >/dev/null 2>&1 || {
    echo "# node is required by this guard and is not installed — it cannot run,"
    echo "# and a guard that does not run is worse than one that fails."
    false
  }
  WORK="$(mktemp -d)"
  export WORK
  extract_script > "$WORK/outcome-check.js"
  # If the extraction ever silently yields nothing, every scenario below would pass
  # against an empty program. Fail here instead.
  [ -s "$WORK/outcome-check.js" ]
  grep -q 'steward-handoff' "$WORK/outcome-check.js"
}

teardown() { rm -rf "$WORK"; }

# The `script:` body of the "Require a visible outcome" step, dedented. awk rather than a
# YAML parser so the guard suite gains no new language dependency beyond node itself.
extract_script() {
  awk '
    /^      - name: Require a visible outcome on auto-triage runs/ { instep = 1; next }
    instep && !inscript && /^      [^ ]/ { exit }
    instep && /^          script: \|/ { inscript = 1; next }
    # The block scalar ends at the first non-blank line that is not indented into it.
    # Terminating on the next "      - " alone is not enough: the step is followed by a
    # comment banner at that indent, and the extraction then ran to end of file and
    # swallowed the rest of the workflow as JavaScript.
    inscript && NF && !/^            / { exit }
    inscript { sub(/^            /, ""); print }
  ' "$STEWARD"
}

# Run the extracted script against a stubbed API.
#   $1 issue title
#   $2 comments as a JSON array
#   $3 branch name from the remote-diff step ("" for none)
#   $4 whether that branch exists on the remote (true/false)
#   $5 whether issues.update should throw (true/false), default false
run_outcome_check() {
  cat > "$WORK/harness.mjs" <<HARNESS
import { readFileSync } from 'node:fs';

const calls = [];
const title = process.env.T_TITLE;
const comments = JSON.parse(process.env.T_COMMENTS);
const branchExists = process.env.T_BRANCH_EXISTS === 'true';
const updateThrows = process.env.T_UPDATE_THROWS === 'true';

const github = {
  paginate: async (fn, args) => fn(args),
  rest: {
    issues: {
      listComments: async () => comments,
      createComment: async (a) => { calls.push(['createComment', a.issue_number]); },
      update: async (a) => {
        if (updateThrows) throw new Error('stubbed 403');
        calls.push(['update', a.issue_number, a.state, a.state_reason]);
      },
    },
    repos: {
      getBranch: async () => {
        if (branchExists) return {};
        const err = new Error('not found'); err.status = 404; throw err;
      },
    },
  },
};

const context = {
  payload: { issue: { number: 77, title } },
  repo: { owner: 'o', repo: 'r' },
  serverUrl: 'https://example.invalid',
  runId: 1234,
};

const core = {
  info: (m) => calls.push(['info', m]),
  warning: (m) => calls.push(['warning', m]),
  setFailed: (m) => calls.push(['setFailed', m]),
};

const body = readFileSync(process.env.T_SCRIPT, 'utf8');
const fn = new Function('github', 'context', 'core', 'process',
  \`return (async () => { \${body} })()\`);
await fn(github, context, core, process);

console.log(JSON.stringify(calls));
HARNESS

  T_SCRIPT="$WORK/outcome-check.js" \
  T_TITLE="$1" \
  T_COMMENTS="$2" \
  T_BRANCH_EXISTS="${4:-false}" \
  T_UPDATE_THROWS="${5:-false}" \
  AGENT_BRANCH="$3" \
  STARTED_AT="2026-08-08T10:00:00Z" \
  node "$WORK/harness.mjs"
}

BOT_REPLY='[{"created_at":"2026-08-08T10:05:00Z","user":{"type":"Bot","login":"agent[bot]"}}]'
HUMAN_REPLY='[{"created_at":"2026-08-08T10:05:00Z","user":{"type":"User","login":"someone"}}]'
NO_COMMENTS='[]'
STALE_BOT_REPLY='[{"created_at":"2026-08-08T09:00:00Z","user":{"type":"Bot","login":"agent[bot]"}}]'

@test "closure: a finished handoff issue with the steward's reply is closed as completed" {
  run run_outcome_check "[steward-handoff] Review findings on PR #12" "$BOT_REPLY" "" false
  [ "$status" -eq 0 ]
  [[ "$output" == *'["update",77,"closed","completed"]'* ]]
}

@test "closure: a handoff finished by a PUSHED BRANCH is closed even with no reply" {
  # The steward that pushes a fix and says nothing on the issue still finished the work.
  run run_outcome_check "[steward-handoff] Review findings on PR #12" "$NO_COMMENTS" "agent/fix-1" true
  [ "$status" -eq 0 ]
  [[ "$output" == *'"update",77,"closed","completed"'* ]]
}

@test "closure: a HUMAN-FILED issue is never closed, however the steward replied" {
  # This step runs on EVERY opened issue. Closing somebody's bug report because the
  # steward answered it would be worse than the problem being fixed.
  run run_outcome_check "Login button does nothing on mobile" "$BOT_REPLY" "" false
  [ "$status" -eq 0 ]
  [[ "$output" != *'"update"'* ]]
}

@test "closure: a [review-lost] issue is never closed" {
  # It reports a broken review pipeline. A steward reply does not repair that, and closing
  # it would retire the one record that the pipeline lost a review.
  run run_outcome_check "[review-lost] Automated review posted nothing on PR #12" "$BOT_REPLY" "" false
  [ "$status" -eq 0 ]
  [[ "$output" != *'"update"'* ]]
}

@test "closure: a handoff where only a HUMAN replied is not closed" {
  # The failure this guard exists for. The outcome check above counts anyone's comment on
  # purpose — an answered issue is not silently unanswered. Reusing that looser signal for
  # CLOSING lets a human writing "hold on" close the ticket they were objecting to.
  run run_outcome_check "[steward-handoff] Review findings on PR #12" "$HUMAN_REPLY" "" false
  [ "$status" -eq 0 ]
  [[ "$output" != *'"update"'* ]]
  # ...and the run still passes, because a human reply IS a visible outcome.
  [[ "$output" != *'"setFailed"'* ]]
}

@test "closure: a comment from BEFORE this run does not close the issue" {
  # Otherwise a previous run's reply closes a handoff this run left unanswered — and the
  # no-outcome notice below would be suppressed at the same time.
  run run_outcome_check "[steward-handoff] Review findings on PR #12" "$STALE_BOT_REPLY" "" false
  [ "$status" -eq 0 ]
  [[ "$output" != *'"update"'* ]]
  [[ "$output" == *'"setFailed"'* ]]
}

@test "closure: a named branch that is NOT on the remote is not a finished handoff" {
  # `branch_name` is set even when nothing was committed, so the name alone is not proof —
  # the same lesson the pull-request step already encodes.
  run run_outcome_check "[steward-handoff] Review findings on PR #12" "$NO_COMMENTS" "agent/fix-1" false
  [ "$status" -eq 0 ]
  [[ "$output" != *'"update"'* ]]
  [[ "$output" == *'"setFailed"'* ]]
}

@test "closure: a failed close warns and does not fail the run" {
  # The work is done. Reddening a run over the bookkeeping would train people to ignore a
  # red steward run, which is the one signal that has to keep meaning something.
  run run_outcome_check "[steward-handoff] Review findings on PR #12" "$BOT_REPLY" "" false true
  [ "$status" -eq 0 ]
  [[ "$output" == *'"warning"'* ]]
  [[ "$output" == *"close it by hand"* ]]
  [[ "$output" != *'"setFailed"'* ]]
}

@test "closure: the no-outcome notice still fires when nothing happened at all" {
  # The behaviour this step existed for before the close was added. A green, silent run is
  # the unrecoverable one, because nobody knows to look.
  run run_outcome_check "[steward-handoff] Review findings on PR #12" "$NO_COMMENTS" "" false
  [ "$status" -eq 0 ]
  [[ "$output" == *'["createComment",77]'* ]]
  [[ "$output" == *'"setFailed"'* ]]
  [[ "$output" != *'"update"'* ]]
}

@test "closure: the title prefix the steward closes on is the one review.yml files" {
  # Two files, one string. If review.yml's handoff title is ever reworded, this close stops
  # matching and every handoff issue silently goes back to staying open.
  run grep -q 'TITLE="\[steward-handoff\] Review findings on PR #\$PR"' \
    "$REPO_ROOT/.github/workflows/review.yml"
  [ "$status" -eq 0 ]
  run grep -q "title.startsWith('\[steward-handoff\]')" "$STEWARD"
  [ "$status" -eq 0 ]
}
