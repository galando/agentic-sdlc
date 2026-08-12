#!/usr/bin/env bats
#
# Scenario: the second brain (docs/knowledge/, docs/plans/second-brain-and-sdlc-extension.md
# Part A) stays small and internally consistent. tools/knowledge-lint.sh is the FAST gate
# that enforces the card contract in docs/knowledge/README.md mechanically; these tests
# exercise the real script against synthetic fixtures, never a copy of its logic.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LINT="$REPO_ROOT/tools/knowledge-lint.sh"

setup() {
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/tools" "$FIXTURE/docs/knowledge"
  cp "$LINT" "$FIXTURE/tools/knowledge-lint.sh"
  chmod +x "$FIXTURE/tools/knowledge-lint.sh"
}

teardown() {
  rm -rf "$FIXTURE"
}

write_index() {
  cat > "$FIXTURE/docs/knowledge/INDEX.md" <<EOF
# Knowledge index
$1
EOF
}

write_card() {
  # write_card <slug> <type> <extra-body-lines>
  local slug="$1" type="$2" extra="${3:-}"
  cat > "$FIXTURE/docs/knowledge/$slug.md" <<EOF
---
name: Test card
topic: $slug
type: $type
description: a test card
symptoms: a test symptom
verified: 2026-08-12
---

Body text.
$extra
EOF
}

@test "clean tree (index and one rule card agree) passes" {
  write_index 'example-slug — a one-line description.
  Symptoms: what you would observe.'
  write_card example-slug rule
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
}

@test "a rule card with no index entry fails" {
  write_index ''
  write_card orphan-card rule
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"orphan-card"* ]]
  [[ "$output" == *"no entry"* ]]
}

@test "an index entry with no matching card fails" {
  write_index 'ghost-slug — a description that has no card.
  Symptoms: whatever.'
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghost-slug"* ]]
  [[ "$output" == *"no matching card"* ]]
}

@test "a project card indexed anyway fails — project cards are grep-only" {
  write_index 'proj-card — a description.
  Symptoms: whatever.'
  write_card proj-card project
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"grep-only"* ]]
}

@test "a project card with no index entry is fine (excluded by design)" {
  write_index ''
  write_card proj-card project
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 0 ]
}

@test "a card missing a required frontmatter field fails" {
  write_index 'broken-card — a description.
  Symptoms: whatever.'
  cat > "$FIXTURE/docs/knowledge/broken-card.md" <<'EOF'
---
name: Broken card
topic: broken-card
type: rule
description: missing symptoms and verified
---

Body.
EOF
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"symptoms"* ]]
  [[ "$output" == *"verified"* ]]
}

@test "a card whose topic does not match its filename fails" {
  write_index 'mismatched — a description.
  Symptoms: whatever.'
  cat > "$FIXTURE/docs/knowledge/mismatched.md" <<'EOF'
---
name: Mismatched card
topic: something-else
type: rule
description: topic does not match filename
symptoms: whatever
verified: 2026-08-12
---

Body.
EOF
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match its filename"* ]]
}

@test "an invalid type fails" {
  write_index 'bad-type — a description.
  Symptoms: whatever.'
  write_card bad-type notatype
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not one of rule, trap, project"* ]]
}

@test "a non-date verified field fails" {
  write_index 'bad-date — a description.
  Symptoms: whatever.'
  cat > "$FIXTURE/docs/knowledge/bad-date.md" <<'EOF'
---
name: Bad date
topic: bad-date
type: rule
description: verified is not a date
symptoms: whatever
verified: not-a-date
---

Body.
EOF
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a YYYY-MM-DD date"* ]]
}

@test "a card body over 60 lines fails" {
  write_index 'long-card — a description.
  Symptoms: whatever.'
  {
    echo "---"
    echo "name: Long card"
    echo "topic: long-card"
    echo "type: rule"
    echo "description: too long"
    echo "symptoms: whatever"
    echo "verified: 2026-08-12"
    echo "---"
    for i in $(seq 1 65); do echo "line $i"; done
  } > "$FIXTURE/docs/knowledge/long-card.md"
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"over the 60-line cap"* ]]
}

@test "INDEX.md over 80 lines fails" {
  {
    echo "# Knowledge index"
    for i in $(seq 1 85); do echo "filler line $i"; done
  } > "$FIXTURE/docs/knowledge/INDEX.md"
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"over the 80-line cap"* ]]
}

@test "a duplicated index slug fails" {
  write_index 'dup-slug — first mention.
  Symptoms: whatever.
dup-slug — second mention.
  Symptoms: something else.'
  write_card dup-slug rule
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"more than once"* ]]
}

@test "an absent docs/knowledge/ directory is a no-op, not a failure" {
  rm -rf "$FIXTURE/docs/knowledge"
  run "$FIXTURE/tools/knowledge-lint.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to check"* ]]
}

@test "the real docs/knowledge/ tree in this repository passes" {
  run "$LINT"
  [ "$status" -eq 0 ]
}
