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
# the reviewer's blocking findings, so the steward handoff is suppressed and real findings
# are stranded. That second direction is the exact failure the handoff step was built to
# fix — the collector would have re-created it one level up.
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

# Extract the handoff step's jq program verbatim from the workflow. Running the real
# program is the point: a copy pasted into this file would drift from the workflow the
# first time somebody edited one and not the other, and this guard would then be
# asserting things about a program that no longer runs anywhere.
handoff_jq() {
  awk '/BODY="\$\(jq -r --arg since/ {f=1; next} f && /\/tmp\/c1\.json \/tmp\/c2\.json/ {f=0} f' "$REVIEW"
}

run_handoff() { # conversation-page-file inline-page-file
  jq -r --arg since "$SINCE" -s "$(handoff_jq)" "$1" "$2"
}

@test "review collector: the handoff jq program can be located in the workflow" {
  # If this fails the extraction below is silently testing an empty program, which would
  # make every assertion in this file pass for the wrong reason.
  prog="$(handoff_jq)"
  [ -n "$prog" ]
  [[ "$prog" == *"add"* ]]
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

@test "review collector: the handoff reads BOTH comment homes" {
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

@test "review collector: both endpoints are queried, in the handoff and in the referee" {
  # Four calls: two endpoints x two collectors. A collector that drops back to one
  # endpoint is the single-home bug returning.
  run grep -cE 'gh api "repos/\$REPO/issues/\$PR/comments" --paginate --slurp' "$REVIEW"
  [ "$output" -eq 2 ]
  run grep -cE 'gh api "repos/\$REPO/pulls/\$PR/comments"' "$REVIEW"
  [ "$output" -eq 2 ]
}

@test "review collector: selection is by positive role marker, never by exclusion" {
  # Selecting role A as "everything that is not role B" makes any unmarked comment —
  # status chatter, a human, a retry — count as role A's review.
  run grep -c 'select(.body | contains("<!-- reviewer: judge -->"))' "$REVIEW"
  [ "$output" -ge 2 ]
  run grep -c 'select(.body | contains("<!-- reviewer: challenge -->"))' "$REVIEW"
  [ "$output" -ge 1 ]
  # No negated marker test anywhere: that is the exclusion shape.
  run grep -cE 'contains\("<!-- reviewer:[^"]*"\)[[:space:]]*\|[[:space:]]*not' "$REVIEW"
  [ "$output" -eq 0 ]
}

@test "review collector: the referee's own collector still slurps before it filters" {
  # `--paginate` with a per-item `--jq` applies the filter once PER PAGE and emits one
  # array per page, so "take the last one" silently returns one result per page.
  # Invisible until a thread passes 100 comments — which is when you need it to be right.
  run grep -c -- '--paginate --slurp' "$REVIEW"
  [ "$output" -ge 4 ]
}
