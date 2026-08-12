#!/usr/bin/env bash
# tools/status.sh — where am I in the adoption, and what is the ONE next step?
#
# Read-only. Answers the question every guard message individually dodges: the
# tooling refuses loudly when a step is run out of order, but nothing showed the
# order. A real adopter, three guards deep, said "too many scripts, it's
# difficult to follow" — and they were right. This prints the whole map with
# your position on it, every time, in seconds.
#
# The adoption is FOUR steps, one script each, in this order:
#   1. tools/init.sh                 — the interview (answers written into the tree)
#   2. tools/adopt-layout.sh         — retire examples/, point the harness at
#                                      backend/ and frontend/  (+ your product code)
#   3. tools/create-ledger-branch.sh — the agents' run-diary branch, once
#   4. tools/measure-floors.sh       — measure YOUR code, set the quality bar there
# Everything else under tools/ is internal plumbing; you never call it.
#
# Checks are local-only except the ledger-branch lookup (one ls-remote); when
# offline that check says "could not check" rather than guessing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AGENTS_ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ROOT="$AGENTS_ROOT"
# shellcheck source=lib/config.sh
. "$ROOT/tools/lib/config.sh"

next=""          # the first incomplete step's command
ok()   { printf '  [done] %s\n' "$1"; }
todo() { printf '  [NEXT] %s\n' "$1"; [ -n "$next" ] || next="$2"; }
info() { printf '  [....] %s\n' "$1"; }

echo "=== Adoption status — four steps, in order ==="
echo "    (this is the read-only map; tools/adopt.sh walks it WITH you, offer by offer)"
echo

# --- 1. The interview --------------------------------------------------------
# The token is BUILT at runtime, never written literally in this file: a literal
# token here would (a) be substituted by init.sh during adoption, silently
# inverting this very check on every adopted tree, and (b) drag this file into
# ADOPTING.md's placeholder map. CI's hygiene gate caught exactly that.
PROVIDER_TOKEN="$(printf '{{%s}}' PROVIDER)"
if grep -qF "$PROVIDER_TOKEN" "$ROOT/.agents/config.yml" 2>/dev/null; then
  todo "1. Answer the interview (writes your answers into the tree)" "tools/init.sh"
else
  provider="$(cfg_get provider '?' 2>/dev/null || echo '?')"
  ok "1. Interview answered (provider: $provider)"
fi

# --- 2. Layout + product -----------------------------------------------------
if [ -d "$ROOT/examples" ]; then
  todo "2. Retire the bundled example and re-point the harness at your product's layout" "tools/adopt-layout.sh"
elif [ ! -d "$ROOT/backend" ] && [ ! -d "$ROOT/frontend" ]; then
  todo "2. Layout adopted — now add your product at backend/ and/or frontend/ (the gates skip cleanly until it exists)" "add your product code"
else
  present=""
  [ -d "$ROOT/backend" ] && present="backend/"
  [ -d "$ROOT/frontend" ] && present="${present:+$present }frontend/"
  ok "2. Example retired; product present at: $present"
fi

# --- 3. The ledger branch ----------------------------------------------------
LEDGER_BRANCH="$(cfg_get ledger.branch agent-ledger 2>/dev/null || echo agent-ledger)"
if ! git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
  info "3. Ledger branch: no 'origin' remote yet — push the repository first, then: tools/create-ledger-branch.sh"
elif git -C "$ROOT" ls-remote --exit-code origin "refs/heads/$LEDGER_BRANCH" >/dev/null 2>&1; then
  ok "3. Ledger branch '$LEDGER_BRANCH' exists on origin (the agents' run diary)"
elif git -C "$ROOT" ls-remote origin >/dev/null 2>&1; then
  todo "3. Create the agents' run-diary branch (one idempotent command)" "tools/create-ledger-branch.sh"
else
  info "3. Ledger branch: could not reach origin to check — when online: tools/create-ledger-branch.sh (idempotent)"
fi

# --- 4. The floors -----------------------------------------------------------
if [ ! -f "$ROOT/floors.yml" ]; then
  info "4. floors.yml missing — was this cloned from the template?"
elif grep -qE '^[^#]*value:[[:space:]]*unset' "$ROOT/floors.yml"; then
  n_unset="$(grep -cE '^[^#]*value:[[:space:]]*unset' "$ROOT/floors.yml")"
  todo "4. Calibrate the quality floors against YOUR code ($n_unset of 9 still unset; slow on purpose — it builds and mutation-tests everything)" "tools/measure-floors.sh"
else
  ok "4. All floors calibrated against this repository's own code"
fi

# --- The front page ----------------------------------------------------------
# Same positive identification write-product-readme.sh uses: the template's own
# H1 survives every adoption step except the README rewrite itself, so its
# presence means visitors still read a description of the template, not of this
# product. Advisory only — never the [NEXT] step, never blocks anything.
if grep -qE '^# Agentic SDLC$' "$ROOT/README.md" 2>/dev/null; then
  echo
  echo "  NOTE: README.md is still the TEMPLATE's readme — visitors read about the"
  echo "  template, not your product. One command writes yours (badges, product"
  echo "  stub, how-this-repo-runs-itself): tools/write-product-readme.sh"
fi

# --- The tree itself ---------------------------------------------------------
if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
  echo
  echo "  NOTE: the working tree has uncommitted changes. Both adopt-layout.sh and"
  echo "  measure-floors.sh leave their edits uncommitted ON PURPOSE — each must land"
  echo "  as its own reviewable commit. measure-floors.sh refuses to start until the"
  echo "  tree is clean, so: review, commit, push, then continue."
fi

echo
if [ -n "$next" ]; then
  echo "Next command:  $next"
else
  cat <<'EOF'
All four tool steps are done. What remains lives in GitHub's UI, in order —
tools/adopt.sh checks each one and offers to do the settable ones for you:
  - add the AGENT_CLI_TOKEN secret. Without it EVERY agent job fails at the
    credential check: the steward runs and leaves nothing behind, reviews post
    no comment — the loop looks broken when it is only unauthenticated.
    (what belongs in it: tools/run-agent.sh --check-credentials steward --role judge)
  - optional secrets with named consequences: the challenge key (without it
    reviews are one opinion, the referee is skipped, and every agent PR wakes
    the steward — docs/runbooks/multi-model-review.md) and STEWARD_HANDOFF_PAT
    (without it agent-filed issues cannot wake the steward).
  - Settings → Actions → General → Workflow permissions: Read and write, and
    tick 'Allow GitHub Actions to create and approve pull requests' — fresh
    repositories ship with it OFF, and the steward then does all its work and
    fails at the moment it opens the pull request.
  - install your agent CLI's GitHub App for this repository
  - see the FAST checks green once in the Actions tab
  - enable branch protection (docs/runbooks/branch-protection.md has the exact strings)
  - then open issue #1 and watch the loop run.
EOF
fi
