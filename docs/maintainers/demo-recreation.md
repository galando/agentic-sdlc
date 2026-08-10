# Rebuilding the demo repository, from zero

**Maintainer-only.** This file describes how the *template's* public proof —
[`galando/agentic-sdlc-demo`](https://github.com/galando/agentic-sdlc-demo) — is
built. It is about this template's marketing surface, not about anybody's product,
so `tools/init.sh` deletes `docs/maintainers/` during the adoption for the same
reason it deletes `site/` and the upstream-drift tooling: an adopter must never
inherit a file describing somebody else's project.

If you are an adopter who landed here by accident, the file you want is
[`README.md`](../../README.md) section 3 — one command, `tools/adopt.sh`.

---

## What the demo is, and what it has to prove

`agentic-sdlc-demo` is a **real product built inside this harness**, not a fork of
the template with the example renamed. Its job is to answer, with a browsable
repository, the three questions the README makes claims about:

1. **The adoption actually completes** — no placeholder survives, no gate is left
   pointing at `examples/`. `ADOPTION-LOG.md` is the written record of that, snags
   included.
2. **The gates run against real code**, not the bundled toy. Both stacks present at
   the root layout (`backend/`, `frontend/`), every reference-stack gate wired.
3. **The agent loop is visible from outside** — issues triaged, PRs reviewed by two
   model families, a human on every merge, in the Actions tab and the closed-PR list.

The product itself is deliberately boring: **Shortlink**, a URL shortener. It is
chosen to be explainable in one sentence and to exercise every reference gate
(a database and therefore Flyway migrations; a service layer and therefore ArchUnit;
a form and therefore accessibility and bundle checks). Do not make it more
interesting. A demo product that needs explaining steals attention from the process,
which is the thing on show.

---

## Part A — the decisions, before you start

These are the exact interview answers the live demo carries. Reuse them unless you
have a reason not to; a demo that differs from this table will not match the
screenshots and prose in `site/`.

| Interview question | Answer used |
|---|---|
| `PRODUCT_NAME` | `Shortlink` |
| `PROVIDER` | `claude-code` |
| `MODEL_JUDGE` | `claude-opus-5` |
| `MODEL_EXECUTE` | `claude-sonnet-5` |
| `MODEL_CHALLENGE` | `gpt-5-mini` *(a different model family — that is the whole point)* |
| `CHALLENGE_BASE_URL` | `https://api.openai.com/v1` |
| `ALERT_CHANNEL` | `none` *(issues only; a demo does not need a pager)* |
| `RUNNER_LABEL` | `ubuntu-latest` |
| `LEDGER_COMMIT_NAME` | `sdlc-agent` |
| `LEDGER_COMMIT_EMAIL` | `agent@example.invalid` |
| `BUILD_PIPELINE` | `the built-in fallback (tools/spec-pipeline/)` |

You will also need, on the demo repository:

- `AGENT_CLI_TOKEN` — a **subscription token**, not an API key. Mint it with your
  agent CLI's own token command;
  `tools/run-agent.sh --check-credentials steward --role judge` prints the exact one
  for the provider above. The `--role` is not decoration: the steward is event-driven
  and therefore deliberately absent from `ledger.agents`, so nothing about it can be
  looked up, and roles may map to different providers. Any scheduled agent answers the
  same question without it — `--check-credentials health`.
- `CHALLENGE_API_KEY` — a real API key for the second model family. Optional
  everywhere else; **required for the demo**, because "two reviews from two model
  families" is one of the three things the demo exists to show.

---

## Part B — the steps, in order

Run them in this order. Steps 1–5 are local and fast; 6 onwards touch GitHub.

### 0. Delete the old demo

GitHub → `galando/agentic-sdlc-demo` → **Settings** → scroll to **Danger Zone** →
**Delete this repository** → type the full `owner/name` to confirm.

**Recreate it under the exact same name.** The template's `README.md` and
`site/index.html` both hard-link `galando/agentic-sdlc-demo`; reusing the name keeps
them resolving and means step 10 is a no-op. There is a window between the delete and
the create where both links 404 — do the two together.

What the delete destroys, and cannot be recovered: every issue and pull request with
its automated reviews, the whole Actions history, and the `agent-ledger` branch. That
history *is* the demo's evidence, so a rebuild is not a refresh — you are re-earning
all of it from step 9. Nothing in the template repository depends on it.

### 1. Create the repository from the template

GitHub → this repository → **Use this template** → **Create a new repository**:

- Owner `galando`, name `agentic-sdlc-demo`, **Public**.
- **Do not** tick "Include all branches" — the demo's `agent-ledger` branch is created
  fresh by `tools/create-ledger-branch.sh` in step 2, and inheriting the template's
  branches imports history that is not the demo's.

The template's default branch is `main`; make sure the work you want in the demo is
merged there first, since a template copy takes the default branch only.

Then clone it and check that `origin` points at the demo, not at the template:

```bash
git clone https://github.com/galando/agentic-sdlc-demo
cd agentic-sdlc-demo
git remote -v          # must say agentic-sdlc-demo
```

`init.sh` derives `REPO_SLUG` from this remote. A clone of the template with the
remote re-pointed later produces a tree that says `galando/agentic-sdlc` in a dozen
places.

### 2. Run the guided adoption

```bash
tools/adopt.sh
```

Answer the interview with Part A's table. When it offers, say **yes** to:

- retiring the bundled example (`tools/adopt-layout.sh` — it deletes `examples/`
  *and* re-points ~50 references at `backend/` / `frontend/`),
- writing the product README,
- creating the `agent-ledger` branch.

It then stops at step 2/8, where it tells you to add your product code, and asks
whether to walk the rest anyway. Say **no** — everything after that step needs the
code to exist to mean anything, and you come back to the same command in step 6. That
is where Part C comes in.

The adoption edits are still uncommitted at that point, and that is fine: step 6
commits them together with the product build. Nothing between here and there reads
them from a commit.

> The demo currently in production was adopted *before* `tools/adopt.sh` existed and
> used the individual tools (`init.sh`, `adopt-layout.sh`, `create-ledger-branch.sh`)
> by hand. Its `tools/` directory is missing `adopt.sh` and `status.sh` as a result.
> Rebuilding it with `adopt.sh` is the point of rebuilding it — the demo should show
> the path an adopter is actually told to take.

### 3. Build the product

Open a session in the clone and paste the prompt in **Part C** verbatim. Nothing
about this step is agentic-process work: it is an ordinary product build, and the
demo is honest about that in `ADOPTION-LOG.md`'s first line.

**Committing straight to `main` here is correct.** Branch protection comes last on
purpose (step 8) and the floors are measured *from* this code (step 6).

### 4. Verify locally before anything reaches CI

Every command below must be green. This is the list the current `ADOPTION-LOG.md`
records as having been run — reproduce it, and record what you actually saw, not
what you expected to see.

```bash
export JAVA_HOME=<a JDK inside pom.xml's [17,25) enforcer window>   # see Part E

cd backend
mvn clean verify -DskipITs                       # unit + slice + Cucumber + ArchUnit
mvn clean verify -Djacoco.skip=true              # integration, against a real postgres:16
mvn -P mutation test                             # PIT runs clean (uncalibrated, cannot fail yet)
# Gate 10, against a FRESH database. Flyway reads these natively; do NOT pass them
# as -D flags, which would expand them into mvn's argv (see pr-validation.yml).
FLYWAY_URL=jdbc:postgresql://localhost:5432/validatedb \
FLYWAY_USER=postgres FLYWAY_PASSWORD=validate-pw \
  mvn -B flyway:migrate flyway:validate -Dflyway.cleanDisabled=false

cd ../frontend
npm install
npm run lint && npm run test:coverage && npm run build
npm run test:e2e && npm run check:design-system && npm run audit:ci
npm run check:bundle                             # gate 19 — build first, it reads dist/

cd ..
bats tests/ tests/harness-guards/
tools/check-placeholders.sh
actionlint .github/workflows/*.yml
```

The integration suite expects Postgres on the same coordinates
`full-integration-tests` uses: port `5433`, database `itdb`, user and password `it`.

### 5. Write `ADOPTION-LOG.md`

**This is the deliverable, more than the product is.** `tools/write-product-readme.sh`
links to it automatically when it exists, and it is what makes the demo evidence
rather than a screenshot. Structure it as the live one is:

- a dated heading and one paragraph on *what* was built and where,
- one paragraph per stack, naming **each gate by number** and whether it is
  calibrated,
- a "Verified locally" paragraph listing the exact commands and their results,
- a **"Snags hit with the template harness"** section.

The snags section is the most valuable part of the whole demo and the easiest to
skip. Write down every friction you hit, including the ones that were your fault —
each one is either a real template bug to fix upstream or a documentation gap, and
`CONTRIBUTING.md` exists to route them back here. The four snags in the live log
(the JDK window, `@Modifying` needing `@Transactional`, dev-only CVE advisories, a
BSD-`sed` test failure) each produced a real upstream change.

### 6. Commit, push, and calibrate the floors

Re-run the guided adoption. This is the resume it was built for: it now sees your
product at `backend/` / `frontend/`, walks past step 2, and offers the two things
this step is — the commit at 4/8 and the calibration at 6/8.

```bash
tools/adopt.sh
#   4/8  "Commit ALL current changes ... and push?"  -> y
#   5/8  reads the AGENT_CLI_TOKEN secret; it is not set yet, which is correct —
#        step 7 below is where that happens
#   6/8  "Run tools/measure-floors.sh now?"          -> y   (slow, online, clean tree)
#   7/8  branch protection                            -> N  (step 8, after FAST is green)
```

Its commit message at 4/8 is the generic `adopt the agentic-sdlc process`. If you
want the demo's history to read better, do that commit yourself first and let 4/8
find a clean tree:

```bash
git add -A && git commit -m "Build Shortlink: URL shortener backend and frontend"
git push -u origin main
```

Calibration leaves the new floors uncommitted on purpose. Put them up as a branch —
`adopt.sh` prints these same three lines when it finishes measuring:

```bash
git checkout -b calibrate-floors && git add -A
git commit -m "calibrate the ratchet against Shortlink" && git push -u origin calibrate-floors
```

Open that as the demo's **first pull request**. It is the proof shot: a PR that
carries both reviews, the referee comment, and the whole gauntlet.

> **Known gap in the live demo, do not repeat it.** `floors.yml` in production is
> still nine `unset` sentinels, while the generated `README.md` states the floors
> "was calibrated against this code by `tools/measure-floors.sh`". The README is
> generated optimistically; the calibration was deferred and never done. Either run
> step 6 or edit that sentence — a demo whose front page contradicts its own
> `floors.yml` is worse than one that admits the floors are uncalibrated.

### 7. Secrets, variables, and the App

On the demo repository:

- Secrets → `AGENT_CLI_TOKEN`, `CHALLENGE_API_KEY` (both, for the demo).
- Variables → `AGENT_MENTION` if you want anything other than the `@agent` default.
- Install the agent CLI's GitHub App for the repository.
- **Settings → Actions → General → Workflow permissions**: set **Read and write
  permissions**, and tick **Allow GitHub Actions to create and approve pull
  requests**.

That last checkbox is the one that bites, and no script in this repository can set
it. A fresh repository ships with it off; the steward declares `pull-requests: write`
and still fails at the moment it opens the PR — *"GitHub Actions is not permitted to
create or approve pull requests"* — after doing all the work. It looks like a broken
agent, and it is a repository setting.

Note the second half of that checkbox's name is a promise the harness does not use:
an agent can open a pull request here, and never approve or merge one. That is
`AGENTS.md` guardrail 2, enforced by branch protection in step 8, not by this setting.

Then `tools/adopt.sh` again — it verifies the secret is present and moves on.

### 8. Branch protection, last

Only after the FAST tier has reported green on the calibration PR:

```bash
tools/adopt.sh     # step 7/8 offers to apply it via gh
```

It requires a PR plus the seven FAST contexts with no bypass. Promote the `full-*`
contexts within the first week — `docs/runbooks/branch-protection.md` has the exact
strings.

### 9. Produce the visible evidence

The demo is only proof if a stranger can *see* the loop. Open two or three issues
that mention the agent and let the whole thing run end to end, merging each yourself:

- a small feature (e.g. "reject URLs that are not `http`/`https` with a 400"),
- a bug that the agent must reproduce first,
- a docs-only change, to show the pipeline exemption working.

Leave them merged and browsable. Then enable **one** scheduled routine (start with
`health`) after a `tools/run-agent.sh health --dry-run`, so the `agent-ledger`
branch has real entries in it. Not all five — the demo should model the ramp the
README tells adopters to follow.

### 10. Re-check the template's own links

`README.md` and `site/index.html` both point at the demo by name. If you renamed
anything in step 0, fix both.

---

## Part C — the product prompt, verbatim

Paste this into an agent session opened in the adopted clone, after step 2. It is
written to produce the Shortlink that the live `ADOPTION-LOG.md` describes, gate
wiring included.

````text
This repository is a product repository that has already adopted the agentic-sdlc
process template. The harness (workflows, tools/, docs/, tests/) is in place and
already points at `backend/` and `frontend/` at the repository root; `examples/` is
gone. Read AGENTS.md and CLAUDE.md first — they bind this session — and read
docs/QUALITY-GATES.md, which lists the gates you are wiring into.

Build the product the template's example stood in for: **Shortlink**, a URL
shortener. Do not touch `tools/`, `tests/`, `.github/` or `docs/` — they are the
harness and are out of scope. Everything you write goes in `backend/` and
`frontend/`.

BACKEND — `backend/`, Java 17, Spring Boot 3, Maven, package `com.shortlink`.

API:
  POST /api/links            {"url": "..."}  -> 201 with the slug and the short URL
  GET  /api/links/{slug}                     -> the link and its hit count
  GET  /r/{slug}                             -> 302 to the original URL; JSON 404 on
                                                an unknown slug (never an HTML error page)

Rules that matter, and why:
  - Slugs are random base62, 7 characters. On a unique-constraint collision, retry —
    bounded, 5 attempts, then fail loudly. Do NOT check-then-insert: that is a race,
    and the constraint is the thing that actually decides.
  - The hit counter is incremented by a single `UPDATE ... SET hit_count = hit_count + 1`
    JPQL query. Never read-modify-write.
  - Flyway owns the schema. One migration to start: `V1__create_links_table.sql`.
  - Layer it properly: `domain/`, `repository/`, `service/`, `web/`, with DTOs at the
    web edge and exceptions mapped by a `@RestControllerAdvice`. ArchUnit will enforce
    the layering, so decide it deliberately rather than discovering it.

Tests and the gates they satisfy:
  - Unit and slice tests against H2 in Postgres-compatibility mode (gate 1).
  - Integration tests against a REAL Postgres, tagged `docker` so Failsafe runs them
    separately (gate 2). CI uses port 5433, database `itdb`, user/password `it`.
  - JaCoCo wired, floors left at the `unset` sentinel (gate 3).
  - ArchUnit layered-architecture rules with a FreezingArchRule store at
    `backend/archunit_store/` (gate 4).
  - Cucumber acceptance specs under `src/test/resources/features/` (gate 8).
  - The backend half of the ratchet-guard test, reading `floors.yml` directly (gate 9).
  - A PIT `mutation` profile that runs clean, floor uncalibrated (gate 17).
  - maven-enforcer JDK/Maven window (gate 13).

FRONTEND — `frontend/`, React 18, TypeScript, Vite.

One page: a form that shortens a URL, the resulting short link, and a session list of
the links created so far with a per-link "Refresh hits" action. The create response
does not carry a hit count, so start each link at 0 and re-fetch on demand via
`GET /api/links/{slug}`. The dev server proxies BOTH `/api` and `/r` to `:8080`.

Tests and the gates they satisfy:
  - ESLint at zero warnings, `react-hooks` rules included (gate 6).
  - Vitest + `@vitest/coverage-v8`, floors at the `unset` sentinel (gate 7).
  - `npm run audit:ci` green — where an advisory is dev-tooling-only, write a per-
    advisory exposure analysis into `frontend/audit-allowlist.json` arguing from the
    code path this pipeline actually runs. Do not raise the audit level to silence it
    (gate 12).
  - The design-system guardrail: colours come from `src/tokens.css`, no raw hex in
    components (gate 14).
  - Playwright + `@axe-core/playwright`, known-violations baseline left empty (gate 15).
  - A Stryker config that runs clean, floor uncalibrated (gate 17).
  - The bundle-size check against `dist/` (gate 19).
  - The frontend half of the ratchet-guard test (gate 9).

DO NOT calibrate any floor. Every value in `floors.yml` stays `unset` — calibration is
a separate, later step run by `tools/measure-floors.sh` against the finished product.

VERIFY, and report exactly what you saw rather than what you expected:
  cd backend  && mvn clean verify -DskipITs
              && mvn clean verify -Djacoco.skip=true    (real postgres:16 on 5433/itdb/it)
              && mvn -P mutation test
              && mvn flyway:migrate flyway:validate     (fresh database; connection via
                 the FLYWAY_URL / FLYWAY_USER / FLYWAY_PASSWORD env vars, never as -D
                 flags — .github/workflows/pr-validation.yml shows the exact invocation)
  cd frontend && npm install && npm run lint && npm run test:coverage && npm run build
              && npm run test:e2e && npm run check:design-system && npm run audit:ci
              && npm run check:bundle                  (reads dist/, so build first)
  bats tests/ tests/harness-guards/

Finally, write `ADOPTION-LOG.md` at the repository root: what you built, gate by gate,
the exact verification commands and their real results, and a "Snags hit with the
template harness" section listing every friction you hit — including the ones that
turned out to be your own mistake. That section is the point of the exercise; a snag
you smooth over silently is a template bug that nobody upstream ever hears about.
````

---

## Part D — done when

- [ ] No `{{...}}` token anywhere (`tools/check-placeholders.sh` exits 0).
- [ ] `examples/` gone, `backend/` and `frontend/` present, harness re-pointed.
- [ ] `ADOPTION-LOG.md` exists, with a snags section that names real snags.
- [ ] `floors.yml` calibrated **or** the README's calibration sentence corrected.
- [ ] `agent-ledger` branch exists on origin and has at least one real entry.
- [ ] At least one merged PR carrying two reviews, a referee comment, and a green gauntlet.
- [ ] Branch protection on, seven FAST contexts required, `enforce_admins` true.
- [ ] The template's `README.md` and `site/index.html` links resolve.

---

## Part E — snags that will happen again

Carried forward from the live `ADOPTION-LOG.md` so the next rebuild does not
rediscover them:

- **The system JDK is probably outside the enforcer window.** `backend/pom.xml`
  requires `[17,25)`. A machine defaulting to a newer JDK fails at `validate` — which
  is the enforcer working correctly. Export `JAVA_HOME` to a JDK inside the window
  before any `mvn`.
- **A hand-written `@Modifying @Query` method is not transactional.** Spring Data
  wraps the *inherited* CRUD methods, not yours. Calling `incrementHitCount` directly
  from a `docker`-tagged repository IT — outside the service layer's `@Transactional`
  boundary — throws `TransactionRequiredException`. Annotate the query method itself.
- **`npm install` surfaces real high/critical advisories from dev-only tooling.** That
  is gate 12 doing its job: force a written per-advisory decision into
  `audit-allowlist.json`, never a blanket audit-level bump.
- **BSD `sed` vs GNU `sed`.** On macOS, `sed -i 's/.../'` without a backup suffix is a
  syntax error. If a `tools/` test fails only on your Mac, check this before believing
  you broke something.
