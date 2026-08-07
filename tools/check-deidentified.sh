#!/usr/bin/env bash
# De-identification sweep — does this repository still name something it should not?
#
# Sweeps three places, because a name survives in all three and a content-only
# grep catches one of them:
#
#   1. file CONTENT of every tracked file
#   2. file NAMES  (a path is where a product name survives longest)
#   3. COMMIT MESSAGES (a template is cloned with its history; anyone can read it)
#
# ---------------------------------------------------------------------------
# THIS SCRIPT NAMES NOTHING ITSELF. That is deliberate and it is the whole
# design.
#
# The obvious version carries the terms inline. Do that in a template and the
# shipped tree contains a curated enumeration of exactly what the template
# claims to have removed — worse than a stray mention, because it is organised,
# and because this is the first file a reader opens to audit whether the
# extraction was clean. The only escape is to exclude this file from its own
# sweep, which makes the leak invisible to the one check meant to catch it.
#
# A check that must exempt itself to pass is not a check. So the terms live in
# a file you pass in, and this script is subject to its own sweep with NO
# carve-out anywhere.
# ---------------------------------------------------------------------------
#
# Usage:
#   tools/check-deidentified.sh [--terms <file>] [--repo <dir>]
#
#   --terms <file>  one pattern per line (POSIX ERE), blank lines and lines
#                   starting with # ignored. Defaults to .deident-terms in the
#                   repository root.
#
# Exit codes:
#   0  no hits, or no term file present (a clean, ANNOUNCED skip)
#   1  at least one hit
#   2  usage error — including a term file that is named but missing, or empty
#
# A missing or empty term list is an ERROR, never a pass. "Zero hits because we
# searched for nothing" is a green run with a wrong answer, which is the exact
# failure this repository is built to prevent.

set -euo pipefail

TERMS=""
REPO="."

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --terms) TERMS="${2:-}"; shift 2 || usage ;;
    --repo)  REPO="${2:-}";  shift 2 || usage ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

cd "$REPO" || { echo "cannot enter repository '$REPO'" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository: $REPO" >&2; exit 2; }

DEFAULTED=0
if [ -z "$TERMS" ]; then
  TERMS=".deident-terms"
  DEFAULTED=1
fi

if [ ! -f "$TERMS" ]; then
  if [ "$DEFAULTED" -eq 1 ]; then
    # An adopter who has not written a list yet must not get a red CI check.
    # But they must not get a SILENT green either: a check that quietly did
    # nothing looks identical to a check that found nothing.
    #
    # Prose in the log is not enough for that, and the difference matters here
    # more than anywhere else in this repository: NOBODY READS A GREEN JOB'S
    # LOG. On a forge, the announcement has to be an annotation, because the
    # annotation is the only part of a passing job anyone ever sees. Same shape
    # as the unarmed watchdog in ci-health-watch.yml and the unconfigured gate
    # 18 in nightly.yml, for the same reason.
    #
    # Gated on $GITHUB_ACTIONS so a terminal gets prose and CI gets both. A bare
    # `::notice::` line in a local run is noise, and noise here trains the
    # reader to skim the one message that must never be skimmed.
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      echo "::notice title=De-identification sweep not armed::No term list, so this check SKIPPED rather than passed. It looked for nothing and found nothing — that is not the same as clean. Supply one with --terms, or commit a .deident-terms file to your fork."
    fi
    echo "check-deidentified: no .deident-terms file — skipping the sweep."
    echo "  This is a SKIP, not a pass. Nothing was searched for."
    echo "  Write one (one pattern per line) to sweep this fork for names that"
    echo "  should not have survived. Keep it out of the tree: add it to"
    echo "  .gitignore, or a committed list becomes the leak it was meant to find."
    exit 0
  fi
  echo "check-deidentified: term file not found: $TERMS" >&2
  exit 2
fi

# Strip comments and blanks. A BLANK LINE used as a grep pattern matches every
# line of every file, which would report the whole tree as a leak and teach the
# reader to ignore this check.
PATTERNS="$(mktemp)"
trap 'rm -f "$PATTERNS"' EXIT
sed -e 's/[[:space:]]*$//' "$TERMS" | grep -vE '^[[:space:]]*(#|$)' > "$PATTERNS" || true

if [ ! -s "$PATTERNS" ]; then
  echo "check-deidentified: term file '$TERMS' is empty (no usable patterns)." >&2
  echo "  Refusing to report success: zero hits from zero patterns is not a result." >&2
  exit 2
fi

# Validate the whole pattern set ONCE, before any sweep runs.
#
# grep says "no match" with exit 1 and "that is not a valid regular expression"
# with exit 2. Every sweep below ends in `|| true` — it has to, because exit 1 is
# the ordinary clean case — and that makes the two indistinguishable at the call
# site: one unescaped paren in a product name reports `clean — 0 hits` having
# matched nothing at all. Worse, the content sweep could not tell them apart even
# if it tried, because xargs collapses grep's 2 into its own generic failure code.
#
# So the check moves up here, where it can still be answered: run the patterns
# against empty input. Exit 1 means "valid, and of course nothing matched"; exit
# 2 means the set is unusable and the only honest thing left is to refuse.
PATTERNS_RC=0
printf '' | grep -q -E -f "$PATTERNS" -- 2>/dev/null || PATTERNS_RC=$?
if [ "$PATTERNS_RC" -ge 2 ]; then
  echo "check-deidentified: term file '$TERMS' contains an invalid pattern." >&2
  echo "  Refusing to report success: a sweep that cannot compile its patterns" >&2
  echo "  finds nothing, and 'found nothing' is exactly what a clean tree looks like." >&2
  echo "  Offending term(s):" >&2
  # Each probe must not be the loop body's exit status: under `set -e` a term
  # that compiles fine answers 1, and a bare failing command at the end of a loop
  # body takes the whole script down before it can name the term that actually
  # broke — reporting the fault without the one detail needed to fix it.
  while IFS= read -r term; do
    term_rc=0
    printf '' | grep -q -E -e "$term" -- 2>/dev/null || term_rc=$?
    if [ "$term_rc" -ge 2 ]; then
      printf '    %s\n' "$term" >&2
    fi
  done < "$PATTERNS"
  exit 2
fi

HITS=0

# --- 1. file content, tracked files only ------------------------------------
# Tracked only, via `git ls-files`. Walking the working tree would flag the
# gitignored term list itself on every run, and the natural fix for that is an
# exclusion — which is how self-exclusion gets introduced. The index is the
# right scope anyway: untracked files are not what gets published.
# -H forces the filename even when an xargs batch holds a single file — without
# it a lone-file batch reports a leak with no path, which is a hit you cannot fix.
CONTENT="$(git ls-files -z \
  | xargs -0 grep -H -n -I -i -E -f "$PATTERNS" -- 2>/dev/null || true)"
if [ -n "$CONTENT" ]; then
  echo "=== file content ==="
  printf '%s\n' "$CONTENT"
  HITS=$(( HITS + $(printf '%s\n' "$CONTENT" | grep -c '') ))
fi

# --- 2. file names ----------------------------------------------------------
NAMES="$(git ls-files | grep -i -E -f "$PATTERNS" || true)"
if [ -n "$NAMES" ]; then
  echo "=== file names ==="
  printf '%s\n' "$NAMES" | sed 's/^/  file name: /'
  HITS=$(( HITS + $(printf '%s\n' "$NAMES" | grep -c '') ))
fi

# --- 3. commit messages -----------------------------------------------------
# %B is the raw body, so a term in a trailer or a long description is caught
# too, not just the subject line.
MSGS="$(git log --format='%h %B' | grep -n -i -E -f "$PATTERNS" || true)"
if [ -n "$MSGS" ]; then
  echo "=== commit messages ==="
  printf '%s\n' "$MSGS" | sed 's/^/  commit message: /'
  HITS=$(( HITS + $(printf '%s\n' "$MSGS" | grep -c '') ))
fi

if [ "$HITS" -eq 0 ]; then
  echo "check-deidentified: clean — 0 hits across content, file names and commit messages."
  exit 0
fi

echo
echo "check-deidentified: $HITS hit(s). This tree still names something it should not."
echo
echo "Rewrite, do not delete. Where a hit sits inside an incident comment, the"
echo "lesson is the value being transferred: strip the specifics and keep the"
echo "reason as neutral prose. A rule without its reason gets deleted by the"
echo "next person."
echo
echo "A commit-message hit needs a history rewrite, not an edit — the tree being"
echo "clean does not make the history clean, and a template is cloned with it."
exit 1
