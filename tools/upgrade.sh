#!/usr/bin/env bash
# tools/upgrade.sh — the manifest, the brownfield installer, and the computable
# upgrade. One mechanism for all three, because they are one problem: knowing,
# per harness file, what the template shipped, what the adopter changed, and
# what a newer release wants.
#
#   list-files              print the harness surface (the files this template
#                           OWNS), derived from git ls-files — never a
#                           hand-kept list, which would go stale silently.
#   stamp <version>         write .agents/template-manifest.json: the version,
#                           the sha256 of every harness file AS IT IS RIGHT
#                           NOW, and the interview answers found in the
#                           environment. tools/init.sh calls this BEFORE its
#                           substitution sweep, so the recorded hashes are the
#                           PRISTINE (pre-answer) content — that is what makes
#                           "adopter customised this" distinguishable from
#                           "the interview substituted this" forever after.
#   --install <target>      brownfield: copy the harness surface into an
#                           EXISTING repository. Never overwrites — a
#                           collision lands beside the host's file as
#                           <name>.agentic-sdlc.proposed — then stamps the
#                           manifest in the target and prints what is next.
#   plan <new-template>     classify every manifest file against a checkout of
#                           a newer template: clean-update / locally-modified /
#                           new-upstream / removed-upstream. Read-only.
#   apply <new-template> <old-template>
#                           take clean updates wholesale; three-way-merge
#                           locally-modified files (base = the OLD template's
#                           pristine file with your answers replayed, ours =
#                           your tree, theirs = the new template with answers
#                           replayed) via git merge-file, leaving ordinary
#                           conflict markers; then re-baseline the manifest to
#                           the new release. floors.yml is NEVER touched —
#                           floors are the adopter's ratchet. BOTH checkouts
#                           are required: without the recorded base, local
#                           edits and upstream changes are indistinguishable,
#                           and applying anyway would re-baseline a tree that
#                           was never brought up to date. `plan` works with
#                           the new checkout alone and names what it cannot
#                           classify.
#
# Why a manifest instead of git subtree or a pull relationship: the harness
# interleaves with adopter-owned space (their workflows sit beside ours, their
# answers are baked into config.yml, their floors are calibrated), so a merge
# strategy that does not know which side owns a line conflicts forever. The
# manifest records the one fact merges need — the pristine base — at the only
# moment it exists: adoption time.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
MANIFEST_REL=".agents/template-manifest.json"

die() { echo "upgrade.sh: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required (same dependency as ledger.sh)"

# sha256, portably: GNU coreutils on Linux, shasum on stock macOS.
file_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# The interview token list — must match tools/init.sh's TOKENS array; the
# guard in tests/upgrade.bats asserts the two never drift.
TOKENS="PRODUCT_NAME PROVIDER MODEL_JUDGE MODEL_EXECUTE MODEL_CHALLENGE CHALLENGE_BASE_URL ALERT_CHANNEL RUNNER_LABEL LEDGER_COMMIT_NAME LEDGER_COMMIT_EMAIL BUILD_PIPELINE"

# The harness surface, derived from the tracked tree of the checkout at $1.
# Excluded: the example product and the site (retired on adoption), the
# maintainer docs (deleted on adoption), README.md (rewritten per product),
# ADOPTING.md (regenerated), the build record, and the manifest itself.
list_files() {
  local from="$1"
  # The last four are the files init.sh deletes unconditionally on adoption
  # (the template's own Pages deploy and upstream-drift tooling): stamping or
  # installing them would hand an adopter files the adoption must then remove.
  ( cd "$from" && git ls-files ) 2>/dev/null \
    | grep -v '^examples/' \
    | grep -v '^site/' \
    | grep -v '^docs/maintainers/' \
    | grep -v '^\.temper/' \
    | grep -v '^README\.md$' \
    | grep -v '^ADOPTING\.md$' \
    | grep -v "^${MANIFEST_REL}\$" \
    | grep -v '^\.github/workflows/pages\.yml$' \
    | grep -v '^tools/check-upstream-drift\.sh$' \
    | grep -v '^\.agents/upstream-sync\.json$' \
    | grep -v '^tests/upstream-drift\.bats$'
}

# Replay the recorded interview answers onto a pristine file, the same
# substitution shape init.sh performs — so a replayed base/theirs lines up
# with the adopter's substituted tree instead of conflicting at every token.
replay_answers() {
  local src="$1" dst="$2" manifest="$3" tok val
  cp "$src" "$dst"
  for tok in $TOKENS; do
    val="$(jq -r --arg t "$tok" '.answers[$t] // empty' "$manifest")"
    [ -n "$val" ] || continue
    # Escape the replacement's sed metacharacters (&, \, and the | delimiter)
    # so a value like "Track & Trace" replays as the literal text adoption
    # actually wrote, never as sed's whole-match expansion.
    val="$(printf '%s' "$val" | sed -e 's/[&\\|]/\\&/g')"
    sed -i.upgradebak "s|{{${tok}}}|${val}|g" "$dst" && rm -f "$dst.upgradebak"
  done
}

cmd_stamp() {
  # Hashes come from THIS checkout's harness surface; the manifest lands at
  # $2 when given (the --install target — whose git does not yet track the
  # overlay, so its own ls-files would record the wrong set) or here.
  local version="${1:-unknown}" dest="${2:-$ROOT}" f sha entries="" answers="" tok val
  cd "$ROOT" || die "cannot cd to $ROOT"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "stamp must run inside a git checkout"
  if [ -f "$dest/$MANIFEST_REL" ]; then
    # The pristine baseline exists only once, at adoption; a re-run of init.sh
    # (documented and safe) must never overwrite it with post-substitution
    # hashes of a tree the adopter has since built a product in.
    echo "manifest already present at $dest/$MANIFEST_REL — keeping the original pristine baseline (not restamping)."
    return 0
  fi
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    sha="$(file_sha "$f")"
    entries="${entries}$(jq -n --arg p "$f" --arg s "$sha" '{($p): $s}')"
  done < <(list_files "$ROOT")
  for tok in $TOKENS; do
    val="$(eval "printf '%s' \"\${$tok:-}\"")"
    [ -n "$val" ] || continue
    answers="${answers}$(jq -n --arg t "$tok" --arg v "$val" '{($t): $v}')"
  done
  local tmpdir
  tmpdir="$(mktemp -d)"
  printf '%s' "$entries" | jq -s 'add // {}' > "$tmpdir/files.json"
  printf '%s' "$answers" | jq -s 'add // {}' > "$tmpdir/answers.json"
  mkdir -p "$dest/$(dirname "$MANIFEST_REL")"
  jq -n --arg v "$version" \
        --slurpfile files "$tmpdir/files.json" \
        --slurpfile ans "$tmpdir/answers.json" \
        '{template_version: $v,
          upstream: "https://github.com/galando/agentic-sdlc",
          note: "Pristine (pre-substitution) sha256 per harness file, stamped at adoption. tools/upgrade.sh plan/apply computes upgrades from it. Do not hand-edit.",
          files: $files[0], answers: $ans[0]}' \
    > "$dest/$MANIFEST_REL"
  rm -rf "$tmpdir"
  echo "stamped $MANIFEST_REL: $(jq '.files | length' "$dest/$MANIFEST_REL") files at version $version"
}

cmd_install() {
  local target="$1" f collisions=0 copied=0
  [ -d "$target" ] || die "--install target is not a directory: $target"
  git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "--install target is not a git repository: $target (the harness needs one)"
  while IFS= read -r f; do
    [ -f "$ROOT/$f" ] || continue
    mkdir -p "$target/$(dirname "$f")"
    if [ -e "$target/$f" ]; then
      # NEVER overwrite the host's file. The proposed copy sits beside it for
      # a human merge — same offer-not-act contract as adopt.sh.
      cp "$ROOT/$f" "$target/$f.agentic-sdlc.proposed"
      collisions=$((collisions + 1))
    else
      cp "$ROOT/$f" "$target/$f"
      copied=$((copied + 1))
    fi
  done < <(list_files "$ROOT")
  # Stamp in the TARGET: the hashes are this template's pristine content,
  # which is exactly what the target now holds (nothing substituted yet).
  local version
  version="$(grep -m1 -oE '^## \[?[0-9]+\.[0-9]+\.[0-9]+\]?' "$ROOT/CHANGELOG.md" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo unknown)"
  cmd_stamp "$version" "$target" || die "could not stamp the manifest in $target"
  cat <<EOF

Installed: $copied files copied, $collisions collision(s) written as *.agentic-sdlc.proposed.
$([ "$collisions" -gt 0 ] && echo "Merge each .proposed file into the host's own by hand — the harness never overwrites." )
Next, inside $target:
  1. review + commit the overlay,
  2. tools/init.sh --answers <file>   (profiles/ has starters; see ONBOARDING.md),
  3. keep your product OUTSIDE backend/ and frontend/ until you swap the measured
     gates to your stack (docs/runbooks/porting-to-your-stack.md) — the process
     layer is live either way, and floors stay as loud unset sentinels until
     tools/measure-floors.sh runs against YOUR code.
EOF
}

# plan/apply share the classification; apply also acts on it.
_classify_and_act() {
  local new="$1" old="${2:-}" act="$3"
  local manifest="$ROOT/$MANIFEST_REL"
  [ -f "$manifest" ] || die "no $MANIFEST_REL here — nothing records what this adoption started from. (An adoption made before the manifest existed can be re-baselined: clone the template at your original version and run 'tools/upgrade.sh stamp <version>' from it.)"
  [ -d "$new" ] || die "new-template dir not found: $new"
  local recorded_version tmp f base_sha ours_sha theirs_pristine replayed_theirs replayed_base
  recorded_version="$(jq -r '.template_version' "$manifest")"
  if [ "$act" = apply ] && [ -z "$old" ]; then
    die "apply needs BOTH checkouts: apply <new-template> <old-template>. Without the recorded base (v$recorded_version), local edits and upstream changes are indistinguishable. Get it with: git clone --depth 1 --branch v$recorded_version $(jq -r '.upstream' "$manifest") — or run 'plan <new-template>' to see what is classifiable without it."
  fi
  tmp="$(mktemp -d)"
  local clean=0 modified=0 conflicts=0 fresh=0 gone=0 collided=""
  while IFS= read -r f; do
    base_sha="$(jq -r --arg p "$f" '.files[$p] // empty' "$manifest")"
    theirs_pristine="$new/$f"
    case "$f" in
      floors.yml)
        # The adopter's ratchet. Only they move it; an upgrade never does.
        continue ;;
    esac
    if [ -z "$base_sha" ]; then
      # Not in the recorded surface: new upstream file — unless the adopter
      # already has their OWN file at that path, which is a collision the
      # harness must never absorb: the proposal lands beside it, and the path
      # stays OUT of the re-baselined manifest so a future upgrade never
      # mistakes the adopter's file for harness surface.
      if [ -f "$theirs_pristine" ]; then
        if [ -e "$ROOT/$f" ]; then
          collided="$collided $f"
          if [ "$act" = apply ]; then
            replay_answers "$theirs_pristine" "$ROOT/$f.agentic-sdlc.proposed" "$manifest"
            echo "collision: $f is yours — the new upstream file is beside it as .agentic-sdlc.proposed"
          else
            echo "collision:        $f (yours; the new upstream file would land as .proposed)"
          fi
        else
          fresh=$((fresh + 1))
          if [ "$act" = apply ]; then
            mkdir -p "$ROOT/$(dirname "$f")"
            replay_answers "$theirs_pristine" "$ROOT/$f" "$manifest"
            echo "new:      $f"
          else
            echo "new-upstream:     $f"
          fi
        fi
      fi
      continue
    fi
    if [ ! -f "$theirs_pristine" ]; then
      gone=$((gone + 1))
      echo "removed-upstream: $f (left in place — delete it yourself if you agree)"
      continue
    fi
    [ -f "$ROOT/$f" ] || { echo "missing-locally:  $f (was deleted here; skipped)"; continue; }
    # Is ours still exactly the substituted pristine? Replay answers onto the
    # RECORDED pristine... we do not store base content, but we do not need it
    # for this question: replay answers onto THEIRS and onto ours' base is
    # impossible — so instead detect local modification by replaying answers
    # onto the OLD template's copy when available, and otherwise by comparing
    # ours against the replayed NEW file (identical ⇒ nothing to do at all).
    replayed_theirs="$tmp/theirs"
    replay_answers "$theirs_pristine" "$replayed_theirs" "$manifest"
    ours_sha="$(file_sha "$ROOT/$f")"
    if [ "$ours_sha" = "$(file_sha "$replayed_theirs")" ]; then
      continue  # already identical to the new release
    fi
    if [ -n "$old" ] && [ -f "$old/$f" ]; then
      replayed_base="$tmp/base"
      replay_answers "$old/$f" "$replayed_base" "$manifest"
      if [ "$ours_sha" = "$(file_sha "$replayed_base")" ]; then
        clean=$((clean + 1))
        if [ "$act" = apply ]; then
          cp "$replayed_theirs" "$ROOT/$f"
          echo "updated:  $f"
        else
          echo "clean-update:     $f"
        fi
      else
        modified=$((modified + 1))
        if [ "$act" = apply ]; then
          if git merge-file -L "yours" -L "base v$recorded_version" -L "new template" \
               "$ROOT/$f" "$replayed_base" "$replayed_theirs"; then
            echo "merged:   $f"
          else
            conflicts=$((conflicts + 1))
            echo "CONFLICT: $f (ordinary conflict markers left in place)"
          fi
        else
          echo "locally-modified: $f (needs the old template to merge)"
        fi
      fi
    else
      modified=$((modified + 1))
      echo "differs:          $f (cannot tell local edits from upstream changes without the old template: git clone --branch v${recorded_version} <upstream> — see .agents/template-manifest.json)"
    fi
  done < <(list_files "$new")
  # Files the manifest records that the NEW release no longer ships: the loop
  # above iterates the new surface, so upstream removals only surface here.
  while IFS= read -r f; do
    if [ ! -f "$new/$f" ] && [ "$f" != "floors.yml" ]; then
      gone=$((gone + 1))
      echo "removed-upstream: $f (left in place — delete it yourself if you agree)"
    fi
  done < <(jq -r '.files | keys[]' "$manifest")
  rm -rf "$tmp"
  echo
  echo "summary: clean=$clean modified=$modified conflicts=$conflicts new=$fresh removed=$gone (recorded base: v$recorded_version; floors.yml never touched)"
  if [ "$act" = apply ]; then
    # Re-baseline the manifest against the NEW release: fresh pristine hashes
    # from the new template, answers carried over — so the NEXT upgrade
    # computes from this one instead of from the original adoption.
    local new_version entries="" sha
    new_version="$(grep -m1 -oE '^## \[?[0-9]+\.[0-9]+\.[0-9]+\]?' "$new/CHANGELOG.md" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo unknown)"
    while IFS= read -r f; do
      [ -f "$new/$f" ] || continue
      case " $collided " in *" $f "*) continue ;; esac   # never claim the adopter's own file
      sha="$(file_sha "$new/$f")"
      entries="${entries}$(jq -n --arg p "$f" --arg s "$sha" '{($p): $s}')"
    done < <(list_files "$new")
    printf '%s' "$entries" | jq -s 'add // {}' > "$tmp.files.json"
    jq --arg v "$new_version" --slurpfile files "$tmp.files.json" \
       '.template_version = $v | .files = $files[0]' "$manifest" > "$manifest.new" \
      && mv "$manifest.new" "$manifest"
    rm -f "$tmp.files.json"
    echo "manifest re-baselined to v$new_version (answers carried over)."
    echo "Now run the suite: bats tests/ tests/harness-guards/ — and resolve any CONFLICT files first."
  fi
}

case "${1:-}" in
  list-files) list_files "$ROOT" ;;
  stamp)      shift; cmd_stamp "${1:-unknown}" "${2:-}" ;;
  --install)  shift; [ -n "${1:-}" ] || die "--install needs a target directory"; cmd_install "$1" ;;
  plan)       shift; [ -n "${1:-}" ] || die "plan needs a new-template checkout"; _classify_and_act "$1" "${2:-}" plan ;;
  apply)      shift; [ -n "${1:-}" ] || die "apply needs a new-template checkout"; _classify_and_act "$1" "${2:-}" apply ;;
  *)
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
