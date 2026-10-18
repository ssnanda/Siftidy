# v0.1 technical architecture

- `lib/main.dart`: app shell and shared Material 3 theme.
- `lib/library/library_repository.dart`: PhotoKit-backed media data and delete boundaries via `photo_manager`.
- `lib/library/filtering.dart`: filter/search display semantics and human-friendly size formatting, with unit tests.
- `lib/library/library_screen.dart`: permission management, lazy 100-item paging, thumbnails, selection and previews.
- `lib/library/selection_review.dart`: optional file-size inspection and two independent deletion confirmations.
- `scripts/bootstrap_apple.sh`: generates the standard Flutter iOS and macOS host runners and applies Photos entitlements/purpose strings.

### Privacy and data safety

Image content is not sent to Siftidy servers. Thumbnails are requested locally through PhotoKit. iCloud Photos may download thumbnails/files as part of Apple's Photos service. Siftidy requests Photos access and may request a system deletion only for user-selected IDs. Favorites are never automatically excluded, but they are visibly indicated; v0.3 will add explicit favorite protection.

### Platform and build status

The source is written for Flutter stable and the latest `photo_manager` plugin with iOS and macOS support. The GitHub Actions workflow performs static checks and unsigned Apple compile checks on a macOS runner. Apple device signing and runtime Photos behavior must be verified on a real iPhone and a Mac before calling v0.1 production-ready. The Python/Linux authoring environment cannot run Xcode and has not compiled an Apple app locally.

### Known limits

The app uses an in-memory list of fetched assets, not a SQLite index. Filters for favorites only operate on pages already loaded. Storage inspection uses the file returned by PhotoManager; it can be unavailable or cause system-managed iCloud retrieval. Progress counts measured files; it does not represent byte-accurate disk recovery. Deletion can sync to iCloud Photos and does not immediately purge Recently Deleted.
