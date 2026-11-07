#!/usr/bin/env bash
# strip-session-stamp.sh — remove a worktree's session version stamp from its branch history.
#
# A worktree session retargets version.txt and the README "**Current Version:**" line to
# x.y.z--<name> (see AGENTS.md → *Worktree version stamp*). That stamp is a session label and must
# not reach main — neither the commit that sets it, nor the one that restores it, nor a stamp that
# rode along inside a feature commit. Landing runs this in the worktree, BEFORE `git rebase main`:
#
#   build/strip-session-stamp.sh [<base>]      # <base> defaults to main
#
# It rewrites every commit in merge-base(<base>, HEAD)..HEAD so that version.txt and the README
# version line hold the value they had at the merge-base (the version the branch started from):
#   - a commit left identical to its parent (stamp-only / restore-only) is dropped;
#   - a commit that also changed other things keeps them, minus the stamp;
#   - author, committer, dates and message are kept.
# Each commit is rebuilt from its own tree, not replayed as a patch, so it cannot conflict. The
# branch then has no version change at all, and the following `git rebase main` cannot conflict on
# version.txt even when main moved from --rc1 to --rc2 meanwhile. Other README edits are kept.
#
# Refuses: a dirty working tree, a detached HEAD, merge commits on the branch.
# Undo: the old tip is printed, and the branch reflog has it (`git reset --keep <old-tip>`).
set -euo pipefail

base="${1:-main}"
root=$(git rev-parse --show-toplevel)
cd "$root"

die() { echo "strip-session-stamp: $*" >&2; exit 1; }
version_line() { git show "$1:README.md" 2>/dev/null | grep -m1 -F '**Current Version:**' || true; }

branch=$(git symbolic-ref -q --short HEAD) || die "HEAD is detached; check out the session branch"
[[ "$branch" != "$base" ]]                 || die "on '$base' itself; run this in the session worktree"
[[ -z "$(git status --porcelain)" ]]       || die "working tree is not clean; commit or set work aside first"

fork=$(git merge-base "$base" HEAD)        || die "no merge-base between '$base' and HEAD"
old_tip=$(git rev-parse HEAD)
[[ -z "$(git rev-list --merges "$fork..HEAD")" ]] || die "branch has merge commits; not supported"

commits=$(git rev-list --reverse "$fork..HEAD")
[[ -n "$commits" ]] || { echo "strip-session-stamp: no commits on '$branch' past '$base'"; exit 0; }

# The version spots as they were where the branch forked.
version_blob=$(git rev-parse -q --verify "$fork:version.txt") || die "no version.txt at $fork"
want=$(git cat-file blob "$version_blob" | tr -d ' \t\r\n')
[[ -n "$want" ]] || die "version.txt is empty at $fork"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_INDEX_FILE="$tmp/index"

parent=$fork
parent_tree=$(git rev-parse "$fork^{tree}")
kept=0 dropped=0 cleaned=0

for c in $commits; do
  git read-tree "$c"

  git update-index --cacheinfo "100644,$version_blob,version.txt"
  if readme=$(git rev-parse -q --verify "$c:README.md"); then
    # Same pattern the pre-commit hook reads: "**Current Version:** v<version>".
    new_readme=$(git cat-file blob "$readme" \
      | sed -E "s/^(.*\*\*Current Version:\*\* v)[^ ]+(.*)$/\1${want}\2/" \
      | git hash-object -w --stdin)
    mode=$(git ls-tree "$c" README.md | cut -d' ' -f1)
    git update-index --cacheinfo "$mode,$new_readme,README.md"
  fi
  tree=$(git write-tree)

  subject=$(git log -1 --format='%h %s' "$c")
  if [[ "$tree" == "$parent_tree" ]]; then
    echo "  dropped  $subject"
    dropped=$((dropped + 1))
    continue
  fi
  # "cleaned" = this commit itself changed a version spot (a stamp riding inside a feature commit).
  if ! git diff --quiet "$c^" "$c" -- version.txt \
     || [[ "$(version_line "$c^")" != "$(version_line "$c")" ]]; then
    echo "  cleaned  $subject"
    cleaned=$((cleaned + 1))
  else
    kept=$((kept + 1))
  fi

  git cat-file commit "$c" | sed '1,/^$/d' > "$tmp/msg"
  parent=$(
    GIT_AUTHOR_NAME=$(git log -1 --format=%an "$c") \
    GIT_AUTHOR_EMAIL=$(git log -1 --format=%ae "$c") \
    GIT_AUTHOR_DATE=$(git log -1 --format=%ad --date=raw "$c") \
    GIT_COMMITTER_NAME=$(git log -1 --format=%cn "$c") \
    GIT_COMMITTER_EMAIL=$(git log -1 --format=%ce "$c") \
    GIT_COMMITTER_DATE=$(git log -1 --format=%cd --date=raw "$c") \
    git commit-tree "$tree" -p "$parent" -F "$tmp/msg"
  )
  parent_tree=$tree
done

unset GIT_INDEX_FILE
if [[ "$parent" == "$old_tip" ]]; then
  echo "strip-session-stamp: nothing to strip on '$branch'"
  exit 0
fi
git reset -q --keep "$parent"
echo "strip-session-stamp: '$branch' $kept kept, $cleaned cleaned, $dropped dropped (version stays $want)"
echo "  old tip: $old_tip   (undo: git reset --keep $old_tip)"
