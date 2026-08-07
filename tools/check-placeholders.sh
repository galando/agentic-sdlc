#!/usr/bin/env bash
# tools/check-placeholders.sh — the post-init check (design.md section 4.2).
#
# Fails if any double-brace UPPER_SNAKE_CASE placeholder remains in a tracked file outside a
# short, fixed allowlist. tools/init.sh runs this as its own LAST step and refuses to
# print "done" if it fails. `fast-repo-hygiene` runs it on every pull request too.
#
# The allowlist is NOT configurable — a configurable allowlist is how a genuine
# unresolved placeholder gets excused. It is a short, explicit list of files (plus three
# narrowly-scoped directory prefixes below), each with a one-line reason, and it lives
# here, in code, not in a file someone could edit to make a red check green.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# FILE allowlist — exact tracked-file paths. Each entry is P5 "syntax documentation"
# (design.md section 4.1): the token appears as prose ABOUT the placeholder system,
# never as a live value waiting on this adopter's answer.
#
# ADOPTING.md            — IS the placeholder map; every token is named there on purpose.
# README.md              — documents the placeholder syntax itself in prose.
# CONTRIBUTING.md        — same: explains the convention to a contributor.
# docs/runbooks/agent-routines.md
#                         — the HEALTH_SIGNAL token appears ONLY as documented example syntax
#                           (design.md section 4.3); the real slots live in
#                           .agents/health-signals.yml, which is not on this list.
# docs/QUALITY-GATES.md  — the four floor tokens (FLOOR_LINE, FLOOR_BRANCH,
#                           FLOOR_MUTATION, CEILING_BUNDLE_KIB) are a documented STYLE
#                           meaning "whatever floors.yml currently holds" (P4's `unset`
#                           sentinel, or a calibrated number after tools/measure-floors.sh
#                           runs) — nothing ever mechanically substitutes them, by design
#                           (see "Floors ship UNCALIBRATED" in this same file). PRODUCT_NAME
#                           here IS still rewritten by init.sh's tree-wide substitution pass
#                           even though this check does not re-verify it in this one file,
#                           same trade-off as the three entries above.
# tools/ledger.sh         — the ledger-commit-name/email tokens are a DELIBERATE runtime
#                           fallback value (not an unresolved build-time token): if the
#                           adopter never sets the env var, the ledger commit author is the
#                           literal placeholder string on purpose, so a malformed commit
#                           identity is obviously wrong rather than a plausible-looking lie.
#                           See the comment at its point of use.
# tools/spec-pipeline/new-spec.sh
#                         — the slug/date tokens are its OWN sed search pattern (literal
#                           source code), substituted at spec-creation time, not by init.sh.
# .github/workflows/nightly.yml
#                         — the upstream-provider token (gate 18) is, by its own comment at
#                           the point of use, "deliberately NOT interpolated into any run:
#                           body": gate 18 ships as a documented CONTRACT, not an
#                           implementation, so there is no live command for a value to ever
#                           land in. Arming the gate means writing tools/live-api-contract.sh
#                           by hand; the token in the comment just names what belongs there.
# ---------------------------------------------------------------------------
ALLOWLIST="ADOPTING.md README.md CONTRIBUTING.md docs/runbooks/agent-routines.md docs/QUALITY-GATES.md tools/ledger.sh tools/spec-pipeline/new-spec.sh .github/workflows/nightly.yml"

# ---------------------------------------------------------------------------
# PREFIX exclusions — whole directories that never carry a live P1/P2 placeholder.
# Scoped narrowly and each justified, per the same "not configurable except in code,
# and never silently widened" rule as the file allowlist above.
#
# .temper/specs/       — the build record (design.md's own worked example of a spec
#                         directory, and tasks.md Task 29's resolved decision to sanitize
#                         rather than retire it). init.sh itself never touches this
#                         directory (see its own header comment); a token here is prose
#                         ABOUT the placeholder system or a deliberately-preserved
#                         de-identification artifact (a SOURCE_REPO mention), not a live
#                         placeholder waiting on this adopter.
# tools/spec-pipeline/templates/
#                       — reusable micro-templates for `new-spec.sh <slug>`. Their slug/date
#                         tokens are resolved per-spec, at spec-creation time, by
#                         new-spec.sh itself — never by init.sh, and never once, because a
#                         NEW spec needs the same two tokens again next time.
# tests/                — test fixtures that deliberately construct or reference
#                         placeholder-shaped strings (a provider token, a ledger-commit-name
#                         token, etc.) as literal DATA to exercise the
#                         substitution/detection tooling itself (init.sh, ledger.sh, this
#                         script). A *.bats file is test code, never shipped adopter-facing
#                         config or docs, so a real unresolved P1/P2 placeholder cannot
#                         occur here by construction — only a hand-built fixture that
#                         intentionally echoes the syntax it is testing.
# ---------------------------------------------------------------------------
PREFIX_EXCLUSIONS=".temper/specs/ tools/spec-pipeline/templates/ tests/"

is_allowlisted() {
  local f="$1" a
  for a in $ALLOWLIST; do
    [ "$f" = "$a" ] && return 0
  done
  for a in $PREFIX_EXCLUSIONS; do
    case "$f" in
      "$a"*) return 0 ;;
    esac
  done
  return 1
}

cd "$ROOT"

hits=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  is_allowlisted "$f" && continue
  matches="$(grep -noE '\{\{[A-Z][A-Z0-9_]*\}\}' "$f" 2>/dev/null || true)"
  [ -z "$matches" ] && continue
  while IFS=: read -r line token; do
    echo "$f:$line: unresolved placeholder $token"
    hits=$((hits + 1))
  done <<<"$matches"
done < <(git ls-files)

# ---------------------------------------------------------------------------
# Has the interview run yet?
#
# A freshly instantiated template is SUPPOSED to be full of unresolved placeholders —
# that is the entire premise of tools/init.sh. Failing the build for them means the very
# first pull request on a brand-new repository is red for doing nothing wrong, and
# "green on day one, or adoption dies" is not a slogan: a red check on an untouched
# template reads as "this thing is broken", and it gets deleted the same afternoon.
#
# So before init has run, this reports LOUDLY and passes; afterwards it fails, because
# then an unresolved token really is an unfinished job. The signal is .agents/config.yml,
# the one file init.sh certainly rewrites — if its tokens are still there, nothing has
# been configured. There is no flag and no environment variable for this: a switch is a
# thing someone sets in CI to keep a genuinely red check quiet.
# ---------------------------------------------------------------------------
initialised=1
if [ -f .agents/config.yml ] && grep -qE '\{\{[A-Z][A-Z0-9_]*\}\}' .agents/config.yml; then
  initialised=0
fi

if [ "$hits" -gt 0 ] && [ "$initialised" -eq 0 ]; then
  echo
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::warning title=Template not initialised::$hits unresolved placeholder(s). This repository has not run tools/init.sh yet, so this is EXPECTED and not a failure. This check starts failing as soon as .agents/config.yml is filled in."
  fi
  echo "check-placeholders: $hits unresolved placeholder(s) — and .agents/config.yml is"
  echo "  still unresolved too, so tools/init.sh has not been run. That is the expected"
  echo "  state of a freshly instantiated template, so this is NOT a failure."
  echo
  echo "  Run tools/init.sh to configure the repository. From then on this check is"
  echo "  strict, and an unresolved placeholder fails the build."
  exit 0
fi

if [ "$hits" -gt 0 ]; then
  echo
  echo "check-placeholders: $hits unresolved placeholder(s). Run tools/init.sh, or fill" >&2
  echo "them in by hand if you are not using the interview." >&2
  exit 1
fi

echo "check-placeholders: clean — 0 unresolved placeholders outside the allowlist."
exit 0
