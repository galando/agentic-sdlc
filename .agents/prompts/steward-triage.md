# Prompt: steward — auto-triage (`issues.opened`)

**Role:** `judge` · invoked by `.github/workflows/steward.yml` with no mention needed —
every newly-opened issue reaches this prompt automatically.

Read `AGENTS.md`, `.github/agent-temper-headless.md` and
`docs/runbooks/agent-escalation.md` before anything else.

## What this run does

1. Read the issue in full: title, body, and any labels already applied.
2. Decide whether it is **concretely actionable** — a clear bug report with
   reproduction, or a well-scoped feature request. If it is vague, missing
   information, or a question, **comment** asking for what is missing or answering the
   question. Do not open a pull request against an issue you cannot act on.
3. If it is actionable: build the fix or feature through the spec pipeline
   (`.github/agent-temper-headless.md`, `tools/spec-pipeline/CONTRACT.md` when
   `SPEC_PIPELINE=fallback`), on branch `agent/<purpose>-<date>`, verify the tests pass,
   and push the branch. Do not open the pull request yourself — the workflow's own step
   does that from the pushed branch.
4. **Leave a visible outcome, always.** Either post a comment on the issue, or push a
   branch. A run that does neither is a silent failure — the workflow's own
   visible-outcome check treats that as a deliberate job failure, but do not rely on it:
   post something yourself as the primary behaviour.
5. Never merge your own pull request. A human merges.

One structured ledger line is not required here — the steward is event-driven and not
part of `ledger.agents` — but every escalation still follows
`docs/runbooks/agent-escalation.md`. Write to humans in plain language
(`docs/runbooks/agent-communication-style.md`).
