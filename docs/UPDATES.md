# macOS updates and distribution

Only macOS is maintained. The application checks GitHub's latest Release metadata on launch if automatic checks are enabled; checks can be disabled in the update dialog. Images and photo metadata are never uploaded by this feature. Update installation opens a GitHub Release download and requires user action.

The single GitHub Actions workflow validates on pushes and pull requests, builds one universal macOS Flutter app (Intel x86_64 and Apple Silicon arm64), publishes DMG and ZIP, and cleans temporary working files. A separate job within the same workflow removes old completed Actions runs and retired IPA assets. Weekly scheduled and manual cleanup do not build.

Previous signed/unsigned iPhone packages are retired and removed from historical GitHub Releases by the post-publish cleanup. The AltStore JSON feed and synchronization script are removed from source. No iOS releases will be produced.

Mac ZIP/DMG packages are currently unsigned and unnotarized. Apple's Gatekeeper may require manual approval. Developer ID signing and notarization can be added later.
