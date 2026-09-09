#!/usr/bin/env bash
# Run as a post-commit hook (see .pre-commit-config.yaml). Regenerates
# CHANGELOG.md and, if it changed, amends it straight into the commit that
# just happened rather than creating a separate "update changelog" commit.
#
# Safe from infinite recursion: amending re-triggers this hook, but git-cliff
# derives its output purely from commit messages (unchanged by --no-edit), so
# the second pass produces identical content, sees no diff, and exits.
set -euo pipefail

if ! command -v git-cliff >/dev/null 2>&1; then
  echo "update-changelog: git-cliff not installed, skipping (brew install git-cliff)" >&2
  exit 0
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

git-cliff --config cliff.toml -o CHANGELOG.md

if git diff --quiet -- CHANGELOG.md; then
  exit 0
fi

git add CHANGELOG.md
git commit --amend --no-edit -q
