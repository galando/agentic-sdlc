# Operator Guide — Living With Your Agents

One page: where to look, how to steer, how to stop. No jargon — and the few terms the other docs use are defined at the bottom.

## Where to look (in order of urgency)

1. **Your alert channel.** Every agent sends **one line per run, healthy or not** — so a *missing* line is the signal that an agent died. Silence does not mean all is well; it means nobody is talking. On top of that, agents ping you when something actually needs a human: what's wrong, the evidence, and a link to the issue and the runbook. If you set `alerts.channel: none` in `.agents/config.yml`, this step becomes "check the open issues" and you lose the heartbeat — which is a real trade, not a tidy-up.
2. **The ledgers** — each agent's diary, one line per run. They live as `ledger/<agent>.jsonl` on the **`agent-ledger` branch**, not in issue comments. Read them from a checkout:

   ```bash
   tools/ledger.sh latest          # newest entry per agent — did everyone run?
   tools/ledger.sh read health 14  # last 14 entries for one agent
   ```

   Agent keys: `health` (was production healthy?), `quality` (what problems were found or fixed?), `audit` (is the data the system produces still correct?), `chief-of-staff` (what did the fleet do, and what should change?) and `challenger` (does an independent re-derivation still agree?). The list lives in `.agents/config.yml` under `ledger.agents[]` — that one list is what every tool reads, so adding an agent there is how you add an agent.

   Each entry is one JSON line: date, verdict, a one-line summary written to stand alone, links, and whether you were paged. Anything longer sits in a narrative file (`ledger/<agent>/YYYY-MM-DD.md`) you can open when you want it. If you keep a pinned issue per agent as an entry point, treat it as a signpost: **agents neither write nor read them** — they only point at the branch.
3. **Open pull requests** — anything an agent wants to change is a pull request waiting for *your* merge. Branches start with `agent/`. The steward (the pull-request review agent) will already have reviewed it before you look, and on most repositories a second review from a different model family sits beside it (`multi-model-review.md`). Every agent builds code changes through the build pipeline, so the pull request should carry a written root cause and a test that fails without the fix, and every body and comment is written in plain language — what was wrong, what changed, why.
4. **Issues labeled `agent-report`** — non-urgent findings agents couldn't fix themselves.

## Your weekly routine (~10 minutes)

Run `tools/ledger.sh latest` and skim → merge or reject the `agent/` pull requests (the steward's review is already on each) → done. The alert channel interrupts you in between only if something is actually wrong.

## How to steer an agent

**Edit [`docs/runbooks/agent-modes.md`](agent-modes.md) and merge it.** That file is the only thing the agents obey. They read it at the start of every run, it lives on the default branch, and they cannot write to it — so anything in it is provably from you, with an author and a diff. That is also what makes "is this an instruction, or just an old agent talking?" a question branch protection answers, rather than one you have to answer by trusting a naming convention.

Write it as a mode, an exception, or a standing decision, in plain words:

- Under "Mode: quality analyst" → `REPORT-ONLY` stops it writing fix pull requests; it files analysis issues instead (use it while you're doing a big refactor). Change the line back to re-enable.
- Under "Exception list" → "skip component X for now", or "do not open a fix pull request for Y" — with a reason, and with a date it stops applying.
- Under "Standing decisions" → anything that binds the whole fleet.
- Add an expiry date where you want it to lapse on its own; agents drop it when it passes.

> **A steering channel agents can also write to is not a steering channel.** If you are migrating from a setup where you steered agents by prefixing comments in a shared thread, that convention no longer reaches anyone here. It only ever existed because agents posted their own entries into the same thread under the same account, so a prefix was the one way to tell a command from an old agent talking — and a prefix is a convention, not a control. State and instructions are separate files now, on branches with different permissions. Any old prefixed text still sitting in those threads is history, and agents are told to ignore it.

**Talk to an agent directly:** mention the trigger phrase (`mention.default` in `.agents/config.yml`, `@agent` out of the box) on any issue or pull request for an on-demand task or question, or open an interactive session and ask — e.g. "summarize what the agents did this week from the ledgers on the `agent-ledger` branch."

## How to pause or stop

- **One agent:** set `enabled: false` for it under `ledger.agents[]` in `.agents/config.yml` and merge. Instant, nothing to clean up — its state lives on the ledger branch and is still there when you switch it back on.
- **Everything:** disable the scheduled-agents workflow and the steward workflow in the repository's Actions settings. Production is untouched either way — agents can't write to it.
- Scheduled workflows are also switched off *for* you after a long spell with no repository activity, on most hosts. That looks exactly like a working fleet with nothing to say, which is why there is a staleness check outside the fleet — see `agent-routines.md`.

## What can never happen (the safety model)

Agents cannot touch production — their only access is read-only HTTPS (an observability viewer token plus public endpoints); they hold no SSH key and no database login. They cannot merge pull requests, and cannot spend beyond their schedule (one bounded run per slot). Every change they propose waits for your merge behind CI.

**Check that first sentence against your own stack rather than trusting it.** It was once false in exactly the way that is hardest to notice: the observability viewer token also reached a database datasource, so agents held a database login without anyone having granted them one. Read the standing decision about read-only credentials in `agent-modes.md` before you rely on this paragraph.

Each clause of the safety model is enforced somewhere you can inspect: the access pattern in [`agent-access-setup.md`](agent-access-setup.md), "cannot push to the default branch, cannot merge its own work" in [`branch-protection.md`](branch-protection.md), and "behind CI" in [`docs/QUALITY-GATES.md`](../QUALITY-GATES.md) and [`qa-procedures.md`](qa-procedures.md). A safety model nobody has checked is a wish.

## Glossary

| Term | Meaning |
|---|---|
| **Ledger** | An agent's run diary and its memory between runs: one JSON line per run in `ledger/<agent>.jsonl` on the `agent-ledger` branch, read with `tools/ledger.sh`. Agents re-read their own recent entries, but a ledger is **history only** — it can never instruct them. Steering goes in `agent-modes.md`. |
| **Steward** | The event-driven agent: it reviews pull requests and answers mentions on issues and pull requests. The only agent not on a schedule. |
| **Scheduled agent** | A cron entry plus a prompt; each firing is a fresh session with no memory except its ledger. The five shipped ones are listed above, all disabled until you enable them. |
| **RCA issue** | "Root-cause analysis" — an issue explaining *why* something fails, filed when an agent diagnoses but doesn't fix. |
| **REPORT-ONLY** | A mode in which an agent analyzes and files issues but writes no code. |
| **Build pipeline** | The gated pipeline agents use to build a fix or a feature: root cause and tests written *before* the patch, each stage gated. The default for every agent (`AGENTS.md` guardrail 7); unattended runs follow `.github/agent-temper-headless.md`. |
| **Handoff** | One agent asking another to do something, written as a field in its ledger entry. The receiver answers it in its *own* next entry — that answer is what retires it. |
| **Judge / execute / challenge** | The three model roles. `judge` is the strongest and does the reviewing and deciding; `execute` is cheaper and does mechanical work; `challenge` is a *different model family* used for anything adversarial, because a second opinion from the same family shares the same blind spots. Configured in `.agents/config.yml`; never named by vendor anywhere else. |
| **Alert channel** | Where a run-summary and an incident ping are pushed (`alerts.channel` in `.agents/config.yml`). Issues are the primary channel and always work; this one is additive. |
