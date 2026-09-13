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
#   3. ORDER    — chronological, explicitly sorted. Three endpoints are read and merged,
#                 and concatenation order is NOT chronological: without the sort every
#                 inline finding lands after every conversation comment whatever its time.
#
# Drop (2) and the lost-review detector below it is disarmed in both directions at once:
# any unrelated human comment in the window makes the body non-empty, so a review that
# posted nothing looks like a review that posted; and a human "looks fine to me" reads as
# the reviewer's opinion, so this reviewer reads as having posted a clean review and its
# real findings are stranded. That second direction is the exact failure the handoff was
# built to fix — the collector would have re-created it one level up.
#
# AND EVERY MARKED ITEM IS KEPT — never `| last`. A review has three shapes: a top-level
# conversation comment, an inline comment on a code line, and a review submission, each
# on its own endpoint. A reviewer that posts its findings as several inline comments has
# posted several items, and "the newest one" threw away all but one of them: an item that
# is on the pull request but not in the collected body is a finding the referee never
# sees and the handoff never names. Items are rendered in time order, an inline item
# headed by its `path:line`, joined with `---`.
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

# An inline comment on a code line, shaped like the pulls/N/comments endpoint returns it.
inline() { # created_at, body, path, line, [review_id], [id]
  jq -nc --arg t "$1" --arg b "$2" --arg p "$3" --argjson l "$4" \
         --argjson r "${5:-null}" --argjson i "${6:-1}" \
     '{created_at: $t, body: $b, path: $p, line: $l, pull_request_review_id: $r, id: $i,
       html_url: ("https://e.invalid/pr/12#discussion_r" + ($i | tostring))}'
}

# A review submission, shaped like the pulls/N/reviews endpoint returns it.
review() { # submitted_at, body, id
  jq -nc --arg t "$1" --arg b "$2" --argjson i "$3" \
     '{submitted_at: $t, body: $b, id: $i, html_url: ("https://e.invalid/pr/12#pullrequestreview-" + ($i | tostring))}'
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

run_handoff() { # conversation-page-file inline-page-file [reviews-page-file]
  "$COLLECTOR" --marker '<!-- reviewer: judge -->' --since "$SINCE" --from-files "$@"
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

@test "review collector: EVERY marked item is kept, in time order, not the newest by endpoint" {
  # Two marked items from the same run. Both are kept — `| last` used to drop the earlier
  # one, and when a reviewer posts its findings as several items, that is every finding
  # but one. Concatenation order puts every inline comment after every conversation
  # comment regardless of time, so the explicit sort is what makes the rendered review
  # read in the order it was written.
  page "$(comment "2026-08-05T10:20:00Z" "<!-- reviewer: judge -->
Second item, posted later.")" > "$FIX/c1.json"
  page "$(comment "2026-08-05T10:05:00Z" "<!-- reviewer: judge -->
BLOCKING: first item, posted earlier.")" > "$FIX/c2.json"

  run run_handoff "$FIX/c1.json" "$FIX/c2.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"first item, posted earlier"* ]]
  [[ "$output" == *"Second item, posted later"* ]]
  # Earlier first, whichever endpoint it came from.
  first="${output%%Second item*}"
  [[ "$first" == *"first item, posted earlier"* ]]
  # Joined with a separator line, so the referee can tell where one item ends.
  [[ "$output" == *$'\n\n---\n\n'* ]]
}

@test "review collector: no '| last' anywhere in the collector or the referee's render" {
  # The construct itself. Whatever else changes, taking one item out of many is the bug.
  # Comment lines are excluded — the notes explaining WHY it is banned quote it.
  run grep -nE '^[^#]*\|[[:space:]]*last([[:space:]]|$)' "$COLLECTOR"
  [ "$status" -ne 0 ]
  run grep -nE '^[^#]*\|[[:space:]]*last([[:space:]]|$)' "$REVIEW"
  if [ "$status" -eq 0 ]; then
    echo "# '| last' still in review.yml:"; echo "$output" | sed 's/^/#   /'; false
  fi
}

@test "review collector: three shapes — conversation, inline with path:line, and a review submission" {
  # The fixture the lesson asks for: three marked items, one of them inline on a code
  # line. All three must come back, the inline one headed by its path:line so the
  # referee and the handoff can still cite it.
  page "$(comment "2026-08-05T10:05:00Z" "<!-- reviewer: judge -->
Summary: two findings, one blocking.")" > "$FIX/c1.json"
  page "$(inline "2026-08-05T10:06:00Z" "<!-- reviewer: judge -->
BLOCKING: the error is dropped here." "src/a.js" 10 77 501)" > "$FIX/c2.json"
  page "$(review "2026-08-05T10:07:00Z" "<!-- reviewer: judge -->
Review submission: overall the change is sound." 77)" > "$FIX/c3.json"

  run run_handoff "$FIX/c1.json" "$FIX/c2.json" "$FIX/c3.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Summary: two findings"* ]]
  [[ "$output" == *"the error is dropped here"* ]]
  [[ "$output" == *"Review submission: overall"* ]]
  [[ "$output" == *'**`src/a.js:10`**'* ]]
  # Two separators for three items.
  [ "$(printf '%s\n' "$output" | grep -c '^---$')" -eq 2 ]
}

@test "review collector: an unmarked inline comment inherits the marker of its review submission" {
  # A model that submits a review with the marker in the summary body and forgets it on
  # each inline comment has still posted those findings as that role. The submission id
  # links them; the time-split fallback upstream used is deliberately NOT here, because
  # the workflow's own notices come from the same account as the reviews.
  page "" > "$FIX/c1.json"
  page "$(inline "2026-08-05T10:06:00Z" "Drops the error." "src/a.js" 10 77 501),$(inline "2026-08-05T10:06:30Z" "Orphan inline, no submission, no marker." "src/b.js" 3 null 502)" > "$FIX/c2.json"
  page "$(review "2026-08-05T10:07:00Z" "<!-- reviewer: judge -->
Two inline findings below." 77)" > "$FIX/c3.json"

  run run_handoff "$FIX/c1.json" "$FIX/c2.json" "$FIX/c3.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Drops the error."* ]]
  [[ "$output" == *'**`src/a.js:10`**'* ]]
  [[ "$output" != *"Orphan inline"* ]]
}

@test "review collector: the third file is optional, and the two-file call still works" {
  page "$(comment "2026-08-05T10:05:00Z" "<!-- reviewer: judge -->
Only a conversation comment.")" > "$FIX/c1.json"
  page "" > "$FIX/c2.json"
  run run_handoff "$FIX/c1.json" "$FIX/c2.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Only a conversation comment"* ]]
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

@test "review collector: all THREE endpoints are queried, in the shared collector and in the referee" {
  # Three endpoints x two collector homes. A collector that drops back to fewer is the
  # single-home bug returning — whichever file it returns in.
  for ep in 'issues/\$PR/comments' 'pulls/\$PR/comments' 'pulls/\$PR/reviews'; do
    run grep -cE "gh api \"repos/\\\$REPO/$ep\" +--paginate --slurp" "$REVIEW"
    [ "$output" -eq 1 ] || { echo "review.yml: $ep queried $output times"; return 1; }
    run grep -cE "gh api \"repos/\\\$REPO/$ep\" +--paginate --slurp" "$COLLECTOR"
    [ "$output" -eq 1 ] || { echo "collector: $ep queried $output times"; return 1; }
  done
}

@test "review collector: selection is by positive role marker, never by exclusion" {
  # Selecting role A as "everything that is not role B" makes any unmarked comment —
  # status chatter, a human, a retry — count as role A's review. The shared collector
  # takes the marker as an argument and matches it POSITIVELY; the workflow must pass a
  # positive marker at each call site, and the referee's inline collector keeps its own
  # positive selects.
  run grep -c 'contains($marker)' "$COLLECTOR"
  [ "$output" -ge 1 ]
  run grep -c 'contains("<!-- reviewer: judge -->")' "$REVIEW"
  [ "$output" -ge 1 ]
  run grep -c 'contains("<!-- reviewer: challenge -->")' "$REVIEW"
  [ "$output" -ge 1 ]
  # No negated marker test anywhere: that is the exclusion shape.
  run grep -cE 'contains\("<!-- reviewer:[^"]*"\)\)?[[:space:]]*\|[[:space:]]*not' "$REVIEW"
  [ "$output" -eq 0 ]
  run grep -cE 'contains\(\$marker\)\)?[[:space:]]*\|[[:space:]]*not' "$COLLECTOR"
  [ "$output" -eq 0 ]
}

# ---------------------------------------------------------------------------
# THE REFEREE'S OWN COLLECTOR MUST AGREE WITH THE SHARED SCRIPT. The referee keeps an
# inline jq (its flatten is a pinned string, and it also needs the record list for the
# inline-thread inventory). Two programs drift, so these extract the referee's programs
# out of the workflow and run them against the same fixtures the script gets — the
# rendered body must be identical, and the thread inventory must list the inline item.
# ---------------------------------------------------------------------------

# The jq program between `jq --arg since "$SINCE" -s '` and the closing `' file...` line,
# in the "Collect both reviews" step.
extract_referee_records_jq() {
  awk '
    /^      - name: Collect both reviews/ { instep = 1; next }
    instep && /^      - name:/ { exit }
    instep && /^          jq --arg since "\$SINCE" -s .$/ { inside = 1; next }
    inside && /^          . \.review-artifacts\/conversation\.json/ { exit }
    inside { print }
  ' "$REVIEW"
}

# The body of render_role()'s jq program.
extract_referee_render_jq() {
  awk '
    /^          render_role\(\) \{/ { infn = 1; next }
    infn && /^            jq -r --arg who "\$1" .$/ { inside = 1; next }
    inside && /^            . \.review-artifacts\/all\.json/ { exit }
    inside { print }
  ' "$REVIEW"
}

@test "referee collector: the programs can be extracted (otherwise the equivalence test is vacuous)" {
  records="$(extract_referee_records_jq)"
  [ -n "$records" ]
  [[ "$records" == *"then add else . end"* ]]
  render="$(extract_referee_render_jq)"
  [ -n "$render" ]
  [[ "$render" == *'join("\n\n---\n\n")'* ]]
}

@test "referee collector: renders the SAME body as the shared script for the three-shape fixture" {
  page "$(comment "2026-08-05T10:05:00Z" "<!-- reviewer: judge -->
Summary: two findings, one blocking.")" > "$FIX/c1.json"
  page "$(inline "2026-08-05T10:06:00Z" "<!-- reviewer: judge -->
BLOCKING: the error is dropped here." "src/a.js" 10 77 501),$(inline "2026-08-05T10:06:30Z" "Unmarked, inherits from submission 77." "src/c.js" 4 77 503),$(comment "2026-08-05T10:08:00Z" "<!-- reviewer: challenge -->
The challenge role's own inline note, no path.")" > "$FIX/c2.json"
  page "$(review "2026-08-05T10:07:00Z" "<!-- reviewer: judge -->
Review submission: overall the change is sound." 77)" > "$FIX/c3.json"

  extract_referee_records_jq > "$FIX/records.jq"
  extract_referee_render_jq  > "$FIX/render.jq"
  jq --arg since "$SINCE" -s -f "$FIX/records.jq" "$FIX/c1.json" "$FIX/c2.json" "$FIX/c3.json" > "$FIX/all.json"
  jq -r --arg who judge -f "$FIX/render.jq" "$FIX/all.json" > "$FIX/referee-judge.md"
  jq -r --arg who challenge -f "$FIX/render.jq" "$FIX/all.json" > "$FIX/referee-challenge.md"

  run_handoff "$FIX/c1.json" "$FIX/c2.json" "$FIX/c3.json" > "$FIX/script-judge.md"
  "$COLLECTOR" --marker '<!-- reviewer: challenge -->' --since "$SINCE" \
    --from-files "$FIX/c1.json" "$FIX/c2.json" "$FIX/c3.json" > "$FIX/script-challenge.md"

  diff "$FIX/referee-judge.md" "$FIX/script-judge.md"
  diff "$FIX/referee-challenge.md" "$FIX/script-challenge.md"
  # And the bodies are what the fixture promises: every item, the inherited one included.
  grep -q 'src/a.js:10' "$FIX/referee-judge.md"
  grep -q 'inherits from submission 77' "$FIX/referee-judge.md"
  grep -q 'Review submission: overall' "$FIX/referee-judge.md"
  grep -q "challenge role's own" "$FIX/referee-challenge.md"
  ! grep -q "challenge role's own" "$FIX/referee-judge.md"
}

@test "referee collector: the inline-thread inventory names every inline item with its role" {
  page "" > "$FIX/c1.json"
  page "$(inline "2026-08-05T10:06:00Z" "<!-- reviewer: judge -->
BLOCKING: the error is dropped here." "src/a.js" 10 null 501),$(inline "2026-08-05T10:09:00Z" "<!-- reviewer: challenge -->
Also this." "src/b.js" 2 null 502)" > "$FIX/c2.json"
  page "" > "$FIX/c3.json"

  extract_referee_records_jq > "$FIX/records.jq"
  jq --arg since "$SINCE" -s -f "$FIX/records.jq" "$FIX/c1.json" "$FIX/c2.json" "$FIX/c3.json" > "$FIX/all.json"
  # The same program the workflow runs to write inline-threads.json.
  threads_jq="$(grep -oE "jq '\[ \.\[\] \| select\(\.kind == \"inline\"\)[^']*'" "$REVIEW" | head -n1 | sed "s/^jq '//; s/'$//")"
  [ -n "$threads_jq" ]
  run jq -c "$threads_jq" "$FIX/all.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"reviewer":"judge"'* ]]
  [[ "$output" == *'"reviewer":"challenge"'* ]]
  [[ "$output" == *'"path":"src/a.js"'* ]]
  [[ "$output" == *'"line":10'* ]]
  [[ "$output" == *'"id":502'* ]]
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
