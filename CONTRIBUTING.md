# Contributing to this template

This file is about contributing **to the template itself** — the harness under
`.agents/`, `.github/`, `tools/`, `floors.yml` and the docs at the repo root. If you are
adopting the template for your own product, see `README.md`'s quickstart and
`ADOPTING.md` instead; this file will not help you set up your fork.

## Why upstream at all

Template repositories do not merge — an adopter's fork diverges the moment
`tools/init.sh` runs, and there is no ongoing pull relationship after that (see
`CHANGELOG.md`). That means a lesson learned in one fork — a workflow edge case, a
missing guard, a rule that turned out to be wrong — either comes back here, or it dies in
that one fork and every other adopter re-learns it the hard way. **Every incident-derived
rule in this repository exists because something went wrong once and someone wrote down
why**, never deleted the reasoning, only rewritten it as a neutral lesson. Keeping that
property intact is the actual point of this file.

## Before you open a pull request

1. **Read `AGENTS.md`.** It is the binding ruleset for every agent session against this
   repository, human or automated, and it applies here in full.
2. **A spec directory is required** for any fix or feature (gate 21,
   `.github/workflows/spec-artifacts.yml`) — see `tools/spec-pipeline/CONTRACT.md`. If
   your build pipeline genuinely cannot produce one, say
   `temper: unavailable — <real reason>` in the pull request body instead; gate 21 passes
   with a warning annotation recording the reason, never silently.
3. **Never lower a floor, widen an exclude, or suppress a rule to make a check pass.**
   That is what gate 9's ratchet guards exist to catch, and it is a human decision with a
   written justification, not something a contributor (agent or otherwise) does to get
   green. See `docs/QUALITY-GATES.md`'s ratchet policy.
4. **Fill in the gate-integrity attestation** in `.github/pull_request_template.md`: a
   checkbox stating that no floor was lowered, no rule suppressed, no exclude widened —
   and if one had to move, that it moved in the direction the ratchet allows.
5. **Run `tools/check-deidentified.sh` and `tools/check-placeholders.sh` locally** before
   opening the pull request; `fast-repo-hygiene` runs both again and will not let a
   regression through quietly.

## Adding a new placeholder

Every `{{UPPER_SNAKE_CASE}}` <!-- placeholder: this occurrence documents the naming convention itself, not a real token --> token needs a one-line annotation at its point of use —
`# placeholder: <what belongs there>` in shell/YAML, `<!-- placeholder: ... -->` in
Markdown — on the **same line** as the token. `tools/gen-adopting.sh` fails the build if
it finds a token with no annotation, and `fast-repo-hygiene` runs it and diffs
`ADOPTING.md` against the committed copy: a placeholder without a row in the map cannot
be merged. Do not hand-edit the table between `<!-- PLACEHOLDERS:BEGIN -->` and
`<!-- PLACEHOLDERS:END -->` in `ADOPTING.md` — edit the annotation and re-run the
generator.

If the new token is something `tools/init.sh` should ask about and substitute, add it to
the `TOKENS` array and the interview (`ask ...` line) in `tools/init.sh`. If it is
resolved by something else entirely (a different tool, never, or only per some other
unit of work — see `ADOPTING.md`'s "Resolved by" column for the existing examples), say
so in the annotation instead.

## Adding a new lesson to gate 22 (the harness guards)

If you find a workflow edge case that is not already text-pinned, the flow is:

1. Add an entry to `tests/harness-guards/pins.json` — `id`, `source_file`, `source_line`
   (if extracted from a known incident), `quoted_source_string`, `why` (the neutral
   lesson, not the specifics of the original incident), `expected_in`, and `pin_kind`
   (`literal`, `regex`, or `semantic-manual`).
2. Run `tests/harness-guards/gen-pin-tests.sh` to regenerate
   `tests/harness-guards/pins.generated.bats` from it. Do not hand-edit the generated
   file — `fast-repo-hygiene` diffs it against a fresh regeneration.
3. **Verify the guard is real**: delete the string it pins from the workflow and confirm
   the new test goes red. A guard never seen red is a guard not known to work.
4. `semantic-manual` entries (a string that must change during genericization, so no
   literal pin is possible) do not get a generated assertion — they are named in the
   suite's own output as hand-discharged, never silently omitted.

## Adding a new gate

Add it to the inventory table in `docs/QUALITY-GATES.md` with a context string, a tier
(FAST if it needs no container, browser, or service; FULL otherwise), and a one-line
"what a failure means". Wire the job into the relevant workflow with a **job-level**
`if:` for stack-absence — never a workflow-level `paths:` filter on anything that will
ever be a required check (see "Required checks — the rule that bites" in the same file).
If it carries a numeric floor, it ships as the `unset` sentinel and is wired into
`floors.yml` / `tools/render-floors.sh`, never a hardcoded number.

## Style

- **Rewrite incident-derived comments; never delete them.** The specifics of what went
  wrong can be genericized away; the reasoning that survived it cannot, or the next
  person deletes the guard along with the comment that would have stopped them.
- **No vendor name outside `tools/providers/` and `.agents/config.yml`.** Everywhere
  else, address a model by its role (`judge`, `execute`, `challenge`).
- **A second list is a drift risk.** If you are about to hand-maintain a second copy of
  something already defined once (an agent list, a token classification, a floor value),
  look for the existing single source of truth first — `tools/lib/config.sh`,
  `floors.yml`, `tools/init.sh`'s own `TOKENS` array — and read from it instead.
