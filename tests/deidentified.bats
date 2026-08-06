#!/usr/bin/env bats
#
# Scenario: "De-identification sweep finds zero source-project traces" (SC1).
#
# The scanner under test must be GENERIC. It takes --terms <file> and contains
# no project-specific string of its own, which is the only reason it can be
# subject to its own sweep with no self-exclusion.
#
# A scanner carrying its terms inline would ship, in the template, a curated
# enumeration of precisely what the template claims to have removed — a worse
# leak than a stray mention, because it is organised, and because it is the
# first file a reader opens to audit whether the extraction was clean. The only
# escape from that is self-exclusion, which makes the leak invisible to the one
# check meant to catch it. A check that must exempt itself to pass is not a
# check.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCAN="$REPO_ROOT/tools/check-deidentified.sh"

setup() {
  WORK="$(mktemp -d)"
  export WORK
  git init -q "$WORK/repo"
  cd "$WORK/repo"
  git config user.name  "test"
  git config user.email "test@example.invalid"

  printf 'acmecorp\nwidgetron\n' > "$WORK/terms.txt"

  echo "a perfectly generic readme" > README.md
  git add README.md
  git commit -q -m "chore: initial"
}

teardown() {
  rm -rf "$WORK"
}

@test "a clean tree exits 0 and says so" {
  cd "$WORK/repo"
  run "$SCAN" --terms "$WORK/terms.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 hit"* || "$output" == *"clean"* ]]
}

@test "a term in file CONTENT is found and the file and line are named" {
  cd "$WORK/repo"
  printf 'this belongs to AcmeCorp\n' > notes.md
  git add notes.md && git commit -q -m "chore: notes"
  run "$SCAN" --terms "$WORK/terms.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"notes.md"* ]]
}

@test "the content match is case-insensitive" {
  cd "$WORK/repo"
  printf 'ACMECORP shouted loudly\n' > shout.md
  git add shout.md && git commit -q -m "chore: shout"
  run "$SCAN" --terms "$WORK/terms.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"shout.md"* ]]
}

@test "a term in a FILE NAME is found even when the content is clean" {
  # A file name is not file content, so a content-only grep misses it entirely
  # — and a path is exactly where a product name survives longest.
  cd "$WORK/repo"
  echo "nothing incriminating inside" > acmecorp-setup.md
  git add acmecorp-setup.md && git commit -q -m "chore: add a doc"
  run "$SCAN" --terms "$WORK/terms.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"acmecorp-setup.md"* ]]
  [[ "$output" == *"file name"* || "$output" == *"filename"* ]]
}

@test "a term in a COMMIT MESSAGE is found even when the tree is clean" {
  # The tree can be spotless while the history still names the source project.
  # A template is cloned with its history; anyone can read it.
  cd "$WORK/repo"
  echo "harmless" > x.md
  git add x.md && git commit -q -m "feat: port the widgetron importer"
  run "$SCAN" --terms "$WORK/terms.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"commit message"* ]]
}

@test "only TRACKED files are scanned — an ignored term file is not a finding" {
  # The real term list lives gitignored under .temper/evidence/. If the scanner
  # walked the working tree instead of the index it would flag its own input on
  # every run, and the honest response to that would be an exclusion — which is
  # how self-exclusion gets introduced.
  cd "$WORK/repo"
  mkdir -p .temper/evidence
  printf '.temper/evidence/\n' > .gitignore
  cp "$WORK/terms.txt" .temper/evidence/deident-terms.txt
  git add .gitignore && git commit -q -m "chore: ignore evidence"
  run "$SCAN" --terms "$WORK/terms.txt"
  [ "$status" -eq 0 ]
}

@test "a missing term file is a usage error, never a silent pass" {
  # The worst possible behaviour: report success because the list was empty.
  # That is a green run with a wrong answer, which is the exact failure this
  # whole template is built to prevent.
  cd "$WORK/repo"
  run "$SCAN" --terms "$WORK/does-not-exist.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not found"* || "$output" == *"no such"* ]]
}

@test "an EMPTY term file is a usage error, never a silent pass" {
  cd "$WORK/repo"
  : > "$WORK/empty.txt"
  run "$SCAN" --terms "$WORK/empty.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"empty"* ]]
}

@test "with no --terms it looks for .deident-terms and skips CLEANLY when absent" {
  # The CI wiring must not fail an adopter who has not written a term list.
  # It must also not be silent about having checked nothing.
  cd "$WORK/repo"
  run "$SCAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *".deident-terms"* ]]
  [[ "$output" == *"skip"* || "$output" == *"no term"* ]]
}

@test "the announced skip is ANNOUNCED where CI shows it, not only in the log body" {
  # An adopter reading a job's log will see the prose. Nobody reads a green job's log.
  # The annotation is the difference between "this check found nothing" and "this check
  # looked at nothing", displayed at the only place a green run is ever glanced at.
  #
  # This is the same announced-skip shape ci-health-watch.yml and gate 18 use, and it is
  # here for the same reason: the de-identification sweep is the check that proves SC1,
  # and a silently-green SC1 is the exact class of failure this repository is built to
  # prevent — a green run with a wrong answer.
  cd "$WORK/repo"
  export GITHUB_ACTIONS=true
  run "$SCAN"
  unset GITHUB_ACTIONS
  [ "$status" -eq 0 ]
  [[ "$output" == *"::notice title=De-identification sweep not armed::"* ]]
}

@test "outside CI the skip stays plain prose — no annotation syntax in a terminal" {
  cd "$WORK/repo"
  run "$SCAN"
  [ "$status" -eq 0 ]
  [[ "$output" != *"::notice"* ]]
}

@test "the CI wiring can arm the sweep without the term list entering the tree" {
  # The constraint that makes this hard: committing the term list would ship a curated
  # enumeration of exactly what the template claims to have removed. So the list reaches
  # CI as a SECRET, is written outside the working tree, and is never added to it.
  WF="$REPO_ROOT/.github/workflows/pr-tests.yml"
  grep -q 'DEIDENT_TERMS' "$WF"
  grep -qE '\-\-terms' "$WF"
  # Written under the runner's temp directory, never under the checkout. A term file
  # inside the tree is one `git add -A` away from being the leak it was written to find.
  grep -q 'RUNNER_TEMP' "$WF"
  run grep -cE '\-\-terms[[:space:]]+\.?/?(\.deident-terms|[a-z]+/)' "$WF"
  [ "$output" -eq 0 ]
}

@test "the CI wiring never reports the sweep as passed when it was not armed" {
  # Both branches must be present and distinguishable: armed and swept, or announced and
  # skipped. What must not exist is a third branch that is quiet.
  WF="$REPO_ROOT/.github/workflows/pr-tests.yml"
  grep -q 'not armed' "$WF"
}

@test "with no --terms it USES .deident-terms when it is present" {
  cd "$WORK/repo"
  cp "$WORK/terms.txt" .deident-terms
  printf 'acmecorp again\n' > leak.md
  git add leak.md && git commit -q -m "chore: leak"
  run "$SCAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"leak.md"* ]]
}

@test "blank lines and # comments in the term file are ignored" {
  # A blank line as a grep pattern matches EVERY line of every file, which
  # would report the whole tree as a leak and teach the reader to ignore it.
  cd "$WORK/repo"
  printf '# the source project\n\nacmecorp\n\n' > "$WORK/commented.txt"
  run "$SCAN" --terms "$WORK/commented.txt"
  [ "$status" -eq 0 ]
}

@test "--list-terms is not a thing: the scanner never prints the terms it was given" {
  # Printing the list into a CI log would put the enumeration back in public,
  # which is the leak this split exists to prevent.
  run grep -nE 'cat[[:space:]]+"?\$(TERMS|TERM_FILE)' "$SCAN"
  [ "$status" -ne 0 ]
}

@test "a malformed term is a loud failure, never a clean sweep" {
  # grep answers "no match" with exit 1 and "your pattern is not a valid regular
  # expression" with exit 2. Both sweeps here end in `|| true`, so the two become
  # indistinguishable and one unescaped paren in a product name turns the whole
  # check into `clean — 0 hits` while it matched nothing at all.
  #
  # The content sweep cannot demux this after the fact even if it wanted to:
  # xargs collapses grep's 2 to its own generic failure code. So the pattern file
  # has to be validated ONCE, up front, before any sweep runs.
  cd "$WORK/repo"
  echo "acmecorp is named right here" > leak.md
  git add leak.md
  git commit -q -m "chore: add a real leak"

  printf 'acmecorp\nwidget(ron\n' > "$WORK/bad-terms.txt"
  run "$SCAN" --terms "$WORK/bad-terms.txt"
  [ "$status" -ne 0 ]
  [ "$status" -ne 1 ]                # not "found hits" — it could not look at all
  [[ "$output" != *"clean"* ]]       # and it must never claim cleanliness
  [[ "$output" == *"widget(ron"* ]]  # and it must name the term that broke
}

@test "a valid term file with no matches is still an ordinary clean pass" {
  # The other half: the validity probe must not turn every no-match run into a
  # failure. `clean` has to stay reachable.
  cd "$WORK/repo"
  run "$SCAN" --terms "$WORK/terms.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
}

@test "the scanner itself contains no project-specific string — it passes its own sweep" {
  # This is the whole point, and it is asserted against the REAL term list.
  # The scanner is swept exactly like any other file, with no carve-out, which
  # is the only version of this check that means anything.
  cd "$REPO_ROOT"
  if [ ! -f .temper/evidence/deident-terms.txt ]; then
    skip "no build-time term list present (expected on an adopter's clone)"
  fi
  run grep -n -i -E -f <(grep -vE '^[[:space:]]*(#|$)' .temper/evidence/deident-terms.txt) \
      tools/check-deidentified.sh
  [ "$status" -ne 0 ]
}

@test "the scanner carries no mechanism that would exempt any path from the sweep" {
  # Not a search for the WORDS "self-exclusion" — the script explains at length
  # why it has none, and that explanation is the point. What must not exist is
  # a working exclusion: a --exclude flag, a grep -v over the file list, or a
  # skip clause keyed on a path.
  run grep -nE '(--exclude|grep[[:space:]]+-v[[:space:]]).*(deident|\$0|tools/)' "$SCAN"
  [ "$status" -ne 0 ]
}
