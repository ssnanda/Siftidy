# Siftidy roadmap — revised October 23, 2026

Siftidy is a **macOS-only**, privacy-first personal media cleanup app. The priority is to make scanning dependable before expanding intelligent cleanup. No iPhone/iOS app builds are planned under the current direction.

| Version | Focus | Priority |
| --- | --- | --- |
| **0.1** | Media browsing, selection, deletion, updates | Existing foundation |
| **0.2** | Scan stability, performance and history | Foundation |
| **0.3** | Smart Organization: accidental screenshots and property tours | **Current** |
| **0.4** | Advanced bulk cleanup and intelligent recommendations | Later |
| **0.5** | Verified backup, archive and restore | Later |
| **0.6** | Advanced organization and searchable collections | Later |
| **0.7** | Messages and WhatsApp media | Later |
| **0.8** | OCR search and automation | Later |
| **1.0** | Stable personal release | Target |

## 0.2 — Scan foundation

**Finish reliability before adding new detection features.**

### Implementation and verification sequence

1. **Scan engine reliability** — prove that scanning advances, pause/resume works, graceful quit saves checkpoints, and relaunch/update resumes actual processing without restarting completed analysis.
2. **Performance and background operation** — profile Minimal/Eco/Balanced/Turbo, bounded parallelism, resource use, responsive menu-bar operation and consistent status indicators.
3. **Scheduling and automation** — configurable scan schedules, idle/AC constraints and appropriate behavior through sleep, wake and interruption.
4. **Storage, metrics and history** — validate checkpoint integrity, recovery from partial writes, cache size/path, scan histories, durations, throughput and safe discard.
5. **End-to-end operational testing** — run the entire personal photo library, including interruptions and full quits; confirm no data loss or accidental deletion.
6. **Result validation — final v0.2 phase** — inspect exact-duplicate, similar, blurry and no-people results against selected real examples; verify saved results after reopening and test false positives/false negatives and Keep All/dismiss/keeper protection. Only tackle correctness defects and safety issues in v0.2; more sophisticated classification/ranking remains in v0.4.

The last phase may use **Claude or Codex** to inspect user-selected example images, expected/actual groups, and scanner code. Build a small opt-in reference set with examples of correct groups and false positives (especially visually similar people photos and mostly-white screenshots). Keep sensitive screenshots and family photos private by default; never upload personal images to GitHub or external tools automatically. All existing scan results remain review-first, with no automatic deletion.


- Keep scans running in the macOS menu bar when the window is closed or hidden with ⌘Q; make **Quit Completely** explicit.
- Recover scan progress, analyzed items and results from on-device checkpoints after a full quit, restart, or app update, including when the Photos library changes.
- Keep scan percentages and Running/Paused/Stopped/Completed status consistent between the window and menu bar.
- Preserve Minimal/Eco/Balanced/Turbo behavior, active speed and the remaining timed Turbo session across relaunch. Support idle/AC-aware scanning and user-controlled scheduling.
- Monitor process CPU/RAM, progress, processing rate, time remaining, elapsed duration, and scan history.
- Provide an inspectable local scan-data folder, actual cache size and safe **Discard scan results** behavior without modifying photos.
- Handle failed/interrupted scans, stale or corrupt checkpoints, partial writes and performance limits without silent resets.

**0.2 completion criterion:** A long Photos scan can be interrupted, resumed, accelerated, inspected and safely discarded with predictable results; its state is clear across the main window and menu bar; and final user-reviewed result validation confirms reliable, safe baseline outputs. Refinements beyond baseline correctness belong to later versions.

Existing exact-duplicate, similar-photo, blurry-photo and people-detection *review tools* are retained; substantial new intelligence in these tools is not the primary focus of 0.2.

## 0.3 — Smart Organization + practical cleanup (current)

### Active scan-results fixes

1. [x] Keep the last completed suggestions visible during incremental scans.
2. [x] Restore those suggestions when a paused scan resumes after relaunch.
3. [x] Reserve the final 5% of progress for post-scan result finalization.
4. [x] Checkpoint property-tour candidate progress and confirmed tours.
5. [x] Use the same finalization percentage in the window and menu bar.
6. [x] Persist an explicit user Pause across relaunches.
7. [x] Keep a deleted active history row hidden until new results complete.
8. [ ] Verify an interrupted full-library finalization in the packaged app.

### Property organization and result sizes

1. [x] Show measured original size per cleanup category and unique total.
2. [x] Resolve GPS-backed tour addresses with Apple and cache them locally.
3. [x] Group repeated dated tours beneath their property/address.
4. [x] Recognize garages, driveways, porches and residential exteriors.
5. [ ] Verify 6822 Trimbach Way and 958 Plaza Walk after a fresh scan.

**Shipped for testing:** six result tiles; on-device possible lock-screen,
near-blank and repeated-screenshot detection; 5+ consecutive property-photo
sessions validated with Apple Vision; local editable tour names and explicit
Apple reverse geocoding. Saved result snapshots and dismissals persist. These
are conservative *suggestions*, never automatic deletion, new Photos albums
or silent network calls. A new v0.3 scan is required; historical v0.2 results
show "not analyzed" rather than invented counts. Model quality on actual
personal-photo libraries is not yet verified and remains a v0.3 validation task.


Deliver useful day-to-day ways to sort and organize media and review obvious clutter. Favor understandable, review-first workflows and user control over ambitious automatic recommendations.

**New priority:** [Accidental Screenshot Review and Property Tours](SMART_CATEGORIES.md). Offer conservative lock-screen/blank/repeated-capture screenshot suggestions with Keep/Not accidental. Suggest property-photo sessions only after at least five consecutive related photos plus time/location and visual evidence; let the user verify each tour, assign/edit address, and categorize listing/move-in/move-out. Never silently reverse-geocode private photo coordinates or auto-delete. The existing Scenes & objects category must explicitly distinguish not-analyzed results from confirmed zero matches.

## 0.4 — Advanced bulk cleanup and intelligent recommendations

Improve visual similarity accuracy, false-positive handling, content-aware suggestions and bulk review. Any suggested deletion must remain subject to user review.

## 0.5 — Verified backup, archive and restore

Plan reliable, verifiable backup/archive to local disks, NAS or other user-controlled storage, with restoration procedures and checks before deletion or offloading.

## 0.6 — Advanced organization and searchable collections

Add more flexible organization, custom collections and ways to retrieve previously organized media.

## 0.7 — Messages and WhatsApp media

Explore macOS-available Messages and WhatsApp media with local privacy/security and access feasibility assessed before implementing any integration. Do not assume unrestricted access to either application's data.

## 0.8 — OCR search and automation

Add text-aware local search and carefully controlled automation on top of the established scan and organization foundations.

## 1.0 — Stable personal release

A dependable, safe personal macOS release with well-tested cleanup and recovery behavior. A public/business launch and iOS support are not implied.

---

**Safety:** Scanning must never delete photos automatically. User-reviewed deletion occurs through Apple Photos and can sync to iCloud Photos and other devices. App-owned scan results and history stay local unless the user explicitly exports them.

**Roadmap status:** This document states the intended sequence, not a claim that each planned capability has shipped. Shipping progress and implementation notes belong in the README, commit history and releases.
