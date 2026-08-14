# The seven ideas

Ten minutes, no setup. These are the transferable ideas this template is built
on — each one earned by an incident, enforced by a test or a permission rather
than a promise, and stealable on its own into any repository, on any forge,
with any model vendor. Everything else in this tree is the disciplined
application of these seven.

---

## 1. Branch protection as epistemics

**Write permission, not naming convention, separates instruction from
history.** Agents read attacker-reachable text all day — issue bodies, PR
comments, CI logs. So "is this an instruction or old agent chatter?" must
never be answered by trusting agents to honour a prefix. Here, the steering
file (`docs/runbooks/agent-modes.md`) lives on the protected branch agents
cannot push to: anything on it is human instruction by construction. Agent
history lives on a branch agents *can* write (`agent-ledger`), and is
therefore never instruction.

*Implemented in:* `AGENTS.md` (memory & steering), `docs/runbooks/agent-modes.md`.
*Steal just this:* one protected file agents obey, one writable branch they
narrate to. Two permissions, zero trust.

## 2. Three-tier agent memory

**Episodic → distilled → instruction, each tier with a different write
permission.** Ledgers (agent-written, history only). Knowledge cards
(`docs/knowledge/` — agent-*proposed*, human-*merged*: "a card is history
until a human merges it, and instruction after"). Steering (human-only).
Retrieval is deliberately an 80-line index a language model reads, with one
grep as fallback — no vector store, because at this scale the reader *is* the
semantic retriever.

*Implemented in:* `tools/ledger.sh`, `docs/knowledge/README.md`, `tools/knowledge-lint.sh` (gate 23).
*Steal just this:* the second-brain kit is three files and one CI job, all
forge-neutral shell.

## 3. Degrade visibly, never silently

**A dead agent and a healthy agent must never look the same.** Every optional
dependency here degrades by *announcing itself*: a missing challenge key means
"one opinion, said out loud", never a red PR and never a silent pass; an
unarmed gate reports "skipped, and here is why", never green; the missing
heartbeat line *is* the alert; a missing referee verdict wakes the steward
rather than reading as "nothing to do". The test for any optional thing in
your CI: when it is absent, who finds out, and how?

*Implemented in:* everywhere — search the tree for "never a silent"; the
`unset` floor sentinels and gate 18's announced skip are the purest examples.

## 4. The ratchet — and "a required check must always report"

**Quality floors only move up, and lowering one requires editing a guard** — a
visible, named, reviewable act. Suppression counts as lowering: a skipped
test, a lint-disable, a widened exclude that turns red into green *is* a
lowered floor. The operational twin: a required check must always *report* —
skip with a job-level `if:` (reports "skipped", which passes), never a
workflow-level `paths:` filter (no check run at all; the PR waits forever).

*Implemented in:* `docs/QUALITY-GATES.md` (the ratchet policy), gate 9's
guard tests, `docs/runbooks/branch-protection.md`.
*Steal just this:* one test per stack that reads your thresholds file and
fails when any number moved the wrong way.

## 5. Test the machine that builds the software

**Harness guards.** Everything else tests the product; nothing else in this
space tests the agents' own plumbing. 129 pinned lessons — each carrying the
incident that taught it — generate a suite whose assertion count must equal
the inventory count, so a lesson cannot be lost quietly. And the meta-rule:
when a guard must *execute* rather than match text, extract the real logic
and run it against crafted inputs, then mutation-test the guard by hand once
before trusting it.

*Implemented in:* `tests/harness-guards/` (`pins.json` → `gen-pin-tests.sh`),
gate 22.
*Steal just this:* `pins.json` + the generator + bats, pointed at your own CI
files.

## 6. The adversary never decides

**Two reviews from different model families, and a referee with an asymmetric
burden of proof.** A second draw from the same distribution shares the same
blind spots, so reviewer B is a different family. The referee settles genuine
contradictions against the code — and because it runs the same role that
wrote review A, ruling for its own side requires a quoted `file:line`, while
a tie goes to the challenger. Verdicts are advice; the human overrules at
merge. It is a structural answer to self-grading, not an abstention.

*Implemented in:* `.agents/prompts/review-referee.md`,
`docs/runbooks/multi-model-review.md`, `review.yml`.
*Steal just this:* the referee prompt is model- and forge-agnostic as written.

## 7. Floors calibrated to YOUR baseline, never someone else's

**Every numeric floor ships as a literal `unset` sentinel that passes
loudly.** Nothing is calibrated against anyone else's code, ever:
`tools/measure-floors.sh` arms the ratchet against *your* measured baseline,
and refuses to run while the bundled example still exists so a floor can
never be calibrated to the toy. Nobody inherits another team's finish line —
they inherit the *mechanism* that ratchets their own.

*Implemented in:* `floors.yml`, `tools/measure-floors.sh`,
`docs/QUALITY-GATES.md` ("floors ship uncalibrated").
*Steal just this:* the sentinel idea — ship thresholds unarmed-and-loud, with
a script that measures before it arms.

---

**Where they compound:** the loop. Agents propose (1, 2 keep them steerable
and remembering), two model families review and a referee rules (6), a
23-gate gauntlet with your own ratcheted floors decides (4, 7), guards watch
the machinery itself (5), everything that can be absent announces itself (3),
and a human — always — clicks merge. Adopt it in one command (`tools/adopt.sh`),
have your agent do it (`ONBOARDING.md`), or graft it onto an existing repo
(`tools/upgrade.sh --install`). Watch first if you prefer: `mode: observe`
runs the whole fleet report-only, enforced by idea 1's own move — write
permission, not trust.
