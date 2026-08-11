#!/usr/bin/env bats
#
# Guard: the harness must run on a maintainer's macOS laptop, not only on CI's Linux.
#
# WHY THIS FILE EXISTS.
#
# `sed -i 's/x/y/' file` is not portable. GNU sed edits in place; BSD sed — which is what
# macOS ships — reads the NEXT argument as the backup suffix, swallows the script, and dies
# with "sed: 1: ...: invalid command code". The failure names a line in a test file rather
# than a platform, so it reads as "you broke something" instead of "this never worked here".
#
# This has now cost three separate rebuilds. `docs/maintainers/demo-recreation.md` carried
# it as a known snag, the fix landed in whichever file was noticed at the time, and the next
# bare `sed -i` arrived unremarked because prose in a runbook cannot fail a build. So it is
# a test.
#
# Two portable forms, and BOTH are accepted here: `sed -i.bak ... && rm -f ....bak`, which
# is what the rest of this suite uses, and `sed -i '' ...`, which is BSD-only and therefore
# rarer. Removing the backup matters as much as creating it: several fixtures are git
# repositories and the tools under test branch on whether the working tree is clean, so a
# stray .bak silently flips that branch.
#
# Scope note: this checks the SHIPPED harness (tools/ and tests/), not examples/. The
# example product is built by CI on Linux and by the adopter's own toolchain; its
# portability is the adopter's call, not a property of the template.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# The one implementation of the rule. Both the guard and its teeth test call this, so a
# regex that cannot catch the thing cannot pass as a clean sweep — which is exactly how the
# first draft of this file went wrong.
#
#   1. `sed -i` followed by WHITESPACE. `sed -i.bak` has a `.` there and never matches.
#   2. minus the explicit-empty-suffix form, `sed -i ''` / `sed -i ""`, which is portable.
#   3. minus comment lines — prose ABOUT this pitfall is how the rule stays explained,
#      matched precisely against the `path:line:` prefix rather than anywhere in the line.
#
# `-H` is not optional: grep omits the filename prefix when handed a single file, and the
# comment filter below anchors on `path:line:`. Without it the filter silently stops
# matching for exactly the one-file case the teeth tests use.
bare_sed_i() {
  grep -rHnE "(^|[^[:alnum:]_.-])sed -i[[:space:]]" "$@" 2>/dev/null \
    | grep -vE "sed -i[[:space:]]+(''|\"\")" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    || true
}

@test "no bare 'sed -i' in the harness — BSD sed needs an explicit suffix" {
  local hits
  hits="$(bare_sed_i "$REPO_ROOT/tools" "$REPO_ROOT/tests")"

  if [ -n "$hits" ]; then
    echo "# Bare 'sed -i' is a syntax error on macOS."
    echo "# Use: sed -i.bak 's/x/y/' file && rm -f file.bak"
    echo "$hits" | sed 's/^/#   /'
    false
  fi
}

@test "the guard has teeth: a planted bare 'sed -i' is caught" {
  # A guard nobody has watched fail is a guard nobody knows the shape of. The first
  # version of this file passed the check above while being incapable of matching
  # anything, and this test is what said so.
  # The offending string is assembled through %s rather than written literally: spelled
  # out, this line would be a bare `sed -i` in a non-comment line of a file the guard
  # scans, and the guard would correctly report itself.
  local planted="$BATS_TEST_TMPDIR/planted.sh"
  printf '#!/usr/bin/env bash\n%s -i %ss/a/b/%s file\n' sed "'" "'" > "$planted"

  [ -n "$(bare_sed_i "$planted")" ]
}

@test "the guard does not fire on either portable form" {
  # A guard that also condemns the fix teaches people to delete the guard.
  local ok="$BATS_TEST_TMPDIR/ok.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'sed -i.bak %ss/a/b/%s file && rm -f file.bak\n' "'" "'"
    printf "sed -i '' 's/a/b/' file\n"
    # Assembled through %s for the same reason as the planted case above.
    printf '# %s -i is a syntax error on macOS -- this comment must not fire it\n' sed
  } > "$ok"

  [ -z "$(bare_sed_i "$ok")" ]
}

@test "the portable form the guard recommends is genuinely in use" {
  # If the suggested replacement appeared nowhere, the message above would be advice
  # nobody had tried. It is the idiom the rest of the suite already runs on.
  run grep -rl "sed -i\.bak" "$REPO_ROOT/tests"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "no GNU-only tool flags in the scripts an adopter runs before CI" {
  # tools/ runs on the adopter's own machine during adoption, BEFORE anything reaches a
  # Linux runner. A GNU-coreutils-only flag there fails at exactly the moment the adopter
  # has nothing to compare against and no reason to suspect the template.
  local hits
  hits="$(grep -rnE "grep -P|readlink -f|(^|[[:space:]])sed -r([[:space:]]|$)|stat -c|date -d[[:space:]]|find[^|]* -printf" \
            "$REPO_ROOT/tools" 2>/dev/null \
          | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"

  if [ -n "$hits" ]; then
    echo "# GNU-only flag in tools/ — these fail on a stock macOS toolchain:"
    echo "$hits" | sed 's/^/#   /'
    false
  fi
}
