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
# THE THIRD OUTCOME. A [steward-handoff] run pushes to the pull request's EXISTING branch,
# so it never creates a branch of its own, and its closing reply is often lost when the
# API token dies late in a long run. Counting only "a comment was posted or a new branch
# was pushed" therefore read a finished handoff as silence, left the issue open, and the
# title dedupe blocked the next handoff for that pull request. Commits on the pull
# request's branch inside the run's window are the third signal. Two things about it are
# behavioural, not textual, and are pinned below: it is scoped to [steward-handoff] titles
# only, and the CLOSE keys on the commit's resolved GitHub ACCOUNT (`c.author.type`),
# never on the git author name — the first version matched the name, and the close path
# was dead in production while a stub that also matched the name could not see it.
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
# The pull-request side is driven by environment variables so the original scenarios
# keep their shape:
#   T_COMMITS          commits on the pull request's head, as the API returns them
#                      (default: none). The stub honours `since` the way the API does.
#   T_PR_HEAD          the pull request's head ref (default agent/fix-12)
#   T_DEFAULT_BRANCH   the base repository's default branch (default main)
#   T_PULLS_GET_THROWS true makes pulls.get fail
#   T_BODY             the issue body (default empty)
run_outcome_check() {
  cat > "$WORK/harness.mjs" <<HARNESS
import { readFileSync } from 'node:fs';

const calls = [];
const title = process.env.T_TITLE;
const comments = JSON.parse(process.env.T_COMMENTS);
const branchExists = process.env.T_BRANCH_EXISTS === 'true';
const updateThrows = process.env.T_UPDATE_THROWS === 'true';
const commits = JSON.parse(process.env.T_COMMITS || '[]');
const prHead = process.env.T_PR_HEAD || 'agent/fix-12';
const defaultBranch = process.env.T_DEFAULT_BRANCH || 'main';
const pullsGetThrows = process.env.T_PULLS_GET_THROWS === 'true';
const body = process.env.T_BODY || '';

const github = {
  paginate: async (fn, args) => fn(args),
  rest: {
    pulls: {
      get: async (a) => {
        calls.push(['pullsGet', a.pull_number]);
        if (pullsGetThrows) throw new Error('stubbed 502');
        return { data: { head: { ref: prHead }, base: { repo: { default_branch: defaultBranch } } } };
      },
    },
    repos: {
      listCommits: async (a) => {
        calls.push(['listCommits', a.sha, a.since]);
        // `since` filters server-side; a stub that ignored it would let a script that
        // forgot to pass it count last week's commits as this run's work.
        return commits.filter(c => new Date(c.commit.author.date) >= new Date(a.since));
      },
      getBranch: async () => {
        if (branchExists) return {};
        const err = new Error('not found'); err.status = 404; throw err;
      },
    },
    issues: {
      listComments: async () => comments,
      createComment: async (a) => { calls.push(['createComment', a.issue_number]); },
      update: async (a) => {
        if (updateThrows) throw new Error('stubbed 403');
        calls.push(['update', a.issue_number, a.state, a.state_reason]);
      },
    },
  },
};

const context = {
  payload: { issue: { number: 77, title, body } },
  repo: { owner: 'o', repo: 'r' },
  serverUrl: 'https://example.invalid',
  runId: 1234,
};

const core = {
  info: (m) => calls.push(['info', m]),
  warning: (m) => calls.push(['warning', m]),
  setFailed: (m) => calls.push(['setFailed', m]),
};

const script = readFileSync(process.env.T_SCRIPT, 'utf8');
const fn = new Function('github', 'context', 'core', 'process',
  \`return (async () => { \${script} })()\`);
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

# Commits as the API returns them: `commit.author` is the git identity (a free-text name
# anyone can set), `author` is the GitHub account GitHub resolved from the email — or null.
BOT_COMMIT='[{"sha":"a1","commit":{"author":{"name":"agent","date":"2026-08-08T10:20:00Z"}},"author":{"login":"agent[bot]","type":"Bot"}}]'
HUMAN_COMMIT='[{"sha":"b2","commit":{"author":{"name":"someone","date":"2026-08-08T10:20:00Z"}},"author":{"login":"someone","type":"User"}}]'
NAME_ONLY_COMMIT='[{"sha":"c3","commit":{"author":{"name":"agent[bot]","date":"2026-08-08T10:20:00Z"}},"author":null}]'
STALE_BOT_COMMIT='[{"sha":"d4","commit":{"author":{"name":"agent","date":"2026-08-08T09:30:00Z"}},"author":{"login":"agent[bot]","type":"Bot"}}]'
HANDOFF='[steward-handoff] Review findings on PR #12'

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

# --- the third outcome: commits on the pull request's branch ---------------------------

@test "closure: commits in the run's window on the handoff's PR branch are an outcome, not silence" {
  # No reply, no new branch: the handoff pushed to the pull request's EXISTING branch.
  # Before the commit signal this run was reported as silent.
  T_COMMITS="$BOT_COMMIT" run run_outcome_check "$HANDOFF" "$NO_COMMENTS" "" false
  [ "$status" -eq 0 ]
  [[ "$output" == *'["pullsGet",12]'* ]]
  [[ "$output" == *'"listCommits","agent/fix-12","2026-08-08T10:00:00.000Z"'* ]]
  [[ "$output" != *'"setFailed"'* ]]
  [[ "$output" != *'"createComment"'* ]]
  [[ "$output" == *'"update",77,"closed","completed"'* ]]
}

@test "closure: a commit is an outcome for anyone, but closes only when its ACCOUNT is a Bot" {
  # The same two-tier split as posted / stewardPosted: the PR author committing mid-run
  # means the branch is alive (no notice), and is not the steward finishing (no close).
  T_COMMITS="$HUMAN_COMMIT" run run_outcome_check "$HANDOFF" "$NO_COMMENTS" "" false
  [ "$status" -eq 0 ]
  [[ "$output" != *'"setFailed"'* ]]
  [[ "$output" != *'"update"'* ]]
}

@test "closure: the git author NAME never closes — only the resolved GitHub account does" {
  # The first version matched the git name. Anyone can set that to anything, and in
  # production the commits carried a name GitHub had not resolved to an account, so the
  # close path was dead while a stub matching the same name stayed green. `author` null
  # must degrade to "not closed", whatever the name says.
  T_COMMITS="$NAME_ONLY_COMMIT" run run_outcome_check "$HANDOFF" "$NO_COMMENTS" "" false
  [ "$status" -eq 0 ]
  [[ "$output" != *'"setFailed"'* ]]
  [[ "$output" != *'"update"'* ]]
  # And the script must key on the account type, never the name field.
  run grep -q "c.author && c.author.type === 'Bot'" "$WORK/outcome-check.js"
  [ "$status" -eq 0 ]
  run grep -q 'commit.author.name' "$WORK/outcome-check.js"
  [ "$status" -ne 0 ]
}

@test "closure: a [review-lost] issue ignores commits on its PR branch" {
  # Also titled "... on PR #N", but its run re-runs a review and never pushes: a commit
  # there is somebody else's work and must not silence the lost-review notice.
  T_COMMITS="$BOT_COMMIT" run run_outcome_check "[review-lost] Automated review posted nothing on PR #12" "$NO_COMMENTS" "" false
  [ "$status" -eq 0 ]
  [[ "$output" != *'"pullsGet"'* ]]
  [[ "$output" == *'"setFailed"'* ]]
  [[ "$output" == *'["createComment",77]'* ]]
  [[ "$output" != *'"update"'* ]]
}

@test "closure: a failed pull-request lookup is neither silence nor health — notice posted, nothing closed" {
  # The probe could not run. Concluding "silent" would be wrong, concluding "fine" would
  # hide a lost run. Warn, let the notice fire (recoverable), close nothing.
  T_COMMITS="$BOT_COMMIT" T_PULLS_GET_THROWS=true run run_outcome_check "$HANDOFF" "$NO_COMMENTS" "" false
  [ "$status" -eq 0 ]
  [[ "$output" == *'"warning"'* ]]
  [[ "$output" == *'Could not read commits for PR #12'* ]]
  [[ "$output" == *'["createComment",77]'* ]]
  [[ "$output" == *'"setFailed"'* ]]
  [[ "$output" != *'"update"'* ]]
}

@test "closure: a pull request headed by the DEFAULT branch contributes no commit signal" {
  # Every merge in the window would otherwise read as this run's work.
  T_COMMITS="$BOT_COMMIT" T_PR_HEAD=main T_DEFAULT_BRANCH=main \
    run run_outcome_check "$HANDOFF" "$NO_COMMENTS" "" false
  [ "$status" -eq 0 ]
  [[ "$output" != *'"listCommits"'* ]]
  [[ "$output" == *'"warning"'* ]]
  [[ "$output" == *'"setFailed"'* ]]
  [[ "$output" != *'"update"'* ]]
}

@test "closure: commits from BEFORE the run started are silence" {
  # Same window as the comment and branch signals: a branch quiet since before the run
  # is exactly the silent run the notice exists for.
  T_COMMITS="$STALE_BOT_COMMIT" run run_outcome_check "$HANDOFF" "$NO_COMMENTS" "" false
  [ "$status" -eq 0 ]
  [[ "$output" == *'["createComment",77]'* ]]
  [[ "$output" == *'"setFailed"'* ]]
  [[ "$output" != *'"update"'* ]]
}

@test "closure: the pull request can be named by a /pull/N link in the body when the title lacks it" {
  T_COMMITS="$BOT_COMMIT" T_BODY='See https://example.invalid/o/r/pull/12 for the findings.' \
    run run_outcome_check "[steward-handoff] Review findings" "$NO_COMMENTS" "" false
  [ "$status" -eq 0 ]
  [[ "$output" == *'["pullsGet",12]'* ]]
  [[ "$output" == *'"update",77,"closed","completed"'* ]]
}
