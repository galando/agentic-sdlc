# The second brain — card contract

This directory is the layer of memory the fleet has been missing: knowledge the agents
themselves **distill**, sitting between episodic memory (`ledger/*.jsonl` — history,
never instruction) and operator-written instruction (`docs/runbooks/agent-modes.md`). A
card is history **until a human merges it**, and instruction **after** — the same
branch-protection line that already separates a ledger entry from a standing decision.
The design arrived as Part A of PR #18's plan document; what survives in-tree is the
implementation spec (success criteria, scenarios, gate ledger) at
`.temper/specs/second-brain-and-sdlc-extension/` — and this README, which is the
operative contract.

## Layout

```
docs/knowledge/
  README.md      # this file — the card contract
  INDEX.md       # one entry per rule/trap card; hard cap 80 lines
  <topic-slug>.md
```

`<topic-slug>` is the filename without `.md`, and it is also the card's `topic`
frontmatter field — the exact convention `ledger/<agent>.jsonl`'s `topic` field already
uses, so the same slug means the same thing whether it names a deep-dive investigation
or a knowledge card.

## Card format

Every card is one markdown file with this frontmatter, then a body of **at most 60
lines** of distilled instruction:

```yaml
---
name: <human-readable title>
topic: <slug>              # == the filename, no .md
type: rule | trap | project
description: <one line — what this card is for>
symptoms: <the retrieval surface — what the NEXT agent would observe, not a label>
verified: YYYY-MM-DD       # date this card was last confirmed still true
related: [<slug>, ...]     # optional — the cheap graph, not required
---
```

- **`rule`** — a standing instruction distilled from a recurring pattern ("always do X
  before Y").
- **`trap`** — a specific mistake to avoid, usually anchored to one incident ("X looks
  right and is wrong because Y").
- **`project`** — a reference snapshot about this specific system (a naming convention,
  a subsystem's shape). **Grep-only**: excluded from `INDEX.md` and the index-first read
  path in `AGENTS.md`, because it answers "what is true about this system" rather than
  "what should I do" — the read path in `AGENTS.md` is for the second kind of question.

**Evidence stays in ledgers and pull requests, not in the card.** A card is the
distilled conclusion, not the log line that motivated it — that discipline is what keeps
the body under 60 lines and the index under 80.

## The index

`INDEX.md` carries exactly one entry per `rule`/`trap` card (never `project` cards),
shaped so the **symptoms** line is what a reading agent actually matches against:

```
<slug> — <one-line description>.
  Symptoms: <what the next agent would observe when this card applies>.
```

`tools/knowledge-lint.sh` enforces that the index and the `rule`/`trap` cards agree
1:1, that every card's frontmatter is complete, that every body is ≤ 60 lines, that
`verified` parses as a date, and that the index itself is ≤ 80 lines. It runs as a FAST
gate on every pull request (`docs/QUALITY-GATES.md`).

## Read path

Session start, after the ledger read (`AGENTS.md`): read `INDEX.md`. If a line's
symptoms match the task, read those cards only — rarely more than 2–3. If nothing in
the index matches but the task names a specific error string, file, or metric, run one
`grep -ril '<term>' docs/knowledge/` as a fallback. Never read the whole directory. A
miss costs nothing — work as you would today.

There is deliberately **no embedding store or graph database** here: the reader is a
language model, so reading an 80-line index *is* semantic retrieval, grep is the
fallback retriever, and `related:` is the graph. Revisit this with a *derived* index
(git staying the source of truth) only past ~150 `rule`/`trap` cards, or a genuine need
to search narratives rather than distilled cards.

## Write path

**The chief of staff is the distiller**, in its existing retrospective (every second
run). Two added questions, answered from the last ~7 days of every agent's structured
entries:

1. Did any `fix_verified`, recurring `topic`, or chronic `pending` teach something
   durable? → one docs-only pull request, **at most 2 cards + index lines**.
2. Did any run **re-derive** something a card already covers? → the defect is the index
   line's `symptoms` wording; fix it in the same pull request. This is what makes
   retrieval self-healing — a miss becomes a wording fix, not just a shrug.

Other agents never write cards mid-run; they hand evidence to the chief of staff via a
`handoff` (`docs/runbooks/agent-ledgers.md`). **The operator merges every card pull
request** — rejecting one is cheap and normal, the same as rejecting any other pull
request.

## Maintenance

Every `rule`/`trap` card carries `verified:`. The chief of staff's daily brief lists any
card stale past 90 days ("confirm, fold, or delete"). The 80-line index cap is the
forcing function: when it is full, fold or retire a card before adding another. Steady
state is a few dozen cards, so context cost cannot drift silently upward.
