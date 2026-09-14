# Agentic SDLC

**Agents propose, a human merges, CI decides.**

A GitHub template that runs your software delivery lifecycle with autonomous
agents — and keeps every one of them behind a quality gauntlet, a two-model
review, and a merge button you click (unless you hand it, in writing, to the
opt-in merger).

```
  issue opened  ──▶  steward triages  ──▶  PR opened  ──▶  two reviews
                                                                │
        ┌───────────────────────────────────────────────────────┘
        ▼
  23-gate gauntlet  ──▶  YOU merge  ──▶  filing agent verifies the fix landed
```

**Proof it works:** [agentic-sdlc-demo](https://github.com/galando/agentic-sdlc-demo),
a real product adopted from this template with the adoption logged step by step.
**Why it is built this way:** [seven ideas](#why-it-is-built-this-way), each enforced by
a test or a permission, not a promise.

## One command in

From inside **any** git repository — a fresh one, or one with years of code in it:

```bash
curl -fsSL https://raw.githubusercontent.com/galando/agentic-sdlc/main/tools/bootstrap.sh | bash -s -- --product "My Product"
```

No questions. It installs the harness beside your files (never over them), answers the
interview with printed defaults, verifies with the shipped checkers, and ends with the
four things only you can do:

1. commit and push what landed;
2. add one repository secret, `AGENT_CLI_TOKEN` (it prints how to mint it);
3. tick one GitHub setting so Actions may open pull requests;
4. open issue #1 and mention the agent.

Nothing is pushed and nothing leaves your machine. `--dry-run` shows the plan first;
re-running it is safe. `tools/bootstrap.sh --help` lists `--provider`, `--source`
and `--ref`.

Other ways in, same destination:

| You are… | Do this |
|---|---|
| **Starting from the template** | Click **Use this template**, clone, run `tools/bootstrap.sh --product "My Product"`. Then `tools/adopt.sh` when you want the guided walk through the GitHub-side steps — it never acts without your yes. |
| **Sending your agent** | Hand Claude Code / Codex this repo and say *"read `ONBOARDING.md` and adopt this."* `profiles/` has ready answer files — a platform team publishes one internal profile and every team adopts with `--provider <name>`. |
| **Just looking** | Open in a devcontainer/Codespace: `tools/demo-local.sh` runs the ~900-test suite, the adoption map, and a dry-run agent command — three minutes, offline, zero credentials. |

Not ready to hand over write access? Set `mode: observe` in
`.agents/config.yml`: the whole fleet runs report-only for a trial week —
reviews and reports still post, but pushing is *mechanically* impossible,
because observe runs simply never receive a write token.

## What you get

- **An event-driven steward** that triages every new issue and answers
  mentions — it writes fixes as pull requests; it never merges them.
- **Two reviews from different model families** on every PR (a second draw
  from the same distribution shares the same blind spots), plus a **referee**
  that settles their genuine disagreements against the code. Verdicts are
  advice; you overrule at merge. Non-blocking findings are labelled, and filed
  as an issue only if they survive to the merge.
- **A 23-gate gauntlet** — tests, coverage, mutation, architecture,
  migrations, e2e/a11y, secrets, bundle size, and the harness's own guards —
  with **ratcheted floors calibrated to *your* codebase**, never someone
  else's. Floors ship as loud `unset` sentinels until `tools/measure-floors.sh`
  measures *your* baseline; from then on they only move up.
- **Twelve scheduled agents** (health, quality, audit, chief-of-staff,
  challenger, docs freshness, backlog groomer, test gap, dependency steward,
  code hygiene, release drafter, and an opt-in merger that merges only under a
  written bar you control) — all shipped **off**, enabled one at a time when
  you're ready.
- **Three watches that look where nothing else looks**: the default branch
  after merges, the agent fleet from *outside* it, and CI's own runners and
  minutes — each scheduled, each alerting through one tracking issue that names
  what it found and stays quiet when the findings have not changed.
- **A second brain** (`docs/knowledge/`): agents propose distilled lessons as
  cards, a human merges them, and every future session reads the 80-line
  index first.
- **~900 tests that test the machine itself**: 176 incident-derived lessons
  pinned so they cannot be lost quietly, plus executable guards on the
  agents' own plumbing.
- **Provider-neutral by construction**: models are addressed by role (judge /
  execute / challenge), vendors appear in exactly one adapter directory, and
  a guard fails the build if a vendor name leaks anywhere else. Works with a
  flat agent-CLI subscription; behind corporate proxies; on GitHub Enterprise.
- **Everything degrades visibly, never silently.** A missing optional
  credential announces itself and the run continues; absence of a heartbeat
  *is* the alert; a dead agent and a healthy agent never look the same.

## What you need

- A GitHub repository and **one agent-CLI subscription** (Claude Code today;
  codex/gemini adapters ship as documented stubs to finish). Normal cost: your
  existing flat monthly plan. One *optional* API key for a different model
  family unlocks the adversarial second review —
  `docs/runbooks/credentials-and-cost.md` has the honest numbers.
- **Any language.** The agent process is stack-agnostic from day one; only the
  measured gates ship as reference implementations (Java + React) you swap for
  your own tools — `docs/runbooks/porting-to-your-stack.md` has the exact
  table.

## Turning on the routines

The twelve scheduled agents ship disabled — nobody should meet this system as twelve
crons and an alert firehose. Dry-run each one first
(`tools/run-agent.sh <agent> --dry-run` prints the exact command and invokes
nothing), then flip its `enabled: true` in `.agents/config.yml`, one at a
time. Note: GitHub auto-disables schedules after ~60 days of repo inactivity —
if ledgers go stale, re-enable from the Actions tab; the fleet heartbeat files an
issue when an enabled agent misses its slot. Details:
`docs/runbooks/agent-routines.md`.

## Steering, and your ten minutes a week

`docs/runbooks/agent-modes.md` is the **only** channel agents obey — it lives
on the protected branch, so steering is always a reviewed pull request. The
one fleet-wide switch (`mode: active | observe`) lives in `.agents/config.yml`.
Once running, budget ~10 minutes a week: read review summaries, click merge,
glance at the daily brief. The full operator walkthrough is
`docs/runbooks/agent-operator-guide.md`; lost at any point, `tools/status.sh`
prints the map with your position on it.

## Why it is built this way

Seven ideas, each earned by an incident and each enforced by a test or a permission.
Any one of them can be taken alone, without adopting the rest.

1. **Branch protection as epistemics.** Instruction and history are separated by
   *write permission*, not by trust. Agents obey only `docs/runbooks/agent-modes.md`
   on the protected branch (every steer is a reviewed pull request); their own
   ledgers live on an orphan branch they can write freely, and nothing reads a ledger
   as an instruction. Enforced by the ledger tooling and the harness guards.
2. **Three-tier agent memory.** History (ledgers, append-only, per run), knowledge
   (`docs/knowledge/` cards, proposed by agents, merged by a human, read at every
   session start through an 80-line index), and steering (`agent-modes.md`, human
   written). Each tier has its own write permission; that separation is the template's
   signature idea.
3. **Degrade visibly, never silently.** A missing optional credential announces itself
   and the run continues; a dead agent and a healthy one must never look the same; the
   fleet is watched from outside itself, so its silence is an alert rather than a calm.
   A run that produced nothing fails on purpose.
4. **The ratchet.** Floors only move up, and suppression counts as lowering: a
   widened exclude, a deleted threshold, a hand-edited freeze store. Ratchet guards on
   every stack turn that from a convention into a failing check. A required status check
   must always report; one that can never report blocks every pull request forever.
5. **Test the machine that builds the software.** ~900 tests exercise the agents'
   own plumbing, and 176 incident-derived lessons are pinned as text assertions
   generated from one inventory, so a lost lesson cannot pass quietly.
6. **The adversary never decides.** Two reviews from different model families (a
   second draw from the same distribution shares its blind spots), a referee that
   rules against the code with the burden on the challenger, and a human who overrules
   at merge. The opt-in merger is the one exception, and it merges only what a bar you
   wrote allows.
7. **Your baseline, never someone else's.** Every floor ships as an `unset` sentinel
   that passes loudly until `tools/measure-floors.sh` measures your own code. A number
   copied from another project is a wish, not a floor.

## When to use something else

Solo prototyping doesn't need a gauntlet. If you want unattended merges with no
written bar, this is deliberately the wrong tool — the human merge *is* the
default, and the opt-in merger only ever merges what a human-written bar in
`agent-modes.md` allows. If you only want spec discipline or dependency bumps, a
spec tool or Renovate alone is lighter. This template is for teams who want
autonomous agents doing real work *and* a mechanical reason to trust every change
that lands.

## Where to read next

`docs/README.md` is the map of every document here, sorted by who reads it: adopter,
operator, agent, template maintainer. The short version:

| You want to… | Read |
|---|---|
| Adopt with an agent doing the work | `ONBOARDING.md` |
| See every placeholder and which file it lives in | `ADOPTING.md` (generated) |
| Live with the agents day to day | `docs/runbooks/agent-operator-guide.md` |
| Understand a gate, or a floor that will not move | `docs/QUALITY-GATES.md` |
| Match a symptom to its cause | `docs/runbooks/troubleshooting.md` |
| Upgrade a fork to a newer template | `tools/upgrade.sh plan/apply <new-template>`, from your adoption manifest |
| Contribute to the template itself | `CONTRIBUTING.md`, and `AGENTS.md` for the binding rules |

License: [MIT](LICENSE).
