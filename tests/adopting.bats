#!/usr/bin/env bats
#
# Scenario "init.sh leaves no unresolved placeholder" (intent.md, SC7) and tasks.md
# Task 26 — design.md section 4.4 (D9): ADOPTING.md's placeholder table is a pure
# function of the tracked tree, regenerated and diff-gated by fast-repo-hygiene so "a
# placeholder whose ADOPTING.md row is missing is invisible" cannot be merged.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

@test "ADOPTING.md exists and carries the generator markers" {
  [ -f "$REPO_ROOT/ADOPTING.md" ]
  grep -qF '<!-- PLACEHOLDERS:BEGIN -->' "$REPO_ROOT/ADOPTING.md"
  grep -qF '<!-- PLACEHOLDERS:END -->' "$REPO_ROOT/ADOPTING.md"
}

@test "tools/gen-adopting.sh is a pure function of the tree — regenerating it is a no-op" {
  cd "$REPO_ROOT"
  cp ADOPTING.md /tmp/adopting-before.$$.md
  run bash tools/gen-adopting.sh
  [ "$status" -eq 0 ]
  run diff -q /tmp/adopting-before.$$.md ADOPTING.md
  rm -f /tmp/adopting-before.$$.md
  [ "$status" -eq 0 ]
}

@test "every real P1 token still present in the tree has a row in the generated table" {
  # Real interview tokens (tools/init.sh's own TOKENS array) must each appear as a row,
  # not just P2/P4/P5 tokens — WHILE the token still occurs in the scanned tree. After
  # tools/init.sh has run, a resolved token legitimately has zero occurrences and zero
  # rows; requiring the row unconditionally made this test fail on every adopted
  # repository the moment the interview completed, forever.
  cd "$REPO_ROOT"
  for tok in PRODUCT_NAME PROVIDER MODEL_JUDGE MODEL_EXECUTE MODEL_CHALLENGE \
             CHALLENGE_BASE_URL ALERT_CHANNEL RUNNER_LABEL LEDGER_COMMIT_NAME \
             LEDGER_COMMIT_EMAIL BUILD_PIPELINE; do
    if git grep -l -F "{{${tok}}}" -- ':!tests' ':!.temper/specs' ':!ADOPTING.md' >/dev/null 2>&1; then
      grep -qF "{{${tok}}}" "$REPO_ROOT/ADOPTING.md"
    fi
  done
}

@test "tools/init.sh never substitutes inside ADOPTING.md itself" {
  grep -q "ADOPTING\\\\.md" "$REPO_ROOT/tools/init.sh"
}

@test "gen-adopting.sh fails loudly on a token with no annotation" {
  cd "$REPO_ROOT"
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/tools"
  cp tools/gen-adopting.sh "$FIXTURE/tools/gen-adopting.sh"
  # A minimal init.sh stand-in — gen-adopting.sh only reads it to classify resolvers.
  cat > "$FIXTURE/tools/init.sh" <<'EOF'
declare -a TOKENS=(PRODUCT_NAME)
EOF
  cat > "$FIXTURE/ADOPTING.md" <<'EOF'
<!-- PLACEHOLDERS:BEGIN -->
<!-- PLACEHOLDERS:END -->
EOF
  echo 'no annotation here: {{UNANNOTATED_TOKEN}}' > "$FIXTURE/somefile.md"
  ( cd "$FIXTURE" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init )
  run bash "$FIXTURE/tools/gen-adopting.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no annotation found"* ]]
  rm -rf "$FIXTURE"
}
