#!/usr/bin/env bash
# Package universal macOS builds only. Siftidy no longer ships an iPhone IPA.
set -euo pipefail
: "${RELEASE_VERSION:?RELEASE_VERSION not set}"
: "${BUILD_NUMBER:?BUILD_NUMBER not set}"

MAC_APP=$(find build/macos/Build/Products/Release -maxdepth 1 -type d -name '*.app' -print -quit)
[[ -n "$MAC_APP" ]] || { echo "No release macOS app"; exit 1; }
MAC_BINARY=$(find "$MAC_APP/Contents/MacOS" -maxdepth 1 -type f -print -quit)
[[ -n "$MAC_BINARY" ]] || { echo "No executable in macOS app"; exit 1; }
ARCHS=$(lipo -archs "$MAC_BINARY")
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || {
  echo "macOS app is not universal: $ARCHS"; exit 1;
}
MAC_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MAC_APP/Contents/Info.plist")
[[ "$MAC_VERSION" == "$RELEASE_VERSION" ]] || { echo "Incorrect macOS version $MAC_VERSION"; exit 1; }

mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$MAC_APP" "dist/Siftidy-macOS-universal-v$RELEASE_VERSION.zip"
hdiutil create -volname "Siftidy" -srcfolder "$MAC_APP" -ov -format UDZO \
  "dist/Siftidy-macOS-universal-v$RELEASE_VERSION.dmg"

unzip -tq "dist/Siftidy-macOS-universal-v$RELEASE_VERSION.zip"
echo "Built Siftidy $RELEASE_VERSION (macOS: $ARCHS)"
ls -lh dist
