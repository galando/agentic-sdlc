#!/usr/bin/env bash
# tools/review-handoff-decide.sh — does this pull request need a steward handoff?
#
#   tools/review-handoff-decide.sh --judge <file> --challenge <file> \
#                                  --verdict <file> \
#                                  --collector-outcome <success|failure|cancelled|...>
#
# Prints shell-assignable KEY=VALUE lines on stdout and exits 0. It DECIDES; it never
# files, comments or talks to anything. That separation is the point — the caller owns the
# side effects, so the decision can be exercised on its own with crafted inputs.
#
#   DECISION=findings         something must be fixed before merge -> file the handoff and
#                             wake the steward
#   DECISION=followup         reviews landed and NOTHING has to be fixed before merge ->
#                             file a follow-up issue that wakes nobody. The findings are
#                             kept; the pull request is left alone.
#   DECISION=none             nothing landed, and the collector ran fine -> the review
#                             job's lost-review check owns this case
#   DECISION=collector-failed nothing landed BECAUSE THE COLLECTOR DIED -> say so on the
#                             pull request; findings may be sitting there with no listener
#
# THE REFEREE DECIDES, NOT A GREP (2026-08-09).
#
# This script used to read the review bodies and ask whether each one contained the
# literal words "No issues found". That phrase is a code-review PLUGIN's clean marker.
# Nothing in this repository emits it: `.agents/prompts/review-judge.md` and
# `review-challenge.md` both ask for prose, and prose never contains that phrase. So every
# review that landed counted as "findings" and every agent pull request got a handoff —
# the steward woke on pull requests both reviewers had approved, pushed commits onto them
# and reset CI. Upstream measured 46 handoff issues, one per agent pull request, before
# the same defect was found there.
#
# The referee already reads both reviews AND the diff and rules on them. It now also
# writes one word to `.review-artifacts/referee-verdict.txt`, and that word decides:
#
#   blocking      at least one finding must be fixed before merge -> wake the steward
#   non-blocking  every finding is a suggestion or a follow-up    -> file, wake nobody
#   undecided     the referee genuinely could not tell            -> wake the steward
#
# THE DIRECTION-OF-ERROR RULE IS UNCHANGED, and it is the reason this reads the way it
# does. The test below is an equality against the ONE word that means "leave it alone", so
# an unrecognised format — a missing file, an empty file, or a word nobody recognises —
# counts as findings and gets escalated rather than silently dropped. Wrong in the
# direction of one spurious escalation, never in the direction of another stranded finding.
#
# A missing input must never read as "nothing to do": one unnecessary steward run costs one
# person one look, a dismissed real finding costs a defect in production. Do not
# "helpfully" default an unreadable verdict to non-blocking, and never rewrite the test
# below as a list of the words that WAKE the steward — a new spelling or a typo would then
# fall through to silence.
#
# TWO SMALLER RULES, both load-bearing:
#
#   * `wc -c` greater than 1, not `[ -s ]`. The collector writes an empty result as a lone
#     newline, so a 1-byte file means "this reviewer posted nothing" — and counting that as
#     a review that landed would let a pull request nobody reviewed reach the verdict
#     branch at all.
#   * VERDICT is reduced to `[a-z0-9-]` and truncated before it is printed. Every value
#     this script emits is meant to be sourced by the caller, and this one is the only
#     value that starts life in a file an agent wrote.
set -euo pipefail

JUDGE="" CHALLENGE="" OUTCOME="" VERDICT_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --judge)             JUDGE="${2:-}";        shift 2 ;;
    --challenge)         CHALLENGE="${2:-}";    shift 2 ;;
    --verdict)           VERDICT_FILE="${2:-}"; shift 2 ;;
    --collector-outcome) OUTCOME="${2:-}";      shift 2 ;;
    *) echo "review-handoff-decide.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

for pair in "judge:$JUDGE" "challenge:$CHALLENGE" "verdict:$VERDICT_FILE" \
            "collector-outcome:$OUTCOME"; do
  if [ -z "${pair#*:}" ]; then
    echo "review-handoff-decide.sh: --${pair%%:*} is required" >&2
    exit 2
  fi
done

LANDED=0
PRESENT=""

for pair in "judge:$JUDGE" "challenge:$CHALLENGE"; do
  role="${pair%%:*}"
  f="${pair#*:}"
  [ -f "$f" ] || continue
  [ "$(wc -c < "$f")" -gt 1 ] || continue

  case "$role" in
    judge)     PRESENT="${PRESENT}the judge role, " ;;
    challenge) PRESENT="${PRESENT}the challenge role, " ;;
  esac
  LANDED=$((LANDED + 1))
done

PRESENT="${PRESENT%, }"

# The referee's word, normalised. Lowercased, stripped of the markdown an agent tends to
# wrap a lone word in, first line only, then reduced to a safe charset and truncated.
VERDICT=""
if [ -f "$VERDICT_FILE" ]; then
  VERDICT="$(tr '[:upper:]' '[:lower:]' < "$VERDICT_FILE" \
             | tr -d '`*_"'"'"' \t\r' | head -n1 | tr -cd 'a-z0-9-' | cut -c1-32)"
fi

case "$VERDICT" in
  blocking|non-blocking|undecided) VERDICT_RECOGNISED=true  ;;
  *)                               VERDICT_RECOGNISED=false ;;
esac

if [ "$LANDED" = "0" ]; then
  # WHY `none` AND `collector-failed` ARE DIFFERENT, when they look identical on disk.
  #
  #   none              the collector looked and there was nothing to find. Already
  #                     reported by the lost-review check; a second report would duplicate.
  #   collector-failed  the reviews ARE on the pull request, with findings, and the
  #                     lost-review check correctly filed nothing BECAUSE IT SAW THEM. The
  #                     handoff then reads "no reviews" and exits quietly. Nobody is woken.
  #
  # The second is the stranded-finding failure the whole handoff exists to prevent,
  # arriving through a different door — and it is invisible in every other signal.
  if [ "$OUTCOME" != "success" ]; then
    DECISION="collector-failed"
  else
    DECISION="none"
  fi
elif [ "$VERDICT" = "non-blocking" ]; then
  DECISION="followup"
else
  # blocking, undecided, missing, empty, unrecognised. All of them wake the steward.
  DECISION="findings"
fi

# Quoted so the caller can `. <(...)` this directly. Every value here comes from a fixed
# vocabulary, from counting, or — for VERDICT — from a charset-reduced single word.
printf 'DECISION=%s\n'            "$DECISION"
printf 'REVIEWS_PRESENT="%s"\n'   "$PRESENT"
printf 'REVIEWS_LANDED=%s\n'      "$LANDED"
printf 'VERDICT="%s"\n'           "$VERDICT"
printf 'VERDICT_RECOGNISED=%s\n'  "$VERDICT_RECOGNISED"
