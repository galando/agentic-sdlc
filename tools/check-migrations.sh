#!/usr/bin/env bash
# tools/check-migrations.sh — Gate 10, the cheap file-level half of migration validation.
#
# Two migrations claiming the same Flyway version number is a merge artefact: two branches
# each add "the next" migration, both pick the same number, and Flyway only discovers the
# collision when it tries to apply them — which is also why the workflow's next step
# applies the whole chain to a clean database. This check runs FIRST because it is
# free, needs no database, and gives a precise answer ("these two files") instead of a
# generic apply failure.
#
# HARD REQUIREMENT, not a `[ -x ]`-guarded optional step: this script IS gate 10's
# duplicate-version check, called unconditionally by pr-validation.yml. Making it
# optional would let the exact silent-gap failure mode findings 1/2 in the same PR
# already produced recur here — a job that reports success while never having examined
# a single migration file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MIGRATION_DIR="$ROOT/examples/backend/src/main/resources/db/migration"

if [ ! -d "$MIGRATION_DIR" ]; then
  echo "check-migrations.sh: no $MIGRATION_DIR in this tree — nothing to check."
  exit 0
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Flyway's own naming convention: V<version>__<description>.sql, version made of
# digits with optional dot-separated parts (V1, V1_1 is NOT standard Flyway — dots,
# e.g. V1.1__x.sql, are). Anything not matching this shape is not a versioned
# migration this check has an opinion about (repeatable R__ migrations, for example,
# have no version to collide on).
while IFS= read -r f; do
  [ -z "$f" ] && continue
  base="$(basename "$f")"
  version="$(printf '%s' "$base" | sed -nE 's/^V([0-9]+(\.[0-9]+)*)__.*\.[Ss][Qq][Ll]$/\1/p')"
  [ -n "$version" ] || continue
  printf '%s\t%s\n' "$version" "$base" >> "$TMP"
done < <(find "$MIGRATION_DIR" -maxdepth 1 -type f | sort)

dupes=0
while IFS= read -r version; do
  [ -z "$version" ] && continue
  files="$(awk -F'\t' -v v="$version" '$1==v{print $2}' "$TMP" | tr '\n' ' ')"
  echo "::error::Duplicate Flyway migration version '$version': $files claim the same version number."
  dupes=$((dupes + 1))
done < <(cut -f1 "$TMP" 2>/dev/null | sort | uniq -d)

if [ "$dupes" -gt 0 ]; then
  echo "check-migrations.sh: $dupes duplicate migration version(s) found in $MIGRATION_DIR." >&2
  exit 1
fi

echo "check-migrations.sh: clean — no duplicate migration versions in $MIGRATION_DIR."
exit 0
