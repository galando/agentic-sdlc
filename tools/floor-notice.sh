#!/usr/bin/env bash
# tools/floor-notice.sh <scope> — the "floor not yet calibrated" workflow step.
#
# Runs as an `if: always()` step in every ratchet-bearing CI job, BEFORE the tool step,
# and always exits 0 (design.md section 7.3 — Decision D12). Prints a
# `::notice::` per uncalibrated floor in <scope> plus a table appended to
# $GITHUB_STEP_SUMMARY when that variable is set (harmless no-op locally).
#
# The exact sentence below is required VERBATIM by the intent scenario "Uncalibrated
# floors pass loudly, then arm against the adopter's own baseline" and is pinned by
# tests/floors-sentinel.bats — a reword must not slip through unnoticed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/config.sh
. "$ROOT/tools/lib/config.sh"

SCOPE="${1:-}"
[ -n "$SCOPE" ] || { echo "floor-notice.sh: usage: floor-notice.sh <scope-prefix>" >&2; exit 0; }

FLOORS_FILE="$(_floors_file)"
[ -f "$FLOORS_FILE" ] || exit 0

SENTENCE="floor not yet calibrated — run tools/measure-floors.sh against your product"

# floors.yml keys are literal strings (containing dots) at 2-space indent under
# `floors:` — a plain grep, not jq (floors.yml is YAML, not JSON) or yq (kept optional
# everywhere else in this repo's tooling; this script has no other reason to need it).
keys="$(grep -E '^  [A-Za-z0-9_.-]+:' "$FLOORS_FILE" | sed -E 's/^  //; s/:.*$//' | grep -F "$SCOPE" || true)"
[ -z "$keys" ] && exit 0

any=0
{
  echo "| Floor | Status |"
  echo "|---|---|"
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    val="$(floor_get "$key" 2>/dev/null || echo unset)"
    if [ "$val" = "unset" ]; then
      echo "::notice title=Floor not calibrated::${key}: ${SENTENCE}"
      echo "| $key | uncalibrated |"
      any=1
    fi
  done <<<"$keys"
} | { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && tee -a "$GITHUB_STEP_SUMMARY" >/dev/null || cat; }

[ "$any" -eq 1 ] || true
exit 0
