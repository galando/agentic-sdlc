#!/usr/bin/env bash
# tools/gen-adopting.sh — regenerate the placeholder-map table inside ADOPTING.md
# (design.md section 4.4, tasks.md Task 26).
#
# Mechanically scans the tracked tree for every distinct double-brace placeholder occurrence, finds its
# one-line "what goes there" annotation, works out how it gets resolved by checking
# tools/init.sh's OWN source (never a second hand-maintained list — a second list of
# which tokens init.sh handles is exactly the kind of thing that drifts the moment
# somebody adds a token to one and forgets the other), and rewrites the table between
# <!-- PLACEHOLDERS:BEGIN --> and <!-- PLACEHOLDERS:END --> in ADOPTING.md. Prose outside
# the markers is hand-written and preserved.
#
# `fast-repo-hygiene` runs this and then `git diff --exit-code ADOPTING.md` — a
# placeholder without a row cannot be merged (design.md D9). See tools/check-placeholders.sh
# for the SEPARATE, narrower question of "did an adopter forget to fill one in"; this
# script answers "does every token that exists anywhere have a row explaining it",
# regardless of whether it is auto-resolved.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ADOPTING="$ROOT/ADOPTING.md"
INIT_SH="$ROOT/tools/init.sh"

die() { echo "gen-adopting.sh: $*" >&2; exit 1; }

[ -f "$ADOPTING" ] || die "$ADOPTING not found — write its hand-authored prose (with the markers) first."
[ -f "$INIT_SH" ] || die "$INIT_SH not found."

cd "$ROOT"

# ---------------------------------------------------------------------------
# Scope: every tracked file EXCEPT test fixtures (placeholder-shaped strings used as
# literal test data, never a real token — tests/) and the build record (the worked
# spec-directory example, deliberately preserved or already-resolved prose, not a live
# token for THIS adopter — .temper/specs/). ADOPTING.md itself is excluded so a stale
# row from a previous generation cannot feed the next one.
# ---------------------------------------------------------------------------
scan_files() {
  git ls-files \
    | grep -v '^tests/' \
    | grep -v '^\.temper/specs/' \
    | grep -v '^ADOPTING\.md$'
}

# ---------------------------------------------------------------------------
# Pass 1: collect every distinct token and the files it appears in.
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

: > "$TMP/occurrences.tsv"   # token \t file
while IFS= read -r f; do
  [ -f "$f" ] || continue
  matches="$(grep -noE '\{\{[A-Z][A-Z0-9_]*\}\}' "$f" 2>/dev/null || true)"
  [ -z "$matches" ] && continue
  while IFS=: read -r _line tok; do
    tok="${tok#\{\{}"
    tok="${tok%\}\}}"
    printf '%s\t%s\n' "$tok" "$f" >> "$TMP/occurrences.tsv"
  done <<<"$matches"
done < <(scan_files)

[ -s "$TMP/occurrences.tsv" ] || die "found zero placeholder tokens in scope — is the scan broken?"

TOKENS="$(cut -f1 "$TMP/occurrences.tsv" | sort -u)"

# ---------------------------------------------------------------------------
# find_annotation <token> — the first "placeholder: ..." note attached to the token,
# on the same line, searched across the same file set in a stable (sorted) order.
# Two comment styles: "# placeholder: ..." (shell/YAML) and
# "<!-- placeholder: TOKENNAME ... -->" (Markdown/YAML-comment).
# ---------------------------------------------------------------------------
find_annotation() {
  local tok="$1" f line note
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    line="$(grep -m1 -E "\{\{${tok}\}\}.*placeholder:|placeholder:.*\{\{${tok}\}\}" "$f" 2>/dev/null || true)"
    [ -z "$line" ] && continue
    note="${line#*placeholder:}"
    note="$(printf '%s' "$note" | sed -E 's/-->\s*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    # Drop a leading "TOKENNAME — " (double-brace form) if the annotation restates the token.
    note="$(printf '%s' "$note" | sed -E "s/^\{\{${tok}\}\}[[:space:]]*[—-][[:space:]]*//")"
    [ -n "$note" ] && { printf '%s' "$note"; return 0; }
  done < <(scan_files | sort)
  printf 'no annotation found — add "# placeholder: ..." at its point of use'
}

# ---------------------------------------------------------------------------
# resolved_by <token> — derived from tools/init.sh's OWN source, not a second list here.
# ---------------------------------------------------------------------------
resolved_by() {
  local tok="$1"
  if grep -qE "^\s*(PRODUCT_NAME|PROVIDER|MODEL_JUDGE|MODEL_EXECUTE|MODEL_CHALLENGE|CHALLENGE_BASE_URL|ALERT_CHANNEL|RUNNER_LABEL|LEDGER_COMMIT_NAME|LEDGER_COMMIT_EMAIL|BUILD_PIPELINE)\s+" "$INIT_SH" 2>/dev/null \
     && grep -q "declare -a TOKENS=" "$INIT_SH" && grep -qE "\\b${tok}\\b" <(sed -n '/declare -a TOKENS=/,/)/p' "$INIT_SH"); then
    printf 'tools/init.sh (interview)'
    return 0
  fi
  if grep -q "resolve_derived ${tok} " "$INIT_SH" 2>/dev/null; then
    printf 'tools/init.sh (derived automatically — see design.md P2)'
    return 0
  fi
  case "$tok" in
    SLUG|DATE)
      printf 'tools/spec-pipeline/new-spec.sh (per new spec directory, not by init.sh)' ;;
    FLOOR_LINE|FLOOR_BRANCH|FLOOR_MUTATION|CEILING_BUNDLE_KIB)
      printf 'tools/measure-floors.sh, via floors.yml (never a live substitution — see docs/QUALITY-GATES.md)' ;;
    UPSTREAM_PROVIDER)
      printf 'manual — write tools/live-api-contract.sh; the comment names what belongs there (gate 18 is a contract, not an implementation)' ;;
    HEALTH_SIGNAL|HEALTH_SIGNAL_DISK)
      printf 'manual — documented example syntax only; real slots are .agents/health-signals.yml (P3, design.md section 4.3)' ;;
    PLACEHOLDER|UPPER_SNAKE_CASE|UNRESOLVED_TOKEN|THIS)
      printf 'n/a — documents the {{...}} syntax itself, not a real token' ;;
    TARGET_REPO)
      printf 'n/a — appears only in build-record prose (an example command), not a live token' ;;
    *)
      printf 'manual — no automatic resolver; fill in by hand' ;;
  esac
}

# ---------------------------------------------------------------------------
# Emit the table.
# ---------------------------------------------------------------------------
TABLE="$TMP/table.md"
{
  echo "| Token | Files | What goes there | Resolved by |"
  echo "|---|---|---|---|"
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    files="$(awk -F'\t' -v t="$tok" '$1==t{print $2}' "$TMP/occurrences.tsv" | sort -u | paste -sd, - | sed 's/,/, /g')"
    note="$(find_annotation "$tok")"
    resolver="$(resolved_by "$tok")"
    # Escape pipe characters so a note never breaks the Markdown table.
    note="$(printf '%s' "$note" | sed 's/|/\\|/g')"
    printf '| `{{%s}}` | %s | %s | %s |\n' "$tok" "$files" "$note" "$resolver"
  done <<<"$TOKENS"
} > "$TABLE"

fail=0
if grep -q 'no annotation found' "$TABLE"; then
  echo "gen-adopting.sh: FAILED — one or more tokens have no annotation:" >&2
  grep 'no annotation found' "$TABLE" >&2
  fail=1
fi

[ "$fail" -eq 0 ] || die "add a \"# placeholder: ...\" (or Markdown \"<!-- placeholder: ... -->\") annotation at the token's point of use and re-run."

# ---------------------------------------------------------------------------
# Splice the table between the markers, preserving hand-written prose outside them.
# ---------------------------------------------------------------------------
BEGIN_MARK='<!-- PLACEHOLDERS:BEGIN -->'
END_MARK='<!-- PLACEHOLDERS:END -->'
grep -qF "$BEGIN_MARK" "$ADOPTING" || die "$ADOPTING has no $BEGIN_MARK marker."
grep -qF "$END_MARK" "$ADOPTING" || die "$ADOPTING has no $END_MARK marker."

awk -v begin="$BEGIN_MARK" -v end="$END_MARK" -v tablefile="$TABLE" '
  $0 == begin { print; inblock = 1; while ((getline line < tablefile) > 0) print line; next }
  $0 == end   { inblock = 0; print; next }
  inblock { next }
  { print }
' "$ADOPTING" > "$TMP/ADOPTING.md.new"

mv "$TMP/ADOPTING.md.new" "$ADOPTING"
echo "gen-adopting.sh: wrote $(printf '%s\n' "$TOKENS" | wc -l | tr -d ' ') token row(s) into $ADOPTING."
