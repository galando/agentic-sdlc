#!/usr/bin/env bash
#
# collect-review-comment.sh — the ONE collector that decides whether a role's
# review reached a pull request, and returns EVERYTHING that role posted.
#
# Used by both lost-review checks in .github/workflows/review.yml (the judge
# job's and the challenge job's). It used to live inline in the judge step;
# the challenge check needed the identical program, and two copies of a
# collector is how the upstream system once lost half of one — so the program
# moved here, to exactly one home, and the workflow steps call it.
# tests/harness-guards/review-collector.bats executes THIS script against
# crafted fixtures, so the program the guard proves is the program that runs.
#
# A pull-request thread is PUBLIC: anyone may comment there — a human, another
# bot, a status integration. Three filters make a comment a REVIEW rather than
# a comment, and all three are load-bearing:
#
#   1. TIME     — created since the caller's recorded job start, so a previous
#                 run's review is not read back as this one's output.
#   2. IDENTITY — it carries the role marker (`<!-- reviewer: <role> -->`) the
#                 reviewer's prompt is required to emit as its first line.
#                 Every role posts from the SAME bot account, so a login can
#                 never tell two reviews apart; the marker can.
#   3. ORDER    — chronological by timestamp, explicitly sorted. The comment
#                 endpoints are CONCATENATED, and concatenation order is not
#                 chronological: without the sort, an inline finding lands
#                 after every conversation comment whatever time it was
#                 written, and the rendered review reads out of order.
#
# Dropping (2) disarms the lost-review detector in both directions at once: an
# unrelated human comment makes a lost review look posted, and a human "looks
# fine" reads as the reviewer's opinion. Dropping (3) scrambles the review.
#
# A REVIEW HAS THREE SHAPES, AND EVERY ITEM IS KEPT. A reviewer can post a
# top-level conversation comment, an inline comment on a code line, or a
# pull-request review (the "submit review" form, which has its own endpoint).
# This reads all three. It keeps EVERY item that carries the marker — never
# `| last`: taking the newest item threw away every inline finding but one,
# and a finding that is on the pull request but not in the collected body is
# a finding the referee never sees and the handoff never names. An inline
# comment that carries no marker itself but belongs to a review submission
# whose body does is that role's too. Items are rendered in time order, an
# inline item headed by its `path:line`, joined with `---`.
#
# NO TIME-SPLIT FALLBACK for unmarked items, on purpose. Upstream assigned an
# unmarked bot item to a reviewer by whether it came before or after the second
# reviewer's job started. Here every notice the workflow itself posts ("no
# review is coming", "did not run") comes from the same account as the reviews,
# so a time split would count the notice that says a review is missing AS that
# review. The marker is the only discriminator; unmarked items are dropped.
#
# Usage:
#   collect-review-comment.sh --marker STR --since ISO --repo OWNER/NAME --pr N
#   collect-review-comment.sh --marker STR --since ISO --from-files C1 C2 [C3]
#
# The first form reads all three homes (issue comments, pull-request review
# comments, pull-request reviews) via `gh api --paginate --slurp`; the second
# reads page-shaped JSON files, which is what the harness feeds it — the third
# file (reviews) may be omitted. Prints every matching item joined with a
# `---` separator line, or nothing. Exits non-zero only when GitHub could not
# be asked — the caller must treat that as "could not look", never as "looked
# and found nothing".
set -euo pipefail

MARKER='' SINCE='' REPO='' PR='' C1='' C2='' C3=''
while [ $# -gt 0 ]; do
    case "$1" in
        --marker) MARKER="$2"; shift ;;
        --since)  SINCE="$2";  shift ;;
        --repo)   REPO="$2";   shift ;;
        --pr)     PR="$2";     shift ;;
        --from-files)
            C1="$2"; C2="$3"; shift 2
            # The third file is optional so the two-file call shape still works.
            if [ $# -gt 1 ] && [ "${2#--}" = "$2" ]; then C3="$2"; shift; fi
            ;;
        *) echo "collect-review-comment.sh: unknown option $1" >&2; exit 2 ;;
    esac
    shift
done
if [ -z "$MARKER" ] || [ -z "$SINCE" ]; then
    echo "collect-review-comment.sh: --marker and --since are required" >&2; exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -z "$C1" ]; then
    if [ -z "$REPO" ] || [ -z "$PR" ]; then
        echo "collect-review-comment.sh: --repo and --pr are required without --from-files" >&2; exit 2
    fi
    C1="$WORK/c1.json"
    C2="$WORK/c2.json"
    C3="$WORK/c3.json"
    # ALL THREE homes. A review item lives at one of three endpoints —
    # conversation comments, inline review comments, and review submissions —
    # and a collector that reads fewer loses whichever shape the reviewer used.
    gh api "repos/$REPO/issues/$PR/comments" --paginate --slurp > "$C1"
    gh api "repos/$REPO/pulls/$PR/comments"  --paginate --slurp > "$C2"
    gh api "repos/$REPO/pulls/$PR/reviews"   --paginate --slurp > "$C3"
fi

# A missing or empty third file reads as "no review submissions".
if [ -z "$C3" ] || [ ! -s "$C3" ]; then
    C3="$WORK/c3-empty.json"
    printf '[]\n' > "$C3"
fi

# `--paginate --slurp` yields an ARRAY OF PAGES; flatten before filtering.
# One flat record per item, EVERY marked item — never `| last`.
jq -r --arg since "$SINCE" --arg marker "$MARKER" -s '
  def flat(x): [ x[] | (if length > 0 and (.[0] | type) == "array" then add else . end) ] | add // [];
  ( flat([.[0]])
    | map(select((.created_at // "") >= $since))
    | map({ts: .created_at, kind: "comment", path: null, line: null,
           id, html_url, review_id: null, body: (.body // "")})
  ) + (
    flat([.[1]])
    | map(select((.created_at // "") >= $since))
    | map({ts: .created_at, kind: "inline", path, line: (.line // .original_line),
           id, html_url, review_id: .pull_request_review_id, body: (.body // "")})
  ) + (
    flat([.[2]])
    | map(select((.submitted_at // "") >= $since))
    | map({ts: .submitted_at, kind: "review", path: null, line: null,
           id, html_url, review_id: .id, body: (.body // "")})
  )
  | . as $all
  # Review submissions whose body carries the marker: their inline comments
  # belong to the same role even when the model forgot the marker on each one.
  | [ $all[] | select(.kind == "review" and (.body | contains($marker))) | .review_id ] as $marked_reviews
  | [ $all[]
      | select( (.body | contains($marker))
                or (.kind == "inline" and .review_id != null
                    and (. as $it | any($marked_reviews[]; . == $it.review_id))) ) ]
  | sort_by(.ts)
  | map( if .kind == "inline" and .path != null and .line != null then
           "**`" + .path + ":" + (.line | tostring) + "`**\n\n" + .body
         else .body end )
  | join("\n\n---\n\n")
' "$C1" "$C2" "$C3"
