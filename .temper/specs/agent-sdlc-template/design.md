# Design: Autonomous-Agent SDLC Template Repository

**Created:** 2026-08-05
**Complexity:** complex
**Risk:** HIGH
**Based on:** `intent.md`, `plan.md`, `tasks.md`, `agentsdlcrepoprompt.md`
**Source (READ-ONLY, never written):** `{{SOURCE_REPO}}`

This design specifies the seven surfaces that plan.md's Decisions 6–11 created and did
not yet make concrete. Everything the plan already fixed (extraction inventory, three-PR
order, bucket assignments, the eleven approach decisions) is taken as given and is not
re-opened. Where I found the plan or intent **wrong or self-contradictory**, it is said
plainly in §9 rather than designed around.

---

## 1. System Architecture

Four layers, plus one cross-cutting seam the plan named but did not draw.

```
                        .agents/config.yml            floors.yml
                        (schema: 1)                   (the ratchet ledger)
                              |                            |
                              v                            v
  +------------------- tools/lib/config.sh --------------------------------+
  |  THE ONLY PARSER. cfg_get, adapter_status, floor_get, assert_schema.   |
  |  Sourced by every tool below. No other file parses either YAML file.   |
  +---+---------+---------+---------+---------+---------+---------+--------+
      |         |         |         |         |         |         |
      v         v         v         v         v         v         v
  run-agent  ledger.sh  init.sh  measure-  render-   floor-    alert.sh
     .sh                         floors.sh floors.sh notice.sh
      |                             |         |         |
      |  exec (env-var contract)    |  writes |  writes |  prints, exits 0
      v                             v         v         v
  tools/providers/<name>.sh     floors.yml  pom.xml / vitest.config.js /
   claude-code       verified               stryker.config.mjs (marked blocks)
   compatible-endp.  verified
   codex             unverified
   gemini-cli        unverified
      |
      | SPEC_PIPELINE=plugin | fallback
      v
  tools/spec-pipeline/  --(validate.sh, one implementation)-->  gate 21
```

**Workflow layer** (the only thing branch protection sees) calls `run-agent.sh`,
`floor-notice.sh`, `alert.sh` and `spec-pipeline/validate.sh`. It never calls a vendor
action, never parses YAML config, and never contains a model id.

### What is new / modified / existing

| Class | Count | What |
|---|---|---|
| **Existing** — extracted near-verbatim (bucket A) | 8 | `agent-ledgers.md`, `agent-escalation.md`, `agent-temper-headless.md`, `pull_request_template.md`, `nightly-alert.yml`, `ledger.sh`, `agent-communication-style.md`, `multi-model-review.md` |
| **Modified** — extracted then genericized (bucket B) | 20 | `AGENTS.md`, `QUALITY-GATES.md`, `agent-routines.md`, `agent-modes.md`, `agent-operator-guide.md`, `branch-protection.md`, `qa-procedures.md`, `agent-access-setup.md`, `steward.yml`, `review.yml`, `pr-tests.yml`, `pr-mutation.yml`, `pr-validation.yml`, `secret-scan.yml`, + the five nightly workflows consolidated into `nightly.yml`, + `ci-health-watch.yml` |
| **New** — nothing upstream to extract | 26 | `config.yml`, 5 prompts, `health-signals.yml`, `lib/config.sh`, `run-agent.sh`, 4 adapters, `spec-pipeline/`, `init.sh`, `measure-floors.sh`, `render-floors.sh`, `floor-notice.sh`, `alert.sh`, `gen-adopting.sh`, `check-placeholders.sh`, `check-deidentified.sh`, `floors.yml`, `spec-artifacts.yml`, `actionlint.yml`, `agents-scheduled.yml`, harness-guard suite, bats suites, `examples/`, front-door docs |

Data flow, one sentence: **an event or a cron reaches a workflow, the workflow reaches
`run-agent.sh`, `run-agent.sh` resolves role → model → prompt → adapter from the single
config, the adapter executes exactly one CLI invocation, and the run's only durable
outputs are a ledger line on an orphan branch and a spec directory in the diff.**

---

## 2. `.agents/config.yml` — the full schema

### 2.1 Worked example (this is the shipped file, pre-`init.sh`)

```yaml
# .agents/config.yml — the ONE file an adopter edits to change provider or model.
# Read by: tools/lib/config.sh (the only parser). Everything else asks that library.
# Breaking-change policy: see the header comment on `schema:` below.

schema: 1                     # integer. Bumped ONLY on a breaking change. See §2.3.

provider: "{{PROVIDER}}"      # placeholder: claude-code | codex | gemini-cli | compatible-endpoint.
                              # Must equal a filename in tools/providers/ without .sh.

# ---------------------------------------------------------------------------
# Models are addressed by ROLE, never by task and never by vendor name.
# Pin EXACT ids. A floating alias ("opus", "sonnet", "latest") silently resolves
# to whatever the platform default is, which defeats knowing which model reasoned.
# ---------------------------------------------------------------------------
models:
  judge:     "{{MODEL_JUDGE}}"      # placeholder: strongest model. Reviews, referee, triage decisions.
  execute:   "{{MODEL_EXECUTE}}"    # placeholder: cheaper model. Mechanical edits, scheduled routines.
  challenge: "{{MODEL_CHALLENGE}}"  # placeholder: a DIFFERENT MODEL FAMILY. A second draw from the
                                    # same distribution shares the same blind spots.

# Which provider delivers which role. Usually one provider for judge+execute and a
# compatible endpoint for challenge — that split is the whole point of the role model.
role_provider:
  judge:     "{{PROVIDER}}"
  execute:   "{{PROVIDER}}"
  challenge: compatible-endpoint

# ---------------------------------------------------------------------------
# Auth, per provider. Subscription first; an API key is the fallback, not the norm.
# `token_secret` names a GitHub Actions secret — never a value. Guardrail 5.
# ---------------------------------------------------------------------------
auth:
  claude-code:
    mode: subscription              # subscription | api-key
    token_secret: AGENT_CLI_TOKEN
    required: true                  # absent credential => exit 5, the job fails loudly
  codex:
    mode: subscription
    token_secret: AGENT_CLI_TOKEN
    required: true
  gemini-cli:
    mode: subscription
    token_secret: AGENT_CLI_TOKEN
    required: true
  compatible-endpoint:
    mode: api-key
    token_secret: CHALLENGE_API_KEY
    base_url: "{{CHALLENGE_BASE_URL}}"  # placeholder: the compatible endpoint's base URL.
    required: false                 # OPTIONAL BY DESIGN. Absent => exit 6 => the caller
                                    # degrades to one opinion and says so. Never a red PR.

# ---------------------------------------------------------------------------
# A workflow `if:` cannot read a file, so the trigger phrase lives in a repo
# variable with a default. This block documents it; it does not set it.
# ---------------------------------------------------------------------------
mention:
  variable: AGENT_MENTION
  default: "@agent"

# ---------------------------------------------------------------------------
# Alerting. `channel: none` is legal and means "GitHub issues only" — the issue
# is the PRIMARY channel and needs only GITHUB_TOKEN. A pushed channel is additive:
# if it is missing the notifier still files the issue. Never let the notifier be the
# thing that breaks when a secret rotates, or you lose the alert about losing the alert.
# ---------------------------------------------------------------------------
alerts:
  channel: "{{ALERT_CHANNEL}}"      # placeholder: none | webhook | command
  webhook_secret: ALERT_WEBHOOK_URL # used only when channel: webhook
  command: ""                       # used only when channel: command; receives the message on stdin
  severity_floor: S2                # do not push anything below this; S3 is issue-only

# ---------------------------------------------------------------------------
# Liveness. Absence must be the signal — but on a BEST-EFFORT scheduler, "did not
# run today" fires on ordinary lateness. Escalate on the AGE of the newest entry,
# never on a count of consecutive misses. See Decision 11 / agent-routines.md.
# ---------------------------------------------------------------------------
liveness:
  max-age-hours: 12                 # default tolerance for a DAILY agent. Comfortably past
                                    # normal cron drift. Tightening this below the scheduler's
                                    # real drift converts liveness detection into alert fatigue,
                                    # which ends with the check muted and nothing watching.
  staleness-hours: 36               # EXTERNAL check: newest entry across ALL agents. A ring
                                    # cannot detect its own total absence — there is nobody left
                                    # to notice. GitHub also disables scheduled workflows after
                                    # ~60 days of repository inactivity, which makes total
                                    # silence a real scenario for a template repo.

# ---------------------------------------------------------------------------
# The ledger. `agents:` is THE list — ledger.sh validates against it, latest/trend
# iterate it, agents-scheduled.yml builds its matrix from it, and the watcher ring's
# predecessor is simply the PREVIOUS ENTRY IN THIS LIST, wrapping at the top.
# One list. A separate ring table would be a second source of truth.
# ---------------------------------------------------------------------------
ledger:
  branch: agent-ledger
  identity:
    name: "{{LEDGER_COMMIT_NAME}}"    # placeholder: commit author for ledger writes, e.g. "sdlc-agent"
    email: "{{LEDGER_COMMIT_EMAIL}}"  # placeholder: commit email, e.g. "agent@example.invalid"
  agents:
    - id: health
      prompt: .agents/prompts/health.md
      role: execute
      schedule: "17 6 * * *"          # odd minutes: the top of the hour is the most contended slot
      enabled: false                  # minimal mode. One-line enable, see README §6.
    - id: quality
      prompt: .agents/prompts/quality.md
      role: execute
      schedule: "23 7 * * *"
      enabled: false
    - id: audit
      prompt: .agents/prompts/audit.md
      role: execute
      schedule: "41 8 * * *"
      enabled: false
      max-age-hours: 26               # per-agent override of liveness.max-age-hours
    - id: chief-of-staff
      prompt: .agents/prompts/chief-of-staff.md
      role: judge
      schedule: "13 17 * * *"
      enabled: false
    - id: challenger
      prompt: .agents/prompts/challenger.md
      role: challenge
      schedule: "37 18 * * *"
      enabled: false

# The spec-artifact contract version that tools/spec-pipeline/validate.sh enforces.
spec_contract: 1
```

`.agents/health-signals.yml` is a **separate** file, deliberately:

```yaml
# The health checker reads its signals from here. Ships EMPTY on purpose.
# An empty list means the health agent reports "no health signals configured"
# and exits green. It does NOT mean a broken query. See §4.3.
schema: 1
signals: []
# Example (delete the comment markers and fill in when you have a metrics source):
#   - id: disk_saturation
#     query: 'node_filesystem_avail_bytes / node_filesystem_size_bytes'
#     warn_below: 0.20
#     severity: S2
```

### 2.2 The single-parser rule

`tools/lib/config.sh` is the **only** code that reads `config.yml`, `health-signals.yml`
or `floors.yml`. It exposes exactly:

| Function | Contract |
|---|---|
| `cfg_assert_schema <file> <supported>` | exits 3 with a CHANGELOG pointer on mismatch |
| `cfg_get <dotted.path> [default]` | one scalar to stdout; exit 3 if required and absent |
| `cfg_list <dotted.path>` | one item per line |
| `cfg_agents` | agent ids, in ring order, one per line |
| `cfg_predecessor <agent>` | the previous agent in the list, wrapping |
| `adapter_status <provider>` | `verified` \| `unverified`; exit 3 on missing/ambiguous |
| `adapter_docs_url <provider>` | the URL |
| `floor_get <key>` | numeric value or the literal `unset` |

Implementation: prefer `yq` when on `PATH`; otherwise a restricted awk reader. The
restriction is a **documented constraint on the config file**, enforced by
`tests/config-reader.bats`, which runs both readers over the shipped config and asserts
byte-identical output for every documented path:

- two-space indent, no tabs
- no anchors, aliases, merge keys, multi-line scalars or flow maps
- list items are `- key: value` maps or `- scalar`
- comments start at column 0 or after two spaces

Rationale: `yq` is not on the plan's dependency list and cannot be assumed on an
adopter's laptop, but `--dry-run` must work "with no agent CLI installed at all" (SC4)
and `init.sh` must make no network calls (SC7). A pure-shell fallback is the only way
both hold. Two readers is a real cost; one test that proves they agree is the price.

### 2.3 The versioning rule (this is a breaking-change contract with strangers)

`config.yml` is read by `run-agent.sh`, all four adapters (indirectly, via the env-var
contract), `agents-scheduled.yml`, `steward.yml`, `review.yml`, `ledger.sh`, `init.sh`,
`measure-floors.sh` and `alert.sh`. Every one of those lives in the **adopter's** copy,
which upstream can never patch.

- **`schema:` is an integer, incremented only on a breaking change.**
- Breaking = renaming a key, removing a key, changing a key's type or meaning, making an
  optional key required, or changing a default in a way that changes behaviour.
- **Not** breaking = adding an OPTIONAL key with a documented default, adding a list
  entry, or changing a comment. These do not bump `schema`.
- Every consumer calls `cfg_assert_schema .agents/config.yml 1` before its first read.
  On mismatch: exit 3 with
  `config schema N is not supported by this tool (expects M) — see CHANGELOG.md "Config schema N → M"`.
- Every `schema` bump requires, in the same release: a `### Breaking` entry in
  `CHANGELOG.md` naming every changed key with old → new, a migration paragraph in
  `ADOPTING.md`, and a `tools/migrate-config-N-to-M.sh` that is idempotent and offline.
- `init.sh` refuses to run against a config whose schema it does not know, rather than
  rewriting it — a template that silently upgrades a stranger's config is the same class
  of failure as a green run with a wrong answer.

---

## 3. The `run-agent.sh` → adapter contract

### 3.1 Command line

```
tools/run-agent.sh <agent> [--role judge|execute|challenge] [--dry-run]
                           [--prompt-file PATH] [--timeout SECONDS]
tools/run-agent.sh --check-credentials <agent>     # resolve auth only; run nothing
tools/run-agent.sh --adapter-status <provider>     # print one word
tools/run-agent.sh --list-agents                   # ring order, one per line
```

`--role` overrides `ledger.agents[].role`. It exists because `review.yml` needs to invoke
the same script three times with three different roles against three prompts.

### 3.2 Environment IN — what `run-agent.sh` guarantees the adapter

The adapter is executed as `exec tools/providers/<provider>.sh <verb>` with a clean
environment plus exactly these. **An adapter must never read `config.yml` itself** — one
parser, one place a schema change lands.

| Variable | Always set? | Meaning |
|---|---|---|
| `AGENT_NAME` | yes | agent id, e.g. `health` |
| `AGENT_ROLE` | yes | `judge` \| `execute` \| `challenge` |
| `AGENT_MODEL` | yes | the resolved **exact** model id for the role |
| `AGENT_PROMPT_FILE` | yes | absolute path; the adapter passes a PATH, never the text |
| `AGENT_SYSTEM_PROMPT_FILE` | yes | absolute path to `.github/agent-temper-headless.md` |
| `AGENT_WORKDIR` | yes | absolute repo root; the adapter must `cd` here and nowhere else |
| `AGENT_AUTH_MODE` | yes | `subscription` \| `api-key` |
| `AGENT_AUTH_TOKEN` | yes (may be empty) | the resolved secret VALUE |
| `AGENT_AUTH_REQUIRED` | yes | `1` \| `0` |
| `AGENT_BASE_URL` | yes (may be empty) | non-empty only for `compatible-endpoint` |
| `AGENT_ALLOWED_TOOLS` | yes | comma-separated tool grant, from `run-agent.sh`'s single default |
| `AGENT_TIMEOUT_SECONDS` | yes | integer; the adapter must honour it |
| `AGENT_DRY_RUN` | yes | `1` \| `0` |
| `SPEC_PIPELINE` | yes | `plugin` \| `fallback` (see §8) |
| `SPEC_PIPELINE_DIR` | yes | `tools/spec-pipeline` |

Nothing else. `run-agent.sh` explicitly unsets any inherited `ANTHROPIC_*`, `OPENAI_*`,
`GEMINI_*` or `*_API_KEY` before exec — the compatible-endpoint lesson generalised: if the
original credential survives into the subprocess it wins, and the "different family"
second opinion is silently the same model.

Every adapter begins with `set -euo pipefail` and `set +x`. A `set -x` anywhere in an
adapter prints `AGENT_AUTH_TOKEN` into a public Actions log; `tests/adapter-hygiene.bats`
greps for `set -x` and for any `echo` of `$AGENT_AUTH_TOKEN` and fails on either.

### 3.3 Adapter verbs

| Verb | Must do | Must not do |
|---|---|---|
| `print-argv` | print the argv it *would* run, ONE TOKEN PER LINE, to stdout; exit 0 | invoke anything; make a network call; print a token value |
| `run` | exec the CLI; propagate its exit status | print a token; write outside `AGENT_WORKDIR` |
| `status` | print `verified` or `unverified`; exit 0 | anything else |

`print-argv` substitutes the literal string `$AGENT_AUTH_TOKEN` wherever the token value
would appear. A dry-run printed into a pull-request log must not leak a credential, and
SC4 requires the dry-run to be usable exactly there.

### 3.4 `ADAPTER_STATUS` — one greppable line, one regex, two callers

Every file in `tools/providers/` carries, at column 0, before any logic:

```sh
ADAPTER_STATUS=verified                                   # verified | unverified — THE source of truth
ADAPTER_DOCS_URL=https://docs.example.invalid/cli/headless # where a maintainer confirms the flags
```

- Matched by exactly one regex, defined once in `tools/lib/config.sh`:
  `^ADAPTER_STATUS=(verified|unverified)$`
- `adapter_status()` in that library is the only implementation. `run-agent.sh
  --adapter-status` calls it. `init.sh` calls it. There is **no** lookup table anywhere.
- `tests/adapter-status.bats` asserts, for every `tools/providers/*.sh`: exactly one
  matching line, exactly one `ADAPTER_DOCS_URL=` line, and that
  `run-agent.sh --adapter-status <p>` agrees with `<p>.sh status`.
- Exit 3 if a provider's file is missing, or has zero or more than one matching line.
  Ambiguity here decides whether the steward ships live; it may not be resolved by
  "take the first match".

### 3.5 Exit codes OUT

| Code | Meaning | What the caller does |
|---|---|---|
| 0 | success | continue |
| 1 | the agent ran and reported failure | fail the job |
| 2 | usage error (unknown agent, missing prompt file, bad flag) | fail loudly |
| 3 | config error (unreadable/unsupported schema, unknown provider, ambiguous ADAPTER_STATUS) | fail loudly |
| 4 | adapter is an UNVERIFIED STUB and was asked to `run` | fail loudly; banner + docs URL already printed |
| 5 | a **required** credential is absent | fail loudly |
| 6 | an **optional** credential is absent (`auth.<p>.required: false`) | **degrade**: skip this reviewer, PR is not failed |
| 124 | timed out | fail loudly |
| 127 | provider CLI not found on `PATH` | fail loudly with the install hint |

Code 6 is the mechanism behind SC10. `run-agent.sh` emits the `::warning::` itself (one
place, one wording) and exits 6; the review workflow's gate step does:

```yaml
- id: gate
  run: |
    set +e
    tools/run-agent.sh --check-credentials challenger
    rc=$?
    set -e
    case "$rc" in
      0) echo "run=true"  >> "$GITHUB_OUTPUT" ;;
      6) echo "run=false" >> "$GITHUB_OUTPUT" ;;   # degrade, never cancel
      *) exit "$rc" ;;
    esac
```

and every subsequent step carries `if: steps.gate.outputs.run == 'true'`. The referee job
carries `if: ${{ !cancelled() && needs.challenge-review.outputs.ran == 'true' }}` —
`!cancelled()` and not `success()`, so a *failed* reviewer A still lets the referee report
what it has.

### 3.6 `--dry-run`, exactly

`--dry-run` is a **real smoke test**, not a no-op: every resolution error still exits 2 or 3.

1. Resolve config → schema → provider → adapter file → role → model → prompt file.
2. Print a fixed six-line header:
   `provider:`, `adapter-status:`, `role:`, `model:`, `prompt:`, `system-prompt:`.
3. Call the adapter's `print-argv`; print the tokens one per line, then one
   shell-quoted single-line form.
4. If `adapter_status` is `unverified`, additionally print:
   ```
   ================ UNVERIFIED STUB ================
   tools/providers/codex.sh has never been executed against a real CLI.
   The command shape above is a placeholder. Confirm the headless flag,
   the model flag and the tool-permission flag before enabling it:
     https://docs.example.invalid/cli/headless
   Running this adapter for real exits 4 on purpose.
   =================================================
   ```
5. Exit **0**, for verified and unverified alike — SC4 requires all four providers to
   print. `run` on an unverified adapter exits 4; `print-argv` never does.
6. Make no network call and invoke no CLI. `tests/run-agent-dryrun.bats` runs the four
   providers with `PATH` reduced to a directory containing only coreutils, proving no
   vendor binary is consulted.

---

## 4. Placeholder taxonomy

**Naming convention.** `{{UPPER_SNAKE_CASE}}` — ASCII letters, digits and underscore
only; no spaces; never nested; never split across lines; never inside a regex or a shell
expansion where a literal `{` is meaningful. One token = one adopter decision.

**Annotation convention (mechanically enforced).** Every placeholder occurrence must have,
on the same line or the line immediately above, an annotation:
`# placeholder: <one line saying what belongs there>` in YAML/shell,
`<!-- placeholder: ... -->` in Markdown, `<!-- placeholder: ... -->` in YAML comments
where a `#` would break parsing. `tools/gen-adopting.sh` **fails** if any distinct token
has no annotation anywhere in the tree. That turns the plan's "a one-line comment saying
what belongs there" from a habit into a check.

### 4.1 The classes

| Class | Resolver | Token examples | Files | If it is still there after `init.sh` |
|---|---|---|---|---|
| **P1 — interview** | `init.sh` asks, `init.sh` rewrites | `{{PRODUCT_NAME}}`, `{{PROVIDER}}`, `{{MODEL_JUDGE}}`, `{{MODEL_EXECUTE}}`, `{{MODEL_CHALLENGE}}`, `{{CHALLENGE_BASE_URL}}`, `{{ALERT_CHANNEL}}`, `{{RUNNER_LABEL}}`, `{{LEDGER_COMMIT_NAME}}`, `{{LEDGER_COMMIT_EMAIL}}`, `{{BUILD_PIPELINE}}` | `.agents/config.yml`, `AGENTS.md`, all runbooks, `README.md`, workflows | **BUG.** `check-placeholders.sh` exits non-zero and `init.sh` fails its own closing check |
| **P2 — derived** | `init.sh` computes; never asks | `{{REPO_SLUG}}` (from `git remote`), `{{DEFAULT_BRANCH}}` (from `git symbolic-ref`), `{{TEMPLATE_VERSION}}` (from `CHANGELOG.md`) | `branch-protection.md`, `README.md`, `agent-operator-guide.md` | **BUG**, and a different one: derivation failed. `init.sh` must SAY which derivation failed and why, not fall back to prompting |
| **P3 — deferred-manual** | **nobody**; converted by `init.sh` into a counted `TODO(adopter):` marker | none remain as `{{...}}` — see §4.3 | `.agents/prompts/*.md`, `agent-routines.md` | n/a by construction |
| **P4 — sentinel, outside the namespace** | `measure-floors.sh` | the literal token `unset` in `floors.yml` | `floors.yml` only | Not a placeholder. Deliberately not `{{...}}` so that `grep '{{'` returning zero is a TRUE statement about configuration, and an uncalibrated floor is still loudly visible on every run |
| **P5 — syntax documentation** | never | `{{PLACEHOLDER}}`, `{{HEALTH_SIGNAL}}` shown as examples | `ADOPTING.md`, `README.md`, `CONTRIBUTING.md`, `docs/runbooks/agent-routines.md` | Expected and allowed. This is the only permitted post-init `{{` |

### 4.2 The post-init check

`tools/check-placeholders.sh`:

```
grep -rn --binary-files=without-match -E '\{\{[A-Z][A-Z0-9_]*\}\}' <tracked files>
  minus the allowlist:  ADOPTING.md, README.md, CONTRIBUTING.md,
                        docs/runbooks/agent-routines.md
  → any hit is an error
```

The allowlist lives **in the script**, is four entries long, and each entry carries a
one-line comment saying why. It is not configurable, because a configurable allowlist is
how a genuine unresolved placeholder gets excused. `init.sh` runs this as its own last
step and refuses to print "done" if it fails. `tests/init-idempotent.bats` runs it too.

### 4.3 P3, and why it does not exist as a placeholder

plan.md and tasks.md put `{{HEALTH_SIGNAL}}` slots into `agent-routines.md` **and into the
per-agent prompts**. In a prompt body that is a live broken query: the agent runs, the
"metric" is a literal `{{HEALTH_SIGNAL_DISK}}`, and the run goes green having checked
nothing. That is the template's own named failure mode. It also makes SC7's "grep `{{`
returns zero outside ADOPTING.md" false.

**Design:** health signals move out of prose and into `.agents/health-signals.yml` with
`signals: []`. The prompt says "read `.agents/health-signals.yml`; if `signals` is empty,
report `no health signals configured` and finish green". `agent-routines.md` keeps
`{{HEALTH_SIGNAL}}` **only as documented example syntax in prose** (class P5), which is
what tasks.md Task 6's `grep -c '{{HEALTH_SIGNAL' > 0` check actually measures. Anywhere
else a P3 concept survives, `init.sh` rewrites it to
`TODO(adopter): <what to supply> — see ADOPTING.md §<n>` and reports the count.

### 4.4 ADOPTING.md is generated, and the generation is a gate

`tools/gen-adopting.sh`:
1. Scans tracked files for `\{\{[A-Z][A-Z0-9_]*\}\}`.
2. For each distinct token, collects every file it appears in and its annotation text.
3. Emits a table between `<!-- PLACEHOLDERS:BEGIN -->` and `<!-- PLACEHOLDERS:END -->`
   in `ADOPTING.md`: `| Token | Class | Files | What goes here | Resolved by |`.
4. Fails if any token has no annotation, or if a token appears in a file whose class
   contradicts its resolver (a P1 token in a prompt body, for instance).

The prose outside the markers is hand-written and preserved. CI job `fast-repo-hygiene`
runs `gen-adopting.sh && git diff --exit-code ADOPTING.md`. **A placeholder without a row
therefore cannot be merged** — which is the plan's named blast-radius item ("a placeholder
whose ADOPTING.md row is missing is invisible") closed mechanically rather than by
discipline.

---

## 5. `tests/harness-guards/pins.json`

### 5.1 Record schema

```json
{
  "schema": 1,
  "captured_at": "2026-08-05",
  "source_head": "<git rev-parse HEAD of the source repo at capture time>",
  "pins": [
    {
      "id": "review-marker-first-line",
      "source_file": ".github/workflows/claude-review.yml",
      "source_line": 470,
      "quoted_source_string": "the FIRST line of the comment you post must be exactly the HTML comment <!-- reviewer:",
      "why": "Every reviewer posts from the same bot account, so nothing downstream can tell two reviews apart by author. Selection is by an exact first-line marker; status chatter lands in the same window from the same account and otherwise gets mistaken for a review.",
      "expected_in": ".github/workflows/review.yml",
      "pin_kind": "literal"
    },
    {
      "id": "collector-slurps-before-filtering",
      "source_file": ".github/workflows/claude-review.yml",
      "source_line": 544,
      "quoted_source_string": "gh api --paginate --slurp",
      "pattern": "--paginate[[:space:]]+--slurp",
      "why": "--paginate with a per-item jq filter applies the filter once per page and emits one array per page, so \"take the last one\" silently returns one result per page. Slurp, flatten, then filter. Invisible until a thread passes 100 comments, which is exactly when the collector has to be right.",
      "expected_in": ".github/workflows/review.yml",
      "pin_kind": "regex"
    },
    {
      "id": "repo-standards-doc-paths",
      "source_file": ".github/workflows/claude-review.yml",
      "source_line": 470,
      "quoted_source_string": "Judge the diff against this repo's own standards: CLAUDE.md at the root, and .claude/reference/",
      "why": "The reviewer must be pointed at THIS repository's written standards, not at generic best practice. The paths themselves are project-specific and must change; what may not change is that a concrete, in-repo standards path is named at all.",
      "expected_in": ".github/workflows/review.yml",
      "pin_kind": "semantic-manual",
      "concept": "reviewer is anchored to in-repo standards documents",
      "replacement_must_preserve": "names AGENTS.md and docs/runbooks/ explicitly, by path",
      "discharged_in": null
    }
  ]
}
```

**Required fields, every entry:** `id` (kebab-case, unique), `source_file`, `source_line`
(integer > 0), `quoted_source_string` (verbatim from the source, before substitution),
`why` (the neutral lesson, ≥ 40 characters), `expected_in`, `pin_kind` ∈
`literal | regex | semantic-manual`.
**Additionally required for `regex`:** `pattern` (POSIX ERE).
**Additionally required for `semantic-manual`:** `concept`, `replacement_must_preserve`,
and `discharged_in` (null at capture time; filled by Task 10b with the replacement text
or a pointer into `.temper/evidence/extraction-diff.md`).

`why` is the test's own comment in the generated suite. A rule without its reason gets
deleted by the next person, and that deletion is precisely what gate 22 exists to catch —
so a `why` shorter than 40 characters fails schema validation.

### 5.2 How the bats suite consumes it, and why the count cannot drift

Three files, and the count is forced by construction rather than by discipline:

```
tests/harness-guards/
  pins.json                 the inventory (Task 6b, written BEFORE substitution)
  gen-pin-tests.sh          deterministic generator: pins.json -> pins.generated.bats
  pins.generated.bats       COMMITTED, reviewable in a diff, regenerated in CI
  pins-schema.bats          validates pins.json itself
  pin-count.bats            the count assertion + the semantic-manual roll call
```

1. **`gen-pin-tests.sh`** emits, for every `literal` and `regex` entry, exactly one
   `@test`, preceded by the entry's `why` verbatim as `#` comment lines:

   ```bash
   # WHY: Every reviewer posts from the same bot account, so nothing downstream can
   # WHY: tell two reviews apart by author. ...
   @test "pin[review-marker-first-line]: .github/workflows/review.yml" {
     run grep -F -q -- '<!-- reviewer:' "$REPO_ROOT/.github/workflows/review.yml"
     [ "$status" -eq 0 ] || fail "PIN LOST: review-marker-first-line
       source: .github/workflows/claude-review.yml:470
       why:    Every reviewer posts from the same bot account, ...
       Restore the string in .github/workflows/review.yml. Do NOT weaken the pin."
   }
   ```
   and, for every `semantic-manual` entry, one comment line plus a name in the roll call:
   ```bash
   # SEMANTIC-MANUAL (hand-discharged, not asserted): repo-standards-doc-paths
   #   concept: reviewer is anchored to in-repo standards documents
   #   discharged: .temper/evidence/extraction-diff.md#repo-standards-doc-paths
   ```

2. **`pins.generated.bats` is committed**, and `fast-repo-hygiene` runs
   `gen-pin-tests.sh && git diff --exit-code tests/harness-guards/pins.generated.bats`.
   Hand-editing the suite, or adding a pin without regenerating, fails CI. The suite
   cannot be smaller than the inventory because the suite is a pure function of it.

3. **`pin-count.bats`** is the belt to that braces, and it is what the intent scenario
   literally demands:
   ```bash
   @test "assertion count equals the literal/regex entry count" {
     expected=$(jq '[.pins[] | select(.pin_kind=="literal" or .pin_kind=="regex")] | length' pins.json)
     actual=$(grep -c '^@test "pin\[' pins.generated.bats)
     [ "$expected" -eq "$actual" ]
   }
   @test "every semantic-manual entry is named as hand-discharged" {
     # prints each one to the suite's OUTPUT, so an unpinnable lesson is never
     # mistaken for an omitted one
     jq -r '.pins[] | select(.pin_kind=="semantic-manual") | "HAND-DISCHARGED: \(.id) — \(.concept)"' pins.json
     expected=$(jq '[.pins[] | select(.pin_kind=="semantic-manual")] | length' pins.json)
     actual=$(grep -c '^# SEMANTIC-MANUAL' pins.generated.bats)
     [ "$expected" -eq "$actual" ]
     # and none may still be undischarged by the time PR (a) closes
     [ "$(jq '[.pins[] | select(.pin_kind=="semantic-manual" and .discharged_in==null)] | length' pins.json)" -eq 0 ]
   }
   @test "every expected_in file exists" { ... }   # a pin pointing at a deleted file FAILS, not vanishes
   ```

4. **`pins-schema.bats`** enforces the record schema above, plus `entry count >= 25`
   (tasks.md Task 6b) and unique `id`s.

5. **Verification that the guards work.** Task 20's exit criterion is a captured
   transcript: for a sample of at least five pins across both workflows, delete the pinned
   string, run the suite, record it red, restore. A guard never seen red is a guard not
   known to work.

---

## 6. The FAST / FULL tier split, as concrete jobs

### 6.1 The naming rule that makes context strings safe

> **Every gate job's `name:` is character-identical to its job id.**

A GitHub Actions required-check context is the job's `name:` when it has one and the job
id otherwise. The source repo got bitten by exactly this: its gitleaks job has id
`gitleaks` and `name: Scan for secrets with gitleaks`, so the branch-protection context is
the sentence, and its own runbook calls that "the usual failure mode: GitHub accepts a
context that never reports, and then every PR blocks forever waiting on it."

Making `name == id` means there is **one** string per gate, it is greppable, and it cannot
be got wrong by reading the wrong field. `tests/harness-guards/` pins this rule with an
assertion over every workflow: for each job under `jobs:`, either no `name:` key, or a
`name:` whose value equals the job id.

The names below are **frozen at v0.1.0** and are the published contract. Renaming one
after release breaks branch protection in every downstream adopter, silently — the PR
simply waits forever on a context that will never report again.

### 6.2 FAST tier — 7 required contexts, safe to require on day one

| Context string | Workflow | Job-level `if:` | Gates covered | Cost |
|---|---|---|---|---|
| `fast-unit-tests` | `pr-tests.yml` | `needs.changes.outputs.backend == 'true'` | 1 unit, 3 backend coverage ratchet, 4 arch rules + freeze store, 8 acceptance specs, 9 (backend guard), 13 build hygiene | JDK + Maven resolve, ~90 s |
| `fast-frontend-checks` | `pr-tests.yml` | `needs.changes.outputs.frontend == 'true'` | 6 lint zero-warnings, 7 frontend tests + coverage ratchet, 9 (frontend guard), 12 fast CVE, 14 design-system guardrail | `npm ci` + vitest, ~60 s |
| `fast-harness-guards` | `pr-tests.yml` | **none** — runs on every PR | 22 | bats over text, ~3 s |
| `fast-repo-hygiene` | `pr-tests.yml` | **none** | placeholder check, ADOPTING sync, `floors.yml` ↔ tool-config consistency (part of 9), de-identification sweep when a term file exists | ~5 s |
| `fast-actionlint` | `actionlint.yml` | **none** | SC8 | ~10 s |
| `fast-secret-scan` | `secret-scan.yml` | **none** | 11 | ~15 s |
| `fast-spec-artifacts` | `spec-artifacts.yml` | **none** | 21 | ~5 s |

No Testcontainers, no browser download, no service container. Total ≈ 2 minutes on a cold
cache, dominated by dependency resolution.

`changes` (job id, no `name:`, in `pr-tests.yml`) is the `dorny/paths-filter` job. It is
**not** a required context — it is plumbing, and every job that depends on it reports in
its own right.

`fast-harness-guards`, `fast-repo-hygiene` and `fast-spec-artifacts` deliberately carry
**no** `needs: changes` gate. Decision 5's reasoning generalises: a docs-only or spec-only
PR skips the stack jobs, and these three are exactly the checks that matter most on that
class of PR. A required check that skips reports "passing".

### 6.3 FULL tier — 5 contexts, live and reporting from day one, required in one step

| Context string | Workflow | Job-level `if:` | Gates | Why it is not day-one required |
|---|---|---|---|---|
| `full-integration-tests` | `pr-tests.yml` | `needs.changes.outputs.backend == 'true'` | 2 | pulls a Postgres image |
| `full-migration-validation` | `pr-validation.yml` | `needs.changes.outputs.migrations == 'true'` | 10 | pulls a Postgres image |
| `full-mutation-on-diff` | `pr-mutation.yml` | `needs.scope.outputs.backend_main == 'true'` | 17 | PIT, minutes not seconds |
| `full-e2e-accessibility` | `pr-tests.yml` | `needs.changes.outputs.frontend == 'true'` | 15 (PR appearance; the nightly run stays) | downloads a Playwright browser |
| `full-bundle-budget` | `pr-tests.yml` | `needs.changes.outputs.frontend == 'true'` | 19 | needs `npm run build`; see §9.4 |

Promotion is one documented command in `docs/runbooks/branch-protection.md`, a `PUT` with
the union of both lists, and it is listed in the README's setup order immediately before
branch protection itself. `QUALITY-GATES.md` states the one-week expectation and keeps
every gate's "what a failure means" row unchanged, so the tier split cannot quietly
become a parking space.

### 6.4 Nightly contexts — never required, and why

`nightly.yml`: `nightly-mutation-backend`, `nightly-mutation-frontend`,
`nightly-e2e-accessibility`, `nightly-dependency-scan`, `nightly-api-contract`,
`nightly-flaky-detection`, plus one notifier job **per gate** (`notify-mutation-backend`,
…). They do not run on pull requests at all, so a required nightly context would block
every PR forever. `branch-protection.md` says so in the same words.

Each notifier call passes its own `gate:` input. See §9.6 — a single OR-ing
`notify-failure` job would collapse five distinct `[nightly] <gate> is failing` issues
into one.

### 6.5 Branch protection, verbatim

```
FAST (mark required immediately):
  fast-unit-tests
  fast-frontend-checks
  fast-harness-guards
  fast-repo-hygiene
  fast-actionlint
  fast-secret-scan
  fast-spec-artifacts

FULL (add within the first week, after watching them pass once):
  full-integration-tests
  full-migration-validation
  full-mutation-on-diff
  full-e2e-accessibility
  full-bundle-budget

NEVER required:
  changes, and every nightly-* / notify-* context
```

---

## 7. The floor sentinel — one ledger, four different encodings

### 7.1 `floors.yml` is the single ratchet ledger

Every floor's authoritative value lives in exactly one file at the repo root. The tool
configs are **rendered** from it.

```yaml
# The ratchet ledger. `unset` means NOT YET CALIBRATED. It is not zero and it is not
# "switched off". tools/measure-floors.sh replaces these against YOUR product; gate 9
# fails any pull request that lowers one.
schema: 1
floors:
  backend.coverage.line:        { value: unset, direction: up,   tool: jacoco }
  backend.coverage.branch:      { value: unset, direction: up,   tool: jacoco }
  backend.mutation.score:       { value: unset, direction: up,   tool: pit }
  frontend.coverage.statements: { value: unset, direction: up,   tool: vitest }
  frontend.coverage.branches:   { value: unset, direction: up,   tool: vitest }
  frontend.coverage.functions:  { value: unset, direction: up,   tool: vitest }
  frontend.coverage.lines:      { value: unset, direction: up,   tool: vitest }
  frontend.mutation.score:      { value: unset, direction: up,   tool: stryker }
  frontend.bundle.total_kib:    { value: unset, direction: down, tool: bundle-check }
```

Once calibrated, each entry gains the provenance the ratchet policy's "the measuring
instrument changed" exemption is unusable without:

```yaml
  backend.coverage.line:
    value: 0.87
    direction: up
    tool: jacoco
    measured: 0.8812
    on: 2026-09-02
    by: "jacoco-maven-plugin 0.8.13 / mvn 3.9.9 / temurin-24"
```

**Why a ledger rather than the tool configs alone:** for two of the four tools, the
uncalibrated encoding is textually identical to a deliberately-disabled gate (PIT's
`0`, Stryker's `null`). No amount of comment discipline inside those files distinguishes
the two states to a machine. `floors.yml` is the discriminator, and gate 9 reads it.

### 7.2 What `unset` looks like in each tool — this differs per tool, and that is the point

**1. JaCoCo (`backend/pom.xml`).** `jacoco:check` has no "no threshold" mode: `<minimum>`
must be a decimal. So the uncalibrated encoding is to skip the check execution.

```xml
<execution>
  <id>coverage-ratchet</id>
  <goals><goal>check</goal></goals>
  <configuration>
    <!-- FLOORS:BEGIN backend.coverage.line backend.coverage.branch -->
    <!-- floors.yml says `unset`. jacoco:check cannot express "no threshold" —
         a <minimum> must be a decimal — so the check is skipped and
         tools/floor-notice.sh prints the uncalibrated notice instead.
         This <skip> is indistinguishable from a disabled gate BY DESIGN of the
         tool; floors.yml is what tells the two apart, and gate 9 reads it. -->
    <skip>true</skip>
    <!-- FLOORS:END -->
  </configuration>
</execution>
```
Calibrated, the same block becomes `<skip>false</skip>` plus `<rules><rule>
<element>BUNDLE</element><limits>` with `LINE`/`COVEREDRATIO`/`<minimum>0.87</minimum>`
and `BRANCH`/`COVEREDRATIO`/`<minimum>0.79</minimum>`, each carrying the measured value,
date and tool version as an XML comment.

**2. PIT (`backend/pom.xml` property).**
```xml
<!-- FLOORS:BEGIN backend.mutation.score -->
<!-- floors.yml says `unset`. PIT's documented "no threshold" IS 0 — which is also
     exactly what a switched-off gate looks like. That collision is the reason the
     sentinel cannot live in this file. -->
<pit.mutationThreshold>0</pit.mutationThreshold>
<!-- FLOORS:END -->
```
Calibrated: `<pit.mutationThreshold>86</pit.mutationThreshold>` (PIT takes an integer
percentage, not a ratio — a per-tool unit difference `render-floors.sh` owns).

**3. vitest (`frontend/vitest.config.js`).** vitest enforces nothing when `thresholds`
is empty, and that is a legitimate first-class state.
```js
      // FLOORS:BEGIN frontend.coverage.*
      // floors.yml says `unset` — no thresholds enforced yet. An empty object is
      // vitest's own "measure but do not gate"; run tools/measure-floors.sh to arm it.
      thresholds: {},
      // FLOORS:END
```
Calibrated: `{ statements: 91, branches: 84, functions: 93, lines: 92 }` (integer
percentages) with the measured/date/tool comment block above them.

**4. Stryker (`frontend/stryker.config.mjs`).** Stryker's documented "never break the
build" is `break: null`; `high` and `low` are reporting colours, not gates, and ship as
constants.
```js
  // FLOORS:BEGIN frontend.mutation.score
  // `break: null` is Stryker's documented "do not fail the build". floors.yml says
  // `unset`; when calibrated this becomes an integer and only ever moves up.
  thresholds: { high: 95, low: 85, break: null },
  // FLOORS:END
```

**5. Bundle ceiling (`frontend/scripts/check-bundle.mjs`).** This is our own script, so
it reads `floors.yml` directly — no rendering. On `unset` it prints the measured gzipped
total, prints the uncalibrated notice, and exits 0. It is the only one of the five that
needs no marked block, and the asymmetry is documented in `QUALITY-GATES.md`.

### 7.3 How the gate PASSES and PRINTS

`tools/floor-notice.sh <scope>` runs as an `if: always()` step in every ratchet-bearing
job, before the tool step, and always exits 0:

```
::notice title=Floor not calibrated::backend.coverage.line: floor not yet calibrated — run tools/measure-floors.sh against your product
```

plus a table appended to `$GITHUB_STEP_SUMMARY` listing every uncalibrated floor. The
exact sentence

> `floor not yet calibrated — run tools/measure-floors.sh against your product`

is required verbatim by the intent scenario and is pinned by `tests/floors-sentinel.bats`
so a reword cannot slip through. The notice lives in the **workflow job**, not inside four
different build tools, because only three of the five tools can be made to print anything
in their skipped state at all.

### 7.4 `tools/measure-floors.sh` — explicitly online, explicitly slow

The opposite contract to `init.sh`, and the README says so in those words.

1. **Refuse if `examples/` exists.** Exit 4:
   `examples/ is still present. Floors measured against the bundled example are floors calibrated to a toy service you were invited to delete. Remove or move examples/ first.`
   There is no `--anyway` flag; the guard is the whole mechanism behind SC12b.
2. **Refuse if the working tree is dirty**, so the rewrite lands as its own reviewable diff.
3. Measure, per tool: `mvn clean verify -DskipITs` → `target/site/jacoco/jacoco.csv`;
   `mvn -Pmutation …` → PIT's `mutations.xml`; `npm ci && npx vitest run --coverage` →
   `coverage/coverage-summary.json`; `npx stryker run` → `reports/mutation/mutation.json`;
   `npm run build` → gzipped `dist/assets/*` total.
4. **Write `floors.yml`.** For `direction: up`, `value = floor(measured) - 1` percentage
   point of margin — enough that one uncovered defensive branch does not trip the gate
   while a genuinely untested feature does. For `direction: down` (the bundle ceiling),
   `value = ceil(measured * 1.10)`. Record `measured`, `on`, `by`.
5. **Render.** Call `tools/render-floors.sh`, which rewrites every `FLOORS:BEGIN…END`
   block. It is idempotent and unit-agnostic per tool (ratio for JaCoCo, integer percent
   for PIT/vitest/Stryker, KiB for the bundle).
6. **Ratchet enforcement on re-runs.** If a floor already holds a number,
   `measure-floors.sh` refuses to lower it without `--rebaseline "<reason>"`, and writes
   `rebaselined: { on: <date>, reason: "<reason>" }` into the entry. The only two honest
   reasons are named in the refusal message: the measuring instrument changed, or the
   scope got wider.
7. Print a summary and the next step: commit this, and gate 9 now fails any PR that
   lowers one.

### 7.5 Gate 9 closes the hand-edit hole

`fast-repo-hygiene` runs `tools/render-floors.sh && git diff --exit-code` over the four
tool configs. Hand-editing a `<minimum>` in the pom without touching `floors.yml` fails
there. The stack-native ratchet guard tests (the source's `ratchetGuard.test.js` idiom,
extracted) additionally assert that each tool config's value equals `floor_get`'s value,
so the check survives even if someone deletes the hygiene job.

---

## 8. `tools/spec-pipeline/` — the artifact contract

Gate 21 checks **artifacts**, never a plugin. That is what makes it enforceable on a fork
running any vendor's CLI.

### 8.1 The contract (normative; lives at `tools/spec-pipeline/CONTRACT.md`)

```
.temper/specs/<slug>/intent.md      REQUIRED  problem, success criteria, BDD scenarios
.temper/specs/<slug>/plan.md        REQUIRED  approach decisions, files, blast radius
.temper/specs/<slug>/tasks.md       REQUIRED  ordered tasks, each with a validate line
.temper/specs/<slug>/design.md      OPTIONAL  complex features only
.temper/specs/<slug>/gates.json     REQUIRED  the gate ledger for this spec
.temper/build-state.json            OPTIONAL  repo-global pointer at the active spec
```

`gates.json`, per spec:
```json
{ "spec_contract": 1,
  "stages": { "plan":  { "verdict": "PASS", "ts": "…", "requirements": [ {"name":"…","pass":true,"detail":"…"} ] },
              "build": { "verdict": "PASS_WITH_WARNINGS", "ts": "…", "requirements": [ … ] } } }
```
`verdict` ∈ `PASS | PASS_WITH_WARNINGS | FAIL`.

### 8.2 Directory

```
tools/spec-pipeline/
  CONTRACT.md          the normative document above; versioned by spec_contract
  new-spec.sh <slug>   creates the directory from templates/, seeds gates.json
  record-gate.sh       <stage> <verdict> [name=pass:detail]... ; appends, never rewrites
  validate.sh          THE check — exit 0/1, used by CI and locally, one implementation
  templates/{intent,plan,tasks,design}.md
```

### 8.3 Gate 21's algorithm — `spec-artifacts.yml` calls `validate.sh`, nothing else

The workflow job is a checkout, a `git diff --name-only "$BASE"..."$HEAD"` into a file,
and `tools/spec-pipeline/validate.sh --pr-body-file … --changed-files …`. The CI check
and the local pre-flight are **the same code**; two implementations is how the plugin path
and the fallback path drift until gate 21 becomes plugin-shaped after all.

In precedence order:

1. If the PR carries none of the labels in `vars.SPEC_REQUIRED_LABELS` (default
   `fix,feature`) → exit 0 with a note. Not a skip: the check reports success.
2. If the PR body contains a line matching
   `^temper: unavailable[[:space:]]*[—–-][[:space:]]*(.+)$` with a captured reason of
   ≥ 10 characters that is not in the non-reason list (`n/a`, `none`, `-`, `tbd`) →
   **exit 0** and emit `::warning title=Spec pipeline declared unavailable::<reason>`.
3. Otherwise the **changed-file list** must contain `intent.md`, `plan.md`, `tasks.md`
   and `gates.json` under one and the same `.temper/specs/<slug>/`. The diff, not the
   tree — a spec directory that was already on main proves nothing about this change.
4. `gates.json` must parse, carry `spec_contract: 1`, and contain at least one stage
   whose `verdict` is `PASS` or `PASS_WITH_WARNINGS`. A committed `FAIL` fails gate 21;
   you may not ship a red gate ledger and call the discipline satisfied.
5. On failure, print **both** accepted remedies verbatim:
   ```
   FAIL: this pull request is labelled 'fix' and carries no spec artifacts.
   Two remedies, both accepted:
     1. Commit the spec directory:  .temper/specs/<slug>/{intent,plan,tasks}.md + gates.json
        Create one with: tools/spec-pipeline/new-spec.sh <slug>
     2. If the pipeline is genuinely unreachable, put this line in the PR body:
          temper: unavailable — <the real reason>
        The reason is recorded as a warning annotation. "Availability is a finding,
        not an excuse": say what was unreachable and why.
   ```

### 8.4 How an adapter chooses plugin vs fallback

`run-agent.sh` sets `SPEC_PIPELINE` before exec:
- `claude-code.sh` probes for the build plugin (`--adapter-probe spec-pipeline`, offline)
  and reports `plugin` or `fallback`.
- `compatible-endpoint.sh`, `codex.sh`, `gemini-cli.sh` report `fallback` unconditionally
  until a maintainer verifies otherwise.

The **prompts and the headless playbook never name a plugin.** They say: "build every fix
and feature through the spec pipeline; its contract is
`tools/spec-pipeline/CONTRACT.md`; if `SPEC_PIPELINE=fallback`, drive
`tools/spec-pipeline/` directly." That is how SC9 (no vendor name in any prompt, workflow
or runbook) survives contact with a Claude-Code-only plugin.

---

## 9. What I found that contradicts the plan

Reported plainly rather than designed around silently, per the brief.

### 9.1 intent.md's Constraints bullet still says ONE working adapter — it must say two

`intent.md` line 122: *"**One working adapter (Claude Code); three clearly-marked stubs**
(Codex, Gemini CLI, compatible-endpoint)."* This directly contradicts plan.md Decision 3,
plan.md's "Third-party facts deliberately NOT invented" section, tasks.md Task 16, and
SC10's degradation scenario — all of which ship `compatible-endpoint` **verified**.
`tasks.md` is itself inconsistent: Task 22's validate line says *"three of four adapters
are unverified stubs"* while Task 33 says *"two of four"*.

**This is the single most consequential contradiction in the spec set**, because a Build
agent reading intent.md's Constraints as binding would ship the `challenge` role with no
delivery path — reviewer B never runs for anyone, SC10's degradation branch becomes the
permanent normal state, and the `challenger` scheduled agent has no execution path at all.
Plan Decision 3 already argues this at length.

**Fix before Build:** intent.md line 122–125 → two working (claude-code,
compatible-endpoint), two stubs (codex, gemini-cli); tasks.md Task 22's validate line →
"two of four". This design assumes the corrected version.

### 9.2 `pr-validation.yml` / `pr-mutation.yml` cannot both keep a workflow-level `paths:` filter and be promotable

plan.md's Architectural-compliance block says `pr-validation.yml` ships **with** its
workflow-level `paths:` filter plus a comment explaining why that is safe. Decision 10 and
the SC12c scenario require `branch-protection.md` to list the FULL tier's exact context
strings as requireable in one documented step. A check behind a workflow-level `paths:`
filter can never be required — that is the lesson the extracted runbook exists to teach.

**Resolution:** the template moves both filters down to a `changes`-fed job-level `if:`,
which is precisely the conversion the source's own `branch-protection.md` prescribes
("To make them requireable, move the filter from the workflow's `on.pull_request.paths`
down to a job-level `if:` fed by `dorny/paths-filter`, exactly as `pr-tests.yml` already
does"). The incident comment survives, rewritten as a lesson: *upstream this filter sat at
workflow level, which is why these two checks could never be required; here it is at job
level so that they can be.* That is extraction of the lesson, not of the defect.

### 9.3 "Job names frozen at extraction time" collides with Task 23b's tier split

plan.md's blast radius says job names are frozen at extraction time. Task 23b then splits
FAST/FULL, which necessarily changes the job set (the source has one `unit-tests` job
carrying both fast and slow frontend work).

**Resolution:** "frozen" means **frozen at v0.1.0**, not "identical to the source". Nothing
is published until then, so a rename inside PR (a)→(c) costs nothing. But the final names
must be fixed **once**, in Task 9, so that Task 23b is documentation-only. Concretely:
**do the FAST/FULL job split in Task 9, and reduce Task 23b to writing the tier tables in
`QUALITY-GATES.md` and `branch-protection.md`.** Otherwise Task 23b renames the very
contexts Task 9 called frozen.

### 9.4 The bundle budget in the FULL tier costs a second `npm ci`

Task 23b puts the bundle budget in FULL and frontend lint/tests in FAST. In the source
they are steps in one job because they share `npm ci` and `npm run build`. Split across
jobs, `full-bundle-budget` must `npm ci` again (~40 s) and build again.

**Recommendation (honours intent literally):** `fast-frontend-checks` uploads `dist/` as an
artifact after its build; `full-bundle-budget` downloads it and runs the 0.2 s zlib check.
**Cheaper alternative, if the Build agent prefers:** keep the bundle budget in
`fast-frontend-checks` — it needs no container and no browser, and the whole cost is one
`npm run build`. That would move one gate from the FULL list, which contradicts the SC12c
scenario text as written. Flagging rather than choosing; the artifact hand-off is designed
above.

### 9.5 `agentsdlcrepoprompt.md` still says `init.sh` measures the floors

Prompt lines 499–506: *"coverage/mutation floors START at the adopter's measured baseline
— init measures and writes them."* Decision 7 deliberately overrides this and the intent's
SC12/SC12b encode the override. Since tasks.md tells the Build agent to treat the prompt
as the acceptance checklist, **the design records the override explicitly** so it is not
re-introduced: `init.sh` measures nothing, makes no network call, and writes the `unset`
sentinel; `measure-floors.sh` is the online step. Same for the prompt's "three stubs"
phrasing, superseded by §9.1.

### 9.6 Consolidating five nightly workflows into one collapses five alert issues into one

Task 10 consolidates `mutation-tests`, `e2e-tests`, `security-scan`,
`live-api-contract-tests` and `flaky-test-detection` into a single `nightly.yml`. The
source has one `notify-failure` job per workflow, each passing its own `gate:` input to
the reusable notifier, which opens or updates the `[nightly] <gate> is failing` issue.

A single consolidated `notify-failure` that ORs five job results would file **one** issue
for five different gates, and a second gate going red while the first is still open would
be invisible — the exact failure the notifier was built to end.

**Resolution:** `nightly.yml` carries **one notifier job per gate**, each
`if: failure() && needs.<gate>.result == 'failure'`, each with its own `gate:`,
`what_red_means:` and `runbook:` inputs. The workflow-level
`permissions: {contents: read, issues: write}` block and its startup-failure postmortem
comment are declared once and cover all five callers.

### 9.7 `ledger.sh` becomes config-driven but runs inside a throwaway clone

Task 2 makes the hard-coded `AGENTS="ops quality growth …"` list config-driven. The
extracted `cmd_append` clones the **remote** into a temp dir (correctly — cloning the local
checkout makes the push land on a local ref and report success while nothing reaches the
server). The ledger orphan branch does not contain `.agents/config.yml`.

**Resolution:** `ledger.sh` resolves the agent list from the **caller's** checkout, before
the clone, and passes it in as a shell variable. `AGENTS_CONFIG` may be overridden by env
for the scratch-repo round-trip test. Small, but it is exactly the kind of thing that
works in the round-trip transcript and fails on a runner.

### 9.8 `.temper/gates.json` as a repo-global file conflicts on every PR

The current temper layout puts `gates.json` at `.temper/gates.json`, repo-global. Two
concurrent feature branches both rewrite it, so every second PR carries a merge conflict
in a file gate 21 requires in the diff.

**Resolution (adopted in §8.1):** the fallback pipeline writes `gates.json` **per spec**,
at `.temper/specs/<slug>/gates.json`. `validate.sh` accepts either location, preferring
the per-spec one, so a repo driving the Claude-Code plugin's global file still passes.

---

## 10. Decision Log

| # | Decision | Options considered | Chosen | Rationale |
|---|---|---|---|---|
| D1 | Who parses the config | each tool parses its own YAML; require `yq`; one shared library | **`tools/lib/config.sh`, the only parser, `yq` when present + a tested awk fallback** | The config is read by 8+ consumers in a stranger's repo. One parser means a schema bump lands in one place; a `yq` hard requirement breaks SC4's "works with no CLI installed" and SC7's offline guarantee |
| D2 | Config versioning | semver string; date; integer counter | **`schema:` integer, bumped only on breaking change; additive optional keys do not bump** | Consumers need an equality test, not a range comparison. Additive keys are the common case and must not force a migration on every adopter |
| D3 | Ring order representation | explicit `predecessor:` per agent; a separate ring table; list order | **list order, wrapping** | A second list is a second source of truth. `cfg_predecessor` derives it, so reordering the agents reorders the ring by construction |
| D4 | `ADAPTER_STATUS` discovery | lookup table in `init.sh`; adapter exports a function; a greppable assignment line | **one column-0 assignment line, one regex, one library function, two callers** | Decision 8's requirement. The moment someone finishes an adapter, a second list is stale — and it is stale in a direction that ships a live workflow calling a broken CLI |
| D5 | Adapter reads config? | adapters read `config.yml`; `run-agent.sh` passes env | **env-var contract only; adapters never parse config** | Four adapters × one schema change = four breakages. Also makes `print-argv` trivially testable with a fabricated environment |
| D6 | Degradation signalling | adapter returns 0 and prints a warning; a sentinel file; a distinct exit code | **exit 6, plus `--check-credentials`** | SC10 needs "degrade, never cancel, never fail". A distinct code lets the caller branch without parsing text, and `--check-credentials` lets the gate step run before any billable invocation |
| D7 | Token in `--dry-run` output | print resolved argv verbatim; redact with `***`; print the env-var reference | **print the literal `$AGENT_AUTH_TOKEN`** | SC4 wants "the exact command". Guardrail 5 forbids a secret in a log. The env-var reference is both: it is copy-pasteable and it is not the value |
| D8 | Placeholders init cannot resolve | leave `{{HEALTH_SIGNAL}}` in prompts; a second token syntax; move to a config file with an empty list | **`.agents/health-signals.yml` with `signals: []`** | An unresolved placeholder inside a live query is a green run that checked nothing. An empty list is a legible, safe, documented state, and it makes SC7's zero-`{{` check true |
| D9 | ADOPTING.md upkeep | hand-maintained; generated once; generated + diff-gated in CI | **generated between markers, `git diff --exit-code` in `fast-repo-hygiene`** | The plan names "a placeholder whose ADOPTING.md row is missing" as invisible-by-construction. Only a gate makes it visible |
| D10 | Gate-22 suite ↔ `pins.json` linkage | hand-written tests + a count assertion; a runtime loop; a committed generated suite | **committed generated suite + regeneration diff gate + an independent count assertion** | A runtime loop hides the `why` text from the diff, which is where the lesson has to be readable. A committed generated file is reviewable AND cannot drift |
| D11 | Where the floor sentinel lives | in each tool config; a shared `floors.yml`; both | **`floors.yml` authoritative, tool configs rendered from it** | Two of four tools encode "no threshold" identically to "disabled" (PIT `0`, Stryker `null`). No comment discipline fixes that for a machine; a ledger does, in one place, for all four |
| D12 | Who prints "floor not yet calibrated" | each build tool; the ratchet guard test; the workflow job | **`tools/floor-notice.sh` as an `if: always()` workflow step** | Only three of five tools can be made to print anything in their skipped state. The gate is the job, so the job prints |
| D13 | Context-string safety | keep source names; prefix with the workflow name; make `name:` identical to the job id | **`name:` == job id, pinned by a harness guard** | The source's own runbook names a mismatched `name:`/id as "the usual failure mode". One string per gate is one string to get wrong |
| D14 | Where gate 21's logic lives | inline in the workflow; a bats-tested script called by the workflow | **`tools/spec-pipeline/validate.sh`, called by CI and locally** | Two implementations drift, and gate 21's whole premise is that the contract is the artifacts and not the tool that produced them |
| D15 | Nightly notifier granularity | one OR-ing `notify-failure`; one per gate | **one per gate** | Five gates sharing one issue means the second failure is invisible while the first is open — see §9.6 |

---

## 11. Security Considerations

Sensitivity remains LOW (no product code, no auth path, no data access), with four
design-level controls:

1. **No secret value ever crosses into printable output.** `--dry-run` prints
   `$AGENT_AUTH_TOKEN`, never its value (D7). `tests/adapter-hygiene.bats` fails on any
   `set -x` in an adapter and on any `echo`/`printf` of the token variable.
2. **Credential isolation for the compatible endpoint.** `run-agent.sh` unsets every
   inherited `*_API_KEY` / `*_AUTH_TOKEN` / `*_BASE_URL` before exec. The extracted lesson
   is that if the original credential survives into the subprocess it wins, and the
   "different family" second opinion is silently the same model — the check appears to run
   and proves nothing.
3. **The supply-chain carve-out survives genericization.** `review.yml`'s special handling
   of pull requests that edit workflow files is a deliberate security control; it is a
   `semantic-manual` pin in `pins.json` with an explicit `replacement_must_preserve`, so it
   cannot be dropped as project-specific noise without a recorded, hand-walked decision.
4. **The de-identification term list never enters the tree.** `check-deidentified.sh`
   takes `--terms <file>` and names nothing itself; the real terms live gitignored in
   `.temper/evidence/`. The scanner is subject to its own sweep with no self-exclusion —
   a check that must exempt itself to pass is not a check.

Secret surface: 4 names in the shipped tree (`AGENT_CLI_TOKEN`, `CHALLENGE_API_KEY`,
`ALERT_WEBHOOK_URL`, `STEWARD_HANDOFF_PAT`), each with a README row naming what breaks
when it is absent. `CHALLENGE_API_KEY` and `ALERT_WEBHOOK_URL` are optional by design and
degrade; `STEWARD_HANDOFF_PAT` absent means the review workflow still files the handoff
issue and says loudly that the handoff did not happen.

---

## 12. Performance Considerations

| Path | Budget | How it is held |
|---|---|---|
| FAST tier, cold cache | ≈ 2 min | no service container, no browser download, no mutation run; the only network is dependency resolution |
| `tools/init.sh` | seconds | zero network calls; zero measurement; pure text substitution over a bounded file list |
| `run-agent.sh --dry-run` | < 200 ms | no CLI invocation; config read once; adapter runs `print-argv` only |
| `tools/lib/config.sh` awk fallback | < 50 ms per file | the config is < 150 lines and the reader is single-pass; results memoised per process |
| Gate 22 suite | < 5 s | `grep -F`/`grep -E` over ~1,100 lines of YAML; no checkout of anything |
| `measure-floors.sh` | minutes, deliberately | the explicit counterweight to init.sh; the README says "explicitly online, explicitly slow" in those words |
| `nightly.yml` | unbounded | never required, never blocks a merge; each gate has its own notifier |

The one cost this design *adds* over the plan is the FULL-tier `npm ci` for
`full-bundle-budget` (§9.4), mitigated by a `dist/` artifact hand-off.

---

## 13. ADRs

The design methodology asks for `docs/decisions/NNNN-*.md` for architectural decisions.
Not written here: the brief forbids creating files outside
`.temper/specs/agent-sdlc-template/`, and `docs/decisions/` would be a shipped template
artifact rather than a spec artifact.

Four decisions above are ADR-grade and should be emitted during Build, in PR (b):

- `0001-single-config-parser-and-schema-versioning` (D1, D2)
- `0002-adapter-env-var-contract-and-exit-codes` (D5, D6)
- `0003-floors-yml-as-the-single-ratchet-ledger` (D11, D12)
- `0004-context-string-equals-job-id` (D13)
