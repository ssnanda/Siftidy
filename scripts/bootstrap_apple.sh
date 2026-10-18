#!/usr/bin/env bash
# Initialize reproducible iOS and macOS Flutter runners and required Photos settings.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v flutter >/dev/null || { echo 'Flutter SDK is required.' >&2; exit 1; }
command -v /usr/libexec/PlistBuddy >/dev/null || {
  echo 'Run this on macOS with Xcode installed.' >&2; exit 1;
}
flutter create --project-name siftidy --org com.siftidy --platforms=ios,macos .
flutter pub get

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

for plist in ios/Runner/Info.plist macos/Runner/Info.plist; do
  plist_set_string "$plist" NSPhotoLibraryUsageDescription \
    'Siftidy needs access to show, review and optionally delete media you select.'
  plist_set_string "$plist" NSPhotoLibraryAddUsageDescription \
    'Siftidy only changes your Photos library when you confirm an action.'
done
for entitlements in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
  plist_set_bool "$entitlements" com.apple.security.personal-information.photos-library
done

echo 'Ready: flutter run -d macos or flutter run -d <iOS device id>'
echo 'For iOS devices, select your signing team in Xcode first.'
