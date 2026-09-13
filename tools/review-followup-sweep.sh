#!/usr/bin/env bash
#
# review-followup-sweep.sh — decide, at merge time, whether a non-blocking review
# finding still deserves an issue.
#
# review.yml no longer files a `[review-followup]` issue while the pull request is
# open. It labels the pull request `review-followup-pending` and posts the findings
# there under `### Review follow-up: clear these before you merge`. This script reads
# that label after the pull request closes:
#
#   merged, still labelled   -> file ONE issue against the default branch, with the
#                               referee's comparison embedded; then clear the label
#   merged, label cleared    -> file nothing; the author handled it on the branch
#   closed without merging   -> close any open follow-up issue for it; keep the label
#
# The token the caller hands in is the switch. The workflow passes GITHUB_TOKEN on
# purpose: GitHub starts no workflow run from an event that token creates, so an issue
# filed here wakes no steward. A personal access token here would wake it for exactly
# the findings the referee ruled it should not be woken for.
#
# Standing rule: a missing input never reads as "nothing to do". Every unreadable
# state below files rather than stays quiet, and a failed filing exits non-zero.
#
# Usage:
#   review-followup-sweep.sh --pr <N> --merged true|false [--repo O/R] [--base NAME]
#   review-followup-sweep.sh --scan [--limit N] [--days N] [--repo O/R] [--base NAME]
#
#   --repo   OWNER/NAME; defaults to $GITHUB_REPOSITORY. Never a built-in slug.
#   --base   the default branch, for the issue text; asked of GitHub when omitted.
#
# Exit codes: 0 done · 1 something was not recorded (a filing, a close, a lookup, or
# the scan's own listing failed) · 2 the run could not start (bad arguments, no repo,
# no gh, no jq).
#
# Harness: tests/review-followup-sweep.bats. Runbook: docs/runbooks/review-followup-sweep.md.
#
set -uo pipefail

LABEL="review-followup-pending"
# The referee's comment starts with this heading (.agents/prompts/review-referee.md).
REFEREE_HEADING="## Reviewer comparison"
# review.yml's own pre-merge reminder quotes the comparison inside itself; it is
# never the comparison.
MARKER_HEADING="### Review follow-up: clear these before you merge"
# review.yml posts this when the comparison step could not run; it says there are
# no sorted findings, it is not the findings.
PLACEHOLDER="Reviewer comparison - not available"

REPO="${GITHUB_REPOSITORY:-}"
SERVER="${GITHUB_SERVER_URL:-https://github.com}"
RUN_URL="${RUN_URL:-}"
BASE=""

MODE=""
PR=""
MERGED=""
LIMIT=50
DAYS=14

# Set when a filing fails or an input this script depends on cannot be read. The run
# exits non-zero, so the step shows red rather than reporting success over a finding
# it did not record.
FAILED=0

usage() {
    sed -n '3,33p' "$0"
}

need_value() {
    [ -n "${2:-}" ] || { echo "$1 needs a value" >&2; exit 2; }
}

while [ $# -gt 0 ]; do
    case "$1" in
        --pr)     need_value "$1" "${2:-}"; MODE=one; PR="$2"; shift 2 ;;
        --merged) need_value "$1" "${2:-}"; MERGED="$2";       shift 2 ;;
        --limit)  need_value "$1" "${2:-}"; LIMIT="$2";        shift 2 ;;
        --days)   need_value "$1" "${2:-}"; DAYS="$2";         shift 2 ;;
        --repo)   need_value "$1" "${2:-}"; REPO="$2";         shift 2 ;;
        --base)   need_value "$1" "${2:-}"; BASE="$2";         shift 2 ;;
        --scan)   MODE=scan;                                   shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$MODE" ]; then
    echo "usage: review-followup-sweep.sh --pr <N> --merged true|false | --scan [--limit N] [--days N]" >&2
    exit 2
fi
if [ "$MODE" = "one" ] && [ "$MERGED" != "true" ] && [ "$MERGED" != "false" ]; then
    echo "--merged must be true or false (got '${MERGED}')" >&2
    exit 2
fi
# The repository comes from the caller or from Actions, never from a default slug: a
# vendored copy of this script must not file issues against the template's own repo.
if [ -z "$REPO" ]; then
    echo "ERROR: no repository — pass --repo OWNER/NAME or set GITHUB_REPOSITORY." >&2
    exit 2
fi
command -v gh >/dev/null 2>&1 || { echo "ERROR: the gh CLI is not on PATH." >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is not on PATH." >&2; exit 2; }

# Per-run temp dir, never a fixed path in /tmp: a self-hosted runner's /tmp is shared,
# and a leftover file owned by another user cannot be truncated by this one.
WORK="${RUNNER_TEMP:-}"
if [ -z "$WORK" ] || [ ! -w "$WORK" ]; then
    WORK="$(mktemp -d)"
fi

# The default branch, for the issue text. Asked once, lazily; a failed lookup names
# it generically rather than guessing `main`.
default_branch() {
    if [ -z "$BASE" ]; then
        BASE="$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)"
        [ -n "$BASE" ] || BASE="the default branch"
    fi
    printf '%s' "$BASE"
}

# findings_of <pr> <outfile> — the referee's comparison, embedded for the issue.
#
# Three endpoints, not one: conversation comments, inline review comments and formal
# review bodies. The comparison is posted as a conversation comment today, but this
# sweep is the last reader of it, so it accepts every shape a review can take.
#
# Only a Bot author's text may be embedded. The body becomes an issue that agents act
# on, so it may not be arbitrary text from anyone who can comment on the pull request.
# Filtered by `user.type`, never by login: a template does not know the adopter's bot
# account, and every role posts from the same one anyway.
#
# --paginate: the comparison is among the NEWEST comments; one page returns the oldest.
findings_of() {
    local pr="$1" out="$2" body issues_json pulls_json reviews_json
    issues_json="$WORK/sweep-issue-comments.json"
    pulls_json="$WORK/sweep-pull-comments.json"
    reviews_json="$WORK/sweep-reviews.json"
    gh api "repos/$REPO/issues/$pr/comments" --paginate --slurp > "$issues_json" 2>/dev/null || echo '[]' > "$issues_json"
    gh api "repos/$REPO/pulls/$pr/comments"  --paginate --slurp > "$pulls_json"  2>/dev/null || echo '[]' > "$pulls_json"
    gh api "repos/$REPO/pulls/$pr/reviews"   --paginate --slurp > "$reviews_json" 2>/dev/null || echo '[]' > "$reviews_json"

    # `--paginate --slurp` yields an ARRAY OF PAGES; flatten before filtering. A file
    # that is not JSON at all counts as an empty endpoint, never as a failed run.
    body="$(jq -r -s \
        --arg heading "$REFEREE_HEADING" \
        --arg marker "$MARKER_HEADING" \
        --arg placeholder "$PLACEHOLDER" '
        [ .[] | (if type == "array" then .[] else . end)
              | (if type == "array" then .[] else . end)
              | select(type == "object") ]
        | map(select((.user.type // "") == "Bot"))
        | map(select((.body // "") | contains($heading)))
        | map(select((.body // "") | contains($marker) | not))
        | map(select((.body // "") | contains($placeholder) | not))
        | map({ts: (.created_at // .submitted_at // ""), body: .body})
        | sort_by(.ts) | last | .body // ""
    ' "$issues_json" "$pulls_json" "$reviews_json" 2>/dev/null || true)"

    if [ -n "$body" ]; then
        {
            echo "<details><summary><b>The findings, as the referee sorted them</b></summary>"
            echo
            printf '%s\n' "$body"
            echo
            echo "</details>"
        } > "$out"
        return 0
    fi

    {
        echo "> [!WARNING]"
        echo "> The referee's comparison **could not be read** from that pull request, so the"
        echo "> findings are not repeated here. Read them on the pull request itself."
    } > "$out"
}

# followup_title <pr> — the exact title this sweep files under.
followup_title() {
    printf '[review-followup] Non-blocking findings on merged PR #%s' "$1"
}

# open_issue_titles — "<number>\t<title>" per open issue, newest 200. Prints nothing
# and returns 1 when GitHub could not be asked.
open_issue_titles() {
    gh issue list --repo "$REPO" --state open --limit 200 \
        --json number,title --jq '.[] | "\(.number)\t\(.title)"' 2>/dev/null
}

# open_followups_for <pr> — open non-blocking follow-ups for this pull request, both
# the shape this sweep files and the shape review.yml filed before the label existed.
# Exact, anchored match on the title, never GitHub's tokenising search: there
# "PR #60" matches "PR #601", and a false match suppresses a real finding.
open_followups_for() {
    local pr="$1"
    open_issue_titles \
      | grep -E "^[0-9]+	\[review-followup\] Non-blocking findings on (merged )?PR #${pr}$" || true
}

# file_for_merged <pr>
file_for_merged() {
    local pr="$1" title body titles base
    title="$(followup_title "$pr")"

    # Dedupe on the exact, whole-line title. The dedupe is check-then-create with no
    # lock, which is why the workflow serialises every run in one concurrency group.
    if ! titles="$(open_issue_titles)"; then
        echo "::error::Could not list open issues for PR #$pr, so a duplicate cannot be ruled out. Not filing; the label stays for the next sweep."
        FAILED=1
        return 0
    fi
    if printf '%s\n' "$titles" | cut -f2- | grep -qFx "$title"; then
        echo "A follow-up issue for #$pr is already open - not filing another."
        return 0
    fi

    base="$(default_branch)"
    findings_of "$pr" "$WORK/sweep-findings.md"
    body="$WORK/sweep-issue-body.md"
    {
        echo "Both automatic reviews of **PR #$pr** raised findings. The referee ruled that none of"
        echo "them had to be fixed before it merged, so nothing was woken and the pull request was"
        echo "labelled \`$LABEL\` instead."
        echo
        echo "**That pull request has now merged with the label still on it**, so the findings"
        echo "below were never cleared. They are now about \`$base\`."
        echo
        echo "**Task:** check each finding against \`$base\`. Fix what is still true; close this"
        echo "saying why for anything that is not. A finding only one reviewer raised is still a"
        echo "finding."
        echo
        echo "- Pull request: $SERVER/$REPO/pull/$pr"
        [ -n "$RUN_URL" ] && echo "- Sweep run: $RUN_URL"
        echo
        cat "$WORK/sweep-findings.md"
        echo
        echo "Filed automatically by \`tools/review-followup-sweep.sh\` with \`GITHUB_TOKEN\`, so opening"
        echo "it wakes nobody."
        echo
        echo "**Do not edit this body** — comment instead, so the filed record survives."
    } > "$body"

    # --label is best-effort: a missing label must not lose the finding.
    if gh issue create --repo "$REPO" --title "$title" --body-file "$body" --label agent-report \
       || gh issue create --repo "$REPO" --title "$title" --body-file "$body"; then
        echo "PR #$pr merged still labelled - filed: $title"
        gh pr edit "$pr" --repo "$REPO" --remove-label "$LABEL" >/dev/null 2>&1 \
            || echo "::warning::Filed the follow-up for #$pr but could not remove the label $LABEL. The open issue stops a duplicate; clear the label by hand."
        return 0
    fi

    echo "::error::Could not file the follow-up for #$pr. Leaving the label on so the next sweep retries."
    FAILED=1
    return 0
}

# close_for_unmerged <pr>
#
# The findings never reached the default branch, so an open follow-up is closed with
# that reason. The label is deliberately LEFT ON: a closed pull request can be reopened
# and merged, review.yml does not review a reopened pull request, and the label is the
# only memory that findings exist. --days bounds what a stale label can cost.
close_for_unmerged() {
    local pr="$1" rows number
    rows="$(open_followups_for "$pr")"
    if [ -z "$rows" ]; then
        echo "PR #$pr closed unmerged - no open follow-up issue to close."
        return 0
    fi
    while IFS=$'\t' read -r number _; do
        [ -n "$number" ] || continue
        gh issue comment "$number" --repo "$REPO" --body \
"Closed automatically: **PR #$pr was closed without merging**, so these findings never reached the default branch.

Nothing here is a defect in the shipped system. If the same change comes back as a new pull request, it gets its own review.

Closed by \`tools/review-followup-sweep.sh\`." >/dev/null 2>&1 \
            || echo "::warning::Could not comment on #$number before closing it."

        if gh issue close "$number" --repo "$REPO" --reason "not planned" >/dev/null 2>&1 \
           || gh issue close "$number" --repo "$REPO" >/dev/null 2>&1; then
            echo "Closed #$number - PR #$pr never merged."
        else
            echo "::error::Could not close #$number for unmerged PR #$pr."
            FAILED=1
        fi
    done <<< "$rows"
}

# handle <pr> <merged: true|false> [labelled: yes|unknown]
#
# `labelled: yes` lets the scan skip a second lookup — `gh pr list --label` already
# proved the label is there. On the event path it is unknown and must be read.
handle() {
    local pr="$1" merged="$2" labelled="${3:-unknown}" view labels

    if [ "$merged" != "true" ]; then
        close_for_unmerged "$pr"
        return 0
    fi

    if [ "$labelled" != "yes" ]; then
        view="$(gh pr view "$pr" --repo "$REPO" --json labels 2>/dev/null || true)"
        # The LABELS: prefix is the readable/unreadable signal. Without it an empty
        # result — a 502, a missing gh — cannot be told apart from "the author cleared
        # the label", and the run would file nothing and go green.
        labels="$(printf '%s' "$view" \
            | jq -r '"LABELS:" + ([.labels[]?.name // empty] | join(","))' 2>/dev/null || true)"

        case "$labels" in
            LABELS:*)
                labels="${labels#LABELS:}"
                case ",$labels," in
                    *",$LABEL,"*) ;;
                    *)
                        echo "PR #$pr merged with the label cleared - the author handled the findings. Filing nothing."
                        return 0
                        ;;
                esac
                ;;
            *)
                echo "::error::Could not read the labels of PR #$pr - filing the follow-up anyway rather than assuming they were cleared."
                FAILED=1
                ;;
        esac
    fi

    file_for_merged "$pr"
}

if [ "$MODE" = "one" ]; then
    handle "$PR" "$MERGED"
    exit "$FAILED"
fi

# --scan: the backstop. A merge performed with GITHUB_TOKEN starts no workflow run, and
# a fork's event run holds a read-only token, so the event path alone can miss a merge.
# Bounded by --days so the window cannot fill with long-abandoned pull requests.
SINCE="$(date -u -d "${DAYS} days ago" +%F 2>/dev/null \
         || date -u -v-"${DAYS}"d +%F 2>/dev/null || true)"
echo "Scanning pull requests closed since ${SINCE:-the beginning} that still carry $LABEL..."

LIST="$WORK/sweep-pr-list.txt"
SEARCH=()
[ -n "$SINCE" ] && SEARCH=(--search "closed:>=$SINCE")

gh pr list --repo "$REPO" --state closed --label "$LABEL" --limit "$LIMIT" \
    "${SEARCH[@]+"${SEARCH[@]}"}" \
    --json number,mergedAt --jq '.[] | "\(.number)\t\(.mergedAt // "")"' > "$LIST" 2>/dev/null
LIST_RC=$?

# A backstop that reports success when its only input failed is not a backstop. The
# redirect creates the file either way, so the exit code is the only honest signal.
if [ "$LIST_RC" -ne 0 ]; then
    echo "::error::Could not list closed pull requests carrying $LABEL (gh exit $LIST_RC). The sweep did nothing this run."
    exit 1
fi

# A file, not a pipe: a pipe puts the loop in a subshell and FAILED never reaches the
# exit below.
while IFS=$'\t' read -r number merged_at; do
    [ -n "$number" ] || continue
    if [ -n "$merged_at" ]; then
        handle "$number" true yes
    else
        handle "$number" false yes
    fi
done < "$LIST"
echo "Sweep complete."
exit "$FAILED"
