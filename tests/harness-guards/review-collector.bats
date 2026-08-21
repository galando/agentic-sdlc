#!/usr/bin/env bats
#
# Gate 22 guard — the two comment collectors in `.github/workflows/review.yml`.
#
# BEHAVIOURAL, not a text pin. Every other guard in this directory asserts that a
# load-bearing STRING survived substitution. These assertions extract the actual `jq`
# programs out of the workflow file and run them against crafted comment fixtures,
# because the defect they exist to catch was not a missing string — it was a filter that
# had been dropped and replaced with nothing, in a step whose remaining text still read
# as if it were there.
#
# ---------------------------------------------------------------------------
# THE LESSON. A collector that gathers "the comments on this pull request" is gathering
# from a public thread. Anyone may comment there — a human, another bot, a status
# integration. Three filters make a comment a REVIEW rather than a comment, and all three
# have to be present at once:
#
#   1. TIME     — created since this run's recorded job start, so a previous run's review
#                 is not mistaken for this one's.
#   2. IDENTITY — it carries the role marker its reviewer's prompt is required to emit.
#                 The upstream system filtered on the bot's login; a template cannot,
#                 because it does not know the adopter's bot account. The marker is the
#                 portable form of the same filter, and it is strictly better: every role
#                 posts from the same account, so a login cannot tell two reviews apart.
#   3. ORDER    — newest by `created_at`. Two endpoints are read and merged, and
#                 concatenation order is NOT chronological: `last` over a merged list
#                 returns the last INLINE comment whenever any exists, whatever its time.
#
# Drop (2) and the lost-review detector below it is disarmed in both directions at once:
# any unrelated human comment in the window makes the body non-empty, so a review that
# posted nothing looks like a review that posted; and a human "looks fine to me" outranks
# the reviewer's blocking findings, so this reviewer reads as having posted a clean review
# and its real findings are stranded. That second direction is the exact failure the
# handoff was built to fix — the collector would have re-created it one level up.
#
# Drop (3) and the same suppression happens on timing alone, with no human involved.
# ---------------------------------------------------------------------------
#
# Hand-written, like `ci-health-watch.bats`. `pins.json` entry
# `collector-single-endpoint-must-merge-both` is `semantic-manual` — the source's filter
# was an account login, which by definition could not survive genericisation — so no
# mechanical pin over the source string is possible and Task 20's generated suite will not
# produce one. See `tests/harness-guards/semantic-discharges.md` #12.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
REVIEW="$REPO_ROOT/.github/workflows/review.yml"

# `--paginate --slurp` yields an ARRAY OF PAGES. Both collectors flatten that before
# filtering, so every fixture here is shaped the way the real API response is: a list of
# pages, each a list of comments. Feeding a flat list would test a shape the collector
# never sees.
page() { printf '[[%s]]\n' "$1"; }

comment() { # created_at, body
  jq -nc --arg t "$1" --arg b "$2" '{created_at: $t, body: $b}'
}

setup() {
  FIX="$(mktemp -d)"
  export FIX
  SINCE="2026-08-05T10:00:00Z"
  export SINCE
}

teardown() { rm -rf "$FIX"; }

# The collector program used to live inline in the judge step's lost-review check and
# was extracted from the YAML by awk here. When the challenge job grew its own
# lost-review check it needed the identical program, and two copies of a collector is
# how the upstream system once lost half of one — so the program moved to
# tools/collect-review-comment.sh, its ONE home, and both workflow steps call it.
# These assertions therefore execute the real script directly (the meta-doctrine's
# stronger form: when a guard must execute, run the real logic), and the call-site
# checks below prove the workflow actually invokes it for both roles.
COLLECTOR="$REPO_ROOT/tools/collect-review-comment.sh"

run_handoff() { # conversation-page-file inline-page-file
  "$COLLECTOR" --marker '<!-- reviewer: judge -->' --since "$SINCE" --from-files "$1" "$2"
}

@test "review collector: the shared collector exists and the workflow calls it for BOTH roles" {
  # If this fails, the assertions below are testing a program nothing runs — which would
  # make every one of them pass for the wrong reason.
  [ -x "$COLLECTOR" ]
  run grep -c "tools/collect-review-comment.sh --marker '<!-- reviewer: judge -->'" "$REVIEW"
  [ "$output" -eq 1 ]
  run grep -c "tools/collect-review-comment.sh --marker '<!-- reviewer: challenge -->'" "$REVIEW"
  [ "$output" -eq 1 ]
}

@test "review collector: a human comment in the window is NOT mistaken for a review" {
  # The original incident, exactly: the review posted nothing, and the lost-review
  # detector below this collector only fires on an EMPTY body. One unrelated human
  # comment in the same window is enough to make the body non-empty, and the detector
  # never fires — for the one failure it exists to catch.
  page "$(comment "2026-08-05T10:05:00Z" "any idea why CI is slow today?")" > "$FIX/c1.json"
  page "" > "$FIX/c2.json"

  run run_handoff "$FIX/c1.json" "$FIX/c2.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "review collector: a human inline comment cannot outrank the reviewer's findings" {
  # The merged list is a CONCATENATION, so `last` returns the last inline comment
  # whenever one exists. A human replying "looks fine to me" on a code line therefore
  # became the "review body", the clean-phrase check ran against it, and the steward
  # handoff was suppressed with the blocking findings still sitting on the pull request.
  page "$(comment "2026-08-05T10:05:00Z" "<!-- reviewer: judge -->
BLOCKING: the migration drops a column with no backfill.")" > "$FIX/c1.json"
  page "$(comment "2026-08-05T10:06:00Z" "looks fine to me")" > "$FIX/c2.json"

  run run_handoff "$FIX/c1.json" "$FIX/c2.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKING"* ]]
  [[ "$output" != *"looks fine to me"* ]]
}

@test "review collector: the newest REVIEW wins, by time and not by which endpoint it came from" {
  # Two reviews from the same run — a retry after a transient posting failure is the
  # ordinary cause. The later one is the one that counts. Concatenation order puts every
  # inline comment after every conversation comment regardless of time, so without an
  # explicit sort the SUPERSEDED review wins whenever it happens to be the inline one.
  page "$(comment "2026-08-05T10:20:00Z" "<!-- reviewer: judge -->
No issues found - the second, corrected review.")" > "$FIX/c1.json"
  page "$(comment "2026-08-05T10:05:00Z" "<!-- reviewer: judge -->
BLOCKING: stale first attempt.")" > "$FIX/c2.json"

  run run_handoff "$FIX/c1.json" "$FIX/c2.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"corrected review"* ]]
  [[ "$output" != *"stale first attempt"* ]]
}

@test "review collector: a review posted BEFORE this run's job start is out of scope" {
  # The time filter, still doing its job alongside the new marker filter. A previous
  # run's review must not be re-read as this run's output.
  page "$(comment "2026-08-05T09:00:00Z" "<!-- reviewer: judge -->
BLOCKING: from the run before this one.")" > "$FIX/c1.json"
  page "" > "$FIX/c2.json"

  run run_handoff "$FIX/c1.json" "$FIX/c2.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "review collector: the lost-review check reads BOTH comment homes" {
  # A review posted as an inline comment on a code line lives on a different endpoint
  # from a top-level conversation comment. Reading one endpoint reported a review that
  # was sitting on the pull request the whole time as missing.
  page "" > "$FIX/c1.json"
  page "$(comment "2026-08-05T10:05:00Z" "<!-- reviewer: judge -->
BLOCKING: found only on the inline endpoint.")" > "$FIX/c2.json"

  run run_handoff "$FIX/c1.json" "$FIX/c2.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"inline endpoint"* ]]
}

@test "review collector: both endpoints are queried, in the shared collector and in the referee" {
  # Two endpoints x two collector homes. A collector that drops back to one endpoint is
  # the single-home bug returning — whichever file it returns in.
  run grep -cE 'gh api "repos/\$REPO/issues/\$PR/comments" --paginate --slurp' "$REVIEW"
  [ "$output" -eq 1 ]
  run grep -cE 'gh api "repos/\$REPO/pulls/\$PR/comments"' "$REVIEW"
  [ "$output" -eq 1 ]
  run grep -cE 'gh api "repos/\$REPO/issues/\$PR/comments" --paginate --slurp' "$COLLECTOR"
  [ "$output" -eq 1 ]
  run grep -cE 'gh api "repos/\$REPO/pulls/\$PR/comments"' "$COLLECTOR"
  [ "$output" -eq 1 ]
}

@test "review collector: selection is by positive role marker, never by exclusion" {
  # Selecting role A as "everything that is not role B" makes any unmarked comment —
  # status chatter, a human, a retry — count as role A's review. The shared collector
  # takes the marker as an argument and matches it POSITIVELY; the workflow must pass a
  # positive marker at each call site, and the referee's inline collector keeps its own
  # positive selects.
  run grep -c 'select(.body | contains($marker))' "$COLLECTOR"
  [ "$output" -eq 1 ]
  run grep -c 'select(.body | contains("<!-- reviewer: judge -->"))' "$REVIEW"
  [ "$output" -ge 1 ]
  run grep -c 'select(.body | contains("<!-- reviewer: challenge -->"))' "$REVIEW"
  [ "$output" -ge 1 ]
  # No negated marker test anywhere: that is the exclusion shape.
  run grep -cE 'contains\("<!-- reviewer:[^"]*"\)[[:space:]]*\|[[:space:]]*not' "$REVIEW"
  [ "$output" -eq 0 ]
  run grep -cE 'contains\(\$marker\)[[:space:]]*\|[[:space:]]*not' "$COLLECTOR"
  [ "$output" -eq 0 ]
}

@test "review collector: the referee's own collector still slurps before it filters" {
  # `--paginate` with a per-item `--jq` applies the filter once PER PAGE and emits one
  # array per page, so "take the last one" silently returns one result per page.
  # Invisible until a thread passes 100 comments — which is when you need it to be right.
  run grep -c -- '--paginate --slurp' "$REVIEW"
  [ "$output" -ge 2 ]
  run grep -c -- '--paginate --slurp' "$COLLECTOR"
  [ "$output" -ge 2 ]
}
