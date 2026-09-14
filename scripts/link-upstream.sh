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

# 1. are we in the course repository itself?
#    Running this here would add an upstream remote pointing at the repo you are
#    standing in, and report "Already linked" -- true, and useless.
slug() { printf '%s' "$1" | sed -E 's#^https://github\.com/##; s#^git@github\.com:##; s#/$##; s#\.git$##'; }
origin_url="$(git remote get-url origin 2>/dev/null || true)"
if [ -n "$origin_url" ] && [ "$(slug "$origin_url")" = "$(slug "$UPSTREAM_URL")" ]; then
  printf '\nThis is the course repository itself, not your copy of it.\n\n'
  printf 'Work in a repository under your own account. Open\n\n'
  printf '    %s\n\n' "${UPSTREAM_URL%.git}"
  printf 'click "Use this template", clone the repository that creates, and run this\n'
  printf 'script from inside that clone. Nothing was changed here.\n\n'
  exit 1
fi

# 2. no uncommitted work -- a merge should never be the thing that loses it
if [ -n "$(git status --porcelain)" ]; then
  printf '\nYou have uncommitted changes. Commit them first:\n\n'
  printf '    git add -A && git commit -m "work in progress"\n\n'
  printf 'Then run this script again.\n\n'
  exit 1
fi

# 3. remote
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

# Since git 2.27, `git pull` refuses to act on diverging branches until you say
# whether you want merge or rebase. Collecting course updates is a merge -- your
# commits stay where they are and keep their hashes. Set it for this repository
# only, so nothing about how you use git elsewhere changes.
git config pull.rebase false

# And do not drop them into vim to approve the merge message. Git opens an editor
# for a merge commit only when a terminal is attached, which is exactly when a
# student is sitting there -- and "how do I get out of vim" is not the lesson.
# The generated message is fine. Repository-local, like the setting above.
git config branch."$BRANCH".mergeOptions "--no-edit"

# 4. already linked?
if git merge-base HEAD "upstream/$BRANCH" >/dev/null 2>&1; then
  printf '\nAlready linked -- your history and the course history share commits.\n'
  printf 'To collect updates from now on:\n\n'
  printf '    git pull upstream main\n\n'
  exit 0
fi

# 5. warn if there is already work to conflict with
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

# 6. the one-time merge
#
#    One wrinkle: your copy was made from the course repo as it stood at that
#    moment. If the course repo has been pushed to since, your copy differs from
#    it in exactly the files that changed in between -- and with no common
#    ancestor git cannot tell "an older version" from "an edit", so it reports
#    those as conflicts. On an untouched copy the answer is never in doubt: the
#    course repo has the newer file, so take it. That is handled below without
#    bothering you. Once you have started working, conflicts mean something real
#    and you resolve them yourself.

linked_ok() {
  printf '\nLinked. Push it so your copy on GitHub has it too:\n\n'
  printf '    git push\n\n'
  printf 'From now on, when a new lab or a fix is announced:\n\n'
  printf '    git pull upstream main\n'
  printf '    git push\n\n'
  exit 0
}

git merge --allow-unrelated-histories --no-edit \
  -m "Link this repository to the CS 450 course repository" \
  "upstream/$BRANCH" && linked_ok

conflicted="$(git diff --name-only --diff-filter=U)"

if [ -n "$conflicted" ] && [ "${commits:-1}" -eq 1 ]; then
  printf '\nYour copy was made before the most recent change to the course repo.\n'
  printf 'You have not edited anything yet, so the course version is the one to\n'
  printf 'keep. Taking it for:\n\n'
  printf '%s\n' "$conflicted" | sed 's/^/    /'
  printf '\n'
  printf '%s\n' "$conflicted" | while IFS= read -r f; do
    [ -n "$f" ] && git checkout --theirs -- "$f" >/dev/null 2>&1
  done
  git add -A
  if git commit -q -m "Link this repository to the CS 450 course repository"; then
    linked_ok
  fi
  printf 'Could not complete the merge automatically. Run: git merge --abort\n\n'
  exit 1
fi

printf '\nThe merge stopped with conflicts. Files still to resolve:\n\n'
printf '%s\n' "$conflicted" | sed 's/^/    /'
printf '\nEach file has both versions marked with <<<<<<< and >>>>>>>. Keep what\n'
printf 'you want, delete the markers, then:\n\n'
printf '    git add -A && git commit\n\n'
printf 'To abandon the attempt instead: git merge --abort\n\n'
exit 1
