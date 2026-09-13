# The review follow-up sweep — an issue only for findings that reached the default branch

`tools/review-followup-sweep.sh`, run by `.github/workflows/review-followup-sweep.yml`
when a pull request closes and once a day as a backstop. Behavioural guards:
`tests/review-followup-sweep.bats`. Not to be confused with `review-sweep.yml`, which
reports a *cancelled* review run and files nothing.

## What was wrong

When the referee ruled a pull request's findings non-blocking, the review workflow filed
a `[review-followup]` issue right then — while the pull request was still open. Upstream,
in the running system this template was extracted from, that produced 166 issues in one
month. Most were filed against a pull request that merged about two hours later, and by
then the author had usually fixed the finding on the branch. About two thirds of those
issues were closed with "already fixed". Every one still cost an agent session to read
and close.

## What this does

The review workflow now **labels** the open pull request `review-followup-pending` and
posts the findings on it under `### Review follow-up: clear these before you merge`. The
author clears the label when the findings are handled. This sweep reads the label after
the pull request closes:

| Pull request state | Sweep action |
|---|---|
| Merged, label still on | Files **one** issue: `[review-followup] Non-blocking findings on merged PR #N`, with the referee's comparison embedded in a collapsible block. Then removes the label. |
| Merged, label cleared | Nothing. The author handled it before merging. |
| Closed without merging | Comments on and closes (`not planned`) any open follow-up issue for that pull request. **The label stays on.** |
| Could not read the pull request | Files the issue anyway and the run goes red. "Could not look" is never "nothing to do". |

The daily run (`--scan --limit 50 --days 14`) lists every pull request closed in the last
14 days that still carries the label and does the same for each. It exists because two
merges never produce a `pull_request: closed` run this workflow can act on:

- a merge performed with `GITHUB_TOKEN` starts no workflow run at all;
- a pull request from a fork gets a read-only token, so its event run cannot file.

In both cases the label is still on the merged pull request, and the scan picks it up.
Nothing is dropped; it is only late.

## Why

The author is awake, on the branch, and already doing this work. Giving them a label to
clear costs nothing and ends the loop for the findings that never needed an issue. The
findings that survive a merge are the ones worth an issue: they are now true of the
default branch, and the issue says so and embeds them, so the reader does not have to
go back to the pull request.

The label is kept on an unmerged close on purpose. A closed pull request can be reopened
and merged, the review workflow does not review a reopened pull request, and the label is
the only memory that findings exist. The 14-day window bounds what a stale label on an
abandoned pull request can cost.

## The token is the switch

The workflow files with `GITHUB_TOKEN`, never a personal access token. GitHub starts no
workflow run from an event that token creates, and the steward wakes on every
`issues.opened` event with no sender check (`steward.yml`). A personal access token here
would wake the steward for exactly the findings the referee ruled it should not be woken
for. Swap the token and the whole point of the non-blocking verdict is gone.

## How to read its output

Each run prints one line per pull request:

| Line | Meaning |
|---|---|
| `PR #N merged still labelled - filed: ...` | An issue was filed and the label removed. |
| `PR #N merged with the label cleared - ...` | Nothing filed; the author handled it. |
| `A follow-up issue for #N is already open - not filing another.` | Dedupe on the exact title. Normal after a retry. |
| `PR #N closed unmerged - no open follow-up issue to close.` | Nothing to do. |
| `Closed #M - PR #N never merged.` | A stale follow-up was closed with a comment saying why. |
| `::error::Could not read the labels of PR #N ...` | GitHub could not be asked. The issue was filed anyway; the run is red so someone looks. |
| `::error::Could not file the follow-up for #N ...` | The label stays on; the next run retries. Red. |
| `::error::Could not list closed pull requests ...` | The scan's only input failed. Nothing was swept; red. |
| `::warning::Filed ... but could not remove the label` | The open issue stops a duplicate; clear the label by hand. |

Exit codes: `0` everything was recorded · `1` something was not (a filing, a close, a
listing) · `2` the run could not start (bad arguments, no repository, no `gh`, no `jq`).

A non-zero exit from the **daily scan or a hand run** routes through `nightly-alert.yml`:
one tracking issue for the gate `Review follow-up sweep`, updated rather than re-filed,
so a cause that persists does not open a new issue every day. A red `pull_request` run
does not alert: a fork's run holds a read-only token and fails by design, and the daily
scan repairs whatever an event run could not do.

## Never make this a required check

It does not run on a pull request's own pushes — only on `closed`, on the schedule, and by
hand. Requiring it blocks every pull request forever, waiting for a check that by design
never reports. It is a reporter, not a gate; see the never-require list in
`docs/runbooks/branch-protection.md`.

## The issue body

The body embeds the referee's comparison, taken from the pull request's comments. Three
rules decide what is embedded:

- Only a comment whose author is a **Bot** (`user.type`), never matched by login — the
  body becomes an issue that agents act on, so it may not be arbitrary text from anyone
  who can comment on the pull request.
- The review workflow's own pre-merge reminder quotes the comparison inside itself and
  is skipped, as is the placeholder posted when the comparison could not be produced.
- All three comment homes are read — conversation comments, inline review comments and
  formal review bodies — and the newest match wins.

If no comparison can be read, the issue is still filed and says so plainly. **Do not edit
the body** — comment instead, so the filed record survives.

## Running it by hand

```bash
GH_TOKEN=... tools/review-followup-sweep.sh --pr 943 --merged true --repo OWNER/NAME
GH_TOKEN=... tools/review-followup-sweep.sh --scan --limit 50 --days 14 --repo OWNER/NAME
```

`--repo` defaults to `GITHUB_REPOSITORY` and is required otherwise; the script never
assumes a repository. `--base` names the default branch in the issue text; without it the
script asks GitHub. From the Actions tab, `workflow_dispatch` runs the scan.
