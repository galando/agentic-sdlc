# Knowledge index

One entry per `rule`/`trap` card in this directory. Read this file first
(`AGENTS.md` session-start step); if a line's symptoms match your task, read that card
only. Hard cap: **80 lines**. See `README.md` for the card contract and the write path.

a-log-line-is-not-the-row — A signal emitted before a write, a validation gate, or a filter proves the attempt, not the outcome; verify at the boundary a consumer reads.
  Symptoms: A fix is being verified from a log line, a counter, or a "changed X to Y" message; the log says a value changed but the API/database/served page still shows the old one; a verification step reads the component that produced the change instead of the surface that serves it.

a-turn-that-ends-is-the-run — An agent that ends its turn "waiting" for subagents or follow-ups has ended its run; publish the deliverable before the turn ends, always.
  Symptoms: A run recorded success and its deliverable (a review, a comment, a pull request) never appeared; a transcript ends with "waiting for the last agent before I post"; work was completed in-context and nothing externally visible exists.

guard-inside-the-guarded — Name what kills the thing you are guarding, then ask whether the same event kills your guard; if it does, the guard must run somewhere else.
  Symptoms: A cleanup or health-check step reads SKIPPED after a failure; an if:always() step still did not run; a rollback, an alert or a secret-removal step is written into the job it protects; a pipeline took the system down and never noticed; you are about to add a safety step to a workflow you already have open; a scheduled job is itself one of the scheduled jobs it checks; a liveness check only runs while the thing it checks is alive; a fleet, queue or scheduler went quiet and the thing that should have said so was in it.

half-landed-fix — A merged pull request can land only half a fix; read its "what I did not do" before you treat the issue as finished, because the closed issue says nothing about the other half.
  Symptoms: An issue reads closed and the defect is still visible; you are about to delete a parked row, a TODO or a queue entry because its issue closed; a merged pull request added a script, a patch file or a flag that nothing calls; a fix's own body names a manual step; you are about to write "shipped" or "fixed" from a merge or a close alone; the repository carries a .patch file; an issue whose only remaining half is a human decision reads closed with no comment naming the decision; a pending item or a handoff names an issue that has closed since it was written; an issue closed with no closing pull request and no closing comment; you are about to take the top parked item and have not checked whether its work already shipped.

issue-count-is-a-band — An issue's headline count can fall to zero while its defect is still live; measure the property, not the value.
  Symptoms: An issue's own number reads fixed but the defect is still visible; a count fell with nothing merged; a count fell because a record was destroyed, not repaired; you are about to close or downgrade an issue because its headline number moved; a new issue looks like a duplicate of an old one whose count says it is solved; you are about to report a red gate, a failing job or an open issue as a live problem without checking whether that failure is already an accepted decision.

log-tail-is-not-the-run — A log fetch returns the tail by default; finding nothing there proves nothing about the run.
  Symptoms: You grepped a job log and are about to write that something did not happen; a "no failure found" conclusion drawn from a log API, tail, or a line-capped fetch; you are about to warn against a pull request because its cause is absent from a log; a search over a truncated log is being used as proof of absence.

measure-the-property-not-the-value — A metric, band or skip guard reads a value something else resets; name the property first, then ask what moves your reading without moving it.
  Symptoms: A metric reads the same figure over 24h and over 7d; a counter or gauge lives in process memory and the process restarts many times a day; a query uses last_over_time, increase() or a tail and the process behind it restarts; a guard skips work because a timestamp has not moved; an issue's meaning changed and no event landed on the issue; you read a level at one moment and call it a daily minimum, maximum or average; a projection names a start date and you have not read the field that names the end; a band retires or confirms on a part-day reading; two sources print the same log line and your band keys on that line.

merge-is-not-deploy — Merging a fix does not run anything on the server; if its mechanism is a manual step, the fix is not live.
  Symptoms: A pull request merged and its checks are green, but the metric/config/rule it was supposed to change has not moved after a full deploy window; the fix's last step is a runbook line telling a human to run something over ssh.

parked-pr-branch — A run whose token died still pushed its branch; check the remote's branches before writing that nothing is in flight.
  Symptoms: An agent comment or ledger entry announces a fix and no pull request exists; an issue looks abandoned days after "fixing it now"; a run report mentions an expired token or a 401 from the API; you are about to write "no work is in flight" or "nothing shipped"; a pull request has zero check runs while its neighbours have a full set; a sweeper-opened pull request says the reviewers ran and no review exists.

probe-the-capability-you-need — A health probe must exercise the exact operation the run needs; a read probe does not certify a write, and a secret's presence does not certify its validity.
  Symptoms: A credential passes a health check and the real operation is then refused; a fine-grained token works for reads and fails writes; a secrets.X || secrets.Y fallback chain picked a dead token; a job switched to a fallback because of a 502 or a timeout.

second-branch-is-yours — The branch your session started on never caps how many pull requests you may open; create the second agent/... branch instead of recording a stop.
  Symptoms: You are about to leave a fix slot, a second pull request or a parked item undone because a pull request already holds your branch; your session prompt names one platform-assigned branch and you read that as a limit; a ledger entry records a second deliverable as blocked by a "guardrail" because a second open pull request needs a second head branch; you are about to push your deliverable to the platform-assigned branch; the same stop appears in your own entry two runs running.

shallow-clone-hides-history — An agent container's clone is shallow, so git finds no history for files that have plenty; never conclude "this never existed" before the depth check.
  Symptoms: git log or git log --all returns nothing for a path you expect to have history; you are about to write that a file, class, test or plan "was never built" or "has no git history at all"; a dead-reference or dead-code finding rests on a git search coming back empty; git blame is empty, or the repository reports far fewer commits than its age suggests.
