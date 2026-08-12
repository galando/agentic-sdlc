# Intent: second-brain-and-sdlc-extension

**Created:** 2026-08-12
**Ticket:** PR #18 (`docs/plans/second-brain-and-sdlc-extension.md`)

## Problem

The template has episodic memory (ledgers — history, never instruction) and
operator-written instruction (`docs/runbooks/agent-modes.md`), but no layer for
knowledge the agents themselves distill: a lesson only becomes durable today if the
operator hand-writes it into a runbook. The fleet also has no coverage for dependency
upgrades, doc rot, backlog rot, proactive floor raises, or release drafting, and the
template has no scripted way to show every capability end to end without waiting on
organic activity. PR #18 is a plan proposing three fixes for this (Part A, B, C); this
spec covers implementing all three, on the operator's explicit instruction to do the
whole plan in one pass rather than the plan's own phased sequencing.

## Success Criteria

- [x] SC1 — A `docs/knowledge/` second brain exists: card contract, an 80-line-capped
      index, one seed card, a session-start read step, and a chief-of-staff write path
      (self-gated retrospective, at most 2 cards per pull request, human-merged).
- [x] SC2 — The second brain's own consistency (index/card 1:1, frontmatter, line caps)
      is enforced by a new FAST gate, not by convention.
- [x] SC3 — Five new scheduled agents exist (docs freshness, backlog groomer, test gap,
      dependency steward, release drafter), each the standard four-file shape, shipped
      `enabled: false` like every other agent, with harness-guard pins on their
      load-bearing shaping rules.
- [x] SC4 — Adding five agents to the shared `ledger.agents` list does not silently
      break the watcher ring: the new wrap point (`health`'s predecessor moving from
      `challenger` to `release`) is stated explicitly everywhere the old value was.
- [x] SC5 — `DEMO.md` documents a reproducible, fixed-order capability tour covering the
      existing loop plus every new capability.
- [x] SC6 — Every generated file this change affects (`ADOPTING.md`,
      `tests/harness-guards/pins.generated.bats`) is regenerated from the full tracked
      tree and diffs clean; the harness suite, `actionlint` and `shellcheck` all pass.

## Constraints

- Nothing vendor-specific in any new prompt or workflow (provider indirection stands).
- No lowering of any floor, threshold or exclude (the ratchet policy applies to this
  change like any other).
- New agents ship disabled by default — the template must not wake up as five new
  crons and an alert firehose on day one.
- The plan's own recommended sequencing (Part A as one PR, Part B one agent per phase)
  is explicitly overridden here at the operator's request; this is a scope decision,
  not an oversight, and is recorded in `plan.md`.

## Scenarios (BDD)

```gherkin
Scenario: An agent's task matches a knowledge card's symptoms
  Given docs/knowledge/INDEX.md lists a rule/trap card whose symptoms match the task
  When the agent follows the AGENTS.md session-start read step
  Then it reads that card (and no more than 2-3) before starting its own work
  Note: unit (tests/knowledge-lint.bats exercises the index/card contract this depends on)

Scenario: A knowledge card's index entry has no matching card file
  Given docs/knowledge/INDEX.md names a slug with no docs/knowledge/<slug>.md
  When tools/knowledge-lint.sh runs
  Then it fails with an error naming the missing card
  Note: unit (tests/knowledge-lint.bats: "an index entry with no matching card fails")

Scenario: A new scheduled agent ships safely on a fresh clone
  Given a freshly instantiated template with docs/groomer/testgap/deps/release added to
    ledger.agents
  When agents-scheduled.yml fires on any of their cron schedules
  Then the matrix entry resolves enabled=false and no-ops without alerting
  Note: unit (tests/harness-guards/agents-scheduled.bats: "every configured agent ships
    enabled: false")

Scenario: The watcher ring's wrap point after adding five agents
  Given ledger.agents now ends with docs, groomer, testgap, deps, release
  When health checks its own predecessor's liveness
  Then it reads release's ledger entry, using release's own max-age-hours override
  Note: unit (tests/config-reader.bats: "cfg_predecessor wraps at the top")
```

## Scenario Coverage Checklist

- [x] An agent's task matches a knowledge card's symptoms -> `tests/knowledge-lint.bats`
      (index/card contract), `AGENTS.md` session-start step 4 (manual/prose scenario,
      not independently unit-tested — the read behaviour itself is a prompt
      instruction, not a mechanism)
- [x] A knowledge card's index entry has no matching card file -> `tests/knowledge-lint.bats::"an index entry with no matching card fails"`
- [x] A new scheduled agent ships safely on a fresh clone -> `tests/harness-guards/agents-scheduled.bats::"every configured agent ships enabled: false (minimal mode, day one)"`
- [x] The watcher ring's wrap point after adding five agents -> `tests/config-reader.bats::"cfg_predecessor wraps at the top under both readers"`
