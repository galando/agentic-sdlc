#!/usr/bin/env bats
#
# Gate: ONBOARDING.md (the procedure an adopting AGENT executes), the profiles,
# the skill pointer, and the devcontainer front door stay true to the tools they
# name. Every enumerable fact below is DERIVED from the tool sources at test
# time, never retyped here — a hand-maintained list in this file would be the
# exact drift these tests exist to prevent (the repo's own efficiency-rule-7
# lesson: every handoff that reached a reader who structurally never looked was
# an enumeration that fell out of date).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
ONBOARDING="$REPO_ROOT/ONBOARDING.md"
PROFILE="$REPO_ROOT/profiles/claude-code.answers"

@test "onboarding: every ADOPT_* acceptance variable adopt.sh honours is named in ONBOARDING.md" {
  # Derived from adopt.sh's own source. A variable adopt.sh grows that the
  # onboarding prompt never mentions is an offer no agent will ever accept.
  vars="$(grep -oE 'ADOPT_[A-Z_]+' "$REPO_ROOT/tools/adopt.sh" | sort -u)"
  [ -n "$vars" ]
  missing=""
  while IFS= read -r v; do
    grep -qF "$v" "$ONBOARDING" || missing="$missing $v"
  done <<< "$vars"
  [ -z "$missing" ] || { echo "ONBOARDING.md never names:$missing"; false; }
}

@test "onboarding: every interview variable init.sh asks for is covered by the claude-code profile" {
  # Derived from init.sh's ask lines. PRODUCT_NAME is deliberately only a
  # comment in the profile (the one answer with no default) — a commented
  # mention satisfies this check; total absence does not.
  vars="$(grep -oE '^ask [A-Z_]+' "$REPO_ROOT/tools/init.sh" | awk '{print $2}' | sort -u)"
  [ -n "$vars" ]
  missing=""
  while IFS= read -r v; do
    grep -qE "(^|#)${v}=" "$PROFILE" || missing="$missing $v"
  done <<< "$vars"
  [ -z "$missing" ] || { echo "profiles/claude-code.answers never covers:$missing"; false; }
}

@test "onboarding: every interview variable is also named in ONBOARDING.md" {
  vars="$(grep -oE '^ask [A-Z_]+' "$REPO_ROOT/tools/init.sh" | awk '{print $2}' | sort -u)"
  [ -n "$vars" ]
  missing=""
  while IFS= read -r v; do
    grep -qF "$v" "$ONBOARDING" || missing="$missing $v"
  done <<< "$vars"
  [ -z "$missing" ] || { echo "ONBOARDING.md never names:$missing"; false; }
}

@test "onboarding: the profile is a valid answers file init.sh accepts end to end" {
  # Executed, not grepped: run the real interview against a scratch copy of the
  # tree with the profile plus a PRODUCT_NAME, and require it to finish and
  # produce a clean placeholder check. This is the promise profiles/README.md
  # makes ('the whole interview, pre-filled, minus PRODUCT_NAME'), enforced.
  command -v git >/dev/null 2>&1 || skip "no git"
  scratch="$BATS_TEST_TMPDIR/adopt"
  mkdir -p "$scratch"
  git -C "$REPO_ROOT" archive HEAD | tar -x -C "$scratch"
  # An uncommitted-but-current profile must be testable too (first run adds it).
  mkdir -p "$scratch/profiles"
  cp "$PROFILE" "$scratch/profiles/"
  # init.sh sweeps `git ls-files` and derives its P2 tokens from the repo, so
  # the scratch needs to BE a repo — with an origin URL for the slug derivation.
  git -C "$scratch" init -q
  git -C "$scratch" config user.name test
  git -C "$scratch" config user.email test@example.invalid
  git -C "$scratch" remote add origin https://github.com/example/profile-smoke.git
  git -C "$scratch" add -A
  git -C "$scratch" commit -qm scratch
  answers="$BATS_TEST_TMPDIR/answers"
  { cat "$scratch/profiles/claude-code.answers"; echo 'PRODUCT_NAME="profile-smoke-test"'; } > "$answers"
  run bash -c "cd '$scratch' && tools/init.sh --answers '$answers' </dev/null"
  [ "$status" -eq 0 ]
  run bash -c "cd '$scratch' && tools/check-placeholders.sh"
  [ "$status" -eq 0 ]
}

@test "onboarding: the ordering trap is stated — init.sh --answers before adopt.sh" {
  # The one mistake that looks like success: adopt.sh in a non-interactive
  # shell exits 0 pre-interview having done nothing. The prompt must warn it.
  grep -qF 'init.sh --answers' "$ONBOARDING"
  grep -qiE 'non-interactive shell.*exits 0|exits 0.*non-interactive' "$ONBOARDING"
}

@test "onboarding: the verification loop names the shipped checkers, not vibes" {
  for cmd in 'tools/check-placeholders.sh' 'tools/status.sh' 'bats tests/ tests/harness-guards/' '--dry-run' '--check-credentials'; do
    grep -qF -e "$cmd" "$ONBOARDING"
  done
}

@test "onboarding: the never-merge guardrail is restated to the adopting agent" {
  grep -qiE 'never merge' "$ONBOARDING"
}

@test "onboarding: the skill is a pointer at ONBOARDING.md, never a second copy" {
  skill="$REPO_ROOT/.claude/skills/adopt-agentic-sdlc/SKILL.md"
  [ -f "$skill" ]
  grep -qF 'ONBOARDING.md' "$skill"
  grep -qiE 'single source of truth|ONBOARDING\.md wins' "$skill"
}

@test "onboarding: the devcontainer front door runs the local demo" {
  dc="$REPO_ROOT/.devcontainer/devcontainer.json"
  [ -f "$dc" ]
  grep -qF 'tools/demo-local.sh' "$dc"
  [ -x "$REPO_ROOT/tools/demo-local.sh" ]
}
