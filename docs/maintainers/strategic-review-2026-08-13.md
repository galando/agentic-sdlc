# Strategic review — 2026-08-13

Scope: the whole template, reviewed against four goals — best-in-class agentic SDLC,
adoptable for new **and existing** projects, fundamentals graspable by anyone, and
adaptable inside a locked-down corporation (Claude only via AWS Bedrock, GitLab as the
forge, egress proxy, security review board).

Method: two deep survey passes (doctrine/docs and harness/workflows), then a nine-agent
workflow — four adversarial fact-checkers over twenty load-bearing claims (**19
confirmed, 1 partial**), four independent strategy lenses, one completeness critic —
integrated by hand. Every file:line below was verified against the tree at `aaafad9`.

---

## 1. The verdict

**The doctrine is world-class and the execution of it is real.** This is the only
project in the agentic-SDLC space whose safety and process claims are enforced by tests
rather than asserted in prose — 128 pinned lessons, a suite that tests *the machine that
builds the software*, and a memory architecture whose tiers are separated by write
permission instead of trust.

**Three things stand between it and "best in the world," all structural, none
conceptual:**

1. **It only runs where it was born** — GitHub + Anthropic subscription + open egress.
   Zero Bedrock support, a challenge adapter that strips proxy variables, 4,346 lines of
   forge-locked YAML.
2. **It only adopts greenfield** — template instantiation, no path into an existing
   repository, and a manual tail of PATs and admin toggles behind the two-click claim.
3. **It doesn't yet run itself** — all ten agents ship disabled while six documented
   drift bugs sit in the tree that the fleet exists to catch.

Every blocker lands in a seam the architecture already provides (the adapter contract,
the config schema's bump policy, the pin re-homing mechanism) — the strongest evidence
the original design was right.

## 2. The seven ideas worth stealing

The transferable doctrine, currently scattered across 3,000+ lines of runbooks. Each
deserves a section in a root-level `THE-SEVEN-IDEAS.md` with (a) the idea in one
sentence, (b) the incident that taught it, (c) where it is implemented, (d) "how to
steal just this one" for repos not adopting the template.

1. **Branch protection as epistemics.** "Instruction or old agent chatter?" is answered
   by write permission, not naming convention. Agents cannot push to the steering file's
   branch; anything there is human instruction. The single best idea in the repo.
2. **Three-tier agent memory.** Ledger (agent-writable history, never instruction) →
   knowledge cards (agent-proposed, human-merged — "history until a human merges it,
   instruction after") → `agent-modes.md` (human-only steering). No vector store on
   purpose: an 80-line index read by a language model *is* semantic retrieval.
3. **Degrade visibly, never silently.** A dead agent and a healthy agent must never look
   the same. Unset sentinels pass loudly; a missing verdict wakes the steward; the
   missing heartbeat line *is* the alert.
4. **The ratchet + "a required check must always report."** Floors only move up;
   suppression counts as lowering; skip with a job-level `if:` (reports "skipped"),
   never a workflow-level `paths:` filter (no check run → the PR waits forever).
5. **Harness guards — test the machine that builds the software.** 128 incident-derived
   pins whose assertion count must equal the inventory count, plus the meta-doctrine:
   when a guard must *execute*, extract the real logic and run it; mutation-test the
   guard by hand once before trusting it.
6. **The adversary never decides.** Different-model-family second review; a referee that
   settles contradictions against the code with an asymmetric burden of proof (ruling
   for its own role requires a quoted `file:line`; ties go to the challenger); verdicts
   are advice, the human overrules at merge.
7. **Floors calibrated to your baseline, never someone else's.** `unset` sentinels,
   armed only by `measure-floors.sh` against the adopter's own code; it refuses to run
   while `examples/` exists.

## 3. What blocks adoption today (verified)

### A. The corporate wall

- **Zero Bedrock support; the auth schema cannot express it.** `git grep -i
  'bedrock|vertex|sigv4'` → nothing. Credential = one scalar (`run-agent.sh:195-210`,
  exit 5 when empty); `claude-code.sh:105-109` rejects any mode but
  `subscription|api-key`. Bedrock needs `CLAUDE_CODE_USE_BEDROCK=1` + AWS credential
  chain (or OIDC role) + `eu.anthropic.*` model ids. Mitigating: the CLI supports
  Bedrock natively, and the scrub at `run-agent.sh:314-316` spares `AWS_*` — plumbing,
  not an integration.
- **The challenge reviewer is dead behind any corporate proxy — silently.**
  `compatible-endpoint.sh:90-95` uses `env -i`, re-adding only HOME/PATH/
  ANTHROPIC_BASE_URL/ANTHROPIC_API_KEY. HTTPS_PROXY, NO_PROXY, SSL_CERT_FILE,
  NODE_EXTRA_CA_CERTS are stripped. Because `required: false`, it degrades to one
  opinion on every run and nothing goes red.
- **The adapter hint is wrong on the load-bearing point.** `compatible-endpoint.sh:11`
  promises "any OpenAI-compatible backend"; the mechanism requires Anthropic-wire
  compatibility (corrected only in `demo-recreation.md:51`).
- **Org repos hit a day-one red X:** `secret-scan.yml:52` (gitleaks-action@v2) needs
  `GITLEAKS_LICENSE` on organization repos — never mentioned in
  `credentials-and-cost.md`.
- **4,346 lines of Actions YAML with the logic inside** (review.yml 1,346; ~61%
  embedded bash/jq; the two-endpoint comment collector exists twice with drift), and
  119 of 128 pins point into that YAML. Also `api.github.com` hard-coded in
  `ci-health-watch.yml:157,179` (breaks GHES), runtime `npm install -g` in
  `claude-code.sh:89-92`, curl→bash in `actionlint.yml:39`.
- **The cost doctrine breaks on Bedrock.** "Marginal cost of one more run is zero" is
  false under metered billing; nothing records spend per run, caps a runaway agent, or
  alarms on budget.

### B. The onboarding gap

- **Template-instantiation only.** No overlay path into an existing repo — the Booking
  case *and* the "point Claude at my repo" case. The seams exist (`AGENTS_ROOT`
  vendored-operation design, loud sentinels, stack-agnostic process layer).
- **The template punishes its own extension paths.** `adapter-hygiene.bats:75-93` pins
  "exactly two verified adapters" *by name*; verifying codex/gemini (as `init.sh`
  instructs) or adding a Bedrock adapter turns the adopter's own required check red.
- **The manual GitHub tail** (fine-grained PAT — which exists only to route around
  "GITHUB_TOKEN events don't trigger workflows"; org toggles; branch protection) is
  presented as one undifferentiated wall.
- **No permissions-enforced trial mode.** REPORT-ONLY exists for one agent, as prose.
- **No see-it-run path.** No devcontainer; the demo needs ~an hour before anything
  moves, while a 3-minute zero-credential tour (626 tests, `status.sh`, `--dry-run`)
  already exists in pieces.

### C. The credibility gap

- **The fleet ships disabled; the template doesn't run its own agents** — while six
  drift bugs sit in the tree: `docs/plans/second-brain-and-sdlc-extension.md` missing
  but referenced by 4+ files; "five scheduled agents" (`agent-routines.md:7,514`,
  `agent-operator-guide.md:15,86`) vs ten in config; "guardrail 8"
  (`agent-modes.md:287`) of seven; "22-gate" (`porting-to-your-stack.md:59`) vs 23; a
  no-op loop in `DEMO.md:42`; a stale test count in CLAUDE.md (~365 vs 626).
- **The second brain is N=1.** One card; the 80-line index cap (~40 cards) has no
  designed fold behaviour.
- **Nothing serves the 90-second reader.** No recording, no positioning against the
  four adjacent things people know, doctrine buried in runbooks.

## 4. The plan, dependency-ordered

The four lenses produced 27 recommendations; the critic found the collisions. Three
mattered: **three incompatible overlay/upgrade designs** (resolved in favour of the
pristine-sha manifest — the only one that can ever compute an upgrade), **a curl|bash
contradiction** (resolved: checksummed, gh-native flows only), and **doctrine-bending**
(marketing pins in pins.json, force-seeding 30 cards — both cut).

### Phase 0 — the honesty pass (week 1–2, all S)

- Fix `ADAPTER_MODEL_HINT` → Anthropic-wire-compatible, note the gateway bridge
  (LiteLLM's Anthropic-format route); add a preflight so a wrong-protocol endpoint
  errors by name instead of degrading mutely.
- Whitelist proxy/CA vars through `env -i` — explicit named passthrough (HTTP(S)_PROXY,
  NO_PROXY, SSL_CERT_FILE, SSL_CERT_DIR, NODE_EXTRA_CA_CERTS, AWS_CA_BUNDLE); they
  select the network path and cannot re-select the backend, so the credential-isolation
  lesson survives. Bats guard: proxy vars survive, a planted OPENAI_API_KEY does not.
- Un-block adapter promotion: split `adapter-hygiene.bats` into per-adapter open-world
  contract checks (keep always) and the template-only census (skip when `{{PROVIDER}}`
  is resolved — the `day-one-green.bats` idiom).
- Sweep the six drift bugs; document GITLEAKS_LICENSE; `api.github.com` →
  `${{ github.api_url }}` (unlocks GHES for an S); parameterize hard-coded slugs in
  `write-product-readme.sh`.
- Two fragilities: `adopt-layout.sh` deletes `examples/` *before* verifying its
  substitution list (reorder: sweep → verify → delete); the watcher ring is positional
  over all agents including disabled ones — make it "previous *enabled* agent" or the
  minimal recommended fleet has a vacuous ring.

### Phase 1 — the corporate on-ramp (first 30 days)

- **Schema 2 designed once, first:** `auth.<provider>.credentials` as a list of env
  entries (scalar = degenerate case), `forge:` key reserved, awk fallback generalised
  past its hidden one-list whitelist (it matters *more* on locked-down runners).
- **Bedrock as a mode branch in `claude-code.sh`**, not a fifth adapter: export
  `CLAUDE_CODE_USE_BEDROCK=1`, require AWS_REGION, warn on non-region-namespaced model
  ids; `run-agent.sh` verifies the ambient AWS chain (OIDC-first, no long-lived secret)
  instead of demanding a token; adapters declare `ADAPTER_CREDENTIAL_VARS` /
  `ADAPTER_SCRUB_PATTERNS` so the scrub stops being a hard-coded vendor regex outside
  the one legitimate vendor home.
- **Spend governance:** tokens/cost per run in the ledger schema, per-run ceilings,
  budget line in the chief-of-staff brief, honest Bedrock section in the cost runbook.
- **OBSERVE mode enforced by permissions:** `mode: observe|active` in config; observing
  workflows run with `contents: read` so a push is mechanically impossible — the repo's
  own signature move applied to its trial week. Ship observing by default; graduating is
  an explicit adoption step (converts "ships disabled" into a designed ramp).
- **Agent-led onboarding:** `ONBOARDING.md` written TO the adopting agent (drive
  `init.sh --answers` + the `ADOPT_*` vars; verify with `check-placeholders.sh`,
  `status.sh`, the bats suites, `--dry-run`; hand back the human-only click list; note
  the trap that `adopt.sh` exits silently non-interactively before the interview). Ship
  the same content as a Claude Code skill.
- **Answer-file profiles** (`profiles/`): working interview answers per provider — and
  the unit a platform team ships internally.
- **Devcontainer + `tools/demo-local.sh`:** 3-minute zero-credential tour as the front
  door.

### Phase 2 — adopt-into-anything, proof in public (first 90 days)

- **One manifest, one mechanism:** `init.sh` stamps `.agents/template-manifest.json`
  (version, harness file list, sha256 of *pristine* pre-substitution content, interview
  answers). `tools/upgrade.sh` computes three-way merges against later releases; never
  touches calibrated floors. **Brownfield = `upgrade.sh --install`** on a repo with no
  manifest: copy in, never overwrite (collisions become `.proposed`), interview in
  place. Stamp the manifest *now* — retrofitting means guessing instantiation releases.
- **The brownfield gate-mapping interview** (the critic's sharpest catch): without a
  per-gate "what command produces your coverage number?", an overlaid host gets 23
  gates where the measured majority skip forever — a Potemkin quality layer.
- **`THE-SEVEN-IDEAS.md`** + README three doors (skeptical → doctrine+evidence;
  convinced → adopt; watching → recording) + honest positioning table with a "when to
  use that instead" column + glossary of house vocabulary at first use.
- **Dogfood in public:** enable docs-freshness, chief-of-staff, health on this repo; do
  NOT pre-fix the remaining drift — let the fleet's first public PRs fix it; link the
  merged PRs, ledger branch, and cards from the README. Seed 6–8 knowledge cards (not
  30 — the brain "grows slowly on purpose"; 30 maintainer-merged cards in a week reads
  as astroturf) from pins.json why-fields and changelog standing decisions.
- **The 90-second loop** recorded from the demo repo, above the fold; DEMO.md split
  into "one loop" and "the full 13-stop tour."
- **`docs/THREAT-MODEL.md`:** assets/entry-points/mitigations with each mitigation
  cross-referenced to its enforcing test; residual risks stated honestly (the default
  tool allowlist includes Bash; the real boundary is branch protection + two reviews +
  the human merge).
- **Air-gap/mirror profile:** parameterize all seven external fetches
  (NPM_CONFIG_REGISTRY, Maven mirror, PLAYWRIGHT_DOWNLOAD_HOST, `IT_DB_IMAGE` var, NVD
  datafeed, checksummed actionlint binary, marketplace-action mirroring notes) behind
  one interview question; the inventory doubles as a security-review deliverable.

### Phase 3 — the forge frontier (90–180 days, only with real pull)

- **Logic out of YAML first:** extract review.yml's step bodies into tested
  `tools/review/` scripts (collector, punt detector, lost-review filer, handoff filer,
  poster) and steward.yml's github-script into `tools/steward/`; workflows shrink to
  thin shims — the residue that is legitimately forge-specific. Moved pins re-home to
  the scripts and become *executable* guards (gate 22's own stronger form). Largest
  single de-risking of GitLab; pays for itself on GitHub alone.
- **Then the forge contract:** `tools/forge/github.sh` behind neutral verbs, with a
  CONTRACT.md whose centerpiece is the behavioural-seams table — the invariants that do
  NOT transfer: the inert-token loop-breaker, two comment endpoints,
  concurrency-eviction semantics, skipped-counts-as-passing, forks-get-no-secrets. Same
  verified/unverified promotion mechanism as providers.
- **The GitLab reference needs a venue and an owner:** a mirrored gitlab.com dogfood
  repo (nothing GitHub-hosted can ever execute `.gitlab-ci.yml`, so without a venue the
  profile ships permanently unverified by the repo's own rules); the mapping doc
  (required checks → MR pipelines + `allow_failure: false`; protected steering branch →
  protected branches + CODEOWNERS; ledger push → project access token, CI_JOB_TOKEN
  can't push; mention-wake → scheduled poller first); runner provisioning notes.
- **Second-brain fold design** before the ~40-card cap binds: per-topic index shards,
  each capped, lint extended across them.

### Deliberately not built

- A curl|bash bootstrap front door (contradicts the security posture; gh-native +
  checksummed only; corporate entry = the internal profile).
- A forge abstraction before the YAML extraction (abstracting 4,346 embedded lines
  produces a dishonest seam; abstracting ten scripts produces a real one).
- Marketing pins in pins.json (pins are incident-derived lessons; pinning README
  structure dilutes the inventory into change-friction).
- Force-seeding ~30 cards in a week (6–8, then organic growth via the dogfooded
  chief-of-staff).
- A line-by-line GitLab port of the workflow YAML (two 4,000-line trees drift — the
  repo's own second-source-of-truth failure mode).

## 5. The Booking playbook

**Take today, unchanged:** `tools/` (run-agent, ledger, spec-pipeline, floors,
knowledge-lint — plain git+POSIX), all fifteen prompts, AGENTS.md, the runbooks, the
three-tier memory, the referee prompt. The ledger mechanism works identically on GitLab.

**Build (S): the Bedrock mode** per Phase 1 — the CLI supports Bedrock natively; in CI
prefer the OIDC-assumed role (no long-lived secret; the answer the security board
wants). Model ids are Bedrock inference-profile ids (`eu.anthropic.claude-*`).

**Build (S): challenge via the internal gateway** — after the Phase-0 proxy fix, point
`CHALLENGE_BASE_URL` at the internal gateway's Anthropic-format route (LiteLLM has one)
serving a *different model family*. Same gateway, different distribution — the
rationale is fully satisfied. Without it, note the compounding cost: no challenge → no
referee → the fail-safe wakes the steward on every agent PR.

**Build (M): the GitLab thin layer from the runbooks, not the YAML.** Key mappings:
required contexts → MR pipelines with `allow_failure: false` (the "must always report"
lesson transfers: `rules:` that produce no pipeline deadlock the MR the same way);
protected steering branch → protected branches + CODEOWNERS; the GITHUB_TOKEN
loop-breaker → **no equivalent invariant, use a scheduled poller**; ledger push →
project access token; two comment endpoints → one notes API (the collector simplifies,
slurp-before-filter stays); schedule auto-disable → doesn't exist on GitLab, keep the
external staleness check anyway (a ring can't detect its own total absence).

**Bring to the security board:** the threat model with test-backed mitigations, the
mirror-fetch inventory, the observe-mode trial week, and the honest residual (agents
execute shell under acceptEdits; the real boundary is branch protection + two reviews +
the human click — a stronger story than sandbox claims that don't survive scrutiny).

**Bring to procurement:** the metered-billing answer before being asked — per-run
token/cost in the ledger, per-run ceilings, budget alarms.

**The platform-team move:** ship one internal answers-profile + mirror settings; every
team adopts with it. That is the corporate "couple of clicks," and it is the same
mechanism as the public one.

## 6. The two-click story for everyone (end state)

| You have | You do | What happens |
|---|---|---|
| Nothing yet | Use this template → `tools/adopt.sh` | Guided interview, landing in observe mode, profile pre-filled |
| An existing repo | `tools/upgrade.sh --install` | Harness overlays without touching your files; gate-mapping interview wires *your* commands; floors calibrate to *your* baseline; the manifest makes future releases a computable merge |
| An agent | "Read `ONBOARDING.md`, adopt this into my repo" | The agent runs the interview non-interactively, verifies with the shipped checkers, hands back the human-only click list |

Plus: the 90-second recording above the fold, the Codespaces badge into 626 green tests
with zero credentials, `THE-SEVEN-IDEAS.md` for the ten-minute why. The second brain
travels furthest of all — `knowledge-lint.sh` + the card contract is a complete,
forge-neutral kit any repo can steal, and every stolen kit is a future adopter.

## Appendix: the twenty verified claims

| # | Claim | Verdict |
|---|---|---|
| 1 | `env -i` strips proxy/CA vars from the challenge adapter (`compatible-endpoint.sh:90-95`) | confirmed |
| 2 | Zero Bedrock/Vertex/SigV4 anywhere (`git grep -i`) | confirmed |
| 3 | Single-scalar auth; unknown modes hard-fail (`run-agent.sh:195-210`; `claude-code.sh:105-109`) | confirmed |
| 4 | Credential scrub spares `AWS_*` (`run-agent.sh:314-316`) | confirmed |
| 5 | Fixed forwarded-secret list, policed by `secret-wiring.bats` | confirmed |
| 6 | Verifying a stub adapter reds the adopter's required check (`adapter-hygiene.bats:75-93`) | confirmed |
| 7 | Runtime `npm install -g` of the CLI (`claude-code.sh:89-92`) | confirmed |
| 8 | curl→bash in `actionlint.yml:39` | confirmed |
| 9 | GITLEAKS_LICENSE undocumented; org repos fail gate 11 | confirmed |
| 10 | "OpenAI-compatible" hint vs Anthropic-wire mechanism | confirmed |
| 11 | `docs/plans/second-brain-and-sdlc-extension.md` missing, referenced 4+ times | confirmed |
| 12 | "Five scheduled agents" twice; config lists ten | confirmed |
| 13 | "Guardrail 8" cited; seven exist | confirmed |
| 14 | "22-gate" vs 23 | confirmed |
| 15 | No-op loop in `DEMO.md:42` | confirmed |
| 16 | GitHub-specific hint in `run-agent.sh:297` | confirmed |
| 17 | Hard-coded `api.github.com` (`ci-health-watch.yml:157,179`) | confirmed |
| 18 | Hard-coded slugs in `write-product-readme.sh:34,95` | confirmed |
| 19 | 4,346 workflow lines; review.yml 1,346, ~61% embedded logic (github-script detail wrong: it lives in steward/nightly-alert, not review.yml) | partial |
| 20 | Handoff loop-breaker rests on GITHUB_TOKEN event semantics (`review.yml:1119-1128`) | confirmed |
