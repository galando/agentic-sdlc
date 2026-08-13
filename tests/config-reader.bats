#!/usr/bin/env bats
#
# Gate: the yq reader and the restricted-awk fallback reader in tools/lib/config.sh must
# agree, byte for byte, on every documented path. .agents/config.yml is written to the
# restricted subset (two-space indent, no anchors/aliases/flow maps, list items are
# `- key: value` maps or scalars) precisely so this can hold — see the header comment on
# both config.sh and config.yml, and design.md section 2.2 (Decision D1).
#
# `--dry-run` (SC4) has to work with no agent CLI installed at all, and tools/init.sh must
# make no network call (SC7) — a hard `yq` dependency would break both on a laptop that
# never installed it. The awk fallback is what makes that true; this file is what makes
# the fallback trustworthy instead of merely present.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB="$REPO_ROOT/tools/lib/config.sh"
CONFIG="$REPO_ROOT/.agents/config.yml"

# The `config reader:` tests force AGENTS_CONFIG_READER=yq for one half of each
# comparison. When no usable mikefarah/yq is on PATH that force is refused and the
# library answers from awk instead, which would quietly turn "both readers agree"
# into awk agreeing with itself — every assertion still green, nothing compared.
# A suite that cannot run its own subject says so rather than passing.
#
# Scoped by name on purpose: the cfg_assert_schema tests below do NOT force a
# reader, so they are meaningful under either one and must keep running here.
setup() {
  case "$BATS_TEST_DESCRIPTION" in
    "config reader: "*)
      AGENTS_CONFIG_READER=yq bash -c ". '$LIB'; _cfg_has_yq" 2>/dev/null ||
        skip "no usable mikefarah/yq v4 on PATH — no second reader for awk to agree with"
      ;;
  esac
}

both_readers_agree() {
  local path="$1"
  local yq_val awk_val yq_rc awk_rc
  yq_val="$(AGENTS_CONFIG_READER=yq bash -c ". '$LIB'; cfg_get '$path'" 2>/dev/null)"
  yq_rc=$?
  awk_val="$(AGENTS_CONFIG_READER=awk bash -c ". '$LIB'; cfg_get '$path'" 2>/dev/null)"
  awk_rc=$?
  [ "$yq_rc" -eq "$awk_rc" ] || { echo "rc mismatch for $path: yq=$yq_rc awk=$awk_rc"; return 1; }
  [ "$yq_val" = "$awk_val" ] || { echo "value mismatch for $path: yq=[$yq_val] awk=[$awk_val]"; return 1; }
}

@test "config reader: both readers agree on schema" {
  run both_readers_agree "schema"
  [ "$status" -eq 0 ]
}

@test "config reader: both readers agree on provider" {
  run both_readers_agree "provider"
  [ "$status" -eq 0 ]
}

@test "config reader: both readers agree on models.judge / execute / challenge" {
  run both_readers_agree "models.judge"
  [ "$status" -eq 0 ]
  run both_readers_agree "models.execute"
  [ "$status" -eq 0 ]
  run both_readers_agree "models.challenge"
  [ "$status" -eq 0 ]
}

@test "config reader: both readers agree on role_provider.challenge" {
  run both_readers_agree "role_provider.challenge"
  [ "$status" -eq 0 ]
}

@test "config reader: both readers agree on auth.<provider>.* including hyphenated keys" {
  run both_readers_agree "auth.claude-code.mode"
  [ "$status" -eq 0 ]
  run both_readers_agree "auth.claude-code.token_secret"
  [ "$status" -eq 0 ]
  run both_readers_agree "auth.compatible-endpoint.required"
  [ "$status" -eq 0 ]
  run both_readers_agree "auth.compatible-endpoint.base_url"
  [ "$status" -eq 0 ]
}

@test "config reader: both readers agree on mention.variable / default" {
  run both_readers_agree "mention.variable"
  [ "$status" -eq 0 ]
  run both_readers_agree "mention.default"
  [ "$status" -eq 0 ]
}

@test "config reader: both readers agree on alerts.*" {
  run both_readers_agree "alerts.channel"
  [ "$status" -eq 0 ]
  run both_readers_agree "alerts.severity_floor"
  [ "$status" -eq 0 ]
}

@test "config reader: both readers agree on liveness.*" {
  run both_readers_agree "liveness.max-age-hours"
  [ "$status" -eq 0 ]
  run both_readers_agree "liveness.staleness-hours"
  [ "$status" -eq 0 ]
}

@test "config reader: both readers agree on ledger.branch / identity.*" {
  run both_readers_agree "ledger.branch"
  [ "$status" -eq 0 ]
  run both_readers_agree "ledger.identity.name"
  [ "$status" -eq 0 ]
  run both_readers_agree "ledger.identity.email"
  [ "$status" -eq 0 ]
}

@test "config reader: both readers agree on spec_contract" {
  run both_readers_agree "spec_contract"
  [ "$status" -eq 0 ]
}

@test "config reader: both readers agree a missing required key is an error (exit 3)" {
  run both_readers_agree "this.path.does.not.exist"
  [ "$status" -eq 0 ]
  yq_rc="$(AGENTS_CONFIG_READER=yq bash -c ". '$LIB'; cfg_get this.path.does.not.exist >/dev/null 2>&1; echo \$?")"
  [ "$yq_rc" -eq 3 ]
}

@test "config reader: both readers agree on a default for a missing key" {
  yq_val="$(AGENTS_CONFIG_READER=yq bash -c ". '$LIB'; cfg_get nope.nope default-val")"
  awk_val="$(AGENTS_CONFIG_READER=awk bash -c ". '$LIB'; cfg_get nope.nope default-val")"
  [ "$yq_val" = "default-val" ]
  [ "$awk_val" = "default-val" ]
}

@test "config reader: cfg_agents returns the ring in list order under both readers" {
  yq_val="$(AGENTS_CONFIG_READER=yq bash -c ". '$LIB'; cfg_agents" | tr '\n' ' ')"
  awk_val="$(AGENTS_CONFIG_READER=awk bash -c ". '$LIB'; cfg_agents" | tr '\n' ' ')"
  [ "$yq_val" = "$awk_val" ]
  [ "$yq_val" = "health quality audit chief-of-staff challenger docs groomer testgap deps release " ]
}

@test "config reader: cfg_predecessor skips disabled agents and wraps, under both readers" {
  # A disabled agent writes no ledger entries, so a ring that watches one
  # escalates forever — exactly the state the enable-one-at-a-time rollout
  # spends its first weeks in. The ring is therefore "previous ENABLED agent,
  # wrapping"; an absent enabled field counts as in the ring.
  fixture="$BATS_TEST_TMPDIR/ring.yml"
  cat > "$fixture" <<'EOF'
schema: 1
ledger:
  branch: agent-ledger
  agents:
    - id: alpha
      enabled: true
    - id: beta
      enabled: false
    - id: gamma
      enabled: true
    - id: delta
      enabled: false
EOF
  # gamma's list-predecessor beta is disabled -> skip to alpha.
  for reader in yq awk; do
    val="$(AGENTS_CONFIG="$fixture" AGENTS_CONFIG_READER=$reader bash -c ". '$LIB'; cfg_predecessor gamma")"
    [ "$val" = "alpha" ]
  done
  # alpha wraps at the top, past disabled delta and beta, to gamma.
  for reader in yq awk; do
    val="$(AGENTS_CONFIG="$fixture" AGENTS_CONFIG_READER=$reader bash -c ". '$LIB'; cfg_predecessor alpha")"
    [ "$val" = "gamma" ]
  done
}

@test "config reader: cfg_predecessor with no other enabled agent exits 4, never invents one" {
  # The shipped config is exactly this state: every agent starts enabled: false.
  # A manufactured predecessor here would be a liveness check green against an
  # agent that is switched off by design — exit 4 is the distinct "nothing to
  # watch" answer the caller turns into an honest green.
  for reader in yq awk; do
    run env AGENTS_CONFIG_READER=$reader bash -c ". '$LIB'; cfg_predecessor health"
    [ "$status" -eq 4 ]
    [[ "$output" == *"no other enabled agent"* ]]
  done
}

@test "cfg_assert_schema passes on the shipped config" {
  run bash -c ". '$LIB'; cfg_assert_schema '$CONFIG' 1"
  [ "$status" -eq 0 ]
}

@test "cfg_assert_schema fails loudly on an unsupported schema" {
  run bash -c ". '$LIB'; cfg_assert_schema '$CONFIG' 99"
  [ "$status" -eq 3 ]
  [[ "$output" == *"not supported"* ]]
  [[ "$output" == *"CHANGELOG.md"* ]]
}

# ---------------------------------------------------------------------------
# `yq` names two different programs and only one of them is this one.
# kislyuk/yq — the Python jq wrapper, and what `apt-get install yq` gives you on
# Debian and Ubuntu — has no `eval` subcommand. A presence-only check (`command -v
# yq`) accepts it, every read then fails, and cfg_get reports "required path 'x'
# not found" about a key sitting right there in the file. Right config, wrong
# error, and an awk reader on hand the whole time that would have answered.
# ---------------------------------------------------------------------------

@test "the yq probe tests behaviour, not the name on PATH" {
  # A `yq` that exists and cannot do the job must not be selected. Shadow PATH with
  # a stub that behaves like the Python one: exits non-zero on `eval`.
  local shim="$BATS_TEST_TMPDIR/shim"
  mkdir -p "$shim"
  printf '#!/bin/sh\nexit 2\n' > "$shim/yq"
  chmod +x "$shim/yq"

  run env PATH="$shim:$PATH" AGENTS_CONFIG_READER= bash -c ". '$LIB'; _cfg_has_yq"
  [ "$status" -ne 0 ]
}

@test "a wrong-flavour yq falls back to awk and still reads the config correctly" {
  # The payoff: the value comes back, rather than a lie about a missing key.
  local shim="$BATS_TEST_TMPDIR/shim2"
  mkdir -p "$shim"
  printf '#!/bin/sh\nexit 2\n' > "$shim/yq"
  chmod +x "$shim/yq"

  run env PATH="$shim:$PATH" AGENTS_CONFIG="$CONFIG" bash -c ". '$LIB'; cfg_get schema"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "forcing the yq reader when yq is unusable says so instead of silently using awk" {
  # Otherwise the reader-agreement tests above compare awk with awk and pass.
  local shim="$BATS_TEST_TMPDIR/shim3"
  mkdir -p "$shim"
  printf '#!/bin/sh\nexit 2\n' > "$shim/yq"
  chmod +x "$shim/yq"

  run env PATH="$shim:$PATH" AGENTS_CONFIG_READER=yq bash -c ". '$LIB'; _cfg_has_yq"
  [ "$status" -ne 0 ]
  [[ "$output" == *"kislyuk"* ]]
}
