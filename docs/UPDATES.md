# Siftidy update delivery (v0.1)

## Check for updates inside the app

- **macOS:** On launch, Siftidy reads the latest stable release metadata from
  the public GitHub Releases API. It offers a Download update link **only**
  when the release contains a macOS .dmg, .pkg or .zip asset named for macOS.
  The user chooses when to download/install. The app does **not** replace its
  running binary or bypass Gatekeeper.
- **iOS:** On launch, Siftidy reads
  https://raw.githubusercontent.com/ssnanda/Siftidy/main/altstore.json .
  It compares installed version against entries for com.siftidy.siftidy.
  The Updates dialog can open the feed in AltStore Classic; AltStore handles
  installing/resigning/updating the iPhone app.
- Both platforms offer a **Check now** action and an **automatic checks on
  launch** switch. This preference defaults **on** and can be disabled.
- The only outbound application request is public version metadata.
  No media, identifiers, user accounts, or analytics are uploaded to Siftidy.

## Publishing a working update

1. Bump pubspec.yaml version/build, and create GitHub Release tagged vX.Y.Z.
2. Attach a distribution-ready, signed macOS build named with macOS and
   ending in .dmg, .pkg or .zip. Unsigned macOS CI debug artifacts are *not*
   releases. Test Gatekeeper/notarization or document local testing rules.
3. To publish for AltStore Classic, attach exactly one **signed device IPA**
   with Siftidy in its name, whose Info.plist has bundle ID
   com.siftidy.siftidy, marketing version X.Y.Z, and a valid build number.
   This must not be the iOS simulator .app debug archive.
4. Publish the GitHub Release. The Publish AltStore source workflow verifies
   the IPA, reads its bundle metadata/privacy permissions/signing entitlements,
   then commits a real entry to altstore.json on main. If no IPA is attached,
   the feed remains unchanged. If an asset was added after publishing, run the
   workflow manually with the existing release tag.
5. The source is for **AltStore Classic**. AltStore PAL requires a notarized
   alternative-distribution package (ADP), not an ordinary IPA.

The source intentionally begins with an empty apps list. There is currently no
installable signed iOS release and no macOS Release asset; the updater reports
this rather than offering a broken download.

## CI cleanup

- On the successful main-branch Apple build, GitHub Actions deletes *older*
  artifacts named siftidy-apple-debug-builds, preserving the new one.
- Debug artifacts have a seven-day retention limit.
- Both CI jobs clean their temporary build directories with always() steps,
  including failure paths. GitHub-hosted runners are also discarded by GitHub.
- GitHub Release assets are **never deleted** by CI cleanup.
- The checked-in source and the AltStore JSON feed are **never deleted**.

Check https://github.com/ssnanda/Siftidy/actions for job outcomes.

## Automated GitHub Releases

Pushes to `main` and manual runs of **Build and publish Siftidy** build an unsigned iPhone IPA (for AltStore Classic re-signing) and a universal `arm64` + `x86_64` macOS app, published as both ZIP and DMG. The macOS builds are not notarized. Version names use the pubspec major/minor and the Release workflow run number. The pipeline updates `altstore.json` after the Release is published; its commit skips CI to prevent a loop.

The **Prune old Actions runs** workflow runs daily or manually and also runs after successful releases. It preserves the latest five executions of each workflow and deletes completed runs older than seven days. Released binaries, release tags and release history are retained. Cleanup of local build directories runs even when a release build fails.
