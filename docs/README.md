# The documentation map

Every document in this repository, sorted by who reads it. If a page is not on this map,
it is either generated (`ADOPTING.md`) or a build record (`.temper/specs/`).

## Adopting (you are bringing the harness into a repository)

| Read | For |
|---|---|
| `README.md` | The one-command adoption, what you get, when to use something else, the seven ideas |
| `ONBOARDING.md` | The complete adoption procedure, written so an agent can run it for you |
| `ADOPTING.md` | Generated map of every placeholder token and the file it lives in; `tools/gen-adopting.sh` regenerates it |
| `profiles/README.md` | Answer profiles: one per provider, or one your platform team publishes |
| `docs/runbooks/credentials-and-cost.md` | Every secret, what breaks without it, what it costs |
| `docs/runbooks/porting-to-your-stack.md` | Swapping the reference gates (Java, React) for your own tools |
| `docs/runbooks/branch-protection.md` | Which status checks are safe to require, by exact string |

## Operating (the agents are running and you steer them)

| Read | For |
|---|---|
| `docs/runbooks/agent-operator-guide.md` | Living with the agents: setup order, the merger switch, the glossary |
| `docs/runbooks/agent-modes.md` | The only channel agents obey; every steer is a pull request against it |
| `docs/runbooks/agent-modes-history.md` | Past modes and expired exceptions, kept out of the session-start read |
| `docs/runbooks/agent-routines.md` | The twelve scheduled agents: schedules, prompts, caps, the rules that bind each |
| `docs/QUALITY-GATES.md` | The gate inventory, the watchdogs, the ratchet policy |
| `docs/runbooks/qa-procedures.md` | Running the gauntlet and reading a red gate |
| `docs/runbooks/troubleshooting.md` | Symptom to cause |
| `docs/runbooks/multi-model-review.md` | The two-review and referee design, verdicts, lost reviews |
| `docs/runbooks/review-followup-sweep.md` | Non-blocking findings filed at merge, not at review |
| `docs/runbooks/parked-branch-sweep.md` | The three-hourly sweep that opens what a dead run could not |
| `docs/runbooks/model-budget-exhaustion.md` | What a spent agent budget looks like, and who can fix it |
| `docs/runbooks/agent-escalation.md` | The S1/S2 ladder and when an agent pings a human |
| `docs/runbooks/agent-access-setup.md` | One-time read-only production access wiring |
| `docs/runbooks/agent-ledgers.md` | The ledger format and the orphan branch it lives on |

## For agents (read at run time)

| Read | For |
|---|---|
| `AGENTS.md` | The binding guardrails and the session-start checklist |
| `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md` | Vendor entry points; the last two only point at `AGENTS.md` |
| `.agents/prompts/*.md` | The prompt each agent and review role runs with |
| `.github/agent-temper-headless.md` | How fixes and features are built unattended |
| `.agents/observe.md` | Appended to every prompt while `mode: observe` |
| `docs/runbooks/agent-communication-style.md` | Writing for humans in plain language |
| `docs/knowledge/INDEX.md` and the cards | The second brain: one distilled lesson per card, contract in `docs/knowledge/README.md` |
| `tools/spec-pipeline/CONTRACT.md` | What a spec directory must contain for gate 21 |

## Maintaining the template itself

| Read | For |
|---|---|
| `CONTRIBUTING.md` | How lessons from forks come back upstream |
| `CHANGELOG.md` | Release history; its newest heading is also the template version stamp |
| `docs/DEMO.md` | The scripted capability tour of the public demo; removed from adopted trees by `tools/init.sh` |
| `tests/harness-guards/lesson-inventory.md` | Every pinned lesson, with the incident that taught it |
| `tests/harness-guards/semantic-discharges.md` | Where each manually checked pin is discharged |
| `.temper/specs/agent-sdlc-template/` | The build record of the template, and the worked example of a spec directory |
