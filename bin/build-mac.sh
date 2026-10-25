#!/usr/bin/env bash
# Build Siftidy on this Mac using the exact version in pubspec.yaml.
# Produces a native .app, verifies a universal ZIP, and uploads it to GitHub Releases.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OPEN_APP=false
PACKAGE=true
UPLOAD=true

usage() {
  cat <<'USAGE'
Build Siftidy for macOS locally.

Usage:
  ./bin/build-mac.sh [--open] [--no-upload] [--no-zip] [--help]

  --open       Launch the built .app after a successful build.
  --no-upload  Build and package locally without uploading to GitHub.
  --no-zip     Build the .app only (also skips upload).
  --help       Show this help.

Requires macOS, Xcode, CocoaPods, and Flutter.
Uploading additionally requires GitHub CLI (gh), authentication, and clean,
pushed source. A successful build publishes the verified ZIP to the matching
GitHub Release tag; an existing version's ZIP is replaced.
Existing installed apps are not overwritten.
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --open) OPEN_APP=true ;;
    --no-upload) UPLOAD=false ;;
    --no-zip) PACKAGE=false; UPLOAD=false ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "This build script must be run on macOS." >&2; exit 1;
}
for tool in flutter xcodebuild swift sips ditto lipo python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required tool: $tool" >&2; exit 1;
  }
done
xcodebuild -version >/dev/null
[[ -x /usr/libexec/PlistBuddy ]] || {
  echo "Missing macOS PlistBuddy; install the Xcode command line tools." >&2
  exit 1
}

RAW_VERSION="$(sed -nE 's/^version: ([^[:space:]]+).*$/\1/p' pubspec.yaml)"
[[ "$RAW_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$ ]] || {
  echo "Invalid pubspec.yaml version: $RAW_VERSION" >&2; exit 1;
}
RELEASE_VERSION="${BASH_REMATCH[1]}"
BUILD_NUMBER="${BASH_REMATCH[2]}"
echo "Building Siftidy $RELEASE_VERSION+$BUILD_NUMBER for macOS..."

if [[ "$UPLOAD" == true ]]; then
  command -v gh >/dev/null 2>&1 || {
    echo "GitHub CLI is required to upload: brew install gh" >&2
    echo "Or use --no-upload for a local-only build." >&2
    exit 1
  }
  gh auth status --hostname github.com >/dev/null 2>&1 || {
    echo "Sign in before publishing: gh auth login" >&2
    exit 1
  }
  command -v git >/dev/null 2>&1 || {
    echo "Git is required to identify the release source." >&2
    exit 1
  }
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "Commit tracked changes before uploading a release." >&2
    echo "Or use --no-upload to build locally." >&2
    exit 1
  fi
  SOURCE_HEAD="$(git rev-parse HEAD)"
  SOURCE_BRANCH="$(git symbolic-ref --quiet --short HEAD)" || {
    echo "Checkout a branch before publishing a release." >&2
    exit 1
  }
  REMOTE_HEAD="$(git ls-remote --heads origin "$SOURCE_BRANCH" | awk '{print $1}')"
  if [[ -z "$REMOTE_HEAD" || "$REMOTE_HEAD" != "$SOURCE_HEAD" ]]; then
    echo "Push the current commit to origin/$SOURCE_BRANCH before publishing." >&2
    echo "Or use --no-upload to build locally." >&2
    exit 1
  fi
  RELEASE_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  [[ -n "$RELEASE_REPO" ]] || {
    echo "Could not identify the GitHub release repository." >&2
    exit 1
  }
fi

# flutter create may regenerate source config; always put the user's
# originals back on success or failure (including local, uncommitted edits).
BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/siftidy-build.XXXXXX")"
for item in analysis_options.yaml pubspec.yaml pubspec.lock; do
  if [[ -f "$item" ]]; then cp -p "$item" "$BACKUP_DIR/$item"; fi
done
restore_config() {
  for item in analysis_options.yaml pubspec.yaml pubspec.lock; do
    if [[ -f "$BACKUP_DIR/$item" ]]; then
      cp -p "$BACKUP_DIR/$item" "$ROOT_DIR/$item"
    fi
  done
  rm -rf "$BACKUP_DIR"
}
trap restore_config EXIT

./scripts/bootstrap_apple.sh
# The app must build with the exact source version, even if flutter create
# recreated the Flutter package metadata during bootstrap.
if ! cmp -s "$BACKUP_DIR/pubspec.yaml" pubspec.yaml; then
  echo "Restoring pubspec.yaml changed by Flutter bootstrap."
  cp -p "$BACKUP_DIR/pubspec.yaml" pubspec.yaml
  flutter pub get
fi
flutter build macos --release \
  --build-name="$RELEASE_VERSION" --build-number="$BUILD_NUMBER"

BUILT_APP="$(find build/macos/Build/Products/Release \
  -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$BUILT_APP" ]] || {
  echo "Build finished without finding Siftidy.app" >&2; exit 1;
}
BUNDLE_PLIST="$BUILT_APP/Contents/Info.plist"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUNDLE_PLIST")"
BUNDLE_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUNDLE_PLIST")"
if [[ "$BUNDLE_VERSION" != "$RELEASE_VERSION" ||
      "$BUNDLE_NUMBER" != "$BUILD_NUMBER" ]]; then
  echo "Version mismatch: requested $RELEASE_VERSION+$BUILD_NUMBER, app contains $BUNDLE_VERSION+$BUNDLE_NUMBER" >&2
  exit 1
fi
echo "Built app: $ROOT_DIR/$BUILT_APP ($BUNDLE_VERSION+$BUNDLE_NUMBER)"

if [[ "$PACKAGE" == true ]]; then
  export RELEASE_VERSION BUILD_NUMBER
  ./scripts/package_release.sh
  RELEASE_ZIP="$ROOT_DIR/dist/Siftidy-macOS-universal-v$RELEASE_VERSION.zip"
  [[ -s "$RELEASE_ZIP" ]] || { echo "Release ZIP missing or empty." >&2; exit 1; }
  echo "ZIP: $RELEASE_ZIP"
fi

# Restore tracked configuration before releasing, so the uploaded binary
# corresponds to the clean source checked at startup.
restore_config

if [[ "$UPLOAD" == true ]]; then
  RELEASE_TAG="v$RELEASE_VERSION"
  if gh release view "$RELEASE_TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    echo "Updating ZIP in existing GitHub Release $RELEASE_TAG..."
    gh release upload "$RELEASE_TAG" "$RELEASE_ZIP" --clobber --repo "$RELEASE_REPO"
  else
    echo "Publishing GitHub Release $RELEASE_TAG..."
    gh release create "$RELEASE_TAG" "$RELEASE_ZIP" \
      --repo "$RELEASE_REPO" --target "$SOURCE_HEAD" \
      --title "Siftidy $RELEASE_VERSION" \
      --notes "Universal macOS ZIP for Intel and Apple Silicon. Built locally; not Apple Developer ID signed or notarized." \
      --latest
  fi
  echo "Published: https://github.com/$RELEASE_REPO/releases/tag/$RELEASE_TAG"
fi

if [[ "$OPEN_APP" == true ]];
  open "$BUILT_APP"
fi

echo "macOS build completed successfully."
