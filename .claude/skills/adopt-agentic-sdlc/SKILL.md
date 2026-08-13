---
name: adopt-agentic-sdlc
description: "Adopt the agentic-SDLC harness into this repository: run the adoption interview non-interactively from an answers profile, drive the guided adoption, verify every phase with the shipped checkers, and hand back the short list of steps only a human can do. Use when the user asks to adopt, install, onboard, or set up the agentic SDLC template."
---

# Adopt the agentic SDLC

`ONBOARDING.md` at the repository root is the complete, binding procedure —
read it now and execute it top to bottom. This skill adds nothing to it; it
exists so `/adopt-agentic-sdlc` finds it. Single source of truth: if this file
and `ONBOARDING.md` ever disagree, `ONBOARDING.md` wins.

The three things people get wrong, restated because they are cheap to ruin:

1. **Order**: `tools/init.sh --answers <file>` FIRST, then `tools/adopt.sh`
   with the `ADOPT_*` variables. In a non-interactive shell, `adopt.sh` before
   the interview exits 0 having done nothing.
2. **Never merge anything** (`AGENTS.md` guardrail 2), and never report done
   over a red check — verify with `tools/check-placeholders.sh`,
   `tools/status.sh`, and `bats tests/ tests/harness-guards/`.
3. **Do not calibrate floors** (`ADOPT_MEASURE`) until the human's own product
   code exists at `backend/`/`frontend/`.
