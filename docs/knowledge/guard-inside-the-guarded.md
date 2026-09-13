---
name: A guard that runs inside the thing it guards
topic: guard-inside-the-guarded
type: rule
description: Name what kills the thing you are guarding, then ask whether the same event kills your guard; if it does, the guard must run somewhere else.
symptoms: A cleanup or health-check step reads SKIPPED after a failure; an if:always() step still did not run; a rollback, an alert or a secret-removal step is written into the job it protects; a pipeline took the system down and never noticed; you are about to add a safety step to a workflow you already have open; a scheduled job is itself one of the scheduled jobs it checks; a liveness check only runs while the thing it checks is alive; a fleet, queue or scheduler went quiet and the thing that should have said so was in it.
verified: 2026-09-11
related: [half-landed-fix, probe-the-capability-you-need]
---

## The rule

Write down what kills the thing your guard protects. Then ask whether that same event
kills your guard. If the answer is yes, the guard is decoration: it runs on the days you
do not need it and stops on the day you do.

`if: always()` does not solve this. It protects against a **failed step**. It cannot help
when the runner process itself goes away — a shutdown, a cancellation, a lost machine. The
step is never reached, so its condition is never evaluated.

## What it cost

Upstream, a deploy pipeline ran on a shared self-hosted box, and the box was shut down
between "stop the old container" and "start the new one". Production stayed down for over
an hour, and the pipeline hit this twice inside 90 seconds:

- The **"remove deploy key"** step carried `if: always()` and still read SKIPPED. The
  production key stayed readable on a box that also runs unreviewed pull-request builds.
- The **"health check"** step never ran either. The pipeline that took production down
  did not check that it came back.

It is not only about steps and `if:` conditions. A *schedule* can be the thing that dies.
Six days later the scheduler behind the agent fleet stopped. Every agent due after that
hour wrote no ledger entry — ten missed runs across five agents. The only check for a
dead schedule was the watcher ring, and each agent runs it during its own run, so it is
inside the fleet. Two of the five dead agents were the ones whose job is noticing this.
Nobody was told for 24 hours; it surfaced only because one early run happened to
survive. Had the outage begun an hour earlier, every agent would have been silent and
nothing would have said so.

## Where to put the guard instead

Somewhere the killing event cannot reach. This harness already has the machinery:
`ci-health-watch.yml` watches the self-hosted runner from the hosted one and pins its
notifier there too — a detector on a safe runner handing off to an alarm on the dead one
tells nobody. The `liveness.staleness-hours` check in `.agents/config.yml` reads the
newest entry across ALL agents, because a ring cannot notice every member stopping at
once (`docs/runbooks/agent-routines.md`, "Liveness on a best-effort scheduler"). A guard
that must survive the runner belongs in a job on another runner that fires on
`cancelled` as well as `failure`, or in a scheduled workflow that reads the end state
afterwards.

**Then check the guard's own silent path.** A guard that exits "nothing wrong" when it
could not do its job is the same bug one level up. Upstream's fleet heartbeat shipped
with that defect and review caught it: its table parser ran in a subshell, so a failure
to read the schedule exited the subshell only, the caller looped over nothing, and it
reported a healthy fleet. Make "I could not check" a loud, separate outcome from "I
checked and all is well", and write a test for it.
