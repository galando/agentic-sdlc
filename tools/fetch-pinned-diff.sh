#!/usr/bin/env bash
# tools/fetch-pinned-diff.sh — write the diff of a pull request AT A FIXED COMMIT.
#
# Usage:
#   tools/fetch-pinned-diff.sh --repo O/R --pr N --base <sha> --head <sha> --out <file>
#                              [--note-file <file>]
#
# WHY THIS EXISTS, and why the three review jobs all call it instead of asking for "this
# pull request's diff".
#
# The obvious command (`gh pr diff`) resolves the pull request's head AT THE MOMENT IT
# RUNS. The review pipeline has three jobs that read the diff at three different times —
# reviewer A, reviewer B, and the referee that compares their two reviews — so the obvious
# command gives each of them a potentially DIFFERENT commit, and nothing ties any of them
# to what the others read.
#
# Two failures came out of that, and the second one is the expensive one:
#
#   1. The referee measured a FIX and scored it against the finding that produced it. A
#      reviewer reports a real bug, the author fixes it immediately, the referee runs and
#      cannot find the bug — so the reviewer who was right is recorded as wrong. It bites
#      precisely when an author is RESPONSIVE, and the referee's comment is the last word
#      on the page.
#   2. The two reviewers could review different code and still be compared as though they
#      had reviewed the same code. "Both reviewers found this" and "only one reviewer
#      found this" both become meaningless if the two were not reading the same commit —
#      and nothing in the output would look wrong.
#
# The base and head shas come from the event payload, which is FIXED WHEN THE RUN IS
# TRIGGERED. Every job in the run passes the same two values, so every job reads the same
# bytes. That is the whole point: not "a fresher diff", but THE SAME diff.
#
# DEGRADES, NEVER DIES. A failed fetch leaves an empty output file and warns. The callers
# treat an empty diff as "verify against the checked-out tree instead" — which is itself
# pinned to the same commit — because a review pipeline that cancels itself over a
# transient API error is worse than one that reviews with less context and says so.
#
# --note-file is for the referee alone. It records whether the pull request has moved on
# since the reviewed commit, so the comparison can say that its verdicts describe an
# older commit. A reviewer does not need it: it reviews the pinned commit and says so.
set -euo pipefail

REPO="" PR="" BASE="" HEAD="" OUT="" NOTE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)      REPO="${2:-}"; shift 2 ;;
    --pr)        PR="${2:-}";   shift 2 ;;
    --base)      BASE="${2:-}"; shift 2 ;;
    --head)      HEAD="${2:-}"; shift 2 ;;
    --out)       OUT="${2:-}";  shift 2 ;;
    --note-file) NOTE="${2:-}"; shift 2 ;;
    *) echo "fetch-pinned-diff.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# Usage errors exit 2 and are LOUD. A missing --head silently defaulting to "whatever is
# current" would reintroduce the exact bug this script exists to remove, and it would do
# it invisibly: the output file would still be a perfectly valid diff.
for pair in "repo:$REPO" "pr:$PR" "base:$BASE" "head:$HEAD" "out:$OUT"; do
  if [ -z "${pair#*:}" ]; then
    echo "fetch-pinned-diff.sh: --${pair%%:*} is required" >&2
    echo "usage: fetch-pinned-diff.sh --repo O/R --pr N --base <sha> --head <sha> --out <file> [--note-file <file>]" >&2
    exit 2
  fi
done

mkdir -p "$(dirname "$OUT")"

# The compare endpoint with the diff media type, NOT `gh pr diff`. `base...head` is the
# three-dot range: the pull request's own changes, not everything the base branch has
# gained since the branch point.
# stderr is NOT suppressed. A hidden error turns "could not fetch the pinned diff" into
# a dead end — the operator needs to see whether it was a 404, a permission problem or a
# rate limit, and this is the only place that knows.
if ! gh api "repos/$REPO/compare/${BASE}...${HEAD}" \
       -H "Accept: application/vnd.github.v3.diff" > "$OUT"; then
  echo "::warning::Could not fetch the pinned diff for $REPO#$PR at ${HEAD} — the reviewer will verify against the checked-out tree instead."
  : > "$OUT"
fi

echo "Pinned diff: $(wc -c < "$OUT") bytes at ${HEAD}"

# The sha, next to the diff, for the reviewer to copy into its comment.
#
# WHY A FILE AND NOT JUST THE PROMPT. "All three jobs read the same commit" is enforced
# for the FETCH — one script, one range, shas fixed at trigger. That a reviewer then
# actually read the file is a prompt instruction, and a prompt is a request. Writing the
# sha here lets each reviewer stamp what it read, and lets the referee CHECK that the two
# reviews it is about to compare describe the same commit. A claim you can verify beats a
# claim you have to trust.
printf '%s\n' "$(printf '%.7s' "$HEAD")" > "$(dirname "$OUT")/reviewed-commit.txt"

[ -n "$NOTE" ] || exit 0

# Has the pull request moved on since the reviewed commit?
#
# An UNREADABLE live head is not a moved head. Guessing "moved" from a failed lookup puts
# a caveat on a comparison that needs none, and a caveat nobody needs is a caveat everyone
# learns to skip.
LIVE="$(gh api "repos/$REPO/pulls/$PR" --jq .head.sha 2>/dev/null || echo "")"
if [ -n "$LIVE" ] && [ "$LIVE" != "$HEAD" ]; then
  echo "::warning::PR head moved from ${HEAD} to ${LIVE} after the reviews - the comparison describes the reviewed commit."
  {
    echo "> [!NOTE]"
    echo "> **This compares the two reviews against \`$(printf '%.7s' "$HEAD")\`, the commit they"
    echo "> were written for.** The pull request has since moved to \`$(printf '%.7s' "$LIVE")\`, so a"
    echo "> finding below may no longer be present — usually because the author fixed it"
    echo "> *after* the review and *because of* it. Verdicts here are about the reviewed"
    echo "> commit."
    echo
  } > "$NOTE"
fi
