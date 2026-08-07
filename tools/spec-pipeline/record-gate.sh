#!/usr/bin/env bash
# tools/spec-pipeline/record-gate.sh <slug> <stage> <verdict> [name=pass:detail]...
#
# Appends one stage's verdict to .temper/specs/<slug>/gates.json. NEVER rewrites another
# stage's entry — each call only touches stages.<stage>, so plan/build/review/check can
# each record independently without clobbering the others.
set -euo pipefail

die() { echo "record-gate.sh: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat >&2 <<'EOF'
usage: record-gate.sh <slug> <stage> <PASS|PASS_WITH_WARNINGS|FAIL> [name=pass:detail]...

  <slug>    the spec directory under .temper/specs/
  <stage>   e.g. plan, build, review, check
  verdict   PASS | PASS_WITH_WARNINGS | FAIL
  each requirement is  name=pass:detail  where pass is "true" or "false"
                       e.g. 'RED then GREEN=true:1 failing-first run(s), 1 passing run(s)'
EOF
}

SLUG="${1:-}"; STAGE="${2:-}"; VERDICT="${3:-}"
[ -n "$SLUG" ] && [ -n "$STAGE" ] && [ -n "$VERDICT" ] || { usage; exit 2; }
shift 3 || true

case "$VERDICT" in
  PASS|PASS_WITH_WARNINGS|FAIL) : ;;
  *) usage; die "verdict must be PASS, PASS_WITH_WARNINGS or FAIL, got '$VERDICT'" ;;
esac

SPEC_DIR="$ROOT/.temper/specs/$SLUG"
GATES_FILE="$SPEC_DIR/gates.json"
[ -d "$SPEC_DIR" ] || die "$SPEC_DIR does not exist — run new-spec.sh $SLUG first"

if [ ! -f "$GATES_FILE" ]; then
  echo '{"spec_contract":1,"stages":{}}' > "$GATES_FILE"
fi

jq -e '.spec_contract == 1' "$GATES_FILE" >/dev/null 2>&1 || die "$GATES_FILE does not declare spec_contract: 1"

REQS_JSON="[]"
for arg in "$@"; do
  name="${arg%%=*}"
  rest="${arg#*=}"
  pass="${rest%%:*}"
  detail="${rest#*:}"
  [ "$rest" = "$arg" ] && { detail=""; pass="$rest"; }
  case "$pass" in true|false) : ;; *) die "requirement '$arg': pass must be true or false" ;; esac
  REQS_JSON="$(printf '%s' "$REQS_JSON" | jq -c --arg name "$name" --argjson pass "$pass" --arg detail "$detail" \
    '. + [{"name":$name,"pass":$pass,"detail":$detail}]')"
done

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
tmp="$(mktemp "$SPEC_DIR/.gates.json.XXXXXX")"
jq --arg stage "$STAGE" --arg verdict "$VERDICT" --arg ts "$TS" --argjson reqs "$REQS_JSON" \
  '.stages[$stage] = {"verdict": $verdict, "ts": $ts, "requirements": $reqs}' \
  "$GATES_FILE" > "$tmp"
mv "$tmp" "$GATES_FILE"

echo "recorded $SLUG/$STAGE = $VERDICT ($GATES_FILE)"
