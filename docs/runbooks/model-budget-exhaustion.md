# Model budget exhaustion — the agents' own budget, not the product's

<!-- placeholder: {{PRODUCT_NAME}} — the system your agents watch. tools/init.sh fills it in. -->

**This page covers the budget the agents themselves run on** — the subscription or key
behind `AGENT_CLI_TOKEN` (`credentials-and-cost.md`), which every scheduled routine, the
steward and the review workflow's judge role draw from. If {{PRODUCT_NAME}} itself calls
a model, that is a different budget with its own runbook; an agent that confuses the two
spends a run on the wrong console.

## What it looks like

Every scheduled agent stops at once. No routine writes a ledger entry, no run-summary
line arrives on the alert channel, no pull request gets a review. **The agents that
would normally notice are themselves stopped, so the in-fleet watcher ring reports it to
nobody** — a fleet with no budget cannot make it report anything. What does report it is
`.github/workflows/fleet-heartbeat.yml`: on the hosted runner, every six hours,
`tools/check-heartbeat.sh` reads every enabled agent's newest ledger entry against its own
`schedule:` and files an overdue-agents issue once the grace period has passed. Expect that
issue, not silence. Upstream, before that watch existed, five routines died on one day and
the cause was not named for a full day.

**Do not blame the scheduler.** Upstream the first three readings all pointed at the
scheduler console, and all three were wrong — nothing was disabled. Check the budget
before you open any investigation into schedules, locks or catch-up runs.

The reviewers meter separately from anything the product spends. A refused review job
ends in seconds and posts no review; the referee's notice names the missing reviewer and
quotes the refusal when the job log is readable (`agent-modes.md`, "Mode: merger" → the
one-reviewer clause). That is a reading of the budget, and it arrives days before the
routines go dark.

## Read the budget for free

Most agent CLIs print the account's live usage into every job log. Any recent review job
is therefore a reading, and it costs nothing:

```bash
gh run list --workflow=review.yml --limit 1 --json databaseId
gh run view <run-id> --log | grep -m1 -i 'utilization'
```

A session with no `gh` reads the same lines through the Actions API: list the runs of
`review.yml`, take the newest, list its jobs, and fetch the review job's log. Fetch the
log with an explicit start, not the default tail — a tail proves nothing about what the
job printed.

Four numbers come out of one reading, and you need all four (the field names are the
provider's; the shape is what matters):

| Field | What it means |
|---|---|
| the long-window utilization | share of the budget spent, `0.00`–`1.00` |
| the long-window reset time | when the window resets — **the end of the dark period** |
| the short-window utilization | the short-horizon budget; small here even on a dead morning |
| the overage flag | whether anything can buy past the wall — usually nothing can, by organisation setting |

## The arithmetic, and the mistake to avoid

Take the window start from the reset time minus the window length:

```
burn per day = utilization / (now - window start, in days)
the wall     = window start + (1.00 / burn per day) days
hours dark   = reset time - the wall
```

**Read the reset time, not only utilization.** Upstream, two agents got the wall right
and the length of the outage wrong on two days running, because they projected the 100%
date and then guessed how long it lasted. **An earlier wall leaves *more* of the window
to sit through, not less.** The reset time was in the same payload both times. Say
"inferred" in the sentence that first uses any value your run could not read at source.

## What an agent does about it

Nothing in the product changes. The fix is a spend limit in a console no agent can
reach, so this is an `operator-only` stop (`agent-routines.md`, efficiency rule 9) and
an S2 row in `agent-escalation.md`.

- Put it at the **top** of the decisions-needed list with the wall date and the dark
  hours.
- Name the console — the provider's usage or billing settings page — and the two actions
  that end it: raise the spend limit, or turn overage back on.
- It is done when a review job log no longer prints the overage-disabled flag.
- **Do not re-run a refused job.** The provider refuses the retry the same way.
- **A run that is refused mid-way writes no ledger entry.** Treat a missing entry from a
  day near the wall as "the budget stopped it", not as "the agent had nothing to say" —
  and never as a liveness failure of that agent.

## When the merger is enabled

A spent reviewer allowance writes no verdict, and the merge bar's review line alone can
stop every merge in the repository for days. The one-reviewer clause in `agent-modes.md`
("Mode: merger") is the deliberate, dated relaxation for exactly this case; the merge
comment must say the pull request was reviewed once, name the missing reviewer, and quote
its reset time.
