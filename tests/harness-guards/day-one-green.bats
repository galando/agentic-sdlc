#!/usr/bin/env bats
#
# Scenario: "A fresh instantiation is green on day one" (intent.md).
#
# WHY THIS FILE EXISTS.
#
# Every one of these was found by a real Actions run on the first pull request this
# template ever opened, and every one of them made an UNTOUCHED repository look broken.
# That is the failure that ends adoption: somebody clicks "Use this template", sees red
# CI before they have typed anything, concludes the thing does not work, and deletes it.
# Local testing cannot catch these — they only appear when the workflows actually run
# against a tree where tools/init.sh has not been run yet.
#
# The rule they all encode: NOT-YET-CONFIGURED IS A STATE TO ANNOUNCE, NOT TO FAIL ON.
# It has to stay loud, though. A check that goes quiet is how a genuinely unresolved
# placeholder ships six months later.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

@test "placeholder check passes, loudly, while the template is uninitialised" {
  # The shipped tree IS the uninitialised state: .agents/config.yml still holds tokens.
  run "$REPO_ROOT/tools/check-placeholders.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT a failure"* ]]
  [[ "$output" == *"init.sh"* ]]
}

@test "placeholder check announces itself in CI, where the reader actually looks" {
  # Printed prose scrolls past in a log. An annotation is what surfaces on the run.
  run env GITHUB_ACTIONS=true "$REPO_ROOT/tools/check-placeholders.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning title=Template not initialised::"* ]]
}

@test "placeholder check turns STRICT the moment the config is filled in" {
  # Without this the fix is indistinguishable from deleting the gate: it would pass
  # forever, including on the configured repository where an unresolved token is real.
  SCRATCH="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$SCRATCH"
  cp -R "$REPO_ROOT"/.agents "$REPO_ROOT"/tools "$SCRATCH/"
  cd "$SCRATCH"
  git init -q .
  git config user.name t; git config user.email t@example.invalid

  # Resolve the config (what init.sh does), and leave a token elsewhere.
  sed -i.bak 's/{{[A-Z][A-Z0-9_]*}}/resolved/g' .agents/config.yml && rm -f .agents/config.yml.bak
  mkdir -p docs
  printf 'a live {{PRODUCT_NAME}} token\n' > docs/thing.md
  git add -A

  run "$SCRATCH/tools/check-placeholders.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRODUCT_NAME"* ]]
}

@test "the agent workflows treat an unconfigured provider as inert, never as an error" {
  # `adapter_status` exits non-zero when no adapter file resolves. Under `bash -e` that
  # took the whole job down. Both call sites must tolerate it and set enabled=false.
  for wf in review.yml steward.yml; do
    run grep -c 'adapter_status "$provider" 2>/dev/null || true' "$REPO_ROOT/.github/workflows/$wf"
    [ "$output" -ge 1 ]
    run grep -c 'cfg_get role_provider.judge 2>/dev/null || true' "$REPO_ROOT/.github/workflows/$wf"
    [ "$output" -ge 1 ]
    # And it must say so where the reader looks, not fail silently into a skip.
    run grep -c 'not configured::' "$REPO_ROOT/.github/workflows/$wf"
    [ "$output" -ge 1 ]
  done
}

@test "the integration job does not pass a tag filter that surefire also reads" {
  # -Dgroups= is honoured by surefire AND failsafe. Passing it to select the docker-tagged
  # integration tests also told surefire to run only docker-tagged unit tests, so the
  # acceptance @Suite discovered nothing and failed the build. The routing belongs in
  # pom.xml, where each plugin gets its own.
  # Comment lines are allowed to NAME the flag — that is how the lesson survives. Only
  # a live command line is a regression, so strip comments before looking.
  run bash -c "grep -vE '^[[:space:]]*#' '$REPO_ROOT/.github/workflows/pr-tests.yml' | grep -n 'Dgroups='"
  [ "$status" -ne 0 ]
}

@test "surefire is told, in the pom, to leave the docker and live tags to failsafe" {
  run grep -A20 'maven-surefire-plugin' "$REPO_ROOT/examples/backend/pom.xml"
  [[ "$output" == *"<excludedGroups>docker,live</excludedGroups>"* ]]
}

@test "the flyway plugin is declared and version-pinned, not resolved by prefix" {
  # `mvn flyway:migrate` with no plugin declaration resolves whatever the prefix points
  # at today, with no JDBC driver and no connection details, and fails on contact with the
  # database — reporting migration drift that does not exist.
  run grep -A3 'flyway-maven-plugin' "$REPO_ROOT/examples/backend/pom.xml"
  [ "$status" -eq 0 ]
  [[ "$output" == *'${flyway.version}'* ]]
}

@test "migration validation gets its connection details through env, not the command line" {
  run grep -A12 'Apply migrations and validate' "$REPO_ROOT/.github/workflows/pr-validation.yml"
  [[ "$output" == *"FLYWAY_URL:"* ]]
  [[ "$output" == *"FLYWAY_PASSWORD:"* ]]
}
