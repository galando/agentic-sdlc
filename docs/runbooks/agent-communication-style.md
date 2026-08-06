# Agent communication style — explain it in plain language

**Binding on every agent that writes anything a human will read**: the five
scheduled agents (`health`, `quality`, `audit`, `chief-of-staff`, `challenger`),
the steward, the automatic pull-request reviewer, any skill run, any ad-hoc
unattended session, and every agent added after this file was written. If you are
an agent in this repo, this applies to you. New agents inherit it automatically —
**you do not get to opt out by not being mentioned by name.**

This is `AGENTS.md` guardrail 6, stated in full. It is an operator decision, not a
style preference: explanations of what happened, what was fixed, and why must be
in simple, clear, easy-to-understand language. No fluff, no complicated
explanations.

## Where it applies

Everything you write for a person to read:

- Pull-request titles and bodies
- Code-review comments and review findings
- Issue bodies, issue comments, and escalations
- Ledger `summary` lines and narrative files
- `{{ALERT_CHANNEL}}` run-summaries and incident pings
- Commit messages
- Your final reply in a chat session

<!-- placeholder: {{ALERT_CHANNEL}} — where operational pings go (a chat channel,
     an email list, a pager). -->

It does **not** apply to machine-read output: JSON ledger fields, manifest records,
gate evidence tables, log excerpts, queries, code. Those stay exactly as precise as
they are today.

## The rule

Answer three questions, in this order, before anything else:

1. **What was wrong** (or what you were asked to do)
2. **What you changed**
3. **Why**

Then, if it applies: **how you know it works**, and **what you did not do**.

Write it so someone who did not read the code can follow it.

## How to write it

1. **Lead with the answer.** First sentence says what happened. No build-up, no
   restating the request, no "Great question".
2. **Short sentences. Everyday words.** One idea per sentence. If a sentence needs
   a comma-spliced sub-clause to survive, split it.
3. **Explain the effect, not just the mechanism.** "Nobody received their nightly
   export" beats "the dispatch predicate short-circuited". Give the mechanism
   after the effect, in one sentence, if it matters.
4. **Expand jargon the first time you use it.** Internal names (the ratchet, the
   freeze store, the harness guards, the full tier) get four words of explanation
   on first mention.
5. **Be concrete.** Names, numbers, `file:line`. "Three of the eight scheduled
   jobs failed" beats "several jobs had issues".
6. **Say what you did not do.** Anything skipped, unverified, or left broken gets
   its own sentence. This is not optional and it is never softened.
7. **Claim "fixed" only when you verified it.** Otherwise say what you ran and what
   you did not. "Tests pass locally, not verified in production" is a complete and
   acceptable answer.
8. **Cut the fluff.** No apologies, no self-praise, no filler openers or closers, no
   summarising what you are about to say before you say it.

## Length

| Where | Plain-language part |
|---|---|
| Ledger `summary` | 1 line |
| `{{ALERT_CHANNEL}}` summary / ping | 1 line |
| Review finding | 2–3 sentences, then the code detail |
| Issue "what is wrong" | 1 sentence, then the evidence |
| PR body "what & why" | ≤ 5 sentences |
| Chat reply | As short as the question allows |

**The detail is not deleted — it moves *below* the plain summary**, into the
evidence block, the narrative file, or the code comment. This rule never trades
away accuracy, and "I simplified it" is not a licence to drop the stack trace, the
metric, the file path or the caveat. Somebody skimming only the first lines must
never miss something that needed them; somebody who reads on must still find
everything.

## Words to drop

| Don't write | Write |
|---|---|
| leverage, utilise | use |
| surface, propagate | show, pass on |
| remediate | fix |
| ascertain | check, find out |
| non-trivial | hard, or say how hard |
| comprehensive, robust, seamless, holistic | say the actual property, or drop it |
| in order to | to |
| it should be noted that | (drop it) |
| I hope this helps / Let me know if / Great question | (drop it) |

## Example

**Too complicated:**

> The root cause was identified as an unintended short-circuit in the export
> pipeline's record predicate, whereby iteration would prematurely terminate upon
> encountering an uncategorised entity, thereby precluding downstream emission for
> the remainder of the affected batch. A comprehensive remediation was applied to
> the predicate evaluation logic and the corresponding test coverage was augmented
> accordingly.

**Plain:**

> The nightly export has been sending almost no rows for the last five days.
>
> The export code stopped as soon as it hit a record with no category, so every row
> after the first uncategorised one was silently dropped. I changed it to treat a
> missing category as "unclassified" instead of as a fatal error
> (`ExportJob:142`), and added a test that fails without the fix.
>
> Verified: the unit tests and the acceptance specs pass locally. Not verified in
> production — the operator needs to deploy it, and I have not checked whether the
> five days of missing rows need a backfill.

## Same rule, one line

Write like you are explaining it to a colleague who is competent but was not in the
room. Say what broke, what you changed, and why. Stop there.
