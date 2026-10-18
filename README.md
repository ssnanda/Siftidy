# Siftidy

**Private, review-first media cleanup for iPhone and Mac.**

Siftidy is a hobby project that helps organize and review your Apple Photos library without uploading photos to a server. The app is at **v0.1 (early development)**. Pushes to `main` create versioned unsigned IPA and universal macOS GitHub Releases; releases are not Apple notarized.

## v0.1 — what is implemented

- One Flutter UI for **iOS and macOS** using the platform-backed `photo_manager` (PhotoKit) integration.
- Local media thumbnails, fullscreen photo preview, basic video thumbnail preview.
- Photos, videos, and favorites filters; oldest/newest ordering.
- Paged library loading (100 assets per request), load-more and refresh.
- Long-press/tap selection and select-currently-loaded-media.
- Explicit selected-items review, optional file-size measurement with progress, and **two-step manual deletion** using the platform's Photos confirmation.
- Handling of full/limited/denied permission states and system Settings.
- GitHub Actions analysis and tests, automatic unsigned iPhone IPA + universal macOS ZIP/DMG release assets, and an AltStore feed.

**Deletion warning:** When you delete items in Apple Photos, deletions can sync to other devices using iCloud Photos. Items normally move to Recently Deleted. Siftidy does not offer an instant undo, verified backup, or automatic duplicate cleanup in v0.1. Back up important media before testing deletion. The displayed size is an approximation and is **not** a guaranteed amount of immediately reclaimed device storage.

## Local development (requires a Mac)

1. Install recent stable Flutter, Xcode and CocoaPods and run `flutter doctor`.
2. Clone this repository and run `./scripts/bootstrap_apple.sh` from the project root. This generates standard Flutter iOS/macOS runners locally and inserts required Photos permission strings and macOS entitlements.
3. Run `flutter run -d macos` for a local Mac app, or use `flutter devices` and `flutter run -d <device-id>` for iOS. For a physical iPhone, configure your Apple Development signing team in `ios/Runner.xcworkspace` first.
4. Run `flutter analyze` and `flutter test` for static and unit checks.

Runner files under `ios/` and `macos/` are intentionally generated instead of committed: run bootstrap on a Mac after cloning and after `flutter clean` if you remove the runner. Do not run the app against irreplaceable photos until you've made a backup. An iPhone cannot build or run macOS Flutter apps without a Mac/Xcode build machine.

## Project boundaries

- Local first: no user accounts, analytics, or photo telemetry. An optional automatic update check (on by default, switchable off) fetches only public GitHub Release or AltStore JSON version metadata. PhotoKit may communicate with iCloud as part of the system's Photos implementation.
- v0.1 only: no perceptual similarity, no people detection, no ranking large files, no Mac arbitrary-folder scan, no NAS/Ubuntu verified backup, no iMessage or WhatsApp direct database access.
- Favorites searches apply to **currently loaded batches**; load more to include older items. Full-library indexing is planned for later.
- v0.1 video preview is a thumbnail, not a video player.
- Apple Photos may prompt for final confirmation after Siftidy's two review steps.

See [docs/ROADMAP.md](docs/ROADMAP.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and [docs/UPDATES.md](docs/UPDATES.md).

## Update source

- AltStore Classic JSON: https://raw.githubusercontent.com/ssnanda/Siftidy/main/altstore.json
- macOS download releases: https://github.com/ssnanda/Siftidy/releases
- Both platforms check on launch (configurable in the app) and provide a manual check; installation remains user-controlled.
- Every push to `main` (excluding docs/AltStore-only edits) or manual Release workflow run builds an unsigned iPhone IPA suitable for AltStore Classic re-signing, plus both Intel/Apple Silicon macOS ZIP and DMG packages. Release numbers use `vMAJOR.MINOR.<workflow run number>`; the AltStore source is updated after the Release publishes.
- iOS installation requires AltStore Classic (which re-signs the IPA); the published macOS builds are **unsigned and unnotarized**, so Gatekeeper may block them. Native signed/notarized releases require Apple Developer signing credentials.
- CI removes generated iOS/macOS runners and temporary build directories after each release attempt. A scheduled cleanup and post-release cleanup delete completed workflow runs after 7 days while preserving the newest five per workflow. Published Releases, tags, and assets are **never deleted** by cleanup.
