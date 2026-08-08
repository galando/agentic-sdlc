#!/usr/bin/env bash
# tools/adopt-layout.sh — retire the bundled example and re-point the harness at the
# adopter layout (backend/ and frontend/ at the repo root), in one idempotent step.
#
# Why this exists: the workflows, the mutation-scope tool and .gitignore ship
# targeting the example's paths (examples/backend, examples/frontend) so the 22
# gates have something real to run against on day one. The adopter's own product
# lives at the ROOT layout — the one tools/measure-floors.sh calibrates against —
# and the first real adoption measured what the move costs by hand: ~50 path
# references across four workflows, the mutation-scope tool and its self-test,
# .gitignore's build-output patterns, plus a relative-depth fix (a step whose
# working-directory rises one level needs one fewer ../). This script is that
# whole sweep, mechanically. The harness guards need no rewriting at all: they
# detect the layout themselves (tests/harness-guards/review-fix-regressions.bats,
# day-one-green.bats).
#
# Called by tools/init.sh when you accept the delete-the-example offer, and
# runnable directly at any later time — deleting examples/ by hand and running
# this afterwards converges on the identical state. Running it twice is a no-op.
# Offline, plain text substitution only, like init.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

die() { echo "adopt-layout.sh: $*" >&2; exit 1; }

changed=0
note() { echo "  $*"; changed=1; }

echo "=== tools/adopt-layout.sh — adopt the root layout (backend/, frontend/) ==="

# --- 1. Retire the bundled example ------------------------------------------
if [ -d "$ROOT/examples" ]; then
  # Refuse while examples/ carries UNCOMMITTED work. The example is the working
  # reference implementation, which makes it the tempting place to start
  # building — and this step is an rm -rf. Committed work survives in git
  # history; uncommitted work would be simply gone. Product code belongs at
  # backend// frontend/ (the layout this very script adopts); anything a user
  # was editing in here must be moved or committed before the retirement runs.
  # Degrades silently outside a git repo (the test fixtures), where there is no
  # notion of uncommitted to protect.
  dirty="$(git -C "$ROOT" status --porcelain -- examples 2>/dev/null || true)"
  if [ -n "$dirty" ]; then
    die "examples/ has UNCOMMITTED changes and this step DELETES the directory.
If that is your own work, move it to backend// frontend/ (or commit it) first:
$dirty"
  fi
  rm -rf "$ROOT/examples"
  note "deleted examples/"
else
  echo "  examples/ already absent."
fi

# --- 2. Re-point the workflows and the mutation-scope tool ------------------
# Plain prefix substitution: every harness reference to the example paths becomes
# the same reference at the root layout. sed -i only rewrites; the loop below
# reports per file so a no-op run says so instead of staying silent.
repoint() {
  local f="$1"
  [ -f "$f" ] || return 0
  if grep -qE 'examples/(backend|frontend)' "$f"; then
    sed -i.adoptbak -e 's|examples/backend|backend|g' -e 's|examples/frontend|frontend|g' "$f"
    rm -f "$f.adoptbak"
    note "re-pointed ${f#"$ROOT"/}"
  fi
}

for f in "$ROOT"/.github/workflows/*.yml \
         "$ROOT/tools/mutation-scope.sh" \
         "$ROOT/tools/test-mutation-scope.sh" \
         "$ROOT/tools/check-migrations.sh" \
         "$ROOT/floors.yml" \
         "$ROOT/.gitignore"; do
  repoint "$f"
done

# --- 3. Relative depth: ./examples/backend was TWO levels under root, ./backend
# is ONE — every ../../tools reference inside a step whose working-directory
# moved up must lose one ../, or it resolves outside the repo.
if [ -f "$ROOT/.github/workflows/pr-mutation.yml" ] \
   && grep -qF '../../tools/floor-get.sh' "$ROOT/.github/workflows/pr-mutation.yml"; then
  sed -i.adoptbak 's|\.\./\.\./tools/floor-get\.sh|../tools/floor-get.sh|g' "$ROOT/.github/workflows/pr-mutation.yml"
  rm -f "$ROOT/.github/workflows/pr-mutation.yml.adoptbak"
  note "re-based ../../tools/floor-get.sh to ../tools/floor-get.sh in pr-mutation.yml"
fi

# --- 4. Sanity: nothing in the harness still points at the example ----------
# Two exclusions, both legitimate references rather than live targets: this
# script's own source names the example paths because they ARE its substitution
# patterns (the same self-mutation reasoning as init.sh excluding its own
# siblings), and render-floors.sh probes BOTH layouts by design — its
# examples/ mention is the documented fallback, not a target to re-point.
leftovers="$(grep -rlE 'examples/(backend|frontend)' "$ROOT/.github/workflows" "$ROOT/tools" "$ROOT/floors.yml" 2>/dev/null \
  | grep -vE '/tools/(adopt-layout|render-floors)\.sh$' || true)"
if [ -n "$leftovers" ]; then
  die "these files still reference the example paths after the sweep — the substitution list above is incomplete:
$leftovers"
fi

echo
if [ "$changed" -eq 1 ]; then
  cat <<EOF
Done. The harness now targets backend/ and frontend/ at the repo root:
  - wire your product in at those paths (the gates skip cleanly until it exists),
  - then calibrate: tools/measure-floors.sh
Review the diff and commit it as its own change.
EOF
else
  echo "Nothing to do — the root layout is already adopted."
fi
