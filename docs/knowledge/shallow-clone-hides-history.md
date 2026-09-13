---
name: A shallow clone hides every commit it did not fetch
topic: shallow-clone-hides-history
type: trap
description: An agent container's clone is shallow, so git finds no history for files that have plenty; never conclude "this never existed" before the depth check.
symptoms: git log or git log --all returns nothing for a path you expect to have history; you are about to write that a file, class, test or plan "was never built" or "has no git history at all"; a dead-reference or dead-code finding rests on a git search coming back empty; git blame is empty, or the repository reports far fewer commits than its age suggests.
verified: 2026-09-07
related: [log-tail-is-not-the-run]
---

## The trap

Agent containers clone the repository shallow, and so do the checkouts in `review.yml`
and `steward.yml` (`fetch-depth: 1`). `git log`, `git log --all` and `git blame` then
answer from the few commits that were fetched, and say nothing about the rest. They do
not warn you. An empty answer reads exactly like "this path never existed", which is the
strongest claim a docs or hygiene finding can make — and it is wrong.

Upstream, measured on one session: the clone held **50** commits; the full history was
**2309**.

The same day, the docs-freshness agent re-tested every "never existed" verdict it had
recorded after unshallowing. Three were false:

- A live-pipeline test class — added in one commit, deleted in a later one.
- A plan document — added on a branch that was never merged, and still alive there. A
  whole argument had been built on "no git history at all".
- Two service classes — both existed, both removed by named pull requests.

## What to do

Run the tripwire before any git-history search, and again before you write "never":

```bash
git rev-list --count HEAD                # a small number means shallow
git rev-parse --is-shallow-repository    # true means shallow
```

If it is shallow, fetch the history first and only then search:

```bash
git fetch --unshallow      # or: git fetch --deepen=<n> for a bounded dig
```

If you cannot unshallow, the honest finding is **"not found in the commits this clone
holds"**, with the depth stated. That sentence is still useful. "It was never built" is a
different claim and this clone cannot support it.

The harness already knows this in one place: `tools/sweep-parked-branches.sh` refuses to
run on a shallow clone, because every judgement it makes is a commit range
(`parked-branch-sweep.yml` checks out with `fetch-depth: 0`). Extend the same refusal to
any finding that rests on absence from history.
