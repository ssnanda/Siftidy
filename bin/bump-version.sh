#!/usr/bin/env bash
set -euo pipefail

# Version bump using the highest published Git tag as the next-release floor.
# Commit all local project changes with the release, matching the normal workflow.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
PUBSPEC_FILE="$ROOT_DIR/pubspec.yaml"
APP_NAME="Siftidy"

VERSION_OVERRIDE=""
BUMP_PART=""
DO_PUSH=true
YES=false

usage() {
  cat <<'USAGE'
Siftidy version bump, commit and optional push.

Usage:
  ./bin/bump-version.sh [--bump patch|minor|major|build] [--yes] [--no-push]
  ./bin/bump-version.sh --version X.Y.Z+B [--yes] [--no-push]

The patch default uses the newer of the local version and published version
tags as a baseline. All non-ignored local changes are committed and pushed.
USAGE
}
get_version() { awk '/^version:/ { print $2; exit }' "$PUBSPEC_FILE"; }
validate_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]] || {
    echo "Version must look like X.Y.Z+B: $1" >&2; exit 1;
  }
}
bump_version() {
  local current="$1" part="$2" semantic build major minor patch
  semantic="${current%+*}"
  build="${current#*+}"
  IFS='.' read -r major minor patch <<< "$semantic"
  case "$part" in
    patch) patch=$((patch + 1)); build=$((build + 1)) ;;
    minor) minor=$((minor + 1)); patch=0; build=$((build + 1)) ;;
    major) major=$((major + 1)); minor=0; patch=0; build=$((build + 1)) ;;
    build) build=$((build + 1)) ;;
    *) echo "Invalid bump type: $part" >&2; exit 1 ;;
  esac
  echo "$major.$minor.$patch+$build"
}
# Numeric SemVer comparison works on macOS without GNU sort -V.
version_gt() {
  local x1 x2 x3 y1 y2 y3
  IFS='.' read -r x1 x2 x3 <<< "$1"
  IFS='.' read -r y1 y2 y3 <<< "$2"
  if (( x1 != y1 )); then (( x1 > y1 )); return; fi
  if (( x2 != y2 )); then (( x2 > y2 )); return; fi
  (( x3 > y3 ))
}
latest_tag() {
  command -v python3 >/dev/null 2>&1 || return 0
  local remote_tags
  if ! remote_tags="$(git ls-remote --tags --refs origin 2>/dev/null)"; then
    echo "Warning: couldn't check release tags; using local version." >&2
    return 0
  fi
  printf '%s\n' "$remote_tags" | python3 -c '
import re,sys
tags = []
for line in sys.stdin:
    match = re.search(r"refs/tags/v(\d+)\.(\d+)\.(\d+)\s*$", line)
    if match: tags.append(tuple(int(n) for n in match.groups()))
if tags: print(".".join(map(str, max(tags))))
'
}
choose_version() {
  local current="$1" base="$2" choice="" custom=""
  while true; do
    cat >&2 <<MENU
Current local version: $current
Published-version baseline: $base

Choose release type:
  1) patch  ($(bump_version "$base" patch))
  2) minor  ($(bump_version "$base" minor))
  3) major  ($(bump_version "$base" major))
  4) build  ($(bump_version "$current" build))
  5) custom version
MENU
    read -r -p "Enter choice (1-5, default=1): " choice
    case "${choice:-1}" in
      1|patch|p) bump_version "$base" patch; return ;;
      2|minor|m) bump_version "$base" minor; return ;;
      3|major|M) bump_version "$base" major; return ;;
      4|build|b) bump_version "$current" build; return ;;
      5|custom|c)
        read -r -p "Enter version X.Y.Z+B: " custom
        validate_version "$custom"
        echo "$custom"
        return ;;
      *) echo "Choose 1, 2, 3, 4 or 5." >&2 ;;
    esac
  done
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) [[ $# -ge 2 ]] || exit 2; VERSION_OVERRIDE="$2"; shift 2 ;;
    --bump) [[ $# -ge 2 ]] || exit 2; BUMP_PART="$2"; shift 2 ;;
    --no-push) DO_PUSH=false; shift ;;
    --yes|-y) YES=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done
[[ -z "$VERSION_OVERRIDE" || -z "$BUMP_PART" ]] || {
  echo "Use only one of --version or --bump." >&2; exit 1;
}
command -v git >/dev/null || { echo "Git required." >&2; exit 1; }
BRANCH="$(git symbolic-ref --quiet --short HEAD)" || {
  echo "Cannot version-bump in detached HEAD." >&2; exit 1;
}
CURRENT_VERSION="$(get_version)"
validate_version "$CURRENT_VERSION"
LATEST="$(latest_tag)"
BASE="$CURRENT_VERSION"
if [[ -n "$LATEST" ]] && version_gt "$LATEST" "${CURRENT_VERSION%+*}"; then
  BASE="$LATEST+${CURRENT_VERSION#*+}"
fi
echo "Latest GitHub release tag: ${LATEST:-unknown}" >&2

if [[ -n "$VERSION_OVERRIDE" ]]; then
  NEXT_VERSION="$VERSION_OVERRIDE"
elif [[ -n "$BUMP_PART" ]]; then
  if [[ "$BUMP_PART" == build ]]; then
    NEXT_VERSION="$(bump_version "$CURRENT_VERSION" build)"
  else
    NEXT_VERSION="$(bump_version "$BASE" "$BUMP_PART")"
  fi
else
  NEXT_VERSION="$(choose_version "$CURRENT_VERSION" "$BASE")"
fi
validate_version "$NEXT_VERSION"
[[ "$CURRENT_VERSION" != "$NEXT_VERSION" ]] || {
  echo "Version already equals $NEXT_VERSION." >&2; exit 1;
}
if [[ -n "$LATEST" ]] &&
    ! version_gt "${NEXT_VERSION%+*}" "$LATEST"; then
  echo "Note: v${NEXT_VERSION%+*} is not newer than v$LATEST." >&2
  echo "GitHub will validate this commit but skip publishing a release." >&2
fi

if [[ "$DO_PUSH" == true ]]; then
  ACTION="commit all local changes and push"
else
  ACTION="commit all local changes locally (no push)"
fi
if [[ "$YES" != true ]]; then
  if [[ -n "$(git status --short)" ]]; then
    echo "Other local changes that will be included:"
    git status --short
  fi
  read -r -p "Bump to $NEXT_VERSION, $ACTION? [Y/n] " CONFIRM
  case "${CONFIRM:-y}" in y|Y|yes|YES) ;; *) echo "Cancelled"; exit 0 ;; esac
fi

# On macOS, sed -i requires an explicit empty backup suffix.
sed -i '' "s/^version: .*/version: $NEXT_VERSION/" "$PUBSPEC_FILE"
git add -A
if git diff --cached --quiet; then
  echo "Nothing changed; no commit created." >&2
  exit 1
fi
git commit -m "Release $APP_NAME $NEXT_VERSION"
echo "Version: $CURRENT_VERSION -> $NEXT_VERSION"

if [[ "$DO_PUSH" == true ]]; then
  "$ROOT_DIR/bin/pull-latest.sh"
  git push origin "$BRANCH"
  echo "Pushed version to origin/$BRANCH."
fi
