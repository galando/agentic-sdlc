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

@test "placeholder check passes loudly pre-init, and strictly clean post-init" {
  # The shipped tree is the uninitialised state; an adopted tree is the strict state.
  # Both must exit 0 on a clean tree — what changes is which message proves the check
  # actually looked.
  run "$REPO_ROOT/tools/check-placeholders.sh"
  [ "$status" -eq 0 ]
  if grep -qF '{{PROVIDER}}' "$REPO_ROOT/.agents/config.yml"; then
    [[ "$output" == *"NOT a failure"* ]]
    [[ "$output" == *"init.sh"* ]]
  else
    [[ "$output" == *"clean"* ]]
  fi
}

@test "placeholder check announces itself in CI, where the reader actually looks" {
  # Printed prose scrolls past in a log. An annotation is what surfaces on the run —
  # and on an adopted tree the annotation must be ABSENT, or every CI run carries a
  # stale "not initialised" warning forever.
  run env GITHUB_ACTIONS=true "$REPO_ROOT/tools/check-placeholders.sh"
  [ "$status" -eq 0 ]
  if grep -qF '{{PROVIDER}}' "$REPO_ROOT/.agents/config.yml"; then
    [[ "$output" == *"::warning title=Template not initialised::"* ]]
  else
    [[ "$output" != *"Template not initialised"* ]]
  fi
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

backend_pom() {
  # Layout-aware: the template ships the product at examples/backend; an adopted
  # tree carries it at backend/ (tools/adopt-layout.sh). Neither present yet — the
  # window between deleting the example and wiring a product in — is a skip, not
  # a failure: there is no pom for the claim to be about.
  if [ -f "$REPO_ROOT/examples/backend/pom.xml" ]; then
    echo "$REPO_ROOT/examples/backend/pom.xml"
  elif [ -f "$REPO_ROOT/backend/pom.xml" ]; then
    echo "$REPO_ROOT/backend/pom.xml"
  else
    return 1
  fi
}

@test "surefire is told, in the pom, to leave the docker and live tags to failsafe" {
  pom="$(backend_pom)" || skip "no backend pom in this tree yet"
  run grep -A20 'maven-surefire-plugin' "$pom"
  [[ "$output" == *"<excludedGroups>docker,live</excludedGroups>"* ]]
}

@test "the flyway plugin is declared and version-pinned, not resolved by prefix" {
  # `mvn flyway:migrate` with no plugin declaration resolves whatever the prefix points
  # at today, with no JDBC driver and no connection details, and fails on contact with the
  # database — reporting migration drift that does not exist.
  pom="$(backend_pom)" || skip "no backend pom in this tree yet"
  run grep -A3 'flyway-maven-plugin' "$pom"
  [ "$status" -eq 0 ]
  [[ "$output" == *'${flyway.version}'* ]]
}

@test "migration validation gets its connection details through env, not the command line" {
  run grep -A12 'Apply migrations and validate' "$REPO_ROOT/.github/workflows/pr-validation.yml"
  [[ "$output" == *"FLYWAY_URL:"* ]]
  [[ "$output" == *"FLYWAY_PASSWORD:"* ]]
}
