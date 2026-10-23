# Siftidy roadmap — revised October 23, 2026

Siftidy is a **macOS-only**, privacy-first personal media cleanup app. The priority is to make scanning dependable before expanding intelligent cleanup. No iPhone/iOS app builds are planned under the current direction.

| Version | Focus | Priority |
| --- | --- | --- |
| **0.1** | Media browsing, selection, deletion, updates | Existing foundation |
| **0.2** | Scan stability, scheduling, performance and history | **Current** |
| **0.3** | Smart Organization + practical cleanup | **Next** |
| **0.4** | Advanced bulk cleanup and intelligent recommendations | Later |
| **0.5** | Verified backup, archive and restore | Later |
| **0.6** | Advanced organization and searchable collections | Later |
| **0.7** | Messages and WhatsApp media | Later |
| **0.8** | OCR search and automation | Later |
| **1.0** | Stable personal release | Target |

## 0.2 — Scan foundation (current)

**Finish reliability before adding new detection features.**

- Keep scans running in the macOS menu bar when the window is closed or hidden with ⌘Q; make **Quit Completely** explicit.
- Recover scan progress, analyzed items and results from on-device checkpoints after a full quit, restart, or app update, including when the Photos library changes.
- Keep scan percentages and Running/Paused/Stopped/Completed status consistent between the window and menu bar.
- Preserve Minimal/Eco/Balanced/Turbo behavior, active speed and the remaining timed Turbo session across relaunch. Support idle/AC-aware scanning and user-controlled scheduling.
- Monitor process CPU/RAM, progress, processing rate, time remaining, elapsed duration, and scan history.
- Provide an inspectable local scan-data folder, actual cache size and safe **Discard scan results** behavior without modifying photos.
- Handle failed/interrupted scans, stale or corrupt checkpoints, partial writes and performance limits without silent resets.

**0.2 completion criterion:** A long Photos scan can be interrupted, resumed, accelerated, inspected and safely discarded with predictable results, and its state is clear across the main window and menu bar.

Existing exact-duplicate, similar-photo, blurry-photo and people-detection *review tools* are retained; substantial new intelligence in these tools is not the primary focus of 0.2.

## 0.3 — Smart Organization + practical cleanup (next)

Deliver useful day-to-day ways to sort and organize media and review obvious clutter. Favor understandable, review-first workflows and user control over ambitious automatic recommendations.

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
