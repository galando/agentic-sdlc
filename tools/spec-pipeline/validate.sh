#!/usr/bin/env bash
# tools/spec-pipeline/validate.sh — gate 21's actual check, one implementation.
#
# .github/workflows/spec-artifacts.yml calls this and does nothing else; a developer or
# an agent can run it locally before opening a pull request. The CI check and the local
# pre-flight are the SAME code on purpose — two implementations is exactly how the
# plugin path and the fallback path drift until gate 21 becomes plugin-shaped after all.
# See CONTRACT.md for the algorithm this implements, in prose.
set -euo pipefail

die() { echo "validate.sh: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq is required"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat >&2 <<'EOF'
usage: validate.sh --pr-body-file PATH --changed-files PATH
                    [--labels a,b,c] [--required-labels fix,feature]

  --pr-body-file    a file holding the pull request's body text
  --changed-files   a file holding one changed path per line (git diff --name-only)
  --labels          comma-separated labels on the pull request (default: empty)
  --required-labels comma-separated labels that make gate 21 apply (default: fix,feature)
EOF
}

PR_BODY_FILE=""
CHANGED_FILES_FILE=""
LABELS=""
REQUIRED_LABELS="fix,feature"

while [ $# -gt 0 ]; do
  case "$1" in
    --pr-body-file) PR_BODY_FILE="${2:-}"; shift 2 ;;
    --changed-files) CHANGED_FILES_FILE="${2:-}"; shift 2 ;;
    --labels) LABELS="${2:-}"; shift 2 ;;
    --required-labels) REQUIRED_LABELS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown flag '$1'" ;;
  esac
done

[ -n "$PR_BODY_FILE" ] || { usage; die "--pr-body-file is required"; }
[ -n "$CHANGED_FILES_FILE" ] || { usage; die "--changed-files is required"; }
[ -f "$PR_BODY_FILE" ] || die "--pr-body-file not found: $PR_BODY_FILE"
[ -f "$CHANGED_FILES_FILE" ] || die "--changed-files not found: $CHANGED_FILES_FILE"

print_remedies() {
  local required_labels="$1"
  cat <<EOF
FAIL: this pull request carries a label in [$required_labels] and no spec artifacts.
Two remedies, both accepted:
  1. Commit the spec directory:  .temper/specs/<slug>/{intent,plan,tasks}.md + gates.json
     Create one with: tools/spec-pipeline/new-spec.sh <slug>
  2. If the pipeline is genuinely unreachable, put this line in the PR body:
       temper: unavailable — <the real reason>
     The reason is recorded as a warning annotation. "Availability is a finding,
     not an excuse": say what was unreachable and why.
EOF
}

# --- 1. Does gate 21 even apply to this PR? --------------------------------
IFS=',' read -r -a required_arr <<<"$REQUIRED_LABELS"
IFS=',' read -r -a label_arr <<<"$LABELS"
applies=0
for r in "${required_arr[@]}"; do
  [ -z "$r" ] && continue
  for l in "${label_arr[@]}"; do
    [ "$l" = "$r" ] && applies=1
  done
done
if [ "$applies" -eq 0 ]; then
  echo "PASS: no label in [$REQUIRED_LABELS] present — gate 21 does not apply to this pull request."
  exit 0
fi

# --- 2. Declared-unavailable escape hatch -----------------------------------
NON_REASONS="n/a none - tbd"
unavailable_line="$(grep -iE '^temper: unavailable[[:space:]]*[—–-][[:space:]]*(.+)$' "$PR_BODY_FILE" | head -n1 || true)"
if [ -n "$unavailable_line" ]; then
  reason="$(printf '%s' "$unavailable_line" | sed -E 's/^temper: unavailable[[:space:]]*[—–-][[:space:]]*//I')"
  reason_trimmed="$(printf '%s' "$reason" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  is_non_reason=0
  for nr in $NON_REASONS; do
    low="$(printf '%s' "$reason_trimmed" | tr '[:upper:]' '[:lower:]')"
    [ "$low" = "$nr" ] && is_non_reason=1
  done
  if [ "$is_non_reason" -eq 0 ] && [ "${#reason_trimmed}" -ge 10 ]; then
    echo "::warning title=Spec pipeline declared unavailable::$reason_trimmed"
    echo "PASS: spec pipeline declared unavailable — $reason_trimmed"
    exit 0
  fi
  echo "FAIL: 'temper: unavailable — ...' line found but the reason is missing or too short (need >= 10 characters, and not one of: $NON_REASONS)." >&2
  print_remedies "$REQUIRED_LABELS" >&2
  exit 1
fi

# --- 3. The diff must carry a complete spec directory -----------------------
# (a portable read loop, not `mapfile` — not a bash-4+ builtin, and this must run under
# whatever /usr/bin/env bash resolves to, including bash 3.2)
changed=()
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] && changed+=("$line")
done < "$CHANGED_FILES_FILE"

find_slug_for() {
  local suffix="$1" f
  for f in "${changed[@]}"; do
    case "$f" in
      .temper/specs/*/"$suffix")
        f="${f#.temper/specs/}"
        printf '%s\n' "${f%%/*}"
        return 0
        ;;
    esac
  done
  return 1
}

slug="$(find_slug_for intent.md || true)"
if [ -z "$slug" ]; then
  echo "FAIL: no .temper/specs/<slug>/intent.md in this pull request's diff." >&2
  print_remedies "$REQUIRED_LABELS" >&2
  exit 1
fi

missing=""
for suffix in intent.md plan.md tasks.md gates.json; do
  found=0
  for f in "${changed[@]}"; do
    [ "$f" = ".temper/specs/$slug/$suffix" ] && found=1
  done
  [ "$found" -eq 1 ] || missing="$missing .temper/specs/$slug/$suffix"
done

if [ -n "$missing" ]; then
  echo "FAIL: .temper/specs/$slug/ is missing from this pull request's diff:$missing" >&2
  print_remedies "$REQUIRED_LABELS" >&2
  exit 1
fi

# --- 4. gates.json must parse and carry at least one non-FAIL stage ---------
GATES_FILE="$ROOT/.temper/specs/$slug/gates.json"
[ -f "$GATES_FILE" ] || die "$GATES_FILE is listed as changed but does not exist on disk — is the branch checked out?"

if ! jq -e '.spec_contract == 1' "$GATES_FILE" >/dev/null 2>&1; then
  echo "FAIL: $GATES_FILE does not parse or does not declare spec_contract: 1." >&2
  print_remedies "$REQUIRED_LABELS" >&2
  exit 1
fi

ok_stage_count="$(jq '[.stages[]? | select(.verdict == "PASS" or .verdict == "PASS_WITH_WARNINGS")] | length' "$GATES_FILE")"
if [ "$ok_stage_count" -lt 1 ]; then
  echo "FAIL: $GATES_FILE has no stage with verdict PASS or PASS_WITH_WARNINGS — a committed FAIL does not satisfy gate 21." >&2
  print_remedies "$REQUIRED_LABELS" >&2
  exit 1
fi

echo "PASS: .temper/specs/$slug/ carries intent.md, plan.md, tasks.md and gates.json, with $ok_stage_count passing stage(s)."
exit 0
