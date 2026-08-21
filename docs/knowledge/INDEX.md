# Knowledge index

One entry per `rule`/`trap` card in this directory. Read this file first
(`AGENTS.md` session-start step); if a line's symptoms match your task, read that card
only. Hard cap: **80 lines**. See `README.md` for the card contract and the write path.

a-log-line-is-not-the-row — A signal emitted before a write, a validation gate, or a filter proves the attempt, not the outcome; verify at the boundary a consumer reads.
  Symptoms: A fix is being verified from a log line, a counter, or a "changed X to Y" message; the log says a value changed but the API/database/served page still shows the old one; a verification step reads the component that produced the change instead of the surface that serves it.

a-turn-that-ends-is-the-run — An agent that ends its turn "waiting" for subagents or follow-ups has ended its run; publish the deliverable before the turn ends, always.
  Symptoms: A run recorded success and its deliverable (a review, a comment, a pull request) never appeared; a transcript ends with "waiting for the last agent before I post"; work was completed in-context and nothing externally visible exists.

merge-is-not-deploy — Merging a fix does not run anything on the server; if its mechanism is a manual step, the fix is not live.
  Symptoms: A pull request merged and its checks are green, but the metric/config/rule it was supposed to change has not moved after a full deploy window; the fix's last step is a runbook line telling a human to run something over ssh.

parked-pr-branch — A run whose token died still pushed its branch; check the remote's branches before writing that nothing is in flight.
  Symptoms: An agent comment or ledger entry announces a fix and no pull request exists; an issue looks abandoned days after "fixing it now"; a run report mentions an expired token or a 401 from the API; you are about to write "no work is in flight" or "nothing shipped".

probe-the-capability-you-need — A health probe must exercise the exact operation the run needs; a read probe does not certify a write, and a secret's presence does not certify its validity.
  Symptoms: A credential passes a health check and the real operation is then refused; a fine-grained token works for reads and fails writes; a secrets.X || secrets.Y fallback chain picked a dead token; a job switched to a fallback because of a 502 or a timeout.
