#!/usr/bin/env bash
# tools/lib/config.sh — THE ONLY PARSER for .agents/config.yml and floors.yml.
#
# Every other tool sources this and asks it; nothing else in the repo parses either YAML
# file directly. That is what lets a schema change land in one place instead of N.
# See .temper/specs/agent-sdlc-template/design.md section 2.2 (D1) for the rationale.
#
# Two readers, same contract: `yq` (mikefarah/yq v4) when it is on PATH, otherwise a
# restricted awk fallback. `--dry-run` (SC4) must work with no agent CLI installed at all,
# and `tools/init.sh` must make no network call (SC7) — a hard `yq` dependency would break
# both on a laptop that never installed it. The price of the fallback is a restriction on
# the config file's own shape (documented on config.yml itself and exercised by
# tests/config-reader.bats, which asserts both readers agree, byte for byte, on every
# documented path):
#   - two-space indent, no tabs
#   - no anchors, aliases, merge keys, multi-line scalars or flow maps in config.yml
#     (floors.yml is exempt — see floor_get below, it is read differently)
#   - list items are `- key: value` maps (only ledger.agents uses this) or `- scalar`
#   - comments start at column 0, or after two spaces on the same line as a value
#
# This file is meant to be SOURCED, not executed: `. tools/lib/config.sh`.
#
# Env overrides (used by tests and by callers that are not at the repo root):
#   AGENTS_CONFIG        — path to config.yml (default: <repo root>/.agents/config.yml)
#   FLOORS_CONFIG         — path to floors.yml  (default: <repo root>/floors.yml)
#   AGENTS_CONFIG_READER  — force "yq" or "awk", for the reader-agreement test

set -uo pipefail

_cfg_root() {
  # AGENTS_ROOT first, because `git rev-parse --show-toplevel` answers a DIFFERENT
  # question than "which copy of this harness am I part of". A caller that knows its
  # own location — run-agent.sh does, from BASH_SOURCE — sets AGENTS_ROOT and every
  # path below (config.yml, floors.yml, tools/providers/*.sh) resolves against that
  # one answer. Without it, a vendored copy nested inside another git-controlled repo
  # reads the OUTER repo's config while executing THIS copy's adapter: split-brain
  # resolution that surfaces as an argv naming a provider nobody configured here.
  #
  # The git fallback stays for standalone callers invoked from inside a checkout.
  if [ -n "${AGENTS_ROOT:-}" ]; then
    printf '%s\n' "$AGENTS_ROOT"
    return
  fi
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

_cfg_file() {
  printf '%s\n' "${AGENTS_CONFIG:-$(_cfg_root)/.agents/config.yml}"
}

_floors_file() {
  printf '%s\n' "${FLOORS_CONFIG:-$(_cfg_root)/floors.yml}"
}

_cfg_has_yq() {
  case "${AGENTS_CONFIG_READER:-}" in
    awk) return 1 ;;
    yq)  command -v yq >/dev/null 2>&1 ;;
    *)   command -v yq >/dev/null 2>&1 ;;
  esac
}

# ---------------------------------------------------------------------------
# cfg_assert_schema <file> <supported-int>
#   Every consumer calls this before its first read. Mismatch => exit 3, never a silent
#   upgrade — a template that rewrites a stranger's config without asking is the same
#   class of failure as a green run with a wrong answer.
# ---------------------------------------------------------------------------
_cfg_schema_of() {
  local file="$1"
  if _cfg_has_yq; then
    yq eval '.schema' "$file" 2>/dev/null
  else
    grep -E '^schema:' "$file" 2>/dev/null | head -n1 | sed -E 's/^schema:[[:space:]]*//; s/[[:space:]]*(#.*)?$//'
  fi
}

cfg_assert_schema() {
  local file="$1" supported="$2" have
  [ -f "$file" ] || { echo "cfg_assert_schema: $file not found" >&2; return 3; }
  have="$(_cfg_schema_of "$file")"
  if [ -z "$have" ] || [ "$have" = "null" ]; then
    echo "cfg_assert_schema: $file has no 'schema:' key" >&2
    return 3
  fi
  if [ "$have" != "$supported" ]; then
    echo "config schema $have is not supported by this tool (expects $supported) — see CHANGELOG.md \"Config schema $have → $supported\"" >&2
    return 3
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Internal: strip a same-line comment ("value  # note") and surrounding quotes.
# ---------------------------------------------------------------------------
_cfg_clean_scalar() {
  local rest="$1" ci
  case "$rest" in
    *' #'*) rest="${rest%% \#*}" ;;
  esac
  # trim trailing whitespace
  rest="$(printf '%s' "$rest" | sed -E 's/[[:space:]]+$//')"
  if [[ "$rest" == \"*\" ]] && [ "${#rest}" -ge 2 ]; then
    rest="${rest#\"}"
    rest="${rest%\"}"
  fi
  printf '%s' "$rest"
}

# ---------------------------------------------------------------------------
# Internal restricted-awk reader for a dotted scalar path in a nested-map-only YAML file
# (no lists in the traversed path). Exit 0 + prints the value (possibly empty string) if
# found; exit 1 if not found. This is the "restricted awk reader" the header describes.
# ---------------------------------------------------------------------------
_cfg_awk_get() {
  local file="$1" target="$2"
  awk -v target="$target" '
    function rtrim(s) { sub(/[ \t]+$/, "", s); return s }
    function unquote(s,   n) {
      n = length(s)
      if (n >= 2 && substr(s,1,1) == "\"" && substr(s,n,1) == "\"") return substr(s,2,n-2)
      return s
    }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^[ \t]*$/) next
      if (line ~ /^[ \t]*#/) next
      if (line ~ /^[ \t]*-([ \t]|$)/) next   # list items unsupported by this resolver

      indent = 0
      tmp = line
      while (substr(tmp,1,1) == " ") { indent++; tmp = substr(tmp,2) }
      if (tmp !~ /^[A-Za-z0-9_.-]+:/) next

      colon = index(tmp, ":")
      key = substr(tmp, 1, colon-1)
      rest = substr(tmp, colon+1)
      sub(/^[ \t]+/, "", rest)
      ci = index(rest, " #")
      if (ci > 0) rest = substr(rest, 1, ci-1)
      rest = rtrim(rest)
      rest = unquote(rest)

      while (depth > 0 && stack_indent[depth] >= indent) depth--

      if (rest == "") {
        depth++
        stack_key[depth] = key
        stack_indent[depth] = indent
      } else {
        path = ""
        for (i = 1; i <= depth; i++) path = path stack_key[i] "."
        path = path key
        if (path == target) { print rest; found = 1; exit }
      }
    }
    END { exit (found ? 0 : 1) }
  ' "$file"
}

# ---------------------------------------------------------------------------
# cfg_get <dotted.path> [default]
#   One scalar to stdout. Required (no default given) and absent => exit 3.
# ---------------------------------------------------------------------------
cfg_get() {
  local path="$1" have_default=0 default="" file val rc
  if [ "$#" -ge 2 ]; then have_default=1; default="$2"; fi
  file="$(_cfg_file)"
  if [ ! -f "$file" ]; then
    echo "cfg_get: $file not found" >&2
    return 3
  fi
  if _cfg_has_yq; then
    val="$(yq eval ".${path}" "$file" 2>/dev/null)"
    rc=$?
    if [ $rc -ne 0 ] || [ "$val" = "null" ]; then
      if [ $have_default -eq 1 ]; then printf '%s\n' "$default"; return 0; fi
      echo "cfg_get: required path '$path' not found in $file" >&2
      return 3
    fi
    printf '%s\n' "$val"
    return 0
  fi
  val="$(_cfg_awk_get "$file" "$path")"
  rc=$?
  if [ $rc -ne 0 ]; then
    if [ $have_default -eq 1 ]; then printf '%s\n' "$default"; return 0; fi
    echo "cfg_get: required path '$path' not found in $file" >&2
    return 3
  fi
  printf '%s\n' "$val"
  return 0
}

# ---------------------------------------------------------------------------
# cfg_agents — agent ids from ledger.agents, in RING ORDER, one per line.
#   THE list: ledger.sh validates against it, latest/trend iterate it,
#   agents-scheduled.yml builds its matrix from it, cfg_predecessor derives the ring from
#   it. No separate ring table anywhere (Decision D3).
# ---------------------------------------------------------------------------
cfg_agents() {
  local file rc
  file="$(_cfg_file)"
  [ -f "$file" ] || { echo "cfg_agents: $file not found" >&2; return 3; }
  if _cfg_has_yq; then
    yq eval '.ledger.agents[].id' "$file" 2>/dev/null
    return $?
  fi
  awk '
    /^ledger:/ { inledger = 1; next }
    inledger && /^[A-Za-z]/ { inledger = 0 }
    inledger && /^[ \t]{2}agents:/ { inagents = 1; next }
    inledger && inagents && /^[ \t]{2}[A-Za-z]/ && !/^[ \t]{2}agents:/ { inagents = 0 }
    inagents && /-[ \t]*id:/ {
      line = $0
      sub(/^.*-[ \t]*id:[ \t]*/, "", line)
      sub(/[ \t]*(#.*)?$/, "", line)
      print line
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# cfg_agent_field <agent-id> <field> — one field (role, prompt, schedule, enabled,
# max-age-hours) from a single entry in ledger.agents. Exit 1/nonzero if the agent or the
# field is absent, so callers can supply their own fallback (e.g. liveness.max-age-hours).
# ---------------------------------------------------------------------------
cfg_agent_field() {
  local id="$1" field="$2" file
  file="$(_cfg_file)"
  [ -f "$file" ] || { echo "cfg_agent_field: $file not found" >&2; return 3; }
  if _cfg_has_yq; then
    local val
    val="$(yq eval ".ledger.agents[] | select(.id == \"${id}\") | .${field}" "$file" 2>/dev/null)"
    if [ -z "$val" ] || [ "$val" = "null" ]; then return 1; fi
    printf '%s\n' "$val"
    return 0
  fi
  awk -v target_id="$id" -v field="$field" '
    /^ledger:/ { inledger = 1; next }
    inledger && /^[A-Za-z]/ { inledger = 0 }
    inledger && /^[ \t]{2}agents:/ { inagents = 1; next }
    inledger && inagents && /^[ \t]{2}[A-Za-z]/ && !/^[ \t]{2}agents:/ { inagents = 0 }
    inagents && /-[ \t]*id:/ {
      line = $0
      sub(/^.*-[ \t]*id:[ \t]*/, "", line)
      sub(/[ \t]*(#.*)?$/, "", line)
      active = (line == target_id) ? 1 : 0
      if (field == "id" && active) { print line; found = 1; exit }
      next
    }
    inagents && active {
      line = $0
      pat = "^[ \t]+" field ":"
      if (line ~ pat) {
        val = line
        sub(pat, "", val)
        sub(/^[ \t]+/, "", val)
        sub(/[ \t]*(#.*)?$/, "", val)
        gsub(/^"|"$/, "", val)
        print val
        found = 1
        exit
      }
    }
    END { exit (found ? 0 : 1) }
  ' "$file"
}

# ---------------------------------------------------------------------------
# cfg_list <dotted.path> — one item per line, for a scalar list. Fallback reader only
# knows the one list the shipped config carries; extend deliberately, not accidentally.
# ---------------------------------------------------------------------------
cfg_list() {
  local path="$1" file
  file="$(_cfg_file)"
  [ -f "$file" ] || { echo "cfg_list: $file not found" >&2; return 3; }
  if _cfg_has_yq; then
    yq eval ".${path}[]" "$file" 2>/dev/null
    return $?
  fi
  case "$path" in
    ledger.agents) cfg_agents ;;
    *)
      echo "cfg_list: fallback reader does not support list path '$path'" >&2
      return 3
      ;;
  esac
}

# ---------------------------------------------------------------------------
# cfg_predecessor <agent> — the previous agent in ledger.agents, wrapping at the top.
# The watcher ring's whole definition (Decision D3): reorder the agents, reorder the ring.
# ---------------------------------------------------------------------------
cfg_predecessor() {
  local target="$1" id
  local -a ids=()
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    ids+=("$id")
  done < <(cfg_agents)
  local n="${#ids[@]}" i
  if [ "$n" -eq 0 ]; then
    echo "cfg_predecessor: no agents configured" >&2
    return 3
  fi
  for (( i = 0; i < n; i++ )); do
    if [ "${ids[$i]}" = "$target" ]; then
      local pi=$(( (i - 1 + n) % n ))
      printf '%s\n' "${ids[$pi]}"
      return 0
    fi
  done
  echo "cfg_predecessor: unknown agent '$target'" >&2
  return 3
}

# ---------------------------------------------------------------------------
# adapter_status <provider> — "verified" | "unverified". THE only implementation; init.sh
# and `run-agent.sh --adapter-status` both call this. No lookup table anywhere (D4):
# a second list is stale the moment someone finishes an adapter, and stale in the
# direction that ships a live workflow calling a broken CLI.
#
# Matched by exactly one regex, defined once, here: ^ADAPTER_STATUS=(verified|unverified)
# — the value must start the line at column 0 immediately after the `=`; a trailing
# same-line comment (design.md's own worked example carries one, to say what the line
# means) is permitted and stripped, so the match is on the ASSIGNMENT, not the whole
# line verbatim. Exit 3 if the provider file is missing, or has zero or more than one
# matching line — ambiguity here decides whether the steward ships live, so it may not
# be resolved by "take the first match".
# ---------------------------------------------------------------------------
adapter_status() {
  local provider="$1" file matches n val
  file="$(_cfg_root)/tools/providers/${provider}.sh"
  [ -f "$file" ] || { echo "adapter_status: no such provider '$provider' ($file)" >&2; return 3; }
  matches="$(grep -E '^ADAPTER_STATUS=(verified|unverified)([[:space:]]|$)' "$file" || true)"
  n="$(printf '%s\n' "$matches" | grep -c . || true)"
  if [ "$n" -ne 1 ]; then
    echo "adapter_status: '$provider' declares $n ADAPTER_STATUS lines, expected exactly 1" >&2
    return 3
  fi
  val="${matches#ADAPTER_STATUS=}"
  val="${val%%[[:space:]]*}"
  printf '%s\n' "$val"
}

adapter_auth_hint() { # HOW TO OBTAIN this provider's credential, in prose.
                      # Vendor-specific by nature, so it lives in the adapter — the one
                      # place a vendor name is legitimate — rather than in a runbook that
                      # is supposed to read the same on every provider.
                      # Absent is not fatal and never prints to stderr: a missing hint
                      # must not turn a credential problem into a second, louder failure.
  local provider="$1" file matches val
  file="$(_cfg_root)/tools/providers/${provider}.sh"
  [ -f "$file" ] || return 0
  matches="$(grep -E '^ADAPTER_AUTH_HINT=' "$file" 2>/dev/null | head -1 || true)"
  [ -z "$matches" ] && return 0
  val="${matches#ADAPTER_AUTH_HINT=}"
  val="${val#\'}"; val="${val%\'}"
  printf '%s\n' "$val"
}

adapter_docs_url() {
  local provider="$1" file matches n val
  file="$(_cfg_root)/tools/providers/${provider}.sh"
  [ -f "$file" ] || { echo "adapter_docs_url: no such provider '$provider' ($file)" >&2; return 3; }
  matches="$(grep -E '^ADAPTER_DOCS_URL=' "$file" || true)"
  n="$(printf '%s\n' "$matches" | grep -c . || true)"
  if [ "$n" -ne 1 ]; then
    echo "adapter_docs_url: '$provider' declares $n ADAPTER_DOCS_URL lines, expected exactly 1" >&2
    return 3
  fi
  val="${matches#ADAPTER_DOCS_URL=}"
  val="${val%%[[:space:]]*}"
  printf '%s\n' "$val"
}

# ---------------------------------------------------------------------------
# floor_get <dotted.key> — a floors.yml value, or the literal string "unset".
#
# floors.yml keys are themselves LITERAL strings containing dots (e.g. the map key is
# exactly "backend.coverage.line") — this is not a nested-map path like cfg_get's, so it
# is read differently. The entry may be a one-line flow map (uncalibrated) or a multi-line
# block (calibrated, with provenance) — see design.md section 7. Both are handled.
# ---------------------------------------------------------------------------
floor_get() {
  local key="$1" file
  file="$(_floors_file)"
  [ -f "$file" ] || { echo "floor_get: $file not found" >&2; return 3; }
  if _cfg_has_yq; then
    yq eval ".floors[\"${key}\"].value" "$file" 2>/dev/null
    return $?
  fi
  awk -v key="$key" '
    BEGIN { found = 0; inblock = 0 }
    {
      line = $0
      if (inblock) {
        if (line ~ /^[ \t]{2}[A-Za-z0-9_.-]+:/) { inblock = 0 }
        else {
          if (match(line, /value:[ \t]*/)) {
            v = substr(line, RSTART + RLENGTH)
            sub(/[ \t]*(#.*)?$/, "", v)
            gsub(/^"|"$/, "", v)
            print v
            found = 1
            exit
          }
          next
        }
      }
      pat = "^[ \t]{2}" key ":"
      if (line ~ pat) {
        rest = line
        sub(pat, "", rest)
        sub(/^[ \t]+/, "", rest)
        if (rest ~ /^\{/) {
          if (match(rest, /value:[ \t]*/)) {
            v = substr(rest, RSTART + RLENGTH)
            sub(/[ \t]*[,}].*$/, "", v)
            gsub(/^"|"$/, "", v)
            print v
            found = 1
            exit
          }
        } else if (rest == "") {
          inblock = 1
        }
      }
    }
    END { exit (found ? 0 : 1) }
  ' "$file"
}
