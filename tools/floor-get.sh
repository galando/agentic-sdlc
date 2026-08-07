#!/usr/bin/env bash
# tools/floor-get.sh — one floor value on stdout, for workflows.
#
# The thin CLI over tools/lib/config.sh's floor_get (the ONLY parser of
# floors.yml): pr-mutation.yml reads the diff-scoped mutation floor through
# this instead of parsing YAML in a run: block. Prints the calibrated value,
# or the literal `unset` while the floor is uncalibrated; exits non-zero only
# when the key does not exist at all.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AGENTS_ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=lib/config.sh
. "$AGENTS_ROOT/tools/lib/config.sh"

[ "$#" -eq 1 ] || { echo "usage: tools/floor-get.sh <dotted.floor.key>" >&2; exit 2; }
floor_get "$1"
