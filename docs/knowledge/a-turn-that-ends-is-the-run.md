---
name: A turn that ends is the run ending
topic: a-turn-that-ends-is-the-run
type: trap
description: An agent that ends its turn "waiting" for subagents or follow-ups has ended its run; publish the deliverable before the turn ends, always.
symptoms: A run recorded success and its deliverable (a review, a comment, a pull request) never appeared; a transcript ends with "waiting for the last agent before I post"; work was completed in-context and nothing externally visible exists.
verified: 2026-08-20
related: [parked-pr-branch]
---

## The trap

An agent session only acts while its turn is open. A turn that ends without a tool
call IS the end of the run — there is no "after they finish": no pending subagent,
tool result, or follow-up ever returns to a turn that has ended. So a plan phrased "I
will post once they return" is a promise nothing in the system can keep, and the
runner records `success` because the turn ended cleanly.

Upstream, the second reviewer wrote a complete review twice in one week and ended its
turn waiting on subagents it had spawned. Both runs cost real money and minutes, both
recorded success, nothing reached the pull request — and each pull request read as
"reviewed twice" when it was reviewed once, which is how the loss stayed invisible.

## The rule

**The externally visible deliverable is the last mandated action of the run, and you
must take it before the turn ends.** Post the review, open the pull request, file the
issue — inside your own turn, never "after" anything. Two corollaries:

- **Partial beats lost.** Running short of room? Publish what you have, with one line
  saying what you did not get to. A partial review that reaches the pull request is
  worth more than a complete one that does not.
- **Remove the affordance where you can.** Where a role keeps losing its output to
  this trap, taking the subagent capability away from that role beats instructing
  around it — a shallower opinion that exists beats a deeper one that vanishes.

## Where this binds

`.agents/prompts/review-judge.md` and `review-challenge.md` carry the posting-last
rule verbatim, and `review.yml`'s per-role lost-review checks are the detectors: a
run that lost its review files a `[review-lost]` issue and exits non-zero, because a
green check on a lost deliverable is the whole defect.
