#!/usr/bin/env bash
#
# sweep-parked-branches.sh — open the pull requests agent runs could not open.
#
# WHAT WAS WRONG (upstream, 2026-08-16). In the running system this template was
# extracted from, six agent branches carried finished, tested work that no pull
# request ever showed to anyone. Each run wrote the code, pushed the branch, and
# then got HTTP 401 from the GitHub API because its token had expired part-way
# through the run. `git push` uses a different credential, so the code reached
# the server and the report did not. Two agents then wrote "nothing is in
# flight" about work that existed, because they checked open issues and open
# pull requests — not branches. One of the invisible branches fixed a
# data-corruption bug that kept corrupting data while its fix sat unread.
#
# WHAT THIS DOES. On a schedule it lists every `agent/*` branch on the remote
# and makes the two API calls the dead token could not:
#
#   - No pull request at all -> open one, READY for review, so the two automatic
#     reviewers run on it like on any other pull request.
#   - An open DRAFT that has gone quiet -> mark it ready. `review.yml` fires on
#     `opened` and `ready_for_review` and skips drafts, so a draft gets CI and
#     no review. Marking it ready is an API call at the END of a run — the same
#     call, with the same expired token, that failed to open the pull request.
#     The run cannot make it; this job can.
#
# So a run that dies reaches the same end state as a healthy one, without a
# human. Only the merge is left, which is a human's job anyway (AGENTS.md
# guardrail 2 — which also carries the prevention half of this lesson: open the
# draft EARLY, while the token is young).
#
# THREE THINGS IT MUST NEVER DO, in order of what they would cost:
#
#   1. Open a second pull request for a branch that already has one. Every
#      decision hangs on a `gh pr list` answer, so a lookup that FAILS stops
#      that branch and fails the run. "Could not ask" must never read as "no
#      pull request exists".
#   2. Re-open squash-merged work. A squash-merged branch is never an ancestor
#      of the base branch, so it stays "ahead" of it forever. Being ahead of
#      the base is therefore NOT evidence of parked work — only the absence of
#      a pull request is.
#   3. Take a branch away from a run that is still going. The push happens well
#      before the pull request, so a branch minutes old is normal. Branches
#      inside --grace-minutes are left alone, and a draft is only promoted after
#      --promote-after minutes of silence — long enough that a run doing an hour
#      of tests without committing is not promoted out from under itself.
#
# Harness: tests/sweep-parked-branches.bats (runs in pr-tests.yml's `bats
# tests/` invocation). Runbook: docs/runbooks/parked-branch-sweep.md.
#
# Usage:
#   GH_TOKEN=... tools/sweep-parked-branches.sh [options]
#
#   --dry-run             report only, open nothing
#   --limit N             open at most N pull requests this run (default 10)
#   --max-age-days N      ignore branches older than this (default 14)
#   --grace-minutes N     ignore branches younger than this (default 90)
#   --promote-after N     mark a quiet agent draft ready after N minutes
#                         (default 180)
#   --draft               open new pull requests as drafts (default: ready for
#                         review, so the reviewers run)
#   --remote NAME         default origin
#   --base NAME           default main
#   --prefix STR          branch prefix to sweep (default agent/)
#   --no-fetch            skip `git fetch` (the harness and CI checkouts)
#
# Exit codes: 0 nothing needs a human · 1 something does (a lookup, a create or
# a promotion failed, or the run fell back to GITHUB_TOKEN) · 2 the run could
# not start (no token, no gh, no jq, a shallow clone).
#
set -uo pipefail

REMOTE=origin
BASE=main
PREFIX='agent/'
MAX_AGE_DAYS=14
GRACE_MINUTES=90
PROMOTE_AFTER=180
LIMIT=10
DRAFT=0
DRY_RUN=0
FETCH=1

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)        DRY_RUN=1 ;;
        --no-fetch)       FETCH=0 ;;
        --limit)          LIMIT="$2"; shift ;;
        --max-age-days)   MAX_AGE_DAYS="$2"; shift ;;
        --grace-minutes)  GRACE_MINUTES="$2"; shift ;;
        --promote-after)  PROMOTE_AFTER="$2"; shift ;;
        --draft)          DRAFT=1 ;;
        --remote)         REMOTE="$2"; shift ;;
        --base)           BASE="$2"; shift ;;
        --prefix)         PREFIX="$2"; shift ;;
        -h|--help)        sed -n '2,70p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

die() { echo "ERROR: $*" >&2; exit 2; }

command -v git >/dev/null 2>&1 || die "git is not on PATH."
command -v gh  >/dev/null 2>&1 || die "the gh CLI is not on PATH — this sweep cannot ask GitHub which branches have pull requests."
command -v jq  >/dev/null 2>&1 || die "jq is not on PATH."
[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ] || die "no GitHub token (GH_TOKEN or GITHUB_TOKEN). Without one every lookup fails, and a failed lookup is indistinguishable from 'no pull request exists' — which would open duplicates."

REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
    url="$(git remote get-url "$REMOTE" 2>/dev/null || true)"
    REPO="$(printf '%s' "$url" | sed -E 's#^.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#')"
fi
[ -n "$REPO" ] || die "cannot work out the repository (set GITHUB_REPOSITORY)."

REPO_OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"

# token_can_read_repo — is this credential alive at all?
token_can_read_repo() {
    gh api "repos/$REPO" --jq .full_name >/dev/null 2>&1
}

# looks_like_a_refusal <error-text>
#
# True when GitHub said "you may not", false when it said "something went
# wrong". Only a refusal is evidence about the token. A 502, a timeout or a
# reset connection says nothing about it, and must never move the run onto
# GITHUB_TOKEN — every pull request opened from there loses its CI and its
# review, which is a real cost to pay for a guess.
#
# One definition, used by the start-of-run probe and by both mid-run retries,
# so the two cannot drift apart.
looks_like_a_refusal() {
    case "$1" in
        *"not accessible"*|*"Bad credentials"*|*"HTTP 401"*|*"HTTP 403"*|*"HTTP 404"*) return 0 ;;
    esac
    return 1
}

# token_can_open_pull_requests — can it do the thing this run exists to do?
#
# Before `gh pr create` writes anything it reads `repository.defaultBranchRef`
# over GraphQL. A fine-grained PAT with pull-requests:write and no
# contents:read passes every REST read above and is refused on exactly that
# field, so a probe that only checks reads reports a healthy token and then
# every create fails — which upstream cost four branches in one run. Probe the
# capability the run needs, not one that merely correlates with it.
#
# Answers 1 only for a REFUSAL. A probe is not the work it stands in for, so an
# error that says nothing about the token — a network blip, a query a later edit
# broke — must not quietly downgrade every run to GITHUB_TOKEN. Those answer 0
# and say so; a real refusal is still caught at the create below.
token_can_open_pull_requests() {
    local out
    # The $variables in the query are GraphQL's, not the shell's:
    # shellcheck disable=SC2016
    out="$(gh api graphql \
             -f query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){defaultBranchRef{name}}}' \
             -f owner="$REPO_OWNER" -f name="$REPO_NAME" 2>&1)" && return 0

    looks_like_a_refusal "$out" && return 1
    echo "::warning::Could not tell whether the token can open pull requests: ${out%%$'\n'*}. Carrying on with it — that error is not evidence about the token."
    return 0
}

# Two flags, because they answer different questions.
#
#   FALLBACK_ATTEMPTED — "has this run already tried the switch?" It enforces
#     "switch at most once" and is set BEFORE the probe, so a switch that fails
#     is not tried again either.
#   RUNNING_DEGRADED   — "is this run opening pull requests that get no CI and
#     no review?" Set only when the switch SUCCEEDS. It is reported in the
#     summary and makes the run exit 1, so the workflow alerts a human. Before
#     this split, upstream, the single flag was private to the guard: a
#     fallback run opened uncheckable pull requests and still exited 0, and one
#     of them sat 12 hours with no checks while the bug it fixed kept firing.
FALLBACK_ATTEMPTED=0
RUNNING_DEGRADED=0

# use_fallback_token <why> — switch the run to GITHUB_TOKEN, once.
#
# 0 when the run now holds a token that can open pull requests, 1 when there is
# nothing better to switch to (the caller then reports the branch as lost). On
# 1 the preferred token is left in place, so nothing downstream is made worse.
use_fallback_token() {
    local why="$1" prev_gh="${GH_TOKEN:-}" prev_github="${GITHUB_TOKEN:-}"

    [ "$FALLBACK_ATTEMPTED" = "0" ] || return 1
    [ -n "${FALLBACK_GH_TOKEN:-}" ] && [ "${FALLBACK_GH_TOKEN}" != "${GH_TOKEN:-}" ] || return 1
    FALLBACK_ATTEMPTED=1

    export GH_TOKEN="$FALLBACK_GH_TOKEN"
    export GITHUB_TOKEN="$FALLBACK_GH_TOKEN"
    if token_can_read_repo && token_can_open_pull_requests; then
        RUNNING_DEGRADED=1
        echo "::warning::${why} — falling back to GITHUB_TOKEN. Pull requests opened from here get no CI and no review, because GitHub does not start workflow runs from GITHUB_TOKEN events. Fix the PAT: docs/runbooks/parked-branch-sweep.md."
        return 0
    fi

    export GH_TOKEN="$prev_gh"
    export GITHUB_TOKEN="$prev_github"
    echo "::warning::${why}, and GITHUB_TOKEN cannot open pull requests either."
    return 1
}

# A token that EXISTS is not a token that WORKS, and a token that WORKS is not a
# token that can open a pull request. Both distinctions have cost a run: an
# expired PAT is a non-empty string, so a `secrets.PAT || secrets.GITHUB_TOKEN`
# chain resolves once, picks the dead one, and never falls back; and a live PAT
# missing one permission passes a read probe and then loses every create. Left
# unchecked, the tool built to repair token damage is disabled by token damage.
if ! token_can_read_repo; then
    use_fallback_token "The preferred GitHub token does not work against $REPO — it exists and GitHub refuses it, which is what an expired PAT looks like" \
        || die "no GitHub token works against $REPO. Rotate STEWARD_HANDOFF_PAT, or pass FALLBACK_GH_TOKEN."
elif ! token_can_open_pull_requests; then
    use_fallback_token "The preferred GitHub token can read $REPO but cannot open pull requests — GitHub refuses it on repository.defaultBranchRef, which is what a fine-grained PAT without 'Contents: read' looks like" \
        || die "the GitHub token can read $REPO but cannot open pull requests: GitHub refuses repository.defaultBranchRef, which \`gh pr create\` reads before it writes anything. Give STEWARD_HANDOFF_PAT 'Contents: read' as well as 'Pull requests: write', or pass a FALLBACK_GH_TOKEN that has both. Stopping here on purpose: every create would be refused and every branch would stay invisible."
fi

if [ "$FETCH" = "1" ]; then
    git fetch --quiet --prune "$REMOTE" || die "git fetch failed."
fi

# Every judgement below is a `$BASE..$branch` range, and on a shallow clone
# those ranges are fiction: the grafted history makes a 1-commit branch read as
# thousands of commits ahead of a base it shares no ancestor with, and the file
# list that picks the saved pull-request body is wrong with it. The workflow
# checks out with fetch-depth: 0 for this reason; a hand-run in a shallow clone
# must not quietly produce a confidently false pull request body.
[ "$(git rev-parse --is-shallow-repository)" = "true" ] \
    && die "this is a shallow clone, so commit ranges against $BASE are wrong and every pull request body built from them would be too. Run \`git fetch --unshallow\` first (CI checks out with fetch-depth: 0)."

git rev-parse --verify --quiet "$REMOTE/$BASE" >/dev/null \
    || die "$REMOTE/$BASE does not exist locally — fetch it before sweeping."

NOW="$(date -u +%s)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

OPENED=()      # branches this run opened a pull request for
PROMOTED=()    # drafts this run marked ready for review
DEFERRED=()    # parked, but past --limit
LEFTOVER=()    # a pull request merged/closed and the branch has newer commits
UNKNOWN=()     # the lookup failed — cannot say
FAILED=()      # tried to open, GitHub refused
WAITING=0      # inside the grace window
TOOOLD=0       # past the age cap
COVERED=0      # has a pull request, nothing to do

# Ready for review by default. A draft gets CI and no review, so opening one
# would swap invisible work for unreviewed work — `review.yml` never fires
# again once `opened` has passed with draft=true.
DRAFT_FLAG=()
[ "$DRAFT" = "1" ] && DRAFT_FLAG=(--draft)

# saved_body_for <ref>
#
# The pull-request body the run committed when it could not post it — a
# `*pr-body*.md` / `*pr-comment*.md` file, or the autonomy report guardrail 7
# requires at .temper/autonomy-reports/<slug>.md. Prints a path, or nothing.
#
# Two traps, both of which have produced the wrong document upstream:
#
#   - `git ls-tree` lists the whole tree, so it returns files that came from
#     the base branch. That once picked another branch's report.
#   - `git diff base...branch` fixes that but still lists what a PARENT agent
#     branch added, because agent branches get stacked (a fix built on a fix).
#     Sorting those by path is arbitrary — the parent's report can win.
#
# So candidates come from `git log`, newest commit first: the run's own parking
# commit is the newest thing that adds a report, and it beats anything inherited.
saved_body_for() {
    local ref="$1" candidates named
    candidates="$(git log --format= --diff-filter=A --name-only "$REMOTE/$BASE..$ref" 2>/dev/null \
                  | grep -iE '(pr-body|pr-comment)[^/]*\.md$|^\.temper/autonomy-reports/.*\.md$')"
    # A file that names itself a pull-request body beats a generic report, but
    # only among files added by the same-or-newer commit — hence the ordering.
    named="$(printf '%s\n' "$candidates" | grep -iE '(pr-body|pr-comment)' | head -1)"
    [ -n "$named" ] && { printf '%s' "$named"; return; }
    printf '%s' "$(printf '%s\n' "$candidates" | head -1)"
}

# title_for <branch> <ref> <saved-body-path>
#
# NOT the tip commit's subject. On a parked branch the tip is usually the commit
# that records the failure ("save PR body — API token expired mid-run"), which
# describes the accident and not the work. In order: the saved body's own title,
# then the first commit that changes behaviour, then the branch name.
title_for() {
    local branch="$1" ref="$2" saved="$3" title=""

    if [ -n "$saved" ]; then
        title="$(git show "$ref:$saved" 2>/dev/null | grep -m1 '^# ' | sed 's/^# *//')"

        # A pipeline report can open with its own bookkeeping, not a title:
        # "SHIP-PENDING-COMMIT — quota counter never incremented (#753)".
        # The words after the marker are the title; the marker is noise.
        # Alternation, not a bracket expression: an em dash is three bytes, and
        # `[—-]` in the C locale matches one of them and mangles the rest.
        title="$(printf '%s' "$title" | sed -E 's/^[A-Z][A-Z0-9]*(-[A-Z0-9]+)+ *(—|–|-|:) *//')"

        # Some reports lead with a section heading instead, which describes
        # every report ever written and names no work at all. Fall through to
        # the commits rather than open "What & why".
        case "$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')" in
            "what & why"|"what and why"|"what this is"|"what changed"|"the change" \
            |summary|overview|description|context|background|problem|goal|"tl;dr")
                title="" ;;
        esac

        # A report headed with its own file name — a bare kebab-case slug — is
        # a worse title than the commit subject sitting right next to it. A
        # title has words in it, so test for a space once any trailing
        # "(#944)" is out of the way.
        case "$(printf '%s' "$title" | sed -E 's/ *\([^)]*\) *$//')" in
            *" "*) ;;
            *)     title="" ;;
        esac
    fi
    if [ -z "$title" ]; then
        title="$(git log --reverse --format='%s' "$REMOTE/$BASE..$ref" \
                 | grep -m1 -E '^(fix|feat|perf|refactor|build)[(:]')"
    fi
    # Every commit is a pipeline stage marker (wip / chore / docs). Naming the
    # branch is honest; guessing from a stage marker is not.
    [ -n "$title" ] || title="Parked work: $branch"
    printf '%s' "$title"
}

# no_pull_request_yet <branch>
#
# Re-asks GitHub before a retry. `gh pr create` can fail after the pull request
# exists, and rule 1 of this script is never to open a second one. A lookup that
# cannot be made answers "no" — the retry is skipped and a human looks.
no_pull_request_yet() {
    local prs
    prs="$(gh pr list --repo "$REPO" --head "$1" --state all --limit 5 --json number 2>/dev/null)" || return 1
    printf '%s' "$prs" | jq -e 'type == "array" and length == 0' >/dev/null 2>&1
}

# create_pull_request <branch> <title> <body-file> — prints the pull request URL
#
# --label may fail when the label does not exist; the pull request matters more
# than the label, so it retries without it (same idiom as review.yml's handoff).
create_pull_request() {
    local branch="$1" title="$2" body="$3"
    gh pr create --repo "$REPO" --head "$branch" --base "$BASE" "${DRAFT_FLAG[@]}" \
        --title "$title" --body-file "$body" --label parked-branch 2>"$WORKDIR/err.txt" \
    || gh pr create --repo "$REPO" --head "$branch" --base "$BASE" "${DRAFT_FLAG[@]}" \
        --title "$title" --body-file "$body" 2>"$WORKDIR/err.txt"
}

# body_for <branch> <ref> <saved-body-path> <outfile>
body_for() {
    local branch="$1" ref="$2" saved="$3" out="$4"
    local commits count last_date

    commits="$(git log --format='- %h %s' "$REMOTE/$BASE..$ref" | head -40)"
    count="$(git rev-list --count "$REMOTE/$BASE..$ref")"
    last_date="$(git log -1 --format='%ci' "$ref")"

    {
        echo "> Opened automatically by \`tools/sweep-parked-branches.sh\`. Nobody has reviewed this yet."
        echo
        # A parked branch is old by definition, and on a repo that
        # squash-merges, a branch built on another branch that has since merged
        # conflicts even though it looks like a clean fast-forward. Say so in
        # the body rather than leaving a reader to wonder why GitHub shows a
        # red merge box. merge-tree needs git 2.38; an older git exits 128 and
        # prints nothing, so probe it on a pair that cannot conflict first.
        if ! git merge-tree --write-tree "$REMOTE/$BASE" "$ref" >/dev/null 2>&1; then
            if git merge-tree --write-tree "$REMOTE/$BASE" "$REMOTE/$BASE" >/dev/null 2>&1; then
                echo "> **This branch does not merge into \`$BASE\` cleanly.** Rebase it before review."
                echo
            fi
        fi
        echo "## What this is"
        echo
        echo "The run that produced \`$branch\` pushed its work and never opened a pull request."
        echo "That is what this sweep looks for: the run's GitHub API token expires part-way"
        echo "through, \`git push\` keeps working because it uses a different credential, and the"
        echo "code reaches the server while the report does not."
        echo
        echo "$count commit(s) ahead of \`$BASE\`, last pushed $last_date."
        echo
        echo "**Nobody has reviewed this.** The automatic reviewers run on this pull request the"
        echo "same way they do on any other. The sweep does not judge whether the work is still"
        echo "wanted — read it, then merge it or close it."
        echo
        echo "## What the run said"
        echo
        echo '```'
        git log -1 --format='%B' "$ref" | head -30
        echo '```'
        echo
        if [ -n "$saved" ]; then
            echo "## The pull-request body the run wrote (\`$saved\`)"
            echo
            git show "$ref:$saved" 2>/dev/null || echo "_(could not read \`$saved\` from the branch)_"
            echo
        fi
        echo "## Commits"
        echo
        echo "$commits"
    } > "$out"
}

for ref in $(git for-each-ref --format='%(refname:short)' "refs/remotes/$REMOTE/${PREFIX}*"); do
    branch="${ref#"$REMOTE"/}"

    # Merged with a real merge commit — the tip is in the base branch already.
    if git merge-base --is-ancestor "$ref" "$REMOTE/$BASE" 2>/dev/null; then
        COVERED=$((COVERED + 1))
        continue
    fi

    tip="$(git rev-parse "$ref")"
    ts="$(git log -1 --format='%ct' "$ref")"
    age_min=$(( (NOW - ts) / 60 ))

    if [ "$age_min" -lt "$GRACE_MINUTES" ]; then
        WAITING=$((WAITING + 1))
        echo "waiting  $branch — ${age_min}m old, inside the ${GRACE_MINUTES}m grace window; its own run may still be opening the pull request."
        continue
    fi
    if [ "$age_min" -gt $(( MAX_AGE_DAYS * 1440 )) ]; then
        TOOOLD=$((TOOOLD + 1))
        echo "too old  $branch — $(( age_min / 1440 ))d old, past the ${MAX_AGE_DAYS}d cap; not resurrected."
        continue
    fi

    prs="$(gh pr list --repo "$REPO" --head "$branch" --state all --limit 20 \
           --json number,state,url,headRefOid,isDraft 2>"$WORKDIR/err.txt")"
    rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$prs" ] || ! printf '%s' "$prs" | jq -e 'type == "array"' >/dev/null 2>&1; then
        # Never fall through to "no pull request exists" — that opens duplicates.
        UNKNOWN+=("$branch")
        echo "UNKNOWN  $branch — could not ask GitHub whether a pull request exists: $(head -1 "$WORKDIR/err.txt" 2>/dev/null). Skipped, because a failed lookup and 'no pull request' look identical and one of them opens a duplicate."
        continue
    fi

    total="$(printf '%s' "$prs"  | jq 'length')"
    open_prs="$(printf '%s' "$prs" | jq '[.[] | select(.state == "OPEN")] | length')"
    tip_seen="$(printf '%s' "$prs" | jq --arg t "$tip" '[.[] | select(.headRefOid == $t)] | length')"

    if [ "$open_prs" -gt 0 ]; then
        # An open DRAFT is not "already shown". `review.yml` fires on `opened`
        # and `ready_for_review` and skips drafts, so a draft gets CI and no
        # review. Marking it ready is an API call at the END of a run — the
        # same call, with the same expired token, that failed to open the pull
        # request. The run cannot make it. This job can, with a fresh one.
        draft_no="$(printf '%s' "$prs" | jq -r 'first(.[] | select(.state == "OPEN" and .isDraft == true) | .number) // empty')"
        if [ -n "$draft_no" ]; then
            if [ "$age_min" -lt "$PROMOTE_AFTER" ]; then
                # Long enough that a run doing an hour of tests without
                # committing is not promoted out from under itself.
                echo "waiting  $branch — draft #$draft_no, last commit ${age_min}m ago; its run may still be working (promotes after ${PROMOTE_AFTER}m)."
                COVERED=$((COVERED + 1))
                continue
            fi
            if [ "$DRY_RUN" = "1" ]; then
                PROMOTED+=("$branch")
                echo "would ready $branch — draft #$draft_no, quiet for ${age_min}m"
                continue
            fi
            if gh pr ready "$draft_no" --repo "$REPO" 2>"$WORKDIR/err.txt"; then
                PROMOTED+=("$branch")
                echo "ready    $branch — draft #$draft_no marked ready for review after ${age_min}m of silence; the reviewers run now."
            else
                refusal="$(head -2 "$WORKDIR/err.txt" | tr '\n' ' ')"
                if looks_like_a_refusal "$refusal" \
                   && use_fallback_token "GitHub refused to mark draft #$draft_no ready ($refusal)" \
                   && gh pr ready "$draft_no" --repo "$REPO" 2>"$WORKDIR/err.txt"; then
                    PROMOTED+=("$branch")
                    # Ready is the right end state, but GITHUB_TOKEN does not
                    # start workflow runs, so this promotion alone summons no
                    # reviewer. The next push to the branch does.
                    echo "ready    $branch — draft #$draft_no marked ready with GITHUB_TOKEN after the preferred token was refused. No reviewer fires from this event; fix the PAT."
                else
                    FAILED+=("$branch")
                    echo "FAILED   $branch — draft #$draft_no could not be marked ready: $refusal. Nothing will review it."
                fi
            fi
            continue
        fi
        COVERED=$((COVERED + 1))
        continue
    fi

    if [ "$tip_seen" -gt 0 ]; then
        COVERED=$((COVERED + 1))
        continue
    fi

    if [ "$total" -gt 0 ]; then
        # A pull request closed or merged, and the branch grew afterwards. A new
        # pull request from here would replay the squash-merged commits as new
        # work, so this one needs a human: cherry-pick the extra commits onto a
        # fresh branch, or delete the branch.
        LEFTOVER+=("$branch")
        echo "leftover $branch — its pull request(s) closed, then $(git rev-list --count "$REMOTE/$BASE..$ref") commit(s) were pushed on top. Not auto-opened: the diff would replay merged work. Cherry-pick what is still wanted onto a new branch."
        continue
    fi

    if [ "${#OPENED[@]}" -ge "$LIMIT" ]; then
        DEFERRED+=("$branch")
        continue
    fi

    saved="$(saved_body_for "$ref")"
    title="$(title_for "$branch" "$ref" "$saved")"
    body="$WORKDIR/body.md"
    body_for "$branch" "$ref" "$saved" "$body"

    if [ "$DRY_RUN" = "1" ]; then
        OPENED+=("$branch")
        echo "would open  $branch — \"$title\""
        continue
    fi

    if url="$(create_pull_request "$branch" "$title" "$body")"; then
        OPENED+=("$branch")
        echo "opened   $branch — $url"
    else
        # A refusal here is the failure this whole job exists to repair, aimed
        # at the job itself, so it gets one more try with the other token
        # before the branch is written off as lost.
        refusal="$(head -2 "$WORKDIR/err.txt" | tr '\n' ' ')"
        if ! looks_like_a_refusal "$refusal"; then
            # Same rule as the start-of-run probe: this error is not evidence
            # about the token, so switching would cost every later branch its
            # CI and its review for nothing.
            FAILED+=("$branch")
            echo "FAILED   $branch — could not open a pull request: $refusal. Not retried with GITHUB_TOKEN, because that error says nothing about the token."
        elif ! use_fallback_token "GitHub refused to open a pull request for $branch ($refusal)"; then
            FAILED+=("$branch")
            echo "FAILED   $branch — could not open a pull request: $refusal"
        elif ! no_pull_request_yet "$branch"; then
            FAILED+=("$branch")
            echo "FAILED   $branch — the create was refused ($refusal), and the retry was skipped because GitHub now reports a pull request for this branch, or could not be asked. Look before opening one by hand: a second pull request is worse than none."
        elif url="$(create_pull_request "$branch" "$title" "$body")"; then
            OPENED+=("$branch")
            echo "opened   $branch — $url (with GITHUB_TOKEN, after the preferred token was refused; no CI and no review will run on it)"
        else
            FAILED+=("$branch")
            echo "FAILED   $branch — could not open a pull request with either token: $(head -2 "$WORKDIR/err.txt" | tr '\n' ' ')"
        fi
    fi
done

echo
echo "=== sweep summary ==="
echo "opened:        ${#OPENED[@]} ${OPENED[*]:-}"
echo "marked ready:  ${#PROMOTED[@]} ${PROMOTED[*]:-}"
echo "already shown: $COVERED"
echo "waiting:       $WAITING (younger than ${GRACE_MINUTES}m)"
echo "too old:       $TOOOLD (older than ${MAX_AGE_DAYS}d)"
[ "${#LEFTOVER[@]}" -gt 0 ] && echo "leftover:      ${#LEFTOVER[@]} ${LEFTOVER[*]} — commits pushed after a pull request closed; a human decides."
# A cap that hides what it dropped reads as "everything is covered".
[ "${#DEFERRED[@]}" -gt 0 ] && echo "deferred:      ${#DEFERRED[@]} ${DEFERRED[*]} — past --limit $LIMIT this run; the next run takes them, or raise --limit."
[ "${#UNKNOWN[@]}" -gt 0 ]  && echo "UNKNOWN:       ${#UNKNOWN[@]} ${UNKNOWN[*]} — GitHub could not be asked; nothing was opened for these."
[ "${#FAILED[@]}" -gt 0 ]   && echo "FAILED:        ${#FAILED[@]} ${FAILED[*]} — the work is still invisible."
# A green run that quietly used GITHUB_TOKEN is how a fixed bug once kept
# firing for 12 more hours upstream. Name it here, and exit 1 below, so the
# workflow alerts someone.
[ "$RUNNING_DEGRADED" = "1" ] \
    && echo "DEGRADED:      this run fell back to GITHUB_TOKEN. Any pull request it opened or marked ready gets no CI and no review — GitHub does not start workflow runs from GITHUB_TOKEN events. Fix the PAT: docs/runbooks/parked-branch-sweep.md."

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### Parked-branch sweep"
        echo
        echo "- opened: ${#OPENED[@]} ${OPENED[*]:-}"
        echo "- marked ready: ${#PROMOTED[@]} ${PROMOTED[*]:-}"
        echo "- already shown: $COVERED · waiting: $WAITING · too old: $TOOOLD"
        [ "${#LEFTOVER[@]}" -gt 0 ] && echo "- leftover (needs a human): ${LEFTOVER[*]}"
        [ "${#DEFERRED[@]}" -gt 0 ] && echo "- deferred past --limit $LIMIT: ${DEFERRED[*]}"
        [ "${#UNKNOWN[@]}" -gt 0 ]  && echo "- **lookup failed**: ${UNKNOWN[*]}"
        [ "${#FAILED[@]}" -gt 0 ]   && echo "- **could not open**: ${FAILED[*]}"
        [ "$RUNNING_DEGRADED" = "1" ] \
            && echo "- **DEGRADED — fell back to GITHUB_TOKEN**: pull requests opened by this run get no CI and no review. Fix the PAT."
    } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "${#UNKNOWN[@]}" -gt 0 ] || [ "${#FAILED[@]}" -gt 0 ] || [ "$RUNNING_DEGRADED" = "1" ]; then
    exit 1
fi
exit 0
