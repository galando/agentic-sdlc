---
name: A log tail is not the run
topic: log-tail-is-not-the-run
type: trap
description: A log fetch returns the tail by default; finding nothing there proves nothing about the run.
symptoms: You grepped a job log and are about to write that something did not happen; a "no failure found" conclusion drawn from a log API, tail, or a line-capped fetch; you are about to warn against a pull request because its cause is absent from a log; a search over a truncated log is being used as proof of absence.
verified: 2026-08-24
related: [a-log-line-is-not-the-row, shallow-clone-hides-history]
---

## The trap

Log readers return the **end** of the log, not the log. A job-log API call has a
`tail_lines` default. `tail`, `journalctl -n`, and most log UIs do the same. A search over
that slice tells you what is in the slice. It tells you nothing about the rest of the run.

A negative result from a truncated log is **evidence about the tail, never about the
run.**

## The instance

Upstream, a triage agent grepped the last 300 lines of a 4000-line job log, found no
migration failure, and wrote on the issue that the migration had not failed — while
stating it had searched the whole log. The checksum mismatch was in the part it never
read. A pull request from another agent named the real cause. The triage agent re-read
the full log itself rather than trust the pull request body, then posted a public
correction withdrawing its warning against that pull request.

Self-caught within minutes, and only because a merge happened to contradict it.

## What to do

- Before you conclude **"X did not happen"**, check how much of the log you actually
  fetched. Compare the line count you got against the log's real size.
- Raise the limit, or fetch the failed step's own log, then search again.
- If you cannot read all of it, say what you searched: "no match in the last 300 lines"
  is true and useful; "it did not happen" is neither.
- A positive match in a tail is still a positive match. This trap is one-directional:
  only the **absence** is untrustworthy.

`shallow-clone-hides-history` is the same trap for git: an empty answer from a
truncated source reads exactly like "never existed".
