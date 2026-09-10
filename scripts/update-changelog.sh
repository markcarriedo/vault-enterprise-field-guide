#!/usr/bin/env bash
# Run as a pre-commit hook (see .pre-commit-config.yaml). Regenerates
# CHANGELOG.md from git log and stages it, so the update becomes part of
# whatever commit is currently being made.
#
# Deliberately runs at the pre-commit *stage*, not post-commit: at this point
# the commit being made doesn't exist yet, so git-cliff only ever sees
# already-finalized commits whose hashes will never change again. That's
# what makes it safe to show each entry's short commit hash - a commit's own
# entry (and hash) simply doesn't appear until the *next* commit, once it
# exists and is stable. The alternative (post-commit + self-amend) can't
# show a commit's own hash at all: amending to fix it changes the hash
# again, forever. See the decision log for the full story.
set -euo pipefail

if ! command -v git-cliff >/dev/null 2>&1; then
  echo "update-changelog: git-cliff not installed, skipping (brew install git-cliff)" >&2
  exit 0
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

git-cliff --config cliff.toml -o CHANGELOG.md
git add CHANGELOG.md
