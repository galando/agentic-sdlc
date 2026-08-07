# What & why

<!-- One paragraph: the problem, and the behavior change. Link the issue.
     Plain language, please: what was wrong, what changed, why. Short
     sentences, everyday words, no fluff. Agents: this is binding
     (AGENTS.md guardrail 6, docs/runbooks/agent-communication-style.md). -->

Closes #

## Behavior change

<!-- What an end user (or an operator) can now do, or no longer suffers.
     If this is pure refactor/infra, say "no user-visible change". -->

## How it was verified

<!-- Name the evidence, not the intention. Gate output beats prose.
     Built through the spec pipeline? Link the `.temper/specs/<slug>/` directory.
     Agents: the pipeline is the default for fixes and features (AGENTS.md
     guardrail 7) — if it was not used, say why HERE, in this exact form:
     `temper: unavailable — <the real reason>`. Gate 21 reads that line, and
     "availability is a finding, not an excuse": say what was unreachable and
     why. See .github/agent-temper-headless.md. -->

<!-- placeholder: {{BUILD_PIPELINE}} — the spec pipeline this repo builds through.
     tools/init.sh fills it in. -->

<!-- The three checkboxes below name REFERENCE-STACK commands (Java/Maven +
     React/npm). On another stack, replace the commands and keep the claims:
     "the blocking gauntlet is green locally", "the integration tier is green if
     this touches persistence", "lint and coverage are green". docs/QUALITY-GATES.md
     has the stack-agnostic contract for each gate. -->

- [ ] Backend gauntlet green locally: `cd examples/backend && mvn clean verify -DskipITs`
      (unit tests + coverage ratchet + architecture rules + build hygiene)
- [ ] Backend integration tests green (if the change touches persistence/schema):
      `cd examples/backend && mvn clean verify -Dgroups=docker -DexcludedGroups=live`
- [ ] Frontend gauntlet green locally: `cd examples/frontend && npm run lint -- --max-warnings 0 && npm run test:coverage -- --run`
- [ ] New behavior is covered by a test that **fails without the change**
      (assertion on the real outcome, not on a mock echoing itself)
- [ ] Acceptance scenario added/updated if this changes a domain rule

## Gate integrity

<!-- These two boxes are the ratchet policy made into an act someone has to
     perform. A floor that drops in an unrelated diff is invisible; a floor that
     drops here has a name attached to it. See docs/QUALITY-GATES.md. -->

- [ ] **No floor was lowered.** No coverage or mutation threshold, architecture
      rule, lint rule, or build-hygiene rule was relaxed, suppressed, excluded,
      or disabled to make this pass. (If one had to move, it moved **up**.)
- [ ] No lint-disable, warning suppression, or coverage/mutation exclusion was
      added — or, if unavoidable, it is justified in a code comment **and**
      called out below for a human decision.

<!-- If you ticked the exception above, explain here. A reviewer must
     explicitly accept it; agents may never do this on their own
     (see docs/QUALITY-GATES.md and AGENTS.md). Remember: suppression is not
     passing. A skipped test or a widened exclude that turns a red gate green
     counts as lowering a floor. -->

## Risk & rollback

<!-- Blast radius, and how to undo it. Migrations: is it reversible?
     Feature-flagged? Which flag, and what is its intended state on merge? -->

---

Full gate inventory and the ratchet policy: [docs/QUALITY-GATES.md](../docs/QUALITY-GATES.md).
QA procedure (what to run, how to read a red gate): [docs/runbooks/qa-procedures.md](../docs/runbooks/qa-procedures.md).
