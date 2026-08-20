#!/usr/bin/env bash
# Agent ledger read/write helper. See docs/runbooks/agent-ledgers.md.
#
# State lives as one JSON object per line in ledger/<agent>.jsonl on the
# `agent-ledger` orphan branch — NOT in issue comments, and never on the default
# branch (AGENTS.md guardrail 2 forbids agents pushing there, which is exactly
# what makes "instruction vs. old agent chatter" decidable by branch protection
# instead of by a naming convention agents are trusted to honour).
#
# Reads are cheap on purpose: an agent loads ~2 KB of its own history at session
# start instead of paginating an issue thread. Writes go through a
# fetch-append-push retry so two agents finishing at once cannot lose an entry.
set -euo pipefail

BRANCH="${LEDGER_BRANCH:-agent-ledger}"
LEDGER_TMP=""

die() { echo "ledger.sh: $*" >&2; exit 1; }

need_jq() { command -v jq >/dev/null 2>&1 || die "jq is required"; }

# ---------------------------------------------------------------------------
# The agent list is CONFIG-DRIVEN, never hard-coded here.
#
# `ledger.agents[].id` in .agents/config.yml is THE list: ledger.sh validates
# against it, `latest` iterates it, agents-scheduled.yml builds its matrix from
# it, and the watcher ring's predecessor is simply the previous entry in it.
# A second list in this file would be a second source of truth and would drift
# the moment someone adds an agent.
#
# Resolution order, and why each step exists:
#   1. $LEDGER_AGENTS       — explicit override. This is what lets the round-trip
#                             test drive a scratch repository that has no config
#                             file, and what lets an operator run a one-off
#                             against an agent not yet in the config.
#   2. tools/lib/config.sh  — THE parser (see the design's single-parser rule).
#                             Nothing else in the repo may parse config.yml.
#   3. fail loudly          — never a built-in default. A silent fallback list
#                             would validate against agents that do not exist and
#                             report "(no entries)" for agents that do, which is
#                             indistinguishable from a dead agent. Absence must
#                             be the signal, so absence of CONFIG must be an error.
#
# NOTE: this must run in the CALLER's checkout, before cmd_append's throwaway
# clone. The ledger orphan branch does not contain .agents/config.yml, so
# resolving the list inside the clone would find nothing.
# ---------------------------------------------------------------------------
AGENTS=""
resolve_agents() {
  [ -n "$AGENTS" ] && return 0

  if [ -n "${LEDGER_AGENTS:-}" ]; then
    AGENTS="$LEDGER_AGENTS"
    return 0
  fi

  local root lib
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  lib="$root/tools/lib/config.sh"
  if [ -f "$lib" ]; then
    # shellcheck source=/dev/null
    . "$lib"
    AGENTS="$(cfg_agents | tr '\n' ' ')"
    [ -n "${AGENTS// /}" ] || die "no agents configured in .agents/config.yml (ledger.agents)"
    return 0
  fi

  die "cannot resolve the agent list: no \$LEDGER_AGENTS and no tools/lib/config.sh.
     The list lives at ledger.agents[].id in .agents/config.yml. Set LEDGER_AGENTS
     to a space-separated list to run against a repository without one."
}

check_agent() {
  resolve_agents
  local a="$1" known
  for known in $AGENTS; do [ "$a" = "$known" ] && return 0; done
  die "unknown agent '$a' (expected one of: $AGENTS)"
}

# Print the ledger file for an agent from the remote branch, or nothing if absent.
# Never checks the branch out: these commands run inside a session working on some
# other branch, and switching would clobber the agent's actual work.
show_file() {
  git show "origin/${BRANCH}:ledger/$1.jsonl" 2>/dev/null || true
}

cmd_read() {
  local agent="${1:-}" n="${2:-14}"
  [ -n "$agent" ] || die "usage: ledger.sh read <agent> [n]"
  check_agent "$agent"
  git fetch -q origin "$BRANCH" 2>/dev/null || true
  show_file "$agent" | tail -n "$n"
}

# Newest entry per agent. This is the watcher-ring check in one call instead of a
# separate paginated read per agent.
#
# An agent with no entries still prints a line. Absence is the signal the ring
# exists to detect, so an agent that quietly vanished from the output would defeat
# the whole mechanism — "(no entries)" and "not listed" must never look the same.
cmd_latest() {
  need_jq
  resolve_agents
  git fetch -q origin "$BRANCH" 2>/dev/null || true
  local agent last
  for agent in $AGENTS; do
    last="$(show_file "$agent" | tail -n 1)"
    if [ -z "$last" ]; then
      printf '%-16s %s\n' "$agent" "(no entries)"
    else
      printf '%-16s %s  %s\n' "$agent" \
        "$(printf '%s' "$last" | jq -r '.date')" \
        "$(printf '%s' "$last" | jq -r '.verdict')"
    fi
  done
}

# Print a metric's series so trends are arithmetic rather than recalled from prose.
# "Down more than N points since the last audit" is a rule you can evaluate; "it
# feels worse than last week" is not.
cmd_trend() {
  need_jq
  local agent="${1:-}" metric="${2:-}" n="${3:-14}"
  [ -n "$agent" ] && [ -n "$metric" ] || die "usage: ledger.sh trend <agent> <metric> [n]"
  check_agent "$agent"
  git fetch -q origin "$BRANCH" 2>/dev/null || true
  show_file "$agent" | tail -n "$n" \
    | jq -r --arg m "$metric" 'select(.metrics[$m] != null) | "\(.date) \(.metrics[$m])"'
}

cmd_append() {
  need_jq
  local agent="${1:-}" entry="${2:-}" narrative="${3:-}"
  [ -n "$agent" ] && [ -n "$entry" ] || die "usage: ledger.sh append <agent> <json> [narrative-file]"
  check_agent "$agent"

  # Validate BEFORE cloning anything. A malformed entry should cost nothing.
  printf '%s' "$entry" | jq -e . >/dev/null 2>&1 || die "entry is not valid JSON"
  local field
  for field in date verdict summary; do
    printf '%s' "$entry" | jq -e --arg f "$field" 'has($f)' >/dev/null \
      || die "entry is missing required field '$field'"
  done
  printf '%s' "$entry" | jq -e '.verdict | test("^(green|amber|red)$")' >/dev/null \
    || die "verdict must be green, amber or red"

  # The hygiene agent's rotation state, validated at the WRITE and not the
  # read: nothing downstream ever rejects this value — the agent's next run
  # just finds nothing it recognises, defaults back to dead-code, and ships
  # plausible pull requests for one half of its job forever, with no error
  # anywhere. A state field an agent's own next run branches on gets an enum
  # check here, where failing costs one re-run instead of a silent permanent
  # derailment.
  if [ "$agent" = "hygiene" ]; then
    printf '%s' "$entry" | jq -e '(.focus // "none") | test("^(dead-code|duplication|none)$")' >/dev/null \
      || die "hygiene entries carry focus: dead-code | duplication | none — it is the rotation state the next run branches on"
  fi

  # `.date` REACHES A FILE PATH, so its shape is a safety property and not a
  # formatting preference. The narrative below lands at
  # `ledger/<agent>/<date>.md`, and `has("date")` alone lets any string through
  # to that interpolation.
  #
  # What a traversal value costs is worse than the write itself. `cp` puts the
  # file outside the clone; `git add` then fails with "outside repository"; that
  # failure is swallowed by the subshell that the five-attempt retry loop wraps;
  # and the entry that eventually reaches the branch carries a `narrative` field
  # pointing at a file that is not on it. Wrong data in the one record this
  # system treats as authoritative, and exit 0 the whole way — the ledger's
  # entire value is that it is the record nothing silently rewrites.
  #
  # Checked here, with the other cheap validations, so a bad entry costs no
  # clone. `type == "string"` first because jq's `and` short-circuits and
  # `test()` on a number is an error rather than a false.
  printf '%s' "$entry" \
    | jq -e '.date | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")' >/dev/null 2>&1 \
    || die "date must be a YYYY-MM-DD string (it is interpolated into a file path)"

  local narrative_src="" narrative_rel=""
  if [ -n "$narrative" ]; then
    [ -f "$narrative" ] || die "narrative file '$narrative' does not exist"
    # The argument names a SOURCE file anywhere on disk; the destination is always
    # ledger/<agent>/<date>.md inside the branch. Deriving it rather than trusting
    # the argument keeps the layout uniform and stops an absolute path being handed
    # to `git add`, which fails as "outside repository".
    narrative_src="$(cd "$(dirname "$narrative")" && pwd)/$(basename "$narrative")"
    narrative_rel="ledger/${agent}/$(printf '%s' "$entry" | jq -r '.date').md"
    entry="$(printf '%s' "$entry" | jq -c --arg p "$narrative_rel" '.narrative = $p')"
  fi
  # Compact to exactly one line: the file's whole contract is one JSON object per line.
  entry="$(printf '%s' "$entry" | jq -c --arg a "$agent" '. + {agent: $a}')"

  # The commit identity is the adopter's, and it is a placeholder rather than a
  # value, because a real-looking address in a template is an address somebody's
  # mail server will eventually try to reach.
  #
  # The placeholder is held in its own variable, NOT written inline as
  # `${LEDGER_COMMIT_NAME:-{{LEDGER_COMMIT_NAME}}}`. That form reads correctly and
  # is not: bash closes the parameter expansion at the FIRST `}`, so the default
  # becomes `{{LEDGER_COMMIT_NAME` and the trailing `}}` is appended as literal
  # text to whatever the expansion produced. The unset case looks fine, so the
  # bug is invisible until an adopter sets the variable exactly as documented and
  # every ledger commit is authored by a malformed address.
  local name_placeholder='{{LEDGER_COMMIT_NAME}}'   # placeholder: commit author for ledger writes, e.g. "sdlc-agent"
  local email_placeholder='{{LEDGER_COMMIT_EMAIL}}' # placeholder: commit email, e.g. "agent@example.invalid"
  local commit_name commit_email
  commit_name="${LEDGER_COMMIT_NAME:-$name_placeholder}"
  commit_email="${LEDGER_COMMIT_EMAIL:-$email_placeholder}"

  LEDGER_TMP="$(mktemp -d)"
  trap 'rm -rf "${LEDGER_TMP:-}"' EXIT
  local tmp="$LEDGER_TMP"

  # Work in a throwaway clone so the caller's working tree and branch are untouched.
  #
  # Clone the REMOTE, not the local checkout. Cloning the working checkout gives the
  # clone an `origin` pointing back at that checkout, so the final push lands on a
  # LOCAL ref and reports success while nothing ever reaches the server. It is a
  # green run with a wrong answer, and it stays invisible until somebody asks why
  # the ledger is empty.
  local origin_url
  origin_url="$(git remote get-url origin)" || die "no 'origin' remote"
  git clone -q --depth 1 --branch "$BRANCH" "$origin_url" "$tmp/repo" 2>/dev/null \
    || die "cannot clone branch '$BRANCH' from origin — create it first (see docs/runbooks/agent-ledgers.md)"

  # EVERY command below carries its own `|| exit`, and that is not belt-and-braces.
  # `set -e` is SUPPRESSED inside a subshell that sits in a condition context — as the
  # left operand of `&&` or `||`, or in an `if`. Neither an explicit `set -e` inside the
  # subshell nor capturing its status afterwards restores it; both were measured. So a
  # failing `git commit` (a hook, a signing key, a full disk) used to fall straight
  # through to `git push`, which had nothing new to push and therefore exited 0 — and the
  # whole run printed "appended to ledger/<agent>.jsonl" and returned 0 while the entry
  # never reached the remote.
  #
  # For a ledger that is the sole evidence an agent ran at all, that is the worst
  # available shape: a success message, a zero exit, and no entry. Liveness keys on the
  # age of the newest entry, so the next agent in the ring escalates about a predecessor
  # that believes it reported.
  #
  # The exit codes also separate the two failures the old code conflated. A rejected push
  # is NORMAL — someone appended between our fetch and ours — and is retried. Anything
  # else is not, and retrying it five times only delays a misleading message.
  local attempt rc
  for attempt in 1 2 3 4 5; do
    rc=0
    (
      cd "$tmp/repo" || exit 20
      git fetch -q origin "$BRANCH" || exit 21
      git reset -q --hard "origin/${BRANCH}" || exit 22
      mkdir -p ledger || exit 23
      printf '%s\n' "$entry" >> "ledger/${agent}.jsonl" || exit 24
      if [ -n "$narrative_rel" ]; then
        mkdir -p "$(dirname "$narrative_rel")" || exit 25
        cp "$narrative_src" "$narrative_rel" || exit 26
        git add "$narrative_rel" || exit 27
      fi
      git add "ledger/${agent}.jsonl" || exit 28
      git -c user.name="$commit_name" -c user.email="$commit_email" \
        commit -q -m "ledger($agent): $(printf '%s' "$entry" | jq -r '.date') $(printf '%s' "$entry" | jq -r '.verdict')" \
        || exit 29
      # The ONLY retryable outcome is a RACED push (someone appended between
      # our fetch and ours). A DENIED push — 403, protected ref, a read-only
      # token, which is every scheduled run under fleet `mode: observe` — can
      # never succeed on retry, and five retries bury a credentials problem
      # under a contention message. Distinguish by stderr, because git's exit
      # code alone cannot.
      if ! git push -q origin "HEAD:${BRANCH}" 2>"../push-err"; then
        if grep -qiE '403|permission|denied|protected|read.only|not authorized|write access' "../push-err"; then
          cat "../push-err" >&2
          exit 31
        fi
        cat "../push-err" >&2
        exit 30
      fi
    ) || rc=$?

    [ "$rc" -eq 0 ] && { echo "appended to ledger/${agent}.jsonl on $BRANCH"; return 0; }

    if [ "$rc" -ne 30 ]; then
      case "$rc" in
        31) die "ledger append failed: the push was DENIED, not raced — this credential cannot write to '$BRANCH'. Under fleet 'mode: observe' this is the designed state (scheduled runs cannot write the ledger; the agent-report issue is the run's record — see .agents/observe.md). Otherwise: the token needs contents: write. NOTHING was written, and retrying cannot help." ;;
        29) die "ledger append failed: git commit refused (exit $rc) — a hook, a signing key or a full disk. NOTHING was written to $BRANCH." ;;
        21|22) die "ledger append failed: cannot fetch or reset '$BRANCH' from origin (exit $rc). NOTHING was written." ;;
        26|27) die "ledger append failed: the narrative file could not be staged (exit $rc). NOTHING was written." ;;
        *) die "ledger append failed before push (exit $rc). NOTHING was written to $BRANCH." ;;
      esac
    fi

    # Rejected: someone else appended between our fetch and our push. Refetch and
    # REPLAY the append. Never force-push — a force-push here silently discards
    # another agent's entry, and the ledger's only real value is that it is the one
    # record nothing overwrites.
    echo "push rejected (attempt $attempt) — refetching and replaying" >&2
    sleep $((attempt * 2))
  done
  die "could not append after 5 attempts"
}

case "${1:-}" in
  read)   shift; cmd_read "$@" ;;
  latest) shift; cmd_latest "$@" ;;
  trend)  shift; cmd_trend "$@" ;;
  append) shift; cmd_append "$@" ;;
  *)
    cat >&2 <<EOF
usage:
  ledger.sh read <agent> [n]              last n entries (default 14)
  ledger.sh latest                        newest entry per agent (watcher-ring check)
  ledger.sh trend <agent> <metric> [n]    a metric's series, for trend rules
  ledger.sh append <agent> <json> [file]  append one run entry (+ optional narrative)

agents: from ledger.agents[].id in .agents/config.yml (override: \$LEDGER_AGENTS)
docs:   docs/runbooks/agent-ledgers.md
EOF
    exit 2 ;;
esac
