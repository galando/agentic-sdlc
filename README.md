# Agentic SDLC

**Agents propose, a human merges, CI decides.**

A GitHub template that runs your software delivery lifecycle with autonomous
agents — and keeps every one of them behind a quality gauntlet, a two-model
review, and a merge button only *you* click.

```
  issue opened  ──▶  steward triages  ──▶  PR opened  ──▶  two reviews
                                                                │
        ┌───────────────────────────────────────────────────────┘
        ▼
  23-gate gauntlet  ──▶  YOU merge  ──▶  filing agent verifies the fix landed
```

**Why this one, in ten minutes:** [`THE-SEVEN-IDEAS.md`](THE-SEVEN-IDEAS.md) —
the doctrine everything here is built on, each idea enforced by a test or a
permission, not a promise. **Proof it works:**
[agentic-sdlc-demo](https://github.com/galando/agentic-sdlc-demo), a real
product adopted from this template with the adoption logged step by step.

## Four doors in

| You are… | Do this |
|---|---|
| **Starting a new repo** | Click **Use this template**, then run `tools/adopt.sh` — one resumable command that walks the whole adoption and never acts without your yes. Target: first merged agent loop in ~30 minutes. |
| **Bringing an existing repo** | From a template clone: `tools/upgrade.sh --install /path/to/your-repo`. Copies the harness in, never overwrites your files, and stamps a manifest so future template releases are a computable three-way merge. |
| **Sending your agent** | Hand Claude Code / Codex this repo and say *"read `ONBOARDING.md` and adopt this."* `profiles/` has ready answer files — a platform team can publish one internal profile so every team adopts with a single command. |
| **Just looking** | Open in a devcontainer/Codespace: `tools/demo-local.sh` runs the ~650-test suite, the adoption map, and a dry-run agent command — three minutes, offline, zero credentials. |

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
  advice; you overrule at merge.
- **A 23-gate gauntlet** — tests, coverage, mutation, architecture,
  migrations, e2e/a11y, secrets, bundle size, and the harness's own guards —
  with **ratcheted floors calibrated to *your* codebase**, never someone
  else's. Floors ship as loud `unset` sentinels until `tools/measure-floors.sh`
  measures *your* baseline; from then on they only move up.
- **Ten scheduled agents** (health, quality, audit, chief-of-staff,
  challenger, docs freshness, backlog groomer, test gap, dependency steward,
  release drafter) — all shipped **off**, enabled one at a time when you're
  ready.
- **A second brain** (`docs/knowledge/`): agents propose distilled lessons as
  cards, a human merges them, and every future session reads the 80-line
  index first. History (ledgers), knowledge (cards), and steering
  (`agent-modes.md`) are three memory tiers separated by *write permission* —
  the template's signature idea.
- **~650 tests that test the machine itself**: 129 incident-derived lessons
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

The ten scheduled agents ship disabled — nobody should meet this system as ten
crons and an alert firehose. Dry-run each one first
(`tools/run-agent.sh <agent> --dry-run` prints the exact command and invokes
nothing), then flip its `enabled: true` in `.agents/config.yml`, one at a
time. Note: GitHub auto-disables schedules after ~60 days of repo inactivity —
if ledgers go stale, re-enable from the Actions tab. Details:
`docs/runbooks/agent-routines.md`.

## Steering, and your ten minutes a week

`docs/runbooks/agent-modes.md` is the **only** channel agents obey — it lives
on the protected branch, so steering is always a reviewed pull request. The
one fleet-wide switch (`mode: active | observe`) lives in `.agents/config.yml`.
Once running, budget ~10 minutes a week: read review summaries, click merge,
glance at the daily brief. The full operator walkthrough is
`docs/runbooks/agent-operator-guide.md`; lost at any point, `tools/status.sh`
prints the map with your position on it.

## When to use something else

Solo prototyping doesn't need a gauntlet. If you want unattended merges, this
is deliberately the wrong tool — the human merge *is* the design. If you only
want spec discipline or dependency bumps, a spec tool or Renovate alone is
lighter. This template is for teams who want autonomous agents doing real
work *and* a mechanical reason to trust every change that lands.

## Help, upgrading, license

Something behaving oddly? `docs/runbooks/troubleshooting.md` maps symptoms to
causes. Upgrading a fork: `tools/upgrade.sh plan/apply <new-template>`
computes it from your adoption manifest. Full capability tour: `DEMO.md`.
License: [MIT](LICENSE). Contributing: `CONTRIBUTING.md` — lessons learned in
forks accumulate upstream.
