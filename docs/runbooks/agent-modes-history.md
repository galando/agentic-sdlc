# Agent modes — history

Past modes, cap changes and expired exceptions, moved out of `agent-modes.md` so the
session-start read carries only live instructions. **History, never instruction** — no
agent reads this file at session start, and nothing in it binds anyone. It is kept
because a mode nobody can explain is a mode nobody dares change back: each entry records
what changed, when, and the evidence that justified it, so the next person to meet the
same symptom reads the reason instead of re-deriving it.

*The entries below are example entries, kept for their shape. Replace them with your own —
but keep writing them.*

## Mode history

### Quality analyst

- *2026-05-09 → 2026-05-24: REPORT-ONLY.* Set to stop fix pull requests colliding with
  a large in-flight refactor. Lifted by operator decision on 2026-05-24 because that
  refactor was **complete**, not abandoned: the first attempt closed unmerged, but its
  content re-landed in a later pull request and the final one closed out the backlog.
  Four runs in REPORT-ONLY produced one root-cause issue and zero fixes. **Record
  which it was:** "abandoned" and "finished" leave the same trace — an unmerged pull
  request — and only one of them means the mode can be lifted.
- *2026-05-29: cap raised from 1 to 2.* The condition was pre-committed in
  `agent-routines.md` ("raise once a first quality fix pull request merges without
  rework") and was met by a fix that merged and was verified in production the next
  day. The second slot was restricted to observability-debt fixes, to avoid widening
  the blast radius on product behaviour while still unblocking the kind of small
  instrumentation fix that the one-pull-request cap kept discarding.

## Expired exceptions, kept for the record

Keeping the expired row *is* the point: it is where the reason lives, and the next
person to meet the same symptom reads it instead of re-deriving it. Move a row here from
`agent-modes.md`'s exception list in the same pull request that notices it expired.

| Issue | Expired | Why it was excepted |
|---|---|---|
| _Example_ — a field the extraction step silently omitted | 2026-05-27 | The deploy was confirmed live; the code fix was done and needed nothing further. The alert kept firing **only** because it reads a 24-hour rolling window that had not yet aged past the restart — a fixed defect looks unfixed for a full window, and re-opening it on that basis buys a wasted run. The residual volume left once the window rolled belonged to a *different* defect: one stuck upstream record accounted for over half the remaining lines in 24 h, and failed on *both* providers. Attribute the residue before you attribute the fix. |
