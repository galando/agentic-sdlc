#!/usr/bin/env bats
#
# Gate 22 guard — `docs/runbooks/branch-protection.md` may only tell an admin to require
# a status check that actually exists.
#
# ---------------------------------------------------------------------------
# THE LESSON, and it is the nastiest one on that page because the page is ABOUT it.
#
# GitHub accepts any string as a required status context. It does not validate it against
# anything. A context nothing ever reports leaves every pull request parked at
# "Expected — waiting for status to be reported", with no failure to read and no job to
# re-run. The repository is wedged, and the only way out is an admin edit — by an admin
# who has just been told, on that same page, that these are safe to turn on immediately
# and that there is no pull request they can wedge.
#
# So a copy-pasteable ruleset is a LOADED WEAPON, and the safety on it is that every
# context in it corresponds to a job in this tree. The page's own tiering rule already
# says a required check must always report — that is why nothing is behind a
# workflow-level `paths:` filter. A context whose workflow has not been written yet fails
# the same rule for a simpler reason: it cannot report because it does not exist.
#
# The convention this file enforces, chosen so it cannot drift:
#
#   * A context inside DOUBLE QUOTES is JSON — it is in, or about to be pasted into, the
#     API payload. Every one of those must exist as a job id today.
#   * A context in BACKTICKS is prose. It may name something not yet in the tree, but its
#     table row must carry an explicit not-yet-present marker so a reader adding rows by
#     hand is warned at the exact place they would copy it from.
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
DOC="$REPO_ROOT/docs/runbooks/branch-protection.md"
WF="$REPO_ROOT/.github/workflows"

# A status-check context is the job's `name:`, or its id when it has no `name:`. Every
# gate job in this repository deliberately has no `name:` key, so that the id IS the
# context and the two can never diverge. Job ids sit at exactly two spaces of indent.
job_exists() {
  grep -rqE "^  ${1}:[[:space:]]*\$" "$WF"/*.yml
}

# Contexts as they appear in a JSON payload: "fast-unit-tests",
quoted_contexts() {
  grep -oE '"(fast|full)-[a-z0-9-]+"' "$DOC" | tr -d '"' | sort -u
}

# Contexts as they appear in the tier tables' first column: | `fast-unit-tests` |
table_contexts() {
  grep -oE '^\| `(fast|full)-[a-z0-9-]+`' "$DOC" | tr -d '|` ' | sort -u
}

@test "branch-protection: the page exists and names contexts at all" {
  # A vacuous pass here would make every assertion below meaningless.
  [ -f "$DOC" ]
  [ "$(quoted_contexts | wc -l | tr -d ' ')" -ge 5 ]
  [ "$(table_contexts | wc -l | tr -d ' ')" -ge 5 ]
}

@test "branch-protection: every context in a copy-pasteable payload exists as a job today" {
  missing=""
  while read -r ctx; do
    [ -z "$ctx" ] && continue
    job_exists "$ctx" || missing="$missing $ctx"
  done < <(quoted_contexts)
  if [ -n "$missing" ]; then
    echo "# contexts in the ruleset payload with no job in .github/workflows/:$missing"
    echo "# An admin who pastes this blocks every pull request forever, on a page that"
    echo "# promises the opposite. Remove them from the payload until their workflow lands."
    false
  fi
}

@test "branch-protection: a table row for a context not yet in the tree says so" {
  # Not-yet-written contexts are allowed on the page — the page has to describe the whole
  # ladder — but never silently. The marker goes in the row, where it is read.
  undocumented=""
  while read -r ctx; do
    [ -z "$ctx" ] && continue
    job_exists "$ctx" && continue
    row="$(grep -F "| \`${ctx}\`" "$DOC" || true)"
    case "$row" in
      *"NOT YET IN THE TREE"*) ;;
      *) undocumented="$undocumented $ctx" ;;
    esac
  done < <(table_contexts)
  if [ -n "$undocumented" ]; then
    echo "# listed as requirable with no job and no not-yet-present marker:$undocumented"
    false
  fi
}

@test "branch-protection: the page hands the admin a way to check before pasting" {
  # The durable form of this guard. This file catches drift in CI; the one-liner catches
  # it for an adopter whose fork has diverged, which is every adopter eventually.
  grep -q 'NOT PRESENT' "$DOC"
  grep -q '.github/workflows' "$DOC"
}

@test "quality-gates: the gate inventory marks any job it names that does not exist yet" {
  # The second place that told an admin these were day-one FAST-tier gates. One page
  # corrected and the other left alone is how the wrong impression survives a fix — a
  # reader who checks a claim against a second document and finds it repeated concludes
  # it is right.
  QG="$REPO_ROOT/docs/QUALITY-GATES.md"
  [ -f "$QG" ]
  undocumented=""
  while read -r ctx; do
    [ -z "$ctx" ] && continue
    job_exists "$ctx" && continue
    row="$(grep -F "\`${ctx}\`" "$QG" || true)"
    case "$row" in
      *"NOT YET IN THE TREE"*) ;;
      *) undocumented="$undocumented $ctx" ;;
    esac
  done < <(grep -oE '`(fast|full)-[a-z0-9-]+`' "$QG" | tr -d '`' | sort -u)
  if [ -n "$undocumented" ]; then
    echo "# gates named in QUALITY-GATES.md with no job and no marker:$undocumented"
    false
  fi
}

@test "branch-protection: the page states why an unknown context wedges the repository" {
  # A rule without its reason gets deleted by the next person, and the next person here
  # is an admin tidying a list that looks incomplete.
  grep -qi 'waiting for status to be reported' "$DOC"
}
