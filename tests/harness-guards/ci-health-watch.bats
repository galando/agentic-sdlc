#!/usr/bin/env bats
#
# Gate 22 guards for the two checks that watch THE MACHINE rather than the product:
#
#   * `.github/workflows/ci-health-watch.yml` — runner liveness and the hosted-minutes
#     quota. The only check in the tree whose subject is CI itself.
#   * Gate 18 in `.github/workflows/nightly.yml` — live external API contract. A
#     documented CONTRACT rather than an implementation, because the upstream body was
#     entirely two named providers and fabricating a replacement would be worse than a gap.
#
# HAND-WRITTEN, and deliberately so for now. The assertions over `ci-health-watch.yml`
# have matching entries in `tests/harness-guards/pins.json` and become generated once the
# pin generator lands (tasks.md Task 20); this file then keeps only the gate-18
# assertions. Those CANNOT live in `pins.json`: every `quoted_source_string` there is
# verbatim from the read-only source, and the gate-18 contract text has no source string
# to quote — that is the whole reason it is a shell.
#
# Why any of this is pinned at all: both subjects fail QUIETLY by construction. A
# watchdog that cannot start reports nothing, and an unconfigured gate that passes is
# indistinguishable from one that ran. Neither has any other safety net.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
WATCH="$REPO_ROOT/.github/workflows/ci-health-watch.yml"
NIGHTLY="$REPO_ROOT/.github/workflows/nightly.yml"

# ---------------------------------------------------------------------------
# ci-health-watch.yml
# ---------------------------------------------------------------------------

@test "ci-health-watch: the workflow exists" {
  [ -f "$WATCH" ]
}

@test "ci-health-watch: the watchdog is pinned to the hosted runner" {
  # The load-bearing property. A watchdog routed through the same runner variables as
  # everything else would be sitting on the box it is watching.
  grep -qE '^ +runs-on: ubuntu-latest' "$WATCH"
}

@test "ci-health-watch: no job is routed through a *_RUNNER repository variable" {
  run grep -cE 'runs-on:.*vars\.[A-Z_]*RUNNER' "$WATCH"
  [ "$output" -eq 0 ]
}

# ---------------------------------------------------------------------------
# THE ASSERTION HAS TO FOLLOW THE CALL.
#
# The test above greps one file. This workflow's alerting does not live in one file: the
# watch job detects, and a REUSABLE WORKFLOW does the telling. A called workflow's
# `runs-on` cannot be overridden by its caller, so a `*_RUNNER` variable one file away is
# every bit as fatal as one here — and it passes a single-file grep silently.
#
# What that costs, concretely: the self-hosted runner dies, the hosted watchdog correctly
# detects it, and the notifier queues forever ON THE DEAD RUNNER. The detection is
# perfect and nobody is ever told. An alarm wired to the thing it is alarming about is
# not an alarm.
#
# The scope of the property, stated exactly, because it is easy to over-claim: hosted
# minutes at 100% stop every hosted job including this watch itself, and no in-repository
# mechanism can survive that. That is why the minutes check alerts at a THRESHOLD, below
# the cliff, rather than at exhaustion. What these assertions guarantee is the case that
# IS survivable — the self-hosted fleet going away — and they guarantee it by keeping the
# whole alerting path off that fleet.
# ---------------------------------------------------------------------------

@test "ci-health-watch: the notifier it delegates to is not on the fleet it watches" {
  # Follow the `uses:` rather than assuming which file it points at, so this keeps
  # holding if the notifier is ever renamed or replaced.
  called="$(grep -oE 'uses: \./\.github/workflows/[A-Za-z0-9._-]+\.yml' "$WATCH" \
            | head -n1 | sed 's|^uses: \./||')"
  [ -n "$called" ]
  callee="$REPO_ROOT/$called"
  [ -f "$callee" ]

  # 1. The caller pins the notifier's runner explicitly. A caller that says nothing
  #    inherits the callee's default, and the callee's default is the fleet.
  grep -qE "^ +runner: 'ubuntu-latest'" "$WATCH"

  # 2. The callee honours that input AHEAD of any repository variable. An input the
  #    callee ignores is a caller lying to itself.
  grep -qE '^ +runs-on: \$\{\{ inputs\.runner \|\|' "$callee"

  # 3. The input exists and is declared optional, so every OTHER caller keeps its
  #    current behaviour and this is not a breaking change to the shared notifier.
  grep -qE '^ +runner:$' "$callee"
}

@test "ci-health-watch: the delegated alert resolves to a hosted runner in every configuration" {
  # The demonstration, not just the text pin. GitHub's `||` yields the first truthy
  # operand and an unset variable is the empty string, so the expression is reproducible
  # here exactly. Both configurations are checked, because the defect was only visible in
  # one of them and "it works on my repository" is how it survived review.
  first_truthy() { for v in "$@"; do [ -n "$v" ] && { printf '%s' "$v"; return; }; done; printf ''; }

  called="$(grep -oE 'uses: \./\.github/workflows/[A-Za-z0-9._-]+\.yml' "$WATCH" \
            | head -n1 | sed 's|^uses: \./||')"
  callee="$REPO_ROOT/$called"

  # The value the caller passes for `runner:`.
  input_runner="$(grep -E "^ +runner: '" "$WATCH" | head -n1 | sed "s/.*runner: '\([^']*\)'.*/\1/")"

  # NIGHTLY_RUNNER set — an adopter with a self-hosted fleet, which is the ONLY kind of
  # adopter for whom the runner-liveness half of this watch does anything at all.
  [ "$(first_truthy "$input_runner" "self-hosted-fleet" "ubuntu-latest")" = "ubuntu-latest" ]

  # NIGHTLY_RUNNER unset — a hosted-only adopter.
  [ "$(first_truthy "$input_runner" "" "ubuntu-latest")" = "ubuntu-latest" ]

  # And the callee's expression really is `inputs.runner || <variable> || 'ubuntu-latest'`
  # in that order, so the emulation above matches the file.
  grep -qE "^ +runs-on: \\\$\{\{ inputs\.runner \|\| vars\.[A-Z_]+ \|\| 'ubuntu-latest' \}\}" "$callee"
}

@test "ci-health-watch: the reason the notifier is pinned too is written down" {
  # Same discipline as the watch job's own pin. Without the reason, "standardise the
  # runners" deletes it, and the deletion looks like tidying.
  grep -q 'alarm' "$WATCH"
  grep -qi 'cannot depend on the thing it is alarming about' "$WATCH"
}

@test "ci-health-watch: the reason it is not self-hosted is written down" {
  # A rule without its reason gets deleted by the next person, and this one reads like
  # an obvious inconsistency to anyone standardising runners.
  grep -q 'cannot report that runner dead' "$WATCH"
}

@test "ci-health-watch: the caller declares issues: write at workflow level" {
  # Without it the whole workflow is rejected at STARTUP and the watch never runs —
  # quiet rather than red, which is the worst available outcome for a watchdog.
  run grep -nE '^permissions:' "$WATCH"
  [ "$status" -eq 0 ]
  grep -q 'issues: write' "$WATCH"
}

@test "ci-health-watch: it calls the shared notifier, exactly once" {
  # One notifier job per gate. A second `uses:` here would mean two gates sharing one
  # `[nightly] <gate> is failing` issue.
  run grep -c 'uses: ./.github/workflows/nightly-alert.yml' "$WATCH"
  [ "$output" -eq 1 ]
}

@test "ci-health-watch: the notifier passes its own gate name" {
  grep -qE "^ +gate: '.+'" "$WATCH"
}

@test "ci-health-watch: the notifier fires on result == failure, not failure()" {
  # A run cancelled by its concurrency group is not a failed gate. `failure()` cannot
  # tell the difference; `result` is 'failure' only when the job RAN and FAILED.
  grep -q "result == 'failure'" "$WATCH"
  # Anchored at the `if:` KEY. An unanchored pattern also matches the comment that
  # explains why `failure()` is wrong here, and deleting that comment is how the rule
  # gets reintroduced.
  run grep -cE '^[[:space:]]*if:.*failure\(\)' "$WATCH"
  [ "$output" -eq 0 ]
}

@test "ci-health-watch: could-not-check degrades to a warning, separately from alerts" {
  # Two accumulators, deliberately separate. An expired token or a 5xx must not page
  # four times a day for a problem that is not there.
  grep -q 'ALERTS=' "$WATCH"
  grep -q 'WARNINGS=' "$WATCH"
  grep -q '::warning::' "$WATCH"
}

@test "ci-health-watch: an unarmed watch announces the skip and exits 0" {
  # Never silently green. The notice is the difference between "not configured" and
  # "checked and found nothing wrong".
  grep -q '::notice title=CI health watch not armed::' "$WATCH"
}

@test "ci-health-watch: the runner label is a placeholder, not a project's label" {
  grep -q '{{RUNNER_LABEL}}' "$WATCH"
}

@test "ci-health-watch: the runner label carries its placeholder annotation" {
  # gen-adopting.sh builds the adopter table from these annotations; a token without
  # one is a placeholder nobody is told to resolve.
  grep -q '# placeholder: {{RUNNER_LABEL}}' "$WATCH"
}

@test "ci-health-watch: the quota alert threshold is configurable, with a default" {
  grep -q 'vars.CI_MINUTES_ALERT_PCT' "$WATCH"
}

@test "ci-health-watch: it is never a required status check, and says why" {
  grep -q 'NEVER BE MARKED AS A REQUIRED STATUS CHECK' "$WATCH"
}

# ---------------------------------------------------------------------------
# Gate 18 — the documented shell, as a fillable contract
# ---------------------------------------------------------------------------

@test "gate 18: the contract names its placeholder" {
  grep -q '{{UPSTREAM_PROVIDER}}' "$NIGHTLY"
}

@test "gate 18: the placeholder carries its annotation" {
  grep -q '# placeholder: {{UPSTREAM_PROVIDER}}' "$NIGHTLY"
}

@test "gate 18: the contract says assert the SHAPE, not the values" {
  # The single most common way this gate is filled in wrong. Asserting values makes it
  # fail on every ordinary data change, and it gets switched off within a week.
  grep -qi 'response SHAPE, not the values' "$NIGHTLY"
}

@test "gate 18: the contract says one step per upstream dependency" {
  grep -q 'One step per upstream dependency' "$NIGHTLY"
}

@test "gate 18: the worked example uses an obviously fictional provider" {
  # A real provider name in an example gets copied verbatim into an adopter's repo.
  grep -q 'invalid' "$NIGHTLY"
}

@test "gate 18: it is stated as informative and non-blocking for merges" {
  grep -q 'INFORMATIVE, NON-BLOCKING' "$NIGHTLY"
}

@test "gate 18: the skip is a job-level if:, fed by a detect job" {
  grep -qE "^ +if: needs\.stacks\.outputs\.api_contract == 'true'" "$NIGHTLY"
}

@test "gate 18: no workflow-level paths: filter anywhere in nightly.yml" {
  # A paths: filter creates no check run at all. It is the wrong tool for every skip
  # in this repository and the reason is in docs/QUALITY-GATES.md.
  run grep -cE '^ +paths:' "$NIGHTLY"
  [ "$output" -eq 0 ]
}

@test "gate 18: an unconfigured gate says it SKIPPED rather than passing quietly" {
  grep -q 'SKIPPED, not passed' "$NIGHTLY"
}

@test "gate 18: the detect step emits the not-armed notice itself" {
  # The gate job's own `if:` is false when nothing is configured, so the gate job logs
  # nothing at all. The notice therefore has to come from the job that always runs.
  grep -q '::notice title=Gate 18 not armed::' "$NIGHTLY"
}
