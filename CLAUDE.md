# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Read AGENTS.md first

`AGENTS.md` is the canonical, binding ruleset for every agent session here — guardrails,
memory/steering separation, fix verification, the session-start checklist. **The rules are
not repeated in this file.** A second copy is a second source of truth and it will drift;
`GEMINI.md` and `.github/copilot-instructions.md` are one-line pointers to AGENTS.md for
the same reason. This file covers what AGENTS.md deliberately does not: how to build and
test the harness, and the architecture you would otherwise have to read a dozen files to
reconstruct.

## What this repository is

A **GitHub template repository**, not an application. The deliverable is process
scaffolding: scheduled agents watch a running system, open pull requests, and a human
merges. `examples/` holds a deliberately small two-stack product so the gates have
something real to run against on day one — it is illustrative, and `tools/init.sh` offers
to delete it.

Consequence that catches people out: **the tree ships full of unresolved
double-brace tokens** and is *meant* to. `tools/init.sh` is the adoption interview that
resolves them; `ADOPTING.md` maps every one to its file. Until the interview runs, the
`provider:` key in `.agents/config.yml` still holds its token, so anything reading the
config resolves a literal placeholder rather than a provider name — which is why a fresh
clone cannot run an agent until it is initialised.

(This file deliberately does not spell those tokens out literally. `init.sh` substitutes
them wherever it finds them, so a live token quoted here as an example would be rewritten
into a statement that is no longer true.)

## Commands

```bash
# The harness suite — the main one. ~630 tests, seconds to run.
bats tests/ tests/harness-guards/

# A single file, or a single test by name
bats tests/ledger-roundtrip.bats
bats tests/ledger-roundtrip.bats -f "append writes one entry"

# Workflow lint — every workflow must pass with zero findings
actionlint .github/workflows/*.yml

shellcheck tools/*.sh tools/providers/*.sh tools/lib/*.sh

# De-identification sweep. Term-agnostic by design: it has no built-in list.
tools/check-deidentified.sh --terms <file>

# Print the exact argv a provider would run, invoking nothing
tools/run-agent.sh <agent> --dry-run
tools/run-agent.sh --list-agents
tools/run-agent.sh --check-credentials <agent>
tools/run-agent.sh --adapter-status <provider>
```

Example product (only if you are touching `examples/`):

```bash
cd examples/backend  && mvn clean test            # add -DskipITs to skip integration
cd examples/frontend && npm run test:coverage     # also: lint, build, test:e2e, audit:ci
```

Note `tests/` exercises **the harness**; `examples/*/src/test` exercises the example
product. They are separate suites with separate purposes — a change to `tools/` is covered
by the former, never the latter.

## Architecture

**Provider indirection is the spine.** Nothing vendor-specific may appear in a workflow, a
runbook or a prompt. The chain is always:

```
workflow  ->  tools/run-agent.sh  ->  tools/providers/<name>.sh  ->  the vendor CLI
                     ^
              .agents/config.yml  (provider + model per ROLE)
```

Models are addressed by **role** — `judge`, `execute`, `challenge` — never by task and
never by vendor name. `tools/lib/config.sh` is the *only* parser of `config.yml` and
`floors.yml`; adapters must never read the config themselves. Adapters declare
`ADAPTER_STATUS=verified|unverified`, and an unverified one refuses to run rather than
guessing at flags. `tests/harness-guards/vendor-neutrality.bats` enforces that vendor names
appear only in `tools/providers/` and `.agents/config.yml`.

Root resolution is single-sourced through `AGENTS_ROOT`: `run-agent.sh` exports it from its
own location, and `_cfg_root()` honours it before falling back to `git rev-parse`. Without
that, a vendored copy reads one repo's config while running another's adapter.

**Two kinds of agent.** Scheduled agents are a cron plus a fixed prompt in
`.agents/prompts/<agent>.md`, each a fresh session with no memory
(`.github/workflows/agents-scheduled.yml`). The event-driven steward wakes on an issue or a
mention (`.github/workflows/steward.yml`).

**The gates** live in `docs/QUALITY-GATES.md` (inventory + ratchet policy) and are split
FAST (blocking, every PR) and FULL/nightly. Two tiers matter architecturally:

- **Ratchet guards** — assert no floor was lowered, no threshold deleted, no exclude
  widened. Without them every number elsewhere is only a convention.
- **Harness guards** (`tests/harness-guards/`) — text-pin the load-bearing strings inside
  the agent workflows themselves. `pins.json` is the inventory; `gen-pin-tests.sh`
  generates `pins.generated.bats` from it, so the assertion count equals the entry count
  and a lost lesson cannot pass quietly. Regenerate rather than hand-editing the generated
  file.

Floors live in `floors.yml` and ship as `unset` sentinels that pass **loudly**;
`tools/measure-floors.sh` arms them against the adopter's own baseline. Never lower one to
make something pass — see the ratchet policy in `docs/QUALITY-GATES.md`.

**Ledgers are history, never instruction.** `tools/ledger.sh` appends one JSON line per run
per agent to `ledger/<agent>.jsonl` on the orphan `agent-ledger` branch, via a throwaway
clone of the *remote* (cloning the local checkout makes the push land on a local ref and
report success while nothing reaches the server). Instructions reach agents only through
`docs/runbooks/agent-modes.md` on the protected branch, plus the two sheets
`tools/run-agent.sh` injects into the system prompt (`.github/agent-temper-headless.md`
always; `.agents/observe.md` when `mode: observe`) — which also live on the protected
branch, so the same write-permission argument covers them.

**Spec artifacts are the contract, not the plugin.** `tools/spec-pipeline/` is the
provider-neutral scaffold producing the same spec directory and gate ledger a pipeline
plugin would; `tools/spec-pipeline/CONTRACT.md` defines what gate 21
(`.github/workflows/spec-artifacts.yml`) checks. An adapter either delegates to the plugin
or drives this scaffold.

## Things that will bite you

- A required status check must **always report**. Skip it with a job-level `if:` (reports
  "skipped", which counts as passing), never a workflow-level `paths:` filter — that
  creates no check run at all and the PR waits forever. `docs/runbooks/branch-protection.md`
  lists which contexts are safe to require, by exact string.
- A comment on a PR has **two homes** (conversation and inline); any collector must read
  both endpoints and merge. Related: `--paginate` with a per-item `--jq` filter applies the
  filter once *per page* — slurp, flatten, then filter.
- A reusable workflow cannot hold more permission than its caller, so every caller of
  `nightly-alert.yml` must declare `permissions: {contents: read, issues: write}`.
- Events created with `GITHUB_TOKEN` do not trigger workflows.
- A missing **optional** credential degrades a check — it never cancels one and never fails
  a PR.
