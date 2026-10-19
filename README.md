# Siftidy for macOS

![Siftidy photo-stack mark](assets/branding/siftidy_mark.svg)

**Private, review-first Apple Photos cleanup on the Mac.**

Siftidy is currently a **macOS-only hobby project**. iOS development and distribution have been discontinued. It runs locally through Flutter and PhotoKit; it never uploads your photo library to an application server. PhotoKit may use iCloud Photos as part of Apple's own system behavior.

## Features

- Starts with the native Apple Photos **Screenshots** smart album.
- Left sidebar with Screenshots, All Media, Photos, Videos, Favorites, Screen Recordings (if available), and existing user-created Photos albums.
- Load **25 images per page**, with automatic progressive loading as you scroll or explicit Load More.
- **Single-click to select/deselect** and build multi-selection; grid clicks do not open a photo preview.
- **All loaded** checkbox applies to currently loaded items in the current view, not the entire Photos library.
- **Double-click** opens preview. In the grid, **Arrow keys** select and move focus, **Space** toggles selection, **Enter** opens preview, and **Delete** deletes selected items. In preview, **arrows** navigate and select without deselecting, **Space** toggles only the current photo, and **Enter** closes preview.
- **Keep in Keepers** saves a screenshot to a real Apple Photos album named **Siftidy Keepers**. Kept screenshots are excluded from Siftidy's default Screenshots view and protected from Siftidy's Delete action. This does not remove their native screenshot classification in Apple Photos.
- The grid uses fixed cached thumbnail tiles and updates lightweight selection overlays instead of re-decoding photos on every click.
- **Privacy & Security** shortcut in the update dialog opens macOS Settings (Apple's Open Anyway action itself cannot be deep-linked).
- The larger, high-contrast **Delete selected** button (or the keyboard Delete key) immediately requests deletion through Apple Photos. Siftidy adds no dialog; Apple Photos may still show a system confirmation.
- Photo/video thumbnails, sorting by age, refresh, optional estimated size inspection, Photos permission handling.
- macOS update checks via public GitHub Releases, configurable on/off, with a one-click **Update & Restart** action for writable Applications installations.

**Important:** Deleting photos may sync deletions to iCloud Photos and other Apple devices. Photos normally moves them to Recently Deleted. Make backups before using deletion; estimated storage savings are not guaranteed.

## Install and run

[Latest macOS Releases](https://github.com/ssnanda/Siftidy/releases) include one universal macOS ZIP package for Intel and Apple Silicon. They are currently unsigned and unnotarized, so macOS may show a Gatekeeper warning. Do not disable Gatekeeper globally.

For local development, install Flutter, Xcode and CocoaPods, clone this repository, then run `./scripts/bootstrap_apple.sh` followed by `flutter run -d macos`. Run `flutter analyze` and `flutter test` for source checks.

## Workflow

The only workflow file is `.github/workflows/siftidy.yml`:
validation → universal macOS build → GitHub Releases (ZIP only) → Actions cleanup. A successful Mac release also removes retired IPA and DMG assets from historical Releases, without deleting Mac packages or release tags. The obsolete AltStore feed and iOS build pipeline have been deleted.

The current release is intended for personal testing, not a notarized production installation.

### Mac rendering compatibility

Siftidy currently disables Flutter's default macOS Impeller renderer to investigate corrupted text/dialogs and stale frames. The build pipeline verifies the flag in the actual app ZIP. This is a compatibility workaround, and should be checked on the affected Mac before treating the issue as resolved. Newer releases also fix frozen update progress dialogs with visible errors and a ZIP fallback.

## Siftidy branding

The photo-stack icon is the Siftidy identity: layered photo cards, a golden sun, and teal/blue mountains. The editable vector design is at `assets/branding/siftidy_mark.svg`. The Flutter header paints a matching lightweight mark with no image decoding; the macOS bootstrap uses `scripts/render_macos_icon.swift` to generate matching icon assets from 16 to 1024 pixels for Finder and the Dock. The build ships those native icons as part of the macOS application, without any added image/network dependency.
