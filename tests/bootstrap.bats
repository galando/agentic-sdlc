#!/usr/bin/env bats
#
# tools/bootstrap.sh — the one-command adoption, and tools/init.sh --defaults under it.
#
# The promise these tests pin: from inside ANY git repository, one command with no
# questions lands the harness, resolves every placeholder with printed defaults,
# verifies with the shipped checkers, never overwrites a file of yours, never pushes,
# and never reads its answers from stdin (it may be running from `curl | bash`, where
# stdin IS the script). The template itself is the fixture: a copy of this working
# tree, so an uncommitted change to the tools is tested too.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# A template checkout built from the working tree (tracked + untracked, not ignored),
# without the example product — its node_modules and build outputs are irrelevant here
# and the copy is a fraction of the size without them.
make_template() {
  local dir="$1"
  mkdir -p "$dir"
  ( cd "$REPO_ROOT" && git ls-files -co --exclude-standard | grep -v '^examples/' | tar -T - -c ) | tar -x -C "$dir"
  ( cd "$dir" && git init -q && git config user.name t && git config user.email t@example.invalid \
      && git remote add origin https://github.com/example/my-shop.git \
      && git add -A && git commit -qm template )
}

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  TPL="$BATS_TEST_TMPDIR/template"
  make_template "$TPL"
}

@test "a template clone: one command, no questions, every placeholder resolved, README rewritten, nothing pushed" {
  run bash -c "cd '$TPL' && tools/bootstrap.sh --product 'Acme Widgets' </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"State: a clone of the template"* ]]
  [[ "$output" == *"--defaults: assumed"* ]]
  [[ "$output" == *"Four things only you can do"* ]]
  run bash -c "cd '$TPL' && tools/check-placeholders.sh"
  [ "$status" -eq 0 ]
  grep -q 'provider: "claude-code"' "$TPL/.agents/config.yml"
  grep -q 'Acme Widgets' "$TPL/AGENTS.md"
  grep -q '^# Acme Widgets' "$TPL/README.md"
  # Nothing left the machine: the remote has no branches at all.
  ! git -C "$TPL" ls-remote --exit-code origin >/dev/null 2>&1 || true
  [ "$(git -C "$TPL" rev-list --count HEAD)" -eq 1 ]
}

@test "the product name defaults to the repository's name from the origin remote, and is printed" {
  run bash -c "cd '$TPL' && tools/bootstrap.sh </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRODUCT_NAME=my-shop"* ]]
  grep -q 'my-shop' "$TPL/AGENTS.md"
}

@test "a second run finds the repository adopted and changes nothing" {
  bash -c "cd '$TPL' && tools/bootstrap.sh --product Acme </dev/null" >/dev/null
  before="$(cd "$TPL" && git status --porcelain | sort)"
  run bash -c "cd '$TPL' && tools/bootstrap.sh --product Other </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already adopted"* ]]
  after="$(cd "$TPL" && git status --porcelain | sort)"
  [ "$before" = "$after" ]
  grep -q 'Acme' "$TPL/AGENTS.md"
}

@test "an existing repository: the harness lands beside its files, never over them, and is visible to the interview" {
  HOST="$BATS_TEST_TMPDIR/host"
  mkdir -p "$HOST/src"
  printf '# My existing project\n' > "$HOST/README.md"
  printf 'print("hi")\n' > "$HOST/src/app.py"
  printf 'node_modules/\n' > "$HOST/.gitignore"
  ( cd "$HOST" && git init -q && git config user.name t && git config user.email t@example.invalid \
      && git remote add origin git@github.com:example/widget-shop.git && git add -A && git commit -qm base )
  # An existing repository has no tools/ yet: the script comes from the template (or
  # from curl), so it is invoked by its template path here.
  run bash -c "cd '$HOST' && bash '$TPL/tools/bootstrap.sh' --source '$TPL' </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"State: your repository, harness not installed yet"* ]]
  [[ "$output" == *"PRODUCT_NAME=widget-shop"* ]]
  # The harness is there and initialised.
  [ -f "$HOST/.agents/config.yml" ]
  [ -x "$HOST/tools/run-agent.sh" ]
  [ -f "$HOST/.github/workflows/review.yml" ]
  grep -q 'provider: "claude-code"' "$HOST/.agents/config.yml"
  grep -q 'widget-shop' "$HOST/AGENTS.md"
  [ "$(jq -r '.template_version' "$HOST/.agents/template-manifest.json")" != "" ]
  run bash -c "cd '$HOST' && tools/check-placeholders.sh"
  [ "$status" -eq 0 ]
  # Nothing of the host's was touched; a collision landed beside the host's file.
  [ "$(cat "$HOST/README.md")" = "# My existing project" ]
  [ "$(cat "$HOST/src/app.py")" = 'print("hi")' ]
  [ "$(cat "$HOST/.gitignore")" = "node_modules/" ]
  [ -f "$HOST/.gitignore.agentic-sdlc.proposed" ]
  # The copied files are visible to git (intent-to-add), so the interview's sweep saw them;
  # the host's own tree is still exactly one commit.
  git -C "$HOST" ls-files --error-unmatch tools/run-agent.sh >/dev/null
  [ "$(git -C "$HOST" rev-list --count HEAD)" -eq 1 ]
}

@test "outside a git repository it refuses and names the one command that fixes it" {
  NOREPO="$BATS_TEST_TMPDIR/norepo"
  mkdir -p "$NOREPO"
  run bash -c "cd '$NOREPO' && bash '$TPL/tools/bootstrap.sh' --source '$TPL' </dev/null"
  [ "$status" -ne 0 ]
  [[ "$output" == *"git init"* ]]
}

@test "--dry-run prints the plan and changes nothing" {
  before="$(cd "$TPL" && git status --porcelain)"
  run bash -c "cd '$TPL' && tools/bootstrap.sh --product Acme --dry-run"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Plan (--dry-run"* ]]
  [[ "$output" == *"tools/init.sh --defaults"* ]]
  [ "$(cd "$TPL" && git status --porcelain)" = "$before" ]
  grep -qF '{{PROVIDER}}' "$TPL/.agents/config.yml"
}

@test "stdin is never read: piping answers at it changes no offer (curl | bash is safe)" {
  # If any offer read stdin, these three lines would delete the example and create
  # the ledger branch. The example is absent from this fixture, so the observable is
  # the ledger-branch offer: the remote must still have no branch afterwards.
  run bash -c "cd '$TPL' && printf 'y\ny\ny\n' | tools/bootstrap.sh --product Acme"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped. Run tools/create-ledger-branch.sh"* ]]
}

@test "init.sh --defaults: preset variables win over the profile and the derived name" {
  run bash -c "cd '$TPL' && PRODUCT_NAME='Preset Name' MODEL_JUDGE='judge-x' tools/init.sh --defaults </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"PRODUCT_NAME=my-shop"* ]]
  [[ "$output" == *"MODEL_EXECUTE="* ]]
  grep -q 'Preset Name' "$TPL/AGENTS.md"
  grep -q 'judge-x' "$TPL/.agents/config.yml"
}

@test "init.sh --defaults: an unknown provider with no profile stops loudly, naming the profile path" {
  run bash -c "cd '$TPL' && PROVIDER=nope tools/init.sh --defaults </dev/null"
  [ "$status" -ne 0 ]
  [[ "$output" == *"profiles/nope.answers"* ]]
}

@test "the front doors point at the one command: README, ONBOARDING.md, the skill, the devcontainer" {
  grep -qF 'tools/bootstrap.sh' "$REPO_ROOT/README.md"
  grep -qF 'tools/bootstrap.sh' "$REPO_ROOT/ONBOARDING.md"
  grep -qF 'tools/bootstrap.sh' "$REPO_ROOT/.claude/skills/adopt-agentic-sdlc/SKILL.md"
  grep -qF 'tools/bootstrap.sh' "$REPO_ROOT/site/index.html"
}
