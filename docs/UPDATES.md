# macOS updates and distribution

Only macOS is maintained. The application checks GitHub's latest Release metadata on launch if automatic checks are enabled; checks can be disabled in the update dialog. Images and photo metadata are never uploaded by this feature. When an update is available, **Update & Restart** downloads the GitHub ZIP, checks its release SHA-256 digest and app bundle identity/version, and starts a detached installer that replaces the existing app in a writable /Applications or ~/Applications location after Siftidy quits. The old installation is retained until replacement succeeds and is restored on failure. A non-writable /Applications directory still requires manual installation.

The single GitHub Actions workflow validates on pushes and pull requests, builds one universal macOS Flutter app (Intel x86_64 and Apple Silicon arm64), publishes ZIP only, and cleans temporary working files. A separate job within the same workflow removes old completed Actions runs and retired IPA/DMG assets. Weekly scheduled and manual cleanup do not build.

Previous signed/unsigned iPhone packages are retired and removed from historical GitHub Releases by the post-publish cleanup. The AltStore JSON feed and synchronization script are removed from source. No iOS releases will be produced.

The universal Mac ZIP is currently unsigned and unnotarized. Apple's Gatekeeper may require manual approval. Developer ID signing and notarization can be added later.

## Gatekeeper and privacy

The app offers **Privacy & Security** inside its update dialog and when PhotoKit permission is denied. It attempts to open System Settings' Privacy & Security pane, falling back to System Settings. This cannot bypass Apple's Open Anyway requirement or make the app automatically trusted. Automatic updates are disabled for non-writable system Applications installs; no privileged helper is installed.
