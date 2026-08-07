#!/usr/bin/env bash
# tools/alert.sh — the pushed-alert sender the escalation runbook mandates.
#
# Usage:  tools/alert.sh <S0|S1|S2|S3> "<one-line message>"
#
# This is the PUSH half of the alerting design only. The GitHub issue is the
# PRIMARY channel and is filed by the caller (or by nightly-alert.yml for CI
# gates) — this script never touches issues, so it can fail without taking the
# primary channel down with it (see docs/runbooks/agent-escalation.md,
# "Channels").
#
# Transport comes from .agents/config.yml via tools/lib/config.sh (the only
# parser):
#   alerts.channel: none    -> announce the skip and exit 0. Legal, supported.
#   alerts.channel: webhook -> POST {"text": <message>} to the URL in the env
#                              var named by alerts.webhook_secret.
#   alerts.channel: command -> run alerts.command with the message on stdin.
#
# Severity handling, matching the runbook exactly:
#   - S0 is the once-per-run heartbeat. It ALWAYS pushes when a channel is
#     configured — absence is the signal, so the floor never suppresses it.
#   - S1..S3 are compared against alerts.severity_floor (default S2): below the
#     floor the push is skipped (exit 0, announced) — those stay issue-only.
#
# Exit codes:
#   0  sent, or legitimately skipped (channel none / unconfigured / below floor)
#   2  usage error
#   3  configuration problem (unknown channel, missing command, schema mismatch)
#   4  a configured push FAILED (missing secret, HTTP error, command error).
#      The caller must then record the undelivered ping — issue title prefix
#      `[agent][UNDELIVERED PING]` and the ledger entry's `ping` field — rather
#      than fail silently. This script never fails silently either: every
#      non-zero exit says what went wrong and where.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AGENTS_ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=lib/config.sh
. "$AGENTS_ROOT/tools/lib/config.sh"

die_usage() {
  echo "usage: tools/alert.sh <S0|S1|S2|S3> \"<one-line message>\"" >&2
  echo "  $*" >&2
  exit 2
}

[ "$#" -eq 2 ] || die_usage "expected exactly 2 arguments, got $#"
SEVERITY="$1"
MESSAGE="$2"

sev_rank() {
  case "$1" in
    S0) echo 0 ;;
    S1) echo 1 ;;
    S2) echo 2 ;;
    S3) echo 3 ;;
    *)  return 1 ;;
  esac
}

RANK="$(sev_rank "$SEVERITY")" || die_usage "unknown severity '$SEVERITY'"
[ -n "$MESSAGE" ] || die_usage "the message is empty"

cfg_assert_schema "$(_cfg_file)" 1 || exit 3

CHANNEL="$(cfg_get alerts.channel none)" || exit 3

# A freshly-instantiated template still carries the interview placeholder here.
# That is the documented pre-init state and must not fail an agent run — but it
# must not look like a delivered ping either, so say what happened.
case "$CHANNEL" in
  \{\{*\}\})
    echo "alert.sh: alerts.channel is still the interview placeholder — run tools/init.sh. Push skipped; the issue remains the only channel."
    exit 0
    ;;
esac

if [ "$CHANNEL" = "none" ]; then
  echo "alert.sh: alerts.channel is 'none' — push skipped by configuration; the issue is the primary channel."
  exit 0
fi

# The heartbeat (S0) is exempt from the floor: a dead agent and a healthy agent
# must never look the same, and the daily summary line is how absence stays a
# signal. Everything else respects the floor.
if [ "$RANK" -ne 0 ]; then
  FLOOR="$(cfg_get alerts.severity_floor S2)" || exit 3
  FLOOR_RANK="$(sev_rank "$FLOOR")" || { echo "alert.sh: alerts.severity_floor '$FLOOR' is not one of S0..S3" >&2; exit 3; }
  if [ "$RANK" -lt "$FLOOR_RANK" ]; then
    echo "alert.sh: $SEVERITY is below alerts.severity_floor ($FLOOR) — push skipped; that tier is issue-only."
    exit 0
  fi
fi

case "$CHANNEL" in
  webhook)
    SECRET_NAME="$(cfg_get alerts.webhook_secret ALERT_WEBHOOK_URL)" || exit 3
    URL="${!SECRET_NAME:-}"
    if [ -z "$URL" ]; then
      echo "alert.sh: PUSH NOT SENT — alerts.channel is 'webhook' but \$${SECRET_NAME} is not set." >&2
      echo "alert.sh: record this as an undelivered ping (issue title '[agent][UNDELIVERED PING]', ledger 'ping' field)." >&2
      exit 4
    fi
    command -v jq >/dev/null 2>&1 || { echo "alert.sh: jq is required for the webhook payload" >&2; exit 3; }
    HTTP="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
      -X POST "$URL" \
      -H 'content-type: application/json' \
      --data "$(jq -nc --arg t "$MESSAGE" '{text: $t}')" || echo 000)"
    if [ "$HTTP" = "200" ] || [ "$HTTP" = "204" ]; then
      echo "alert.sh: $SEVERITY ping sent via webhook."
      exit 0
    fi
    echo "alert.sh: PUSH FAILED — webhook returned HTTP ${HTTP}." >&2
    echo "alert.sh: record this as an undelivered ping (issue title '[agent][UNDELIVERED PING]', ledger 'ping' field)." >&2
    exit 4
    ;;
  command)
    CMD="$(cfg_get alerts.command "")" || exit 3
    if [ -z "$CMD" ]; then
      echo "alert.sh: alerts.channel is 'command' but alerts.command is empty — nothing to run." >&2
      exit 3
    fi
    if printf '%s\n' "$MESSAGE" | bash -c "$CMD"; then
      echo "alert.sh: $SEVERITY ping sent via command."
      exit 0
    fi
    echo "alert.sh: PUSH FAILED — alerts.command exited non-zero." >&2
    echo "alert.sh: record this as an undelivered ping (issue title '[agent][UNDELIVERED PING]', ledger 'ping' field)." >&2
    exit 4
    ;;
  *)
    echo "alert.sh: unknown alerts.channel '$CHANNEL' (expected none | webhook | command)" >&2
    exit 3
    ;;
esac
