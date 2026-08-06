#!/usr/bin/env bash
# tools/spec-pipeline/new-spec.sh <slug> — create a spec directory from templates/.
#
# This is the fallback path: it exists so that ANY agent, on any provider, that cannot
# reach its own build plugin still produces the artifacts CONTRACT.md requires. See
# .github/agent-temper-headless.md "Availability is a finding, not an excuse" — reach
# for this second, not first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

die() { echo "new-spec.sh: $*" >&2; exit 1; }

SLUG="${1:-}"
[ -n "$SLUG" ] || die "usage: new-spec.sh <slug>  (kebab-case, e.g. fix-login-redirect)"
if ! printf '%s' "$SLUG" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
  die "slug '$SLUG' must be kebab-case (lowercase letters, digits, hyphens)"
fi

SPEC_DIR="$ROOT/.temper/specs/$SLUG"
if [ -d "$SPEC_DIR" ]; then
  die "$SPEC_DIR already exists — pick a new slug, or continue working in the existing one"
fi

mkdir -p "$SPEC_DIR"

# {{SLUG}} {{DATE}} placeholder: kebab-case spec slug (from argv), and today's date (UTC YYYY-MM-DD) — resolved fresh on every call, not a one-time init.sh substitution.
DATE="$(date -u +%Y-%m-%d)"
for f in intent.md plan.md tasks.md; do
  sed -e "s/{{SLUG}}/$SLUG/g" -e "s/{{DATE}}/$DATE/g" "$TEMPLATES_DIR/$f" > "$SPEC_DIR/$f"
done

cat > "$SPEC_DIR/gates.json" <<EOF
{
  "spec_contract": 1,
  "stages": {}
}
EOF

cat <<EOF
Created $SPEC_DIR
  intent.md   — fill in the problem, success criteria and at least one scenario
  plan.md     — fill in the approach, files touched and blast radius
  tasks.md    — fill in ordered tasks, each with a Validate: line
  gates.json  — empty; tools/spec-pipeline/record-gate.sh appends stage verdicts

design.md is optional — copy tools/spec-pipeline/templates/design.md in only for a
change complex enough to need the exploration written down.

Gate 21 (.github/workflows/spec-artifacts.yml) needs intent.md, plan.md, tasks.md and
gates.json to change in THIS pull request's diff, and gates.json to carry at least one
stage whose verdict is PASS or PASS_WITH_WARNINGS — see
tools/spec-pipeline/CONTRACT.md.
EOF
