#!/usr/bin/env bash
#
# CS 450 -- link your repository to the course repository. Run this ONCE,
# right after you clone, before you start working.
#
# Your repository was created from a template. That gives you a clean history
# of your own, but it also means your repo and the course repo share no
# commits at all. Git can only merge two histories sensibly when it can find a
# common ancestor to compare them against; without one it treats every file
# that differs as a conflict -- including files you never touched.
#
# Running this now, while your copy is still identical to the course repo,
# joins the two histories with zero conflicts. From then on, collecting new
# labs and fixes is just:
#
#     git pull upstream main
#
# Safe to run twice: it detects an existing link and stops.
#
set -uo pipefail

UPSTREAM_URL="https://github.com/torsten-grabs-bc/cs450-fall26-labs.git"
BRANCH="main"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.." || exit 1

die()  { printf '\nERROR: %s\n\n' "$*" >&2; exit 1; }
note() { printf '  %s\n' "$*"; }

git rev-parse --git-dir >/dev/null 2>&1 ||
  die "This is not a git repository. Clone your own copy first, then run this from inside it."

# 1. no uncommitted work -- a merge should never be the thing that loses it
if [ -n "$(git status --porcelain)" ]; then
  printf '\nYou have uncommitted changes. Commit them first:\n\n'
  printf '    git add -A && git commit -m "work in progress"\n\n'
  printf 'Then run this script again.\n\n'
  exit 1
fi

# 2. remote
if git remote get-url upstream >/dev/null 2>&1; then
  current="$(git remote get-url upstream)"
  if [ "$current" != "$UPSTREAM_URL" ]; then
    note "upstream pointed at $current -- correcting it"
    git remote set-url upstream "$UPSTREAM_URL"
  fi
else
  git remote add upstream "$UPSTREAM_URL"
  note "added remote upstream -> $UPSTREAM_URL"
fi

git fetch --quiet upstream "$BRANCH" ||
  die "Could not reach the course repository. Check your network and try again."

# 3. already linked?
if git merge-base HEAD "upstream/$BRANCH" >/dev/null 2>&1; then
  printf '\nAlready linked -- your history and the course history share commits.\n'
  printf 'To collect updates from now on:\n\n'
  printf '    git pull upstream main\n\n'
  exit 0
fi

# 4. warn if there is already work to conflict with
commits="$(git rev-list --count HEAD)"
if [ "${commits:-1}" -gt 1 ]; then
  printf '\nHeads up: your repository already has %s commits.\n' "$commits"
  printf 'Linking is cleanest on a fresh copy. Files you have changed may come\n'
  printf 'back as conflicts, and you will have to resolve them by hand.\n\n'
  printf 'If you would rather not merge, you can take new lab folders directly\n'
  printf 'without linking at all:\n\n'
  printf '    git fetch upstream\n'
  printf '    git checkout upstream/main -- lab1/\n\n'
  read -r -p 'Link anyway? [y/N] ' ans
  case "$ans" in [yY]*) ;; *) printf 'Nothing changed.\n\n'; exit 1 ;; esac
fi

# 5. the one-time merge
if git merge --allow-unrelated-histories --no-edit \
     -m "Link this repository to the CS 450 course repository" \
     "upstream/$BRANCH"; then
  printf '\nLinked. Push it so your copy on GitHub has it too:\n\n'
  printf '    git push\n\n'
  printf 'From now on, when a new lab or a fix is announced:\n\n'
  printf '    git pull upstream main\n'
  printf '    git push\n\n'
else
  printf '\nThe merge stopped with conflicts. Files still to resolve:\n\n'
  git diff --name-only --diff-filter=U | sed 's/^/    /'
  printf '\nEdit each one, then:\n\n'
  printf '    git add -A && git commit\n\n'
  printf 'To abandon the attempt instead: git merge --abort\n\n'
  exit 1
fi
