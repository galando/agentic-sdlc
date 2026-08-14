# Onboarding, driven by an agent

This file is written **to an agent** — Claude Code, Codex, or any capable coding
agent whose human said some version of *"adopt this template into my repository."*
If you are that agent: this is your complete procedure. Everything here is also
runnable by a human, one command at a time; nothing below is agent-only magic.

Two rules bind you before anything else:

1. **Read `AGENTS.md` first.** Its guardrails apply to you for this whole task.
   In particular guardrail 2: you propose, a human merges — you never merge
   anything yourself, here or ever.
2. **Every mutating step below is offline and local** except two named
   exceptions: creating the ledger branch (one push) and the GitHub-side steps
   in part 4 (which need an authenticated `gh`). If you cannot push or reach
   GitHub, do parts 1–3 and hand back part 4 as a list.

## 0. The one ordering trap

`tools/adopt.sh` is the guided walk, and it is what you will drive — but **in a
non-interactive shell it exits 0, telling you to run the interview yourself,
whenever the interview has not run yet**. An agent that starts with `adopt.sh`
gets a clean exit and nothing done, which looks like success. The order is
always:

1. `tools/init.sh --answers <file>` — the interview, scripted.
2. `tools/adopt.sh` with `ADOPT_*` variables — everything after the interview.

## 1. Interview the human (the answers only they know)

Collect these before touching anything. `profiles/` ships ready-made answer
files — start from the closest one and ask only for what it leaves unset:

| Variable | What to ask | Notes |
|---|---|---|
| `PRODUCT_NAME` | "What system will the agents watch?" | The only answer with no possible default |
| `PROVIDER` | Which agent CLI they subscribe to | `claude-code` \| `codex` \| `gemini-cli`; the two stubs refuse to run until verified — say so if they pick one |
| `MODEL_JUDGE` | Exact model id for reviews/referee/triage | Exact id, never an alias — `tools/run-agent.sh --adapter-status <provider>` prints the hint with the authoritative URL |
| `MODEL_EXECUTE` | Exact model id for mechanical runs | Cheaper tier of the same provider |
| `MODEL_CHALLENGE` | Exact model id for the second opinion | **Must be a different model family** than the judge |
| `CHALLENGE_BASE_URL` | Where the challenge model is served | Must be an **Anthropic-wire-compatible** endpoint (it serves `/v1/messages`); `none` is valid and documented — reviews degrade to one opinion, announced |

The remaining interview variables (`ALERT_CHANNEL`, `RUNNER_LABEL`,
`LEDGER_COMMIT_NAME`, `LEDGER_COMMIT_EMAIL`, `BUILD_PIPELINE`) have safe
defaults every profile sets; change them only if the human asks.

## 2. Run the interview, scripted

Write the answers to a file (or copy and edit a profile), then:

```bash
cp profiles/claude-code.answers /tmp/answers   # or the closest profile
# edit /tmp/answers: set PRODUCT_NAME, adjust models
tools/init.sh --answers /tmp/answers
```

`init.sh` is offline, idempotent, and finishes in seconds. It rewrites every
placeholder it resolves and prints what is left. **Verify before moving on:**

```bash
tools/check-placeholders.sh   # must exit 0; post-interview it must say clean
tools/status.sh               # the adoption map, with your position on it
```

## 3. Drive the guided adoption, non-interactively

`tools/adopt.sh` is resumable and idempotent; each `ADOPT_*` variable set to
`y` accepts one offer, and anything left unset is declined (adopt.sh prints the
manual command instead — collect those for the handback list). The full set,
verbatim from `adopt.sh`'s own header:

```bash
ADOPT_COMMIT=y ADOPT_MEASURE=y ADOPT_PROTECT=y ADOPT_ISSUE=y \
ADOPT_CONTINUE_WITHOUT_PRODUCT=y \
ADOPT_SET_TOKEN=y ADOPT_SET_CHALLENGE=y ADOPT_SET_HANDOFF=y \
ADOPT_WORKFLOW_PERMS=y ADOPT_FLOORS_PR=y \
DELETE_EXAMPLE=y WRITE_README=y CREATE_LEDGER_BRANCH=y \
tools/adopt.sh
```

Judgment calls you must make, not blindly accept:

- **`DELETE_EXAMPLE`**: only `y` if the human confirmed they don't want the
  bundled example product. It is an `rm -rf` (committed work survives in git
  history; the script refuses on uncommitted changes).
- **`ADOPT_MEASURE`** (floor calibration): leave **unset** until the human's own
  product code exists at `backend/`/`frontend/` — `measure-floors.sh` refuses
  while `examples/` is present, needs a clean tree, and is explicitly online
  and slow. Floors ship as loud `unset` sentinels until then; that is designed.
- **`ADOPT_SET_TOKEN` / `ADOPT_SET_CHALLENGE` / `ADOPT_SET_HANDOFF`**: these
  call `gh secret set`, which needs the secret **values**. Never ask the human
  to paste a credential into your chat if you can avoid it — prefer handing
  back the exact `gh secret set` commands for them to run in their own shell.
- **`ADOPT_PROTECT`** (branch protection): needs repo admin. Apply it **last**,
  after the FAST gates have been green once — `adopt.sh` sequences this
  correctly on its own; do not force it early.

## 4. Verify your own work — with the shipped checkers, never by eyeballing

After each phase, and always before you report done:

```bash
tools/check-placeholders.sh                 # zero unresolved placeholders
tools/status.sh                             # every step shows [done] or names what's left
bats tests/ tests/harness-guards/           # the harness suite — all green
tools/run-agent.sh --list-agents            # the ten scheduled agents resolve
tools/run-agent.sh health --dry-run         # exact argv, invokes nothing — repeat per agent
tools/run-agent.sh --check-credentials health   # names the missing secret, if any
```

A red anywhere is **your** finding: fix it or report it precisely; never report
adoption complete over a red check.

## 5. The handback — what only the human can do

End your run by giving the human this list, filled in with their repo's names
(everything you declined or that failed a `gh` probe goes here too):

1. **Mint the agent-CLI subscription token** (interactive vendor login on their
   machine; `tools/run-agent.sh --check-credentials <agent>` prints the exact
   mint command) and add it as the `AGENT_CLI_TOKEN` repository secret.
2. **Set the remaining secrets** they chose not to hand you:
   `CHALLENGE_API_KEY` (optional — second reviewer), `STEWARD_HANDOFF_PAT`
   (optional — sub-minute handoff latency), `GITLEAKS_LICENSE` (organization
   repos only), per `docs/runbooks/credentials-and-cost.md`.
3. **Org-level Actions policy**, if the repository setting "Allow GitHub
   Actions to create and approve pull requests" is overridden by their org —
   `adopt.sh` reports this as `[????] could not verify`.
4. **The first merge** — open issue #1, watch the steward triage it, and click
   merge themselves. That click is the system working, not a leftover chore.

## If this repository already has its own code (brownfield)

Use the installer — never overlay by hand. From a clone of the template:

```bash
tools/upgrade.sh --install /path/to/existing-repo
```

It copies the harness surface in, **never overwrites** (a collision lands
beside the host's file as `<name>.agentic-sdlc.proposed` for a human merge),
and stamps `.agents/template-manifest.json` — the pristine-content record that
makes every future template release a computable `tools/upgrade.sh plan/apply`
three-way merge instead of a changelog archaeology dig. Then continue from
step 2 of this document inside the host repo, with two honesty notes for the
human: keep their product **outside** `backend/`/`frontend/` until the
measured gates are swapped to their stack
(`docs/runbooks/porting-to-your-stack.md` — the process layer is live either
way), and merge every `.proposed` collision themselves. For a team that only
wants one piece, the self-contained kits still apply: `docs/knowledge/` +
`tools/knowledge-lint.sh`, `tools/ledger.sh`, or the review prompts — all
forge-neutral.
