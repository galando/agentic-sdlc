# Branch protection — making the gauntlet binding

**Without this, every gate in [docs/QUALITY-GATES.md](../QUALITY-GATES.md) is
advisory.** GitHub will happily let a pull request merge with red checks unless
the branch has a protection rule that marks those checks *required*. This is
the single setting that turns the whole suite from "CI ran and complained" into
"this cannot land broken."

It is a repository **admin** setting, so it cannot be committed to the repo or
applied by an agent — a human with admin rights has to set it once. That makes
it the **last** step of setting this template up, and the one nobody can do for
you. Until the rule exists *and* "do not allow bypassing" is ticked, everything
else here is a suggestion.

<!-- placeholder: {{DEFAULT_BRANCH}} — the branch pull requests merge into (`main` for most repos); tools/init.sh fills it in. -->
<!-- placeholder: {{REPO_SLUG}} — `owner/repo` on GitHub. -->

## How a context string is decided

A required check is matched by its **context string**, and the context string is
the job's `name:` when it has one and the **job id** otherwise. Nothing warns
you when you get it wrong: GitHub accepts any string you type, including one no
job will ever report, and then every pull request blocks forever waiting on a
check that does not exist. That is the usual failure mode, and it is silent.

This is not hypothetical. Upstream, a secret-scanning job had a one-word job id
and a `name:` that was a whole sentence ("Scan for secrets with `<tool>`"), so
the string branch protection actually needed was the sentence — and the obvious
guess, the job id, matched nothing at all. Every pull request sat un-mergeable
behind a check that was never going to report, and the only symptom was a
spinner.

**So in this template, every blocking job's `name:` is character-identical to
its job id.** One string per gate instead of two that can drift apart. If you
add a gate, keep that property; if you rename a job or give it a prettier
`name:`, the context string changes with it and the ruleset must be updated in
the same pull request.

A check can also stop reporting *after* running to completion — every step
succeeds and the job still never publishes a conclusion. That is an
infrastructure stall, not a configuration bug, and nothing on this page will
fix it; see [qa-procedures.md](qa-procedures.md) §3, "When a check hangs
`in_progress`", which tells the two apart.

## The checks to require

The blocking gates are split into two cost tiers. Both run on every pull request
to `{{DEFAULT_BRANCH}}`; neither is behind a workflow-level `paths:` filter, so
every one of these contexts always reports a result.

### Require a context only once its job exists

This is the trap this whole page is about, and it is worth thirty seconds
before you paste anything.

**GitHub does not validate a required status context against anything.** Any
string is accepted. A context that nothing ever reports leaves every pull
request parked at *"Expected — waiting for status to be reported"*: no failure
to read, no job to re-run, no way forward except an admin edit. It is the same
wedge as a required check behind a workflow-level `paths:` filter, arrived at by
a simpler route — the check cannot report because it does not exist.

So the tables below carry a **status** column, and any row marked
`NOT YET IN THE TREE` is a context you must not require yet. Check it yourself
rather than trusting this page, which is a document and can drift:

```bash
# Every context you are about to require must already exist as a job id.
for c in fast-unit-tests fast-frontend-checks fast-harness-guards \
         fast-repo-hygiene fast-secret-scan fast-actionlint fast-spec-artifacts \
         fast-knowledge-lint; do
  grep -rqE "^  ${c}:[[:space:]]*$" .github/workflows/*.yml \
    || echo "NOT PRESENT: $c"
done
```

Silence means every one of them is real. Any line of output is a context that
would wedge your repository — drop it from the list until its workflow lands.

(Job ids are the context strings here because no gate job declares a `name:`
key. That is deliberate: with one string per gate instead of two, the id and the
context cannot drift apart.)

### Fast tier — safe to mark required immediately

Minutes, not tens of minutes. Turn these on the moment the workflows are in
place; there is no reason to wait and no PR they can wedge.

| Check (exact context string) | Workflow | Status | Covers |
|---|---|---|---|
| `fast-unit-tests` | `pr-tests.yml` | present | unit suite, coverage ratchet, architecture rules + freeze store, executable acceptance specs, build hygiene |
| `fast-frontend-checks` | `pr-tests.yml` | present | lint at zero warnings, frontend tests + coverage ratchet, design-system guardrail, fast dependency CVE gate |
| `fast-harness-guards` | `pr-tests.yml` | present | the text-pins over the agent workflows themselves — the only thing testing the machine that builds the product |
| `fast-repo-hygiene` | `pr-tests.yml` | present | ratchet-guard tests: no floor lowered, no threshold deleted, no exclude widened, no freeze store removed |
| `fast-secret-scan` | `secret-scan.yml` | present | a credential about to be committed |
| `fast-actionlint` | `actionlint.yml` | present | every workflow file parses and its expressions are valid |
| `fast-spec-artifacts` | `spec-artifacts.yml` | present | the plan and spec artifacts a change is required to carry |
| `fast-knowledge-lint` | `pr-tests.yml` | present | the second brain's index/card agreement, frontmatter completeness, and line caps (`docs/knowledge/`) |

### Full tier — required in one documented step, within the first week

These are the expensive gates: containers, browsers, mutation runs. They are
**live and reporting from day one** — they run on every pull request from the
moment you adopt the template, they just are not blocking yet. Promote them once
you have watched them report on real pull requests, and do it soon. A gate that
reports and cannot block is advisory, and advisory gates get ignored under
deadline pressure — which is the exact condition they exist for.

| Check (exact context string) | Workflow | Status | Covers |
|---|---|---|---|
| `full-integration-tests` | `pr-tests.yml` | present | integration tests against the real dependency, migrations applied from scratch |
| `full-migration-validation` | `pr-validation.yml` | present | duplicate versions, and migrations that will not apply cleanly to a fresh database |
| `full-mutation-on-diff` | `pr-mutation.yml` | present | mutation score over only the code this PR touches |
| `full-e2e-accessibility` | `pr-tests.yml` | present | end-to-end in a real browser plus the accessibility scan |
| `full-bundle-budget` | `pr-tests.yml` | present | the size ceiling |

Promotion is one edit: add the five strings to the same `contexts` array (Option
B below), in one pull request, with the run links that show them green. Record
the date. "We meant to require those" is not a state anyone can audit.

## Skipped passes. Never-started does not.

This is the distinction the whole page turns on.

- **A job-level `if:` is safe.** A job skipped by an `if:` reports a **skipped**
  conclusion, and GitHub counts `skipped` as satisfied for a required check. A
  gate that sits out a PR touching none of its files still reports.
- **A workflow-level `paths:` filter is fatal.** The workflow never runs, so no
  check run is ever created, so nothing reports — and a required check that never
  reports leaves the pull request permanently un-mergeable. There is no timeout
  and no error; it simply waits.

**Never put a required check behind a workflow-level `paths:` filter.** Scope it
with a job-level `if:` instead.

That is why `pr-validation.yml` and `pr-mutation.yml` look the way they do here.
Upstream, both arrived with workflow-level `paths:` filters — correct there,
because neither was a required check, and skipping the whole workflow on an
unrelated PR is free. In this template both are full-tier gates that *will* be
required, so the filter moved down a level: a `changes` job computes the path
filter once, and each real job carries `if: needs.changes.outputs.<area> ==
'true'`. The workflow always runs, the job skips cleanly, the check reports
`skipped`, and the merge is not blocked. Keep it that way. Moving a `paths:`
filter back up to the workflow is a one-line change that quietly wedges every
pull request that does not touch those paths.

## Never mark these required

| Check | Why not |
|---|---|
| `changes` | Plumbing. It is the paths-filter job whose outputs gate the others, not a gate itself. Requiring it pins an implementation detail into repository policy, and the day you replace the filter mechanism every open PR blocks. |
| every `nightly-*` and `notify-*` context | They **do not run on pull requests at all.** Requiring one blocks every pull request forever, on day one, for a check that by design will never report. Nightly gates reach a human through the alert issue and `{{ALERT_CHANNEL}}` (see `nightly-alert.yml`), never through the merge button. |
| `sweep` (`review-sweep.yml`) | It runs on a `workflow_run` completion and acts **only when the review run was cancelled**, so on an ordinary pull request it never reports. Requiring it blocks every pull request forever, waiting on a check that by design will not arrive — the same trap as the nightly contexts above. It is a reporter, not a gate: its whole job is to say *nobody is acting on these reviews*, which is information for the person merging, never a reason to stop them. |
| `watch-ci-health` | Same reason — scheduled only, never on a pull request. It is also the one check whose *subject* is CI itself: requiring the watchdog that tells you the runners are down would mean a runner outage blocks every merge as well as every build, which is the outage helping itself along. |

<!-- placeholder: {{ALERT_CHANNEL}} — where operational pings go (a chat channel,
     an email list, a pager). -->

## Option A — the UI

Settings → Branches → Add branch ruleset (or "Add rule") for `{{DEFAULT_BRANCH}}`:

- [x] Require a pull request before merging
- [x] Require status checks to pass before merging
  - [x] Require branches to be up to date before merging
  - add every **fast-tier** context above marked `present`, spelled exactly.
        Search by name in the picker rather than typing them: the picker only
        offers contexts it has actually seen report, so a string it cannot find
        is a string that would wedge you. **If the picker does not offer it, do
        not type it in by hand** — that box accepts anything and this is the one
        place the UI would have caught the mistake for you.
- [x] Do not allow bypassing the above settings *(this is the one that matters —
      without it, admins silently bypass everything)*
- [x] Block force pushes

## Option B — one API call

With a token carrying `repo` scope (an admin's personal access token):

```bash
curl -X PUT \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/{{REPO_SLUG}}/branches/{{DEFAULT_BRANCH}}/protection \
  -d '{
    "required_status_checks": {
      "strict": true,
      "contexts": [
        "fast-unit-tests",
        "fast-frontend-checks",
        "fast-harness-guards",
        "fast-repo-hygiene",
        "fast-secret-scan",
        "fast-actionlint",
        "fast-spec-artifacts",
        "fast-knowledge-lint"
      ]
    },
    "enforce_admins": true,
    "required_pull_request_reviews": null,
    "restrictions": null,
    "allow_force_pushes": false,
    "allow_deletions": false
  }'
```

**This array holds all eight fast-tier contexts, every one marked `present`
above** — that is what makes it safe to paste unread. A row this page ever
marks `NOT YET IN THE TREE` must stay out of it until the loop above confirms
otherwise; a ruleset an admin has to hand-edit before using is a ruleset they
will get wrong, and getting this one wrong wedges the repository rather than
merely under-protecting it.

One later edit, the same call with a longer array — the call **replaces** the
whole array, so always send the complete set, never just the additions. Add
each name as a JSON string, exactly as spelled in the tables above:

**Promotion week**, once you have watched the full tier report green on real
pull requests: append the five full-tier names from the table above, for
twelve. Re-run the `NOT PRESENT` loop first — silence is the signal they are
really there.

A rule for this and for anything you add later: **the loop before the paste,
every time.** Two minutes of typing recovered a repository the last time this
page was wrong, and the failure gives you nothing to read — a wedged pull
request looks like a check that is merely slow.

`enforce_admins: true` is deliberate. Agents open pull requests under a human's
identity; if admins can bypass, the gauntlet is optional exactly for the
accounts most likely to be automated.

## Verifying it took effect

```bash
curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/{{REPO_SLUG}}/branches/{{DEFAULT_BRANCH}}/protection \
  | python3 -m json.tool
```

Expect `required_status_checks.contexts` to list exactly the strings above and
`enforce_admins.enabled` to be `true`. Read the contexts character by character
against a real run's job list — a typo here produces a rule that looks correct
in the API response and blocks every pull request.

Then confirm behaviourally: open a throwaway pull request that deliberately
breaks a test and check that the merge button is disabled. **A gate nobody has
watched fail is a gate nobody knows works.** Close the throwaway PR afterwards;
do not merge it green.

## Why agents cannot do this

Per [AGENTS.md](../../AGENTS.md), agents never merge their own pull requests and
never alter repository policy. Branch protection is the mechanism that makes
that guarantee enforceable rather than an honour system, so it deliberately sits
outside what any automated session can change — including the steward, which has
no admin scope and would fail with `403` if it tried.

The ordering matters and it is not accidental. Everything else in this template
can be installed by opening a pull request. This one setting cannot, which is
why it is last, why a human has to do it, and why an adoption is not finished
until someone has.
