---
name: Measure the property, not the value
topic: measure-the-property-not-the-value
type: rule
description: A metric, band or skip guard reads a value something else resets; name the property first, then ask what moves your reading without moving it.
symptoms: A metric reads the same figure over 24h and over 7d; a counter or gauge lives in process memory and the process restarts many times a day; a query uses last_over_time, increase() or a tail and the process behind it restarts; a guard skips work because a timestamp has not moved; an issue's meaning changed and no event landed on the issue; you read a level at one moment and call it a daily minimum, maximum or average; a projection names a start date and you have not read the field that names the end; a band retires or confirms on a part-day reading; two sources print the same log line and your band keys on that line.
verified: 2026-09-13
related: [issue-count-is-a-band, a-log-line-is-not-the-row, guard-inside-the-guarded]
---

## The rule

A reading is not the thing you care about. Write the **property** in one sentence with
no number, no timestamp and no field name in it. Then ask two questions:

1. **What moves my reading without moving the property?** A restart, a deploy, a row
   leaving the pool, a sweep comment, a part-day sample.
2. **What moves the property without moving my reading?** A merge that lands elsewhere,
   a fix that repairs nothing already stored, a second source writing the same line.

If either answer is anything at all, the reading is a value and the check built on it is
blind in that direction. Fix the reading, not the threshold.

## Four in one week, all four shipped before anyone noticed

- **A restart erases it.** A per-source quality score was read with `last_over_time`.
  The value lived in the service's memory and production restarted on every deploy — 15
  times in 24 hours. So the query meant "since the last deploy": 118 of 159 samples
  visible, and 24h and 7d returned identical figures for every source. The property is
  "the average over a day"; the fix publishes it as a level read from the table. A
  catch-up counter had the same shape and the same cause.
- **A sample time is not a day.** A disk band names the daily minimum free space. A
  reading taken at 06:00Z is a part-day figure, not that minimum. One band nearly
  retired on 16.8 GiB where the full day read 14.1.
- **A timestamp is not a meaning.** A skip guard passes over an issue whose timestamp
  has not moved. A merge to the default branch made a correctly refuted report true
  again, with no event on the issue at all.
- **A start date is not a length.** The fleet's model budget prints a utilisation figure
  and a reset time in the same payload. Two agents projected the wall from utilisation
  and then guessed the length of the outage — wrong twice, on two days running, by 23 to
  29 hours. An earlier wall leaves *more* of the week to sit through.

## Where this is already written down

`issue-count-is-a-band` is this rule for the count inside an issue.
`a-log-line-is-not-the-row` is it for a signal emitted before a write. This card is the
general shape, for metrics, guards and projections. `.agents/health-signals.yml` is
where a metric becomes a check: write the property in the signal's comment before the
query, and say what resets the series it reads.
