#!/usr/bin/env bash
# tools/check-upstream-drift.sh — what has the upstream system learned since we last looked?
#
#   tools/check-upstream-drift.sh <upstream-git-dir-or-url> [--since <sha>] [--surface <file>]
#
# ============================================================================
# THIS IS A MAINTAINER TOOL FOR THIS TEMPLATE. ADOPTERS DO NOT NEED IT.
#
# An adopter copies this template once and never pulls from it again — there is no merge
# relationship, which is what `CHANGELOG.md` explains at the top. `tools/init.sh` offers to
# delete this script for exactly that reason.
#
# The template's own situation is the opposite one. It was EXTRACTED from a running system
# that is still running, still meeting incidents, and still writing down what it learned.
# Those lessons are the whole product here. Carrying them across has been done by reading
# `git log` by hand, which works right up until the day somebody skims.
# ============================================================================
#
# What it does: lists every upstream commit since a recorded sync point that touches the
# surface this template actually carries — the agent workflows, the runbooks, the prompts,
# the standing decisions. Product code is deliberately NOT in that surface: an upstream fix
# to a scraper or a payment path teaches this template nothing.
#
# What it does NOT do: judge. It cannot tell you whether a commit's lesson is portable —
# several have not been (a vendor-specific session hook, a stale CVE allowlist entry). It
# tells you what to READ. Deciding is still the job, and recording the decision — "checked,
# not carried, because X" — is part of it.
#
# The sync point lives in .agents/upstream-sync.json, next to the config the agents read,
# and is updated by hand when a sync lands. A sync point nobody updates is a tool that
# reports the same forty commits forever until somebody stops running it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SYNC_FILE="$ROOT/.agents/upstream-sync.json"

UPSTREAM="" SINCE="" SURFACE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since)   SINCE="${2:-}";   shift 2 ;;
    --surface) SURFACE="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) echo "check-upstream-drift.sh: unknown option '$1'" >&2; exit 2 ;;
    *)  UPSTREAM="$1"; shift ;;
  esac
done

if [ -z "$UPSTREAM" ]; then
  echo "check-upstream-drift.sh: usage: check-upstream-drift.sh <upstream-git-dir-or-url> [--since <sha>]" >&2
  echo "  the upstream is a local clone of the system this template was extracted from" >&2
  exit 2
fi

command -v git >/dev/null 2>&1 || { echo "check-upstream-drift.sh: git is required" >&2; exit 3; }

# A URL is not usable directly: this tool reads history, so it needs a clone. Say so with
# the command rather than cloning several hundred megabytes on the user's behalf.
# Accepts a normal clone OR a bare/mirror clone — a mirror is the obvious way to keep a
# local copy of a repository you only ever read. `git rev-parse` answers for both and does
# not care which; hand-checking for .git/ and HEAD got the bare case wrong (HEAD is a FILE
# there, not a directory) and rejected it with a misleading "clone it first".
if ! git -C "$UPSTREAM" rev-parse --git-dir >/dev/null 2>&1; then
  echo "check-upstream-drift.sh: '$UPSTREAM' is not a git checkout." >&2
  echo "  Clone the upstream first, then point this at it:" >&2
  echo "    git clone <upstream-url> /tmp/upstream && tools/check-upstream-drift.sh /tmp/upstream" >&2
  exit 3
fi

# ---------------------------------------------------------------------------
# The sync point.
# ---------------------------------------------------------------------------
if [ -z "$SINCE" ]; then
  if [ -f "$SYNC_FILE" ] && command -v jq >/dev/null 2>&1; then
    SINCE="$(jq -r '.last_synced_upstream_sha // ""' "$SYNC_FILE")"
  elif [ -f "$SYNC_FILE" ]; then
    SINCE="$(grep -o '"last_synced_upstream_sha"[^,}]*' "$SYNC_FILE" \
             | sed -E 's/.*"last_synced_upstream_sha"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
  fi
fi

if [ -z "$SINCE" ] || [ "$SINCE" = "null" ]; then
  echo "check-upstream-drift.sh: no sync point." >&2
  echo "  Record one in $SYNC_FILE, or pass --since <sha>." >&2
  echo "  Without it this cannot tell 'new' from 'already carried', and reporting" >&2
  echo "  everything is the same as reporting nothing." >&2
  exit 4
fi

if ! git -C "$UPSTREAM" cat-file -e "${SINCE}^{commit}" 2>/dev/null; then
  echo "check-upstream-drift.sh: sync point '$SINCE' is not a commit in '$UPSTREAM'." >&2
  echo "  Fetch the upstream (git -C '$UPSTREAM' fetch --all), or check the recorded sha." >&2
  echo "  NOT treated as 'nothing to report' — an unresolvable base must fail loudly," >&2
  echo "  never produce an empty, reassuring list." >&2
  exit 4
fi

# ---------------------------------------------------------------------------
# The surface. Path prefixes, one per line, '#' comments allowed.
# ---------------------------------------------------------------------------
DEFAULT_SURFACE='.github/workflows/
.github/
docs/runbooks/
AGENTS.md
CLAUDE.md
.agents/
.claude/'

if [ -n "$SURFACE" ]; then
  [ -f "$SURFACE" ] || { echo "check-upstream-drift.sh: surface file '$SURFACE' not found" >&2; exit 2; }
  PATHS="$(grep -vE '^\s*(#|$)' "$SURFACE")"
else
  PATHS="$DEFAULT_SURFACE"
fi

# A portable read loop, not `mapfile` — that is a bash-4+ builtin and this must run
# under whatever /usr/bin/env bash resolves to, including the 3.2 that ships on macOS.
# Same reasoning, same convention, as tools/spec-pipeline/validate.sh. This is a
# MAINTAINER tool, so a laptop is exactly where it runs.
PATHSPEC=()
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] && PATHSPEC+=("$line")
done <<EOF
$PATHS
EOF

# ---------------------------------------------------------------------------
# WHICH REF TO READ. This defaulted to `HEAD` and that was wrong in the one way that
# matters: `git fetch` updates remote-tracking refs and leaves the local branch where it
# was, so a clone made yesterday and fetched today still has a stale `HEAD`. The tool then
# reported ONE commit to read when four were waiting — an empty-ish, reassuring list
# produced by the very staleness it exists to detect.
#
# So: prefer the remote-tracking ref, and when falling back to a local one, say so and
# check whether it is behind. Never report a small number quietly.
# ---------------------------------------------------------------------------
resolve_ref() {
  local candidate
  if [ -n "${UPSTREAM_REF:-}" ]; then printf '%s' "$UPSTREAM_REF"; return; fi
  for candidate in origin/HEAD origin/main origin/master; do
    if git -C "$UPSTREAM" rev-parse --verify -q "$candidate" >/dev/null 2>&1; then
      printf '%s' "$candidate"; return
    fi
  done
  printf 'HEAD'
}

REF="$(resolve_ref)"

case "$REF" in
  origin/*) : ;;
  *)
    echo "::warning::Reading local '$REF' — no remote-tracking ref found. A local branch does" >&2
    echo "  not move when you fetch, so this may UNDER-REPORT. Run: git -C '$UPSTREAM' fetch --all" >&2
    ;;
esac

# Even a remote-tracking ref is only as fresh as the last fetch. Say when it was.
LAST_FETCH="$(git -C "$UPSTREAM" log -1 --format=%cd --date=relative "$REF" 2>/dev/null || echo unknown)"

COUNT="$(git -C "$UPSTREAM" rev-list --count "${SINCE}..${REF}" -- "${PATHSPEC[@]}")"

echo "Upstream drift since ${SINCE} (reading ${REF}, newest commit ${LAST_FETCH})"
echo "Surface: ${PATHSPEC[*]}"
echo "Fetch first if that looks stale: git -C '${UPSTREAM}' fetch --all"
echo

if [ "$COUNT" = "0" ]; then
  echo "Nothing to carry: no upstream commit since the sync point touches the extracted surface."
  echo "(Product-only changes are excluded on purpose — they teach this template nothing.)"
  exit 0
fi

echo "$COUNT commit(s) to READ. This tool does not judge portability; you do."
echo
git -C "$UPSTREAM" log --format='%h %ad %s' --date=short --reverse \
  "${SINCE}..${REF}" -- "${PATHSPEC[@]}"
echo
echo "For each one, decide and RECORD the decision — carried, or checked-and-not-carried"
echo "with the reason. A commit nobody wrote a decision about gets re-read every sync."
echo
echo "When the sync lands, update last_synced_upstream_sha in:"
echo "  $SYNC_FILE"
