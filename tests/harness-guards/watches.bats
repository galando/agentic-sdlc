#!/usr/bin/env bats
#
# Gate 22 guards — the two scheduled watches that look at what NOTHING ELSE looks at:
# the default branch after merges (main-watch.yml) and the agent fleet from outside
# it (fleet-heartbeat.yml), plus the secret scan's upload setting.
#
# THE LESSONS.
# - Two independently green pull requests broke the default branch together and
#   nothing re-tested it after the merges. main-watch.yml re-runs the FAST suite
#   against HEAD every four hours; a job that hangs past its budget is as red as one
#   that fails, which is only true while `cancel-in-progress: false` holds.
# - The watcher ring runs inside the agents, so a scheduler that stops them all
#   cannot make the ring say so. fleet-heartbeat.yml runs on the HOSTED runner,
#   literally, and a broken watch is red, never a quiet green.
# - A clean gitleaks scan failed its own artifact upload on a self-hosted runner; the
#   first fix moved HOME and made the scan read zero bytes and report "no leaks".

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
W="$REPO_ROOT/.github/workflows"

@test "main-watch: exists, is scheduled every four hours, never on pull requests" {
  [ -f "$W/main-watch.yml" ]
  grep -qE "cron: '[0-9]+ \*/4 \* \* \*'" "$W/main-watch.yml"
  ! grep -q 'pull_request' "$W/main-watch.yml"
}

@test "main-watch: the notifier fires on failure OR cancelled, and cancel-in-progress is false" {
  grep -q "needs.watch-main.result == 'failure' || needs.watch-main.result == 'cancelled'" "$W/main-watch.yml"
  grep -q 'cancel-in-progress: false' "$W/main-watch.yml"
}

@test "main-watch: it runs both halves of the harness suite and the workflow lint" {
  grep -q 'bats tests/$' "$W/main-watch.yml"
  grep -q 'bats tests/harness-guards/' "$W/main-watch.yml"
  grep -q 'actionlint .github/workflows/\*.yml' "$W/main-watch.yml"
}

@test "main-watch: it passes its own cadence word, so the issue does not say nightly" {
  grep -q "cadence: 'main-watch'" "$W/main-watch.yml"
}

@test "fleet-heartbeat: exists, scheduled, and runs on the hosted runner LITERALLY" {
  [ -f "$W/fleet-heartbeat.yml" ]
  grep -q 'cron:' "$W/fleet-heartbeat.yml"
  grep -q '^    runs-on: ubuntu-latest$' "$W/fleet-heartbeat.yml"
  ! grep -q 'vars\.[A-Z_]*_RUNNER' "$W/fleet-heartbeat.yml"
}

@test "fleet-heartbeat: the notifier is pinned to the hosted runner too — an alarm must not depend on what it alarms about" {
  [ "$(grep -c "runner: 'ubuntu-latest'" "$W/fleet-heartbeat.yml")" -eq 2 ]
}

@test "fleet-heartbeat: a broken watch and overdue agents are two different issues, both red in the Actions tab" {
  grep -q "gate: 'Agent fleet heartbeat'" "$W/fleet-heartbeat.yml"
  grep -q "gate: 'Agent fleet heartbeat watch'" "$W/fleet-heartbeat.yml"
  grep -q 'this is NOT a report of overdue agents' "$W/fleet-heartbeat.yml"
  [ "$(grep -c '^            exit 1$' "$W/fleet-heartbeat.yml")" -eq 2 ]
}

@test "fleet-heartbeat: it reads the ledger branch by archive, never a second checkout, and calls the tested checker" {
  grep -q 'git archive "origin/$BRANCH" ledger' "$W/fleet-heartbeat.yml"
  grep -q 'tools/check-heartbeat.sh check' "$W/fleet-heartbeat.yml"
  [ -x "$REPO_ROOT/tools/check-heartbeat.sh" ]
}

@test "fleet-heartbeat: the caller declares issues: write for the notifier, at workflow level" {
  awk '/^permissions:/{p=1;next} p&&/^[a-z]/{exit} p' "$W/fleet-heartbeat.yml" | grep -q 'issues: write'
}

@test "both watches are on the never-required list, and in the gate inventory" {
  grep -q 'watch-main' "$REPO_ROOT/docs/runbooks/branch-protection.md"
  grep -q 'watch-fleet-heartbeat' "$REPO_ROOT/docs/runbooks/branch-protection.md"
  grep -q 'main-watch.yml' "$REPO_ROOT/docs/QUALITY-GATES.md"
  grep -q 'fleet-heartbeat.yml' "$REPO_ROOT/docs/QUALITY-GATES.md"
}

@test "secret-scan: the artifact upload is off, and HOME is never moved" {
  grep -q 'GITLEAKS_ENABLE_UPLOAD_ARTIFACT: false' "$W/secret-scan.yml"
  ! grep -qE '^\s+HOME:' "$W/secret-scan.yml"
  grep -q 'TMPDIR: ${{ runner.temp }}' "$W/secret-scan.yml"
}

@test "coverage headroom: reported on every frontend run, and can never fail the job" {
  grep -q 'npm run check:coverage-headroom' "$W/pr-tests.yml"
  awk '/check:coverage-headroom/{found=1} found' "$W/pr-tests.yml" >/dev/null
  grep -B6 'npm run check:coverage-headroom' "$W/pr-tests.yml" | grep -q 'continue-on-error: true'
  grep -q '"check:coverage-headroom"' "$REPO_ROOT/examples/frontend/package.json"
}
