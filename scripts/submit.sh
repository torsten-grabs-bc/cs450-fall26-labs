#!/usr/bin/env bash
#
# CS 450 -- submit a checkpoint.
#
#     ./scripts/submit.sh cp1
#
# Tags the current commit, pushes the branch and the tag, and then asks GitHub
# whether the tag actually arrived. That last step is the point of this script.
#
# At CP0, some students who had already done the work were initially not
# graded, because the tag never left their laptop. `git push` sends your
# commits; it does not send tags unless you name one -- `git push origin cp1`.
# GitHub Desktop cannot create a tag at all. Every one of those students
# believed they had submitted. This script does not let you believe that: if it
# prints anything other than "Submitted", you have not submitted.
#
# It deliberately does NOT commit for you. What goes into the commit is your
# decision, not a script's.
#
set -uo pipefail

TAG="${1:-}"
if [ -z "$TAG" ]; then
  echo "usage: $0 <tag>    e.g.  $0 cp1" >&2
  exit 2
fi

cd "$(dirname "$0")/.." || exit 1

if [ ! -d .git ]; then
  echo "This is not a git repository. Run this from inside your clone." >&2
  exit 1
fi

# --- 1. nothing left behind ------------------------------------------------
if [ -n "$(git status --porcelain)" ]; then
  echo "You have uncommitted changes:"
  git status --short | sed 's/^/    /'
  echo
  echo "Whatever is not committed will not be submitted. Commit first:"
  echo
  echo "    git add -A && git commit -m \"$TAG\""
  echo
  echo "then run this again."
  exit 1
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
echo "Submitting $(git rev-parse --short HEAD) on branch '$branch' as tag '$TAG'."

# --- 2. tag and push -------------------------------------------------------
# -f and --force so that re-submitting before the deadline just works: the tag
# moves to your newest commit instead of erroring.
git tag -f "$TAG" >/dev/null || exit 1

if ! git push origin "$branch" </dev/null; then
  echo >&2
  echo "Could not push your branch. Nothing has been submitted." >&2
  exit 1
fi

if ! git push --force origin "$TAG" </dev/null; then
  echo >&2
  echo "Could not push the tag. Nothing has been submitted." >&2
  exit 1
fi

# --- 3. confirm it is really on GitHub -------------------------------------
# Do not trust the push output -- ask the remote what it has.
if git ls-remote --tags origin </dev/null 2>/dev/null | grep -q "refs/tags/${TAG}\$"; then
  url="$(git remote get-url origin 2>/dev/null \
         | sed 's#git@github.com:#https://github.com/#; s#\.git$##')"
  echo
  echo "Submitted. Paste these two things into the Canvas assignment:"
  echo
  echo "    repository:  $url"
  echo "    tag:         $TAG"
  echo
  echo "You can check for yourself: open that URL, click the branch dropdown,"
  echo "and choose Tags. '$TAG' should be listed."
  exit 0
else
  echo >&2
  echo "The tag did NOT reach GitHub, so nothing has been submitted." >&2
  echo "Try once more. If it keeps failing, post on the discussion board with" >&2
  echo "the output of:   git ls-remote --tags origin" >&2
  exit 1
fi
