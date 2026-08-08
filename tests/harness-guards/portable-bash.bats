#!/usr/bin/env bats
#
# Gate 22 guard — the shell in tools/ runs on bash 3.2.
#
# THE LESSON. `tools/spec-pipeline/validate.sh` carries a comment explaining that it uses a
# portable read loop "not `mapfile` — not a bash-4+ builtin, and this must run under
# whatever /usr/bin/env bash resolves to, including bash 3.2". That reasoning was written
# down once and then lived only in that one file, so the next script to need a
# line-to-array read reached for `mapfile` and nothing objected.
#
# It would not have failed in CI. CI is Linux with bash 5. It fails on a maintainer's
# macOS laptop, where /bin/bash is still 3.2 — which is exactly where an adoption
# interview, a floor calibration or an upstream-drift check gets run, and exactly the
# moment a "command not found" is most expensive.
#
# A convention that lives in one file's comment is a convention that has already been
# broken somewhere else.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

@test "no tools/ script uses a bash-4-only builtin" {
  # mapfile/readarray are the ones this repo has actually reached for. Comment lines are
  # excluded so the notes explaining WHY they are banned do not trip the check.
  hits="$(grep -rnE '^[^#]*\b(mapfile|readarray)\b' \
            "$REPO_ROOT/tools" --include='*.sh' || true)"
  if [ -n "$hits" ]; then
    echo "# bash-4-only builtins in tools/ (this repo targets bash 3.2 too):"
    echo "$hits" | sed 's/^/#   /'
    echo "# Use a portable read loop — see tools/spec-pipeline/validate.sh."
    false
  fi
}

@test "no tools/ script uses bash-4-only associative arrays" {
  hits="$(grep -rnE '^[^#]*declare[[:space:]]+-A\b' "$REPO_ROOT/tools" --include='*.sh' || true)"
  if [ -n "$hits" ]; then
    echo "# associative arrays (declare -A) are bash 4+:"
    echo "$hits" | sed 's/^/#   /'
    false
  fi
}

@test "the guard has teeth: a planted mapfile is caught" {
  # Without this, the two assertions above pass just as cleanly on an empty tools/ tree,
  # or if the grep were quietly mistyped.
  tmp="$(mktemp -d)/tools"
  mkdir -p "$tmp"
  printf '#!/usr/bin/env bash\nmapfile -t x < f\n' > "$tmp/planted.sh"
  run grep -rnE '^[^#]*\b(mapfile|readarray)\b' "$tmp" --include='*.sh'
  [ "$status" -eq 0 ]
  [[ "$output" == *"planted.sh"* ]]
  rm -rf "$(dirname "$tmp")"
}

@test "the portability reason is written down where it can be found" {
  # A rule without its reason gets deleted by the next person who finds it inconvenient.
  run grep -q 'bash 3.2' "$REPO_ROOT/tools/spec-pipeline/validate.sh"
  [ "$status" -eq 0 ]
}
