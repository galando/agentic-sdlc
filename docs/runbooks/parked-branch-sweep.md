# The parked-branch sweep — invisible work, made visible

`tools/sweep-parked-branches.sh`, scheduled by
`.github/workflows/parked-branch-sweep.yml` every three hours. Behavioural
guards: `tests/sweep-parked-branches.bats`.

## The failure it repairs

A long agent run outlives its API credential. `git push` authenticates with one
credential and the `gh` API calls with another, so a run whose API token
expires mid-run **pushes its finished, tested work and then cannot open the
pull request** — or cannot mark ready the draft that guardrail 2 told it to
open early. The code reaches the server; the report does not. Upstream, in the
running system this template was extracted from, six such branches sat
invisible for days — one carried the fix for a data-corruption bug that kept
corrupting data the whole time — while agents truthfully reported "nothing is
in flight", because "in flight" was measured in issues and pull requests, not
branches.

Both halves of the lesson ship:

- **Prevention** (AGENTS.md guardrail 2): push the branch early and open the
  pull request **as a draft right then**, before the long test runs, while the
  token is young. Marking it ready is the last thing a run does.
- **Repair** (this sweep): a scheduled job with a fresh token makes whichever
  API call the dead run could not — open the pull request, or promote the
  quiet draft — so a run that dies reaches the same end state as one that
  finishes. Only the merge is left, and that is a human's job anyway.

## What one run does

For every `agent/*` branch on the remote:

| Branch state | Sweep action |
|---|---|
| Tip younger than 90 min (`--grace-minutes`) | Waits — its own run may still be working |
| Tip older than 14 days (`--max-age-days`) | Skips — stale work is not resurrected |
| Merged with a real merge commit | Nothing — the tip is already in the base |
| No pull request has ever existed | Opens one, **ready for review**, so both reviewers fire |
| Open draft, quiet ≥ 180 min (`--promote-after`) | Marks it ready — `ready_for_review` starts the reviewers |
| Open draft, quieter less than that | Waits |
| Open non-draft pull request | Nothing |
| A pull request (any state) exists for this exact tip | Nothing — merged, or closed on purpose |
| A pull request closed, then more commits were pushed | **leftover** — reported, never auto-opened |
| GitHub could not be asked | **UNKNOWN** — skipped, and the run fails |

At most `--limit` (default 10) pull requests per run; anything past the cap is
named in the summary as deferred, because a cap that hides what it dropped
reads as "everything is covered".

The pull-request title comes from the saved report the run committed when it
could not post (`*pr-body*.md`, `*pr-comment*.md`, or the
`.temper/autonomy-reports/<slug>.md` guardrail 7 requires), else the first
behaviour-changing commit, else the branch name — never the tip commit, which
on a parked branch usually records the accident, not the work. The body embeds
the saved report, the commit list, and a warning when the branch no longer
merges cleanly.

## The three nevers

1. **Never a second pull request.** Every decision hangs on a `gh pr list`
   answer, so a lookup that fails stops that branch and fails the run —
   "could not ask" must never read as "no pull request exists". The create is
   retried at most once, and only after re-asking GitHub that no pull request
   appeared in between.
2. **Never resurrect squash-merged work.** A squash-merged branch is never an
   ancestor of the base, so it stays "ahead" forever. Being ahead proves
   nothing; only the absence of a pull request does. Commits pushed after a
   pull request closed are reported as `leftover` for a human to cherry-pick.
3. **Never take a branch from a live run** — the grace window and the
   promote-after threshold exist for exactly this.

## The token, and the degraded mode

The workflow hands the sweep `STEWARD_HANDOFF_PAT` (falling back to
`GITHUB_TOKEN`), because GitHub does not start workflow runs from events
created with `GITHUB_TOKEN` — a pull request opened with the default token
gets **no CI and no review**. For this job the PAT needs **`Contents: read`
as well as `Pull requests: write`**: `gh pr create` reads
`repository.defaultBranchRef` before it writes, and a PAT missing the read
half passes every liveness probe and is then refused on every create.

The script therefore probes **the exact GraphQL read `gh pr create` makes**,
not a probe that merely correlates with it, and distinguishes two kinds of
error with one shared predicate:

- **A refusal** (401/403/404, "not accessible") is evidence about the token →
  fall back to `GITHUB_TOKEN`, once.
- **Anything else** (a 502, a timeout) says nothing about the token → keep
  the preferred token and say so. Falling back on a guess would cost every
  later branch its CI and review.

A run that fell back **exits 1 and prints a `DEGRADED:` line** in the summary
and the step summary, even when every pull request opened fine — a visible
pull request beats a lost one, but an unreviewed pull request that nothing
checks needs a human told. Upstream, before that rule, a fallback run stayed
green and its unreviewed pull request sat twelve hours with zero checks.

## Exit codes, and the repair for each

| Exit | Meaning | Repair |
|---|---|---|
| 0 | Nothing needs a human | — |
| 1 | A lookup failed (`UNKNOWN`), a create/promotion was refused (`FAILED`), **or the run fell back to `GITHUB_TOKEN`** (`DEGRADED`) | For `UNKNOWN`/`FAILED`: read the run's sweep summary and open the named pull requests by hand — after checking none exists. For `DEGRADED`: fix or re-issue `STEWARD_HANDOFF_PAT` (it can exit 1 with nothing `UNKNOWN` or `FAILED` — that is the degraded case, and re-running the sweep repairs nothing until the PAT is fixed) |
| 2 | The run could not start: no token, no `gh`, no `jq`, or a shallow clone | Fix the environment; nothing was swept |

A non-zero exit routes through `nightly-alert.yml`: one tracking issue per
gate, updated rather than re-filed, so a cause that persists across the
3-hour schedule does not page on every tick.

## Running it by hand

```bash
GH_TOKEN=... tools/sweep-parked-branches.sh --dry-run   # report, touch nothing
GH_TOKEN=... tools/sweep-parked-branches.sh             # do it
```

From the Actions tab, `workflow_dispatch` defaults to a dry run. A hand-run
needs a full clone — the script refuses a shallow one, because every judgement
it makes is a `base..branch` commit range and grafted history makes those
ranges fiction.
