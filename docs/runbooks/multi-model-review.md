# Multi-model review — running the adversary on a different model family

**The rule.** Adversarial work in this repo — the challenger's blind re-derivation, and
the second review on every pull request — runs on the **`challenge` role's model**, which
`.agents/config.yml` requires to be from a **different model family** than the `judge`
role.

Roles, never vendor names, everywhere except `.agents/config.yml` and
`tools/providers/`. That is what lets an adopter swap either side without editing a
workflow, a prompt or this document.

## What was wrong

Every checking agent ran on the same model as the agent it was checking.

The challenger's prompt tells it to "go in blind" and re-derive another agent's conclusion
from scratch. That is the right instruction, but the re-derivation was running on the same
model that produced the conclusion. **If a model reasons its way into a wrong answer once,
it tends to reason its way there again from the same evidence.** Blindness stops it
*copying* the answer; it does not stop it *reproducing* the answer. The result looks like
independent confirmation and is not.

Code review had the plain version of the same problem: one reviewer, one set of things it
never notices, and nothing else looking.

## What changed

Two places now run a second model:

| Where | What runs on the `challenge` role | Who decides |
|---|---|---|
| `.github/workflows/review.yml`, job `challenge-review` | A full second review of the same diff, written without reading the first one | A human. The `referee` job sorts the two reviews; it does not grade them. |
| The `challenger` scheduled agent (`docs/runbooks/agent-routines.md`) | The blind re-derivation of the target conclusion | The challenger's own `judge`-role session, after weighing the challenge model's reasoning |

A different family is trained separately and **fails in different places**. That is the
entire point — a second opinion is only worth having if it can disagree. Two draws from
the same distribution share the same blind spots, so a "second opinion" from the same
family is a more expensive way to get the first one.

## Why the adversary never decides

A second model that can *overrule* the first one just moves the single point of failure.
So it cannot:

- The referee runs on the `judge` role, which wrote one of the two reviews it reads. Its
  prompt forbids it from saying who is right, and **its output format has no field for a
  verdict**. It reports where the two agree, where only one spoke, and where they
  contradict each other. A human reads that.
- The challenger reads the challenge model's derivation, checks whether the reasoning
  holds, and forms its own view. A refutation is something the challenger concluded, never
  something it copied through. The adversary disagreeing is a reason to look hard, not a
  ruling.

**A finding only one reviewer raised is not outvoted by the other's silence.** It is the
most valuable thing on the page, because a single reviewer would have lost it completely.

## Setup

### 1. Get a credential

Most providers sell two different things, and they are usually not interchangeable:

- **A flat monthly subscription**, typically scoped to *interactive* use of a coding tool.
- **A metered API key**, billed per token.

CI jobs and unattended routines are automation, not interactive use. **Confirm with your
provider which product covers them before relying on a subscription for either.** If in
doubt, use the metered key — this is the one place in the whole system where per-token
spend is genuinely required, and it is small.

### 2. Store it

| Where | Name | Effect if missing |
|---|---|---|
| Repository secrets | `CHALLENGE_API_KEY` | `challenge-review` and `referee` skip with a workflow warning; the `judge` review still runs. Every pull request gets one reviewer instead of two. **The pull request is never failed by the absence.** |
| The scheduled runner's environment | `CHALLENGE_API_KEY` | The challenger re-derives on the `judge` model and records `"challenge":"unavailable — key unset"`. The check still happens, with a stated caveat. |

Never put the key in a tracked file (`AGENTS.md` guardrail 5). Any settings file that is
committed is not a place for it — including the ones whose `env` blocks look convenient.

`auth.compatible-endpoint.required` is `false` in `.agents/config.yml` on purpose. This is
the one credential the system is designed to survive losing: absent, it degrades to one
opinion **and says so**, which is a signal. Silently degrading would not be.

### 3. Network

The endpoint must be reachable from the environment that runs the review. Test it before
you rely on it:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" --max-time 20 \
  -X POST "$CHALLENGE_BASE_URL/messages" \   # base_url from .agents/config.yml (auth.compatible-endpoint).
                                             # Convention: base_url INCLUDES the version segment (.../v1),
                                             # so append only the route — .../v1/v1/messages is the classic
                                             # double-up when a doc hard-codes both halves.
  -H 'content-type: application/json' -d '{}'
```

- `401` — reachable. The endpoint answered and wants a key. **This is the expected
  result** and it is the one you want to see: it proves the network path, not the
  credential.
- `403` — blocked by a proxy before it ever left. Allow the host in the environment's
  network settings (`agent-access-setup.md`, step 1).

Run this once from the *same environment* the agent runs in. A `401` from your laptop
proves nothing about a runner behind a proxy.

## Calling the challenge model from inside an already-authenticated session

A scheduled session runs on its own subscription against its own provider. You **cannot**
change the model that session is running on — overriding a base URL does not repoint an
already-authenticated session, and setting it would only break your own credentials.

What works is spawning a **second CLI as a subprocess** with the base URL and auth token
overridden, and the original credentials unset. `tools/providers/compatible-endpoint.sh`
implements exactly this; the shape is:

```bash
# A separate config directory, so the subprocess cannot write over the parent
# session's own state.
export AGENT_ALT_CONFIG_DIR=/tmp/challenge-agent && mkdir -p "$AGENT_ALT_CONFIG_DIR"

# Seed workspace trust in that fresh config directory — see lesson 3 below.
# (the adapter does this for you)

# Unset EVERY inherited provider credential — see lesson 1. Spelled as the
# PATTERN, not as one provider's variable names: run-agent.sh derives the list
# from the environment (*_API_KEY, *_AUTH_TOKEN, *_OAUTH_TOKEN, *_BASE_URL), so
# a provider nobody thought to enumerate cannot survive into the subprocess.
env -u '<PROVIDER>_API_KEY' -u '<PROVIDER>_AUTH_TOKEN' -u '<PROVIDER>_OAUTH_TOKEN' \
  AGENT_BASE_URL="$CHALLENGE_BASE_URL" \      # auth.compatible-endpoint.base_url from .agents/config.yml
  AGENT_AUTH_TOKEN="$CHALLENGE_API_KEY" \
  timeout 900 <cli> -p "<your prompt>" --model "<the challenge role's exact model id>" \
  > /tmp/challenge-out.md 2>&1
```

**Four things that will otherwise cost you a run** — each of these was learned the
expensive way:

1. **Unset the inherited credentials explicitly.** The subprocess inherits the parent
   session's credentials, which point at the parent's provider, not at the compatible
   endpoint. If the original credential survives into the subprocess **it wins**, and the
   "different family" second opinion is silently the same model. The check appears to run
   and proves nothing — which is the worst available outcome, because you now trust a
   confirmation you did not get. `tools/run-agent.sh` unsets every inherited `*_API_KEY`,
   `*_AUTH_TOKEN` and `*_BASE_URL` before exec for this reason.
2. **Use a separate config directory.** Sharing the parent's config directory risks the
   subprocess writing over the session's own state mid-run.
3. **Seed workspace trust in that fresh directory.** A brand-new config directory has not
   trusted this workspace, so the CLI prints "this workspace has not been trusted" and
   **ignores every entry in the repo's permission allowlist** — the run then fails in a way
   that looks like a permissions bug in your own config. Seed the trust flag instead. Do
   *not* reach for a skip-all-permissions flag: this is a subprocess you are handing an
   untrusted second opinion to, and the allowlist is the only thing bounding it.
4. **Always use `timeout`.** A bad key does not fail fast; the CLI retries and hangs. A
   two-minute test with a dummy key hit the timeout rather than erroring, so a hung run is
   the *expected* symptom of a wrong credential, not an exotic one. `run-agent.sh` passes
   `AGENT_TIMEOUT_SECONDS` and every adapter must honour it.

## Cost

Every pull request runs two reviews plus a referee, so review cost is roughly double plus
a bit. In the usual configuration the challenge model is substantially cheaper per token
than the judge model, so the second half is the cheap half; the referee is a small call
over two comment bodies.

This is the only per-token spend in the system. Everything else — the steward, the gates,
the routines — runs on a flat-rate subscription where the marginal cost of a run is zero.

## Turning it off

- **Pull-request reviews:** delete the `CHALLENGE_API_KEY` repository secret.
  `challenge-review` and `referee` skip with a warning and the `judge` review carries on
  unchanged. Nothing else to do.
- **The challenger agent:** delete the environment secret. It reports
  `"challenge":"unavailable — key unset"` and re-derives on the `judge` model.

Neither switch can leave a pull request or a routine run *unchecked* — only checked by one
model instead of two. That distinction is the whole design: **degrade to one opinion,
never to no check.**

## What this does not do

- It does not make either model authoritative. Both can be confidently wrong, and they can
  be wrong together.
- It does not replace the quality gates in `docs/QUALITY-GATES.md`. Two reviewers agreeing
  is not a passing test suite.
- It does not extend to every agent. Only the challenger and the pull-request reviewer run
  a second model; the rest are unchanged.
