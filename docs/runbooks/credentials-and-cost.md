# Credentials and cost

What each secret is for, what happens if it's missing, and what this actually costs to
run — the honest version, not the sales version.

## Secrets — what each one is for, and what happens without it

| Secret | Enables | If it is missing |
|---|---|---|
| `AGENT_CLI_TOKEN` | The steward, PR review's judge, and every scheduled routine — the agent CLI's own auth. **This is normally a SUBSCRIPTION TOKEN, not an API key** (see below) | **Required.** The job fails loudly (exit 5) — never a silent no-op, and the message tells you how to mint one |
| `CHALLENGE_API_KEY` | Reviewer B (the adversarial second opinion, a *different* model family) and the challenger routine | Optional. Reviewer B skips with a `::warning::`; reviewer A's review stands and the PR is never failed for it (see "Missing second-reviewer credential degrades, never fails" in the spec). The referee still runs — instead of a comparison it posts a notice naming **which** review is missing, and it is where the steward handoff is filed |
| _(any secret, on a fork)_ | — | Pull requests **from forks receive no secrets at all**, so neither reviewer can authenticate. Both skip and a comment on the pull request says nobody reviewed it — never a red check, because a failure an outside contributor cannot fix teaches everyone to ignore a red review |
| `STEWARD_HANDOFF_PAT` | Lets a lost-review handoff issue actually retrigger the steward | Optional. Falls back to the default `GITHUB_TOKEN`, which GitHub will not let start a new workflow run — the filed issue says so explicitly and tells you to mention the agent by hand |
| `ALERT_WEBHOOK_URL` | The push side of a nightly-failure alert (chat/webhook ping) | Optional. The GitHub issue — the primary channel — still opens; only the push is skipped, and the run's summary says so |
| `CI_HEALTH_PAT` | The optional CI-health watchdog (self-hosted runner liveness, hosted-minutes) | Optional. The watchdog announces it checked nothing and exits 0 — never a silent skip |
| `DEIDENT_TERMS` | The de-identification sweep in `fast-repo-hygiene`, for your own fork's naming hygiene | Optional, adopter-supplied. The sweep announces it is unarmed and skips — never a false "clean" |
| `VALIDATE_DB_PASSWORD` | `full-migration-validation`'s scratch Postgres service | Optional — defaults to a fixed password scoped to that ephemeral CI container |
| `IT_DB_PASSWORD` | `full-integration-tests`'s scratch Postgres service | Optional — same default-password pattern as above |
| `NVD_API_KEY` | Gate 16's backend CVE scan (`nightly-dependency-scan`), a free key from [nvd.nist.gov](https://nvd.nist.gov/developers/request-an-api-key) | Optional. The backend half of the scan SKIPS with a `::notice::` — the frontend advisory audit is unaffected, and the gate is never failed for the absence. Without a key, dependency-check's NVD client currently errors out updating its database rather than degrading to slower unauthenticated access, so running it anyway would report a false gate failure |

## Subscription token or API key? The two are not interchangeable

This trips people up, so it is worth being blunt. `AGENT_CLI_TOKEN` is a **name**, not a
kind. What belongs in it is decided by `auth.<provider>.mode` in `.agents/config.yml`:

| `mode` | What `AGENT_CLI_TOKEN` holds | Billing |
|---|---|---|
| `subscription` *(the default)* | An **OAuth token minted from your existing plan** — the thing your agent CLI's own "set up a token" command prints. **Not** the key from a developer console. | Covered by your flat monthly plan. A run costs nothing extra. |
| `api-key` | A real API key. | Per token. |

Ask the repository itself rather than guessing — it prints the exact command for the
provider *you* configured, and prints nothing vendor-specific for one you did not:

```bash
tools/run-agent.sh --check-credentials <agent>
```

With the credential missing, that exits 5 and tells you which secret is absent, which
mode it is in, how to mint it, and where to paste it. With it present, it exits 0.

`CHALLENGE_API_KEY` is the one place a **per-token API key is genuinely required**: it
reaches a second model family, and no subscription covers somebody else's model. It is
optional by design — without it the adversarial second opinion degrades to one reviewer
and says so, and a pull request is never failed for its absence.

## Cost, honestly

**Lead with the subscription model, because it is the normal case.** One flat monthly
agent-CLI subscription runs the steward, both scheduled reviews' judge role, and every
routine — the marginal cost of one more run is zero, and nothing surprises you at the
end of the month.

The only place real per-token spend can enter is the **optional** `challenge` role
(`CHALLENGE_API_KEY`, a different model family via `compatible-endpoint`). Losing that
key costs you a second opinion on reviews — never the system; see the secrets table
above. If you must run on API keys throughout instead of a subscription, the pieces
that spend tokens, roughly in ramp order, are: each steward run, two reviews per pull
request (one if the challenge key is absent), and each enabled routine once per day.
Turn routines on one at a time (`README.md` section 6) precisely so spend stays
proportional to the value you are actually getting, rather than jumping straight to
ten daily/weekly agents plus two reviews per PR.
