---
name: An issue's own count is a band
topic: issue-count-is-a-band
type: trap
description: An issue's headline count can fall to zero while its defect is still live; measure the property, not the value.
symptoms: An issue's own number reads fixed but the defect is still visible; a count fell with nothing merged; a count fell because a record was destroyed, not repaired; you are about to close or downgrade an issue because its headline number moved; a new issue looks like a duplicate of an old one whose count says it is solved; you are about to report a red gate, a failing job or an open issue as a live problem without checking whether that failure is already an accepted decision.
verified: 2026-09-13
related: [measure-the-property-not-the-value, half-landed-fix]
---

## The trap

An issue filed with a count in it gets re-read for weeks. If that count measures a
**value** the defect happened to take, the value moves on its own — a re-run, a
re-derivation, one record leaving the pool — and the count falls with nothing fixed.

Upstream, two on record, both read as fixed while live:

- "N records with both fields empty." The count fell to four, and all four were
  correctly empty (a category where the fields do not apply). The real defect was 22
  records whose source states a value the system stores as empty.
- "Four records published under city X." The served set held zero rows in X. The defect
  sat on 11 rows from eight sources. One row moved from X to Y against a source page
  that named neither: the value moved, the defect did not.

A third way the number falls: **the record was destroyed, not repaired.** A pool of
malformed rows went from four to two overnight — one repaired, one deleted for good.
Read what happened to each row that left.

## What to do

When you file an issue with a count in it, write two things next to it:

1. **The property, in one sentence with no value in it.** If your sentence names a
   city, a number or a field combination, it is a value — go up one level. "Says X" is
   a value; "the served city is not the one on the source" is the property.
2. **What the count reads when the defect is GONE, and what it reads when it is still
   live but has moved.** If both answers can be the same number, the count is wrong.
   Replace it with a census over the property before you file.

When you re-measure, report the property census next to the headline count. When they
disagree, **the census wins** — correct the title, or supersede the issue.

## The mirror case: a red that is already decided

A number that reads *bad* is not evidence of a live problem either — the failure may
already be an accepted decision. Upstream, a daily brief said "while the nightly
security issue is red, nobody is reading advisories." False: that scan failed every
night by operator decision, recorded in the QA runbook's accepted-exceptions list, and
merges were unaffected. The brief read an open `[nightly]` issue, never the decision
beside it.

Before you report any red as a problem:

1. **Check the accepted list** — the "Exception list" in `docs/runbooks/agent-modes.md`
   and any accepted-red note in `docs/QUALITY-GATES.md`. Report an accepted red **as
   accepted**, naming its tracker.
2. **Read the run, not the issue.** An open issue says a thing failed once, at some
   point. It never says what that thing is doing now.

## Not the band checklist

A band tests the number that verifies a *fix*; this is the issue's own census, which no
check reads. `measure-the-property-not-the-value` is the general shape.
