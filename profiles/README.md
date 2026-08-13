# Answer-file profiles

A profile is a ready-made `--answers` file for `tools/init.sh` — the whole
adoption interview, pre-filled, minus the one answer nobody can default:
`PRODUCT_NAME`. Use one directly:

```bash
cp profiles/claude-code.answers /tmp/answers
# edit /tmp/answers: set PRODUCT_NAME (and adjust model ids if the hint URL says so)
tools/init.sh --answers /tmp/answers
```

Every variable a profile may set is exactly the interview's own list — see
`tools/init.sh --help`. A variable a profile leaves unset is asked
interactively (or fails loudly in a non-interactive shell), so a profile can be
as partial as you like.

## Why this exists: the platform-team pattern

A profile is the unit an organization ships. One platform team writes ONE
internal profile — provider, the exact model ids the org has access to, the
internal gateway URL for the challenge role, the alert channel, the runner
labels — publishes it internally, and every team adopts with it:

```bash
tools/init.sh --answers /path/to/acme-internal.answers
```

That is what "a couple of clicks" looks like inside a company: the individual
adopter answers one question (the product name) because the platform team
already answered the other ten. Model ids churn; update the profile, not every
team's memory.

## Notes on the shipped profiles

- Model ids are **examples dated by the adapter hints** — each adapter's
  `ADAPTER_MODEL_HINT` (shown during the interview, or via
  `tools/run-agent.sh --adapter-status <provider>`) carries the URL that stays
  authoritative. Trust that URL over any committed file, this one included.
- `CHALLENGE_BASE_URL` must be **Anthropic-wire-compatible** (an endpoint
  serving `/v1/messages`) — z.ai's `/api/anthropic` path is one, and a LiteLLM
  or similar internal gateway can expose one in front of another model family.
  `none` is valid: reviews degrade to one opinion, announced, never a red PR.
- `codex` and `gemini-cli` ship as unverified stubs (they refuse to run until
  finished and verified — each stub's own header comment documents the
  promotion path), so there is no profile for them yet. Add one alongside the
  adapter when you verify it.
