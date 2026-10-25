#!/usr/bin/env bash
# Default: safely preserve local changes. -f: discard local edits and sync exactly to origin.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FORCE=false
usage() {
  cat <<'HELP'
Usage: ./bin/pull-latest.sh [-f|--force]

Default: pull and restore existing local changes.
-f, --force: discard ALL tracked changes, staged changes, and unpushed commits;
             delete untracked files/directories; match origin branch.
             Ignored build/cache files are kept.
HELP
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force) FORCE=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done
command -v git >/dev/null 2>&1 || {
  echo "Git is required." >&2; exit 1;
}
cd "$ROOT_DIR"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Not a Git repository: $ROOT_DIR" >&2; exit 1;
}
BRANCH="$(git symbolic-ref --quiet --short HEAD)" || {
  echo "Cannot pull from a detached HEAD." >&2; exit 1;
}

# Never abort or overwrite a merge/rebase that was already in progress
# before this script started.
if [[ -d "$(git rev-parse --git-path rebase-merge)" ||
      -d "$(git rev-parse --git-path rebase-apply)" ||
      -f "$(git rev-parse --git-path MERGE_HEAD)" ||
      -n "$(git ls-files -u)" ]]; then
  echo "A merge, rebase, or conflict is already in progress. Resolve it first." >&2
  exit 1
fi

if [[ "$FORCE" == true ]]; then
  echo "Force syncing origin/$BRANCH (discarding local changes and untracked files)..."
  # Fetch first: a failed network request must NOT delete local work.
  git fetch origin "$BRANCH"
  git reset --hard FETCH_HEAD
  git clean -fd
  echo "Siftidy now matches origin/$BRANCH. Ignored files were kept."
  exit 0
fi

STASHED=false
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "Preserving local changes, including untracked files..."
  PREVIOUS_STASH="$(git rev-parse -q --verify refs/stash 2>/dev/null || true)"
  git stash push --include-untracked \
    -m "siftidy-pull-autostash-$(date +%Y%m%d%H%M%S)" >/dev/null
  NEW_STASH="$(git rev-parse -q --verify refs/stash 2>/dev/null || true)"
  if [[ -z "$NEW_STASH" || "$NEW_STASH" == "$PREVIOUS_STASH" ]]; then
    echo "Could not safely stash local changes; pull cancelled." >&2
    exit 1
  fi
  STASHED=true
fi

echo "Pulling origin/$BRANCH into $ROOT_DIR..."
if ! git -c rebase.autoStash=false pull --rebase origin "$BRANCH"; then
  echo "Pull failed. Attempting to restore your local changes." >&2
  git rebase --abort >/dev/null 2>&1 || true
  if [[ "$STASHED" == true ]]; then
    if ! git stash pop --index; then
      echo "Local changes remain safely stored in git stash (check git stash list)." >&2
    fi
  fi
  exit 1
fi

if [[ "$STASHED" == true ]]; then
  echo "Reapplying your pre-pull changes..."
  if ! git stash pop --index; then
    echo "Pull succeeded, but your saved changes conflicted." >&2
    echo "Resolve conflicts; the original stash was retained (git stash list)." >&2
    exit 1
  fi
fi

echo "Siftidy is up to date on $BRANCH."
git status --short
