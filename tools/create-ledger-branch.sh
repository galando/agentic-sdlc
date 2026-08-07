#!/usr/bin/env bash
# tools/create-ledger-branch.sh — create and push the empty agent-ledger branch.
#
# What this branch is, in plain words: the agents' DIARY. Every scheduled agent
# run appends one line of history ("date, verdict, what I found") to a file on a
# branch named agent-ledger. It is an "orphan" branch — it shares no history
# with main and is never merged; a separate notebook living in the same
# repository. It must exist once, empty, before any agent writes to it, and
# nothing else about it is ever manual: tools/ledger.sh does all reading and
# writing from then on. Full story: docs/runbooks/agent-ledgers.md.
#
# This script is the one-time creation, made safe to not think about:
#   - idempotent — if the branch already exists on the remote it says so and
#     succeeds; running it twice cannot hurt anything
#   - working-tree-safe — it uses git plumbing to push an empty root commit
#     directly, so it never switches your checked-out branch or touches your
#     working files
#   - the ONE network action in the adoption tooling: one push, announced.
#
# Called by tools/init.sh when you accept its offer at the end of the interview,
# and runnable directly at any time.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AGENTS_ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ROOT="$AGENTS_ROOT"
# shellcheck source=lib/config.sh
. "$ROOT/tools/lib/config.sh"

die() { echo "create-ledger-branch.sh: $*" >&2; exit 1; }

# The branch name is config-driven like everything else (ledger.branch); the
# shipped default is agent-ledger and pre-init trees carry it literally, so this
# works before AND after the interview.
BRANCH="$(cfg_get ledger.branch agent-ledger 2>/dev/null || echo agent-ledger)"

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || die "not inside a git repository — run this from your repository checkout."

git -C "$ROOT" remote get-url origin >/dev/null 2>&1 \
  || die "no 'origin' remote is configured. Push your repository to its hosting
service first (git remote add origin <url> && git push -u origin <default-branch>),
then re-run this script."

if git -C "$ROOT" ls-remote --exit-code origin "refs/heads/$BRANCH" >/dev/null 2>&1; then
  echo "The '$BRANCH' branch already exists on origin — nothing to do."
  echo "(Safe to run this any number of times; that is the point.)"
  exit 0
fi

# Plumbing, not `git checkout --orphan`: an empty tree, one root commit on it,
# pushed straight to the remote ref. Your working tree and current branch are
# never touched.
EMPTY_TREE="$(git -C "$ROOT" hash-object -t tree /dev/null)" \
  || die "could not create the empty tree object."
ROOT_COMMIT="$(git -C "$ROOT" commit-tree "$EMPTY_TREE" \
  -m "ledger root — agent run history lands here, one JSONL file per agent (docs/runbooks/agent-ledgers.md)")" \
  || die "could not create the root commit."

git -C "$ROOT" push origin "$ROOT_COMMIT:refs/heads/$BRANCH" \
  || die "the push failed — check your network and that you can push to origin, then re-run."

cat <<EOF

Created and pushed the empty '$BRANCH' branch.

What just happened, in plain words: the agents keep a run diary — one line per
run — on this separate branch. It shares no history with your default branch
and is never merged; think of it as a notebook in the same repository. From
here on tools/ledger.sh does all the reading and writing; you never touch this
branch by hand. Read it any time with:  tools/ledger.sh latest
EOF
