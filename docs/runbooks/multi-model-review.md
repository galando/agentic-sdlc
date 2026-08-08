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
| `.github/workflows/review.yml`, job `challenge-review` | A full second review of the same diff, written without reading the first one | The `referee` job settles disagreements against the code and gives a verdict. The author overrules it at merge time. |
| The `challenger` scheduled agent (`docs/runbooks/agent-routines.md`) | The blind re-derivation of the target conclusion | The challenger's own `judge`-role session, after weighing the challenge model's reasoning |

A different family is trained separately and **fails in different places**. That is the
entire point — a second opinion is only worth having if it can disagree. Two draws from
the same distribution share the same blind spots, so a "second opinion" from the same
family is a more expensive way to get the first one.

## Why the adversary never decides alone

A second model that can *overrule* the first one just moves the single point of failure.
So it never rules on its own:

- The challenger reads the challenge model's derivation, checks whether the reasoning
  holds, and forms its own view. A refutation is something the challenger concluded, never
  something it copied through. The adversary disagreeing is a reason to look hard, not a
  ruling.
- The referee reads both reviews and rules — but on the evidence in the code, not on which
  model it likes. See the next section.

**A finding only one reviewer raised is not outvoted by the other's silence.** It is the
most valuable thing on the page, because a single reviewer would have lost it completely.

## The referee settles disagreements

**What was wrong.** The referee used to sort the two reviews and stop. Its prompt forbade
it from saying who was right and its output ended *"neither review is authoritative, a
human decides"*. Every disagreement became an operator decision.

Two things made that worse than it sounds. Most flagged "contradictions" were not
contradictions — one reviewer being silent about a finding, the two grading the same defect
at different severities, or two perfectly good fixes for one bug. And the ones that *were*
real were almost always questions of fact about the code ("does this line leak the
connection or not?"), which have an answer somebody can go and check. The operator was
being asked to adjudicate things a careful read of the diff would have settled.

**What changed.** The referee now does both jobs.

1. **A much higher bar for calling something a contradiction.** Two reviewers contradict
   each other only when they make claims about the same code that cannot both be true.
   Silence, differing severity, differing-but-valid fixes, broader-vs-narrower descriptions
   and style disagreements are explicitly not contradictions, and are filed where they
   belong.
2. **It settles the real ones against the code.** The workflow hands it
   `.review-artifacts/diff.patch` and it reads the repository. It names the reviewer the
   code supports, quotes the `file:line` that proves it, and says what to do.
3. **Every disagreement gets a verdict. There is no "unresolved".** See the ladder below.
4. **Uncertain findings are kept, not dismissed.** A wrong finding costs one person one
   look. A dismissed real finding costs a defect in production.

### The tie-break ladder

The referee works down this list and stops at the first rung that answers:

| Rung | Test | Verdict |
|---|---|---|
| 1 | Does the code settle it? | Rule for that reviewer, quote the `file:line` |
| 2 | Judgement call, no factual answer | Rule for the option that **fails more safely** — keeps a check, keeps data, keeps a user-visible thing rather than removing it |
| 3 | Both fail equally safely | Rule for whichever advice is **cheaper to undo** if wrong |
| 4 | Still level | **Rule for the challenge role** |

**Rung 4 always terminates, so a verdict is always available.** It also puts every
coin-flip against the referee's own side rather than for it, which is the same asymmetry as
the evidence rule, applied to ties.

There is deliberately **no section for unsettled disagreements**, and the prompt bars the
referee from inventing one — an escape hatch that exists gets used, and every use of it
hands the operator a decision again.

### How the self-grading problem is answered

The objection to letting the referee rule is real: it runs the same `judge` role that wrote
one of the two reviews. One party holds the gavel.

That is answered structurally rather than by abstaining. The referee decides **questions of
fact about the code**, not "which reviewer do I trust" — and facts can be checked by whoever
reads the comment. On top of that the burden of proof is deliberately **asymmetric**: a
ruling in the judge role's favour requires a quoted `file:line`, and without that evidence
the referee must rule for the challenge role. Ruling for the challenge role carries no such
requirement.

**Verdicts are advice, not gates.** The referee posts a comment; it merges nothing and
blocks nothing. The author overrules any verdict at merge time. That is what makes an
occasional wrong call cheap — and why abstaining was never worth its cost.

### The referee judges the commit the reviews were written for

**What was wrong.** The referee fetched the diff with the "give me this pull request's
diff" command, which resolves the head **at the moment the referee runs**. The two reviews
it compares were written earlier, against whatever the head was then. Nothing tied them
together.

So a fix pushed between a review and the referee job made the reviewer who found the bug
look wrong: the referee measured the **fix** and scored it against the finding that produced
it. Observed ruling two accurate reviewers wrong at once — it read a head two commits newer
than one review, then accused a reviewer of miscounting lines that really were that many in
the commit it had read.

The window is usually seconds, which is why it hid. **It bites precisely when an author
fixes findings as they arrive — so the more responsive the author, the more likely their
reviewers are marked down.** And the referee's comment is the last word on the page, so a
reviewer who was right is recorded as wrong.

**What changed**, in three parts, all of which are needed:

- **Pinned.** The diff comes from a compare between the event payload's `base.sha` and
  `head.sha`, which are fixed when the run is triggered, so they name the state the
  reviewers were sent.
- **Disclosed.** The step compares that pinned head against the live head, and when they
  differ, a note is prepended saying the verdicts describe the reviewed commit. Prepending
  happens in **its own step**, so posting stays a plain "send the file" and cannot grow a
  reason to send nothing.
- **Told.** The prompt says the diff is pinned, that the checked-out tree may be newer, and
  that **a finding which looks already fixed is usually a reviewer being right and the
  author acting on it**. This part matters on its own: the referee reads the repository as
  well as the diff, so pinning the diff alone would not stop it reaching the same wrong
  conclusion from the working tree.

This does not stop the two *reviewers* reading different commits from each other — that
needs both review jobs to pin their own fetch, and is a separate change.

`tests/harness-guards/referee-diff-pin.bats` runs the real fetch step against a stubbed
API, because "asks for the pinned range" and "asks for the live head" are two calls that
look almost identical in the file and behave completely differently.

### The missing-review notice has to agree with itself

The notice that says a review did not arrive was built by splicing a noun into a fixed
sentence. When **both** reviews were missing it rendered three contradictions at once: a
plural in a sentence written for a singular ("**BOTH reviews** is not on this pull
request"), a log line claiming one review was found when none were, and "one reviewer at
most" used to describe **zero** — which reads as one.

That notice is the only thing telling a reader a green check does not mean "reviewed
twice". Its entire job is to be right about the count, so it is now a **whole sentence per
case** rather than a noun in a hole, and the zero case says "no automated review at all".

### The prompt is a request, so the output is checked

A prompt cannot force a model to do anything, and on a bad day it could still write "needs a
decision". The workflow step **Check the referee actually ruled** scans the generated
comment for punt language before it is posted: headings like `## Unresolved`, `## Needs a
decision`, `## Open questions`, and closing lines like "a human decides" or "leave this to
the author".

If it finds one, the comment is **still posted** — a silent referee would lose the whole
comparison, not just the punt — but with a warning block on top saying the referee broke its
own rule, that this is a **bug to report rather than a decision you owe anyone**, and
linking the run. The job also emits a workflow warning naming the offending lines.

So a punt cannot reach you disguised as a question. It reaches you labelled as a defect,
which is what it is.

`tests/harness-guards/referee-verdict.bats` pins these behaviours, and
`tests/harness-guards/steward-handoff-order.bats` pins the ordering below.

## The steward handoff runs after BOTH reviews

The handoff issue — the one that tells the steward "this pull request has review findings,
go act on them" — is filed at the end of the `referee` job, not at the end of `review`.

It used to be filed from `review`. But `challenge-review` declares `needs: review`, so
nothing the challenge role posts can exist yet at that point: on every pull request, always,
not by bad luck. Three things followed.

1. The steward was woken before the second review and the referee comparison existed, and
   then reported on a pull request it had read once, minutes before the rest of it arrived.
2. It built its fix on one opinion out of three.
3. Worst, and invisible: the clean check read **one** comment body, which by that ordering
   could only be the judge-role review. A pull request where the judge role was clean and
   the challenge role found a bug filed **no handoff at all** — the stranded-finding failure
   the handoff exists to prevent, reintroduced for the second reviewer.

The handoff now reads both collected review bodies and files when **either** carries
findings. Two consequences worth knowing:

- The `referee` job is no longer gated on the challenge role having run. Gating it that way
  would have deleted every handoff behind a missing `CHALLENGE_API_KEY`, which is far worse
  than the bug that moved it. Either reviewer producing a review is enough to enter the job;
  neither producing one skips it silently, which is the untouched-template state.
- The collector produces the two review bodies even when `jq` is missing from the runner,
  using the `jq` that `gh` embeds. A missing `jq` costs the comparison only — never the
  handoff.

### Are the verdicts any good? The challenger audits them

Letting the referee rule created an instrument gap: the pipeline is thoroughly instrumented
for findings being **lost** and had nothing at all for findings being **judged badly**. A
confidently wrong verdict is the last word on the page and nothing was looking at it.

The challenger now audits one settled disagreement every third run, using the same blind
re-derivation it applies to any other conclusion — read the diff and both claims, decide,
*then* look at the verdict. It prefers verdicts that went to the judge role, because that is
the direction the asymmetric burden of proof is meant to make hard, so a failure of the
burden shows up there first.

Agreement is recorded rather than discarded: it is the only evidence that exists that the
referee is worth trusting. Disagreement is an S2 — a wrong verdict is advice the author
could already have overruled, not a production defect. **Two disagreements in the same
direction** is the signal that matters, and belongs in a pull request against the referee's
prompt rather than in another issue.

### Two ways the handoff can still be lost, and what each does about it

**The collector fails.** If the step that reads the two reviews off the pull request dies —
a transient API error is enough — the review bodies are missing for a reason that looks
identical on disk to "there were no reviews". But the reviews *are* there, with findings,
and the lost-review check correctly filed nothing because it saw them. The handoff used to
read "no reviews" and exit quietly, waking nobody. It now separates the two cases and
**says so on the pull request** when it could not look, because the person merging is the
only one who can act on it.

**The run is cancelled.** The handoff is filed at the end of the last job, so a run
cancelled part-way — routine on a busy single runner, and this workflow is advisory rather
than a required check — files no handoff even though reviews were posted. This is the
accepted cost of filing late: filing early is what produced a handoff built on one opinion
out of three, and what dropped every finding the second reviewer raised alone.

`review-sweep.yml` closes the reporting half of it: it watches the review workflow finish,
and when the conclusion was `cancelled` it posts one notice on the pull request saying no
handoff was filed and the reviews are the reader's to act on. It deliberately does **not**
file a handoff itself — the collector that decides whether the reviews carry findings is the
very thing that was cancelled, so filing speculatively would wake the steward for clean pull
requests and teach everyone to ignore it.

### The handoff issue closes itself

That issue is **a signal shaped like a work item**. Filing it starts the steward's run, and
the signal is spent the moment the run begins — but for a while nothing owned the ticket
afterwards, so it stayed open. Upstream ended up with 8 of the 42 ever filed still open, one
of them for a fix that had been pushed and replied to hours earlier.

Mostly clutter, with one real cost: **the handoff dedupes on the exact issue title, and that
title carries the pull-request number.** A stale open issue therefore blocks a *second*
handoff for the same pull request — so a pull request marked `ready_for_review` again after
more commits gets a review round that wakes nobody. The stranded finding, one level up.

`steward.yml`'s existing "require a visible outcome" step already works out whether the
steward left anything behind, so it now closes the issue as `completed` when it did. Reusing
computed state rather than adding a prompt instruction an agent can ignore. Two conditions,
both load-bearing:

1. **The title must start `[steward-handoff]`.** That step runs on *every* opened issue,
   including bug reports people file by hand — auto-closing someone's new issue because the
   steward replied would be worse than the problem being fixed. It also keeps `[review-lost]`
   issues open: those report a broken review pipeline, which a steward reply does not repair.
2. **The reply must be the steward's own, not anyone's.** The outcome check counts any
   author on purpose (a human answering means the issue is not silently unanswered). Reusing
   that looser signal for *closing* would let a human writing "hold on" close the very ticket
   they were objecting to.

The close is best-effort: a failure warns rather than reddening a run whose work is done.

`tests/harness-guards/steward-handoff-closure.bats` is behavioural rather than a text pin —
it extracts the real script out of the workflow and runs it against a stubbed API, because
every dangerous failure here is a wrong branch taken, not a missing string. The three
scenarios that must never close are a human's own issue, a `[review-lost]` issue, and a
handoff where only a human replied.

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
| Repository secrets | `CHALLENGE_API_KEY` | `challenge-review` skips with a workflow warning; the `judge` review still runs. The `referee` job still runs and posts a notice **on the pull request** saying which review is missing and that it had one reviewer at most — it is not gated on the second review, because the steward handoff is filed from it. **The pull request is never failed by the absence.** |
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
  `challenge-review` skips with a warning and the `judge` review carries on unchanged. The
  referee still runs, posts "one reviewer at most" on the pull request instead of a
  comparison, and still files the steward handoff. Nothing else to do.
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
