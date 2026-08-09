#!/usr/bin/env bash
# tools/adopt.sh — the guided adoption. ONE command, run as many times as you like.
#
# Why this exists: the adoption is four local tools plus a handful of GitHub-side
# actions, in a documented order — and five live adoptions showed the same failure
# mode each time: not a broken step, but a human unsure WHICH step, or unaware a
# manual one (a secret, a stale commit, branch protection) was theirs. status.sh
# answered "where am I"; this answers "do it for me, one confirmed step at a time".
#
# Contract:
#   - RESUMABLE and IDEMPOTENT: it detects what is already done and moves on, so
#     you re-run it after any pause (adding your product code, waiting on CI).
#   - NOTHING HAPPENS WITHOUT AN EXPLICIT YES. Every action is an offer with the
#     default No; declining prints the manual command and moves on. Read-only
#     probes (git, and `gh` when installed and authenticated) are the exception.
#   - Degrades cleanly: no `gh`, no network, no admin rights — each check says
#     "could not verify" with the manual instruction, never a false "done".
#
# Non-interactive acceptance (for tests and scripting) mirrors init.sh's pattern:
#   ADOPT_COMMIT=y  ADOPT_MEASURE=y  ADOPT_PROTECT=y  ADOPT_ISSUE=y
#   ADOPT_CONTINUE_WITHOUT_PRODUCT=y  (walk past step 2 with no backend//frontend/)
# plus init.sh's own DELETE_EXAMPLE / WRITE_README / CREATE_LEDGER_BRANCH.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AGENTS_ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ROOT="$AGENTS_ROOT"
# shellcheck source=lib/config.sh
. "$ROOT/tools/lib/config.sh"

say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n=== %s ===\n' "$*"; }
note() { printf '  %s\n' "$*"; }

# ask VAR "question" -> yes/no, default No. Non-interactive: reads $VAR (y/N).
offer() {
  local var="$1" prompt="$2" reply
  if [ -t 0 ]; then
    read -r -p "$prompt [y/N]: " reply
  else
    reply="$(eval "printf '%s' \"\${$var:-N}\"")"
  fi
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# The one place that knows whether gh can answer repository questions.
GH_OK=false
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  GH_OK=true
fi

ORIGIN_URL="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
SLUG="$(printf '%s\n' "$ORIGIN_URL" \
  | sed -E -e 's#\.git/?$##' \
  | sed -nE 's#^(git@[^:]+:|https?://[^/]+/|ssh://git@[^/]+/)([^/]+/[^/]+)$#\2#p')"
DEFAULT_BRANCH="$(git -C "$ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
[ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH=main

say "=== Guided adoption — re-run this command any time; it resumes where you are ==="
$GH_OK || say "    (gh CLI not available/authenticated: GitHub-side checks will say so and give manual steps)"

# ---------------------------------------------------------------------------
# 1. The interview.
# ---------------------------------------------------------------------------
PROVIDER_TOKEN="$(printf '{{%s}}' PROVIDER)"
hdr "1/8  The interview (tools/init.sh)"
if grep -qF "$PROVIDER_TOKEN" "$ROOT/.agents/config.yml" 2>/dev/null; then
  note "Not answered yet. The interview asks your product name, provider and models,"
  note "resolves every placeholder, and offers the example retirement, your product"
  note "README and the ledger branch as it goes. Offline, seconds, safe to re-run."
  if [ -t 0 ]; then
    bash "$ROOT/tools/init.sh" || { say "init.sh did not finish — fix the message above and re-run tools/adopt.sh."; exit 1; }
  else
    note "Non-interactive shell: run tools/init.sh yourself (it needs your answers)."
    exit 0
  fi
else
  note "[done] provider: $(cfg_get provider '?' 2>/dev/null || echo '?')"
fi

# ---------------------------------------------------------------------------
# 2. Layout + your product.
# ---------------------------------------------------------------------------
hdr "2/8  Your product at the root layout (backend/ and/or frontend/)"
if [ -d "$ROOT/examples" ]; then
  note "The bundled example is still present; the gates run against it, not you."
  if offer DELETE_EXAMPLE "Retire it and re-point the harness at backend//frontend/ now (tools/adopt-layout.sh)?"; then
    bash "$ROOT/tools/adopt-layout.sh"
  else
    note "Skipped. Manual: tools/adopt-layout.sh (idempotent)."
  fi
fi
if [ ! -d "$ROOT/backend" ] && [ ! -d "$ROOT/frontend" ] && [ ! -d "$ROOT/examples" ]; then
  note "[YOURS] Add your product code at backend/ and/or frontend/ now, then re-run"
  note "tools/adopt.sh. Committing straight to $DEFAULT_BRANCH is CORRECT at this stage:"
  note "the floors are measured FROM this code (step 5), and branch protection (step 7)"
  note "deliberately comes last — the guarantees are prospective, they govern changes"
  note "made after the bar is set, and the gates skip cleanly until code exists."
  # This is a genuine stop, not a note in passing. Every remaining step needs the
  # code to exist to mean anything: the floors are measured FROM it, branch
  # protection requires the FAST tier green on a real pull request, and the first
  # agent-run change has nothing to change. Walking on would offer all four
  # anyway and contradict the "then re-run tools/adopt.sh" two lines above.
  if ! offer ADOPT_CONTINUE_WITHOUT_PRODUCT "Nothing after this step can be done without that code. Walk the rest anyway?"; then
    note "Stopping here. Add your code, then run tools/adopt.sh again — it resumes."
    note "Read-only map of everything still ahead, any time: tools/status.sh"
    exit 0
  fi
  note "Continuing without product code, at your request — steps 6 and 7 will not"
  note "produce anything meaningful until it is there."
elif [ -d "$ROOT/backend" ] || [ -d "$ROOT/frontend" ]; then
  present=""
  [ -d "$ROOT/backend" ] && present="backend/"
  [ -d "$ROOT/frontend" ] && present="${present:+$present }frontend/"
  note "[done] product present at: $present"
fi

# ---------------------------------------------------------------------------
# 3. The ledger branch.
# ---------------------------------------------------------------------------
hdr "3/8  The agents' run-diary branch"
LEDGER_BRANCH="$(cfg_get ledger.branch agent-ledger 2>/dev/null || echo agent-ledger)"
if ! git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
  note "[wait] No 'origin' remote yet — push the repository first."
elif git -C "$ROOT" ls-remote --exit-code origin "refs/heads/$LEDGER_BRANCH" >/dev/null 2>&1; then
  note "[done] '$LEDGER_BRANCH' exists on origin."
elif git -C "$ROOT" ls-remote origin >/dev/null 2>&1; then
  if offer CREATE_LEDGER_BRANCH "Create and push it now (tools/create-ledger-branch.sh — one empty orphan commit)?"; then
    bash "$ROOT/tools/create-ledger-branch.sh"
  else
    note "Skipped. Manual: tools/create-ledger-branch.sh (idempotent)."
  fi
else
  note "[????] Could not reach origin to check — when online: tools/create-ledger-branch.sh"
fi

# ---------------------------------------------------------------------------
# 4. Commit what the tools changed. The tools leave edits uncommitted ON
#    PURPOSE (each should land as a reviewable commit); this closes that loop
#    instead of leaving it as unstated homework — the calibrator refuses to
#    start on a dirty tree, and a real adopter hit exactly that refusal.
# ---------------------------------------------------------------------------
hdr "4/8  Commit and push the adoption changes"
if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
  note "The working tree has uncommitted changes (the interview/layout edits above,"
  note "or your product code). Review them first if you have not: git diff"
  if offer ADOPT_COMMIT "Commit ALL current changes as 'adopt the agentic-sdlc process' and push?"; then
    if git -C "$ROOT" add -A \
        && git -C "$ROOT" commit -m "adopt the agentic-sdlc process" \
        && git -C "$ROOT" push -u origin HEAD; then
      note "[done] committed and pushed."
    else
      note "[FAIL] commit or push failed — see git's message above."
    fi
  else
    note "Skipped. Manual: git add -A && git commit && git push"
  fi
else
  note "[done] working tree clean."
fi

# ---------------------------------------------------------------------------
# 5. The credential.
# ---------------------------------------------------------------------------
hdr "5/8  The agent credential (AGENT_CLI_TOKEN repository secret)"
if $GH_OK && [ -n "$SLUG" ]; then
  if gh secret list --repo "$SLUG" 2>/dev/null | grep -q '^AGENT_CLI_TOKEN'; then
    note "[done] AGENT_CLI_TOKEN is set on $SLUG."
    note "(Presence only — CI proves validity. If a review job says 'not logged in',"
    note " re-mint the token; the command below prints how.)"
  else
    note "[YOURS] Not set. Mint it, then either:"
    note "  gh secret set AGENT_CLI_TOKEN --repo $SLUG        (paste when prompted)"
    note "  or GitHub → Settings → Secrets and variables → Actions."
  fi
else
  note "[????] Cannot check repository secrets without an authenticated gh."
fi
note "What belongs in it (subscription token vs API key), for YOUR provider:"
# --role is not optional here: the steward is event-driven, so it is deliberately
# absent from ledger.agents and nothing about it can be looked up. It runs as
# `judge` in steward.yml, so that is the role whose provider we ask about.
"$ROOT/tools/run-agent.sh" --check-credentials steward --role judge 2>&1 | sed 's/^/    /' || true

# ---------------------------------------------------------------------------
# 6. Calibrate the floors — through a pull request, the first real one.
# ---------------------------------------------------------------------------
hdr "6/8  Calibrate the quality floors against YOUR code"
if [ ! -f "$ROOT/floors.yml" ]; then
  note "[????] floors.yml missing — was this cloned from the template?"
elif grep -qE '^[^#]*value:[[:space:]]*unset' "$ROOT/floors.yml"; then
  n_unset="$(grep -cE '^[^#]*value:[[:space:]]*unset' "$ROOT/floors.yml")"
  note "$n_unset of 9 floors still carry the unset sentinel. Calibration builds and"
  note "mutation-tests everything — slow on purpose, online, needs a clean tree."
  if offer ADOPT_MEASURE "Run tools/measure-floors.sh now?"; then
    "$ROOT/tools/measure-floors.sh" || note "[FAIL] see the calibrator's message above."
    note "Now put the result up as your FIRST pull request (the review pipeline and"
    note "the whole gauntlet run on it — that PR is the proof the process works):"
    note "  git checkout -b calibrate-floors && git add -A && git commit && git push -u origin calibrate-floors"
    note "  then open the pull request on GitHub and merge it once green."
  else
    note "Skipped. Manual: tools/measure-floors.sh, then commit on a branch and open a PR."
  fi
else
  note "[done] all floors calibrated."
fi

# ---------------------------------------------------------------------------
# 7. Branch protection — LAST of the repository settings, once FAST is green.
# ---------------------------------------------------------------------------
hdr "7/8  Branch protection (makes the gauntlet binding)"
FAST_CONTEXTS='fast-unit-tests fast-frontend-checks fast-harness-guards fast-repo-hygiene fast-secret-scan fast-actionlint fast-spec-artifacts'
if $GH_OK && [ -n "$SLUG" ]; then
  if gh api "repos/$SLUG/branches/$DEFAULT_BRANCH/protection" >/dev/null 2>&1; then
    note "[done] $DEFAULT_BRANCH is protected."
  else
    note "[YOURS] Not protected yet — until it is, every gate is advisory."
    note "Precondition: the FAST tier has reported green on at least one pull request"
    note "(otherwise a required check that has never run wedges every PR)."
    if offer ADOPT_PROTECT "Apply it now via gh (require a PR + the 7 FAST checks, no bypass)?"; then
      if printf '{"required_status_checks":{"strict":false,"contexts":["fast-unit-tests","fast-frontend-checks","fast-harness-guards","fast-repo-hygiene","fast-secret-scan","fast-actionlint","fast-spec-artifacts"]},"enforce_admins":true,"required_pull_request_reviews":{"required_approving_review_count":0},"restrictions":null}' \
          | gh api -X PUT "repos/$SLUG/branches/$DEFAULT_BRANCH/protection" --input - >/dev/null; then
        note "[done] protection applied. Promote the full-* contexts within the first week"
        note "       (docs/runbooks/branch-protection.md, 'Full tier')."
      else
        note "[FAIL] gh could not apply it (admin rights?). Manual path: docs/runbooks/branch-protection.md"
      fi
    else
      note "Skipped. Manual: Settings → Branches → protect '$DEFAULT_BRANCH' with contexts:"
      note "  $FAST_CONTEXTS"
      note "Exact walk-through: docs/runbooks/branch-protection.md"
    fi
  fi
else
  note "[????] Cannot check protection without an authenticated gh. Manual:"
  note "  Settings → Branches → protect '$DEFAULT_BRANCH'; require: $FAST_CONTEXTS"
  note "  Exact walk-through: docs/runbooks/branch-protection.md"
fi

# ---------------------------------------------------------------------------
# 8. Open issue #1 and watch the loop.
# ---------------------------------------------------------------------------
hdr "8/8  The first agent-run change"
MENTION="$(cfg_get mention.default '@agent' 2>/dev/null || echo '@agent')"
note "Open an issue describing a small real change and mention the agent ($MENTION —"
note "or whatever the AGENT_MENTION repository variable holds). The steward triages"
note "it, opens a branch and a pull request; reviews and the gauntlet run; YOU merge."
if $GH_OK && [ -n "$SLUG" ]; then
  if offer ADOPT_ISSUE "Open a starter issue now (you will be prompted for the title/body)?"; then
    gh issue create --repo "$SLUG" || note "[FAIL] gh could not open the issue."
    note "Remember to include the mention phrase ($MENTION) in the issue body."
  fi
fi

say ""
say "Done for now. Re-run tools/adopt.sh after any step you finished elsewhere;"
say "read-only map any time: tools/status.sh"
