#!/usr/bin/env bats
#
# Scenario: "No vendor name leaks into workflows, runbooks or prompts" (intent.md).
#
# WHY THIS FILE EXISTS.
#
# The scenario was listed as covered by `tools/check-deidentified.sh`, and it is not.
# That scanner is TERM-AGNOSTIC by design — it sweeps whatever term list it is handed,
# and the list an adopter hands it is their own former project's names. It knows nothing
# about model vendors, and it must not: baking a vendor list into it would give the
# scanner project-specific strings of its own, which is precisely the property
# `tests/deidentified.bats` exists to forbid.
#
# So the claim was true and unguarded — the worst combination, because the next person
# reads the checklist, believes a test is holding the line, and adds `runs-on` with a
# vendor's action in it. Provider-agnosticism is the requirement that outranks
# convenience everywhere it applies; a requirement with nothing asserting it decays into
# a preference.
#
# The rule: a workflow, a runbook or an agent prompt addresses a model by its ROLE —
# judge, execute, challenge. Vendor and model names live in exactly two places, the
# adapter that owns that vendor's command shape and the one config file an adopter edits.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

# Names that identify a specific vendor or model family. Deliberately NOT sourced from
# .temper/evidence/deident-terms.txt — that list is the source project's identifiers and
# is gitignored, so an adopter's clone would silently assert nothing.
VENDOR_PATTERN='anthropic|openai|chatgpt|\bgpt-[0-9]|\bclaude\b|claude-[a-z0-9]|\bgemini\b|\bcodex\b|\bopus\b|\bsonnet\b|\bhaiku\b|google-genai|glm-[0-9]|deepseek|mistral|llama'

# Where a vendor name is legitimate: the adapter that owns that vendor's invocation, and
# the single config file naming the provider. Everything else must be role-addressed.
allowed_path() {
  case "$1" in
    */tools/providers/*) return 0 ;;
    */.agents/config.yml) return 0 ;;
    *) return 1 ;;
  esac
}

# Collect hits under a directory, excluding the legitimate homes.
scan() {
  local dir="$1" f hits=""
  while IFS= read -r f; do
    allowed_path "$f" && continue
    local m
    m="$(grep -n -I -i -E "$VENDOR_PATTERN" "$f" 2>/dev/null || true)"
    [ -n "$m" ] && hits+="$f:"$'\n'"$m"$'\n'
  done < <(find "$dir" -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.md' \) 2>/dev/null)
  printf '%s' "$hits"
}

@test "no vendor or model name appears in .github/workflows/" {
  # A workflow reaching a vendor action directly is the lock-in that matters most:
  # every workflow must go through tools/run-agent.sh, which is the only thing that
  # knows which provider is configured.
  run scan "$REPO_ROOT/.github/workflows"
  [ -z "$output" ] || {
    echo "vendor names found in workflows:"
    echo "$output"
    false
  }
}

@test "no vendor or model name appears in docs/runbooks/" {
  # A runbook naming a vendor tells the operator to do something a fork on another
  # provider cannot do, and it is the last place anyone thinks to look for lock-in.
  run scan "$REPO_ROOT/docs/runbooks"
  [ -z "$output" ] || {
    echo "vendor names found in runbooks:"
    echo "$output"
    false
  }
}

@test "no vendor or model name appears in .agents/prompts/" {
  # The prompts are read by whichever CLI the adopter configured. A prompt naming a
  # vendor is a prompt that is subtly wrong for every other one.
  run scan "$REPO_ROOT/.agents/prompts"
  [ -z "$output" ] || {
    echo "vendor names found in agent prompts:"
    echo "$output"
    false
  }
}

@test "the guard has teeth: a planted vendor name in a workflow is caught" {
  # Without this, all three tests above pass just as happily against an empty pattern,
  # a broken find, or a scan() that silently returns nothing — the same vacuous-green
  # failure the whole harness-guard tier exists to prevent.
  PLANT="$REPO_ROOT/.github/workflows/zz-vendor-neutrality-probe.yml"
  printf 'name: probe\non: workflow_dispatch\njobs:\n  p:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo "model: claude-opus-4"\n' > "$PLANT"
  run scan "$REPO_ROOT/.github/workflows"
  rm -f "$PLANT"
  [ -n "$output" ]
  [[ "$output" == *"zz-vendor-neutrality-probe.yml"* ]]
}

@test "the legitimate homes are exempt, and genuinely contain what they should" {
  # The exemption must be real rather than theoretical: if the adapters stopped naming
  # their own vendor, the carve-out would be silently unnecessary and the next person
  # would widen it without noticing it had never been load-bearing.
  run grep -r -l -i -E "$VENDOR_PATTERN" "$REPO_ROOT/tools/providers"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "models are addressed by role in the config, not by vendor, outside the id fields" {
  # role_provider/judge|execute|challenge is the vocabulary every doc is supposed to use.
  run grep -n -E '^[[:space:]]*(judge|execute|challenge):' "$REPO_ROOT/.agents/config.yml"
  [ "$status" -eq 0 ]
}
