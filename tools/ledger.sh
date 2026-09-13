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
  # `--validate-only` runs every check below and returns before the clone. It is
  # how a prompt, a test or an operator asks "would this entry be accepted?"
  # without spending a network round-trip or writing anything.
  local validate_only=0
  if [ "${1:-}" = "--validate-only" ]; then
    validate_only=1
    shift
  fi
  local agent="${1:-}" entry="${2:-}" narrative="${3:-}"
  [ -n "$agent" ] && [ -n "$entry" ] || die "usage: ledger.sh append [--validate-only] <agent> <json> [narrative-file]"
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

  # `ping.summary` records the INTENT to send the run-summary — "sent" or "none" —
  # never a message id: the entry is appended before that message goes out, so
  # no id exists at write time (efficiency rule 4a). A failed send is an
  # `[<agent>][UNDELIVERED PING]` issue, never a second entry.
  if printf '%s' "$entry" | jq -e '.ping | type == "object" and has("summary")' >/dev/null 2>&1; then
    printf '%s' "$entry" | jq -e '.ping.summary | type == "string" and test("^(sent|none)$")' >/dev/null 2>&1 \
      || die "ping.summary must be \"sent\" or \"none\" — the intent, recorded before the send; a message id never belongs here (rule 4a)"
  fi

  # `fix_verified` verdicts are the vocabulary two other agents branch on (the
  # groomer's close bar, the chief of staff's closed-but-unverified list), so a
  # sixth word is refused here rather than silently ignored there. `partial`
  # must name where the unfixed half lives; `too_early` must name when it
  # becomes scoreable and which issue it belongs to (docs/runbooks/agent-ledgers.md).
  if printf '%s' "$entry" | jq -e 'has("fix_verified")' >/dev/null; then
    printf '%s' "$entry" | jq -e '.fix_verified | type == "array" and all(.[]; type == "object")' >/dev/null \
      || die "fix_verified must be an array of {pr, metric, verdict} objects"
    printf '%s' "$entry" | jq -e '.fix_verified | all(.[]; (.verdict | type == "string" and test("^(moved|partial|not_moved|too_early|unmergeable_state)$")))' >/dev/null \
      || die "fix_verified verdict must be one of moved, partial, not_moved, too_early or unmergeable_state — these five are the whole list"
    printf '%s' "$entry" | jq -e '.fix_verified | all(.[]; .verdict != "partial" or ((.follow_up | type) == "number" or .follow_up == "reopened"))' >/dev/null \
      || die "a partial verdict must carry follow_up: the issue number holding the unfixed half, or \"reopened\""
    printf '%s' "$entry" | jq -e '.fix_verified | all(.[]; .verdict != "too_early" or ((.recheck_after | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and (.issue | type) == "number"))' >/dev/null \
      || die "a too_early verdict must carry recheck_after (YYYY-MM-DD) and issue (the number it is scored for) — never carry it in pending"
  fi

  # Rule 9 (docs/runbooks/agent-routines.md, "never punt"): an agent never
  # punts. Work it leaves undone is listed in `not_done`, and each item names a
  # fixed stop. A prompt cannot force that, so the write refuses a reason
  # outside the list, a missing item or next step, or a `clock` stop with no
  # draft PR number to show the work was already pushed.
  if printf '%s' "$entry" | jq -e 'has("not_done")' >/dev/null; then
    printf '%s' "$entry" | jq -e '.not_done | type == "array" and all(.[]; type == "object")' >/dev/null \
      || die "not_done must be an array of {item, reason, next} objects"
    printf '%s' "$entry" | jq -e '.not_done | all(.[]; (.item | type == "string" and length > 0))' >/dev/null \
      || die "every not_done item must carry a non-empty 'item'"
    printf '%s' "$entry" | jq -e '.not_done | all(.[]; (.next | type == "string" and length > 0))' >/dev/null \
      || die "every not_done item must carry a non-empty 'next' (the exact click, command, PR or issue)"
    printf '%s' "$entry" | jq -e '.not_done | all(.[]; (.reason | type == "string" and test("^(guardrail|cap|operator-only|blocked-by:#[0-9]+|not-reproducible|clock)$")))' >/dev/null \
      || die "not_done reason must be one of guardrail, cap, operator-only, blocked-by:#N, not-reproducible or clock — " \
             "\"later\", \"next run\", \"follow-up\" and \"a human decides\" are punts, not stops (rule 9)"
    printf '%s' "$entry" | jq -e '.not_done | all(.[]; .reason != "clock" or (.next | test("#[0-9]+")))' >/dev/null \
      || die "a clock stop must name the draft PR number in 'next': clock is valid only with the draft PR already pushed (rule 9)"
  fi

  if [ "$validate_only" = 1 ]; then
    echo "entry is valid (not written)"
    return 0
  fi

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
  local attempt rc run_n
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
        # One narrative path per agent per day, so a second run on the same date
        # lands on the first run's file. Append under a `## Run N` heading instead
        # of copying over it: a `cp` deleted the earlier run's evidence while both
        # JSONL entries still pointed at the file.
        #
        # The probe sits after the `reset --hard` above so a replayed attempt sees
        # the branch as it is and never doubles its own text. N counts this date's
        # entries that carry a narrative — the JSONL line was appended just above,
        # so the current entry is already in the count and the first same-day
        # append reads "Run 2". An entry with no narrative wrote no section, so it
        # does not advance the number.
        if [ -s "$narrative_rel" ]; then
          run_n="$(jq -r --arg d "$(printf '%s' "$entry" | jq -r '.date')" \
                     'select(.date == $d and (.narrative // "") != "") | .date' "ledger/${agent}.jsonl" | wc -l | tr -d ' ')"
          {
            printf '\n---\n\n## Run %d — %sZ\n\n' "$run_n" "$(date -u +%H:%M)"
            cat "$narrative_src"
          } >> "$narrative_rel" || exit 32
        else
          cp "$narrative_src" "$narrative_rel" || exit 26
        fi
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
        32) die "ledger append failed: could not append the same-day narrative under its '## Run N' heading (exit $rc). NOTHING was written." ;;
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
  ledger.sh append --validate-only <agent> <json>
                                          run every check, write nothing, clone nothing

agents: from ledger.agents[].id in .agents/config.yml (override: \$LEDGER_AGENTS)
docs:   docs/runbooks/agent-ledgers.md
EOF
    exit 2 ;;
esac
