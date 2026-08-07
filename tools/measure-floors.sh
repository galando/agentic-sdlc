#!/usr/bin/env bash
# tools/measure-floors.sh — arm the ratchet against the ADOPTER'S OWN code.
#
# The opposite contract to tools/init.sh, and it says so in those words: explicitly
# ONLINE (it builds and tests your product for real), explicitly SLOW (minutes, not
# seconds). See design.md section 7.4 and the intent scenario "Uncalibrated floors pass
# loudly, then arm against the adopter's own baseline".
#
# Two guards make the ratchet's promise ("floors only move up from where YOU are") hold:
#   1. Refuses while examples/ is present — a floor measured against the bundled
#      example is a floor calibrated to a toy service the adopter is about to delete
#      (SC12b). No --anyway flag; this is the whole mechanism.
#   2. Refuses on a dirty working tree — the rewrite must land as its own reviewable
#      diff, not mixed into whatever else was in progress.
# On a re-run it refuses to LOWER an already-calibrated floor without --rebaseline
# "<reason>" — the only two honest reasons, named in the refusal message, are that the
# measuring instrument changed or the scope got wider.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/config.sh
. "$ROOT/tools/lib/config.sh"

FLOORS_FILE="$(_floors_file)"

die() { echo "measure-floors.sh: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
usage: tools/measure-floors.sh [--rebaseline "<reason>"] [--only KEY]

Measures line/branch coverage, mutation score and bundle size against the code
actually in this working tree, and writes the result into floors.yml, replacing the
`unset` sentinel (or, with --rebaseline, replacing an existing calibrated value).

  --rebaseline "<reason>"   required to LOWER an already-calibrated floor. The only
                            two honest reasons: the measuring instrument changed, or
                            the scope got wider. Say which, every time.
  --only KEY                measure a single floor key (e.g. backend.coverage.line)
                            instead of all nine. Useful while wiring up one tool at a
                            time.

Explicitly ONLINE, explicitly SLOW — the opposite contract to tools/init.sh.
EOF
}

REBASELINE_REASON=""
ONLY_KEY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rebaseline) REBASELINE_REASON="${2:-}"; shift 2 ;;
    --only) ONLY_KEY="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown flag '$1'" ;;
  esac
done

# --- Guard 1: refuse while the bundled example is present -------------------
if [ -d "$ROOT/examples" ]; then
  die "examples/ is still present. Floors measured against the bundled example are
floors calibrated to a toy service you were invited to delete. Remove or move
examples/ first. There is no --anyway flag; this guard is the whole mechanism
behind SC12b."
fi

# --- Guard 2: refuse on a dirty working tree ---------------------------------
if [ -n "$(cd "$ROOT" && git status --porcelain 2>/dev/null || true)" ]; then
  die "the working tree is dirty. The floor rewrite must land as its own reviewable
diff — commit or stash what is already in progress, then re-run."
fi

[ -f "$FLOORS_FILE" ] || die "$FLOORS_FILE not found. Was this cloned from the template?"

TODAY="$(date -u +%Y-%m-%d)"

# ---------------------------------------------------------------------------
# One function per tool. Each returns a decimal MEASURED value on stdout, or prints
# "SKIP: <reason>" and returns 1 when the tool's config is not present in this repo —
# a template instantiation may not have wired up every stack yet (SC3: absent stack
# skips cleanly, never fails loudly).
#
# Measurement targets the ADOPTER'S product at $ROOT/backend and $ROOT/frontend —
# the layout the closing message names — never examples/ (guard 1 forbids it, and
# an examples/-prefixed path here would make guard 1 and the measurement paths
# mutually exclusive: the script could never measure anything at all).
# ---------------------------------------------------------------------------
measure_backend_line() {
  [ -f "$ROOT/backend/pom.xml" ] || { echo "SKIP: no backend/pom.xml"; return 1; }
  command -v mvn >/dev/null 2>&1 || { echo "SKIP: mvn not on PATH"; return 1; }
  ( cd "$ROOT/backend" && mvn -q -DskipITs clean verify ) >&2
  csv="$ROOT/backend/target/site/jacoco/jacoco.csv"
  [ -f "$csv" ] || { echo "SKIP: jacoco.csv not produced"; return 1; }
  # Columns 8/9 are LINE_MISSED/LINE_COVERED. 4/5 are the INSTRUCTION counters —
  # measuring those here while render-floors.sh enforces <counter>LINE</counter>
  # would calibrate the floor with one instrument and gate with another.
  awk -F, 'NR>1{cov+=$8+$9; miss+=$8} END{if (cov==0){print 0} else {printf "%.4f\n", 1 - (miss/cov)}}' "$csv"
}

measure_backend_branch() {
  [ -f "$ROOT/backend/pom.xml" ] || { echo "SKIP: no backend/pom.xml"; return 1; }
  csv="$ROOT/backend/target/site/jacoco/jacoco.csv"
  [ -f "$csv" ] || { echo "SKIP: jacoco.csv not produced (run the line-coverage measurement first)"; return 1; }
  awk -F, 'NR>1{cov+=$6+$7; miss+=$6} END{if (cov==0){print 0} else {printf "%.4f\n", 1 - (miss/cov)}}' "$csv"
}

measure_backend_mutation() {
  [ -f "$ROOT/backend/pom.xml" ] || { echo "SKIP: no backend/pom.xml"; return 1; }
  command -v mvn >/dev/null 2>&1 || { echo "SKIP: mvn not on PATH"; return 1; }
  grep -q '<id>mutation</id>' "$ROOT/backend/pom.xml" 2>/dev/null || { echo "SKIP: no 'mutation' Maven profile in pom.xml"; return 1; }
  ( cd "$ROOT/backend" && mvn -q -Pmutation org.pitest:pitest-maven:mutationCoverage ) >&2
  xml="$(find "$ROOT/backend/target/pit-reports" -name mutations.xml 2>/dev/null | head -n1)"
  [ -n "$xml" ] || { echo "SKIP: mutations.xml not produced"; return 1; }
  total="$(grep -c '<mutation ' "$xml" || true)"
  # status=.KILLED. with either quote style: PIT writes SINGLE-quoted attributes
  # (status='KILLED'), and a double-quote-only grep counts zero kills — the first
  # real calibration scored a fully-tested product 0.0000 and wrote a floor of 0,
  # which is exactly the "indistinguishable from disabled" state floors.yml exists
  # to prevent.
  killed="$(grep -cE "status=[\"']KILLED[\"']" "$xml" || true)"
  [ "$total" -gt 0 ] || { echo "SKIP: PIT reported zero mutants"; return 1; }
  awk -v k="$killed" -v t="$total" 'BEGIN{printf "%.4f\n", k/t}'
}

measure_frontend_vitest() {
  [ -f "$ROOT/frontend/package.json" ] || { echo "SKIP: no frontend/package.json"; return 1; }
  command -v npm >/dev/null 2>&1 || { echo "SKIP: npm not on PATH"; return 1; }
  ( cd "$ROOT/frontend" && npm ci --silent && npx --yes vitest run --coverage ) >&2
  summary="$ROOT/frontend/coverage/coverage-summary.json"
  [ -f "$summary" ] || { echo "SKIP: coverage-summary.json not produced"; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; return 1; }
  jq -r '.total | "\(.statements.pct) \(.branches.pct) \(.functions.pct) \(.lines.pct)"' "$summary"
}

measure_frontend_mutation() {
  [ -f "$ROOT/frontend/stryker.config.mjs" ] || { echo "SKIP: no frontend/stryker.config.mjs"; return 1; }
  command -v npm >/dev/null 2>&1 || { echo "SKIP: npm not on PATH"; return 1; }
  ( cd "$ROOT/frontend" && npx --yes stryker run ) >&2
  report="$ROOT/frontend/reports/mutation/mutation.json"
  [ -f "$report" ] || { echo "SKIP: mutation.json not produced"; return 1; }
  # Stryker's mutationScore is a PERCENTAGE (e.g. 87.88); floors.yml stores
  # coverage/mutation floors as 0..1 ratios and write_floor scales by 100 itself.
  jq -r '.mutationScore / 100' "$report"
}

measure_frontend_bundle() {
  [ -f "$ROOT/frontend/package.json" ] || { echo "SKIP: no frontend/package.json"; return 1; }
  script="$ROOT/frontend/scripts/check-bundle.mjs"
  [ -f "$script" ] || { echo "SKIP: no frontend/scripts/check-bundle.mjs"; return 1; }
  ( cd "$ROOT/frontend" && npm run -s build ) >&2
  node "$script" --measure-only
}

# ---------------------------------------------------------------------------
# Write one floor: `direction: up` takes floor(measured*100)-1 percentage points of
# margin (one uncovered defensive branch should not trip the gate; a genuinely
# untested feature should). `direction: down` (the bundle ceiling) takes
# ceil(measured*1.10) — 10% headroom, ratchets down over time as the adopter tightens it.
# ---------------------------------------------------------------------------
write_floor() {
  local key="$1" measured="$2" direction="$3" tool="$4"
  local current value
  current="$(floor_get "$key" 2>/dev/null || echo unset)"

  if [ "$direction" = "up" ]; then
    value="$(awk -v m="$measured" 'BEGIN{v=int(m*100)-1; if (v<0) v=0; printf "%.2f\n", v/100}')"
  else
    value="$(awk -v m="$measured" 'BEGIN{printf "%d\n", (m*1.10==int(m*1.10)) ? m*1.10 : int(m*1.10)+1}')"
  fi

  if [ "$current" != "unset" ]; then
    local lowered=0
    if [ "$direction" = "up" ]; then
      awk -v c="$current" -v v="$value" 'BEGIN{exit !(v+0 < c+0)}' && lowered=1
    else
      awk -v c="$current" -v v="$value" 'BEGIN{exit !(v+0 > c+0)}' && lowered=1
    fi
    if [ "$lowered" -eq 1 ] && [ -z "$REBASELINE_REASON" ]; then
      die "$key would move from $current to $value, which LOWERS the ratchet.
Refusing without --rebaseline \"<reason>\". The only two honest reasons: the
measuring instrument changed, or the scope got wider. Say which."
    fi
  fi

  python3 - "$FLOORS_FILE" "$key" "$value" "$direction" "$tool" "$measured" "$TODAY" "$REBASELINE_REASON" <<'PY'
import sys, re
path, key, value, direction, tool, measured, today, reason = sys.argv[1:9]
with open(path) as f:
    text = f.read()
block_re = re.compile(r'^( *)' + re.escape(key) + r':.*(\n(?:\1  .*\n)*)?', re.MULTILINE)
new_block = f"  {key}:\n    value: {value}\n    direction: {direction}\n    tool: {tool}\n    measured: {measured}\n    on: {today}\n"
if reason:
    new_block += f'    rebaselined: {{ on: {today}, reason: "{reason}" }}\n'
if block_re.search(text):
    text = block_re.sub(lambda m: new_block, text, count=1)
else:
    text += new_block
with open(path, "w") as f:
    f.write(text)
PY
  echo "wrote $key -> $value (measured $measured on $TODAY)"

  # Render IMMEDIATELY after every write, not only at the end of the whole run.
  # The next measurement's test suite may contain a ratchet guard comparing the
  # tool configs against floors.yml — and PIT and Stryker both refuse to run on
  # a red suite, so a write left unrendered turns every LATER mutation
  # measurement into a "suite not green" skip. Found on the first real
  # calibration ever run: coverage floors landed, the guards went red, and both
  # mutation floors silently stayed unset.
  if [ -x "$ROOT/tools/render-floors.sh" ]; then
    "$ROOT/tools/render-floors.sh" >/dev/null
  fi
}

echo "=== tools/measure-floors.sh — explicitly online, explicitly slow ==="
echo

any_measured=0
measure_and_write() {
  local key="$1" direction="$2" tool="$3" fn="$4"
  [ -n "$ONLY_KEY" ] && [ "$ONLY_KEY" != "$key" ] && return 0
  echo "--- $key ---"
  local out
  if out="$($fn)"; then
    write_floor "$key" "$out" "$direction" "$tool"
    any_measured=1
  else
    echo "$out"
  fi
}

measure_and_write backend.coverage.line   up   jacoco       measure_backend_line
measure_and_write backend.coverage.branch up   jacoco       measure_backend_branch
measure_and_write backend.mutation.score  up   pit          measure_backend_mutation

if [ -z "$ONLY_KEY" ] || [[ "$ONLY_KEY" == frontend.coverage.* ]]; then
  echo "--- frontend.coverage.* ---"
  if out="$(measure_frontend_vitest)"; then
    stmts="$(printf '%s' "$out" | awk '{print $1/100}')"
    branches="$(printf '%s' "$out" | awk '{print $2/100}')"
    functions="$(printf '%s' "$out" | awk '{print $3/100}')"
    lines="$(printf '%s' "$out" | awk '{print $4/100}')"
    write_floor frontend.coverage.statements "$stmts" up vitest
    write_floor frontend.coverage.branches "$branches" up vitest
    write_floor frontend.coverage.functions "$functions" up vitest
    write_floor frontend.coverage.lines "$lines" up vitest
    any_measured=1
  else
    echo "$out"
  fi
fi

measure_and_write frontend.mutation.score   up   stryker       measure_frontend_mutation
measure_and_write frontend.bundle.total_kib down bundle-check  measure_frontend_bundle

echo
if [ "$any_measured" -eq 1 ]; then
  if [ -x "$ROOT/tools/render-floors.sh" ]; then
    "$ROOT/tools/render-floors.sh"
  fi
  echo "Done. Commit floors.yml (and any rendered tool-config changes) — gate 9 now"
  echo "fails any pull request that lowers a floor written here."
else
  echo "Nothing measured — no reference-stack tool config was found in this tree."
  echo "This is expected on a template instantiation before backend/ or frontend/ exist."
fi
