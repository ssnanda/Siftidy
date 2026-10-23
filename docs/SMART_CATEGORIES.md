# Siftidy smart categories — user-requested design (October 23, 2026)

The current version 0.2 must prioritize stable scanning and safe resumption. Two
new review categories below are **specified for implementation in v0.3**; do
not present them as detected/shipped until their classifier, UI, persistence,
and tests exist. Existing scans remain usable.

## Scenes & objects (fixed in v0.2)

- Rename the former "No people detected" category to **Scenes & objects**.
- A count of **0** is valid only when the scan actually attempted on-device
  human/face analysis. Otherwise display **— / Not analyzed**. The former
  result count could be misleading because people detection was off by default.
- Native Apple Vision human and face rectangles are indicative, not definitive:
  missed/hidden/minuscule people remain possible. This is always an optional,
  review-only grouping, not evidence of absence and never a deletion rule.
- Enabling analysis must clearly require a new scan, and older snapshots
  without analysis metadata must show unknown rather than a false zero.

## Possible accidental screenshots (v0.3)

Present as a *review category* with suggestions, never auto-delete.
Focus on the Photos **Screenshots** smart album, not normal camera images.

Candidate signals should include:
1. **Lock-screen captures:** locally detect clock/status area and relevant
   lock-screen text/layout with Apple Vision OCR and image layout. Clock/time
   alone is not proof, so label as suggested and offer "Not accidental".
2. **Empty or near-empty captures:** conservative dark/blank/one-color
   screenshot detection. Do not classify blank white documents, receipts or
   useful app screens as accidental just because they have little color.
3. **Repeated captures:** multiple near-identical screenshots taken within a
   short time. Reuse conservative screenshot-layout comparisons and avoid
   cross-matching different text/receipt contents.
4. **Mis-taps:** short screenshot bursts with no meaningful visual change,
   including accidentally captured volume/notification/control-center screens.

Show subtype/reason, screenshot thumbnail, taken timestamp and count; support
Keep, Not accidental, and selected review/deletion through Apple Photos.
Persist user's decisions. Review-first; no auto-delete or automatic move.

## Property tours (v0.3 Smart Organization)

Add an optional **Property tours** collection, distinct from deletion cleanup.
It must not presume the user is a property manager; it should work for normal
residential photography and be extensible to other photo-series collections.

Suggestion pipeline:
1. Collect **creation date/time and optional GPS metadata** via PhotoKit's
   `AssetEntity.createDateTime` and `latLng`; do not export originals.
2. Candidate sessions contain **at least 5 consecutive/near-consecutive**
   image captures, initially allowing gaps no longer than 20 minutes and
   geotagged coordinates within an initial ~200-metre radius. Exclude
   screenshots, videos, unrelated jumps and bursts at different locations.
3. Require independent visual evidence that a meaningful portion of the group
   contains **home exteriors, rooms, kitchens, bathrooms, hallways, or
   comparable real-estate/interior content**, using on-device Apple Vision
   classification on a bounded sample. Merely sharing a time and GPS pin
   must not create a confirmed "property" category.
4. If GPS is absent, image/time evidence may propose a **Needs location**
   session; let the user enter or assign an address. Do not fabricate GPS.
5. Use a stable grouping identity from photo IDs + session start. Repeated
   visits to the same address remain distinct **sessions**, with optional
   manually merged property collections.
6. Display **Property tour · [address/location or unassigned] · [date]**,
   a compact thumbnail collage and photo count. A human can rename,
   change address, split/merge sessions, label "Listing", "Move-in" or
   "Move-out", or reject a suggestion. Never infer a specific inspection
   type solely from capture order.
7. GPS alone gives coordinates, **not a postal address**. Reverse geocoding
   may contact a provider. It must be user-enabled, documented, and never
   silently transmit private photo coordinates. Cache accepted addresses
   locally; otherwise display an approximate coordinates/location label.
8. Do **not** create property-specific folders automatically or move/delete
   originals. Keep photo references in the user's local catalog, with manual
   organization later, and allow a photo to belong to multiple collections.

### Operational safeguards and acceptance tests

- Scan a test set of camera photos and screenshots on macOS, both fresh and
  restored from checkpoints, without recomputing unrelated fingerprints.
- Accidental screenshot positives must be inspectable with a stated reason;
  include intentional lock-screen screenshots and screenshots of documents as
  expected negatives.
- Verify at least five property-looking consecutive photos at same place
  produce a candidate; non-property family/event batches should not.
- Verify 4-photo series are excluded, sessions separated by date remain
  distinct, mismatched locations split correctly, and no GPS produces an
  explicitly unassigned location rather than a guessed address.
- Allow user correction and preserve reviewed/dismissed decisions after
  relaunch. Do not require network or enable geocoding automatically.
- Treat unavailable black thumbnails as a loading/rendering problem rather
  than visual content, and never offer deletion based on an unavailable preview.
- All scanning and classification stays on device by default.
