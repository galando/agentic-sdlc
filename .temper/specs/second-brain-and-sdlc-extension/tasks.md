# Tasks: second-brain-and-sdlc-extension

Ordered, one task at a time unless marked `[PARALLEL]`. Written retroactively against
the change actually made (`plan.md` "Decisions" explains why); each `Validate:` line is
a real command run during the build, not a restatement of the task.

## Task 1: The second brain's card contract and seed content

**Action:** CREATE
**File:** `docs/knowledge/README.md`, `docs/knowledge/INDEX.md`, `docs/knowledge/merge-is-not-deploy.md`
**Test:** `tests/knowledge-lint.bats::"the real docs/knowledge/ tree in this repository passes"`
**Validate:** `tools/knowledge-lint.sh` exits 0 against the real tree.

## Task 2: The second brain's lint tool and its own tests

**Action:** CREATE
**File:** `tools/knowledge-lint.sh`, `tests/knowledge-lint.bats`
**Test:** `tests/knowledge-lint.bats` (14 cases: clean tree, orphan card, dangling
index entry, project-card exclusion, missing frontmatter field, topic mismatch,
invalid type, bad date, over-length body, over-length index, duplicate slug, absent
directory)
**Validate:** `bats tests/knowledge-lint.bats` — 14/14 green.

## Task 3: Wire the second brain into the read/write path

**Action:** MODIFY
**File:** `AGENTS.md`, `.agents/prompts/chief-of-staff.md`, `docs/runbooks/agent-modes.md`
**Test:** `tests/harness-guards/pins.generated.bats` (pins
`second-brain-read-path-checklist-step`, `second-brain-distiller-two-questions`,
`second-brain-standing-decision-ownership`)
**Validate:** `bats tests/harness-guards/pins.generated.bats` green; the three quoted
strings are grep-findable in their `expected_in` files.

## Task 4: Wire the second brain's own FAST gate

**Action:** MODIFY
**File:** `.github/workflows/pr-tests.yml`, `docs/QUALITY-GATES.md`, `docs/runbooks/branch-protection.md`
**Test:** `tests/harness-guards/branch-protection-contexts.bats`
**Validate:** `bats tests/harness-guards/branch-protection-contexts.bats` green;
`actionlint .github/workflows/*.yml` exits 0.

## Task 5: Propagate the FAST-tier count change (7 → 8) everywhere it is asserted

**Action:** MODIFY
**File:** `.github/workflows/pr-validation.yml`, `tools/adopt.sh`, `docs/maintainers/demo-recreation.md`
**Test:** manual grep sweep for `"seven"` / the 7-item enumeration, described in
`plan.md` "Blast Radius"
**Validate:** `grep -rn "all seven\|seven fast-tier\|seven FAST" .` returns nothing
live (only unrelated `.temper/specs/agent-sdlc-template/` historical mentions of an
unrelated "seven").

## Task 6: The five new agent prompts

**Action:** CREATE
**File:** `.agents/prompts/{docs-freshness,backlog-groomer,test-gap,dependency-steward,release-drafter}.md`
**Test:** `tests/harness-guards/pins.generated.bats` (5 new per-agent shaping-rule pins)
**Validate:** `bats tests/harness-guards/pins.generated.bats` green.

## Task 7: Wire the five agents into config, scheduler and docs

**Action:** MODIFY
**File:** `.agents/config.yml`, `.github/workflows/agents-scheduled.yml`, `docs/runbooks/agent-routines.md`, `docs/runbooks/agent-modes.md`, `docs/runbooks/agent-ledgers.md`
**Test:** `tests/harness-guards/agents-scheduled.bats`
**Validate:** `bats tests/harness-guards/agents-scheduled.bats` — 8/8 green, including
"carries exactly ten cron entries" and "every configured agent ships enabled: false".

## Task 8: Correct the watcher-ring wrap point (health's predecessor)

**Action:** MODIFY
**File:** `.agents/prompts/health.md`, `docs/runbooks/agent-routines.md`, `tests/config-reader.bats`, `tests/run-agent-dryrun.bats`
**Test:** `tests/config-reader.bats::"cfg_predecessor wraps at the top under both readers"`
**Validate:** `AGENTS_CONFIG_READER=awk bash -c ". tools/lib/config.sh; cfg_predecessor health"` prints `release`.

## Task 9: The capability demo

**Action:** CREATE
**File:** `DEMO.md`
**Test:** none automated (a runbook, not a mechanism) — `plan.md`'s constraint that it
is covered by the docs-freshness agent's own weekly sweep going forward is the ongoing
check.
**Validate:** manual read-through against the 13 stops named in
`docs/plans/second-brain-and-sdlc-extension.md` Part C2; every stop names a trigger, a
thing to show, and an artifact.

## Task 10: Add and regenerate the pin inventory

**Action:** MODIFY
**File:** `tests/harness-guards/pins.json`, `tests/harness-guards/pins.generated.bats`, `tests/harness-guards/lesson-inventory.md`
**Test:** `tests/harness-guards/pins-schema.bats`, `tests/harness-guards/pin-count.bats`, `tests/harness-guards/pins-discharge.bats`
**Validate:** `tests/harness-guards/gen-pin-tests.sh && git diff --exit-code tests/harness-guards/pins.generated.bats` — no diff; all three bats files green (27/27 combined).

## Task 11: Regenerate ADOPTING.md against the full tracked tree

**Action:** MODIFY (generated)
**File:** `ADOPTING.md`
**Test:** `tests/adopting.bats::"tools/gen-adopting.sh is a pure function of the tree — regenerating it is a no-op"`
**Validate:** `git add -A && tools/gen-adopting.sh && git diff --exit-code ADOPTING.md`
— required `git add` first, since the generator reads `git ls-files`, not the working
tree; the first regeneration attempt (before staging) produced no diff and would have
shipped a stale table.

## Task 12: Full-suite verification

**Action:** MODIFY (none — verification only)
**File:** n/a
**Test:** `bats tests/ tests/harness-guards/`
**Validate:** 626/626 passing, 0 failing; `actionlint .github/workflows/*.yml` exit 0;
`shellcheck tools/knowledge-lint.sh tools/adopt.sh` clean (one pre-existing SC1091 info
note in `adopt.sh`, unrelated to this change); `tools/check-placeholders.sh` and
`tools/check-deidentified.sh` both exit 0 in their expected pre-init/unarmed states.
