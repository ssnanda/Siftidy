#!/usr/bin/env bash
set -euo pipefail

# Bump Siftidy's Flutter version, commit all local changes, and push them.
# With no options, pressing Enter selects a patch bump and Enter again confirms.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC_FILE="$ROOT_DIR/pubspec.yaml"
APP_NAME="Siftidy"

VERSION_OVERRIDE=""
BUMP_PART=""
DO_PUSH="true"
YES="false"

usage() {
  cat <<'USAGE'
Siftidy — version bump, commit, and push.

Usage:
  ./bin/bump-version.sh [options]

Options:
  --version X.Y.Z+B              Set an explicit version
  --bump patch|minor|major|build Select the part to bump
  --no-push                      Commit without pushing
  --yes, -y                      Skip confirmation
  --help, -h                     Show this help

With no version option, patch is the default. The script stages all changes,
commits them as "Release Siftidy X.Y.Z+B", rebases on origin, and pushes.
USAGE
}

get_version() {
  awk '/^version:/ {print $2; exit}' "$PUBSPEC_FILE"
}

validate_version() {
  local version="$1"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
    echo "Error: version must use X.Y.Z+B format, for example 1.0.0+1" >&2
    exit 1
  fi
}

bump_version() {
  local current="$1"
  local part="$2"
  local semantic build major minor patch

  semantic="${current%+*}"
  build="${current#*+}"
  IFS='.' read -r major minor patch <<< "$semantic"

  case "$part" in
    patch) patch=$((patch + 1)); build=$((build + 1)) ;;
    minor) minor=$((minor + 1)); patch=0; build=$((build + 1)) ;;
    major) major=$((major + 1)); minor=0; patch=0; build=$((build + 1)) ;;
    build) build=$((build + 1)) ;;
    *) echo "Error: bump must be patch, minor, major, or build" >&2; exit 1 ;;
  esac

  echo "$major.$minor.$patch+$build"
}

choose_version() {
  local current="$1"
  local choice=""
  local custom=""

  while true; do
    cat >&2 <<MENU
Current version: $current

Choose release type:
  1) patch  ($(bump_version "$current" patch))
  2) minor  ($(bump_version "$current" minor))
  3) major  ($(bump_version "$current" major))
  4) build  ($(bump_version "$current" build))
  5) custom version
MENU
    read -r -p "Enter choice (1-5, default=1): " choice
    choice="${choice:-1}"

    case "$choice" in
      1|patch|p) bump_version "$current" patch; return ;;
      2|minor|m) bump_version "$current" minor; return ;;
      3|major|M) bump_version "$current" major; return ;;
      4|build|b) bump_version "$current" build; return ;;
      5|custom|c)
        read -r -p "Enter version X.Y.Z+B: " custom
        validate_version "$custom"
        echo "$custom"
        return
        ;;
      *) echo "Please choose 1, 2, 3, 4, or 5." >&2 ;;
    esac
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Error: --version requires a value" >&2; exit 1; }
      VERSION_OVERRIDE="$2"
      shift 2
      ;;
    --bump)
      [[ $# -ge 2 ]] || { echo "Error: --bump requires a value" >&2; exit 1; }
      BUMP_PART="$2"
      shift 2
      ;;
    --no-push) DO_PUSH="false"; shift ;;
    --yes|-y) YES="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Error: unknown option $1" >&2; usage; exit 1 ;;
  esac
done

[[ -z "$VERSION_OVERRIDE" || -z "$BUMP_PART" ]] || {
  echo "Error: use only one of --version or --bump" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || { echo "Error: git command is required" >&2; exit 1; }
[[ -f "$PUBSPEC_FILE" ]] || { echo "Error: missing $PUBSPEC_FILE" >&2; exit 1; }
git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Error: $ROOT_DIR is not a git repository" >&2
  exit 1
}

cd "$ROOT_DIR"
BRANCH="$(git symbolic-ref --quiet --short HEAD)" || {
  echo "Error: cannot release while HEAD is detached" >&2
  exit 1
}

CURRENT_VERSION="$(get_version)"
validate_version "$CURRENT_VERSION"

if [[ -n "$VERSION_OVERRIDE" ]]; then
  NEXT_VERSION="$VERSION_OVERRIDE"
elif [[ -n "$BUMP_PART" ]]; then
  NEXT_VERSION="$(bump_version "$CURRENT_VERSION" "$BUMP_PART")"
else
  NEXT_VERSION="$(choose_version "$CURRENT_VERSION")"
fi
validate_version "$NEXT_VERSION"

if [[ "$YES" != "true" ]]; then
  read -r -p "Bump to $NEXT_VERSION, commit all changes, and push? [Y/n] " CONFIRM
  case "${CONFIRM:-y}" in
    y|Y|yes|YES) ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

sed -i '' "s/^version: .*/version: $NEXT_VERSION/" "$PUBSPEC_FILE"
echo "Version: $CURRENT_VERSION -> $NEXT_VERSION"

git add -A
if git diff --cached --quiet; then
  echo "Error: nothing to commit" >&2
  exit 1
fi

git commit -m "Release $APP_NAME $NEXT_VERSION"
echo "Git: committed all local changes"

if [[ "$DO_PUSH" == "true" ]]; then
  echo "Git: rebasing $BRANCH on origin/$BRANCH..."
  git pull --rebase origin "$BRANCH"
  git push origin "$BRANCH"
  echo "Git: pushed $BRANCH"
else
  echo "Git: push skipped (--no-push)"
fi
