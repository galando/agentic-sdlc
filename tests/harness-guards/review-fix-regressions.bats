#!/usr/bin/env bats
#
# Gate 22 guards for a review round that found five defects, all variations on the same
# theme: a gate that LOOKS armed but silently checks nothing, or silently cancels instead
# of degrading. Each of these was verified against the raw workflow files before the fix
# landed; this file pins the fix so it cannot regress unnoticed.
#
# ---------------------------------------------------------------------------
# FINDINGS 1 & 2 — gate 10 and gate 17 once pointed at a path where the product does
# not live. A paths-filter that never matches makes its job report "skipped", which
# satisfies a required check exactly as cleanly as a real pass — so the gate went quiet
# instead of red, and nobody watching CI could tell the difference from "nothing
# changed here". Only a change under the real path — not the dead one — proves the
# drift is gone.
#
# LAYOUT-AWARE: the guarded invariant is "every filter targets where the product
# ACTUALLY lives, and the dead path appears nowhere" — and where the product lives has
# two legitimate answers. The template ships it at examples/backend (the bundled
# example); an adopted tree carries it at top-level backend/ (the layout
# tools/adopt-layout.sh re-points to and tools/measure-floors.sh calibrates against).
# The guards detect which tree they are on and pin the SAME invariant either way, so
# adopting the layout never requires editing a test file.
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
VALIDATION="$REPO_ROOT/.github/workflows/pr-validation.yml"
MUTATION="$REPO_ROOT/.github/workflows/pr-mutation.yml"
SCHEDULED="$REPO_ROOT/.github/workflows/agents-scheduled.yml"
STEWARD="$REPO_ROOT/.github/workflows/steward.yml"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"

if [ -d "$REPO_ROOT/examples/backend" ]; then
  # Template layout. The dead path is anchored as a list item ('backend/ at the start
  # of a filter entry) because bare "backend/" is a substring of the live path.
  PRODUCT_BACKEND="examples/backend"
  DEAD_FILTER_RE="^[[:space:]]*-[[:space:]]*'backend/"
  DEAD_WD_RE='working-directory: \./backend[^/a-zA-Z]'
  DEAD_ARTIFACT_RE='^[[:space:]]*path: backend/'
  TOOLS_UP="../../"
  DEAD_TOOLS_UP="../"
else
  # Adopter layout (post tools/adopt-layout.sh). The roles reverse exactly.
  PRODUCT_BACKEND="backend"
  DEAD_FILTER_RE="'examples/backend/"
  DEAD_WD_RE='working-directory: \./examples/backend'
  DEAD_ARTIFACT_RE='^[[:space:]]*path: examples/backend/'
  TOOLS_UP="../"
  DEAD_TOOLS_UP="../../"
fi

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

@test "gate 10: pr-validation.yml's migration filter targets the live product path, never the dead one" {
  grep -qF "'${PRODUCT_BACKEND}/src/main/resources/db/migration/**'" "$VALIDATION"
  ! grep -qE "$DEAD_FILTER_RE" "$VALIDATION"
}

@test "gate 10: pr-validation.yml's working-directory targets the live product path" {
  grep -qF "working-directory: ./${PRODUCT_BACKEND}" "$VALIDATION"
  ! grep -qE "$DEAD_WD_RE" "$VALIDATION"
}

@test "gate 10 DEMONSTRATION: a real migration file trips the corrected filter, and would have missed the old one" {
  glob="${PRODUCT_BACKEND}/src/main/resources/db/migration/**"
  real_file="$(cd "$REPO_ROOT" && ls "${PRODUCT_BACKEND}"/src/main/resources/db/migration/V*__*.sql 2>/dev/null | head -n1 || true)"
  [ -n "$real_file" ] || skip "no product migration at ${PRODUCT_BACKEND} yet — this re-arms once the product is wired in"
  path_matches_dir_glob "$glob" "$real_file"

  # The dead path's glob would never match this real file — proving the filter guards
  # the layout the product actually has, not a naming preference.
  old_glob="$([ "$PRODUCT_BACKEND" = "examples/backend" ] && echo "backend" || echo "examples/backend")/src/main/resources/db/migration/**"
  ! path_matches_dir_glob "$old_glob" "$real_file"
}

@test "gate 17: pr-mutation.yml's scope filter targets the live product path, never the dead one" {
  grep -qF "'${PRODUCT_BACKEND}/src/main/java/**'" "$MUTATION"
  ! grep -qE "$DEAD_FILTER_RE" "$MUTATION"
}

@test "gate 17: pr-mutation.yml's working-directory entries all target the live product path" {
  wd_count="$(grep -cF "working-directory: ./${PRODUCT_BACKEND}" "$MUTATION")"
  [ "$wd_count" -eq 2 ]
  ! grep -qE "$DEAD_WD_RE" "$MUTATION"
}

@test "gate 17: pr-mutation.yml's artifact upload path targets the live product path" {
  grep -qF "path: ${PRODUCT_BACKEND}/target/pit-reports/" "$MUTATION"
  ! grep -qE "$DEAD_ARTIFACT_RE" "$MUTATION"
}

@test "gate 17: the floor-get relative path was re-based for the deeper working-directory" {
  # The ../-depth must match the working-directory's depth under the root — one ../
  # per level, no more, no fewer. Fixed-string (-F) matches anchored on '-x ' and '"$(',
  # so neither depth's literal is a substring of the other's at the same anchor.
  grep -qF -- "-x ${TOOLS_UP}tools/floor-get.sh" "$MUTATION"
  grep -qF -- "${TOOLS_UP}tools/floor-get.sh backend.mutation.score" "$MUTATION"
  ! grep -qF -- "-x ${DEAD_TOOLS_UP}tools/floor-get.sh" "$MUTATION"
  ! grep -qF -- "\"\$(${DEAD_TOOLS_UP}tools/floor-get.sh" "$MUTATION"
}

@test "gate 17 DEMONSTRATION: a real production class trips the corrected filter, and would have missed the old one" {
  glob="${PRODUCT_BACKEND}/src/main/java/**"
  real_file="$(cd "$REPO_ROOT" && find "${PRODUCT_BACKEND}/src/main/java" -name '*.java' 2>/dev/null | head -n1 || true)"
  [ -n "$real_file" ] || skip "no product classes at ${PRODUCT_BACKEND} yet — this re-arms once the product is wired in"
  path_matches_dir_glob "$glob" "$real_file"

  old_glob="$([ "$PRODUCT_BACKEND" = "examples/backend" ] && echo "backend" || echo "examples/backend")/src/main/java/**"
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
