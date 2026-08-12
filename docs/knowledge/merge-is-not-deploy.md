---
name: A merge is not a deploy
topic: merge-is-not-deploy
type: rule
description: Merging a fix does not run anything on the server; if its mechanism is a manual step, the fix is not live.
symptoms: A pull request merged and its checks are green, but the metric/config/rule it was supposed to change has not moved after a full deploy window; the fix's last step is a runbook line telling a human to run something over ssh.
verified: 2026-08-12
related: []
---

## The rule

A merged pull request proves the diff is correct. It proves nothing about whether
anything **ran** it. If the change's mechanism is "a human runs a script over ssh" or
any other manual step, the fix is not deployed the moment it merges — it is deployed
when that step actually executes, and nothing in the gauntlet checks that.

**So: when you open or review a fix, name the thing that will run the change, and say
when.** Acceptable answers are a deploy step, a scheduled job, or an idempotent script
the deploy already calls. If the honest answer is "a human runs a script over ssh", the
pull request is not finished — either fold the step into something that already runs,
or say plainly in the body that a manual step is outstanding and name it.

**The end-state signal for a fix is never the merge.** It is the metric, the served
rule, or the file the mechanism is supposed to produce — read that, per "Fix
verification" in `docs/runbooks/agent-routines.md`.

## Why this is a rule and not a one-off finding

Three incidents shared this shape before it was written down: an alert-rules file
edited and merged while production kept serving the old inode; rules shipped and never
loaded; and a fix whose Compose half deployed two minutes after merge while the half
that actually wrote the metric was a cron line in a setup script nothing but a human
over ssh ever invoked. Each time, the pull request was green, the diff was correct, and
production was unchanged — for a different mechanical reason each time, which is why the
rule is about *asking the question* rather than checking one specific mechanism.

## Where the full version lives

The complete rule, its "fix verification does not run itself" companion, and the
anchoring incidents are in `docs/runbooks/agent-modes.md`, "Standing decisions that
affect every agent". This card is the retrieval-cheap distillation; that section is the
evidence.
