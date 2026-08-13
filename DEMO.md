# The capability demo — build it, then show every capability

<!-- placeholder: {{PRODUCT_NAME}} — the system your agents watch. tools/init.sh fills it in. -->

This is the script for Part C of the second-brain/SDLC-extension design (PR #18's
plan document; the implementation spec — intent, plan, gate ledger — lives at
`.temper/specs/second-brain-and-sdlc-extension/`): a
reproducible walk-through that triggers **every** capability of this harness on
demand, in a fixed order, from a clean template instantiation — the existing agent
loop, the second brain (`docs/knowledge/`), and the five SDLC-extension agents
(Part B of the same design). It exists so an adopter or a
viewer does not have to wait on organic activity to see the whole system work; every
stop below is something you deliberately trigger, and every stop leaves an artifact —
a comment, a pull request, a ledger line, a card — that stays in the repository
afterwards as browsable evidence.

If you only want to adopt the template for real product work, you do not need this
file — start at `README.md` section 3 instead. This file is for demonstrating the
system itself.

---

## C1 — Build (≈ one hour, mostly waiting on runs)

1. **Create the repository from the template**, keeping the bundled example product
   (`examples/`) — the gates need something real to measure, and `tools/measure-floors.sh`
   refuses to run without it.
2. **Run `tools/adopt.sh`** and answer the interview: product name, provider, a model
   per role (`judge` / `execute` / `challenge` — pick `challenge` from a **different
   model family** to unlock the adversarial second review), alert channel, mention
   trigger. Re-run it until `tools/status.sh` reports clean.
3. **Confirm the floors calibrated** against the example product's own baseline —
   `tools/adopt.sh` offers to run `tools/measure-floors.sh` and open the calibration
   pull request; merge it once the FAST tier is green.
4. **Confirm the ledger branch exists** — `tools/adopt.sh` offers
   `tools/create-ledger-branch.sh`; it is idempotent if you run it again by hand.
5. **Branch protection, last** — `docs/runbooks/branch-protection.md`, the FAST tier
   contexts (including `fast-knowledge-lint`), "do not allow bypassing" ticked.
6. **Verify the harness before touching anything else:**
   ```bash
   bats tests/ tests/harness-guards/
   actionlint .github/workflows/*.yml
   tools/run-agent.sh --list-agents
   ```
7. **Check credentials per role**, and dry-run every agent — this prints the exact
   argv each agent would run and invokes nothing, which is the safest thing to put on
   camera:
   ```bash
   tools/run-agent.sh --check-credentials health
   tools/run-agent.sh --check-credentials chief-of-staff
   tools/run-agent.sh --check-credentials challenger   # role: challenge
   for agent in health quality audit chief-of-staff challenger \
                docs groomer testgap deps release; do
     tools/run-agent.sh "$agent" --dry-run
   done
   ```
8. **Seed the demo state** — this is what makes every stop below triggerable on
   demand instead of waiting for organic activity:
   - one planted bug in the example product, with a reproducing test path;
   - one dead link planted in a runbook (docs freshness will find it, C2 stop 9);
   - three stale issues: one with a merged-but-unverified fix, one duplicate pair, one
     past its severity SLA (backlog groomer, C2 stop 10);
   - one dependency with a known available upgrade (dependency steward, C2 stop 12);
   - floors armed a few points below measured, so the test-gap agent has a
     legitimate raise to propose (C2 stop 11).
9. **Enable the agents you intend to show**, one at a time, per README section 6
   ("Turning on the routines") — flip `enabled: true` for that agent's entry in
   `.agents/config.yml`, dry-run it once via `workflow_dispatch`, then let its cron
   take over.

---

## C2 — The capability tour (fixed order, 13 stops)

Each stop names the trigger, what to show on screen, and the artifact that proves it
worked.

1. **Steward triage** — open an issue describing the planted bug (a newly opened
   issue invokes the steward automatically, no mention needed). **Show:** the triage
   comment.
2. **Spec pipeline** — the resulting fix is built through the configured pipeline:
   root cause written *before* the patch, then the failing test, then the code.
   **Show:** the spec artifacts and gate 21 (`fast-spec-artifacts`) green on the pull
   request.
3. **Two reviews + referee** — the judge review, the challenge review from a
   different model family, the referee's merge of the two. **Show:** the review
   threads; point at the role names (`judge`, `challenge`), never a vendor.
4. **The gauntlet** — the FAST checks on the pull request, including the ratchet
   guards and the second brain's own gate. **Show:** the checks tab, every context
   reporting, `fast-knowledge-lint` among them.
5. **The human merge** — the click that nothing bypasses.
6. **Fix verification** — the filing agent's next run reads the end-state signal and
   records `fix_verified` (`"verdict":"moved"`). **Show:** the ledger line; contrast
   "the reload succeeded" against "the system serves the fix" (`docs/knowledge/merge-is-not-deploy.md`
   is the card that distills exactly this contrast).
7. **Second brain, write path** — the chief of staff's every-second-run
   retrospective distills the planted bug into a card. **Show:** the card pull
   request (the diff of the card plus its `INDEX.md` line); merge it.
8. **Second brain, read path** — re-open a *variant* of the planted bug. **Show:**
   the next session's narrative citing the card it read from `docs/knowledge/`, and
   the token math (index + one card, versus re-deriving the fix from nothing).
9. **Docs freshness** — its weekly run finds the planted dead link. **Show:** the
   sweep count in the ledger entry (`metrics.files_swept`) and the ≤ 5-finding
   docs-only pull request.
10. **Backlog groomer** — the three seeded issues resolved three ways: an
    evidence-bearing verified-close, a duplicate link, an SLA breach handed off to
    the chief of staff's brief. **Show:** the appended, dated status section on the
    stale issue — never a rewrite of the original report.
11. **Test gap** — the floor-raise pull request with headroom evidence; merge it.
    **Show:** the ratchet guard now enforcing the higher floor (`bats
    tests/harness-guards/` still green against the new number).
12. **Dependency steward** — the one bounded upgrade pull request, with the CVE
    delta in the ledger's `metrics`. **Show:** the changelog excerpt and the
    failing-without/passing-with test evidence in the pull-request body.
13. **Liveness + the brief** — `tools/ledger.sh latest` (the watcher ring), the
    alert channel's one-line-per-agent day, and the chief of staff's brief showing:
    nightly gate conclusions with dates, the stale-knowledge line (any
    `docs/knowledge/` card past its 90-day `verified` window), and the
    decisions-needed list. Then the **negative proof**: disable one agent's schedule
    for a day (`enabled: false`) and show the missed-heartbeat alert — a dead agent
    and a healthy agent never look the same.

---

## C3 — Demo acceptance criteria

- **Every stop is reproducible from a clean template instantiation** by following
  this file — no organic waiting required for any of the 13 stops.
- **The whole tour's artifacts remain in the repository afterwards** as browsable
  evidence: the issues, the pull requests, the ledger lines (`agent-ledger` branch),
  and the knowledge cards. Nothing in this tour is cleaned up after recording.
- This file itself is covered by the docs freshness agent's weekly sweep like every
  other tracked markdown file — a command in here that stops matching the tree is a
  finding the agent itself will surface, not something that silently rots.
