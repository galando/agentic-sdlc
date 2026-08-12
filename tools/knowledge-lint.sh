#!/usr/bin/env bash
# tools/knowledge-lint.sh — Gate: the second brain stays small, complete and honest.
#
# Checks docs/knowledge/ (the card contract in docs/knowledge/README.md):
#   1. INDEX.md is at most 80 lines — the forcing function that keeps the second brain
#      from growing silently: fold before you add, or this fails.
#   2. Every `rule`/`trap` card has exactly one INDEX.md entry, and every INDEX.md entry
#      names exactly one card — a 1:1 relationship in both directions, so a card written
#      without an index line (unreachable by the read path) and an index line whose card
#      was deleted (a dangling promise) both fail loudly instead of drifting apart.
#   3. `project` cards never appear in the index — they are grep-only by design.
#   4. Every card's frontmatter carries all of: name, topic, type, description, symptoms,
#      verified. `topic` must equal the filename. `type` must be rule|trap|project.
#      `verified` must be a YYYY-MM-DD string (same regex ledger.sh uses for `date` —
#      one convention, not two).
#   5. Every card body (everything after the closing `---`) is at most 60 lines.
#
# Exit 0 and silent on a clean tree; each violation is one `::error::` line naming the
# file, so CI's annotation view is the first place a contributor looks, not a scroll
# through raw script output.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KNOWLEDGE_DIR="$ROOT/docs/knowledge"
INDEX="$KNOWLEDGE_DIR/INDEX.md"

if [ ! -d "$KNOWLEDGE_DIR" ]; then
  echo "knowledge-lint.sh: no $KNOWLEDGE_DIR in this tree — nothing to check."
  exit 0
fi

if [ ! -f "$INDEX" ]; then
  echo "::error::knowledge-lint.sh: $INDEX is missing — every card directory ships with an index, even an empty one."
  exit 1
fi

errors=0
err() {
  echo "::error::knowledge-lint.sh: $1"
  errors=$((errors + 1))
}

# --- 1. INDEX.md line cap -----------------------------------------------------------
index_lines="$(wc -l < "$INDEX" | tr -d ' ')"
if [ "$index_lines" -gt 80 ]; then
  err "docs/knowledge/INDEX.md is $index_lines lines, over the 80-line cap — fold or retire a card before adding another."
fi

# --- slugs the index actually names, one per line, in order -------------------------
# An index entry's first line is `<slug> — <description>.` at column 0. Continuation
# ("  Symptoms: ...") is indented and skipped here.
index_slugs_file="$(mktemp)"
card_slugs_file="$(mktemp)"
trap 'rm -f "$index_slugs_file" "$card_slugs_file"' EXIT
grep -E '^[a-z0-9][a-z0-9-]* — ' "$INDEX" | sed -E 's/^([a-z0-9][a-z0-9-]*) —.*/\1/' > "$index_slugs_file" || true

dup_slugs="$(sort "$index_slugs_file" | uniq -d)"
if [ -n "$dup_slugs" ]; then
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    err "docs/knowledge/INDEX.md lists '$s' more than once."
  done <<<"$dup_slugs"
fi

# --- 2-4. per-card checks -------------------------------------------------------------

while IFS= read -r card; do
  [ -z "$card" ] && continue
  base="$(basename "$card")"
  slug="${base%.md}"

  case "$base" in
    README.md|INDEX.md) continue ;;
  esac

  if [ "$(sed -n '1p' "$card")" != "---" ]; then
    err "$base has no YAML frontmatter (must open with '---' on line 1)."
    continue
  fi
  fm_end="$(awk 'NR>1 && /^---$/ {print NR; exit}' "$card")"
  if [ -z "$fm_end" ]; then
    err "$base's frontmatter is never closed with a second '---' line."
    continue
  fi

  fm="$(sed -n "2,$((fm_end - 1))p" "$card")"

  # `|| true` on the grep stage: under `set -o pipefail`, an absent field (grep finds
  # nothing, exit 1) would otherwise make this whole command substitution fail, and
  # `val="$(get_field "$f")"` below is a plain assignment — `set -e` kills the script
  # right there, before the "missing field" error is ever printed. An absent field is
  # data this script reports on, not a script-ending error.
  get_field() {
    printf '%s\n' "$fm" | { grep -E "^$1:" || true; } | head -1 | sed -E "s/^$1:[[:space:]]*//"
  }

  topic="$(get_field topic)"
  type="$(get_field type)"
  verified="$(get_field verified)"

  for f in name topic type description symptoms verified; do
    val="$(get_field "$f")"
    [ -n "$val" ] || err "$base is missing required frontmatter field '$f'."
  done

  if [ -n "$topic" ] && [ "$topic" != "$slug" ]; then
    err "$base's frontmatter topic ('$topic') does not match its filename ('$slug')."
  fi

  case "$type" in
    rule|trap|project|"") ;;
    *) err "$base's type ('$type') is not one of rule, trap, project." ;;
  esac

  if [ -n "$verified" ] && ! [[ "$verified" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    err "$base's verified field ('$verified') is not a YYYY-MM-DD date."
  fi

  body_lines="$(( $(wc -l < "$card" | tr -d ' ') - fm_end ))"
  if [ "$body_lines" -gt 60 ]; then
    err "$base's body is $body_lines lines, over the 60-line cap."
  fi

  if [ "$type" = "rule" ] || [ "$type" = "trap" ]; then
    printf '%s\n' "$slug" >> "$card_slugs_file"
    if ! grep -qxF "$slug" "$index_slugs_file"; then
      err "$base ($type) has no entry in docs/knowledge/INDEX.md."
    fi
  elif [ "$type" = "project" ]; then
    if grep -qxF "$slug" "$index_slugs_file"; then
      err "$base is type 'project' but appears in docs/knowledge/INDEX.md — project cards are grep-only and must not be indexed."
    fi
  fi
done < <(find "$KNOWLEDGE_DIR" -maxdepth 1 -type f -name '*.md' | sort)

# --- the reverse direction: an index line naming a card that does not exist ---------
while IFS= read -r slug; do
  [ -z "$slug" ] && continue
  grep -qxF "$slug" "$card_slugs_file" 2>/dev/null || \
    err "docs/knowledge/INDEX.md lists '$slug', which has no matching card file (docs/knowledge/$slug.md)."
done < "$index_slugs_file"

if [ "$errors" -gt 0 ]; then
  echo "knowledge-lint.sh: $errors problem(s) found in docs/knowledge/." >&2
  exit 1
fi

echo "knowledge-lint.sh: clean — index and cards agree, every card is within its caps."
exit 0
