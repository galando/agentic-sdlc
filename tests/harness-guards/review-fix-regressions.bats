#!/usr/bin/env bats
#
# Gate 22 guards for a review round that found five defects, all variations on the same
# theme: a gate that LOOKS armed but silently checks nothing, or silently cancels instead
# of degrading. Each of these was verified against the raw workflow files before the fix
# landed; this file pins the fix so it cannot regress unnoticed.
#
# ---------------------------------------------------------------------------
# FINDINGS 1 & 2 — gate 10 and gate 17 pointed at a top-level `backend/` that has never
# existed in this tree. The product lives at `examples/backend/`. A paths-filter that
# never matches makes its job report "skipped", which satisfies a required check exactly
# as cleanly as a real pass — so the gate went quiet instead of red, and nobody watching
# CI could tell the difference from "nothing changed here". `nightly.yml` already used
# `examples/backend` correctly; these two workflows drifted from it, silently, and only a
# change under the real path — not the dead one — proves the drift is gone.
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
VALIDATION="$REPO_ROOT/.github/workflows/pr-validation.yml"
MUTATION="$REPO_ROOT/.github/workflows/pr-mutation.yml"
SCHEDULED="$REPO_ROOT/.github/workflows/agents-scheduled.yml"
STEWARD="$REPO_ROOT/.github/workflows/steward.yml"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"

# A minimal, faithful re-implementation of dorny/paths-filter matching for the one glob
# shape every filter in this repo uses: `<dir>/**` (match anything at or under <dir>).
# Good enough to DEMONSTRATE the filter now matches real on-disk paths, not just assert
# that the right substring appears in the YAML.
path_matches_dir_glob() {
  local glob="$1" path="$2" prefix
  case "$glob" in
    */\*\*) prefix="${glob%/**}/" ;;
    *) return 1 ;;
  esac
  case "$path" in
    "$prefix"*) return 0 ;;
    *) return 1 ;;
  esac
}

@test "gate 10: pr-validation.yml's migration filter targets examples/backend, never top-level backend" {
  grep -qF "'examples/backend/src/main/resources/db/migration/**'" "$VALIDATION"
  ! grep -qE "^\s*-\s*'backend/" "$VALIDATION"
}

@test "gate 10: pr-validation.yml's working-directory targets examples/backend" {
  grep -qF 'working-directory: ./examples/backend' "$VALIDATION"
  ! grep -qE 'working-directory: \./backend[^/a-zA-Z]' "$VALIDATION"
}

@test "gate 10 DEMONSTRATION: a real migration file trips the corrected filter, and would have missed the old one" {
  glob="examples/backend/src/main/resources/db/migration/**"
  real_file="examples/backend/src/main/resources/db/migration/V1__create_items_table.sql"
  [ -f "$REPO_ROOT/$real_file" ]
  path_matches_dir_glob "$glob" "$real_file"

  # The OLD (buggy) glob would never have matched this real file — proving the bug was
  # real, not just a naming preference.
  old_glob="backend/src/main/resources/db/migration/**"
  ! path_matches_dir_glob "$old_glob" "$real_file"
}

@test "gate 17: pr-mutation.yml's scope filter targets examples/backend, never top-level backend" {
  grep -qF "'examples/backend/src/main/java/**'" "$MUTATION"
  ! grep -qE "^\s*-\s*'backend/" "$MUTATION"
}

@test "gate 17: pr-mutation.yml's working-directory entries all target examples/backend" {
  wd_count="$(grep -cF 'working-directory: ./examples/backend' "$MUTATION")"
  [ "$wd_count" -eq 2 ]
  ! grep -qE 'working-directory: \./backend[^/a-zA-Z]' "$MUTATION"
}

@test "gate 17: pr-mutation.yml's artifact upload path targets examples/backend" {
  grep -qF 'path: examples/backend/target/pit-reports/' "$MUTATION"
  ! grep -qE '^\s*path: backend/' "$MUTATION"
}

@test "gate 17: the floor-get relative path was re-based for the deeper working-directory" {
  # working-directory moved from ./backend (one level under root) to ./examples/backend
  # (two levels under root) — every ../-relative reference inside that step needs one
  # more ../, or it silently resolves to examples/tools/ instead of tools/. Fixed-string
  # (-F) matches, not regex: the single-level literal is never a substring of the
  # doubled one at the same offset ("-x ../../tools" never contains "-x ../tools").
  grep -qF -- '-x ../../tools/floor-get.sh' "$MUTATION"
  grep -qF -- '../../tools/floor-get.sh backend.mutation.score' "$MUTATION"
  ! grep -qF -- '-x ../tools/floor-get.sh' "$MUTATION"
  ! grep -qF -- '"$(../tools/floor-get.sh' "$MUTATION"
}

@test "gate 17 DEMONSTRATION: a real production class trips the corrected filter, and would have missed the old one" {
  glob="examples/backend/src/main/java/**"
  real_file="examples/backend/src/main/java/com/example/agentsdlc/service/ItemService.java"
  [ -f "$REPO_ROOT/$real_file" ]
  path_matches_dir_glob "$glob" "$real_file"

  old_glob="backend/src/main/java/**"
  ! path_matches_dir_glob "$old_glob" "$real_file"
}

# ---------------------------------------------------------------------------
# FINDING 3 — the three scripts both filters call unconditionally must exist for real.
# Fixing findings 1/2 without writing these would trade a silent skip for a hard, every-
# run CI failure the moment either filter actually matches. HARD REQUIREMENT, not
# `[ -x ]`-guarded: these scripts ARE the gates, and an optional gate is the same silent
# gap findings 1/2 already were.
# ---------------------------------------------------------------------------

@test "gate 10: tools/check-migrations.sh exists, is executable, and passes on this tree" {
  [ -x "$REPO_ROOT/tools/check-migrations.sh" ]
  run "$REPO_ROOT/tools/check-migrations.sh"
  [ "$status" -eq 0 ]
}

@test "gate 17: tools/mutation-scope.sh and tools/test-mutation-scope.sh exist and are executable" {
  [ -x "$REPO_ROOT/tools/mutation-scope.sh" ]
  [ -x "$REPO_ROOT/tools/test-mutation-scope.sh" ]
}

@test "gate 17: tools/mutation-scope.sh is self-tested, and the self-test passes" {
  run "$REPO_ROOT/tools/test-mutation-scope.sh"
  [ "$status" -eq 0 ]
}

@test "gate 10/17 scripts are called unconditionally (no [ -x ] guard) — a hard requirement, not an optional step" {
  ! grep -qE '\[\s*-x\s+tools/check-migrations\.sh\s*\]' "$VALIDATION"
  ! grep -qE '\[\s*-x\s+\./?tools/mutation-scope\.sh\s*\]' "$MUTATION"
  ! grep -qE '\[\s*-x\s+tools/test-mutation-scope\.sh\s*\]' "$MUTATION"
}

# ---------------------------------------------------------------------------
# FINDING 4 — agents-scheduled.yml ran the challenger agent with no credential
# preflight. The challenger's role resolves to compatible-endpoint, whose credential is
# OPTIONAL (.agents/config.yml auth.compatible-endpoint.required: false): absent it
# should degrade to nothing running, never fail the scheduled run. run-agent.sh exits 6
# for exactly that case, and an Actions step fails on ANY non-zero exit — so without a
# preflight that catches exit 6 and stops there, the very first dry-run a Codex/Gemini-
# style adopter does after enabling the challenger goes red. review.yml's
# challenge-review job already solves this; agents-scheduled.yml must use the same shape.
# ---------------------------------------------------------------------------

@test "agents-scheduled.yml: the run step is gated on a --check-credentials preflight" {
  grep -q -- '--check-credentials "\${{ matrix.agent }}"' "$SCHEDULED"
  grep -qE "if: steps\.gate\.outputs\.run == 'true' && steps\.creds\.outputs\.ok == 'true'" "$SCHEDULED"
}

@test "agents-scheduled.yml: exit 6 (absent optional credential) degrades, never fails the job" {
  grep -q '6) echo "ok=false"' "$SCHEDULED"
  grep -q '# degrade, never cancel' "$SCHEDULED"
}

@test "agents-scheduled.yml preflight matches review.yml's challenge-review shape (same contract, same code shape)" {
  grep -q -- '--check-credentials' "$REVIEW"
  grep -q '6) echo "run=false"' "$REVIEW"
}

# ---------------------------------------------------------------------------
# FINDING 5 — steward.yml's own header comment (lines ~86-95) asserts that
# `issues.opened` is "the ONE path with no sender check". The `issues.assigned` branch
# contradicted it by omission: every other trigger (issue_comment,
# pull_request_review_comment, pull_request_review) ANDs in
# `github.event.sender.type != 'Bot'`, and `issues.assigned` did not. A bot with
# issue-write access auto-assigning an already-mentioned issue could restart the steward
# with no human involved.
# ---------------------------------------------------------------------------

@test "steward.yml: the issues.assigned trigger requires a non-bot sender, like every other tag-gated trigger" {
  grep -qE "action == 'assigned' && github\.event\.sender\.type != 'Bot'" "$STEWARD"
}

@test "steward.yml: issues.opened remains the only trigger with no sender check (comment and code agree)" {
  # Exactly one branch in the job's if: EXPRESSION (not the whole file, which reuses
  # 'issues'/'opened' elsewhere for unrelated steps) has no `sender.type` check — the
  # auto-triage path. Every other branch (assigned, issue_comment, both review types)
  # carries the check. Isolate the expression block: from the `if: |` line that starts
  # the job-level condition to the blank line that ends it.
  block="$(awk '/^    if: \|$/{flag=1; next} flag && /^\s*$/{exit} flag' "$STEWARD")"
  [ -n "$block" ]
  total_branches="$(printf '%s\n' "$block" | grep -cE "github\.event_name == '(issues|issue_comment|pull_request_review_comment|pull_request_review)'")"
  branches_with_sender_check="$(printf '%s\n' "$block" | grep -cE "github\.event_name == '(issues|issue_comment|pull_request_review_comment|pull_request_review)'.*github\.event\.sender\.type != 'Bot'")"
  [ "$total_branches" -eq 5 ]
  [ "$branches_with_sender_check" -eq 4 ]
  grep -qi 'ONE path with no sender check' "$STEWARD"
}
