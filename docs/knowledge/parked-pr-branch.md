---
name: A pushed branch with no pull request is invisible
topic: parked-pr-branch
type: trap
description: A run whose token died still pushed its branch; check the remote's branches before writing that nothing is in flight.
symptoms: An agent comment or ledger entry announces a fix and no pull request exists; an issue looks abandoned days after "fixing it now"; a run report mentions an expired token or a 401 from the API; you are about to write "no work is in flight" or "nothing shipped"; a pull request has zero check runs while its neighbours have a full set; a sweeper-opened pull request says the reviewers ran and no review exists.
verified: 2026-09-01
related: [merge-is-not-deploy, probe-the-capability-you-need, second-branch-is-yours]
---

## The trap

A long run's `git push` and its API calls use **different credentials**. When the API
token expires mid-run, the code reaches the server and the pull request is never
opened — or the early draft is never marked ready. The work is finished, tested, and
pushed, and it is invisible in every place an agent normally looks: not an open issue,
not an open pull request. Upstream, six such branches sat for days — one carrying the
fix for a bug that kept firing the whole time — while two agents truthfully reported
"nothing is in flight", because in-flight was measured in issues and pull requests.

## How to avoid writing the false sentence

Before you write that an issue has no work in flight, look where a dead run's work
actually lands — the branches:

```
git ls-remote origin 'refs/heads/agent/*'
gh pr list --head <branch> --state all --limit 5 --json number
```

`[]` from the second command means **no pull request has ever existed, in any state** —
that branch is parked work. Anything else means it was shown to a human at some point.
Two readings to get right:

- **"Ahead of the base" proves nothing.** A squash-merged branch is never an ancestor
  of the base, so it stays "ahead" forever. Only the absence of a pull request is
  evidence of parked work.
- **A failed lookup is not a "no".** "Could not ask" and "no pull request exists" look
  identical, and acting on the wrong one opens a duplicate. Say the lookup failed.

## The follow-on trap: the sweeper's pull request gets no checks

Opening the pull request does not finish the recovery. **The platform starts no
workflow runs from an event created with the default workflow token**, and a
`secrets.X || secrets.Y` chain only covers a secret being *absent* — an expired token
is a non-empty string, wins the chain, and leaves no fallback
(`probe-the-capability-you-need`). So read this symptom as "create **or rotate**". On
the fallback the pull request exists and **nothing runs on it**: no tests, no reviewers,
no referee — even where its body says the automatic reviewers run on it like any other.
Upstream, a sweeper-opened pull request had **0 check runs 13 hours later**, against nine
each on two dependency-bot pull requests opened four hours earlier. **Count the check
runs.** Zero, while neighbours have a full set, means the fallback fired: say the pull
request carries no gate evidence, and never merge on it.

## The mechanism that owns the repair

You usually do not need to repair this by hand: `tools/sweep-parked-branches.sh`
(scheduled by `.github/workflows/parked-branch-sweep.yml`) opens the pull request a
dead run could not and promotes quiet drafts, and reports `DEGRADED` with exit 1 when it
had to fall back — `docs/runbooks/parked-branch-sweep.md`. The prevention half is
`AGENTS.md` guardrail 2: open the pull request **as a draft early**, while the token is
young, and mark it ready as your last step.
