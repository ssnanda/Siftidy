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
for tool in flutter xcodebuild swift sips ditto lipo; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required tool: $tool" >&2; exit 1;
  }
done
xcodebuild -version >/dev/null

RAW_VERSION="$(sed -nE 's/^version: ([^[:space:]]+).*$/\1/p' pubspec.yaml)"
[[ "$RAW_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$ ]] || {
  echo "Invalid pubspec.yaml version: $RAW_VERSION" >&2; exit 1;
}
RELEASE_VERSION="${BASH_REMATCH[1]}"
BUILD_NUMBER="${BASH_REMATCH[2]}"
echo "Building Siftidy $RELEASE_VERSION+$BUILD_NUMBER for macOS..."

# flutter create overwrites analysis_options.yaml; restore the local version
# even if the build fails. Don't alter existing user changes in this file.
BACKUP_ANALYSIS=""
if [[ -f analysis_options.yaml ]]; then
  BACKUP_ANALYSIS="$(mktemp "${TMPDIR:-/tmp}/siftidy-analysis.XXXXXX")"
  cp -p analysis_options.yaml "$BACKUP_ANALYSIS"
fi
restore_analysis() {
  if [[ -n "$BACKUP_ANALYSIS" && -f "$BACKUP_ANALYSIS" ]]; then
    cp -p "$BACKUP_ANALYSIS" "$ROOT_DIR/analysis_options.yaml"
    rm -f "$BACKUP_ANALYSIS"
  fi
}
trap restore_analysis EXIT

./scripts/bootstrap_apple.sh
flutter build macos --release \
  --build-name="$RELEASE_VERSION" --build-number="$BUILD_NUMBER"

BUILT_APP="$(find build/macos/Build/Products/Release \
  -maxdepth 1 -type d -name 'Siftidy.app' -print -quit)"
[[ -n "$BUILT_APP" ]] || {
  echo "Build finished without finding Siftidy.app" >&2; exit 1;
}
echo "Built app: $ROOT_DIR/$BUILT_APP"

if [[ "$PACKAGE" == true ]]; then
  export RELEASE_VERSION BUILD_NUMBER
  ./scripts/package_release.sh
  echo "ZIP: $ROOT_DIR/dist/Siftidy-macOS-universal-v$RELEASE_VERSION.zip"
fi

if [[ "$OPEN_APP" == true ]]; then
  open "$BUILT_APP"
fi

echo "Local macOS build completed successfully."
