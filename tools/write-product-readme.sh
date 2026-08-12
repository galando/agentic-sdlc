#!/usr/bin/env bash
# tools/write-product-readme.sh — replace the TEMPLATE's README with the PRODUCT's.
#
# Why this exists: an adopted repository kept the template's own README — "this is a
# GitHub template, click Use this template" — indefinitely, because nothing in the
# adoption ever touched it. A visitor to a real product repo read a description of
# somebody else's project, and nothing on the front page said "this repository is run
# by an agentic SDLC" even though every workflow behind it was. The README is the one
# page every visitor sees; it is part of the adoption surface, so the adoption tooling
# owns it.
#
# What it writes: a README titled with YOUR product, live status badges for the
# harness workflows that exist in this tree, a clearly-marked section for you to
# describe the product in, and a section explaining the agentic SDLC this repository
# runs — the loop, the gates, where to see each piece live — with a pointer back to
# the upstream template for anyone who wants the same setup.
#
# Called by tools/init.sh when you accept the README offer (it knows your product
# name from the interview), and runnable directly at any later time:
#
#   tools/write-product-readme.sh [PRODUCT_NAME] [--force]
#
# With no PRODUCT_NAME argument it reads the name AGENTS.md already carries after
# the interview. SAFE BY DEFAULT: it only ever replaces a README it can positively
# identify as the template's own; a README that is already yours is left alone
# (exit 0, with a message) unless you pass --force. Offline, plain text only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

die() { echo "write-product-readme.sh: $*" >&2; exit 1; }

TEMPLATE_REPO_URL="https://github.com/galando/agentic-sdlc"
TEMPLATE_SITE_URL="https://galando.github.io/agentic-sdlc/"

PRODUCT_NAME=""
FORCE="${FORCE_README:-false}"
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    -h|--help)
      echo "usage: tools/write-product-readme.sh [PRODUCT_NAME] [--force]"
      exit 0
      ;;
    *) PRODUCT_NAME="$arg" ;;
  esac
done

# ---------------------------------------------------------------------------
# 1. The product name: argument first, then the line AGENTS.md carries after
#    tools/init.sh's interview. If neither yields one, say exactly what to do.
# ---------------------------------------------------------------------------
if [ -z "$PRODUCT_NAME" ] && [ -f "$ROOT/AGENTS.md" ]; then
  PRODUCT_NAME="$(sed -n 's/^These rules bind every autonomous agent session operating on \(.*\),$/\1/p' "$ROOT/AGENTS.md" | head -1)"
fi
[ -n "$PRODUCT_NAME" ] || die "no product name. Pass it as an argument (tools/write-product-readme.sh \"My Product\") or run tools/init.sh first — the interview writes it into AGENTS.md, which is where this script reads it from."
case "$PRODUCT_NAME" in
  *'{{'*) die "the product name still reads as an unresolved placeholder ('$PRODUCT_NAME') — run tools/init.sh first." ;;
esac

# ---------------------------------------------------------------------------
# 2. Overwrite policy. The template's README is positively identified by its
#    own H1 — the one string that survives no adoption, because nothing until
#    this script ever rewrote the file. Anything else is treated as YOURS:
#    replaced only under --force, never by default, so re-running init.sh (or
#    this script) after you have written a real README costs you nothing.
# ---------------------------------------------------------------------------
README="$ROOT/README.md"
if [ -f "$README" ] && [ "$FORCE" != "true" ]; then
  if ! grep -qE '^# Agentic SDLC$' "$README"; then
    echo "README.md is already your own (it no longer carries the template's title) — not touching it."
    echo "Re-run with --force to regenerate it from scratch."
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# 3. Status badges — the "see for yourself it is working" row. OWNER/REPO come
#    from the origin remote; with no parseable origin the README is generated
#    without badges and says so, rather than shipping dead image links. Only
#    workflows actually present in this tree get a badge.
# ---------------------------------------------------------------------------
ORIGIN_URL="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
# Two expressions, not one: POSIX ERE has no lazy quantifier, so a single
# pattern's greedy [^/]+ would keep ".git" inside the captured slug.
SLUG="$(printf '%s\n' "$ORIGIN_URL" \
  | sed -E -e 's#\.git/?$##' \
  | sed -nE 's#^(git@[^:]+:|https?://[^/]+/|ssh://git@[^/]+/)([^/]+/[^/]+)$#\2#p')"

BADGES=""
if [ -n "$SLUG" ]; then
  for wf in pr-tests review pr-mutation nightly; do
    [ -f "$ROOT/.github/workflows/$wf.yml" ] || continue
    BADGES="${BADGES}[![$wf](https://github.com/$SLUG/actions/workflows/$wf.yml/badge.svg)](https://github.com/$SLUG/actions/workflows/$wf.yml)
"
  done
fi
[ -n "$BADGES" ] || echo "note: no parseable 'origin' remote — generating without status badges (add them once the repository is pushed, or re-run this script with --force then)."

ADOPTION_LOG_LINE=""
if [ -f "$ROOT/ADOPTION-LOG.md" ]; then
  ADOPTION_LOG_LINE="- **[\`ADOPTION-LOG.md\`](ADOPTION-LOG.md)** — the step-by-step record of how this repository adopted the process, written as it happened.
"
fi

# The floors bullet states what floors.yml actually holds, not what the adoption
# hopes will happen. A live adoption shipped a front page claiming the floors
# "was calibrated against this code" while every value in floors.yml still
# carried the `unset` sentinel — calibration had been deferred and never done,
# and the generated README was the only place that said otherwise. Same
# sentinel test as tools/adopt.sh step 6 and tools/status.sh step 4.
if [ -f "$ROOT/floors.yml" ] && ! grep -qE '^[^#]*value:[[:space:]]*unset' "$ROOT/floors.yml"; then
  FLOORS_BULLET="- **The quality floors are this repository's own measured baseline**, not anyone
  else's finish line: [\`floors.yml\`](floors.yml) was calibrated against this
  code by \`tools/measure-floors.sh\`, and the ratchet only lets those numbers
  move up."
else
  FLOORS_BULLET="- **The quality floors are not yet calibrated.** [\`floors.yml\`](floors.yml) still
  carries \`unset\` sentinels — the gates run but cannot ratchet until
  \`tools/measure-floors.sh\` measures this repository's own baseline. (This
  line rewrites itself to say so once you re-run \`tools/write-product-readme.sh
  --force\` after calibrating.)"
fi

# ---------------------------------------------------------------------------
# 4. Write it.
# ---------------------------------------------------------------------------
cat > "$README" <<EOF
# $PRODUCT_NAME

$BADGES
> **Describe $PRODUCT_NAME here** — what it does, who it is for, how to run it.
> This section is yours. Everything below the rule explains how this repository
> *runs itself*, and was generated by \`tools/write-product-readme.sh\`.

---

## This repository runs an agentic SDLC

$PRODUCT_NAME is developed under an autonomous-agent process adopted from the
**[Agentic SDLC template]($TEMPLATE_REPO_URL)** ([guided tour]($TEMPLATE_SITE_URL)).
One line: **agents propose, CI decides, a human merges.**

\`\`\`
  issue opened  ──▶  steward triages  ──▶  PR opened  ──▶  automated reviews
                                                                │
        ┌───────────────────────────────────────────────────────┘
        ▼
  quality-gate gauntlet  ──▶  a HUMAN merges  ──▶  the filing agent verifies the fix
\`\`\`

Concretely, in this repository:

- **Issues are triaged by an agent** (the steward, \`.github/workflows/steward.yml\`).
  Mention it on an issue and it investigates, opens a branch, and raises a pull
  request — it can never merge one.
- **Every pull request is reviewed automatically** (\`.github/workflows/review.yml\`):
  a judge-role review on every PR, an adversarial second review from a *different
  model family* when configured, and a referee comment listing where the two
  disagree. Reviews are advisory to the human, binding on the agents.
- **A gauntlet of quality gates runs on every PR** — tests, coverage, mutation
  testing, architecture rules, lint, migrations, secret scanning and more. The
  full inventory and the ratchet policy: [\`docs/QUALITY-GATES.md\`](docs/QUALITY-GATES.md).
$FLOORS_BULLET
- **Every agent run is on the record.** Scheduled agents append one line per run
  to the \`agent-ledger\` branch — history, never instruction.
- **No agent merges. Ever.** The merge button is the human's; the guardrails
  binding every agent session are in [\`AGENTS.md\`](AGENTS.md).

Where to see it working, right now:

- **The [Actions tab](../../actions)** — every review, gauntlet run and scheduled
  agent, with logs.
- **[Closed pull requests](../../pulls?q=is%3Apr)** — each one carries its
  automated reviews and its full gate run.
$ADOPTION_LOG_LINE
## Asking for a change

Open an issue describing what you want and mention the agent (the mention phrase
is the \`AGENT_MENTION\` repository variable — default \`@agent\`). The steward picks
it up from there; you review and merge what comes back. Operator details:
[\`docs/runbooks/agent-operator-guide.md\`](docs/runbooks/agent-operator-guide.md).

## Want this process on your own repository?

It is a GitHub template — one interview and four scripts to adopt:
**[$TEMPLATE_REPO_URL]($TEMPLATE_REPO_URL)**.
EOF

echo "Wrote README.md for '$PRODUCT_NAME'."
if [ -n "$SLUG" ]; then
  echo "  - status badges point at $SLUG"
fi
echo "  - the description block at the top is a stub: fill it in, review the diff, commit."
