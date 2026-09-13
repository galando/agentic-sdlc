---
name: A merged pull request can land half a fix
topic: half-landed-fix
type: trap
description: A merged pull request can land only half a fix; read its "what I did not do" before you treat the issue as finished, because the closed issue says nothing about the other half.
symptoms: An issue reads closed and the defect is still visible; you are about to delete a parked row, a TODO or a queue entry because its issue closed; a merged pull request added a script, a patch file or a flag that nothing calls; a fix's own body names a manual step; you are about to write "shipped" or "fixed" from a merge or a close alone; the repository carries a .patch file; an issue whose only remaining half is a human decision reads closed with no comment naming the decision; a pending item or a handoff names an issue that has closed since it was written; an issue closed with no closing pull request and no closing comment; you are about to take the top parked item and have not checked whether its work already shipped.
verified: 2026-09-11
related: [parked-pr-branch, merge-is-not-deploy]
---

## The trap

A pull request sometimes lands only the half it is allowed to land, and says so in its
own body. The merge closes the issue anyway. From then on every cheap signal — the issue
state, the merge, the green gauntlet — reads finished, and the only record of the
remaining half is a sentence inside a merged pull request nobody re-opens. Where a
merge closes its issue automatically, "closed" and "done" come apart on every merge,
by design.

## The case that named it

Upstream, a nightly security alert named no advisory, so nobody could tell the accepted
red from a new one. The fix merged as a tested shell script — and said, in bold, that it
changed no workflow and the alert would not print the new line until someone applied a
`.patch` file kept under `.github/`. The author could not push to `.github/workflows/`,
so it named an owner for the remainder and parked a row in the runbook.

What happened next is the trap, three times over:

1. The issue was closed `completed` on the merge.
2. A later pull request deleted the parked row because the fix was "fixed and merged"
   — reading the issue's state as the work's state.
3. Two nights on, the alert still named no advisory, the patch was still unapplied on
   the default branch, and the new script still had no caller.

Every step was individually reasonable. The work simply stopped being written down
anywhere.

## How to avoid it

1. **Never read a close as a completion.** Read the end state the issue described — the
   served value, the alert body, the page — not the issue state. When the remaining half
   is a decision, the end state is a comment naming the option taken; an issue that
   closes silently with open options on it has decided nothing.
2. **Read the merged pull request's "what I did not do" section.** Half-landed fixes
   almost always confess there, and so do bodies that name an owner for a remainder
   (`docs/runbooks/agent-communication-style.md` makes that section mandatory).
3. **A repository artifact with no caller is the tell.** A `.patch` file, a script, a
   flag or an endpoint that nothing references is usually one half of a pair. `git grep`
   the new file's name before you believe it is wired up.
4. **Never delete the remainder's only record** — a parked row, a queue entry, a pending
   item — on the strength of a closed issue.
5. **The same test runs the other way when you take a row.** A row outliving its work
   costs the next slot: upstream, a runbook still parked an item for an agent's fix slot
   while every clause of it was already on the default branch, so the agent's next fix
   would have gone to work that shipped the day before. Read the end state before you
   start, exactly as you would before you delete.

## Where this binds

`docs/runbooks/agent-routines.md`, "Fix verification": an issue closed on merge is a
claim awaiting verification, not a result. `merge-is-not-deploy` is the deploy-side
instance of the same rule; this card is the "half of the diff never landed" instance.
