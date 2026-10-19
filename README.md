# Siftidy for macOS

**Private, review-first Apple Photos cleanup on the Mac.**

Siftidy is currently a **macOS-only hobby project**. iOS development and distribution have been discontinued. It runs locally through Flutter and PhotoKit; it never uploads your photo library to an application server. PhotoKit may use iCloud Photos as part of Apple's own system behavior.

## Features

- Starts with the native Apple Photos **Screenshots** smart album.
- Left sidebar with Screenshots, All Media, Photos, Videos, Favorites, Screen Recordings (if available), and existing user-created Photos albums.
- Load **25 images per page**, with automatic progressive loading as you scroll or explicit Load More.
- **Single-click to select/deselect** and build multi-selection; grid clicks do not open a photo preview.
- **All loaded** checkbox applies to currently loaded items in the current view, not the entire Photos library.
- **Delete selected** opens two review/confirmation steps before requesting deletion through Apple's Photos API.
- Photo/video thumbnails, sorting by age, refresh, optional estimated size inspection, Photos permission handling.
- macOS update checks via public GitHub Releases, configurable on/off.

**Important:** Deleting photos may sync deletions to iCloud Photos and other Apple devices. Photos normally moves them to Recently Deleted. Make backups before using deletion; estimated storage savings are not guaranteed.

## Install and run

[Latest macOS Releases](https://github.com/ssnanda/Siftidy/releases) include universal macOS ZIP and DMG packages for Intel and Apple Silicon. They are currently unsigned and unnotarized, so macOS may show a Gatekeeper warning. Do not disable Gatekeeper globally.

For local development, install Flutter, Xcode and CocoaPods, clone this repository, then run `./scripts/bootstrap_apple.sh` followed by `flutter run -d macos`. Run `flutter analyze` and `flutter test` for source checks.

## Workflow

The only workflow file is `.github/workflows/siftidy.yml`:
validation → universal macOS build → GitHub Releases (ZIP and DMG) → Actions cleanup. A successful Mac release also removes retired IPA assets from historical Releases, without deleting Mac packages or release tags. The obsolete AltStore feed and iOS build pipeline have been deleted.

The current release is intended for personal testing, not a notarized production installation.
