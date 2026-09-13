---
name: A held branch is not a stop
topic: second-branch-is-yours
type: trap
description: The branch your session started on never caps how many pull requests you may open; create the second agent/... branch instead of recording a stop.
symptoms: You are about to leave a fix slot, a second pull request or a parked item undone because a pull request already holds your branch; your session prompt names one platform-assigned branch and you read that as a limit; a ledger entry records a second deliverable as blocked by a "guardrail" because a second open pull request needs a second head branch; you are about to push your deliverable to the platform-assigned branch; the same stop appears in your own entry two runs running.
verified: 2026-09-11
related: [parked-pr-branch, a-turn-that-ends-is-the-run]
---

## The trap

A scheduled run starts on a branch the scheduler picked, usually a random
platform-assigned name. The session prompt says to develop there and not to push
elsewhere without permission. Read alone, that sentence looks like a cap of one pull
request per run.

It is not. `AGENTS.md` guardrail 2 answers it directly:

> Whatever branch the session starts on, create and push your work to an
> `agent/<purpose>-<date>` branch.

The platform branch is plumbing. Your deliverable goes on your own branch, and a second
deliverable goes on a second one. Creating it is ordinary work.

## The case that named it

Upstream, a quality agent's mode grants two fix pull requests per run, the second
reserved for observability debt. Two runs running, it recorded the second slot as not
done, reason "guardrail": *a second open pull request needs a second head branch; this
session's instructions say to develop and push only on the platform branch, and a pull
request holds it.*

Both runs also pushed the fix they *did* build to the platform branch itself. Nothing
was refused; nothing was tried. On the same days, sibling agents in the same kind of
container pushed three `agent/...` branches without incident.

Two designed, evidenced observability fixes did not get built. One of them was an alert
that pages every night the pipeline is healthy.

## Why the rule did not stop it

Guardrail 2 says this inside a parenthesis, at the end of a paragraph about something
else. An agent that has already decided it is blocked does not go back and re-read the
guardrail. The instruction sits behind a door only opened by agents who already got past
the obstacle.

## How to avoid it

1. **Before you write "guardrail" as the reason something is not done, ask what refused
   you.** A guardrail is a rule that forbids the act. "I assumed I could not" is not a
   refusal, and neither is an untried command.
2. **A guardrail is never the reason for an unopened second pull request.** Open the
   branch: `git checkout -b agent/<purpose>-<date>` and push it.
3. **Push your deliverable to your own `agent/...` branch, never the platform-assigned
   one**, even when you only have one pull request to open. The parked-branch sweep
   (`docs/runbooks/parked-branch-sweep.md`) only looks at `agent/*`, so work left on
   the platform branch is invisible to the repair as well.
