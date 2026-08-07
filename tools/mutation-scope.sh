#!/usr/bin/env bash
# tools/mutation-scope.sh <base-ref> — Gate 17: which production classes, under
# examples/backend/src/main/java, does the diff against <base-ref> actually touch?
#
# Prints one fully-qualified class name per changed/added production .java file,
# comma-separated, on stdout — the shape PIT's targetClasses parameter accepts. Prints
# NOTHING (empty stdout) when the diff touches no mutatable production class — a
# docs-only, test-only, frontend-only or resource-only pull request — which the caller
# (pr-mutation.yml) reads as "nothing to mutate" and skips the expensive run.
#
# HARD REQUIREMENT, not a `[ -x ]`-guarded optional step: this script's output IS what
# gate 17 mutates. A missing or silently-empty scope computation does not fail loudly —
# it reports a green mutation check over an empty set, which is indistinguishable from
# passing. See tools/test-mutation-scope.sh, which exercises exactly that failure mode
# before this script is ever trusted on a real diff.
#
# Operates on the CURRENT working directory's git repository. The caller always runs
# this from the repository root (no `working-directory:` override in pr-mutation.yml
# for this step), and tools/test-mutation-scope.sh relies on that same contract to
# point it at a throwaway scratch repository instead of this one.
set -euo pipefail

BASE_REF="${1:-}"
[ -n "$BASE_REF" ] || { echo "mutation-scope.sh: usage: mutation-scope.sh <base-ref>" >&2; exit 2; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "mutation-scope.sh: not inside a git working tree" >&2
  exit 2
}

SRC_PREFIX="examples/backend/src/main/java/"

# Triple-dot: the diff between HEAD and the point where it diverged from BASE_REF —
# exactly a pull request's own changes, not everything BASE_REF has gained since the
# branch point. --diff-filter=ACMR: added, copied, modified or renamed files only — a
# deleted class has nothing left to mutate.
# The base ref must resolve BEFORE the diff runs. Swallowing a git failure here
# (`2>/dev/null || true`) turned "unknown or unfetched base ref" into an empty
# scope, which the caller reads as "nothing to mutate" — the silent narrowing the
# header above says must fail loudly.
git rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null || {
  echo "mutation-scope.sh: base ref '${BASE_REF}' does not resolve to a commit (unfetched shallow clone?) — refusing to report an empty scope" >&2
  exit 1
}
files="$(git diff --name-only --diff-filter=ACMR "${BASE_REF}...HEAD" -- "$SRC_PREFIX")"

scope=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *.java) ;;
    *) continue ;;
  esac
  base="$(basename "$f")"
  case "$base" in
    package-info.java|module-info.java) continue ;;
  esac
  rel="${f#"$SRC_PREFIX"}"
  cls="${rel%.java}"
  cls="${cls//\//.}"
  if [ -z "$scope" ]; then
    scope="$cls"
  else
    scope="$scope,$cls"
  fi
done < <(printf '%s\n' "$files")

printf '%s\n' "$scope"
