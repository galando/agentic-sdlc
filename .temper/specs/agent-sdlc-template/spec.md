# Spec: Autonomous-Agent SDLC Template Repository

**Created:** 2026-08-04
**Ticket:** none — source of truth is `agentsdlcrepoprompt.md` (571 lines), treated
literally as an acceptance checklist
**Complexity:** complex
**Risk:** high

## Problem Statement

A production-proven autonomous-agent SDLC exists in exactly one private product
repository. Its value is not the design — it is ~5,600 lines of files whose every
non-obvious line is a postmortem. None of it is reusable, because it is welded to one
product's name, domain, metrics and vocabulary. This work produces a GitHub **template
repository** carrying that harness generically, so a stranger can instantiate it, reach
all-green CI within the first hour, and swap agent providers by editing one config file.

## Requirements

**R1 — Extraction over regeneration.** Every file that exists in the source repository is
copied and genericized, never rewritten from the prompt. Each file is classified into one
of three buckets (copy nearly as-is / copy then placeholder / write new); plan.md carries
the surveyed 30-row inventory with path, size and what each file encodes.

**R2 — Complete de-identification.** No project name, domain, URL, issue/PR number,
author handle or bespoke domain noun in file content, file names, commit messages or code
comments. Incident-derived comments are rewritten as neutral lessons, never deleted.

**R3 — Provider agnosticism.** One config file (`.agents/config.yml`) holding provider
name, model id per ROLE (`judge` / `execute` / `challenge`), auth mode per provider,
mention trigger and alert channel. One entrypoint (`tools/run-agent.sh`) called by every
workflow; adapters in `tools/providers/`. `--dry-run` prints the exact command per
provider. Subscription auth is the default; an API key is the fallback. No vendor name in
any workflow, runbook or prompt.

**R4 — The full gauntlet.** All 22 gates documented with the ratchet policy intact, the
10-item "why each layer exists" ladder, and the deploy-time backup-restore gate. Blocking
gates on every PR; nightly gates notify a human automatically through the reusable
notifier. Gate 21 (spec artifacts present) and gate 22 (harness guards) are new.

**R5 — The agent contract.** Seven guardrails in `AGENTS.md`; ledgers are history and
`agent-modes.md` is the only instruction channel; liveness through per-run alerts
including healthy ones; fix verification by the filing agent against the end state;
pinned model ids split by role with the challenger from a different family.

**R6 — Adoption path as the product.** No baked-in answers; `tools/init.sh` is an
idempotent, network-free interview; floors start at the adopter's measured baseline;
minimal mode is the default with scheduled agents shipped disabled; a ~200-line example
proves the loop end to end.

**R7 — Delivery shape.** Three PRs in fixed order — (a) extraction + genericization,
(b) new plumbing, (c) example + docs polish — each closing with a plain-language summary
of what was extracted unchanged, genericized, newly written and stubbed.

**R8 — Verified work.** Every workflow passes actionlint. `tools/ledger.sh` round-trips
against a real orphan branch with a captured transcript. The source repository is
byte-identical before and after.

## Acceptance Criteria

- [ ] The de-identification sweep over content, file names and commit messages returns
      zero hits, and runs as a pre-PR step
- [ ] All 22 gates appear in `docs/QUALITY-GATES.md`; every blocking gate names a job
      that exists; every numeric floor is a placeholder, not a number
- [ ] Every gate job skips via a job-level `if:` when its stack is absent; no required
      check sits behind a workflow-level `paths:` filter
- [ ] `tools/run-agent.sh <agent> --dry-run` prints the exact argv for all four
      providers, invoking nothing; the two stubs are loudly marked and exit non-zero
      when actually run
- [ ] `tools/ledger.sh` append / read / latest / trend round-trip on a fresh orphan
      branch, with the transcript in the PR body
- [ ] Gate 21 fails a fix PR lacking spec artifacts and passes one carrying
      `temper: unavailable — <reason>`
- [ ] `tools/init.sh` run twice with the same answers yields an empty diff, makes no
      network call, and leaves no unresolved `{{PLACEHOLDER}}`
- [ ] `actionlint .github/workflows/` reports zero findings
- [ ] A fresh instantiation reaches all-green CI on the example product
- [ ] A missing optional credential degrades the second review and never fails the PR
- [ ] Scheduled agents ship disabled with a documented one-line enable
- [ ] README follows the 10-point outline, carries the gate→tool and secret→consequence
      tables, and states the setup order with branch protection LAST
- [ ] The source repository's checksums and `git status` are unchanged
- [ ] The closing summary states plainly what was not built and what is manual

## Edge Cases

| Scenario | Expected Behavior |
|---|---|
| Optional challenge-role credential absent | Reviewer B and the referee skip with a warning; reviewer A's review stands; the PR is not failed |
| Adopter has no frontend | Frontend gate jobs report `skipped`; every required check still reports; nothing hangs pending |
| PR thread exceeds one API page | Collector slurps and flattens before filtering; returns one result overall, not one per page |
| Review posted as an inline code comment | Collector reads both comment endpoints and merges; reports nothing missing |
| Two people tag the agent on different issues in the same minute | Per-issue job-level concurrency groups keep both; neither is silently evicted |
| A bot account triggers the workflow | Job does not run; the review path files an issue instead, since `issues:[opened]` has no sender check |
| Elevated token missing for a cross-workflow handoff | The issue is still filed, and the run states loudly that the handoff did not happen |
| Auto-triage run produces no comment and no branch | Marker comment posted and the job fails on purpose |
| Build pipeline genuinely unreachable | Fall back to a careful test-first change and say so once, in the ledger entry and the PR body; gate 21 accepts the declared reason |
| A caller of the reusable notifier omits its permissions block | Workflow rejected at startup — documented as the failure signature, with the postmortem comment kept on the permissions block |
| Adopter marks a nightly check as required | Documented as forbidden in `branch-protection.md`, with the exact safe context strings listed |

## Out of Scope

- Any product code beyond the ~200-line example
- Working implementations of the Codex, Gemini CLI and compatible-endpoint adapters —
  they ship as clearly-marked stubs with the exact command shape and a docs link
- Gate implementations for stacks other than the reference stack — those are documented
  contracts with cleanly-skipping jobs
- Routine schedules and branch protection — neither can be committed to a repository;
  both become documented, ordered setup steps
- Secrets, GitHub app installation and the ledger orphan branch — printed by `init.sh` as
  remaining manual work
- The source repository's deploy pipeline, growth agent and prod-env check — domain
  specific; only the deploy-time backup-restore gate idea is harvested
