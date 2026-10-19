# Siftidy macOS architecture

- `lib/main.dart`: shared Flutter app shell, currently released only on macOS.
- `lib/library/library_repository.dart`: PhotoKit album discovery, smart-album subtypes, pagination and user-confirmed deletion.
- `lib/library/filtering.dart`: view and sort semantics.
- `lib/library/library_screen.dart`: macOS album sidebar, Screenshots default, 25-item pagination, tap-to-select, bulk checkbox, and delete action.
- `lib/library/selection_review.dart`: two-stage explicit deletion confirmations and optional size measurement.
- `lib/updates/`: GitHub Releases-based macOS update checks only.
- `scripts/bootstrap_apple.sh`: generates the macOS Flutter runner and sets Photos permissions.
- `scripts/package_release.sh`: creates universal ZIP and DMG, checking both architectures.

This version reads actual Photos smart album membership rather than guessing that screenshots can be recognized from file extensions or image pixels. The user album sidebar is read-only navigation: no item moves or album edits happen when browsing. The All loaded checkbox selects at most the currently paged items. Photos deletion can sync to iCloud, normally placing items in Recently Deleted.

No perceptual similarity detection, people detection, verified backup/archive, or arbitrary Mac folder scanning is implemented yet.
