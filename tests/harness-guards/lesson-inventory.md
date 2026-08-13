# Lesson inventory

_Captured 2026-08-05 against source head `9589c5c65a0baca02a9436b3f472929531e91a88`. 129 entries: 98 `regex`, 8 `literal`, 23 `semantic-manual`._

_Addendum 2026-08-12: eight `literal` entries were added — three for the second brain
(Part A of PR #18's design; spec at `.temper/specs/second-brain-and-sdlc-extension/`) and five for the SDLC-extension
agents (Part B). These are forward-looking pins on live tree content, not extractions
from the original vendor-specific source head above._

> This count is asserted against `pins.json` by
> `tests/harness-guards/pins-discharge.bats`, and so is the presence of a section here for
> every source file that has entries there. That guard was added after this file said
> `110` while `pins.json` held `120` — a whole file's worth of entries missing from the
> human-readable half while its own per-section totals still added up perfectly. Anyone
> reconciling against this page would have dropped exactly those ten, with a count that
> looked self-consistent the entire time. **A number nobody recomputes is a number that is
> already wrong.**

## Why this file was written before the substitution, not after

Seven continuous-integration workflows in a read-only source repository carry months of
production incidents as load-bearing strings and comments. They are about to be copied into
this template and genericised. This inventory enumerates every load-bearing string **before**
that copy happens.

The ordering is the whole point. A guard authored *after* the substitution can only pin what
survived it. A lesson silently dropped during extraction would then be pinned in its absent
state and go green forever — a net woven after the fall. Written first, this file is instead
the acceptance criterion the substitution has to satisfy: an assertion that already existed.

### The exception, stated here and not only in `pins.json`

**One section of this inventory was captured AFTER ITS GENERIC COUNTERPART EXISTED**, and it
is marked as such where it appears: the ten `<CI-HEALTH-WATCH>.yml` entries. That file was
skipped in the original capture pass. Its entries were quoted from the same read-only source
at the same `source_head`, so the quotations are as good as any other — but their `pattern`s
were chosen to fit target text that was already on disk, which the earlier entries' were not.

They therefore guard against a FUTURE regression. **They are not evidence that the extraction
preserved anything**, because they could not have gone red no matter what the extraction had
done. That is the exact weakness the before-substitution rule exists to remove, and it is
worth writing here rather than only in the machine-readable file: `pins.json` disclosed it,
this page did not, and this page is the one a human reads. A reader comparing the two would
have concluded the stronger claim held for all 120 entries — on the ten where it holds least.

Where a claim is weaker than the rule, say so at the same volume as the rule.

Every `quoted_source_string` in `pins.json` is verbatim from the source at the head above,
with the source line number. Where a quoted line contains a project name, domain noun, secret
name, issue number or vendor name, that token is redacted in angle brackets and the entry is
classified `semantic-manual`, because such a string cannot survive genericisation unchanged.

Two of the source FILE PATHS were themselves vendor-named, so they are redacted the same way
— `<VENDOR-REVIEW-WORKFLOW>` and `<VENDOR-STEWARD-WORKFLOW>`. Nothing is lost: `source_head`,
`source_line` and the quoted string still locate every entry exactly in the source, and the
arrow in each section heading still says which target file it became.

## How to read the two pin kinds

- **`literal` / `regex`** — the string survives genericisation unchanged and is pinned
  mechanically. A generated test asserts it against the target file. If the extraction drops
  it, the suite goes red.
- **`semantic-manual`** — the string itself *must* change (a role name, a vendor action, a
  standards-document path, a secret name, a job identifier). **No mechanical assertion is
  possible, so these are NOT pinned.** Each records what the concept is and what the
  replacement must still do. An undischarged `semantic-manual` entry is an open obligation,
  not a passing check — do not mistake one for the other.

  Every one of the 23 is hand-walked in **`tests/harness-guards/semantic-discharges.md`**,
  which is committed alongside this file, and `discharged_in` in `pins.json` names where each
  concept landed. `discharged_in: null` means **genuinely open** — never merely unrecorded —
  and a null entry carries `partial_discharge` saying what has landed and what has not.

  That record was originally written to a gitignored evidence path, which meant the shipped
  tree asserted 23 obligations and carried the proof for none of them. It cost something
  real: `collector-single-endpoint-must-merge-both` had been recorded as fully discharged
  while half of it was missing, and the claim was unreachable for anyone who wanted to check.
  **An unverifiable discharge is worth less than an honest `null`.**

Four entries describe behaviour the source does **not** yet have, where the extraction must
*correct* rather than copy. Each says so in its own "replacement must preserve" line:

- `collector-single-endpoint-must-merge-both` — the source reads only the issue-comments
  endpoint; the target must read the review-comments endpoint as well and merge.
- `review-selection-must-not-use-exclusion` — the source selects one role by excluding the
  other role's marker; the target must select each role by its own positive marker.
- `validation-workflow-paths-filter-must-be-converted` — the source still uses a
  workflow-level path trigger; the target must convert it to a change-detector-fed job
  condition so the check can be required.
- `secret-scan-job-name-differs-from-id` — the source job's identifier and name differ, which
  is the documented usual failure mode; the target must make every name identical to its id.

---

## `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml` → `.github/workflows/review.yml`

_42 entries: 29 mechanical, 13 semantic-manual._

### `review-model-pinned-not-floating-alias`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:13`
- **Pin kind:** `semantic-manual`
- **Lesson:** A reviewing agent must be pinned to an exact model identifier, not a floating alias. A floating alias silently resolves to whatever the platform default happens to be that week, so the thing doing the judging changes underneath you with no diff, no announcement and no way to reproduce an earlier review.
- **Concept:** The model that performs a judgement task is selected by an exact, versioned identifier and the reason for pinning is written down next to it.
- **Replacement must preserve:** An explicit model/agent selection (however the generic runner spells it) plus a comment stating that a floating or default alias is not acceptable for a judgement role because it drifts silently.
- **Discharged in:** .github/workflows/review.yml — reviewer A step comment: the model is taken from `models.judge` and pinned by exact id, with the drift reason stated next to it. See tests/harness-guards/semantic-discharges.md row 1.

### `review-lone-finding-is-the-point`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:44`
- **Pin kind:** `regex` — pattern `a finding only one of them raised`
- **Lesson:** The entire value of a second, differently-failing reviewer is the finding only one of them raised. Any downstream step that treats disagreement as noise, or silence from one reviewer as a veto on the other, destroys the reason the second reviewer exists.

### `referee-sorts-does-not-grade`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:55`
- **Pin kind:** `regex` — pattern `grading its own paper`
- **Lesson:** The comparison step runs on the same model family as one of the reviews it is comparing, so it is a party to the dispute and may only sort findings, never rule on them. A comparator that picks winners is the first reviewer marking its own work, and the human loses the disagreement that was the point.
- **Superseded 2026-08-08** by `docs/runbooks/multi-model-review.md` — "The referee settles disagreements". Abstaining cost more than it saved: every disagreement became an operator decision. The self-grading risk named above is now answered **structurally** — rulings are settled against a diff pinned to the reviewed commit, a ruling in the referee's own side's favour requires quoted `file:line`, a tie goes to the other reviewer, and every verdict is advice the author overrules at merge time. The pinned phrase survives in `review.yml` as the objection being answered; if it disappears, the reason those safeguards exist goes with it.

### `review-triggers-opened-and-ready-for-review`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:67`
- **Pin kind:** `regex` — pattern `types:[[:space:]]*\[[[:space:]]*opened,[[:space:]]*ready_for_review[[:space:]]*\]`
- **Lesson:** The automatic review fires on pull request open and on draft-to-ready only. Adding push-driven re-review turns one review per pull request into one per push and, combined with an agent that pushes fixes, closes a loop that runs away on a single runner.

### `review-concurrency-per-pr-number`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:77`
- **Pin kind:** `regex` — pattern `group:.*github\.event\.pull_request\.number`
- **Lesson:** The review concurrency group is scoped per pull request number. A single global group means work on one pull request evicts queued work on an unrelated one, and the platform gives no way to ask for a deeper queue.

### `review-concurrency-cancel-in-progress-true`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:78`
- **Pin kind:** `regex` — pattern `cancel-in-progress:[[:space:]]*true`
- **Lesson:** An advisory review that is not a required status check may be cancelled by a newer run on the same pull request, because nobody reads a superseded commit's review. This is the opposite setting from the queue that must never drop a request, and the two must not be conflated.

### `referee-window-not-recomputed`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:87`
- **Pin kind:** `regex` — pattern `Recomputing "now" in the referee`
- **Lesson:** The later comparison job must reuse the exact timestamp the first job recorded, exported as a job output, rather than computing its own. A freshly computed instant is after both reviews were posted, so the comparison window excludes the very comments it exists to compare, and reports nothing while going green.

### `review-silent-reviewer-worse-than-none`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:123`
- **Pin kind:** `regex` — pattern `A reviewer that reviews and stays silent is worse than no reviewer`
- **Lesson:** An agent that performs a review and prints it to the run log instead of posting it produces a green check that reads as reviewed-and-clean. The posting flag is what makes the review reach the pull request; the comment recording that is why nobody removes the flag as redundant.

### `review-standards-doc-paths`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:130`
- **Pin kind:** `semantic-manual`
- **Lesson:** A reviewer must be pointed at the repository's own written standards rather than left to invent generic ones, and those standards must be named by path so the instruction is checkable. Which paths they are is project-specific; that there ARE named paths is the lesson.
- **Concept:** Reviewer instructions cite the repository's own standards documents by path instead of relying on the model's general taste.
- **Replacement must preserve:** A reference to the template's own standards files by path, and the phrase distinguishing the repo's own standards from generic ones.
- **Discharged in:** .github/workflows/review.yml — same comment block: the reviewer is anchored to this repository's own standards by path (AGENTS.md, docs/runbooks/), not to generic best practice. See tests/harness-guards/semantic-discharges.md row 2.

### `review-fix-review-loop-guard-rationale`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:142`
- **Pin kind:** `regex` — pattern `review->fix->review loop`
- **Lesson:** The bot-sender exclusion on the fixer workflow is what stops a review triggering a fix triggering a review without end. The exclusion looks like an accident until this sentence is next to it, and removing it is a one-character change.

### `handoff-files-issue-not-comment`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:149`
- **Pin kind:** `semantic-manual`
- **Lesson:** The reviewer cannot reach the fixer by commenting, because the fixer ignores every comment sent by a bot and the reviewer posts as a bot. Opening an issue is the one path that reaches the fixer without weakening the loop guard, so the handoff files an issue rather than commenting.
- **Concept:** Cross-workflow handoff from a read-only reviewer to a write-capable fixer travels by filing an issue, precisely because the comment path is deliberately unreachable for bot senders.
- **Replacement must preserve:** The issue-filing handoff, plus a comment naming the newly-opened-issue trigger as the only auto-invoke path that carries no sender check, and stating that this is what keeps the loop guard intact.
- **Discharged in:** .github/workflows/review.yml — the handoff step files an issue because `issues: [opened]` is the one steward trigger with no bot-sender check, which is stated inline with the loop-guard reasoning. See tests/harness-guards/semantic-discharges.md row 3.

### `review-never-triggers-on-synchronize`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:154`
- **Pin kind:** `regex` — pattern `never on .synchronize.`
- **Lesson:** Never triggering on the push/synchronize event is what makes the fixer's push unable to bounce back into a fresh review. The comment is load-bearing: without the reason written down, adding the event later looks like an obvious improvement.

### `review-handoff-not-cancelled-not-always`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:159`
- **Pin kind:** `regex` — pattern `NOT always\(\)`
- **Lesson:** A post-run detector must be gated on not-cancelled rather than always. Deliberate cancellation is routine on a constrained runner, and an always-gated detector reports every cancellation as a lost result, which trains the reader to ignore the one warning that matters.

### `handoff-pat-required-default-token-inert`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:170`
- **Pin kind:** `regex` — pattern `does not start workflow runs from events created with GITHUB_TOKEN`
- **Lesson:** Events created with the default workflow token do not start further workflow runs. An issue filed with it is visible but inert: it wakes nobody. Any automation that hands work to another workflow by creating an event needs an elevated token, or it is a no-op that looks like success.

### `review-body-fetched-before-author-check`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:190`
- **Pin kind:** `regex` — pattern `Fetched BEFORE the author check`
- **Lesson:** Whether a review actually reached the pull request is checked before any branch on who authored the pull request. A lost review strands every author equally, and an author-first ordering exits reporting no action needed without ever discovering that nothing was posted.

### `carveout-silences-both-reviewers`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:224`
- **Pin kind:** `semantic-manual`
- **Lesson:** Both reviewer roles run the same underlying runner, so one supply-chain trip silences every reviewer at once. There is no surviving reviewer to defer to, which is exactly why the skip must be announced rather than absorbed.
- **Concept:** A shared execution path means a single guard trip removes the whole reviewing capability, not one of two opinions.
- **Replacement must preserve:** A statement that both reviewer roles share the same runner and are therefore both silenced by one trip, so no surviving opinion exists to fall back on.
- **Discharged in:** .github/workflows/review.yml — the supply-chain carve-out notice states that both reviewers are affected and that the green check means the job exited cleanly, not that anything was reviewed. See tests/harness-guards/semantic-discharges.md row 5.

### `carveout-says-so-on-the-pr`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:226`
- **Pin kind:** `regex` — pattern `in a run log nobody opens`
- **Lesson:** The carve-out is not a pass. It fires precisely on the changes where a second pair of eyes matters most, so it announces itself where the person merging will see it rather than in a run log nobody opens.

### `carveout-deliberately-narrow`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:228`
- **Pin kind:** `regex` — pattern `Deliberately narrow`
- **Lesson:** The carve-out is scoped as narrowly as possible: every other green-run-with-no-comment still escalates. Widening a known-benign exception is the standard way a detector stops detecting, so the narrowness is written down as a constraint rather than left to taste.

### `carveout-detects-workflow-file-edits`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:232`
- **Pin kind:** `regex` — pattern `startswith\("\.github/workflows/"\)`
- **Lesson:** The supply-chain carve-out is recognised by inspecting the changed file list for workflow-directory paths. This is a deliberate security control: a reviewing agent must not execute under continuous integration that the same pull request is editing.

### `carveout-warning-not-a-lost-review`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:236`
- **Pin kind:** `regex` — pattern `supply-chain guard`
- **Lesson:** A known, explained skip is distinguished from a lost result so the lost-result detector does not fire repeatedly on one benign cause. Without the distinction the detector files an identical issue on every run and gets muted, taking the real detections with it.

### `handoff-issue-body-warns-not-invoked`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:276`
- **Pin kind:** `regex` — pattern `NOT invoked by this issue`
- **Lesson:** The warning about a non-triggering token is written into the filed issue itself, not only into the run log, because nobody opens run logs for a job that reported success. The person reading the issue is the one who needs to know it woke nobody.

### `review-escalate-unrecognised-format`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:325`
- **Pin kind:** `regex` — pattern `unrecognised format`
- **Lesson:** The clean/not-clean decision is keyed on the phrase that means clean, not on the marker that means a finding. An unrecognised output format then counts as findings and gets escalated rather than silently dropped: wrong in the direction of one spurious escalation, never in the direction of another stranded finding.

### `review-clean-phrase-literal`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:329`
- **Pin kind:** `semantic-manual`
- **Lesson:** The clean-result test is a fixed-string match on one exact phrase the reviewer is required to emit. The phrase itself is tool-specific and will change with the runner, but it must stay a single literal fixed-string match, because a loosened or pattern-based test silently reclassifies findings as clean.
- **Concept:** Exactly one literal phrase means clean; everything else, including malformed output, means escalate.
- **Replacement must preserve:** A fixed-string (non-regex) match against the template's own clean phrase, with the surrounding comment explaining that keying on the clean phrase rather than the finding marker is what makes unrecognised output escalate.
- **Discharged in:** .github/workflows/review.yml + tools/review-handoff-decide.sh — the single-value test moved from a phrase in a review body to the referee's one-word merge verdict: `elif [ "$VERDICT" = "non-blocking" ]`, with every other value — blocking, undecided, empty, missing, unrecognised — waking the steward. See tests/harness-guards/semantic-discharges.md row 6.
- **Superseded 2026-08-09** by `docs/runbooks/multi-model-review.md` — "The merge verdict — who wakes the steward". The clean phrase was a code-review **plugin's** marker and nothing in this template emits it, so the test had one branch and every agent pull request woke the steward. **The concept above survives intact** — one value means clean, everything else escalates — and is the part to defend in any future replacement; only the thing being read changed.

### `dedupe-avoids-search-in-title`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:339`
- **Pin kind:** `regex` — pattern `in:title`
- **Lesson:** Server-side title search tokenises the query, so a number in a title is not anchored and a shorter number matches a longer one, while bracketed prefixes are dropped as punctuation. Both directions are harmful: a false match suppresses a real handoff, a false miss files a duplicate that costs another agent run.

### `dedupe-exact-literal-whole-line`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:355`
- **Pin kind:** `regex` — pattern `grep -cFx`
- **Lesson:** Deduplication is a client-side exact whole-line literal comparison: fixed-string, whole-line, with the no-match exit code absorbed so a strict shell does not turn no-match into a step failure. String equality has neither the false-match nor the false-miss failure mode of tokenised search.

### `handoff-warns-loudly-when-elevated-token-absent`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:395`
- **Pin kind:** `semantic-manual`
- **Lesson:** When the elevated token is missing the handoff still files the issue, but it says so loudly in the run log and in the issue body itself. Nothing may quietly read as handed off when it was not; a visible finding beats a lost one, and a silent degradation is indistinguishable from success.
- **Concept:** Degradation to the non-triggering default token is announced in both channels a human might read, rather than being absorbed silently.
- **Replacement must preserve:** A workflow-log warning annotation AND an in-issue warning block, both stating that the handoff did not invoke the downstream workflow and naming the secret that would fix it.
- **Discharged in:** .github/workflows/review.yml — a `::warning::` annotation AND a `> [!WARNING]` block in the issue body, both naming STEWARD_HANDOFF_PAT. See tests/harness-guards/semantic-discharges.md row 4.

### `reviewer-b-exports-ran-output`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:427`
- **Pin kind:** `regex` — pattern `ran:[[:space:]]*\$\{\{[[:space:]]*steps\.gate\.outputs\.run`
- **Lesson:** The optional second reviewer publishes whether it actually ran as a job output, so the downstream comparison can skip cleanly instead of comparing against a review that does not exist. Inferring it from job conclusion would read a clean skip as a successful review.

### `reviewer-b-unset-secret-degrades`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:435`
- **Pin kind:** `regex` — pattern `An unset secret must degrade`
- **Lesson:** An optional credential that is not configured degrades the pipeline to one reviewer, loudly, and must never turn into a red check on every pull request in the repository. Adding a second opinion may not be able to take the first one down.

### `reviewer-b-gate-warning-one-reviewer`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:441`
- **Pin kind:** `semantic-manual`
- **Lesson:** The degradation is announced with a warning annotation that states plainly how many reviewers actually ran. A quiet skip leaves a green check that reads as fully reviewed when half the reviewing capacity never executed.
- **Concept:** Missing optional credential produces a warning annotation naming the secret and stating the reduced level of assurance, then continues.
- **Replacement must preserve:** A warning annotation (not an error, not silence) that names the missing credential and says explicitly that this change got one reviewer rather than two.
- **Discharged in:** _null — GENUINELY OPEN, not merely unrecorded._ PARTIAL. The credential gate and the degrade-never-fail branch are in .github/workflows/review.yml. NOT landed: the literal 'one reviewer, not two' wording, which belongs in tools/run-agent.sh so it exists in one place, and run-agent.sh is not written yet. Left null on purpose: half a discharge is an open obligation. See tests/harness-guards/semantic-discharges.md row 7.

### `reviewer-b-must-not-read-first-review`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:470`
- **Pin kind:** `semantic-manual`
- **Lesson:** The second reviewer is forbidden from reading the first before forming its own findings. Agreement arrived at independently is evidence; agreement copied from the other reviewer is noise, and a checker that can only reach the same answer is not a check at all.
- **Concept:** Independence of the second opinion is enforced in the instructions, not merely hoped for.
- **Replacement must preserve:** An explicit prohibition on the challenge role reading the judge's review or any other existing comment before forming its own findings, with the reason (copied agreement is worthless) stated.
- **Discharged in:** .github/workflows/review.yml — reviewer B step comment states the prohibition and the reason: agreement it copied is noise. See tests/harness-guards/semantic-discharges.md row 8.

### `reviewer-marker-html-comment-prefix`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:470`
- **Pin kind:** `regex` — pattern `<!-- reviewer:`
- **Lesson:** Each reviewing role self-identifies with an HTML-comment marker as the exact first line of what it posts. The marker prefix is what every downstream consumer keys on, so it must survive genericisation character-for-character even though the role name inside it changes.

### `reviewer-marker-required-first-line`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:470`
- **Pin kind:** `semantic-manual`
- **Lesson:** The marker is required to be the exact first line, not merely present somewhere. First-line placement is what makes the marker cheap and unambiguous to detect and impossible to produce accidentally in prose.
- **Concept:** A mandatory, machine-readable, first-line role marker on every posted review.
- **Replacement must preserve:** An instruction that the first line of the posted comment is exactly the role marker, with the role token replaced by the template's role name, and the requirement described as mandatory rather than preferred.
- **Discharged in:** .github/workflows/review.yml — both reviewer step comments state the exact first-line marker as a non-optional part of the contract. See tests/harness-guards/semantic-discharges.md row 9.

### `reviewer-marker-same-bot-account`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:470`
- **Pin kind:** `semantic-manual`
- **Lesson:** Every agent posts from the same bot identity, so author is useless for telling roles apart, and status chatter lands in the same window from the same account. Only an in-body marker distinguishes a review from a progress note or from the other role's review.
- **Concept:** Author identity cannot discriminate between agent roles; the marker is the only discriminator, and the reason is recorded next to the requirement.
- **Replacement must preserve:** A sentence stating that all roles post from the same account and that without the marker nothing downstream can tell the reviews apart.
- **Discharged in:** .github/workflows/review.yml — 'Every role posts from the SAME bot account, so nothing downstream can tell two reviews apart by author; the marker is the only discriminator.' See tests/harness-guards/semantic-discharges.md row 10.

### `referee-gated-on-b-having-run`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:484`
- **Pin kind:** `semantic-manual`
- **Lesson:** The comparison job is skipped when the second reviewer did not run, gated on that reviewer's own published output rather than on its job conclusion. Skipping cleanly is correct; comparing one review against an empty file and reporting it as a comparison is not.
- **Concept:** A dependent aggregation job is gated on an explicit did-it-actually-run output from its dependency, and skips rather than fails when the dependency degraded.
- **Replacement must preserve:** The referee job's condition reading the challenge job's ran output, combined with the not-cancelled guard, so that a missing optional reviewer skips the comparison without failing the change.
- **Discharged in:** .github/workflows/review.yml — the referee's `if:` requires needs.challenge-review.outputs.ran == 'true', so an absent optional credential skips rather than fails. See tests/harness-guards/semantic-discharges.md row 11.

### `collector-per-page-filter-trap`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:525`
- **Pin kind:** `regex` — pattern `ONCE PER PAGE`
- **Lesson:** Combining pagination with a per-item filter applies the filter once per page and emits one array per page, so any take-the-last operation silently returns one result per page instead of one overall. The bug is invisible until a thread passes one page of comments, which is exactly when the collector has to be right.

### `collector-paginate-slurp`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:530`
- **Pin kind:** `regex` — pattern `--paginate[[:space:]]+--slurp`
- **Lesson:** Paged collection uses slurp to merge all pages into one document before any filtering. This is the fix for the per-page filter trap, and the two flags must stay adjacent on the fetch itself rather than being replaced by a per-item filter.

### `collector-single-endpoint-must-merge-both`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:530`
- **Pin kind:** `semantic-manual`
- **Lesson:** Top-level conversation comments and inline comments on a code line live on two different endpoints. A collector that reads only one of them can announce that a review is not present while that review has been sitting on the change the whole time, so both endpoints must be read and merged.
- **Concept:** Complete comment collection requires both the issue-comments endpoint and the pull-request review-comments endpoint, merged into one list before filtering.
- **Replacement must preserve:** Two paginated fetches, one per endpoint, merged before the role-marker filter runs. The source at this revision reads ONLY the issue-comments endpoint, so this is a gap the extraction must close rather than a behaviour it must copy; the discharge check is that the target reads both.
- **Discharged in:** .github/workflows/review.yml — both collectors read the issue-comments AND pull-request review-comments endpoints, slurp before filtering, merge, filter by the `<!-- reviewer: ... -->` role marker, and sort_by(.created_at) before `last`. The marker filter was MISSING on the first pass and this pin was wrongly recorded as discharged; behaviourally asserted now by tests/harness-guards/review-collector.bats. See tests/harness-guards/semantic-discharges.md row 12.

### `collector-jq-add-flattens-pages`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:534`
- **Pin kind:** `regex` — pattern `then add else \. end`
- **Lesson:** The slurped array-of-arrays is flattened back into one flat list before filtering, with a shape test so a single-page response is handled identically to a multi-page one. Filter after flattening, never before.

### `review-split-by-marker-not-ordering`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:542`
- **Pin kind:** `regex` — pattern `on a marker rather than on ordering`
- **Lesson:** Reviews are separated by their role marker, never by ordering such as newest-comment-wins. Ordering breaks the moment a retry, a status note or any unrelated comment lands in the same window from the same account, and it breaks silently by swapping two results rather than by erroring.

### `review-selection-must-not-use-exclusion`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:546`
- **Pin kind:** `semantic-manual`
- **Lesson:** Selecting one role by excluding the other role's marker is selection by negation: anything else the account posted in the window, including status chatter or a retry, is picked up as that role's review. Each role must be selected by its own positive marker.
- **Concept:** Positive per-role marker matching, not exclusion of the other role and not recency.
- **Replacement must preserve:** Both roles emitting their own marker, and both selections matching a positive marker. The source at this revision selects the first role by exclusion, so the extraction must tighten this rather than copy it.
- **Discharged in:** .github/workflows/review.yml — VARIANT, tightened: both roles emit their own marker and both are selected by positive match, where the source selected role A by excluding role B's marker. See tests/harness-guards/semantic-discharges.md row 13.

### `referee-one-missing-review-is-a-finding`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:555`
- **Pin kind:** `regex` — pattern `One review missing is a real finding`
- **Lesson:** When one of the two expected reviews is absent, the comparison step says which one is missing, on the change itself, rather than staying quiet. A green check must never read as reviewed twice when it was reviewed once.

### `referee-posts-via-plain-script-step`

- **Source:** `.github/workflows/<VENDOR-REVIEW-WORKFLOW>.yml:595`
- **Pin kind:** `regex` — pattern `quietly post nothing and still go green`
- **Lesson:** Publishing is done by a plain script step reading a file the agent wrote, not by the agent itself. An agent that decides for itself whether to publish is an agent that can quietly publish nothing and still report success.

---

## `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml` → `.github/workflows/steward.yml`

_30 entries: 28 mechanical, 2 semantic-manual._

### `steward-workflow-level-concurrency-is-wrong`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:83`
- **Pin kind:** `regex` — pattern `Workflow-level concurrency is evaluated when the RUN is created`
- **Lesson:** Workflow-level concurrency is evaluated when the run is created, before any job condition runs, so an event the workflow deliberately ignores still enters the group, still evicts whatever was pending, and only then skips. The group therefore has to be declared at job level.

### `steward-gate-runs-before-the-runner`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:115`
- **Pin kind:** `regex` — pattern `BEFORE the job reaches`
- **Lesson:** The trigger event cannot be filtered by comment author or content, so the filtering happens in a job condition that is evaluated before the job reaches a runner. Filtered events then show as instantly skipped instead of occupying the queue.

### `steward-auto-triage-needs-no-tag`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:119`
- **Pin kind:** `regex` — pattern `the one unconditional case`
- **Lesson:** The comment records that the newly-opened-issue path is deliberately the only unconditional trigger and that reassignment of an existing issue stays gated. Without it, someone tidying the condition adds a mention requirement and the handoff path goes dark.

### `steward-auto-triage-issues-opened-only`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:123`
- **Pin kind:** `regex` — pattern `github\.event_name == 'issues' && github\.event\.action == 'opened'`
- **Lesson:** Automatic triage fires on newly opened issues only, and that branch carries no mention requirement and no sender requirement. It is the one unconditional path, which is also what makes it usable as a cross-workflow handoff target.

### `steward-bot-sender-gate`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:125`
- **Pin kind:** `regex` — pattern `github\.event\.sender\.type != 'Bot'`
- **Lesson:** Every comment-driven and review-driven trigger requires that the sender is not a bot. Without it the reviewer's own output wakes the fixer, which pushes, which triggers another review, forever, on a runner that executes one job at a time.

### `steward-mention-required-on-every-other-trigger`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:125`
- **Pin kind:** `semantic-manual`
- **Lesson:** Apart from the newly-opened-issue path, every trigger requires an explicit mention in the body as well as a non-bot sender. Both halves are needed: the mention keeps ordinary conversation from invoking the agent, the sender check keeps agents from invoking each other.
- **Concept:** Mention-gating on every non-auto-triage trigger, alongside the bot-sender exclusion.
- **Replacement must preserve:** A body-contains check against the template's configurable mention token on each comment and review trigger, ANDed with the bot-sender exclusion rather than replacing it.
- **Discharged in:** .github/workflows/steward.yml — contains(..., vars.AGENT_MENTION || '@agent') ANDed with sender.type != 'Bot' on all three comment and review triggers. See tests/harness-guards/semantic-discharges.md row 14.

### `steward-review-comment-trigger-bot-gate`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:126`
- **Pin kind:** `regex` — pattern `pull_request_review_comment' && github\.event\.sender\.type != 'Bot'`
- **Lesson:** The bot-sender exclusion is applied to the inline-code-comment trigger too, not only to the top-level conversation trigger. A single unguarded event type is enough to reopen the loop, so the guard is repeated on every one of them.

### `steward-review-submitted-trigger-bot-gate`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:127`
- **Pin kind:** `regex` — pattern `pull_request_review' && github\.event\.sender\.type != 'Bot'`
- **Lesson:** The bot-sender exclusion is applied to the submitted-review trigger as well. Reviews submitted by an automated reviewer are the exact events that would otherwise wake the fixer and close the loop.

### `steward-concurrency-at-job-level`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:130`
- **Pin kind:** `regex` — pattern `skipped job never enters the group`
- **Lesson:** The concurrency group is declared at job level so the job condition is evaluated first: a skipped job never enters the group and therefore can never displace a pending request. Declared at workflow level, the workflow reliably generates its own evictions from events it then ignores.

### `steward-one-running-one-pending`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:133`
- **Pin kind:** `regex` — pattern `One running \+ one pending per group`
- **Lesson:** The platform keeps one running plus exactly one pending run per concurrency group, and a third event evicts the pending one with no run, no comment and no notification. The queue cannot be made deeper, which is why the residual eviction has to be reported instead of prevented.

### `steward-concurrency-group-per-issue-or-pr`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:137`
- **Pin kind:** `regex` — pattern `github\.event\.issue\.number \|\| github\.event\.pull_request\.number`
- **Lesson:** The queue is scoped per issue or pull request number, using a fallback because the two event families carry the number in different places. A single global group means a request on one thread silently evicts a pending request on an unrelated thread.

### `steward-cancel-in-progress-false`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:138`
- **Pin kind:** `regex` — pattern `cancel-in-progress:[[:space:]]*false`
- **Lesson:** A request that is already executing must not be killed by a newer request on the same thread, because the running job is doing real work with side effects. This is the opposite setting from an advisory check and the two must not be unified for consistency.

### `steward-record-job-start-instant`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:151`
- **Pin kind:** `regex` — pattern `date -u \+%Y-%m-%dT%H:%M:%SZ`
- **Lesson:** A timestamp is recorded before the agent runs so later steps can distinguish something this run produced from something already present. Without a recorded start instant, any after-the-fact scan either misses new output or counts old output as new.

### `steward-agent-invocation-step`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:153`
- **Pin kind:** `semantic-manual`
- **Lesson:** The agent is invoked through one clearly identified step so that everything around it, the gates before and the outcome checks after, stay vendor-independent. Swapping the runner must not require rewriting the guard logic that surrounds it.
- **Concept:** A single, replaceable agent-invocation step with all policy expressed outside it.
- **Replacement must preserve:** One invocation of the template's generic agent runner script, with the surrounding trigger gates, concurrency group, outcome check and eviction reporter unchanged.
- **Discharged in:** .github/workflows/steward.yml — one `tools/run-agent.sh steward` step replaces the vendor action block; gates, concurrency, outcome check and eviction reporter are unchanged around it. See tests/harness-guards/semantic-discharges.md row 15.

### `steward-prompt-folded-block-scalar`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:165`
- **Pin kind:** `regex` — pattern `opens a YAML comment`
- **Lesson:** Multi-line instruction text is written as a folded block scalar because in a plain scalar a space followed by a hash opens a YAML comment, which truncates the value mid-expression and makes the whole file unparseable. The failure appears as zero-job runs named by file path, not as a syntax error at the offending line.

### `steward-env-var-indirection-untrusted-input`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:201`
- **Pin kind:** `regex` — pattern `untrusted issue titles out of the shell`
- **Lesson:** User-supplied titles and bodies are passed through environment variables rather than interpolated into a shell command or a template expression. Interpolation puts attacker-controlled text into the command line, and the same mistake also reintroduces the YAML truncation hazard.

### `steward-open-pr-only-when-commits-exist`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:218`
- **Pin kind:** `regex` — pattern `git log origin/main\.\.origin/\$BRANCH`
- **Lesson:** A branch is only turned into a pull request when it actually carries commits ahead of the base. The agent reports a branch name whether or not anything was committed, so the branch name alone is not evidence that work happened.

### `steward-green-silent-run-unrecoverable`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:260`
- **Pin kind:** `regex` — pattern `nobody knows to look`
- **Lesson:** A red run is recoverable because someone re-runs it; a green run that produced nothing is not, because nobody knows to look. That asymmetry is the whole reason a visible-outcome check exists and deliberately fails the job.

### `steward-outcome-not-cancelled-not-always`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:261`
- **Pin kind:** `regex` — pattern `rather than .always\(\)`
- **Lesson:** The outcome check runs on not-cancelled rather than always, so a run an operator killed on purpose is not reported as a lost result. It still fires when the agent step fails, which is a genuine silent-outcome case.

### `steward-visible-outcome-step`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:266`
- **Pin kind:** `regex` — pattern `Require a visible outcome`
- **Lesson:** Automatic triage must leave something a human can see. A dedicated step asserts that, rather than trusting the agent to have spoken, because in the automatic path there is no tracking comment for it to update and posting depends on the model choosing to shell out.

### `steward-outcome-window-from-job-start`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:271`
- **Pin kind:** `regex` — pattern `steps\.jobstart\.outputs\.iso`
- **Lesson:** The comment scan is bounded by the instant recorded before the agent ran, so a comment that was already on the thread cannot be mistaken for output this run produced. Any comment inside the window counts, including a human reply, because the point is that the thread is not silently unanswered.

### `steward-outcome-paginated-comment-scan`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:280`
- **Pin kind:** `regex` — pattern `paginate\(github\.rest\.issues\.listComments`
- **Lesson:** The visible-outcome check scans comments with full pagination rather than reading the first page. On a long thread an unpaginated read misses exactly the newest comments, which are the only ones this check is about.

### `steward-outcome-branch-must-exist-remotely`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:289`
- **Pin kind:** `regex` — pattern `existence on the remote is the real signal`
- **Lesson:** The second acceptable outcome is a branch that genuinely exists on the remote, checked by querying it, not a branch name reported by the agent. The name is populated even when nothing was committed, so trusting it turns a silent run into a false pass.

### `steward-outcome-marker-comment`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:316`
- **Pin kind:** `regex` — pattern `<!-- steward-no-outcome:`
- **Lesson:** When neither visible outcome is present the workflow posts a marker comment keyed by run identifier, so the notice is both machine-detectable and non-duplicating. The marker also states that no conclusion about the request should be drawn from the silence.

### `steward-outcome-deliberate-failure`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:331`
- **Pin kind:** `regex` — pattern `core\.setFailed\(`
- **Lesson:** After posting the notice the step deliberately fails the run. Leaving it green would preserve the exact condition being detected, a run that looks successful and produced nothing, which is unrecoverable because nobody knows to look.

### `steward-eviction-reporter-exists`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:354`
- **Pin kind:** `regex` — pattern `evicted from the queue`
- **Lesson:** The residual eviction cannot be prevented, so the run that took the slot reports on the ones it displaced. An evicted run executes nothing and therefore cannot report itself; the requester otherwise sees no run, no comment and no notification, indistinguishable from the trigger never working.

### `steward-eviction-best-effort`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:356`
- **Pin kind:** `regex` — pattern `continue-on-error:[[:space:]]*true`
- **Lesson:** Reporting is best-effort by design: bookkeeping about dropped requests must never be able to fail the run that is doing the actual work. A reporter that can turn a successful run red will be deleted the first time it does.

### `steward-eviction-filters-pull-requests`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:388`
- **Pin kind:** `regex` — pattern `is load-bearing, not defensive`
- **Lesson:** The issue listing endpoint also returns pull requests, and a last-wins lookup keyed on title would let a pull request that copied the issue title overwrite the issue. The notice would then land somewhere the requester is not watching, and marker dedupe would make that permanent rather than self-correcting.

### `steward-eviction-signature-zero-jobs`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:410`
- **Pin kind:** `regex` — pattern `total_count > 0`
- **Lesson:** An evicted run has a precise signature: cancelled with zero jobs ever created, meaning it never reached a runner. A cancellation that left jobs behind was a deliberate human act and must not be reported, or the notice becomes noise.

### `steward-eviction-marker-dedupe`

- **Source:** `.github/workflows/<VENDOR-STEWARD-WORKFLOW>.yml:420`
- **Pin kind:** `regex` — pattern `<!-- steward-eviction:`
- **Lesson:** Eviction notices are deduplicated by a marker keyed on the evicted run identifier, so repeated scans over the same recent window do not post the same notice again. Marker-based dedupe is also what makes a misdirected notice permanent, which is why the target selection has to be right first.

---

## `.github/workflows/nightly-alert.yml` → `.github/workflows/nightly-alert.yml`

_11 entries: 10 mechanical, 1 semantic-manual._

### `notifier-issue-is-primary-channel`

- **Source:** `.github/workflows/nightly-alert.yml:19`
- **Pin kind:** `regex` — pattern `PRIMARY channel`
- **Lesson:** The primary alert channel is the one that needs no configuration beyond the token every workflow already has. Any chat or paging integration is additive, so a rotated or missing secret degrades the extra channel rather than the alert itself.

### `notifier-must-not-break-on-rotated-secret`

- **Source:** `.github/workflows/nightly-alert.yml:23`
- **Pin kind:** `regex` — pattern `lose the alert about losing the`
- **Lesson:** The notifier must not be the component that breaks when a credential is rotated, or you lose the alert about losing the alert. Ordering the channels so the zero-configuration one runs first and unconditionally is what enforces that.

### `notifier-callers-must-declare-issues-write`

- **Source:** `.github/workflows/nightly-alert.yml:26`
- **Pin kind:** `regex` — pattern `CALLERS MUST DECLARE`
- **Lesson:** Every caller of the reusable notifier has to declare the write permission at workflow level. This instruction is addressed to a file that does not exist yet, which is why it lives here in capitals rather than in a document nobody opens when adding a caller.

### `notifier-permissions-capped-by-caller`

- **Source:** `.github/workflows/nightly-alert.yml:27`
- **Pin kind:** `regex` — pattern `capped by the caller`
- **Lesson:** A reusable workflow can never hold more permission than its caller; token permissions narrow down a call chain and never widen. A caller that declares nothing, or declares only read, turns the notifier's write permission into an escalation request.

### `notifier-startup-failure-kills-whole-caller`

- **Source:** `.github/workflows/nightly-alert.yml:32`
- **Pin kind:** `regex` — pattern `startup_failure`
- **Lesson:** The rejected escalation is refused when the run graph is built, so the entire calling workflow never starts, gate job included. The gate therefore goes quiet rather than red, which is the worst possible failure mode for a check: absent, not failing.

### `notifier-new-caller-permissions-recipe`

- **Source:** `.github/workflows/nightly-alert.yml:35`
- **Pin kind:** `regex` — pattern `permissions: \{contents: read, issues: write\}`
- **Lesson:** The exact permission block a new caller needs is written out literally, together with the instruction to dispatch it once and confirm the run actually starts. A rule stated only in the abstract gets applied wrongly; a copyable block plus a verification step does not.

### `notifier-what-red-means-input`

- **Source:** `.github/workflows/nightly-alert.yml:50`
- **Pin kind:** `regex` — pattern `what_red_means`
- **Lesson:** Each caller must supply, as a required input, one line saying what a human should conclude from this gate being red. An alert that names a failing job without saying what it implies is an alert people learn to skim past.

### `notifier-job-declares-issues-write`

- **Source:** `.github/workflows/nightly-alert.yml:84`
- **Pin kind:** `regex` — pattern `issues:[[:space:]]*write`
- **Lesson:** The notifier job itself declares the write permission it needs, which is what makes the caller's declaration mandatory and the mismatch detectable. Removing it would make the caller requirement disappear along with the ability to file anything.

### `notifier-issue-title-per-gate`

- **Source:** `.github/workflows/nightly-alert.yml:100`
- **Pin kind:** `regex` — pattern `\[nightly\] \$\{gate\} is failing`
- **Lesson:** The tracking issue title is a fixed prefix plus the gate name, which is what makes the open-or-update lookup work. Change the shape of the title and every recurring failure starts a new thread instead of joining the existing one.

### `notifier-opens-or-updates-one-issue`

- **Source:** `.github/workflows/nightly-alert.yml:102`
- **Pin kind:** `regex` — pattern `One issue per gate`
- **Lesson:** One issue per gate, commented on rather than duplicated. A gate that stays red for a week should be one thread with seven comments, not seven issues nobody closes, because a flood of duplicates is functionally the same as no alert.

### `notifier-secondary-channel-degrades-to-summary`

- **Source:** `.github/workflows/nightly-alert.yml:168`
- **Pin kind:** `semantic-manual`
- **Lesson:** When the optional channel's credentials are absent the job writes a visible note into the run summary and exits successfully, rather than failing or staying quiet. A missing secret must be visible as a missing secret, never mistaken for having no alerts to send.
- **Concept:** Optional secondary alert channel degrades to an explicit, visible note without failing the notifier or burying the original failure.
- **Replacement must preserve:** A step-summary block that states the secondary channel was not used and why, an exit code of zero, and the same treatment for a delivery failure so a notifier fault never masks the gate failure it is reporting.
- **Discharged in:** .github/workflows/nightly-alert.yml — a missing webhook writes a $GITHUB_STEP_SUMMARY block and exits 0, and a delivery failure gets the same treatment. See tests/harness-guards/semantic-discharges.md row 16.

---

## `.github/workflows/pr-tests.yml` → `.github/workflows/pr-tests.yml`

_10 entries: 7 mechanical, 3 semantic-manual._

### `pr-tests-concurrency-cancel-true`

- **Source:** `.github/workflows/pr-tests.yml:11`
- **Pin kind:** `regex` — pattern `cancel-in-progress:[[:space:]]*true`
- **Lesson:** Superseded runs on the same reference are cancelled, because nobody reads the test result of a commit that has already been replaced. This is only safe where cancelling cannot strand a required check that branch protection is waiting on.

### `pr-tests-changes-gates-jobs-and-steps`

- **Source:** `.github/workflows/pr-tests.yml:14`
- **Pin kind:** `regex` — pattern `jobs/steps`
- **Lesson:** The change detection gates jobs and steps, both. The doubling is what makes a gate whose stack is absent report skipped rather than missing, and what stops a partially-relevant job from paying for toolchains it will not use.

### `pr-tests-changes-detector-job`

- **Source:** `.github/workflows/pr-tests.yml:17`
- **Pin kind:** `regex` — pattern `^[[:space:]]*changes:`
- **Lesson:** A cheap paths-filter job publishes which parts of the tree changed, and everything downstream reads its outputs. Centralising the decision in one job is what allows both jobs and steps to gate on the same answer.

### `pr-tests-runner-label-must-exist`

- **Source:** `.github/workflows/pr-tests.yml:22`
- **Pin kind:** `regex` — pattern `queues forever and this is a required check`
- **Lesson:** Routing a required check to a runner label that no runner offers does not fail; it queues forever, and the change becomes unmergeable. Any switchable runner selection needs this warning written next to it, because the failure looks like slowness rather than misconfiguration.

### `runner-selection-switchable-variable`

- **Source:** `.github/workflows/pr-tests.yml:25`
- **Pin kind:** `semantic-manual`
- **Lesson:** Runner selection is a repository variable with a hosted default, so moving work between hosted and self-hosted capacity is a settings change rather than a code change. The default must be the one that always has capacity, so an unset variable never strands a required check.
- **Concept:** Runner placement is configuration with a safe hosted fallback, not a hard-coded label.
- **Replacement must preserve:** A repository-variable-driven runs-on with a hosted-runner fallback on every job, using the template's own variable name.
- **Discharged in:** .github/workflows/pr-tests.yml — runs-on: ${{ vars.PR_RUNNER || 'ubuntu-latest' }} on every gate job. Deliberate exception: ci-health-watch.yml and the notifier it calls are pinned hosted. See tests/harness-guards/semantic-discharges.md row 18.

### `pr-tests-changes-outputs-per-stack`

- **Source:** `.github/workflows/pr-tests.yml:31`
- **Pin kind:** `semantic-manual`
- **Lesson:** The detector re-exports one boolean output per stack area so downstream jobs never reach into the filter step directly. The set of stacks is project-specific; the pattern of one named boolean per area, exported as a job output, is not.
- **Concept:** One named per-stack boolean output on the change-detector job, consumed by every gate.
- **Replacement must preserve:** A job outputs block re-exporting each filter result under a stable name, with the template's own stack names, so both job-level and step-level gates read from the job rather than from the step.
- **Discharged in:** .github/workflows/pr-tests.yml — changes.outputs.backend / .frontend consumed at BOTH job level and step level, which is what makes a stack-absent gate report skipped rather than never report. See tests/harness-guards/semantic-discharges.md row 17.

### `pr-tests-paths-filter-action`

- **Source:** `.github/workflows/pr-tests.yml:38`
- **Pin kind:** `regex` — pattern `dorny/paths-filter`
- **Lesson:** Change detection uses a dedicated paths-filter action rather than hand-rolled diff parsing, so the filter semantics match what the platform's own path matching does and there is one place to read the rules.

### `pr-tests-required-job-names`

- **Source:** `.github/workflows/pr-tests.yml:50`
- **Pin kind:** `semantic-manual`
- **Lesson:** Branch protection matches required checks by the reported context string, so job identifiers are an external contract, not an internal detail. Renaming one silently orphans the protection rule, which then waits forever for a context that no longer exists.
- **Concept:** Job identifiers double as required-check context strings and are part of the repository's public configuration surface.
- **Replacement must preserve:** The frozen two-tier job identifiers, each with a name field character-identical to its identifier, so the reported context is unambiguous and stable.
- **Discharged in:** .github/workflows/pr-tests.yml — VARIANT, stronger: the twelve frozen ids are in place with NO `name:` key at all, so the context IS the id and the two cannot diverge. See tests/harness-guards/semantic-discharges.md row 19.

### `clean-skip-job-level-gate`

- **Source:** `.github/workflows/pr-tests.yml:52`
- **Pin kind:** `regex` — pattern `^[[:space:]]{4}if:.*needs\.changes\.outputs\.`
- **Lesson:** Jobs are gated by a condition on the change-detector outputs, at job level. A job skipped this way still reports a conclusion, which satisfies a required status check; a job that never triggers reports nothing and blocks merging forever.

### `clean-skip-step-level-gate`

- **Source:** `.github/workflows/pr-tests.yml:74`
- **Pin kind:** `regex` — pattern `^[[:space:]]{8}if:.*needs\.changes\.outputs\.`
- **Lesson:** Steps inside a job are gated on the same change-detector outputs as the job itself. Without the step-level half, a job that runs for one stack still installs and executes the toolchain of every other stack, and the clean-skip guarantee only half holds.

---

## `.github/workflows/pr-mutation.yml` → `.github/workflows/pr-mutation.yml`

_11 entries: 11 mechanical, 0 semantic-manual._

### `mutation-zero-mutants-skips-announced-never-fails`

- **Source:** `.github/workflows/pr-mutation.yml:156`
- **Pin kind:** `regex` — pattern `Mutation gate skipped, not passed`
- **Lesson:** The diff scope is per file, not per hunk, so a comment-only or annotation-only Java change puts a class in scope that yields zero mutants — and PIT fails the entire build on its own No-mutations-found error before the 20-mutant sampling step can rule. A required gate then goes red for a Javadoc edit. Zero mutants is below the sample floor by definition: the run converts exactly that one PIT error into an announced skip, and every other failure stays a failure. _(Added 2026-08-13, found live on the template's own PR #22.)_

### `mutation-filter-in-job-never-in-trigger`

- **Source:** `.github/workflows/pr-mutation.yml:21`
- **Pin kind:** `regex` — pattern `Filter inside the job; never in the trigger`
- **Lesson:** Scope filtering belongs in a job condition, never in a workflow-level path trigger. The two look equivalent and are not, and the comment is the only thing standing between a future tidy-up and a repository where every unrelated change is permanently unmergeable.

### `mutation-min-sample-before-gating`

- **Source:** `.github/workflows/pr-mutation.yml:22`
- **Pin kind:** `regex` — pattern `MINIMUM number of mutants before enforcing a score`
- **Lesson:** A ratio computed over a handful of samples is noise, so the gate only enforces its threshold once the sample is large enough and reports without failing below that. Otherwise one unkillable but harmless case fails an otherwise good change.

### `mutation-required-check-never-reports`

- **Source:** `.github/workflows/pr-mutation.yml:35`
- **Pin kind:** `regex` — pattern `A required check that never reports does not fail`
- **Lesson:** A required check that never reports does not fail; it waits for a status that can never arrive, and with bypass disabled the change can never merge. Absent is strictly worse than red, because red is visible and absent looks like pending.

### `mutation-skipped-satisfies-required-check`

- **Source:** `.github/workflows/pr-mutation.yml:38`
- **Pin kind:** `regex` — pattern `reports conclusion "skipped"`
- **Lesson:** A job skipped by its own condition still reports a conclusion, and that conclusion satisfies a required check. This is the mechanism that makes clean-skip work, and it is the difference between a gate that is absent and one that is honestly not applicable.

### `mutation-scope-job-name-must-be-unique`

- **Source:** `.github/workflows/pr-mutation.yml:55`
- **Pin kind:** `regex` — pattern `Deliberately NOT named`
- **Lesson:** Two workflows must not publish check runs under the same name, because branch protection matches required checks by name string and duplicate names make that matching ambiguous. Check names are a global namespace across the repository, not per file.

### `mutation-branch-protection-matches-by-name`

- **Source:** `.github/workflows/pr-mutation.yml:56`
- **Pin kind:** `regex` — pattern `branch protection matches required checks by name string`
- **Lesson:** Branch protection matches required checks by name string. That single fact is why job identifiers cannot be renamed casually, why two jobs may not share a name, and why a name field that differs from its identifier is a trap.

### `mutation-scope-script-is-self-tested`

- **Source:** `.github/workflows/pr-mutation.yml:155`
- **Pin kind:** `regex` — pattern `report a green mutation check over an empty`
- **Lesson:** The script that decides what the gate examines is tested on every run, before it is trusted. A silently broken scope computation narrows the gate to nothing and reports success over an empty set, which is indistinguishable from passing.

### `mutation-gate-needs-no-extra-toolchain`

- **Source:** `.github/workflows/pr-mutation.yml:216`
- **Pin kind:** `regex` — pattern `toolchain the job does not install`
- **Lesson:** The enforcement step depends on nothing beyond the shell, because it previously relied on an interpreter this job never installs and died with command-not-found after the expensive work had already passed. Depending on a toolchain the job does not install is how a gate goes quietly missing.

### `mutation-missing-report-fails`

- **Source:** `.github/workflows/pr-mutation.yml:221`
- **Pin kind:** `regex` — pattern `Fail, do not skip`
- **Lesson:** A missing analysis report, at a point where the run should have produced one, fails the job rather than being treated as nothing to check. Treating a missing artefact as a pass is precisely how a gate stops gating while still reporting green.

### `mutation-min-sample-constant`

- **Source:** `.github/workflows/pr-mutation.yml:234`
- **Pin kind:** `regex` — pattern `MIN_MUTANTS=`
- **Lesson:** The minimum sample size is a named constant next to the threshold it protects, so both numbers are visible and adjustable in one place rather than being buried in a formula.

---

## `.github/workflows/pr-validation.yml` → `.github/workflows/pr-validation.yml`

_4 entries: 2 mechanical, 2 semantic-manual._

### `validation-workflow-paths-filter-must-be-converted`

- **Source:** `.github/workflows/pr-validation.yml:5`
- **Pin kind:** `semantic-manual`
- **Lesson:** This workflow still uses a workflow-level path trigger, which is exactly the pattern the diff-scoped gate documents as unusable for a required check: on a non-matching change no check run is ever created, so branch protection waits for a status that never arrives.
- **Concept:** Trigger-level path filtering is replaced by a change-detector job feeding a job-level condition, so the check can be made required.
- **Replacement must preserve:** No workflow-level paths block; instead a change-detector job whose output gates each job, so an unrelated change reports skipped rather than never reporting. This is a correction the extraction must make, not a behaviour to copy.
- **Discharged in:** .github/workflows/pr-validation.yml — no workflow-level paths:; a migration-scope detector job feeds a job-level if:. See tests/harness-guards/semantic-discharges.md row 20.

### `validation-required-set-is-named`

- **Source:** `.github/workflows/pr-validation.yml:19`
- **Pin kind:** `semantic-manual`
- **Lesson:** The comment enumerates the current required check set at the point where that set is being relied on. Without the list written down, the next person cannot tell whether the cancellation setting above is still safe, and a wrong guess makes changes unmergeable.
- **Concept:** Any decision that depends on which checks are required names those checks inline, next to the decision.
- **Replacement must preserve:** An enumeration of the template's own required check contexts, using the frozen two-tier job identifiers, at the point where the cancellation setting is justified.
- **Discharged in:** .github/workflows/pr-validation.yml — both tiers' context strings enumerated inline at the cancel-in-progress justification, with the two not-yet-in-the-tree contexts marked. See tests/harness-guards/semantic-discharges.md row 21.

### `validation-cancel-safe-only-for-non-required`

- **Source:** `.github/workflows/pr-validation.yml:22`
- **Pin kind:** `regex` — pattern `would leave the PR unmergeable`
- **Lesson:** Cancelling superseded runs is only safe for checks branch protection is not waiting on. Cancelling a required check leaves it reported as cancelled and the change unmergeable, so the decision has to be made per workflow against the current required set.

### `validation-error-annotation-on-failure`

- **Source:** `.github/workflows/pr-validation.yml:92`
- **Pin kind:** `regex` — pattern `::error::`
- **Lesson:** Failures emit an error annotation that names the likely causes, so the reason surfaces in the checks user interface rather than only in scrolled-past log output. A gate that fails without saying what it means gets re-run rather than fixed.

---

## `.github/workflows/secret-scan.yml` → `.github/workflows/secret-scan.yml`

_3 entries: 2 mechanical, 1 semantic-manual._

### `secret-scan-job-name-differs-from-id`

- **Source:** `.github/workflows/secret-scan.yml:21`
- **Pin kind:** `semantic-manual`
- **Lesson:** When a job declares a name, the required-check context is that name and not the job identifier. A job whose identifier and name differ is the documented usual failure mode: branch protection is configured against one string while the run reports the other, and the check appears to never report.
- **Concept:** The reported check context is the job name when present, otherwise the identifier; a mismatch between the two silently orphans branch protection.
- **Replacement must preserve:** Every job's name field made character-identical to its identifier, so identifier and reported context can never diverge. The source job here has an identifier and a name that differ, which is the defect the template fixes rather than copies.
- **Discharged in:** .github/workflows/secret-scan.yml — the job is fast-secret-scan with no `name:` key, so id and context can never diverge. Upstream defect fixed. See tests/harness-guards/semantic-discharges.md row 22.

### `secret-scan-full-history-required`

- **Source:** `.github/workflows/secret-scan.yml:30`
- **Pin kind:** `regex` — pattern `fetch-depth:[[:space:]]*0`
- **Lesson:** Secret scanning needs the full history, not a shallow checkout, because a credential committed earlier and removed later is still in the history and still leaked. A shallow clone makes the scan pass on exactly the repositories that most need it to fail.

### `secret-scan-stale-temp-on-persistent-runner`

- **Source:** `.github/workflows/secret-scan.yml:39`
- **Pin kind:** `regex` — pattern `TMPDIR:-/tmp`
- **Lesson:** A persistent runner keeps temporary files between runs, so a leftover file from a previous run makes the next scan fail on a path collision. The cleanup reads the operating system's temporary directory variable rather than assuming a hard-coded path, and runs only where the runner is persistent.

---

## `.github/workflows/<CI-HEALTH-WATCH>.yml` → `.github/workflows/ci-health-watch.yml`

_10 entries: 9 mechanical, 1 semantic-manual._

> **CAPTURED AFTER ITS GENERIC COUNTERPART EXISTED — read these more weakly than the
> rest of this inventory.** This source file was skipped in the original capture pass.
> The quotations below are verbatim from the same read-only source at the same
> `source_head` as every other entry, so they are as accurate. What is different is the
> `pattern`s: they were chosen to fit target text that was already on disk, so they could
> not have gone red whatever the extraction had done. They guard a FUTURE regression;
> they are not evidence that this extraction preserved anything. The distinction is the
> whole reason this inventory is written before a substitution rather than after one, and
> a section that quietly failed to mention its own exception would be a worse omission
> here than anywhere else in the file.

### `ci-health-watchdog-must-not-run-on-the-runner-it-watches`

- **Source:** `.github/workflows/<CI-HEALTH-WATCH>.yml:9`

- **Pin kind:** `regex` — pattern `cannot report that runner dead`

- **Lesson:** A watchdog scheduled onto the runner it watches goes down with that runner, and its silence is then indistinguishable from health. Pinning it to the hosted runner is the only thing that makes it survive the failure it exists to report. It reads as an inconsistency to anyone standardising runners across the repository, which is exactly why the reason must stay written next to it.


### `ci-health-runs-on-the-hosted-runner-literally`

- **Source:** `.github/workflows/<CI-HEALTH-WATCH>.yml:56`

- **Pin kind:** `regex` — pattern `^ +runs-on: ubuntu-latest`

- **Lesson:** The runner is a hard-coded hosted label, not one of the switchable runner variables every other job here uses. Routing this job through a runner variable is a one-line change that silently converts the watchdog into part of the thing it watches.


### `ci-health-could-not-check-is-not-an-incident`

- **Source:** `.github/workflows/<CI-HEALTH-WATCH>.yml:27`

- **Pin kind:** `regex` — pattern `COULD NOT CHECK" IS NOT AN INCIDENT`

- **Lesson:** An expired credential, a provider 5xx or a rate-limit blip mean the watch is BLIND, not that something is wrong. Collapsing those into the alert path pages several times a day about a problem that is not there, and the channel learns to skim past the alert that matters. The accepted cost is stated openly: a silently broken credential stops the paging entirely.


### `ci-health-two-accumulators-alerts-versus-warnings`

- **Source:** `.github/workflows/<CI-HEALTH-WATCH>.yml:81`

- **Pin kind:** `regex` — pattern `Two accumulators, deliberately separate`

- **Lesson:** The warning path and the alert path are two separate accumulators on purpose. Merging them is the mechanical way the rule above gets undone: one variable means one severity, and every could-not-check becomes an incident.


### `ci-health-curl-must-fail-on-http-error`

- **Source:** `.github/workflows/<CI-HEALTH-WATCH>.yml:72`

- **Pin kind:** `regex` — pattern `makes curl fail \(exit 22\)`

- **Lesson:** Without curl's fail-on-HTTP-error flag the client exits 0 and hands the JSON error body to the parser, which makes an expired credential indistinguishable from a real finding. The whole warning-versus-alert split above depends on this one flag being present.


### `ci-health-unarmed-announces-that-it-checked-nothing`

- **Source:** `.github/workflows/<CI-HEALTH-WATCH>.yml:24`

- **Pin kind:** `regex` — pattern `::notice title=CI health watch not armed::`

- **Lesson:** Until its credential exists the watch checks nothing, and it must say so rather than exit green in silence. A check that quietly did nothing looks exactly like a check that found nothing, and an unarmed watchdog that reports green is the most expensive kind of false confidence available.


### `ci-health-quota-exhaustion-is-a-known-state-not-a-mystery`

- **Source:** `.github/workflows/<CI-HEALTH-WATCH>.yml:112`

- **Pin kind:** `regex` — pattern `At 100% every hosted job dies within seconds with no runner assigned`

- **Lesson:** When the hosted-minutes allowance runs out, every hosted job dies within seconds with no runner assigned. That is a perfectly predictable state, but with nothing naming it in advance it gets debugged as a mystery infrastructure fault. Alerting at a threshold, with the remediation written into the alert text, turns a cliff into a planned move onto your own runner.


### `ci-health-failure-is-red-in-the-actions-tab-too`

- **Source:** `.github/workflows/<CI-HEALTH-WATCH>.yml:145`

- **Pin kind:** `regex` — pattern `red in the Actions tab`

- **Lesson:** The job exits non-zero on a real finding rather than only writing a summary, so the finding is red where people already look and not only in whatever channel the notifier reaches. A watchdog whose only output is a step summary is a watchdog nobody reads.


### `ci-health-states-its-own-running-cost`

- **Source:** `.github/workflows/<CI-HEALTH-WATCH>.yml:18`

- **Pin kind:** `regex` — pattern `Cost, stated because an inert watchdog is not a free one`

- **Lesson:** The watchdog consumes the very allowance it is watching, and the header says how much. An optional scheduled job whose cost is not written down is one an adopter cannot make an informed decision about keeping, and the cadence is the only dial they have.


### `ci-health-finding-must-reach-a-human-outside-the-actions-tab`

- **Source:** `.github/workflows/<CI-HEALTH-WATCH>.yml:127`

- **Pin kind:** `semantic-manual`

- **Lesson:** A red run visible only in the Actions tab is most of the way to a check that is not running. The source pushed to one specific chat vendor; what may not change is that a finding here leaves the repository through some pushed channel as well as failing the job.

- **Concept:** An operational watchdog's finding reaches a human through the repository's own notifier, not only through a red square in the Actions tab.

- **Replacement must preserve:** A dedicated notifier job for this gate alone, calling the shared reusable notifier with its own gate name, severity and runbook, gated on the watch job's result being 'failure' rather than on failure().

- **Discharged in:** .github/workflows/ci-health-watch.yml — job `notify-ci-health` calls ./.github/workflows/nightly-alert.yml with gate 'CI health — runner liveness and hosted minutes' at S2, gated on needs.watch-ci-health.result == 'failure', and passes runner: 'ubuntu-latest' explicitly. The explicit runner is part of the discharge, not decoration: a called workflow's runs-on cannot be overridden by its caller, so without it the alarm for a dead self-hosted runner queued on the dead runner. See tests/harness-guards/semantic-discharges.md row 23.


## `AGENTS.md` → `AGENTS.md`

### `second-brain-read-path-checklist-step`

- **Source:** `AGENTS.md:136`

- **Pin kind:** `literal` — `4. Read \`docs/knowledge/INDEX.md\`. If a line's symptoms match your task, read those`

- **Lesson:** The second brain (docs/knowledge/) only pays for itself if every agent actually reads the index at session start, cheaply, before doing its own work. Losing this checklist step silently turns every card the fleet writes into dead weight nobody ever reads, while the write path (the chief of staff's retrospective) keeps right on producing cards.


## `.agents/prompts/chief-of-staff.md` → `.agents/prompts/chief-of-staff.md`

### `second-brain-distiller-two-questions`

- **Source:** `.agents/prompts/chief-of-staff.md:63`

- **Pin kind:** `literal` — `- **You are also the second brain's distiller — two added questions, same evidence`

- **Lesson:** The chief of staff is the ONLY agent that writes knowledge cards, in its self-gated retrospective. Losing this line from its prompt silently removes the fleet's only write path to docs/knowledge/ — the index and read path would keep working, but nothing would ever add to them, and a system nobody feeds looks identical to one nobody built, from the outside.


## `docs/runbooks/agent-modes.md` → `docs/runbooks/agent-modes.md`

### `second-brain-standing-decision-ownership`

- **Source:** `docs/runbooks/agent-modes.md:347`

- **Pin kind:** `literal` — `  written by exactly one.** Every agent reads \`docs/knowledge/INDEX.md\` after its ledger`

- **Lesson:** The operator-facing standing decision is what makes docs/knowledge/'s write ownership (chief-of-staff only, human-merged) an instruction rather than a convention an agent could quietly drift from. This file is the only source of operator instructions (AGENTS.md), so a rule that exists only in a plan document or a runbook prose paragraph elsewhere is not binding on any agent until it is also stated here.


## `.agents/prompts/docs-freshness.md` → `.agents/prompts/docs-freshness.md`

### `docs-freshness-sweep-all-fix-batched`

- **Source:** `.agents/prompts/docs-freshness.md:16`

- **Pin kind:** `literal` — `1. **Sweep ALL tracked markdown**, every run — never a sample and never a subset chosen`

- **Lesson:** Docs freshness only gets full coverage by sweeping every file every run and fixing in small batches, never by scoping to a sample. Losing the sweep-all requirement turns this into an agent that only ever notices the files it happened to look at last time, which is indistinguishable from no coverage guarantee at all.


## `.agents/prompts/backlog-groomer.md` → `.agents/prompts/backlog-groomer.md`

### `backlog-groomer-evidence-only-closes`

- **Source:** `.agents/prompts/backlog-groomer.md:20`

- **Pin kind:** `literal` — `2. **Evidence-only closes.** Close an issue only on a recorded \`fix_verified\` entry from`

- **Lesson:** Closing on a merge alone re-creates the exact failure agent-modes.md's standing decision exists to prevent: an issue marked done while production has not moved. Losing this line from the groomer's own prompt would let its per-run close cap keep working while the closes themselves stopped meaning anything.


## `.agents/prompts/test-gap.md` → `.agents/prompts/test-gap.md`

### `test-gap-ratchet-only-tightens`

- **Source:** `.agents/prompts/test-gap.md:16`

- **Pin kind:** `literal` — `1. **The ratchet only tightens.** Every floor in \`floors.yml\` may only ever move up`

- **Lesson:** This is the one agent with standing write access to floors.yml's neighbourhood, so the one-directional constraint has to live in its own prompt and not only in docs/QUALITY-GATES.md's policy — an agent that can propose both directions is an agent that can eventually make the ratchet mean nothing.


## `.agents/prompts/dependency-steward.md` → `.agents/prompts/dependency-steward.md`

### `dependency-steward-one-upgrade-per-run`

- **Source:** `.agents/prompts/dependency-steward.md:20`

- **Pin kind:** `literal` — `2. **One bounded upgrade pull request per run**, never a batch. Pick the single upgrade`

- **Lesson:** A batched dependency-upgrade pull request is unreviewable and untraceable when something breaks — nobody can tell which of ten bumps caused the regression. Losing the one-per-run cap would let this agent silently regress into exactly the kind of change nothing else in the gauntlet is built to review well.


## `.agents/prompts/release-drafter.md` → `.agents/prompts/release-drafter.md`

### `release-drafter-never-tags-or-publishes`

- **Source:** `.agents/prompts/release-drafter.md:12`

- **Pin kind:** `literal` — `human can read and decide about. **You never tag, publish, or otherwise perform a`

- **Lesson:** Every other agent in this fleet is barred from merging its own work; the release drafter's equivalent boundary is that it drafts and a human tags. Losing this line is the one way this agent's job description could silently expand into the one irreversible action nothing else in the fleet is allowed to take either.
