#!/usr/bin/env bash
# Initialize reproducible macOS Flutter runner and required Photos settings.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v flutter >/dev/null || { echo 'Flutter SDK is required.' >&2; exit 1; }
command -v /usr/libexec/PlistBuddy >/dev/null || {
  echo 'Run this on macOS with Xcode installed.' >&2; exit 1;
}
flutter create --project-name siftidy --org com.siftidy --platforms=macos .
flutter pub get

# Flutter may generate a sample test for 'MyApp', which this app does not use.
# Never remove a real application test.
if [[ -f test/widget_test.dart ]] && grep -q 'await tester.pumpWidget(const MyApp())' test/widget_test.dart; then
  rm test/widget_test.dart
fi

plist_set_string() {
  local plist="$1" key="$2" value="$3"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
}
plist_set_bool() {
  local plist="$1" key="$2"
  /usr/libexec/PlistBuddy -c "Set :$key true" "$plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add :$key bool true" "$plist"
}

plist_set_string macos/Runner/Info.plist NSPhotoLibraryUsageDescription \
  'Siftidy needs access to show, review and optionally delete media you select.'
plist_set_string macos/Runner/Info.plist NSPhotoLibraryAddUsageDescription \
  'Siftidy only changes your Photos library when you confirm an action.'
plist_set_string macos/Runner/Info.plist CFBundleDisplayName 'Siftidy'
for entitlements in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
  plist_set_bool "$entitlements" com.apple.security.personal-information.photos-library
  plist_set_bool "$entitlements" com.apple.security.network.client
done
# The self-updater must replace a user-installed .app inside /Applications.
# The Release app is not sandboxed; keep the sandbox for local debug builds.
# This is explicitly not a Mac App Store distribution.
 /usr/libexec/PlistBuddy -c 'Set :com.apple.security.app-sandbox false' \
   macos/Runner/Release.entitlements 2>/dev/null || true

echo 'Ready: flutter run -d macos'
