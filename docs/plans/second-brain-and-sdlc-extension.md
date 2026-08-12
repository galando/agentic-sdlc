# Plan: a second brain, five new fleet agents, and a capabilities demo

**Date:** 2026-08-12
**Status:** PROPOSED — this document is the plan; nothing in it is wired yet.
**Scope:** three deliverables for the template:

- **Part A** — a *second brain*: a curated, topic-indexed knowledge base that
  agents read cheaply at session start and grow through reviewed pull requests.
- **Part B** — five new scheduled agents extending SDLC coverage: dependency
  steward, docs freshness, backlog groomer, test gap, release drafter.
- **Part C** — a reproducible demo that exercises **every** capability end to
  end, in a fixed order a viewer can follow.

Everything below obeys the existing spine: provider indirection (roles, never
vendors), agents propose / a human merges, ledgers are history never
instruction, and every load-bearing string gets a harness-guard pin.

---

## Part A — The second brain

### A1. The gap it fills

The template has episodic memory (ledgers) and operator-written instruction
(`docs/runbooks/agent-modes.md`). It has no layer for knowledge the **agents
themselves distill** — lessons currently become durable only when the operator
hand-writes them into a runbook. The second brain is that middle layer, built so
that a lesson is *history until a human merges it, instruction after* — the same
branch-protection line that already separates ledgers from `agent-modes.md`.

### A2. Layout and formats

New directory on the default branch:

```
docs/knowledge/
  README.md      # the card contract (this section, condensed)
  INDEX.md       # one entry per rule/trap card; hard cap 80 lines
  <topic-slug>.md
```

Card frontmatter: `name`, `topic` (slug == filename, same convention as the
ledger `topic` field), `type` (`rule` | `trap` | `project`), `description`,
`symptoms` (the retrieval surface — observable symptoms, not labels),
`verified` (date last confirmed), `related` (optional slugs — the cheap graph).
Body **≤ 60 lines**, distilled instruction only; evidence stays in ledgers and
pull requests. `project` cards are grep-only reference snapshots, excluded from
the index read path.

INDEX entry shape (symptoms are what an agent will actually match on):

```
<slug> — <one-line description>.
  Symptoms: <what the next agent would observe when this card applies>.
```

### A3. Read path

One added session-start step in `AGENTS.md`, after the ledger read:

> Read `docs/knowledge/INDEX.md`. If a line's symptoms match your task, read
> those cards only (rarely more than 2–3). If the index matched nothing but your
> task names a specific error string, file, or metric, run one
> `grep -ril '<term>' docs/knowledge/`. Never read the whole directory. A miss
> costs nothing — work as you would today.

Worst-case cost ≈ index (2 KB) + 3 cards (6 KB); typical ≈ 2 KB. Deliberately
**no** embedding store or graph database: the reader is a language model, so
reading an 80-line index *is* semantic retrieval, grep is the fallback
retriever, and `related:` is the graph. Written-down graduation criterion: more
than ~150 `rule`/`trap` cards, or a need to search narratives → revisit with a
*derived* index, git staying the source of truth.

### A4. Write path

- **Distiller: the chief of staff**, in its existing retrospective. Two added
  questions: (1) did any `fix_verified`, recurring `topic`, or chronic `pending`
  teach something durable? → one docs-only pull request, at most 2 cards +
  index lines (docs-only ⇒ no spec pipeline needed, guardrail 7 exception);
  (2) did any run **re-derive** something a card already covers? → the defect
  is the index line's symptoms wording; fix it in the same pull request. That
  second question is what makes retrieval self-healing.
- Other agents never write cards mid-run (scope guardrail); they hand evidence
  to the chief of staff via `handoff`.
- The operator merges every card pull request. Rejecting one is cheap and normal.

### A5. Maintenance

Cards carry `verified:`; the chief of staff's brief lists any `rule`/`trap` card
stale past 90 days ("confirm, fold, or delete"). The 80-line index cap is the
forcing function: when full, fold before adding. Steady state is a few dozen
cards, so context cost cannot drift silently.

### A6. Mechanical changes (one pull request)

1. `docs/knowledge/` with `README.md`, `INDEX.md`, and one seed `rule` card
   (distilled from the template's own docs, e.g. "a merged change whose
   mechanism is a manual step is not deployed").
2. `AGENTS.md`: session-start step + a "Where things live" row.
3. `docs/runbooks/agent-modes.md`: one standing decision (read path, distiller
   ownership, merge rule, staleness line), pointing at `docs/knowledge/README.md`
   for the format.
4. Chief-of-staff prompt (`.agents/prompts/chief-of-staff.md`): the two
   retrospective questions and the brief's staleness line.
5. `tools/knowledge-lint.sh` + `tests/knowledge-lint.bats`: index↔card 1:1 for
   `rule`/`trap`, frontmatter complete, body ≤ 60 lines, `verified` parses,
   index ≤ 80 lines. Wire into PR validation as a FAST gate and add it to the
   inventory in `docs/QUALITY-GATES.md`.
6. `tests/harness-guards/pins.json`: pin the load-bearing strings — the
   checklist step in `AGENTS.md`, the retrospective questions in the
   chief-of-staff prompt, the standing-decision bullet — so a lost lesson about
   the lesson system cannot pass quietly. Regenerate `pins.generated.bats`.
7. `ADOPTING.md` / `tools/init.sh`: no interview question needed — the
   directory ships working and empty-but-for-one-card; note it in the adoption
   docs.

---

## Part B — Five new agents

Common contract, identical to the existing fleet: fresh scheduled session; reads
`AGENTS.md`, modes, own ledger, the knowledge index (A3); exactly one ledger
entry with `metrics`; one alert-channel line every run; handoffs per efficiency
rule 7; plain language; never merges. Mechanically, each agent is the same
four-file change: a prompt in `.agents/prompts/`, an id in `ledger.agents` in
`.agents/config.yml` (the single list the matrix, validator and watcher ring
read), a cron row in `agents-scheduled.yml`, and pins for its load-bearing
prompt strings. Model roles: `judge` for the analysis, `execute` for mechanical
batches, per the model policy.

| Agent | Ledger id | Cadence | One-line charter |
|---|---|---|---|
| Dependency steward | `deps` | weekly | one bounded upgrade PR per run from audit output; CVE deltas as ledger metrics |
| Docs freshness | `docs` | weekly | sweep **all** markdown files; fix top 5 findings in one docs-only PR; rest to `pending` |
| Backlog groomer | `groomer` | weekly | relabel, one evidence-bearing status comment per changed issue, close only on recorded `fix_verified`, SLA breaches to the brief |
| Test gap | `testgap` | weekly | propose the next floor raise with evidence, or fill the single worst load-bearing coverage gap via the spec pipeline |
| Release drafter | `release` | on demand / monthly | draft notes from merged agent PRs + `fix_verified` records; propose a tag; a human presses release |

Shaping rules carried into the prompts (each is also a pin):

- **Docs freshness:** sweep-all, fix-batched — full coverage comes from the
  sweep and the `pending` carry, never from one unreviewable 40-file diff.
  Contradictions between two docs are a report, never an auto-resolve.
- **Backlog groomer:** evidence-only closes (≤ 3 per run, ≤ 15 issues touched);
  "a merged pull request does not close an issue — the filing agent's
  verification does" is enacted, never shortcut. Body updates are appended,
  dated sections — the original report is evidence and is never rewritten.
- **Test gap:** the ratchet only tightens — raises floors with headroom
  evidence, never lowers one, never widens an exclude; a blocking floor is
  escalated, not edited.
- **Dependency steward:** one upgrade per run, through the fix pipeline, with
  the changelog excerpt and the failing-without/passing-with test evidence in
  the PR body; a missing audit tool degrades to a report, never a silent skip.

Sequencing: one agent per phase, each observed for a full cycle before the next
— docs freshness first (safest: docs-only), then groomer, test gap, dependency
steward, release drafter.

---

## Part C — The demo: build it, then show every capability

Goal: a repo an adopter or viewer can watch run the *whole* system — the
existing loop **plus** Parts A and B — with each capability triggered
deliberately rather than waiting for organic activity. The existing demo repo
already proves adoption; this extends the same pattern with a scripted
capability tour, logged step by step in an `ADOPTION-LOG.md` exactly as the
existing demo does.

### C1. Build (≈ one hour, mostly waiting on runs)

1. **Create the repo from the template**, keep the bundled example product
   (`examples/` — the gates need something real to measure).
2. **Run `tools/adopt.sh`** and answer the interview: product name, provider,
   model per role (`judge`/`execute`/`challenge` — challenge from a different
   family to unlock the adversarial review), alert channel, mention trigger.
   Re-run until `tools/status.sh` is clean.
3. **Arm the floors:** `tools/measure-floors.sh` against the example product's
   own baseline, commit the armed `floors.yml`.
4. **Create the ledger branch:** `tools/create-ledger-branch.sh`.
5. **Branch protection** per `docs/runbooks/branch-protection.md` — require the
   FAST contexts by exact string.
6. **Verify the harness:** `bats tests/ tests/harness-guards/`,
   `actionlint`, `tools/run-agent.sh --list-agents`, `--check-credentials` for
   each role, one `--dry-run` per agent (prints the exact argv, invokes
   nothing — ideal on camera).
7. **Seed the demo state** (this is what makes every capability triggerable on
   demand): one planted bug in the example product with a reproducing test
   path; one dead link planted in a runbook; three stale issues (one with a
   merged-but-unverified fix, one duplicate pair, one past its severity SLA);
   one dependency with a known available upgrade; floors armed ~4 points below
   measured so the test-gap agent has a legitimate raise to propose.

### C2. The capability tour (fixed order, ~13 stops)

Each stop names the trigger, what to show on screen, and the artifact that
proves it worked:

1. **Steward triage** — open an issue describing the planted bug (a newly
   opened issue invokes the steward automatically). Show: the triage comment.
2. **Spec pipeline** — the resulting fix is built through the configured
   pipeline: root cause written *before* the patch, then the failing test, then
   the code. Show: the spec artifacts and gate 21 green on the PR.
3. **Two reviews + referee** — the judge review, the challenge review from a
   different model family, the referee's merge of the two. Show: the review
   threads; point at the role names, never a vendor.
4. **The gauntlet** — the FAST checks on the PR, including the ratchet guards
   and the new knowledge-lint gate. Show: the checks tab, every context
   reporting.
5. **The human merge** — the click that nothing bypasses.
6. **Fix verification** — the filing agent's next run reads the end-state
   signal and records `fix_verified` (`moved`). Show: the ledger line;
   contrast "the reload succeeded" vs "the system serves the fix".
7. **Second brain, write path** — the chief of staff's retrospective distills
   the planted bug into a card; show the card PR (diff of card + index line),
   merge it.
8. **Second brain, read path** — re-open a *variant* of the planted bug; show
   the next session's narrative citing the card it read, and the token math
   (index + one card vs. re-derivation).
9. **Docs freshness** — its run finds the planted dead link; show the sweep
   count in the ledger entry and the ≤ 5-finding PR.
10. **Backlog groomer** — show the three seeded issues resolved three ways:
    verified-close (with the evidence named in the close comment), duplicate
    link, SLA breach escalated to the brief. Show the appended dated status
    section on the stale issue.
11. **Test gap** — the floor-raise PR with headroom evidence; merge it; show
    the ratchet guard now enforcing the higher floor.
12. **Dependency steward** — the one bounded upgrade PR with CVE delta in the
    ledger metrics.
13. **Liveness + the brief** — `tools/ledger.sh latest` (the watcher ring), the
    alert channel's one-line-per-agent day, and the chief of staff brief
    showing: nightly gate conclusions with dates, the stale-knowledge line, and
    the decisions-needed list. Then the negative proof: disable one agent's
    schedule for a day and show the missed-heartbeat alert — a dead agent and a
    healthy agent never look the same.

### C3. Demo acceptance criteria

- Every stop reproducible from a clean template instantiation by following
  `DEMO.md` (new file, the C2 list with exact commands) — no organic waiting.
- The whole tour's agent artifacts (issues, PRs, ledger lines, cards) remain in
  the demo repo afterwards as browsable evidence, indexed from its README.

---

## Sequencing across parts

Part A first (it is one PR and every later agent benefits from the read path),
then Part B one agent per phase, then Part C once at least docs freshness and
the groomer are live — the demo is most convincing when the tour has all
thirteen stops. Each phase is its own reviewable PR with tests and pins landing
in the same diff as the behavior they guard.

## Risks

- **Card sprawl / context creep** → index cap, 90-day staleness, fold-before-add,
  and the lint's hard limits (A5, A6.5).
- **A wrong lesson merged** → the operator's merge click is the same defense all
  instruction has; a bad card is a one-file revert.
- **New agents widen the blast radius** → every one is bounded (per-run caps,
  evidence-only actions), ledgered, pinned, and added one phase at a time.
- **Demo rot** → the demo is rebuilt from the template by script; `DEMO.md` is
  covered by the docs-freshness sweep like every other markdown file.
