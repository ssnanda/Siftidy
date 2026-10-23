# Siftidy for macOS

![Siftidy photo-stack mark](assets/branding/siftidy_mark.svg)

**Private, review-first Apple Photos cleanup on the Mac.**

Siftidy is currently a **macOS-only hobby project**. iOS development and distribution have been discontinued. It runs locally through Flutter and PhotoKit; it never uploads your photo library to an application server. PhotoKit may use iCloud Photos as part of Apple's own system behavior.

## Features

- Starts with the native Apple Photos **Screenshots** smart album.
- Left sidebar with Screenshots, All Media, Photos, Videos, Favorites, Screen Recordings (if available), and existing user-created Photos albums.
- Load **50 images per page**, with automatic progressive loading as you scroll or explicit Load More.
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

## Intelligent Cleanup (v0.2)

Click the sparkles icon in the main toolbar, then **Scan Photos library**. Results
are grouped into verified exact-byte duplicates, visual lookalikes, possibly blurry
photos and photos where Apple Vision found no face or human rectangle. The latter
**does not prove a picture has no person**. Select photos individually to add them
to Keepers or request deletion through Apple Photos. Scanning never deletes items,
and existing Keepers are excluded from suggestions. Original-file hashing may
cause Apple Photos to download iCloud originals; the scan can be stopped.

The macOS gallery opens in a larger, screen-aware window (up to 1450 × 950 points) and remembers subsequent user resizing.

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


## Duplicate groups, deletion sizes and activity

Exact Duplicates and Similar Photos show one tile per set (×2, ×3, etc.).
Choose sets individually or Select All, optionally use **Review copies** to
choose which original stays, then **Keep one · Delete extras**.
The native Apple Photos deletion request requires confirmation; Siftidy never
silently removes the extras. In **Review copies**, **Keep all photos** dismisses
the group without moving, editing or deleting a single image. **Not similar**
dismisses a mistaken Similar Photos recommendation. Both choices hide that
suggestion for the current scan, including while more photos are being analyzed.
Other cleanup views support Select All and the same photo preview and deletion
actions as the browser.

**Discard scan results** stops any active scan and forgets all suggestions for
every cleanup category, without modifying Apple Photos. Turn off **Auto scan on
launch** if you do not want a fresh scan the next time Siftidy starts; otherwise
you can always run a manual scan later. Separate screenshots now need a stricter
spatial-layout match before being classified as similar: large white or blank
areas alone are not enough to consider different screenshots duplicates.

Apple Photos media types and albums appear in the **left** sidebar, while
Siftidy's cleanup categories and Deletion activity appear in the **right**.
The Mac window fills the usable screen area below the menu bar (not fullscreen)
on every launch and remains resizable.

Selected original-file sizes are measured lazily when available; iCloud may
download originals, and unknown sizes are explicitly labeled. **Deletion
activity** records the count and measured sizes of media deleted by Siftidy.
Apple Photos' protected **Recently Deleted** contents cannot be read or emptied
through Siftidy's ordinary PhotoKit access. The left sidebar shortcut opens
Apple Photos so users can inspect or empty it directly. Siftidy therefore
reports neither its live item count nor confirmed disk space freed.

## Menu-bar background scanning (v0.2)

Closing the main window **hides it without terminating Siftidy**. The scan
continues in the menu bar while the Mac is awake. Hover over the small ▧
percentage status item to see total/scanned/pending counts, analyzed photos,
approximate ETA, current process CPU percentage, current resident RAM, and
effective scanning speed. Click for **Open Siftidy**, **Start**, **Pause /
Resume**, **Stop**, **Discard scan results**, scan-speed settings, and **Quit
Completely**. Quit Completely actually terminates the application.

Scan profiles may be changed while scanning:

| Mode | Approximate process CPU target | Parallel thumbnail workers |
| --- | --- | --- |
| Minimal | 1–3% | 1 |
| Eco (default) | 5–10% | 1 |
| Balanced | 20–40% | 2 |
| Turbo | Can use multiple CPU cores | 4 |

Process CPU percentages use the macOS convention where 100% is one busy
logical CPU. These are **best-effort average targets, not hard CPU quotas**:
PhotoKit decoding, iCloud transfers and Flutter can create short spikes.
Throttling is adaptive and conservatively delays work in quiet modes. Turbo
parallelizes *thumbnail decoding and Vision requests* in batches of up to four;
photo-library writes/deletion remain user-driven and serial. A scan is never
allowed to delete photos automatically.

Choose **Turbo for 30, 60 or 120 minutes** from the menu. Once the Mac has
been idle for 20 seconds, returning to keyboard/mouse activity switches back
to the configured mode. Turbo also ends at its chosen timeout. Optional
**Auto Turbo after 10 minutes idle** requires AC power and automatically
returns to the selected normal speed on user activity. Serious thermal
pressure reduces the effective speed to Eco. Automatic Turbo is **off by
default**. A scan does not keep a sleeping Mac awake. Results are maintained
only while Siftidy remains running, not across **Quit Completely**.

Menu-bar operation removes the window from the screen and clears the gallery's
decoded-image cache, but the Flutter engine and the in-progress scan remain
in memory. It is not a separate lightweight daemon. CPU and memory readings
are for the whole Siftidy process, not an isolated worker.

## Persistent scan progress, scan history & disk usage

Scan progress now survives closing and quitting Siftidy, Mac restarts and
application updates. Every completed scan batch flushes a local JSONL
checkpoint, including the analyzed thumbnail fingerprint, image dimensions,
verified exact-duplicate hashes when available, screenshot/people flags,
visited/ignored/skipped PhotoKit IDs and processing metrics. Existing entries
are reused after relaunch, without re-decoding every cached thumbnail.

The data lives in the macOS app's **Application Support / ScanData** directory.
Use **History & storage** in the Siftidy scanning screen, or **Scan history &
storage** in the menu-bar dropdown, to see and copy its actual absolute path,
open it in Finder, and display measured bytes for the active checkpoint,
historical summaries, and total directory usage.

The active result dataset is preserved until you start a differently scoped
scan or click **Discard scan results**. The history records up to 30 past
scan summaries (date, outcome, duration, visited, analyzed, skipped, rate,
average measured process CPU, peak RAM and per-mode duration); it does not
retain full copies of historical scan datasets. The current cache is local
only and does not contain original/full-resolution photo files.

A scan that started under **v0.2.8 or earlier cannot be resumed**, because
those versions never wrote an on-disk scan journal. The first scan after this
update must analyze those photos again, then it can resume after later updates.
