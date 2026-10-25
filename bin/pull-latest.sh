#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v git >/dev/null 2>&1 || {
  echo "Error: git command is required" >&2
  exit 1
}

git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Error: $ROOT_DIR is not a git repository" >&2
  exit 1
}

cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: commit or stash local changes before pulling." >&2
  git status --short
  exit 1
fi

BRANCH="$(git symbolic-ref --quiet --short HEAD)" || {
  echo "Error: cannot pull while HEAD is detached" >&2
  exit 1
}

echo "Pulling origin/$BRANCH into $ROOT_DIR..."
git pull --rebase origin "$BRANCH"
echo "Siftidy is up to date."
