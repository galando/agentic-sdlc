#!/usr/bin/env bats
#
# Gate 22 guard — the steward's pull-request step never opens a duplicate.
#
# THE LESSON. Before it opens a pull request for the branch the agent pushed, the step
# asks GitHub whether one already exists. That lookup used to sit inside `$(...)` in an
# `if` test: a failing `gh` prints nothing, and nothing is exactly what "no pull request"
# prints — so a dead token, a 500 or a network blip read as "none yet" and the step went
# on to open a second pull request for a branch that already had one. The sweep
# (tools/sweep-parked-branches.sh, rule 1) had learned the same lesson earlier: a failed
# lookup and "no pull request" look identical, and one of them opens a duplicate.
#
# The rule: the lookup's EXIT STATUS decides, not its output. On failure the step opens
# nothing, exits 1, prints a ::error:: naming the HTTP status and the start of GitHub's
# answer on one line, and says who repairs it — the sweep opens the pull request on its
# next run, so the work is not lost, only late.
#
# WHY BEHAVIOURAL. A text pin on the `gh pr list` line cannot tell `X="$(gh ...)" || rc=$?`
# from `if [ -n "$(gh ...)" ]` — both contain the same command. The difference is which
# branch a failing gh takes, so this extracts the REAL step body and runs it against a
# stubbed gh whose `pr list` fails, the same way steward-handoff-closure.bats runs the
# real outcome script.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
STEWARD="$REPO_ROOT/.github/workflows/steward.yml"

# The `run:` body of the pull-request step, dedented. Terminator: the first non-blank line
# not indented into the block scalar — NOT the next `- name:`, which the comment banner
# that follows this step would sail straight past.
extract_step() {
  awk '
    /^      - name: Open a pull request for the agent.s branch, if any/ { instep = 1; next }
    instep && !inrun && /^      [^ ]/ { exit }
    instep && /^        run: \|/ { inrun = 1; next }
    inrun && NF && !/^          / { exit }
    inrun { sub(/^          /, ""); print }
  ' "$STEWARD"
}

setup() {
  WORK="$(mktemp -d)"
  export WORK
  extract_step > "$WORK/pr-open.sh"
  # An empty extraction would pass every scenario below against nothing.
  [ -s "$WORK/pr-open.sh" ]
  grep -q 'gh pr list' "$WORK/pr-open.sh"
  grep -q 'gh pr create' "$WORK/pr-open.sh"

  mkdir -p "$WORK/bin"
  export GH_CALLS="$WORK/gh-calls.log"
  : > "$GH_CALLS"

  # git: the step's three git calls answer "the branch exists and is one commit ahead",
  # so the step reaches the lookup. The git judgements are not what this file tests.
  cat > "$WORK/bin/git" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  ls-remote) exit 0 ;;
  fetch)     exit 0 ;;
  log)       echo "abc1234 fix: something real"; exit 0 ;;
esac
exit 0
STUB
  # gh: records every call; `pr list` behaves per STUB_PRLIST, `pr create` per
  # STUB_CREATE. A failing call prints what the real gh prints — a multi-line answer with
  # the HTTP status in it — so the flattening and the status extraction are exercised.
  cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
case "$1 $2" in
  "pr list")
    case "${STUB_PRLIST:-empty}" in
      fail)   printf 'gh: Bad credentials\n{\n  "message": "Bad credentials"\n} (HTTP 401)\n' >&2; exit 1 ;;
      exists) echo 41 ;;
      *)      : ;;
    esac ;;
  "pr create")
    if [ "${STUB_CREATE:-ok}" = fail ]; then
      printf 'GraphQL: Resource not accessible by integration (HTTP 403)\n' >&2; exit 1
    fi
    echo "https://example.invalid/o/r/pull/42" ;;
esac
exit 0
STUB
  chmod +x "$WORK/bin/git" "$WORK/bin/gh"
}

teardown() { rm -rf "$WORK"; }

run_step() {
  PATH="$WORK/bin:$PATH" \
  GH_TOKEN=stub BRANCH=agent/fix-1 ISSUE_TITLE="Fix the thing" ISSUE_NUMBER=7 \
  REPO=o/r BASE=main \
  run bash "$WORK/pr-open.sh"
}

@test "pr-open: a FAILED lookup opens nothing, fails the step, and names the sweep as the repair" {
  STUB_PRLIST=fail run_step
  [ "$status" -ne 0 ]
  ! grep -q '^pr create' "$GH_CALLS"
  [[ "$output" == *"::error::"* ]]
  [[ "$output" == *"tools/sweep-parked-branches.sh"* ]]
  # And it must not have concluded "already exists" either — that would be the same
  # wrong branch with a friendlier message.
  [[ "$output" != *"already exists"* ]]
}

@test "pr-open: the error names the HTTP status and GitHub's answer, on ONE line" {
  # An ::error:: annotation stops at the first newline; gh's answer is multi-line JSON,
  # so unflattened it would show `{` and nothing else.
  STUB_PRLIST=fail run_step
  [ "$status" -ne 0 ]
  line="$(grep '^::error::' <<<"$output")"
  [ "$(wc -l <<<"$line")" -eq 1 ]
  [[ "$line" == *"HTTP 401"* ]]
  [[ "$line" == *"Bad credentials"* ]]
}

@test "pr-open: an existing pull request means nothing to open, and the step passes" {
  STUB_PRLIST=exists run_step
  [ "$status" -eq 0 ]
  ! grep -q '^pr create' "$GH_CALLS"
  [[ "$output" == *"already exists"* ]]
}

@test "pr-open: no pull request and a healthy lookup opens exactly one" {
  STUB_PRLIST=empty run_step
  [ "$status" -eq 0 ]
  [ "$(grep -c '^pr create' "$GH_CALLS")" -eq 1 ]
  grep -q -- '--head agent/fix-1' "$GH_CALLS"
}

@test "pr-open: a REFUSED create fails the step and names the sweep as the repair" {
  # The work is pushed and safe; the run must say so and who finishes it, not die on a
  # bare non-zero exit with no cause.
  STUB_CREATE=fail run_step
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"* ]]
  [[ "$output" == *"HTTP 403"* ]]
  [[ "$output" == *"tools/sweep-parked-branches.sh"* ]]
}

@test "pr-open: the lookup's exit status is what decides — never its output alone" {
  # The code form of the lesson. `if [ -n "$(gh pr list ...)" ]` is the shape that let a
  # failing gh read as "no pull request"; the exit status has to be captured and tested.
  run grep -qE 'if \[ -n "\$\(gh pr list' "$WORK/pr-open.sh"
  [ "$status" -ne 0 ]
  run grep -q 'LOOKUP_RC' "$WORK/pr-open.sh"
  [ "$status" -eq 0 ]
}
