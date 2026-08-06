# Agent access setup — one-time wiring, HTTPS-first

<!-- placeholder: {{PRODUCT_NAME}} — the system your agents watch. -->
<!-- placeholder: {{ALERT_CHANNEL}} — how alerts reach a human: none | webhook | command. -->

This is the one-time wiring that gives scheduled agents their **read-only** production
access. It is the mechanical half of `AGENTS.md` guardrail 1.

**No SSH key, no database credentials, no log mirror, no tunnel.** Everything an agent
needs is reachable over HTTPS: an observability endpoint that fronts your metrics and your
logs, and the application's own public health endpoints. Total operator effort ≈ 30
minutes.

> **This file is a SHAPE, not a recipe.** Every host, token name and product below is an
> example. What is not negotiable is the *order* of the steps and the four access rules at
> the bottom — those are what keep an autonomous agent from being able to break production
> even if it is completely wrong about everything else.

## The five steps, in order

Do them in this order. Each one is a prerequisite for the next, and the last one is the
dry-run that tells you whether the first four actually worked.

### Step 1 — Network allowlist (~2 min)

Agent runners usually sit behind an egress proxy that denies by default. Allow outbound
HTTPS from the runner's environment to:

- your observability host;
- your application's public host;
- the alert-channel endpoint, if `alerts.channel` is not `none`;
- the compatible endpoint that serves the `challenge` role, if you are using one
  (`docs/runbooks/multi-model-review.md`).

**Test from the runner's environment, not from your laptop.** A `200` from your machine
proves nothing about a proxy the agent has to cross. The expected result for an
authenticated endpoint is `401` — that means "reachable, and it wants a credential", which
is exactly what you want to see at this stage. A `403` usually means the proxy blocked the
request before it ever left.

```bash
curl -sS -o /dev/null -w "%{http_code}\n" --max-time 20 "https://<host>/api/health"
```

If an agent needs to reach arbitrary third-party sites (an auditor that samples public
pages, say), you have two honest options: give that environment full network access, or
keep the allowlist and run that one agent somewhere that has it. **Do not give an agent a
partial allowlist and hope** — it will report "no data" from a blocked host and a "no
data" that is really a network failure is indistinguishable from a genuinely quiet system.
`agent-modes.md` already says a `no data` is not a pass.

### Step 2 — A read-only observability credential (~5 min)

Create a **service account with the narrowest read-only role your platform offers**, and
mint a token for it. Not an admin token with a promise to be careful.

**If your observability host sits behind an edge gate (basic auth, an IP allowlist, a
WAF), the agent's credential for that gate MUST be distinct from the human admin
credential.** This is the most expensive lesson in this file and it is worth stating in
full, because the wrong version of it looks fine:

- An edge gate typically cannot inspect an `Authorization: Bearer` header, so it rejects
  the request **before** the read-only token is ever evaluated. The agent gets a `401`
  that has nothing to do with its own credentials.
- The obvious fix — hand the agent the human's edge password as well — fails twice over.
  Mechanically, most clients can only send one `Authorization` header, so combining a
  basic-auth credential with a Bearer token silently drops the Bearer half. And
  substantively, the edge password is frequently *the same secret as the platform's admin
  account*, so sending only the edge credential authenticates the agent as **full admin**
  rather than as the intended read-only viewer. A privilege escalation delivered by a
  documentation change.
- The correct fix is structural: give the edge gate a **distinct, single-purpose bypass
  secret** that clears the gate and grants nothing, and let the read-only Bearer token be
  the agent's only real authentication. Then disable the platform's own basic auth, so the
  admin-equivalence path is closed by construction rather than by convention.

The general rule, which outlives the specific stack: **a credential that clears a gate
must not also be a credential that grants authority.** If one secret does both, an agent
holding it has more power than your access diagram says it does.

Generate the bypass secret with real entropy and keep it server-side, outside git:

```bash
openssl rand -hex 32
```

Ship the repository's copy of any bypass configuration as an **inert placeholder**, so the
bypass does not exist until an operator deliberately creates the server-side file. A
committed bypass value is a committed credential.

### Step 3 — Agent environment secrets (~5 min)

Set these in the runner's environment (repository secrets, or your scheduler's secret
store). Names, and what breaks when each is absent, are in the README's secrets table.

| Secret | What it is | Absent ⇒ |
|---|---|---|
| `AGENT_CLI_TOKEN` | the subscription token or API key for the `judge`/`execute` provider | the agent cannot run at all — `run-agent.sh` exits 5, loudly |
| `CHALLENGE_API_KEY` | the optional `challenge`-role credential | **degrades**: one opinion instead of two, with a warning. Never a red pull request |
| `ALERT_WEBHOOK_URL` | the pushed alert channel, if any | the notifier still files the issue. The issue is the primary channel |
| `STEWARD_HANDOFF_PAT` | an elevated token so one agent's action can wake another workflow | the handoff issue is still filed, and the run says loudly that the handoff did not happen |

**Subscription first.** Most coding-agent CLIs run on a flat-rate subscription rather than
per-token billing, so a raw API key is the fallback, not the norm. The one place a
per-token key is genuinely required is the `challenge` role, and that key is optional by
design.

Never write a secret into a commit, a comment, a log, or a ledger entry (guardrail 5).
Every secret above is a NAME in the config, never a value.

### Step 4 — Repository wiring (~10 min)

- Create the `agent-ledger` orphan branch (`docs/runbooks/agent-ledgers.md`).
- Pin one discoverable issue per agent, whose body says where the ledger actually lives.
- Install whatever app or token your agent CLI needs in order to act on the repository.
- **Do not enable branch protection yet.** It is the last step, deliberately — see step 5
  and `docs/runbooks/branch-protection.md`.

### Step 5 — One interactive dry-run per agent, THEN schedule (~10 min)

Run each agent once, interactively, watching it, before it ever runs on a cron:

```bash
tools/run-agent.sh <agent> --dry-run     # prints the exact command, invokes nothing
tools/run-agent.sh <agent>               # the real interactive run
```

For each agent confirm, by looking: the observability queries return **data** and not an
empty result; the alert-channel test message arrives; exactly **one** ledger entry is
written; and the analysis is actually correct. An agent that runs cleanly and concludes
something wrong is the failure mode this whole system is built to make visible, and the
dry-run is the cheapest place to catch it.

Only then enable that agent's schedule, **one at a time**
(`docs/runbooks/agent-routines.md`). Nobody should meet this system as five crons and an
alert firehose on day one.

Branch protection goes on **last** (`docs/runbooks/branch-protection.md`). Until it is on,
every gate is advisory.

## The HTTPS access pattern (what agent prompts refer to)

Agent prompts never contain a hostname or a credential. They refer to these capabilities,
and `.agents/health-signals.yml` holds the actual queries.

- **Metrics** — one query API, called with the read-only token (and the edge bypass header
  if you have one). Ask for a *series*, not a snapshot: the trend rules in
  `agent-routines.md` are arithmetic, and arithmetic needs more than one point.
- **Logs** — the same API and the same credentials, with a log datasource. **Query a time
  range and filter server-side; never pull a whole day raw.** This is efficiency rule
  territory, and it is also the difference between a run that finishes and one that dies
  out of memory.
- **Application health** — the public health and status endpoints, no credential.
- **Public sampling** — where an agent samples public pages, use a plain HTTP client
  rather than a full browser where you can. A launched browser behind a re-terminating
  proxy commonly fails with a connection reset, because a fresh browser profile does not
  trust the proxy's certificate, and debugging that is not the agent's job. Treat any
  suspiciously thin or empty response as an explicit `NO_SIGNAL` value and **never
  silently compare it** — a fetch path that cannot execute client-side scripts will
  cheerfully report an empty page as a change.
- **There is no advanced fallback.** If a deep dive genuinely needs shell access to a box,
  that is an escalation with the exact commands written out, not an agent capability
  (guardrail 1).

## The four rules this file exists to enforce

1. **Read-only, over HTTPS, always.** No SSH key, no database credential, no write token
   against production. Remediation is a human running commands the agent wrote down.
2. **A credential that clears a gate must not also grant authority.** See step 2.
3. **Least privilege at the platform, not in the prompt.** The agent's role is enforced by
   the token's scope. A prompt that says "please only read" is not an access control.
4. **Dry-run before schedule, branch protection last.** The order is the safety property.

## What an operator does when this goes wrong

An agent reporting "no data" is the ambiguous case, and it is common. Work in this order:

1. Is the host reachable from the **runner's** environment? (step 1)
2. Did the request reach the platform, or stop at the edge? A `401` from the edge and a
   `401` from the platform mean completely different repairs. (step 2)
3. Is the token still valid and still scoped to read?
4. Only then: is the system genuinely quiet?

Steps 1–3 are instrument failures. Reporting one of them as a finding about
{{PRODUCT_NAME}} is the same error as querying the wrong alerting system and announcing
"no alerts firing" — a confident, well-evidenced, entirely wrong conclusion. **Never
report a thing as absent until you have looked everywhere it can legitimately be, and say
in the report where you looked.**
