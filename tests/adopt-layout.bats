#!/usr/bin/env bats
#
# tools/adopt-layout.sh — the one-step examples/ retirement + harness re-point.
# The first real adoption did this sweep by hand and counted ~50 references; these
# tests pin that the script covers the whole surface, is idempotent, and fails
# loudly if a reference survives outside its substitution list.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/tools" "$FIXTURE/.github/workflows" "$FIXTURE/examples/backend"
  cp "$REPO_ROOT/tools/adopt-layout.sh" "$FIXTURE/tools/adopt-layout.sh"
  chmod +x "$FIXTURE/tools/adopt-layout.sh"

  echo "example content" > "$FIXTURE/examples/backend/pom.xml"
  cat > "$FIXTURE/.github/workflows/w.yml" <<'EOF'
      - 'examples/backend/src/main/java/**'
      - 'examples/frontend/src/**'
        working-directory: ./examples/backend
          if [ -x ../../tools/floor-get.sh ]; then
            FLOOR="$(../../tools/floor-get.sh backend.mutation.score || echo unset)"
EOF
  cat > "$FIXTURE/tools/mutation-scope.sh" <<'EOF'
SRC_PREFIX="examples/backend/src/main/java/"
EOF
  cat > "$FIXTURE/.gitignore" <<'EOF'
examples/backend/target/
examples/frontend/node_modules/
EOF
}

teardown() {
  rm -rf "$FIXTURE"
}

@test "deletes examples/ and re-points every reference in one run" {
  run bash "$FIXTURE/tools/adopt-layout.sh"
  [ "$status" -eq 0 ]
  [ ! -d "$FIXTURE/examples" ]
  grep -qF "'backend/src/main/java/**'" "$FIXTURE/.github/workflows/w.yml"
  grep -qF "'frontend/src/**'" "$FIXTURE/.github/workflows/w.yml"
  grep -qF 'working-directory: ./backend' "$FIXTURE/.github/workflows/w.yml"
  ! grep -qF 'examples/' "$FIXTURE/.github/workflows/w.yml"
  grep -qF 'SRC_PREFIX="backend/src/main/java/"' "$FIXTURE/tools/mutation-scope.sh"
  grep -qF 'backend/target/' "$FIXTURE/.gitignore"
  ! grep -qF 'examples/' "$FIXTURE/.gitignore"
}

@test "re-bases the ../../tools depth for the shallower working-directory" {
  # pr-mutation.yml is the file that carries this in the real tree; the fixture's
  # workflow stands in for it — the script matches on content, and the depth
  # re-base runs on pr-mutation.yml by name, so exercise it under that name.
  cp "$FIXTURE/.github/workflows/w.yml" "$FIXTURE/.github/workflows/pr-mutation.yml"
  run bash "$FIXTURE/tools/adopt-layout.sh"
  [ "$status" -eq 0 ]
  grep -qF -- '-x ../tools/floor-get.sh' "$FIXTURE/.github/workflows/pr-mutation.yml"
  ! grep -qF -- '../../tools/floor-get.sh' "$FIXTURE/.github/workflows/pr-mutation.yml"
}

@test "running it twice is a no-op that says so" {
  bash "$FIXTURE/tools/adopt-layout.sh" >/dev/null
  run bash "$FIXTURE/tools/adopt-layout.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to do"* ]]
}

@test "a surviving example reference outside the sweep fails loudly, never silently" {
  # A reference in a file the substitution list does not cover must abort with the
  # file named — a silent survivor is a paths-filter that never matches again.
  echo 'scan examples/backend/src' > "$FIXTURE/tools/unlisted-helper.sh"
  run bash "$FIXTURE/tools/adopt-layout.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unlisted-helper.sh"* ]]
}

@test "works when examples/ was already deleted by hand" {
  rm -rf "$FIXTURE/examples"
  run bash "$FIXTURE/tools/adopt-layout.sh"
  [ "$status" -eq 0 ]
  ! grep -qF 'examples/' "$FIXTURE/.github/workflows/w.yml"
}
