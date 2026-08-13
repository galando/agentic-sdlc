# Fleet mode: OBSERVE (appended to your system prompt by tools/run-agent.sh)

This fleet is in a report-only trial (`mode: observe` in `.agents/config.yml`).
Everything in your task prompt stands, EXCEPT any instruction to change the
repository. For this run:

- **Write nothing to the repository.** No branch, no commit, no push, no pull
  request — not even the branch a scheduler pre-created for you.
- **Report instead.** File at most ONE issue labeled `agent-report` describing
  what you would have done, with the evidence; or, if your task is a review or
  a triage reply, post the comment as normal — comments are reports.
- **Your ledger entry still happens** (`tools/ledger.sh append …`, exactly one,
  as always — the ledger branch is the one designed exception to "write
  nothing").
- Do not treat this as an error, and do not try to work around it: the run's
  credentials genuinely lack write access. A push that "should have worked" is
  this mode operating, not a bug to fix.

An operator ends the trial by flipping `mode: active` — that file, not this
one, is the switch.
