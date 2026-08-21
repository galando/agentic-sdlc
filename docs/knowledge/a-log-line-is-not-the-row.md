---
name: A log line is not the stored row
topic: a-log-line-is-not-the-row
type: trap
description: A signal emitted before a write, a validation gate, or a filter proves the attempt, not the outcome; verify at the boundary a consumer reads.
symptoms: A fix is being verified from a log line, a counter, or a "changed X to Y" message; the log says a value changed but the API/database/served page still shows the old one; a verification step reads the component that produced the change instead of the surface that serves it.
verified: 2026-08-20
related: [merge-is-not-deploy]
---

## The trap

Systems log what they **read** and what they **intend**, usually before the write — and
between the log line and the stored state sit validation gates, filters, and failure
paths that can discard the value. Upstream, a "field changed" log line was written three
lines before the save, the save's sanity gate rejected the new value (correctly), and
the log still claimed a change: the public API served the old value the next morning
while every verification signal said the fix had landed.

The general shape: **any signal emitted before a write, before a validation gate, or
before a filter is evidence of an attempt, not an outcome.** A counter that increments
on entry, a log line at the top of the function, an event published before the commit —
all of them can be true while the stored state never moved.

## The rule

**Verify at the boundary a consumer reads** — the served API response, the row a fresh
query returns, the file the mechanism was supposed to produce. Read that first. Use the
log line and the counter only to explain *why* it moved, or to tell "never attempted"
apart from "attempted and refused" — that distinction is exactly what the intermediate
signals are good for, and it is all they are good for.

Enumerate the third state. "Present and correct" and "present and wrong" are not the
only outcomes: a row can be **absent from the read path** — quarantined, filtered,
deferred by a cap. Absent is not fixed and not gone; score it as its own state, or the
verification mis-scores it as whichever of the other two is convenient.

## Where this binds

`AGENTS.md` "Fix verification" already demands the END STATE, not the mechanism; this
card is the write-side instance of that rule (as `merge-is-not-deploy` is the
deploy-side instance), plus the incident that keeps teaching it. The `fix_verified`
ledger field's `metric` must name a signal read at the consumer boundary — never the
log line of the component that made the change.
