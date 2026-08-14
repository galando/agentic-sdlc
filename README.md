# Agentic SDLC

**Agents propose, a human merges, CI decides.**

*A GitHub template for running your software delivery lifecycle with autonomous
agents — guarded, gated, provider-neutral, and always merged by a human. Guided
tour: **[the project site](https://galando.github.io/agentic-sdlc/)**. Proof it
works: **[agentic-sdlc-demo](https://github.com/galando/agentic-sdlc-demo)** — a
real product adopted from this template, its adoption logged step by step in
its `ADOPTION-LOG.md`.*

```
  issue opened  ──▶  steward triages  ──▶  PR opened  ──▶  two reviews
                                                                │
        ┌───────────────────────────────────────────────────────┘
        ▼
  23-gate gauntlet  ──▶  YOU merge  ──▶  filing agent verifies the fix landed
```

> **Just created a repo from this template? Start here — one command, re-run it
> until done:**
> ```bash
> tools/adopt.sh
> ```
> It walks the entire adoption with you and never acts without your yes.
> Details: section 3. Lost later? `tools/status.sh`.
>
> **Prefer your agent to do the adoption?** Hand it this repo and say *"read
> `ONBOARDING.md` and adopt this"* (Claude Code users: the
> `/adopt-agentic-sdlc` skill points there too). `profiles/` ships ready answer
> files — and a platform team can publish one internal profile so every team in
> the org adopts with a single command.
>
> **Just looking?** Open this repo in a devcontainer or Codespace: it runs
> `tools/demo-local.sh` on create — the ~630-test harness suite, the adoption
> map, and a dry-run agent argv, in about three minutes, offline, with zero
> credentials.

Every step an agent takes is reviewable in a diff, gated by 23 automated checks, and
merged by a human. This repository is a **GitHub template**: the process scaffolding —
guardrails, ledger, gauntlet, agent prompts — with no product code of yours in it yet.
Use it, then delete the bundled example and wire in your own.

---

## 1. What this is, and the loop it runs

One line: **agents propose, a human merges, CI decides.** The diagram above is the whole
system. Nothing an agent does reaches your default branch without passing the gauntlet
(`docs/QUALITY-GATES.md`) and a human's explicit merge click.

## 2. Who this is for

- You have a GitHub repository (or are about to create one from this template).
- You have one agent-CLI subscription — Claude Code, Codex, or Gemini CLI. (A second,
  *optional*, API key for a different model family unlocks the adversarial second
  review — see `docs/runbooks/credentials-and-cost.md` and
  `docs/runbooks/multi-model-review.md`.)
- **Prerequisites, concretely:** the GitHub repository, the agent CLI installed
  wherever your workflows run it from, and — for the two working adapters
  (`claude-code`, `compatible-endpoint`) — nothing else to install. `codex` and
  `gemini-cli` ship as unverified stubs (see `tools/providers/`); finishing one is a
  short, documented task, not a rewrite.
- **Rough cost:** the normal case is your existing subscription's flat monthly price —
  see `docs/runbooks/credentials-and-cost.md` before you budget anything else.
- **Any language, not just the two bundled stacks.** The agent process (steward,
  reviews, gates, ledger, alerting) is language-agnostic from day one — only the
  *measured* gates (coverage, mutation, architecture) ship as reference
  implementations you swap for your own tools. Full breakdown, including the exact
  swap table: `docs/runbooks/porting-to-your-stack.md`.

## 3. Quickstart (target: under 30 minutes)

1. Click **Use this template** on GitHub, or `git clone` and re-point the remote.
2. Run the **guided adoption** — one command, resumable, safe to re-run at any
   point; it detects what is already done and offers the next step:
   ```bash
   tools/adopt.sh
   ```
   It runs the interview (product name, provider, model ids per role — offline,
   seconds), retires the bundled example, writes your product's README, creates
   the ledger branch, offers to commit and push, and then walks the
   GitHub-side steps with you: the `AGENT_CLI_TOKEN` secret, floor calibration
   as your first pull request, branch protection (it can apply the exact rule
   via `gh` with your yes), and the first agent-run issue. **Nothing happens
   without an explicit yes**; every declined offer prints the manual command.
   Pause whenever you like and run it again — it picks up where you are. It
   also pauses **itself** at one point: once the bundled example is retired and
   `backend/` / `frontend/` are still empty, it stops and hands you back the
   keyboard, because every step after that one needs your code to exist to mean
   anything. Add it, run the command again, and it carries on. The read-only
   version of the same map is `tools/status.sh`.

   Prefer the steps individually? The interview alone is `tools/init.sh`; it
   asks your answers, rewrites every `{{PLACEHOLDER}}` they resolve, offers the
   example retirement, your product README (`tools/write-product-readme.sh`)
   and the ledger branch, and prints exactly what is left.
3. Add the credentials it lists — at minimum `AGENT_CLI_TOKEN`, which is your agent
   CLI's **subscription token, not an API key** (run
   `tools/run-agent.sh --check-credentials <agent>` and it prints the exact command to
   mint one for the provider you just chose). `CHALLENGE_API_KEY` is a real API key and
   is optional — it buys the adversarial second review. Full table:
   `docs/runbooks/credentials-and-cost.md`.
4. Open **issue #1** against the bundled example (`examples/`) and mention your agent —
   the trigger phrase is the `AGENT_MENTION` repository variable, default `@agent`
   (see the `mention:` block in `.agents/config.yml`). Watch the steward triage it,
   open a PR, and watch two reviews and the gauntlet fire.
5. Make your **first human merge.**

That is the whole loop, once, before any of your own code exists. If you are past 30
minutes, section 9 (troubleshooting) is written for exactly this moment.

Want to see every capability of the system, not just the one loop above? `DEMO.md`
is a fixed, 13-stop scripted tour — steward triage through the second brain and the
five SDLC-extension agents — reproducible from a clean instantiation.

## 4. The operating loop you now live in

```
issue → steward triages → PR opened → two reviews (judge + challenge) → 23 gates → YOU merge → the filing agent verifies the fix landed
```

| Step | Automated | Yours |
|---|---|---|
| Triage a new issue | ✅ the steward (`.github/workflows/steward.yml`) | — |
| Write the fix / feature | ✅ the mentioned agent | Review the diff before it goes further, if you want to |
| First review (judge) | ✅ always runs | — |
| Second review (challenge, different model family) | ✅ when `CHALLENGE_API_KEY` is set; degrades to one opinion otherwise | — |
| The 23-gate gauntlet | ✅ every check in `docs/QUALITY-GATES.md` | — |
| **The merge itself** | ❌ never automated | **✅ always you** |
| Verifying a fix actually landed | ✅ the agent that filed the original issue, on your next comment/mention | Spot-check the ones that matter to you |

**Budget about 10 minutes a week** once this is running: reading review summaries, merging,
and glancing at `agent-modes.md` if something needs steering. That is the entire
operator burden this system is designed around — see
`docs/runbooks/agent-operator-guide.md` for the fuller version.

## 5. Steering

**`docs/runbooks/agent-modes.md`** is the *only* channel agents obey for behavior
changes — mode (`FULL` / `REPORT-ONLY` / `ACTIVE`), per-run PR caps, temporary
exceptions. Ledgers are history, not configuration: every scheduled agent appends one
line per run to an orphan branch (`docs/runbooks/agent-ledgers.md`) for you to read,
never to steer by. Pause one agent with `enabled: false` in `.agents/config.yml`;
pause everything by disabling `agents-scheduled.yml`'s schedule. Full walkthrough:
**`docs/runbooks/agent-operator-guide.md`**.

## 6. Turning on the routines, one at a time

Ten scheduled agents ship **disabled** (five daily — health, quality, audit, chief of
staff, challenger — and five weekly/monthly SDLC-extension agents: docs freshness,
backlog groomer, test gap, dependency steward, release drafter — full table in
`docs/runbooks/agent-routines.md`) — nobody should meet this system as ten crons and
an alert firehose on day one. Dry-run each one before you flip it on, one at a time:

```bash
tools/run-agent.sh <agent> --dry-run   # prints the exact command; invokes nothing
```

Then set `enabled: true` for that one agent in `.agents/config.yml`'s `ledger.agents`
list. **GitHub auto-disables scheduled workflows after ~60 days of repository
inactivity** — if routines stop firing and ledgers go stale, that's almost always why;
re-enable from the Actions tab. Full liveness story:
`docs/runbooks/agent-routines.md`.

## 7. Customization map

Every `{{PLACEHOLDER}}` in this tree, the file it lives in, and what belongs there is
generated mechanically into **`ADOPTING.md`** — read that file rather than grepping the
tree yourself; a placeholder without a row there is exactly the failure mode
`tools/gen-adopting.sh` exists to prevent. Most of them, `tools/init.sh` already
resolved for you in the quickstart above.

## 8. The gauntlet

Full detail, the complete gate inventory and the ratchet policy live in
**`docs/QUALITY-GATES.md`** — read that file for the "what each layer is FOR" argument
and the exact rules. The short version:

- **23 gates**, tiered FAST (green in about two minutes, safe to require on day one) and
  FULL (containers/browsers/mutation, live and reporting from day one, promoted to
  required in one documented step within the first week — see
  `docs/runbooks/branch-protection.md`).
- **Every numeric floor ships as the literal `unset` sentinel.** Nothing is calibrated
  against anyone else's code, ever. Run `tools/measure-floors.sh` against **your own**
  product (explicitly online, explicitly slow — the opposite contract to `init.sh`) to
  arm the ratchet against your own measured baseline. It refuses to run while
  `examples/` still exists, so a floor can never be calibrated to the bundled toy
  service. When you are ready, `tools/adopt-layout.sh` retires the example **and**
  re-points the whole harness (workflows, tools, `.gitignore`) at your product's
  root layout — `backend/` and `frontend/` — in one idempotent step; the harness
  guards detect the layout themselves and need no editing.
- **Your floors are your measured baseline; they only move up from there.** Never
  someone else's finish line — see the worked-example numbers in
  `docs/QUALITY-GATES.md`, which are one team's result after months of ratcheting, not
  a default.

**Porting to your own stack** (which files to swap, gate by gate):
`docs/runbooks/porting-to-your-stack.md`.

**Secrets, subscription-vs-API-key billing, and honest cost estimates:**
`docs/runbooks/credentials-and-cost.md`. Short version: one flat monthly agent-CLI
subscription covers everything except the *optional* adversarial second reviewer,
which needs its own API key.

## 9. Troubleshooting

Something not behaving the way you expect? `docs/runbooks/troubleshooting.md` matches
the symptom you're seeing (a hung check, a silent mention, a "skipped" gate you
expected to run, and more) to its actual cause — most of the time it's working as
designed. For a red gate specifically, `docs/runbooks/qa-procedures.md` has the deeper
triage process.

## 10. Upgrading, license, contributing

**Upgrading.** This is a template repository, not a library — your fork copies it once
and there is no ongoing pull relationship after that. To catch up with a later release,
diff your fork against `CHANGELOG.md`'s release notes. That is also why the harness stays
confined to `.agents/`, `.github/`, `tools/` and the docs at the repo root: keeping the
surface small keeps that diff readable.

**License.** [MIT](LICENSE).

**Contributing.** See `CONTRIBUTING.md` — it routes each new incident-derived rule back
here, so a lesson learned in one fork accumulates upstream instead of dying there.

---

**The exact first-time setup order** (what to do, in what order, including the steps
that can't be committed to a repository — a vendor scheduler and an admin setting
aren't files) is in `docs/runbooks/agent-operator-guide.md`. Lost at any point?
`tools/status.sh` prints the same map with your position on it, read-only, seconds.
