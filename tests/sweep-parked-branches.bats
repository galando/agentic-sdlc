#!/usr/bin/env bats
#
# tools/sweep-parked-branches.sh — the parked-branch sweep's behavioural guards.
#
# Each test builds a REAL bare remote plus a full clone and stubs only `gh`, so
# every git judgement (ancestry, ages, commit ranges, saved-body discovery) runs
# the production code path. The gh stub answers from per-test fixture files and
# records every invocation, so "the sweep did NOT call create" is an assertion,
# not an absence of evidence.
#
# The invariants under test are the three the script's header names — never a
# second pull request, never resurrect squash-merged work, never take a branch
# from a live run — plus the token doctrine: a failed lookup is never "no pull
# request", only a REFUSAL may trigger the GITHUB_TOKEN fallback, and a run
# that fell back must exit 1 and say DEGRADED (a green degraded run is how an
# unreviewed pull request once sat 12 hours with no checks upstream).
#
# Commit timestamps are written with an EXPLICIT +0000 zone. The upstream
# harness wrote them zoneless, so on a UTC+2 machine a branch meant to be 10
# minutes old was stored as 130 minutes old — green in CI (which runs UTC) and
# wrong on every laptop.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SWEEP="$REPO_ROOT/tools/sweep-parked-branches.sh"

setup() {
  TMP="$BATS_TEST_TMPDIR"
  export GH_STUB_DIR="$TMP/gh-stub"
  mkdir -p "$GH_STUB_DIR" "$TMP/bin"

  # --- the gh stub -----------------------------------------------------------
  # Dispatches on the subcommand. Behaviour is driven by files in GH_STUB_DIR:
  #   graphql_script / create_script / ready_script — one line per call:
  #     ok | refuse (HTTP 403) | transient (HTTP 502); empty/missing means ok.
  #   prlist.<branch with / -> _> — JSON for `gh pr list --head <branch>`;
  #     missing means []. prlist_fail (any content) fails every pr list call.
  #   read_repo — "refuse" makes `gh api repos/...` fail.
  # Every call appends its argv to calls.log; pr create records last_title and
  # copies the body file to last_body.md.
  cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_STUB_DIR/calls.log"
pop() { # pop <file> — print first line and remove it; "ok" when absent/empty
  local f="$GH_STUB_DIR/$1" line
  line="$(head -n1 "$f" 2>/dev/null)"
  if [ -f "$f" ]; then tail -n +2 "$f" > "$f.tmp" && mv "$f.tmp" "$f"; fi
  printf '%s' "${line:-ok}"
}
answer() { # answer <verdict>
  case "$1" in
    refuse)    echo "gh: Resource not accessible by personal access token (HTTP 403)" >&2; exit 1 ;;
    transient) echo "gh: HTTP 502 bad gateway" >&2; exit 1 ;;
    *)         return 0 ;;
  esac
}
case "$1" in
  api)
    if [ "$2" = "graphql" ]; then
      answer "$(pop graphql_script)"; echo '{"data":{}}'; exit 0
    fi
    [ "$(cat "$GH_STUB_DIR/read_repo" 2>/dev/null)" = "refuse" ] \
      && { echo "gh: HTTP 401 bad credentials" >&2; exit 1; }
    echo "octo/example"; exit 0 ;;
  pr)
    case "$2" in
      list)
        [ -f "$GH_STUB_DIR/prlist_fail" ] && { echo "gh: HTTP 500" >&2; exit 1; }
        head=""; prev=""
        for a in "$@"; do [ "$prev" = "--head" ] && head="$a"; prev="$a"; done
        f="$GH_STUB_DIR/prlist.${head//\//_}"
        if [ -f "$f" ]; then cat "$f"; else echo "[]"; fi
        exit 0 ;;
      create)
        prev=""
        for a in "$@"; do
          [ "$prev" = "--title" ] && printf '%s' "$a" > "$GH_STUB_DIR/last_title"
          [ "$prev" = "--body-file" ] && cp "$a" "$GH_STUB_DIR/last_body.md"
          prev="$a"
        done
        answer "$(pop create_script)"
        echo "https://example.invalid/pr/99"; exit 0 ;;
      ready)
        answer "$(pop ready_script)"; exit 0 ;;
    esac ;;
esac
exit 0
STUB
  chmod +x "$TMP/bin/gh"
  export PATH="$TMP/bin:$PATH"
  export GH_TOKEN="preferred-token"
  unset GITHUB_TOKEN FALLBACK_GH_TOKEN GITHUB_STEP_SUMMARY 2>/dev/null || true
  export GITHUB_REPOSITORY="octo/example"

  # --- the repos -------------------------------------------------------------
  git init --quiet --bare "$TMP/origin.git"
  git init --quiet -b main "$TMP/seed"
  git -C "$TMP/seed" config user.email t@example.invalid
  git -C "$TMP/seed" config user.name t
  git -C "$TMP/seed" remote add origin "$TMP/origin.git"
  commit_at "$TMP/seed" 20000 "chore: initial commit"
  git -C "$TMP/seed" push --quiet origin main
  # A fresh bare repo's HEAD points at master; aim it at main so clones of it
  # (the shallow-clone test in particular) check out a real branch.
  git -C "$TMP/origin.git" symbolic-ref HEAD refs/heads/main
  git clone --quiet "$TMP/origin.git" "$TMP/repo"
}

# commit_at <repo> <age-minutes> <subject> [file [content]]
commit_at() {
  local repo="$1" age_min="$2" subject="$3" file="${4:-file.txt}" content="${5:-x}"
  local ts=$(( $(date -u +%s) - age_min * 60 ))
  mkdir -p "$repo/$(dirname "$file")"
  printf '%s\n' "$content" >> "$repo/$file"
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="@$ts +0000" GIT_COMMITTER_DATE="@$ts +0000" \
    git -C "$repo" commit --quiet -m "$subject"
}

# make_branch <name> <age-minutes> <subject> [file [content]] — branch off main
make_branch() {
  local name="$1"; shift
  git -C "$TMP/seed" checkout --quiet main
  git -C "$TMP/seed" checkout --quiet -b "$name"
  commit_at "$TMP/seed" "$@"
  git -C "$TMP/seed" push --quiet origin "$name"
  git -C "$TMP/seed" checkout --quiet main
}

run_sweep() {
  cd "$TMP/repo"
  run "$SWEEP" --no-fetch "$@"
}

refresh_clone() { # after seeding more branches
  git -C "$TMP/repo" fetch --quiet --prune origin
}

@test "refuses to start without any token — a tokenless lookup would open duplicates" {
  make_branch agent/fix-x-20260820 200 "fix(x): a real fix"
  refresh_clone
  cd "$TMP/repo"
  unset GH_TOKEN
  run "$SWEEP" --no-fetch
  [ "$status" -eq 2 ]
  [[ "$output" == *"no GitHub token"* ]]
}

@test "refuses a shallow clone — commit ranges there are fiction" {
  git clone --quiet --depth 1 "file://$TMP/origin.git" "$TMP/shallow"
  cd "$TMP/shallow"
  run "$SWEEP" --no-fetch
  [ "$status" -eq 2 ]
  [[ "$output" == *"shallow clone"* ]]
}

@test "opens a ready pull request for a branch with no pull request at all" {
  make_branch agent/fix-x-20260820 200 "fix(x): return an error on upstream timeout"
  refresh_clone
  run_sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"opened   agent/fix-x-20260820"* ]]
  grep -q "gh pr create" "$GH_STUB_DIR/calls.log"
  # Ready for review, never a draft: a draft gets CI and no review.
  ! grep -q -- "--draft" "$GH_STUB_DIR/calls.log"
  [ "$(cat "$GH_STUB_DIR/last_title")" = "fix(x): return an error on upstream timeout" ]
  grep -q "pushed its work and never opened a pull request" "$GH_STUB_DIR/last_body.md"
}

@test "the saved report's heading wins over the parking commit, minus its stage marker" {
  make_branch agent/fix-y-20260820 300 "fix(y): stop the counter drifting"
  # The parking commit is the NEWEST thing on the branch — a title taken from
  # the tip would describe the accident, not the work.
  git -C "$TMP/seed" checkout --quiet agent/fix-y-20260820
  commit_at "$TMP/seed" 200 "docs: save PR body — API token expired mid-run" \
    ".temper/autonomy-reports/counter-drift.md" \
    "# SHIP-PENDING-COMMIT — stop the quota counter drifting (#753)"
  git -C "$TMP/seed" push --quiet origin agent/fix-y-20260820
  git -C "$TMP/seed" checkout --quiet main
  refresh_clone
  run_sweep
  [ "$status" -eq 0 ]
  [ "$(cat "$GH_STUB_DIR/last_title")" = "stop the quota counter drifting (#753)" ]
  # The saved body itself is embedded for the reviewer.
  grep -q "autonomy-reports/counter-drift.md" "$GH_STUB_DIR/last_body.md"
}

@test "a generic report heading is rejected — the first behaviour-changing commit names the work" {
  make_branch agent/fix-z-20260820 300 "fix(z): reject empty payloads"
  commit_at "$TMP/seed" 200 "docs: save PR body" \
    ".temper/autonomy-reports/z.md" "# Summary"
  git -C "$TMP/seed" push --quiet origin agent/fix-z-20260820
  refresh_clone
  run_sweep
  [ "$status" -eq 0 ]
  [ "$(cat "$GH_STUB_DIR/last_title")" = "fix(z): reject empty payloads" ]
}

@test "a branch inside the grace window is left alone — its own run may still be working" {
  make_branch agent/fix-young-20260820 10 "fix(a): young work"
  refresh_clone
  run_sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"waiting  agent/fix-young-20260820"* ]]
  ! grep -q "gh pr create" "$GH_STUB_DIR/calls.log"
}

@test "a branch past the age cap is not resurrected" {
  make_branch agent/fix-old-20260701 $((20 * 1440)) "fix(b): ancient work"
  refresh_clone
  run_sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"too old  agent/fix-old-20260701"* ]]
  ! grep -q "gh pr create" "$GH_STUB_DIR/calls.log"
}

@test "a branch merged with a real merge commit is covered — no lookup, no create" {
  make_branch agent/fix-merged-20260820 400 "fix(c): merged work"
  git -C "$TMP/seed" checkout --quiet main
  git -C "$TMP/seed" merge --quiet --no-ff --no-edit agent/fix-merged-20260820
  git -C "$TMP/seed" push --quiet origin main
  refresh_clone
  run_sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"already shown: 1"* ]]
  ! grep -q "gh pr" "$GH_STUB_DIR/calls.log"
}

@test "an open non-draft pull request means nothing to do" {
  make_branch agent/fix-open-20260820 400 "fix(d): shown work"
  refresh_clone
  tip="$(git -C "$TMP/repo" rev-parse origin/agent/fix-open-20260820)"
  printf '[{"number":5,"state":"OPEN","url":"u","headRefOid":"%s","isDraft":false}]' "$tip" \
    > "$GH_STUB_DIR/prlist.agent_fix-open-20260820"
  run_sweep
  [ "$status" -eq 0 ]
  ! grep -q "gh pr create" "$GH_STUB_DIR/calls.log"
  ! grep -q "gh pr ready" "$GH_STUB_DIR/calls.log"
}

@test "a closed pull request whose head is this exact tip means closed on purpose" {
  make_branch agent/fix-closed-20260820 400 "fix(e): declined work"
  refresh_clone
  tip="$(git -C "$TMP/repo" rev-parse origin/agent/fix-closed-20260820)"
  printf '[{"number":6,"state":"CLOSED","url":"u","headRefOid":"%s","isDraft":false}]' "$tip" \
    > "$GH_STUB_DIR/prlist.agent_fix-closed-20260820"
  run_sweep
  [ "$status" -eq 0 ]
  ! grep -q "gh pr create" "$GH_STUB_DIR/calls.log"
}

@test "commits pushed after a pull request closed are LEFTOVER for a human, never auto-opened" {
  make_branch agent/fix-leftover-20260820 400 "fix(f): merged, then grew"
  refresh_clone
  old_tip="$(git -C "$TMP/repo" rev-parse origin/agent/fix-leftover-20260820)"
  git -C "$TMP/seed" checkout --quiet agent/fix-leftover-20260820
  commit_at "$TMP/seed" 300 "fix(f): one more thing"
  git -C "$TMP/seed" push --quiet origin agent/fix-leftover-20260820
  git -C "$TMP/seed" checkout --quiet main
  refresh_clone
  printf '[{"number":7,"state":"MERGED","url":"u","headRefOid":"%s","isDraft":false}]' "$old_tip" \
    > "$GH_STUB_DIR/prlist.agent_fix-leftover-20260820"
  run_sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"leftover agent/fix-leftover-20260820"* ]]
  ! grep -q "gh pr create" "$GH_STUB_DIR/calls.log"
}

@test "a failed lookup is UNKNOWN and fails the run — never read as 'no pull request exists'" {
  make_branch agent/fix-unknown-20260820 400 "fix(g): unknowable work"
  refresh_clone
  : > "$GH_STUB_DIR/prlist_fail"
  run_sweep
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNKNOWN  agent/fix-unknown-20260820"* ]]
  ! grep -q "gh pr create" "$GH_STUB_DIR/calls.log"
}

@test "a quiet draft is marked ready; a draft whose run may still be working is not" {
  make_branch agent/fix-draft-20260820 200 "fix(h): quiet draft"
  make_branch agent/fix-fresh-20260820 100 "fix(i): busy draft"
  refresh_clone
  t1="$(git -C "$TMP/repo" rev-parse origin/agent/fix-draft-20260820)"
  t2="$(git -C "$TMP/repo" rev-parse origin/agent/fix-fresh-20260820)"
  printf '[{"number":8,"state":"OPEN","url":"u","headRefOid":"%s","isDraft":true}]' "$t1" \
    > "$GH_STUB_DIR/prlist.agent_fix-draft-20260820"
  printf '[{"number":9,"state":"OPEN","url":"u","headRefOid":"%s","isDraft":true}]' "$t2" \
    > "$GH_STUB_DIR/prlist.agent_fix-fresh-20260820"
  run_sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"ready    agent/fix-draft-20260820"* ]]
  [[ "$output" == *"draft #9, last commit"* ]]
  grep -q "gh pr ready 8" "$GH_STUB_DIR/calls.log"
  ! grep -q "gh pr ready 9" "$GH_STUB_DIR/calls.log"
}

@test "dry-run reports what it would open and calls nothing" {
  make_branch agent/fix-dry-20260820 200 "fix(j): dry-run work"
  refresh_clone
  run_sweep --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would open  agent/fix-dry-20260820"* ]]
  ! grep -q "gh pr create" "$GH_STUB_DIR/calls.log"
}

@test "a transient error on the capability probe never triggers the fallback" {
  make_branch agent/fix-blip-20260820 200 "fix(k): work behind a blip"
  refresh_clone
  export FALLBACK_GH_TOKEN="fallback-token"
  printf 'transient\n' > "$GH_STUB_DIR/graphql_script"
  run_sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"not evidence about the token"* ]]
  [[ "$output" != *"DEGRADED"* ]]
  [[ "$output" == *"opened   agent/fix-blip-20260820"* ]]
}

@test "a refused probe falls back to GITHUB_TOKEN, reports DEGRADED, and exits 1" {
  make_branch agent/fix-degraded-20260820 200 "fix(l): degraded-run work"
  refresh_clone
  export FALLBACK_GH_TOKEN="fallback-token"
  export GITHUB_STEP_SUMMARY="$TMP/summary.md"
  # First probe (preferred token) refused; the re-probe on the fallback passes.
  printf 'refuse\nok\n' > "$GH_STUB_DIR/graphql_script"
  run_sweep
  # The pull request still opens — a visible PR beats a lost one — but the run
  # must NOT be green: an unreviewed PR that nothing checks needs a human told.
  [ "$status" -eq 1 ]
  [[ "$output" == *"opened   agent/fix-degraded-20260820"* ]]
  [[ "$output" == *"DEGRADED:"* ]]
  grep -q "DEGRADED" "$TMP/summary.md"
}

@test "a refusal at create time retries once on the fallback — after re-checking no PR appeared" {
  make_branch agent/fix-retry-20260820 200 "fix(m): refused work"
  refresh_clone
  export FALLBACK_GH_TOKEN="fallback-token"
  # create_pull_request tries --label then labelless per attempt: two refusals
  # burn attempt one, then the fallback attempt succeeds.
  printf 'refuse\nrefuse\nok\n' > "$GH_STUB_DIR/create_script"
  run_sweep
  [ "$status" -eq 1 ]
  [[ "$output" == *"opened   agent/fix-retry-20260820"* ]]
  [[ "$output" == *"with GITHUB_TOKEN"* ]]
  # The re-check between refusal and retry is rule 1: never a second PR.
  grep -q "gh pr list .*--limit 5" "$GH_STUB_DIR/calls.log"
}

@test "a transient error at create time is FAILED, not retried on the fallback" {
  make_branch agent/fix-flaky-20260820 200 "fix(n): work behind a 502"
  refresh_clone
  export FALLBACK_GH_TOKEN="fallback-token"
  printf 'transient\ntransient\n' > "$GH_STUB_DIR/create_script"
  run_sweep
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED   agent/fix-flaky-20260820"* ]]
  [[ "$output" == *"says nothing about the token"* ]]
  [[ "$output" != *"DEGRADED"* ]]
}

@test "the open cap defers, and says what it dropped" {
  make_branch agent/fix-one-20260820 300 "fix(o): first"
  make_branch agent/fix-two-20260820 200 "fix(p): second"
  refresh_clone
  run_sweep --limit 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"deferred:      1"* ]]
}
