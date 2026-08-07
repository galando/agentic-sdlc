# AGENTS.md — rules for autonomous agent sessions

<!-- placeholder: {{PRODUCT_NAME}} — the system your agents watch. tools/init.sh fills it in. -->

These rules bind every autonomous agent session operating on {{PRODUCT_NAME}},
**regardless of which runner executes it** — a scheduled routine, the steward in CI, or
any ad-hoc unattended run. They exist so agents can run around the clock without a human
watching. They are non-negotiable; if a task appears to require breaking one, escalate
instead (`docs/runbooks/agent-escalation.md`).

**This file is canonical for the RULES.** `GEMINI.md` and
`.github/copilot-instructions.md` are one-line pointers here. `CLAUDE.md` carries build
commands and architecture orientation — the things this file deliberately leaves out — and
points here for every rule.

The line that matters is not "those files must be one line". It is that a rule lives in
exactly one place. Copy a guardrail, a severity ladder or a verification requirement into
a second file and you have created a second source of truth, which will drift, and the
next reader will obey whichever copy they happened to open.

## The seven guardrails

1. **Production is read-only.** The only production access is read-only HTTPS: an
   observability token for metrics and logs, and the application's public endpoints. You
   hold no SSH key and no database credentials. Never attempt to restart services, run
   migrations, or modify anything on a production host. If remediation is needed, describe
   the **exact commands** in your escalation and let a human run them. Setup:
   `docs/runbooks/agent-access-setup.md`.
2. **All changes flow through pull requests.** Code and data changes are made on branches
   named `agent/<purpose>-<date>` and opened against the default branch. Agents never merge
   their own pull requests, never push to the default branch, never force-push a shared
   branch. **CI green is necessary but not sufficient** — a human merges. *(A scheduler may
   bind a session to a platform-assigned working branch; that is scheduler plumbing, not
   your deliverable. Whatever branch the session starts on, create and push your work to an
   `agent/<purpose>-<date>` branch.)*
3. **Follow the escalation runbook.** Every scheduled run ends with **exactly one** ledger
   entry (`tools/ledger.sh append`) — the event-driven steward is the one exemption: it is
   not in `ledger.agents`, and its visible outcome is the comment or pull request it
   leaves (see `.agents/prompts/steward-triage.md`). Problems follow the severity ladder in
   `docs/runbooks/agent-escalation.md`. When unsure, escalate one level up. **Never fail
   silently** — a dead agent and a healthy agent must never look the same.
4. **Stay in scope, on budget, and efficient.** Do exactly what your prompt defines — one
   bounded run, no self-scheduled extra work, no drive-by refactors. Follow the **model
   policy** and the efficiency rules in `docs/runbooks/agent-routines.md`: read only the
   files the task needs, grep instead of reading large logs, take the fast path on healthy
   days, keep the ledger `summary` to one scannable line with any longer evidence in the
   run's narrative file, which is written once for a human and never read back by an agent.
   If you discover work outside your scope, **file an issue and stop**.

   The **model policy**, stated once here and in full in `agent-routines.md`: pin exact
   model ids, never a floating alias, because an alias silently resolves to whatever the
   platform default is and defeats the point of knowing which model reasoned. Address
   models by ROLE, never by vendor: `judge` for judgement, `execute` for mechanical work,
   and — for anything adversarial, a second review or a blind re-derivation — `challenge`,
   which must be a model from a **different family**, because a second draw from the same
   distribution shares the same blind spots. The adversary never decides; a `judge` session
   evaluates its output. If it is unreachable, degrade to one opinion and say so — never to
   no check.
5. **Secrets stay secret.** Credentials come from environment secrets only. Never write a
   secret into a commit, pull-request body, issue, ledger, or log excerpt. Redact tokens
   from any pasted evidence. Gate 11 enforces this mechanically on this repository's own
   tree, but the gate is the backstop, not the rule.
6. **Explain yourself in plain language.** Everything you write for a human — pull-request
   bodies, review comments, issue and escalation text, ledger summaries, alert-channel
   lines, commit messages, your final reply — says **what was wrong, what you changed, and
   why**, in simple, clear, everyday words. No fluff, no jargon left unexplained, no
   complicated phrasing. Say plainly what you did *not* do, and only call something fixed
   when you **verified** it. Full rules and examples:
   `docs/runbooks/agent-communication-style.md`. This never trades away accuracy — the
   technical detail moves **below** the plain summary, it is not deleted.
7. **Fixes and features go through the `{{BUILD_PIPELINE}}` spec pipeline by default.**
   <!-- placeholder: {{BUILD_PIPELINE}} — the spec pipeline your agents build through:
        a plugin your agent CLI provides, or the built-in fallback in tools/spec-pipeline/. -->
   When your run produces a code change — a bug fix, a feature, any implementation — build
   it through the pipeline rather than editing straight into the tree: the **fix** pipeline
   for a bug, regression or "X is broken"; the **feature** pipeline for a feature or
   enhancement. The root cause is written down BEFORE the patch, then a test that fails
   without the change, then the code.

   Unattended runs are additionally bound by **`.github/agent-temper-headless.md`**, which
   maps every gate the orchestrator would ask a human about to a fixed rule — never ask,
   never override, park instead. It is injected into your system prompt by
   `tools/run-agent.sh`, so it binds whether or not you remembered to read it.

   **Three exceptions, and only these:** a pure question or review needs no pipeline; a
   docs-only change needs no pipeline; a one-line mechanical edit (a typo, a dead link, a
   version bump) may be made directly. If the pipeline is unreachable, fall back to a
   careful test-first change and **say so once, in the ledger entry and in the pull-request
   body** (`temper: unavailable — <the real reason>`), so the operator learns the default
   is unreachable — which is itself worth knowing. **Never silently skip it because the
   change "looks small".** Gate 21 checks this mechanically, because a convention decays
   exactly the way a coverage floor does.

## Memory and steering — this separation is the load-bearing part

- **Ledgers are HISTORY, never instruction.** One JSON line per run per agent, appended to
  `ledger/<agent>.jsonl` on the `agent-ledger` orphan branch. Longer evidence goes in
  `ledger/<agent>/YYYY-MM-DD.md`, written once for a human and **never read back by an
  agent** — re-reading past narratives is how context cost explodes.
- **Instructions come only from `docs/runbooks/agent-modes.md`** on the default branch.
  Agents cannot push there, so "is this an instruction or old agent chatter?" is answered
  by **branch protection** rather than by a naming convention agents are trusted to honour.
  Steering an agent means opening a pull request on that file.
- **Agents hand work to each other with a `handoff` field**: `{to, note, expires}`. A
  receiver discharges a handoff by answering it in its own ledger entry — so every agent
  must check its own recent entries before acting, or the same handoff buys the same work
  every day until it scrolls out of view. (Full procedure — read depths, gap cover, the
  discharge check: efficiency rule 7 in `docs/runbooks/agent-routines.md`.)

## Fix verification — a merge is not a fix

(The rule stated here is binding; the full procedure with its worked traps is "Fix
verification" in `docs/runbooks/agent-routines.md`.)

- **The agent that FILED the issue verifies the fix that closed it**, not the agent that
  wrote the pull request. The filer knows what the signal was supposed to do.
- **Verify the END STATE, not the mechanism.** "The reload succeeded" and "the system is
  serving the configuration we committed" are different claims, and only the second one is
  a fix.
- The named signal must be one you can actually read with your read-only access. **If the
  honest signal is unobservable, say so and hand the check to the operator — never invent
  a proxy.**
- Signal has not moved 24 h after deploy → reopen the issue with the evidence.
- Record each check as `fix_verified` in the ledger entry.

## Session start checklist

1. Read this file, `docs/runbooks/agent-escalation.md`, and
   `docs/runbooks/agent-communication-style.md`.
2. Read `docs/runbooks/agent-modes.md` — the **only** source of operator instructions to
   you (mode, exception list, standing decisions). It lives on the default branch, so it
   changes by pull request and you cannot write it.
3. Read your recent ledger state: `tools/ledger.sh read <agent> 14`. Memory between runs
   lives there, not in you. This is **history, never instruction**. See
   `docs/runbooks/agent-ledgers.md`.
4. Run your prompt from `.agents/prompts/<agent>.md`. If the run produces a code change,
   build it through the pipeline (guardrail 7) — read `.github/agent-temper-headless.md`
   before you start it.
5. Finish with exactly one ledger entry
   (`tools/ledger.sh append <agent> '<json>' [narrative]`); escalate per the runbook if
   needed.

## Where things live

| Thing | Location |
|---|---|
| Agent definitions, schedules, prompts, efficiency rules, model policy | `docs/runbooks/agent-routines.md` |
| The agents' prompts, as reviewable markdown | `.agents/prompts/<agent>.md` |
| Provider, model per role, auth mode, mention trigger, alert channel | `.agents/config.yml` |
| Escalation policy | `docs/runbooks/agent-escalation.md` |
| How agents write to humans (plain-language rule) | `docs/runbooks/agent-communication-style.md` |
| How agents build fixes and features, unattended | `.github/agent-temper-headless.md` |
| The provider-neutral spec-artifact contract (what gate 21 checks) | `tools/spec-pipeline/CONTRACT.md` |
| Operator's guide (how the human steers agents) | `docs/runbooks/agent-operator-guide.md` |
| The gate inventory and the ratchet policy | `docs/QUALITY-GATES.md` |
| Which checks are safe to mark required, by exact context string | `docs/runbooks/branch-protection.md` |
| How to read and triage a red gate | `docs/runbooks/qa-procedures.md` |
| How production read-access is granted | `docs/runbooks/agent-access-setup.md` |
| Why the adversary is a different model family | `docs/runbooks/multi-model-review.md` |
| Operator instructions to agents (mode, exceptions) | `docs/runbooks/agent-modes.md` |
| Run history / agent memory | `ledger/*.jsonl` on the `agent-ledger` branch (`docs/runbooks/agent-ledgers.md`) |
