#!/usr/bin/env bash
# tools/bootstrap.sh — adopt the agentic SDLC into the repository you are standing in.
# ONE command, no questions, nothing pushed.
#
#   # from inside any git repository (new or existing):
#   curl -fsSL https://raw.githubusercontent.com/galando/agentic-sdlc/main/tools/bootstrap.sh | bash -s -- --product "My Product"
#
#   # from a clone made with "Use this template":
#   tools/bootstrap.sh --product "My Product"
#
# Why this exists: the adoption used to be a short document, four tools in a documented
# order, and an interview with eleven questions. Every live adoption stalled on the same
# thing — not a broken step, but a human unsure which step was theirs. This script makes
# the whole LOCAL half one command with sensible, printed defaults, and prints the short
# list that genuinely needs a human (a token, one GitHub setting, a merge) at the end.
#
# What it does, in order:
#   1. Finds the repository (`git rev-parse`), refuses politely if there is none.
#   2. Works out which of three states you are in:
#        - the harness is not here yet (an existing repository): fetches the template
#          (or uses --source) and installs the harness beside your files with
#          tools/upgrade.sh --install — it never overwrites anything of yours;
#        - the harness is here but not initialised (a "Use this template" clone);
#        - already adopted: prints the status map and stops.
#   3. Runs the interview with no questions: tools/init.sh --defaults — every assumption
#      is printed, PRODUCT_NAME comes from --product or the repository name.
#   4. Verifies with the shipped checkers (tools/check-placeholders.sh, tools/status.sh).
#   5. Prints the handback: what only you can do, in order.
#
# It never pushes, never touches GitHub, never reads a secret. Safe to re-run: the
# second run finds the repository adopted and stops at step 2.
#
# Options:
#   --product NAME     the system your agents watch (default: the repository's name)
#   --provider NAME    the agent CLI you subscribe to (default: claude-code)
#   --source DIR       a local template checkout to install from (default: clone
#                      $AGENTIC_SDLC_REPO at $AGENTIC_SDLC_REF; DIR wins over both)
#   --ref REF          the template branch or tag to fetch (default: main)
#   --dry-run          print the plan and exit without changing anything
set -uo pipefail

AGENTIC_SDLC_REPO="${AGENTIC_SDLC_REPO:-https://github.com/galando/agentic-sdlc}"
AGENTIC_SDLC_REF="${AGENTIC_SDLC_REF:-main}"
SOURCE="${AGENTIC_SDLC_SOURCE:-}"
PRODUCT="" PROVIDER_ARG="" DRY_RUN=false

say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n=== %s ===\n' "$*"; }
die()  { printf 'bootstrap.sh: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --product)  PRODUCT="${2:-}"; shift 2 ;;
    --provider) PROVIDER_ARG="${2:-}"; shift 2 ;;
    --source)   SOURCE="${2:-}"; shift 2 ;;
    --ref)      AGENTIC_SDLC_REF="${2:-}"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    -h|--help)  sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option '$1' (see --help)" ;;
  esac
done

command -v git >/dev/null 2>&1 || die "git is required"

# --- 1. The repository ---------------------------------------------------------
TARGET="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  say "bootstrap.sh: this directory is not inside a git repository." >&2
  say "  The harness lives in your repository's tree, so create one first:" >&2
  say "    git init && git add -A && git commit -m 'initial'" >&2
  say "  then run this command again from inside it." >&2
  exit 1
}
cd "$TARGET" || die "cannot cd to $TARGET"

# --- 2. Which state are we in? --------------------------------------------------
PROVIDER_TOKEN="$(printf '{{%s}}' PROVIDER)"   # built, never literal: init.sh would rewrite it
STATE=""
if [ ! -f "$TARGET/.agents/config.yml" ]; then
  STATE=brownfield
elif grep -qF "$PROVIDER_TOKEN" "$TARGET/.agents/config.yml"; then
  STATE=template-clone
else
  STATE=adopted
fi

hdr "Adopting the agentic SDLC into $TARGET"
case "$STATE" in
  brownfield)     say "State: your repository, harness not installed yet — it will be installed beside your files." ;;
  template-clone) say "State: a clone of the template, interview not run yet." ;;
  adopted)
    say "State: already adopted. Nothing to do here; the map:"
    [ -x "$TARGET/tools/status.sh" ] && bash "$TARGET/tools/status.sh"
    exit 0 ;;
esac

if $DRY_RUN; then
  say "Plan (--dry-run, nothing changed):"
  if [ "$STATE" = brownfield ]; then
    if [ -n "$SOURCE" ]; then say "  1. install the harness from $SOURCE with tools/upgrade.sh --install $TARGET"
    else say "  1. clone $AGENTIC_SDLC_REPO ($AGENTIC_SDLC_REF) to a temporary directory and install the harness with tools/upgrade.sh --install $TARGET"; fi
  fi
  say "  2. tools/init.sh --defaults  (PRODUCT_NAME=${PRODUCT:-<the repository name>}, PROVIDER=${PROVIDER_ARG:-claude-code})"
  say "  3. tools/check-placeholders.sh && tools/status.sh"
  say "  4. print the handback list"
  exit 0
fi

# --- 2b. Brownfield: fetch and install the harness ----------------------------------
CLONE_DIR=""
cleanup() { [ -n "$CLONE_DIR" ] && rm -rf "$CLONE_DIR"; }
trap cleanup EXIT

if [ "$STATE" = brownfield ]; then
  command -v jq >/dev/null 2>&1 || die "jq is required to install the harness (tools/upgrade.sh stamps a manifest with it)"
  if [ -z "$SOURCE" ]; then
    CLONE_DIR="$(mktemp -d)"
    say "Fetching the template: $AGENTIC_SDLC_REPO ($AGENTIC_SDLC_REF) ..."
    git clone --quiet --depth 1 --branch "$AGENTIC_SDLC_REF" "$AGENTIC_SDLC_REPO" "$CLONE_DIR/template" \
      || die "could not clone $AGENTIC_SDLC_REPO at $AGENTIC_SDLC_REF. Offline? Clone it yourself and pass --source <dir>."
    SOURCE="$CLONE_DIR/template"
  fi
  [ -x "$SOURCE/tools/upgrade.sh" ] || die "$SOURCE does not look like a template checkout (no tools/upgrade.sh)"
  hdr "Installing the harness (never overwrites your files)"
  AGENTS_ROOT="$SOURCE" bash "$SOURCE/tools/upgrade.sh" --install "$TARGET" || die "the installer failed — see its message above"

  # The interview substitutes placeholders in TRACKED files only (tools/init.sh sweeps
  # `git ls-files`), and the files just copied in are not tracked yet. Intent-to-add
  # makes them visible to that sweep without staging content or touching your own
  # untracked files. The commit itself stays yours to make and review.
  while IFS= read -r f; do
    [ -f "$TARGET/$f" ] && git -C "$TARGET" add --intent-to-add -- "$f" 2>/dev/null
    [ -f "$TARGET/$f.agentic-sdlc.proposed" ] && git -C "$TARGET" add --intent-to-add -- "$f.agentic-sdlc.proposed" 2>/dev/null
  done < <(AGENTS_ROOT="$SOURCE" bash "$SOURCE/tools/upgrade.sh" list-files)
  [ -f "$TARGET/.agents/template-manifest.json" ] && git -C "$TARGET" add --intent-to-add -- .agents/template-manifest.json 2>/dev/null
fi

# --- 3. The interview, with no questions -------------------------------------------
hdr "The interview, with no questions (tools/init.sh --defaults)"
[ -x "$TARGET/tools/init.sh" ] || die "tools/init.sh is missing from $TARGET — the install did not land"
if [ -n "$PRODUCT" ]; then export PRODUCT_NAME="$PRODUCT"; fi
if [ -n "$PROVIDER_ARG" ]; then export PROVIDER="$PROVIDER_ARG"; fi
# stdin is closed on purpose: this script may itself be running from a pipe (curl | bash),
# and the interview's three yes/no offers must read our answers, never the script text.
# WRITE_README=y only ever replaces the TEMPLATE's own README (the generator identifies
# it positively), so an existing repository's README is never touched.
WRITE_README=y DELETE_EXAMPLE=N CREATE_LEDGER_BRANCH=N \
  bash "$TARGET/tools/init.sh" --defaults </dev/null \
  || die "the interview did not finish — fix the message above and re-run tools/bootstrap.sh (it resumes)"

# --- 4. Verify with the shipped checkers, never by eye ---------------------------------
hdr "Verifying"
bash "$TARGET/tools/check-placeholders.sh" || die "unresolved placeholders remain — see above"
bash "$TARGET/tools/status.sh" || true

# --- 5. The handback -----------------------------------------------------------------
MENTION="@agent"
if [ -f "$TARGET/tools/lib/config.sh" ]; then
  # shellcheck source=lib/config.sh
  AGENTS_ROOT="$TARGET" . "$TARGET/tools/lib/config.sh" 2>/dev/null && MENTION="$(cfg_get mention.default '@agent' 2>/dev/null || echo '@agent')"
fi
cat <<EOF

=== Done locally. Four things only you can do, in this order ===

  1. Review and commit what just landed, then push:
       git add -A && git commit -m "adopt the agentic-sdlc process" && git push
     (an existing repository: merge any *.agentic-sdlc.proposed file into your own by hand)

  2. Give the agents their credential — one repository secret, AGENT_CLI_TOKEN.
     What belongs in it and how to mint it, for your provider:
       tools/run-agent.sh --check-credentials steward --role judge
     Without it every agent job stops at the credential check and the loop looks broken.

  3. Let Actions open pull requests: Settings → Actions → General → Workflow
     permissions → "Read and write", and tick "Allow GitHub Actions to create and
     approve pull requests". Fresh repositories ship with it OFF.
     (tools/adopt.sh offers to do 2 and 3 for you with the gh CLI, and walks the rest.)

  4. Open issue #1 describing a small real change and mention the agent ($MENTION).
     The steward opens a pull request; two reviews and the gauntlet run; YOU merge.

Everything else — retiring the bundled example, calibrating the quality floors to your
code, enabling the scheduled agents one at a time, branch protection — is optional
today and guided later: tools/adopt.sh (resumable), or the map: tools/status.sh.
EOF
