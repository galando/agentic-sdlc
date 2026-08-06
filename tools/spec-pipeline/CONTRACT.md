# The spec-pipeline artifact contract

**Normative.** Versioned by `spec_contract` (currently `1`). Gate 21
(`.github/workflows/spec-artifacts.yml`) checks these artifacts, never a plugin or a
tool — that is what makes it enforceable on a fork running any vendor's agent CLI. Any
agent, on any provider, that produces these files in its diff satisfies gate 21.

```
.temper/specs/<slug>/intent.md      REQUIRED  problem, success criteria, BDD scenarios
.temper/specs/<slug>/plan.md        REQUIRED  approach decisions, files, blast radius
.temper/specs/<slug>/tasks.md       REQUIRED  ordered tasks, each with a validate line
.temper/specs/<slug>/design.md      OPTIONAL  complex features only
.temper/specs/<slug>/gates.json     REQUIRED  the gate ledger for this spec
.temper/build-state.json            OPTIONAL  repo-global pointer at the active spec
```

`<slug>` is a short, kebab-case name for the change — `fix-login-redirect`,
`add-export-csv`. One spec directory per change; do not reuse a slug for an unrelated
change later.

## `gates.json`

One JSON object, per spec, at `.temper/specs/<slug>/gates.json`:

```json
{
  "spec_contract": 1,
  "stages": {
    "plan":  { "verdict": "PASS", "ts": "2026-08-06T12:00:00Z",
               "requirements": [ { "name": "artifacts exist", "pass": true, "detail": "intent.md + tasks.md present" } ] },
    "build": { "verdict": "PASS_WITH_WARNINGS", "ts": "2026-08-06T13:00:00Z",
               "requirements": [ { "name": "RED then GREEN", "pass": true, "detail": "1 failing-first run(s), 1 passing run(s)" } ] }
  }
}
```

`verdict` is one of `PASS`, `PASS_WITH_WARNINGS`, `FAIL`. Gate 21 requires **at least
one** stage whose `verdict` is `PASS` or `PASS_WITH_WARNINGS` — a committed `FAIL` fails
gate 21; shipping a red gate ledger is never how the discipline gets satisfied.

**Why per-spec, not repo-global.** A repo-global `.temper/gates.json` conflicts on every
pull request once two feature branches are open at once — both branches rewrite the same
file, so every second PR carries a merge conflict in exactly the file gate 21 requires in
the diff. Keeping the ledger inside the spec directory means each PR's ledger lives at its
own path and cannot collide with another PR's. `validate.sh` also accepts a repo-global
`.temper/gates.json` if that is what a particular pipeline (a plugin) produces, preferring
the per-spec file when both exist — so a repo driving a plugin's own global-file
convention still passes.

## How an agent satisfies gate 21

1. **The build pipeline is present and reachable** (`.github/agent-temper-headless.md`
   "Availability is a finding, not an excuse"): run it normally. It produces this
   contract's artifacts as a side effect; nothing further is needed.
2. **The pipeline is genuinely absent**: drive this directory directly.
   - `tools/spec-pipeline/new-spec.sh <slug>` creates the directory from `templates/`
     and seeds `gates.json`.
   - Fill in `intent.md` (problem, success criteria, at least one scenario), `plan.md`
     (approach, files touched, blast radius) and `tasks.md` (ordered tasks, each with a
     `Validate:` line) by hand or with the agent's own reasoning — the pipeline plugin
     would have produced the same shape; only the tool that filled it in differs.
   - `tools/spec-pipeline/record-gate.sh <stage> <verdict> [name=pass:detail]...` appends
     a stage entry to `gates.json`. It never rewrites another stage's entry.
3. **Even that is unreachable**: fall back to a careful test-first change and say so once,
   in the pull request body, as `temper: unavailable — <the real reason>` — see gate 21's
   second accepted remedy below. Give the REAL reason; "unavailable" alone reads as a fact
   of the environment when it may be a fixable gap.

## Gate 21's algorithm, for reference (the real check lives in `validate.sh`)

1. PR carries none of `vars.SPEC_REQUIRED_LABELS` (default `fix,feature`) → pass, with a
   note. This is not a skip: the check reports success.
2. PR body contains `temper: unavailable — <reason>` (reason ≥ 10 characters, not one of
   `n/a`, `none`, `-`, `tbd`) → pass, with a warning annotation recording the reason.
3. Otherwise the **diff** (not the tree — a spec directory already on the default branch
   proves nothing about THIS change) must add or modify `intent.md`, `plan.md`,
   `tasks.md` and `gates.json` under one `.temper/specs/<slug>/`.
4. `gates.json` must parse, declare `spec_contract: 1`, and contain at least one stage
   whose `verdict` is `PASS` or `PASS_WITH_WARNINGS`.
5. On failure, the message names both remedies verbatim — see `validate.sh`.
