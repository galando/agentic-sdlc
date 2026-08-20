---
name: Probe the capability you need, not one that correlates with it
topic: probe-the-capability-you-need
type: rule
description: A health probe must exercise the exact operation the run needs; a read probe does not certify a write, and a secret's presence does not certify its validity.
symptoms: A credential passes a health check and the real operation is then refused; a fine-grained token works for reads and fails writes; a secrets.X || secrets.Y fallback chain picked a dead token; a job switched to a fallback because of a 502 or a timeout.
verified: 2026-08-20
related: [parked-pr-branch]
---

## The rule

Three distinctions, each of which has cost a run:

1. **A token that EXISTS is not a token that works.** A `secrets.PAT ||
   secrets.GITHUB_TOKEN` chain resolves once, when the env block expands, and only
   covers a secret being ABSENT. An expired PAT is still a non-empty string, so it wins
   the chain and there is nothing left to fall back to. If validity matters, the
   script must probe and carry its own fallback.
2. **A token that works is not a token that can do the job.** A fine-grained PAT with
   `Pull requests: write` and no `Contents: read` passes every REST read and is then
   refused on the GraphQL field `gh pr create` reads before it writes. **Probe the
   exact operation the run needs** — ideally the same API call the real work makes —
   not one that merely correlates with it.
3. **Only a REFUSAL is evidence about the token.** GitHub saying "you may not"
   (401/403/404, "not accessible") justifies switching to a fallback. A 502, a timeout
   or a reset connection says nothing about the credential — switching on it trades a
   guess for a real cost (here: every pull request opened on the fallback token loses
   its CI and its review). Keep ONE shared predicate for "is this a refusal", used by
   the start-of-run probe and every mid-run retry, so the two cannot drift apart.

Two companions: **re-check preconditions before retrying a non-idempotent write** (the
first attempt can fail *after* the side effect exists — re-ask before the retry, and a
lookup that cannot be made answers "no, do not retry"); and **a probe is not the work
it stands in for** — an unknown probe error keeps the preferred path and says so,
because the real operation will still surface a genuine refusal.

## Where this is mechanised

`tools/sweep-parked-branches.sh` is the worked example: `token_can_open_pull_requests`
runs the exact GraphQL read `gh pr create` makes, `looks_like_a_refusal` is the one
shared predicate, and a run that fell back exits 1 and reports `DEGRADED` — see
`docs/runbooks/parked-branch-sweep.md` and the "must not report success" standing
decision in `docs/runbooks/agent-modes.md`.
