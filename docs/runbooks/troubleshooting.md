# Troubleshooting, written as symptoms

The thing you're actually seeing, matched to the thing actually causing it. For a red
gate specifically, `qa-procedures.md` has the deeper triage process; this page is for
everything else.

| Symptom | Cause |
|---|---|
| My pull request hangs waiting on a check that never reports | A required status check is sitting behind a workflow-level `paths:` filter instead of a job-level `if:` — the workflow never even runs, so no check run is ever created. See `docs/runbooks/branch-protection.md`. |
| I mentioned the agent and nothing happened | Either the comment came from a bot account (the steward's job-level `if:` refuses any `sender.type == 'Bot'`), or a third event landed in the same concurrency group and evicted the pending run — GitHub keeps one running plus one pending per group. |
| The referee says a review is missing, but I can see it in the PR | The collector is reading the wrong comment endpoint. A review can land as a top-level issue comment or as an inline PR review comment — the collector must query both and merge them; if you changed a prompt's output shape, check it still lands where the collector looks. |
| A review comment isn't picked up even though it's clearly there | Check that its first line is the exact marker `<!-- reviewer: <role> -->` — selection is by marker, never by ordering or exclusion, so a comment without one is invisible to the collector on purpose. |
| A gate I expected to run says "skipped" | That is very likely correct, not a bug — a stack-absent gate (e.g. no `frontend/` present) is supposed to report `skipped`, which GitHub counts as satisfying a required check. If you expected it to actually run, check the `changes` job's paths-filter output. |
| My PR failed a coverage/mutation gate on a brand-new repo | You have not run `tools/measure-floors.sh` yet — floors ship as the `unset` sentinel and print "floor not yet calibrated" rather than gating anything, so a hard failure here means something else regressed, not the floor itself. |
| The steward triaged an issue but posted nothing and the run is red | That is the intended failure mode, not a bug: a run that produced no visible outcome (no comment, no pushed branch) fails deliberately with a marker comment, rather than reporting green having done nothing. |
| An agent's scheduled routine just stopped running | Check whether GitHub auto-disabled the schedule after ~60 days of inactivity (`README.md` section 6) before assuming the agent itself broke. |
| The gauntlet fails on a fresh clone with no code changes of mine | Run `tools/check-placeholders.sh` — a leftover unresolved placeholder token in a file `tools/init.sh` didn't reach is far more likely than a real regression. |
| An agent doesn't seem to know something it "should" | Check `docs/knowledge/INDEX.md` — the second brain only holds what the chief of staff has distilled so far. A miss there costs nothing (the agent works as it would without it), but it's worth knowing the index is small and grows slowly on purpose. |
