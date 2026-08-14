#!/usr/bin/env bats
#
# tools/upgrade.sh — the manifest, the brownfield installer, and the
# computable upgrade. Executed against synthetic template fixtures, never a
# copy of the logic; the one hand-kept fact (the interview token list) is
# asserted against init.sh so the two can never drift.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
UPGRADE="$REPO_ROOT/tools/upgrade.sh"

# A minimal "template checkout": a git repo with a harness-shaped surface,
# including the exclusions list-files must drop and one placeholder token.
make_template() {
  local dir="$1"
  mkdir -p "$dir/tools" "$dir/examples" "$dir/site" "$dir/docs/maintainers" "$dir/.agents"
  printf '#!/bin/sh\necho "product: {{PRODUCT_NAME}}"\n' > "$dir/tools/hello.sh"
  printf 'shared harness line\n' > "$dir/tools/stable.sh"
  printf 'mutation: unset\n' > "$dir/floors.yml"
  printf 'example product\n' > "$dir/examples/e.txt"
  printf 'site\n' > "$dir/site/index.html"
  printf 'maintainer notes\n' > "$dir/docs/maintainers/notes.md"
  printf 'readme\n' > "$dir/README.md"
  printf '## [1.0.0] - 2026-01-01\n' > "$dir/CHANGELOG.md"
  ( cd "$dir" && git init -q && git config user.name t && git config user.email t@example.invalid \
      && git add -A && git commit -qm base )
}

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  TPL="$BATS_TEST_TMPDIR/template"
  make_template "$TPL"
}

@test "upgrade: the token list matches init.sh's TOKENS array, one for one" {
  # Two lists exist (init.sh's bash array, upgrade.sh's replay list) because
  # they live in different languages; this assertion is what keeps them one.
  init_tokens="$(sed -n '/^declare -a TOKENS=/,/^)/p' "$REPO_ROOT/tools/init.sh" \
    | grep -oE '[A-Z_]+' | grep -v '^TOKENS$' | sort)"
  upgrade_tokens="$(grep -m1 '^TOKENS=' "$UPGRADE" | grep -oE '[A-Z_]+' | grep -v '^TOKENS$' | sort)"
  [ -n "$init_tokens" ]
  [ "$init_tokens" = "$upgrade_tokens" ]
}

@test "upgrade: list-files keeps the harness and drops the retired-on-adoption surface" {
  run env AGENTS_ROOT="$TPL" bash "$UPGRADE" list-files
  [ "$status" -eq 0 ]
  [[ "$output" == *"tools/hello.sh"* ]]
  [[ "$output" == *"floors.yml"* ]]
  [[ "$output" != *"examples/"* ]]
  [[ "$output" != *"site/"* ]]
  [[ "$output" != *"docs/maintainers/"* ]]
  [[ "$output" != *"README.md"* ]]
}

@test "upgrade: stamp records pristine hashes and the answers from the environment" {
  run env AGENTS_ROOT="$TPL" PRODUCT_NAME="widget" bash "$UPGRADE" stamp 1.0.0
  [ "$status" -eq 0 ]
  m="$TPL/.agents/template-manifest.json"
  [ -f "$m" ]
  [ "$(jq -r '.template_version' "$m")" = "1.0.0" ]
  [ "$(jq -r '.answers.PRODUCT_NAME' "$m")" = "widget" ]
  # The recorded hash is the PRISTINE file (token intact).
  want="$(sha256sum "$TPL/tools/hello.sh" | cut -d' ' -f1)"
  [ "$(jq -r '.files["tools/hello.sh"]' "$m")" = "$want" ]
  grep -q '{{PRODUCT_NAME}}' "$TPL/tools/hello.sh"
}

@test "upgrade: --install copies the harness, never overwrites, and stamps the target" {
  host="$BATS_TEST_TMPDIR/host"
  mkdir -p "$host/tools"
  printf 'the host already had this\n' > "$host/tools/stable.sh"
  ( cd "$host" && git init -q )
  run env AGENTS_ROOT="$TPL" bash "$UPGRADE" --install "$host"
  [ "$status" -eq 0 ]
  # New file arrives; colliding file is untouched, proposal beside it.
  [ -f "$host/tools/hello.sh" ]
  grep -q 'the host already had this' "$host/tools/stable.sh"
  [ -f "$host/tools/stable.sh.agentic-sdlc.proposed" ]
  # The example product and the site never cross over.
  [ ! -e "$host/examples" ]
  [ ! -e "$host/site" ]
  # The manifest lands in the TARGET with the template's pristine hashes.
  [ -f "$host/.agents/template-manifest.json" ]
  [ "$(jq -r '.template_version' "$host/.agents/template-manifest.json")" = "1.0.0" ]
}

@test "upgrade: apply takes clean updates, three-way-merges local edits, and never touches floors" {
  # Adopt the template: stamp (pristine), then substitute — as init.sh would.
  ( cd "$TPL" && env AGENTS_ROOT="$TPL" PRODUCT_NAME="widget" bash "$UPGRADE" stamp 1.0.0 >/dev/null )
  sed -i.bak 's|{{PRODUCT_NAME}}|widget|g' "$TPL/tools/hello.sh" && rm -f "$TPL/tools/hello.sh.bak"
  # The adopter edits one harness file and calibrates a floor.
  printf 'local addition\n' >> "$TPL/tools/stable.sh"
  printf 'mutation: 61\n' > "$TPL/floors.yml"
  # The OLD template (the recorded base) and the NEW release.
  OLD="$BATS_TEST_TMPDIR/old"; NEW="$BATS_TEST_TMPDIR/new"
  make_template "$OLD"
  make_template "$NEW"
  printf '#!/bin/sh\necho "product: {{PRODUCT_NAME}}"\necho "upstream improvement"\n' > "$NEW/tools/hello.sh"
  printf 'upstream harness line\nshared harness line\n' > "$NEW/tools/stable.sh"
  printf 'mutation: unset\n' > "$NEW/floors.yml"
  printf 'brand new tool\n' > "$NEW/tools/fresh.sh"
  printf '## [1.1.0] - 2026-02-01\n' > "$NEW/CHANGELOG.md"
  ( cd "$NEW" && git add -A && git commit -qm v1.1.0 )

  run env AGENTS_ROOT="$TPL" bash "$UPGRADE" apply "$NEW" "$OLD"
  [ "$status" -eq 0 ]
  # Clean update arrives with the answers replayed (no token, the real name).
  grep -q 'upstream improvement' "$TPL/tools/hello.sh"
  grep -q 'product: widget' "$TPL/tools/hello.sh"
  run grep -F '{{PRODUCT_NAME}}' "$TPL/tools/hello.sh"
  [ "$status" -ne 0 ]
  # The locally-edited file keeps BOTH sides — a real three-way merge.
  grep -q 'local addition' "$TPL/tools/stable.sh"
  grep -q 'upstream harness line' "$TPL/tools/stable.sh"
  # New upstream file arrives; the calibrated floor is untouched.
  [ -f "$TPL/tools/fresh.sh" ]
  grep -q 'mutation: 61' "$TPL/floors.yml"
  # The manifest re-baselined to the new release, answers carried over.
  [ "$(jq -r '.template_version' "$TPL/.agents/template-manifest.json")" = "1.1.0" ]
  [ "$(jq -r '.answers.PRODUCT_NAME' "$TPL/.agents/template-manifest.json")" = "widget" ]
}

@test "upgrade: plan without the old template names the ambiguity instead of guessing" {
  ( cd "$TPL" && env AGENTS_ROOT="$TPL" PRODUCT_NAME="widget" bash "$UPGRADE" stamp 1.0.0 >/dev/null )
  printf 'local addition\n' >> "$TPL/tools/stable.sh"
  NEW="$BATS_TEST_TMPDIR/new2"
  make_template "$NEW"
  printf 'upstream harness line\nshared harness line\n' > "$NEW/tools/stable.sh"
  ( cd "$NEW" && git add -A && git commit -qm next )
  run env AGENTS_ROOT="$TPL" bash "$UPGRADE" plan "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"differs"* ]]
  [[ "$output" == *"cannot tell local edits from upstream changes"* ]]
}
