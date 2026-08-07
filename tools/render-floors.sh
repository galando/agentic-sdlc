#!/usr/bin/env bash
# tools/render-floors.sh — rewrite each tool config's FLOORS:BEGIN...END block from
# floors.yml (design.md section 7.2). Idempotent and unit-agnostic per tool: a ratio for
# JaCoCo, an integer percentage for PIT/vitest/Stryker, KiB for the bundle ceiling.
#
# Called by tools/measure-floors.sh after a measurement, and by `fast-repo-hygiene`
# (`tools/render-floors.sh && git diff --exit-code`) to catch a hand-edited tool config
# that drifted from floors.yml — see design.md section 7.5.
#
# The BEGIN/END marker LINES themselves are never touched — only the text between them.
# That is what makes this idempotent and safe to re-run: the marker carries the floor
# key(s) it renders, a fresh run finds the same markers, and writes back exactly the same
# content when floors.yml has not changed.
#
# The bundle ceiling (examples/frontend/scripts/check-bundle.mjs) has NO marked block: it is our
# own script, so it reads floors.yml directly at run time instead — see design.md
# section 7.2 point 5. Nothing to render there.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/config.sh
. "$ROOT/tools/lib/config.sh"

# ---------------------------------------------------------------------------
# to_percent <ratio-or-unset> — floors.yml stores coverage/mutation floors as a 0..1
# ratio (e.g. 0.87); PIT, vitest and Stryker all want an integer percentage. JaCoCo wants
# the ratio as-is. "unset" passes through unchanged — callers check for it explicitly.
# ---------------------------------------------------------------------------
to_percent() {
  local ratio="$1"
  [ "$ratio" = "unset" ] && { echo "unset"; return 0; }
  awk -v r="$ratio" 'BEGIN{printf "%d", (r*100)+0.5}'
}

# ---------------------------------------------------------------------------
# resolve_target <adopter-path> <template-path> — the first that exists, on stdout.
# The template ships its marked blocks under examples/; an adopter's product lives at
# backend/ and frontend/ at the repo root (the layout tools/measure-floors.sh names).
# Probing both keeps one script correct in both trees; exit 1 means neither exists
# and the caller skips with its own message.
# ---------------------------------------------------------------------------
resolve_target() {
  local p
  for p in "$1" "$2"; do
    [ -f "$ROOT/$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

# ---------------------------------------------------------------------------
# render_block <file> <key...> <new-content-file>
#   Rewrites the text strictly between the FLOORS:BEGIN <key...> line and the next
#   FLOORS:END line, leaving both marker lines and everything else in the file
#   untouched. <new-content-file> holds the replacement lines, WITHOUT the marker lines
#   themselves and without a trailing blank line.
# ---------------------------------------------------------------------------
render_block() {
  local file="$1" keys="$2" content_file="$3"
  python3 - "$file" "$keys" "$content_file" <<'PY'
import re, sys

path, keys, content_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    text = f.read()
with open(content_path) as f:
    new_content = f.read().rstrip("\n")

# The BEGIN marker line names its key(s) after "FLOORS:BEGIN " — match that exact line
# (any comment style: "<!--", "//", or bare), then everything up to (not including) the
# next line that contains "FLOORS:END".
begin_pat = re.compile(
    # The BEGIN-line group is deliberately bounded to a SINGLE line ([^\n]* rather than
    # DOTALL's ".*"): with re.DOTALL, a trailing ".*\n" is greedy across newlines too,
    # so it does not stop at ITS OWN end-of-line — it swallows forward past the intended
    # FLOORS:END and locks onto whichever END marker is furthest away in the file (regex
    # backtracking prefers the longest match first). Found by running this against a
    # file with two marked blocks, where block 1's render silently absorbed block 2's
    # content instead of stopping at block 1's own END line.
    r'^([ \t]*\S*\s*FLOORS:BEGIN[ \t]+' + re.escape(keys) + r'[^\n]*\n)'
    r'(.*?\n)'
    r'([ \t]*\S*\s*FLOORS:END[^\n]*\n?)',
    re.MULTILINE | re.DOTALL,
)

m = begin_pat.search(text)
if not m:
    print(f"render-floors: no FLOORS:BEGIN {keys!r} block found in {path}", file=sys.stderr)
    sys.exit(1)

indent = re.match(r'^([ \t]*)', m.group(2)).group(1) if m.group(2).strip() else re.match(r'^([ \t]*)', m.group(1)).group(1)
rendered = "\n".join(indent + line if line else "" for line in new_content.split("\n")) + "\n"

new_text = text[:m.start()] + m.group(1) + rendered + m.group(3) + text[m.end():]
if new_text != text:
    with open(path, "w") as f:
        f.write(new_text)
    print(f"render-floors: rewrote {keys!r} block in {path}")
else:
    print(f"render-floors: {keys!r} block in {path} already up to date")
PY
}

# ---------------------------------------------------------------------------
# Backend — JaCoCo coverage ratchet (examples/backend/pom.xml).
# ---------------------------------------------------------------------------
render_backend_jacoco() {
  local target
  target="$(resolve_target backend/pom.xml examples/backend/pom.xml)" || { echo "render-floors: skipped backend coverage ratchet — no backend/pom.xml (or examples/backend/pom.xml) in this tree yet"; return 0; }

  local line branch tmp
  line="$(floor_get backend.coverage.line 2>/dev/null || echo unset)"
  branch="$(floor_get backend.coverage.branch 2>/dev/null || echo unset)"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN

  if [ "$line" = "unset" ] || [ "$branch" = "unset" ]; then
    cat > "$tmp" <<'EOF'
<!-- floors.yml says `unset`. jacoco:check has no "no threshold" mode — a
     <minimum> must be a decimal — so the check execution itself is
     skipped and tools/floor-notice.sh prints the uncalibrated notice
     instead. This <skip> is indistinguishable from a permanently
     disabled gate BY DESIGN OF THE TOOL; floors.yml is what tells the
     two states apart, and gate 9 reads it, not this file.
     <rules> stays present-but-empty even while skipped: the plugin
     validates it as a required parameter BEFORE consulting <skip>, so an
     absent <rules> block fails the build regardless of skip's value. -->
<skip>true</skip>
<rules/>
EOF
  else
    cat > "$tmp" <<EOF
<!-- Calibrated by tools/measure-floors.sh — measured value, tool and date live in
     floors.yml, deliberately NOT repeated here: rendering must be a pure function
     of floors.yml, and an embedded date made every re-render on a later day a
     spurious diff for the fast-repo-hygiene drift gate. Ratchets UP only —
     see docs/QUALITY-GATES.md; never hand-lower these values. -->
<skip>false</skip>
<rules>
  <rule>
    <element>BUNDLE</element>
    <limits>
      <limit>
        <counter>LINE</counter>
        <value>COVEREDRATIO</value>
        <minimum>${line}</minimum>
      </limit>
      <limit>
        <counter>BRANCH</counter>
        <value>COVEREDRATIO</value>
        <minimum>${branch}</minimum>
      </limit>
    </limits>
  </rule>
</rules>
EOF
  fi
  render_block "$ROOT/$target" "backend.coverage.line backend.coverage.branch" "$tmp"
}

# ---------------------------------------------------------------------------
# Backend — PIT mutation threshold (examples/backend/pom.xml property).
# ---------------------------------------------------------------------------
render_backend_pit() {
  local target
  target="$(resolve_target backend/pom.xml examples/backend/pom.xml)" || { echo "render-floors: skipped backend mutation threshold — no backend/pom.xml (or examples/backend/pom.xml) in this tree yet"; return 0; }

  local score pct tmp
  score="$(floor_get backend.mutation.score 2>/dev/null || echo unset)"
  pct="$(to_percent "$score")"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN

  if [ "$pct" = "unset" ]; then
    cat > "$tmp" <<'EOF'
<!-- floors.yml says `unset`. PIT's documented "no threshold" IS 0 — which is also
     exactly what a switched-off gate looks like. That collision is the reason the
     sentinel cannot live in this file. -->
<pit.mutationThreshold>0</pit.mutationThreshold>
EOF
  else
    cat > "$tmp" <<EOF
<!-- Calibrated by tools/measure-floors.sh (provenance lives in floors.yml). Ratchets UP only. -->
<pit.mutationThreshold>${pct}</pit.mutationThreshold>
EOF
  fi
  render_block "$ROOT/$target" "backend.mutation.score" "$tmp"
}

# ---------------------------------------------------------------------------
# Frontend — vitest coverage thresholds (examples/frontend/vitest.config.js).
# ---------------------------------------------------------------------------
render_frontend_vitest() {
  local target
  target="$(resolve_target frontend/vitest.config.js examples/frontend/vitest.config.js)" || { echo "render-floors: skipped frontend coverage thresholds — no frontend/vitest.config.js (or examples/frontend/vitest.config.js) in this tree yet"; return 0; }

  local stmts branches funcs lines tmp
  stmts="$(to_percent "$(floor_get frontend.coverage.statements 2>/dev/null || echo unset)")"
  branches="$(to_percent "$(floor_get frontend.coverage.branches 2>/dev/null || echo unset)")"
  funcs="$(to_percent "$(floor_get frontend.coverage.functions 2>/dev/null || echo unset)")"
  lines="$(to_percent "$(floor_get frontend.coverage.lines 2>/dev/null || echo unset)")"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN

  if [ "$stmts" = "unset" ] || [ "$branches" = "unset" ] || [ "$funcs" = "unset" ] || [ "$lines" = "unset" ]; then
    cat > "$tmp" <<'EOF'
// floors.yml says `unset` — no thresholds enforced yet. An empty object is
// vitest's own "measure but do not gate"; run tools/measure-floors.sh to arm it.
thresholds: {},
EOF
  else
    cat > "$tmp" <<EOF
// Calibrated by tools/measure-floors.sh (provenance lives in floors.yml). Ratchets UP only.
thresholds: { statements: ${stmts}, branches: ${branches}, functions: ${funcs}, lines: ${lines} },
EOF
  fi
  render_block "$ROOT/$target" "frontend.coverage.*" "$tmp"
}

# ---------------------------------------------------------------------------
# Frontend — Stryker mutation threshold (examples/frontend/stryker.config.mjs).
# ---------------------------------------------------------------------------
render_frontend_stryker() {
  local target
  target="$(resolve_target frontend/stryker.config.mjs examples/frontend/stryker.config.mjs)" || { echo "render-floors: skipped frontend mutation threshold — no frontend/stryker.config.mjs (or examples/frontend/stryker.config.mjs) in this tree yet"; return 0; }

  local score pct tmp
  score="$(floor_get frontend.mutation.score 2>/dev/null || echo unset)"
  pct="$(to_percent "$score")"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN

  if [ "$pct" = "unset" ]; then
    cat > "$tmp" <<'EOF'
// `break: null` is Stryker's documented "do not fail the build". floors.yml says
// `unset`; when calibrated this becomes an integer and only ever moves up.
thresholds: { high: 95, low: 85, break: null },
EOF
  else
    cat > "$tmp" <<EOF
// Calibrated by tools/measure-floors.sh (provenance lives in floors.yml). Ratchets UP only.
thresholds: { high: 95, low: 85, break: ${pct} },
EOF
  fi
  render_block "$ROOT/$target" "frontend.mutation.score" "$tmp"
}

render_backend_jacoco
render_backend_pit
render_frontend_vitest
render_frontend_stryker

echo "render-floors: done."
