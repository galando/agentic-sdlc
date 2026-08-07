#!/usr/bin/env bats
#
# tools/write-product-readme.sh — the product-README generator. A real adopted
# repository kept the template's README indefinitely because nothing in the
# adoption touched it; these tests pin the generator's three load-bearing
# behaviors: it writes a README about the PRODUCT (name, badges, no leftover
# template identity), it only ever replaces a README it can positively identify
# as the template's own, and it degrades cleanly with no origin remote.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/tools" "$FIXTURE/.github/workflows"
  cp "$REPO_ROOT/tools/write-product-readme.sh" "$FIXTURE/tools/"
  chmod +x "$FIXTURE/tools/write-product-readme.sh"

  git -C "$FIXTURE" init -q
  git -C "$FIXTURE" remote add origin "https://github.com/acme/widget.git"

  # The template README, positively identified by its H1.
  cat > "$FIXTURE/README.md" <<'EOF'
# Agentic SDLC

**Agents propose, a human merges, CI decides.**

This repository is a **GitHub template**: the process scaffolding.
EOF

  # AGENTS.md as init.sh leaves it after the interview — the line the
  # generator reads the product name from when no argument is given.
  cat > "$FIXTURE/AGENTS.md" <<'EOF'
# AGENTS.md — rules for autonomous agent sessions

These rules bind every autonomous agent session operating on Widget,
**regardless of which runner executes it**.
EOF

  # Two harness workflows present, one absent — the badge row must reflect
  # what actually exists in the tree, never the template's full list.
  touch "$FIXTURE/.github/workflows/pr-tests.yml" "$FIXTURE/.github/workflows/review.yml"
}

teardown() {
  rm -rf "$FIXTURE"
}

@test "replaces the template README with one titled for the product" {
  run bash "$FIXTURE/tools/write-product-readme.sh"
  [ "$status" -eq 0 ]
  grep -qE '^# Widget$' "$FIXTURE/README.md"
  ! grep -qE '^# Agentic SDLC$' "$FIXTURE/README.md"
  # The agentic-SDLC explainer and the backlink to the upstream template.
  grep -qF 'agents propose, CI decides, a human merges' "$FIXTURE/README.md"
  grep -qF 'github.com/galando/agentic-sdlc' "$FIXTURE/README.md"
}

@test "badges point at the origin slug and cover only workflows present in the tree" {
  run bash "$FIXTURE/tools/write-product-readme.sh"
  [ "$status" -eq 0 ]
  grep -qF 'https://github.com/acme/widget/actions/workflows/pr-tests.yml/badge.svg' "$FIXTURE/README.md"
  grep -qF 'workflows/review.yml/badge.svg' "$FIXTURE/README.md"
  # pr-mutation.yml does not exist in this fixture, so no dead badge for it.
  ! grep -qF 'pr-mutation' "$FIXTURE/README.md"
}

@test "an explicit product-name argument beats the AGENTS.md parse" {
  run bash "$FIXTURE/tools/write-product-readme.sh" "Gadget Pro"
  [ "$status" -eq 0 ]
  grep -qE '^# Gadget Pro$' "$FIXTURE/README.md"
}

@test "a README that is already the product's own is never replaced by default" {
  printf '# Widget\n\nHand-written, deliberately.\n' > "$FIXTURE/README.md"
  run bash "$FIXTURE/tools/write-product-readme.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not touching it"* ]]
  grep -qF 'Hand-written, deliberately.' "$FIXTURE/README.md"
}

@test "--force regenerates over a customized README" {
  printf '# Widget\n\nHand-written.\n' > "$FIXTURE/README.md"
  run bash "$FIXTURE/tools/write-product-readme.sh" --force
  [ "$status" -eq 0 ]
  ! grep -qF 'Hand-written.' "$FIXTURE/README.md"
  grep -qF 'This repository runs an agentic SDLC' "$FIXTURE/README.md"
}

@test "no origin remote degrades to no badges, with a note, not a failure" {
  git -C "$FIXTURE" remote remove origin
  run bash "$FIXTURE/tools/write-product-readme.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"without status badges"* ]]
  ! grep -qF 'badge.svg' "$FIXTURE/README.md"
  grep -qE '^# Widget$' "$FIXTURE/README.md"
}

@test "an ssh-style origin URL parses to the same slug" {
  git -C "$FIXTURE" remote set-url origin "git@github.com:acme/widget.git"
  run bash "$FIXTURE/tools/write-product-readme.sh"
  [ "$status" -eq 0 ]
  grep -qF 'https://github.com/acme/widget/actions' "$FIXTURE/README.md"
}

@test "no product name anywhere fails loudly with the fix in the message" {
  rm "$FIXTURE/AGENTS.md"
  run bash "$FIXTURE/tools/write-product-readme.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tools/init.sh"* ]]
}

@test "an unresolved placeholder as the product name is refused, not written" {
  # AGENTS.md before the interview still carries the token; generating a README
  # titled with it would just relocate the broken-placeholder front page.
  sed -i 's/operating on Widget,/operating on {{PRODUCT_NAME}},/' "$FIXTURE/AGENTS.md"
  run bash "$FIXTURE/tools/write-product-readme.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"init.sh"* ]]
}

@test "the generated README carries no unresolved double-brace token" {
  run bash "$FIXTURE/tools/write-product-readme.sh"
  [ "$status" -eq 0 ]
  ! grep -qE '\{\{[A-Z_]+\}\}' "$FIXTURE/README.md"
}

@test "mentions ADOPTION-LOG.md only when the file exists" {
  run bash "$FIXTURE/tools/write-product-readme.sh"
  [ "$status" -eq 0 ]
  ! grep -qF 'ADOPTION-LOG.md' "$FIXTURE/README.md"

  touch "$FIXTURE/ADOPTION-LOG.md"
  run bash "$FIXTURE/tools/write-product-readme.sh" --force
  [ "$status" -eq 0 ]
  grep -qF 'ADOPTION-LOG.md' "$FIXTURE/README.md"
}
