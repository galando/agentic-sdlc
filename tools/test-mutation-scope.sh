#!/usr/bin/env bash
# tools/test-mutation-scope.sh — gate 17's own self-test, run on EVERY pull request
# BEFORE the mutation-scope output is trusted (the "Test the scope computation" step in
# pr-mutation.yml, and the `mutation-scope-script-is-self-tested` lesson: a silently
# broken scope computation narrows the gate to nothing and reports a green mutation
# check over an empty set — indistinguishable from passing).
#
# Builds a throwaway git repository with a known base/head pair — never touches this
# repository's own history — and checks that tools/mutation-scope.sh reports exactly
# the production classes that pair changed: never more, never fewer, and never
# silently empty on a real change.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCOPE_SCRIPT="$ROOT/tools/mutation-scope.sh"

[ -x "$SCOPE_SCRIPT" ] || {
  echo "test-mutation-scope.sh: $SCOPE_SCRIPT is missing or not executable" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
git init -q -b main .
git config user.email "test-mutation-scope@example.invalid"
git config user.name "test-mutation-scope"

mkdir -p examples/backend/src/main/java/com/example/agentsdlc/service
mkdir -p examples/backend/src/main/java/com/example/agentsdlc/web
mkdir -p examples/backend/src/main/resources
echo "class Untouched {}" > examples/backend/src/main/java/com/example/agentsdlc/service/Untouched.java
echo "resource" > examples/backend/src/main/resources/application.yml
git add -A
git commit -q -m base

fail=0

check_present() {
  case ",$2," in
    *",$1,"*) ;;
    *) echo "FAIL: expected '$1' in scope, got: '$2'" >&2; fail=1 ;;
  esac
}
check_absent() {
  case ",$2," in
    *",$1,"*) echo "FAIL: did not expect '$1' in scope, got: '$2'" >&2; fail=1 ;;
    *) ;;
  esac
}

# --- Case 1: two changed production classes, one untouched file left alone ---------
git checkout -q -b feature-classes
echo "class ItemService { }" > examples/backend/src/main/java/com/example/agentsdlc/service/ItemService.java
echo "class ItemController { }" > examples/backend/src/main/java/com/example/agentsdlc/web/ItemController.java
git add -A
git commit -q -m "add two production classes"

scope="$("$SCOPE_SCRIPT" main)"
check_present "com.example.agentsdlc.service.ItemService" "$scope"
check_present "com.example.agentsdlc.web.ItemController" "$scope"
check_absent  "com.example.agentsdlc.service.Untouched" "$scope"

# --- Case 2: a resource-only diff must scope to NOTHING ----------------------------
# This is the exact silent-narrowing failure mode the lesson exists to catch: if the
# script quietly matched every changed file instead of filtering by path prefix and
# extension, this is the assertion that would turn red.
git checkout -q main
git checkout -q -b resource-only
echo "resource changed" > examples/backend/src/main/resources/application.yml
git add -A
git commit -q -m "resource-only change"

resource_scope="$("$SCOPE_SCRIPT" main)"
if [ -n "$resource_scope" ]; then
  echo "FAIL: a resource-only diff produced a non-empty scope: '$resource_scope'" >&2
  fail=1
fi

# --- Case 3: a deleted production class must not appear in scope -------------------
git checkout -q main
git checkout -q -b deleted-class
git rm -q examples/backend/src/main/java/com/example/agentsdlc/service/Untouched.java
git commit -q -m "delete a class"

deleted_scope="$("$SCOPE_SCRIPT" main)"
check_absent "com.example.agentsdlc.service.Untouched" "$deleted_scope"

if [ "$fail" -ne 0 ]; then
  echo "test-mutation-scope.sh: mutation-scope.sh FAILED its self-test." >&2
  exit 1
fi

echo "test-mutation-scope.sh: mutation-scope.sh passed its self-test."
exit 0
