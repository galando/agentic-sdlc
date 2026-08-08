#!/usr/bin/env bash
# tools/review-handoff-decide.sh — does this pull request need a steward handoff?
#
#   tools/review-handoff-decide.sh --judge <file> --challenge <file> \
#                                  --collector-outcome <success|failure|cancelled|...>
#
# Prints shell-assignable KEY=VALUE lines on stdout and exits 0. It DECIDES; it never
# files, comments or talks to anything. That separation is the point — the caller owns the
# side effects, so the decision can be exercised on its own with crafted inputs.
#
#   DECISION=findings         at least one review carries findings -> file the handoff
#   DECISION=clean            every review that landed says "no issues" -> file nothing
#   DECISION=none             nothing landed, and the collector ran fine -> the review
#                             job's lost-review check owns this case
#   DECISION=collector-failed nothing landed BECAUSE THE COLLECTOR DIED -> say so on the
#                             pull request; findings may be sitting there with no listener
#
# WHY `none` AND `collector-failed` ARE DIFFERENT, when they look identical on disk.
#
# Both leave the two review files empty or absent. But:
#
#   none              the collector looked and there was nothing to find. Already
#                     reported by the lost-review check; a second report would duplicate.
#   collector-failed  the reviews ARE on the pull request, with findings, and the
#                     lost-review check correctly filed nothing BECAUSE IT SAW THEM. The
#                     handoff then reads "no reviews" and exits quietly. Nobody is woken.
#
# The second is the stranded-finding failure the whole handoff exists to prevent, arriving
# through a different door — and it is invisible in every other signal.
#
# TWO SMALLER RULES, both load-bearing:
#
#   * Keyed on the CLEAN phrase, never on a finding marker. An unrecognised format then
#     counts as FINDINGS and gets escalated rather than silently dropped. Wrong
#     in the direction of one spurious issue, never in the direction of a lost one.
#   * `wc -c` greater than 1, not `[ -s ]`. The collector writes an empty result as a lone
#     newline, so a 1-byte file means "this reviewer posted nothing" — and counting that as
#     a clean review would suppress the handoff for a pull request nobody reviewed.
set -euo pipefail

JUDGE="" CHALLENGE="" OUTCOME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --judge)             JUDGE="${2:-}";     shift 2 ;;
    --challenge)         CHALLENGE="${2:-}"; shift 2 ;;
    --collector-outcome) OUTCOME="${2:-}";   shift 2 ;;
    *) echo "review-handoff-decide.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

for pair in "judge:$JUDGE" "challenge:$CHALLENGE" "collector-outcome:$OUTCOME"; do
  if [ -z "${pair#*:}" ]; then
    echo "review-handoff-decide.sh: --${pair%%:*} is required" >&2
    exit 2
  fi
done

CLEAN_COUNT=0
WITH_FINDINGS=0
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

  if grep -qF 'No issues found' "$f"; then
    CLEAN_COUNT=$((CLEAN_COUNT + 1))
  else
    WITH_FINDINGS=$((WITH_FINDINGS + 1))
  fi
done

PRESENT="${PRESENT%, }"

if [ "$CLEAN_COUNT" = "0" ] && [ "$WITH_FINDINGS" = "0" ]; then
  if [ "$OUTCOME" != "success" ]; then
    DECISION="collector-failed"
  else
    DECISION="none"
  fi
elif [ "$WITH_FINDINGS" = "0" ]; then
  DECISION="clean"
else
  DECISION="findings"
fi

# Quoted so the caller can `. <(...)` this directly. Every value here comes from a fixed
# vocabulary or from counting, never from a review body.
printf 'DECISION=%s\n'              "$DECISION"
printf 'REVIEWS_PRESENT="%s"\n'     "$PRESENT"
printf 'CLEAN_COUNT=%s\n'           "$CLEAN_COUNT"
printf 'REVIEWS_WITH_FINDINGS=%s\n' "$WITH_FINDINGS"
