#!/usr/bin/env bats
#
# Gate 22 guard — the shared notifier (nightly-alert.yml) names what it found, and a
# thread that keeps failing on the SAME findings does not gain an identical comment
# every run.
#
# THE LESSON. The template's own nightly dependency scan sat red for eleven days, and
# the notifier added a byte-identical comment to the same issue every night. Nobody
# could tell from the thread whether night nine found the advisory of night one or a
# new one, and the one night that WOULD have been news would have looked exactly like
# the other ten. So: a caller may pass `findings`; the body carries them on a
# `**What this run found:**` line; and when the previous comment already carries that
# exact line the run adds nothing. An EMPTY findings line never dedupes — the caller
# could not say what it found, so every run is news.
#
# A second lesson rides along: the title's cadence word is an input, because a caller
# that does not run nightly (a merge-time watch, a fleet heartbeat) was filing issues
# that said "nightly" and sent the reader to the wrong place — and a renamed cadence
# must find the thread it was already commenting on, and retitle it.
#
# These are behavioural, so the REAL script is extracted from the workflow and run
# against a stubbed API, the way steward-handoff-closure.bats does.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
NOTIFIER="$REPO_ROOT/.github/workflows/nightly-alert.yml"

setup() {
  command -v node >/dev/null 2>&1 || {
    echo "# node is required by this guard and is not installed — it cannot run,"
    echo "# and a guard that does not run is worse than one that fails."
    false
  }
  WORK="$(mktemp -d)"
  export WORK
  extract_script > "$WORK/notifier.js"
  [ -s "$WORK/notifier.js" ]
  grep -q 'is failing' "$WORK/notifier.js"
}

teardown() { rm -rf "$WORK"; }

extract_script() {
  awk '
    /^      - name: Open or update the tracking issue/ { instep = 1; next }
    instep && !inscript && /^      - name:/ { exit }
    instep && /^          script: \|/ { inscript = 1; next }
    inscript && NF && !/^            / { exit }
    inscript { sub(/^            /, ""); print }
  ' "$NOTIFIER"
}

# run_notifier — environment drives the scenario:
#   T_GATE, T_CADENCE, T_FINDINGS      the inputs
#   T_ISSUES   JSON array of open agent-report issues ({number,title,body,html_url})
#   T_COMMENTS JSON array of comments on the matched issue ({body})
run_notifier() {
  cat > "$WORK/harness.mjs" <<'HARNESS'
import { readFileSync } from 'node:fs';
const calls = [];
const issues = JSON.parse(process.env.T_ISSUES || '[]');
const comments = JSON.parse(process.env.T_COMMENTS || '[]');
const github = {
  paginate: async (fn, args) => fn(args),
  rest: {
    issues: {
      listForRepo: async () => issues,
      listComments: async () => comments,
      createComment: async (a) => { calls.push(['createComment', a.issue_number, a.body]); return {}; },
      create: async (a) => { calls.push(['create', a.title, a.body]); return { data: { number: 99, html_url: 'u/99' } }; },
      update: async (a) => { calls.push(['update', a.issue_number, a.title]); return {}; },
    },
  },
};
const outputs = {};
const core = {
  setOutput: (k, v) => { outputs[k] = v; },
  info: () => {},
  summary: { addRaw: () => ({ write: async () => {} }) },
};
const context = { serverUrl: 'https://example.invalid', repo: { owner: 'o', repo: 'r' }, runId: 1, sha: 'abcdef0123', ref: 'refs/heads/main' };
process.env.GATE = process.env.T_GATE || 'Dependency CVE scan';
process.env.CADENCE = process.env.T_CADENCE ?? 'nightly';
process.env.FINDINGS = process.env.T_FINDINGS ?? '';
process.env.SEVERITY = 'S2';
process.env.MEANING = 'meaning';
process.env.RUNBOOK = 'runbook.md';
const src = readFileSync(process.env.T_SCRIPT, 'utf8');
const fn = new Function('github', 'core', 'context', 'process', `return (async () => { ${src} })();`);
await fn(github, core, context, process);
console.log(JSON.stringify({ calls, outputs }));
HARNESS
  T_SCRIPT="$WORK/notifier.js" node "$WORK/harness.mjs"
}

@test "a first failure opens an issue titled with the cadence word and carries the findings line" {
  T_CADENCE=nightly T_FINDINGS='UNALLOWLISTED high advisory in x (1)' run run_notifier
  [ "$status" -eq 0 ]
  [[ "$output" == *'["create","[nightly] Dependency CVE scan is failing"'* ]]
  [[ "$output" == *'**What this run found:** UNALLOWLISTED high advisory in x (1)'* ]]
}

@test "a caller with its own cadence titles the issue with that word, not nightly" {
  T_CADENCE=heartbeat T_GATE='Agent fleet heartbeat' run run_notifier
  [ "$status" -eq 0 ]
  [[ "$output" == *'["create","[heartbeat] Agent fleet heartbeat is failing"'* ]]
  [[ "$output" != *'nightly run'* ]]
}

@test "the same findings as the last comment add NO new comment, and say so in the output" {
  issues='[{"number":28,"title":"[nightly] Dependency CVE scan is failing","body":"x","html_url":"u/28"}]'
  comments='[{"body":"**S2 — x**\n\n**What this run found:** UNALLOWLISTED high advisory in x (1)\n\nmore"}]'
  T_ISSUES="$issues" T_COMMENTS="$comments" T_FINDINGS='UNALLOWLISTED high advisory in x (1)' run run_notifier
  [ "$status" -eq 0 ]
  [[ "$output" != *'createComment'* ]]
  [[ "$output" == *'"unchanged":"true"'* ]]
  [[ "$output" == *'"number":28'* ]]
}

@test "different findings on the same thread DO add a comment" {
  issues='[{"number":28,"title":"[nightly] Dependency CVE scan is failing","body":"x","html_url":"u/28"}]'
  comments='[{"body":"**What this run found:** UNALLOWLISTED high advisory in x (1)"}]'
  T_ISSUES="$issues" T_COMMENTS="$comments" T_FINDINGS='UNALLOWLISTED high advisory in y (2)' run run_notifier
  [ "$status" -eq 0 ]
  [[ "$output" == *'["createComment",28,'* ]]
  [[ "$output" == *'"unchanged":"false"'* ]]
}

@test "an empty findings line never dedupes — a caller that cannot say what it found is news every run" {
  issues='[{"number":28,"title":"[nightly] Dependency CVE scan is failing","body":"x","html_url":"u/28"}]'
  comments='[{"body":"**S2 — Dependency CVE scan failed on the nightly run.**\n\n**What red means:** meaning"}]'
  T_ISSUES="$issues" T_COMMENTS="$comments" T_FINDINGS='' run run_notifier
  [ "$status" -eq 0 ]
  [[ "$output" == *'["createComment",28,'* ]]
  [[ "$output" != *'What this run found'* ]]
}

@test "a thread filed under an older cadence word is found AND retitled, never orphaned" {
  issues='[{"number":7,"title":"[nightly] Default-branch FAST suite is failing","body":"x","html_url":"u/7"}]'
  T_ISSUES="$issues" T_CADENCE=main-watch T_GATE='Default-branch FAST suite' run run_notifier
  [ "$status" -eq 0 ]
  [[ "$output" == *'["update",7,"[main-watch] Default-branch FAST suite is failing"]'* ]]
  [[ "$output" == *'["createComment",7,'* ]]
  [[ "$output" != *'"create",'* ]]
}

@test "a different gate under the same cadence is never matched to this gate's thread" {
  issues='[{"number":7,"title":"[nightly] Mutation testing (backend) is failing","body":"x","html_url":"u/7"}]'
  T_ISSUES="$issues" run run_notifier
  [ "$status" -eq 0 ]
  [[ "$output" == *'["create","[nightly] Dependency CVE scan is failing"'* ]]
}

@test "the nightly dependency scan passes its audit lines as findings" {
  grep -q "findings: \${{ needs.nightly-dependency-scan.outputs.findings }}" "$REPO_ROOT/.github/workflows/nightly.yml"
  grep -qF "audit-ci: (UNALLOWLISTED|STALE)" "$REPO_ROOT/.github/workflows/nightly.yml"
}

@test "every nightly notifier fires on cancelled as well as failure, and the pairing with cancel-in-progress: false is written down" {
  local n
  n="$(grep -c "result == 'cancelled')" "$REPO_ROOT/.github/workflows/nightly.yml")"
  [ "$n" -ge 6 ]
  grep -q 'cancel-in-progress: false' "$REPO_ROOT/.github/workflows/nightly.yml"
  grep -q "'cancelled' IS listed, and only because" "$REPO_ROOT/.github/workflows/nightly.yml"
}
