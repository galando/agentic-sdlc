# Autonomous-Agent SDLC Template — Quick Reference

**Stack:** Bash + GitHub Actions YAML + Markdown (reference stack: Java/Spring Boot + React/TypeScript)
**Risk:** HIGH
**Files:** ~55 new, 1 modified
**Tests:** 22 scenarios — bats suites + the gate-22 harness guard suite

## TL;DR

Build a GitHub template repo implementing an autonomous-agent SDLC by EXTRACTING the
working harness from `{{SOURCE_REPO}}` (read-only) and genericizing it —
never regenerating it from the prompt. ~30 surveyed source files across three buckets
(copy as-is / copy then placeholder / write new), delivered in three PRs: extraction,
new plumbing (init + adapters + gates 21/22), example + docs.

## Key Decisions

- Extract-and-genericize the two big workflows (1,060 L) rather than regenerate — the
  prompt summarizes ~11 lessons, the files encode more, and a lost lesson still goes green
- One entrypoint `tools/run-agent.sh` + `tools/providers/*.sh`, so switching provider is
  one config edit and `--dry-run` works uniformly
- Three of four adapters ship as loud stubs — a plausible wrong headless flag succeeds at
  the shell level and does nothing, which is undetectable in an adopter's fork
- Reference stack mirrors the source, so ~12 gate configs port as tested artifacts
- Gate 21 is a standalone workflow, because `pr-tests.yml`'s jobs skip on exactly the
  docs/spec-only PRs where it matters
- Every floor ships as a placeholder; `init.sh` measures the adopter's real baseline

## Watch out for

- The source repo is READ-ONLY and live. Checksum before (Task 0), verify after (Task 32).
- Job `name:`/id strings are branch-protection context strings — freeze them.
- Raw grep understates the de-identification burden; the domain leaks through nouns.

## Run

`/temper:build`
