#!/usr/bin/env bash
# Create packages for AltStore Classic and both macOS architectures.
set -euo pipefail
: "${RELEASE_VERSION:?RELEASE_VERSION not set}"
: "${BUILD_NUMBER:?BUILD_NUMBER not set}"

IOS_APP="build/ios/iphoneos/Runner.app"
[[ -f "$IOS_APP/Info.plist" ]] || { echo "No release iPhone app"; exit 1; }
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$IOS_APP/Info.plist")
IOS_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$IOS_APP/Info.plist")
[[ "$BUNDLE_ID" == "com.siftidy.siftidy" ]] || { echo "Unexpected iOS bundle $BUNDLE_ID"; exit 1; }
[[ "$IOS_VERSION" == "$RELEASE_VERSION" ]] || { echo "Incorrect iOS version $IOS_VERSION"; exit 1; }

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
TMPDIR_IPA=$(mktemp -d)
trap 'rm -rf "$TMPDIR_IPA"' EXIT
mkdir -p "$TMPDIR_IPA/Payload"
ditto "$IOS_APP" "$TMPDIR_IPA/Payload/Runner.app"
(cd "$TMPDIR_IPA" && zip -qry "$OLDPWD/dist/Siftidy-iOS-v$RELEASE_VERSION.ipa" Payload)
ditto -c -k --sequesterRsrc --keepParent "$MAC_APP" "dist/Siftidy-macOS-universal-v$RELEASE_VERSION.zip"
hdiutil create -volname "Siftidy" -srcfolder "$MAC_APP" -ov -format UDZO \
  "dist/Siftidy-macOS-universal-v$RELEASE_VERSION.dmg"

unzip -tq "dist/Siftidy-iOS-v$RELEASE_VERSION.ipa"
unzip -tq "dist/Siftidy-macOS-universal-v$RELEASE_VERSION.zip"
echo "Built Siftidy $RELEASE_VERSION (macOS: $ARCHS)"
ls -lh dist
