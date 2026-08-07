#!/usr/bin/env bash
# tools/init.sh — the adoption interview.
#
# Asks the adopter's decisions ONCE, rewrites every double-brace placeholder those decisions
# resolve, and prints exactly what is left for a human to do by hand. See
# .temper/specs/agent-sdlc-template/design.md section 4 for the placeholder taxonomy
# this implements (P1 interview, P2 derived, P3 deferred-manual, P4 sentinel, P5 syntax
# documentation).
#
# CONTRACT (SC7 / the intent scenarios "init.sh is idempotent" and "init.sh leaves no
# unresolved placeholder"):
#   - NO NETWORK CALLS. Everything here is local text substitution and local git plumbing.
#   - IDEMPOTENT. Running it twice with the same answers produces an empty diff the
#     second time — a placeholder already resolved has nothing left for a second pass
#     to touch.
#   - Completes in seconds. It does NOT measure anything (that is
#     tools/measure-floors.sh's job, deliberately the opposite contract — see Task 21b
#     and design.md section 9.5).
#
# Scope: this substitutes P1 placeholders across the SHIPPED template tree. It
# deliberately does not touch .temper/specs/** — that directory is the build record
# (design.md's own worked example of a spec directory, Task 29), and a PRODUCT_NAME token
# appearing there is prose ABOUT the placeholder system, not a live placeholder waiting
# on this adopter's answer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/config.sh
. "$ROOT/tools/lib/config.sh"

die() { echo "init.sh: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
usage: tools/init.sh [--answers FILE]

Runs the adoption interview and rewrites every placeholder it resolves.

  --answers FILE   a shell file setting PRODUCT_NAME=, PROVIDER=, MODEL_JUDGE=,
                    MODEL_EXECUTE=, MODEL_CHALLENGE=, CHALLENGE_BASE_URL=,
                    ALERT_CHANNEL=, RUNNER_LABEL=, LEDGER_COMMIT_NAME=,
                    LEDGER_COMMIT_EMAIL=, BUILD_PIPELINE=. Any variable it does not set
                    is asked for interactively. This is what makes a second run with
                    "the same answers" reproducible without re-typing them, and what
                    tests/init-idempotent.bats drives non-interactively.

No network calls. Completes in seconds. Safe to re-run.
EOF
}

ANSWERS_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --answers) ANSWERS_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown flag '$1'" ;;
  esac
done

if [ -n "$ANSWERS_FILE" ]; then
  [ -f "$ANSWERS_FILE" ] || die "--answers file not found: $ANSWERS_FILE"
  # shellcheck source=/dev/null
  . "$ANSWERS_FILE"
fi

# ---------------------------------------------------------------------------
# The interview. Each question is skipped if the answers file (or a pre-set env var —
# same mechanism tests/init-idempotent.bats uses to run this twice unattended) already
# has it. Never asked twice in one run; never asked at all when scripted.
# ---------------------------------------------------------------------------
ask() {
  local var="$1" prompt="$2" default="${3:-}"
  local current
  eval "current=\"\${$var:-}\""
  if [ -n "$current" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    die "$var is not set and stdin is not a terminal — pass --answers FILE or set \$$var. See usage."
  fi
  local reply
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " reply
    reply="${reply:-$default}"
  else
    read -r -p "$prompt: " reply
  fi
  eval "$var=\"\$reply\""
}

echo "=== tools/init.sh — the adoption interview ==="
echo "No network calls. Answers are written into the tree as plain text; nothing is sent anywhere."
echo

ask PRODUCT_NAME "What system do your agents watch? (product name)"
ask PROVIDER "Which agent CLI provider? (claude-code | codex | gemini-cli)" "claude-code"
case "$PROVIDER" in
  claude-code|codex|gemini-cli) : ;;
  *) die "PROVIDER must be one of: claude-code, codex, gemini-cli (compatible-endpoint is fixed to the challenge role and is not asked here)" ;;
esac

ask MODEL_JUDGE "Exact model id for the 'judge' role (reviews, referee, triage)"
ask MODEL_EXECUTE "Exact model id for the 'execute' role (mechanical edits, routines)"
ask MODEL_CHALLENGE "Exact model id for the 'challenge' role (MUST be a different model family)"
ask CHALLENGE_BASE_URL "Base URL of the compatible endpoint serving the challenge model (blank if none yet)" "none"
ask ALERT_CHANNEL "Alert channel: none | webhook | command" "none"
ask RUNNER_LABEL "GitHub Actions runner label for CI jobs" "ubuntu-latest"
ask LEDGER_COMMIT_NAME "Commit author name for ledger writes" "sdlc-agent"
ask LEDGER_COMMIT_EMAIL "Commit email for ledger writes" "agent@example.invalid"
ask BUILD_PIPELINE "Name of the spec pipeline your agents build through" "the built-in fallback (tools/spec-pipeline/)"

echo
echo "--- Adapter status for '$PROVIDER' ---"
STATUS="$(adapter_status "$PROVIDER")"
DOCS_URL="$(adapter_docs_url "$PROVIDER")"
if [ "$STATUS" = "verified" ]; then
  cat <<EOF
Provider '$PROVIDER' is VERIFIED. Minimal mode: the steward and PR review ship LIVE,
the five scheduled routines ship DISABLED (enable them one at a time after an
interactive dry-run — see README.md "turning on the routines").
EOF
else
  cat <<EOF
Provider '$PROVIDER' is an UNVERIFIED STUB — its flags have never been run.
The steward and PR review are disabled so your first pull request is green.
The 22 gates are live now and do not depend on any agent CLI.
To finish: tools/providers/$PROVIDER.sh  (docs: $DOCS_URL)  -> set ADAPTER_STATUS=verified
           then re-run tools/init.sh to enable the steward and review.
(Both workflows read this same ADAPTER_STATUS line at run time, so once you flip it
they take effect on their very next trigger — re-running init.sh is not what enables
them mechanically, it is the documented moment to go confirm you actually did it.)
EOF
fi

# ---------------------------------------------------------------------------
# Rewrite every P1 placeholder across the shipped tree — tracked files only, excluding
# the build record (.temper/specs/**, prose ABOUT the placeholder system, not a live
# placeholder) and anything git itself ignores.
# ---------------------------------------------------------------------------
declare -a TOKENS=(
  PRODUCT_NAME PROVIDER MODEL_JUDGE MODEL_EXECUTE MODEL_CHALLENGE CHALLENGE_BASE_URL
  ALERT_CHANNEL RUNNER_LABEL LEDGER_COMMIT_NAME LEDGER_COMMIT_EMAIL BUILD_PIPELINE
)

list_target_files() {
  # Excludes .temper/specs/** (the build record — see the header comment), this script's
  # own two siblings, and ADOPTING.md.
  #
  # tools/init.sh / tools/check-placeholders.sh necessarily mention placeholder token
  # NAMES in their own source (usage text, the DERIVATION FAILED messages, the grep
  # patterns themselves) and would otherwise self-mutate the moment a token they name
  # happened to match a chosen answer — found by running this script twice against a real
  # answers file, where the second run corrupted the first run's own DEFAULT_BRANCH
  # message into unrelated garbage.
  #
  # ADOPTING.md is MECHANICALLY GENERATED by tools/gen-adopting.sh and its whole point is
  # to keep showing every literal double-brace token name as the map's own left column — the
  # placeholder map documenting the PRODUCT_NAME token is not the place a real product
  # name should land, for the same reason a dictionary entry for "red" is not printed in
  # red ink. If this substitution loop touched it, the very first init.sh run would turn the
  # map into an unreadable one-off snapshot instead of a stable reference.
  # tests/** is excluded for the same reason tools/gen-adopting.sh excludes it: test
  # fixtures deliberately construct placeholder-shaped strings as literal test data
  # (init-idempotent's fixture trees, alert.bats' unconfigured-channel case). Substituting
  # inside them rewrites the expected values the assertions are built on, so the whole
  # suite is green before the interview and red forever after — found by adopting this
  # template into a real demo repository, where exactly that happened.
  ( cd "$ROOT" && git ls-files ) \
    | grep -v '^\.temper/specs/' \
    | grep -v '^tests/' \
    | grep -v '^tools/init\.sh$' \
    | grep -v '^tools/check-placeholders\.sh$' \
    | grep -v '^ADOPTING\.md$'
}

echo
echo "--- Rewriting placeholders ---"
total_files_changed=0
for f in $(list_target_files); do
  path="$ROOT/$f"
  [ -f "$path" ] || continue
  changed=0
  for tok in "${TOKENS[@]}"; do
    eval "val=\"\${$tok:-}\""
    [ -z "$val" ] && continue
    if grep -qF "{{$tok}}" "$path" 2>/dev/null; then
      # Escape sed metacharacters (&, /, \) in the replacement value.
      esc="$(printf '%s' "$val" | sed -e 's/[\/&\\]/\\&/g')"
      sed -i.init-tmp "s/{{$tok}}/$esc/g" "$path"
      rm -f "$path.init-tmp"
      changed=1
    fi
  done
  [ "$changed" -eq 1 ] && total_files_changed=$((total_files_changed + 1))
done
echo "Rewrote placeholders in $total_files_changed file(s)."

# ---------------------------------------------------------------------------
# P2 — derived placeholders. init.sh COMPUTES these; it never asks. A failed derivation
# is reported by name, never silently swapped for a prompt (design.md section 4.1).
#
# resolve_derived reuses the P1 substitution shape via a token NAME variable rather
# than a literal double-brace token string, for the same reason list_target_files excludes
# this script: a literal double-brace token in this file's own source would get
# rewritten by the very substitution loop it drives, the first time an adopter's
# answer happened to be a bare word. Reported-by-name failure messages use the token
# name without braces for the same reason — they are prose, not a live placeholder.
# ---------------------------------------------------------------------------
echo
echo "--- Derived placeholders ---"

resolve_derived() {
  local tok="$1" value="$2" f path esc
  if [ -z "$value" ]; then
    echo "DERIVATION FAILED: $tok — $3"
    return 1
  fi
  for f in $(list_target_files); do
    path="$ROOT/$f"
    [ -f "$path" ] || continue
    if grep -qF "{{$tok}}" "$path" 2>/dev/null; then
      esc="$(printf '%s' "$value" | sed -e 's/[\/&\\]/\\&/g')"
      sed -i.init-tmp "s/{{$tok}}/$esc/g" "$path"
      rm -f "$path.init-tmp"
    fi
  done
  echo "$tok -> $value"
}

REPO_SLUG=""
if remote_url="$(cd "$ROOT" && git remote get-url origin 2>/dev/null)"; then
  # Two passes, deliberately not one combined regex: a single pattern needs a
  # non-greedy `+?` to stop `[^/]+` from swallowing a trailing ".git", and POSIX ERE
  # (what BSD/macOS sed speaks, as opposed to GNU sed's -E extensions) has no
  # non-greedy quantifier at all — `+?` there is a syntax error ("repetition-operator
  # operand invalid"), so this line worked in CI (Ubuntu, GNU sed) and broke for any
  # adopter running init.sh locally on a Mac. Stripping ".git" first removes the need
  # for non-greedy matching entirely, so plain greedy `[^/]+` is correct and portable.
  REPO_SLUG="$(printf '%s' "$remote_url" | sed -E 's#\.git$##' | sed -E 's#^.*[:/]([^/]+/[^/]+)$#\1#')"
fi
resolve_derived REPO_SLUG "$REPO_SLUG" "no 'origin' remote configured. Set one with git remote add origin <url> and re-run tools/init.sh." || true

DEFAULT_BRANCH=""
if branch_ref="$(cd "$ROOT" && git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)"; then
  DEFAULT_BRANCH="${branch_ref##*/}"
elif branch_ref="$(cd "$ROOT" && git symbolic-ref HEAD 2>/dev/null)"; then
  DEFAULT_BRANCH="${branch_ref##*/}"
fi
resolve_derived DEFAULT_BRANCH "$DEFAULT_BRANCH" "could not resolve a symbolic ref. Set the default branch on the remote, or check out one locally, and re-run." || true

TEMPLATE_VERSION=""
if [ -f "$ROOT/CHANGELOG.md" ]; then
  TEMPLATE_VERSION="$(grep -m1 -oE '^## \[?[0-9]+\.[0-9]+\.[0-9]+\]?' "$ROOT/CHANGELOG.md" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
  reason="CHANGELOG.md exists but has no '## x.y.z' heading yet."
else
  reason="CHANGELOG.md does not exist yet."
fi
resolve_derived TEMPLATE_VERSION "$TEMPLATE_VERSION" "$reason" || true

# ---------------------------------------------------------------------------
# Offer to delete the bundled example.
# ---------------------------------------------------------------------------
echo
echo "--- Example product ---"
if [ -d "$ROOT/examples" ]; then
  if [ -t 0 ]; then
    read -r -p "Delete the bundled example under examples/? [y/N]: " del_reply
  else
    del_reply="${DELETE_EXAMPLE:-N}"
  fi
  case "$del_reply" in
    y|Y|yes|YES)
      # Deletion is not the whole move: the workflows, the mutation-scope tool and
      # .gitignore ship targeting the example's paths, and the adopter's product
      # lives at the root layout (backend/, frontend/). adopt-layout.sh deletes
      # AND re-points in one idempotent sweep — the first real adoption did this
      # by hand and counted ~50 references; nobody should do that twice.
      bash "$ROOT/tools/adopt-layout.sh"
      ;;
    *)
      echo "Keeping examples/. Delete it any time by running tools/adopt-layout.sh —"
      echo "it also re-points the workflows at your product's root layout (backend/,"
      echo "frontend/); tools/measure-floors.sh refuses to run while examples/ is present."
      ;;
  esac
else
  echo "No examples/ directory present — nothing to offer deleting."
fi

# ---------------------------------------------------------------------------
# Remove the TEMPLATE's explainer site. Unconditional, because it can never be
# right here: site/ describes the template itself and pages.yml deploys it to
# the TEMPLATE's GitHub Pages — on an adopted repository the workflow's own
# guard already skips it, but the dead files would sit in every adopter's tree
# describing someone else's project. Local deletion only; nothing is pushed.
# ---------------------------------------------------------------------------
if [ -d "$ROOT/site" ] || [ -f "$ROOT/.github/workflows/pages.yml" ]; then
  echo
  echo "--- Template explainer site ---"
  rm -rf "$ROOT/site"
  rm -f "$ROOT/.github/workflows/pages.yml"
  echo "Removed site/ and .github/workflows/pages.yml: they are the TEMPLATE's own"
  echo "explainer site and its Pages deploy — content about the template, not about"
  echo "$PRODUCT_NAME. Nothing of yours lived there."
fi

# ---------------------------------------------------------------------------
# Offer to create the agent-ledger branch. The interview itself is strictly
# offline (SC7, pinned by tests/init-idempotent.bats); this offer is the ONE
# network action init.sh can take, it is opt-in, and the mechanics live in
# tools/create-ledger-branch.sh so declining here costs exactly one command
# later. Non-interactive runs: set CREATE_LEDGER_BRANCH=y to accept.
# ---------------------------------------------------------------------------
echo
echo "--- Agent ledger branch ---"
echo "Your agents keep their run history — one line per run — on a separate, empty"
echo "'orphan' branch named agent-ledger: a diary in this same repository that is"
echo "never merged into your default branch (docs/runbooks/agent-ledgers.md). It"
echo "must exist once before any agent runs; after that, tools/ledger.sh does all"
echo "the reading and writing and you never touch it by hand."
if [ -t 0 ]; then
  read -r -p "Create and push it now? This is the ONE network action init.sh will take, and only with this yes. [y/N]: " ledger_reply
else
  ledger_reply="${CREATE_LEDGER_BRANCH:-N}"
fi
case "$ledger_reply" in
  y|Y|yes|YES)
    bash "$ROOT/tools/create-ledger-branch.sh"
    ;;
  *)
    echo "Skipped. Run tools/create-ledger-branch.sh whenever you are ready — it is"
    echo "idempotent and never touches your working tree."
    ;;
esac

# ---------------------------------------------------------------------------
# The post-init check. init.sh refuses to print "done" if this fails.
# ---------------------------------------------------------------------------
echo
echo "--- Checking for unresolved placeholders ---"
if [ -x "$ROOT/tools/check-placeholders.sh" ]; then
  if ! "$ROOT/tools/check-placeholders.sh"; then
    echo
    echo "init.sh: STOPPING — unresolved placeholders remain (see above). Fix them and re-run." >&2
    exit 1
  fi
else
  echo "tools/check-placeholders.sh not found or not executable — skipping (nothing to verify against)."
fi

# ---------------------------------------------------------------------------
# What remains manual, in the documented order — branch protection LAST.
# ---------------------------------------------------------------------------
cat <<'EOF'

=== init.sh is done. What remains is manual, in this order: ===

  1. Create the ledger orphan branch — one idempotent command, done already if
     you said yes to the offer above:
       tools/create-ledger-branch.sh
     (It is the agents' run diary: docs/runbooks/agent-ledgers.md.)
  2. Add repository secrets. AGENT_CLI_TOKEN is REQUIRED and is normally a
     SUBSCRIPTION TOKEN, not an API key — run
       tools/run-agent.sh --check-credentials <agent>
     and it prints, for the provider you just chose, which secret is missing, how to
     mint it, and where to paste it. CHALLENGE_API_KEY (a real API key, optional, buys
     the second reviewer) and ALERT_WEBHOOK_URL follow the same table in README.md.
  3. Grant read-only observability access if you have a health-signal source
     (docs/runbooks/agent-access-setup.md), then fill in .agents/health-signals.yml.
  4. Install the agent's GitHub App / CLI integration for this repository.
  5. Dry-run each agent prompt interactively before scheduling it:
       tools/run-agent.sh <agent> --dry-run
  6. Calibrate the ratchet against YOUR product (explicitly online, explicitly slow —
     the opposite contract to this script):
       tools/measure-floors.sh
  7. Enable the scheduled routines one at a time in .agents/config.yml
     (ledger.agents[].enabled: true), each after step 5's dry-run.
  8. Enable branch protection LAST, once the FAST tier has been seen green at least
     once — docs/runbooks/branch-protection.md lists the exact context strings.

None of the above was touched by this script. The interview itself made no
network call and wrote nothing but plain text into this tree; the only possible
network action was the ledger-branch push above, taken only with your explicit
yes.
EOF
