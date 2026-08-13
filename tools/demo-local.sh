#!/usr/bin/env bash
# tools/demo-local.sh — the three-minute, zero-credential proof.
#
# Why this exists: the cheapest credible evidence this system is real is
# already local and free — ~630 harness tests in seconds, the adoption map,
# and a dry-run that prints the exact argv an agent would run while invoking
# nothing. Before this script, a curious visitor had to discover those four
# commands across three documents; now the devcontainer (and anyone with bats
# installed) gets them in one run. Everything here is offline and read-only:
# no credential is read, nothing is invoked, nothing is written.
#
# Degrades visibly, never silently: a missing tool or an unresolved provider
# is announced with what it means and what to do next — never skipped quietly.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT" || exit 1

say() { printf '%s\n' "$*"; }
hdr() { printf '\n=== %s ===\n' "$*"; }

FAILED=0

say "=== The three-minute tour: everything below runs offline, with no credentials ==="

# --- 1. The harness suite ----------------------------------------------------
hdr "1/4  The harness suite (bats tests/ tests/harness-guards/)"
if command -v bats >/dev/null 2>&1; then
  # LC_ALL pinned: gen-pin-tests.sh's printf %q output differs between the
  # POSIX and UTF-8 locales, and the regeneration-diff gate compares bytes.
  if LC_ALL=C.UTF-8 bats tests/ tests/harness-guards/; then
    say "  All green. Roughly half of these tests guard the agents' own plumbing —"
    say "  the machine that builds the software, not the software."
  else
    FAILED=1
    say "  RED — that is a real finding, not a demo glitch. See the failure above."
  fi
else
  FAILED=1
  say "  bats is not installed, so the suite did NOT run (this is a skip, not a pass)."
  say "  Install: apt-get install bats   (or: brew install bats-core)"
fi

# --- 2. Workflow lint --------------------------------------------------------
hdr "2/4  Workflow lint (actionlint)"
if command -v actionlint >/dev/null 2>&1; then
  if actionlint .github/workflows/*.yml; then
    say "  Zero findings across every workflow."
  else
    FAILED=1
    say "  RED — a workflow lint finding. See above."
  fi
else
  say "  actionlint is not installed — SKIPPED, not passed."
  say "  (Binary releases: github.com/rhysd/actionlint. The CI gate runs it regardless.)"
fi

# --- 3. Where an adoption stands --------------------------------------------
hdr "3/4  The adoption map (tools/status.sh)"
bash tools/status.sh || FAILED=1

# --- 4. The agents, without invoking anything --------------------------------
hdr "4/4  The agent fleet, dry"
bash tools/run-agent.sh --list-agents || FAILED=1
# Same template-vs-adopted discriminator status.sh uses; built at runtime so
# init.sh's substitution pass can never rewrite this check into a tautology.
PROVIDER_TOKEN="$(printf '{{%s}}' PROVIDER)"
if grep -qF "$PROVIDER_TOKEN" "$ROOT/.agents/config.yml" 2>/dev/null; then
  say ""
  say "  No provider chosen yet (this is the uninitialised template), so there is no"
  say "  argv to preview — that is the designed state, not a failure. After the"
  say "  interview (tools/adopt.sh, or tools/init.sh --answers profiles/<name>.answers),"
  say "  \`tools/run-agent.sh health --dry-run\` prints the exact command each agent"
  say "  would run, still invoking nothing."
else
  say ""
  say "  Dry-run of the first agent — the exact argv, nothing invoked:"
  bash tools/run-agent.sh health --dry-run || FAILED=1
fi

echo
if [ "$FAILED" -eq 0 ]; then
  say "=== Done. Everything you just saw ran offline with no credentials. ==="
  say "Next: tools/adopt.sh walks the real adoption, one confirmed step at a time."
else
  say "=== Done, with at least one section red or unable to run — see above. ==="
  say "A red section is a finding; a missing tool is a skip. Neither is a pass."
  exit 1
fi
