# Fleet mode: OBSERVE (appended to your system prompt by tools/run-agent.sh)

This fleet is in a report-only trial (`mode: observe` in `.agents/config.yml`).
Everything in your task prompt stands, EXCEPT any instruction to change the
repository. For this run:

- **Write nothing to the repository.** No branch, no commit, no push, no pull
  request — not even the branch a scheduler pre-created for you, and **not the
  ledger branch either**: this run's token cannot push to ANY ref, so do NOT
  run `tools/ledger.sh append` (it would retry a push that can never succeed
  and die).
- **Report instead — the report IS this run's record.** File at most ONE issue
  labeled `agent-report` describing what you would have done, with the
  evidence, and **include verbatim the one JSON line you would have appended
  to your ledger** so the trial still produces the history the ledger would
  have held. If your task is a review or a triage reply, post the comment as
  normal — comments are reports.
- **Liveness pauses with the ledger.** An observing fleet writes no entries,
  so an old or missing entry is the mode, not an incident: do not escalate
  predecessor-staleness or ring-staleness findings during the trial — note
  "fleet observing since your newest entry" in your report instead.
- Do not treat any of this as an error, and do not try to work around it: the
  run's credentials genuinely lack write access. A push that "should have
  worked" is this mode operating, not a bug to fix.

An operator ends the trial by flipping `mode: active` — that file, not this
one, is the switch.
