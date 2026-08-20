#!/usr/bin/env bash
#
# collect-review-comment.sh — the ONE collector that decides whether a role's
# review reached a pull request.
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
#   3. ORDER    — newest by `created_at`, explicitly sorted. The two comment
#                 endpoints are CONCATENATED, and concatenation order is not
#                 chronological: `last` over the merged list returns the final
#                 INLINE comment whenever any exists, whatever time it was
#                 written.
#
# Dropping (2) disarms the lost-review detector in both directions at once: an
# unrelated human comment makes a lost review look posted, and a human "looks
# fine" outranks the reviewer's blocking findings. Dropping (3) produces the
# same suppression on timing alone.
#
# Usage:
#   collect-review-comment.sh --marker STR --since ISO --repo OWNER/NAME --pr N
#   collect-review-comment.sh --marker STR --since ISO --from-files C1 C2
#
# The first form reads both comment homes (issue comments AND pull-request
# review comments) via `gh api --paginate --slurp`; the second reads two
# page-shaped JSON files, which is what the harness feeds it. Prints the
# newest matching body, or nothing. Exits non-zero only when GitHub could not
# be asked — the caller must treat that as "could not look", never as "looked
# and found nothing".
set -euo pipefail

MARKER='' SINCE='' REPO='' PR='' C1='' C2=''
while [ $# -gt 0 ]; do
    case "$1" in
        --marker) MARKER="$2"; shift ;;
        --since)  SINCE="$2";  shift ;;
        --repo)   REPO="$2";   shift ;;
        --pr)     PR="$2";     shift ;;
        --from-files) C1="$2"; C2="$3"; shift 2 ;;
        *) echo "collect-review-comment.sh: unknown option $1" >&2; exit 2 ;;
    esac
    shift
done
if [ -z "$MARKER" ] || [ -z "$SINCE" ]; then
    echo "collect-review-comment.sh: --marker and --since are required" >&2; exit 2
fi

if [ -z "$C1" ]; then
    if [ -z "$REPO" ] || [ -z "$PR" ]; then
        echo "collect-review-comment.sh: --repo and --pr are required without --from-files" >&2; exit 2
    fi
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    C1="$WORK/c1.json"
    C2="$WORK/c2.json"
    # BOTH homes. A pull-request comment lives at one of two endpoints —
    # conversation comments and inline review comments — and a collector that
    # reads only one loses whichever half the reviewer happened to use.
    gh api "repos/$REPO/issues/$PR/comments" --paginate --slurp > "$C1"
    gh api "repos/$REPO/pulls/$PR/comments"  --paginate --slurp > "$C2"
fi

# `--paginate --slurp` yields an ARRAY OF PAGES; flatten before filtering.
jq -r --arg since "$SINCE" --arg marker "$MARKER" -s '
  [ .[] | (if (.[0] | type) == "array" then add else . end) ] | add
  | [ .[]
      | select(.created_at >= $since)
      | select(.body | contains($marker)) ]
  | sort_by(.created_at) | last | .body // ""
' "$C1" "$C2"
