#!/usr/bin/env bash
# Build Siftidy on this Mac using the exact version in pubspec.yaml.
# Produces a native .app and a verified universal ZIP under dist/.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OPEN_APP=false
PACKAGE=true

usage() {
  cat <<'USAGE'
Build Siftidy for macOS locally.

Usage:
  ./bin/build-mac.sh [--open] [--no-zip] [--help]

  --open     Launch the built .app after a successful build.
  --no-zip   Build the app without packaging a release ZIP.
  --help     Show this help.

Requires macOS, full Xcode, CocoaPods, Flutter, and the Xcode CLI tools.
The .app is written to build/macos/Build/Products/Release/.
The universal ZIP is written to dist/ (unless --no-zip is supplied).
No GitHub release is published. Existing installed apps are not overwritten.
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --open) OPEN_APP=true ;;
    --no-zip) PACKAGE=false ;;
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
  echo "ZIP: $ROOT_DIR/dist/Siftidy-macOS-universal-v$RELEASE_VERSION.zip"
fi

if [[ "$OPEN_APP" == true ]]; then
  open "$BUILT_APP"
fi

echo "Local macOS build completed successfully."
