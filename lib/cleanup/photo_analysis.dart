import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A compact visual summary. Nothing is sent to a server.
class PhotoFingerprint {
  const PhotoFingerprint({
    required this.rows,
    required this.averageRgb,
    required this.sharpness,
    this.spatialLuma = const [],
  });

  /// Eight bytes represent a 9 x 8 difference hash (64 bits).
  final List<int> rows;
  final List<int> averageRgb;
  final double sharpness;

  /// 24 × 24 low-resolution layout for conservative screenshot matching.
  final List<int> spatialLuma;
}

/// Runs in a background isolate through Flutter's compute().
PhotoFingerprint? fingerprintThumbnail(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null || decoded.width < 2 || decoded.height < 2) return null;

  final small = img.copyResize(decoded, width: 9, height: 8);
  final rows = <int>[];
  for (var y = 0; y < 8; y++) {
    var value = 0;
    for (var x = 0; x < 8; x++) {
      if (_luma(small.getPixel(x, y)) > _luma(small.getPixel(x + 1, y))) {
        value |= 1 << x;
      }
    }
    rows.add(value);
  }

  final sample = img.copyResize(decoded, width: 48, height: 48);
  var r = 0.0;
  var g = 0.0;
  var b = 0.0;
  final gray = List<double>.filled(48 * 48, 0);
  for (var y = 0; y < 48; y++) {
    for (var x = 0; x < 48; x++) {
      final p = sample.getPixel(x, y);
      r += p.r.toDouble();
      g += p.g.toDouble();
      b += p.b.toDouble();
      gray[y * 48 + x] = _luma(p);
    }
  }
  // Keep content position, not just average brightness. Otherwise unrelated
  // mostly-white screenshots can share the same tiny perceptual hash.
  final layout = img.copyResize(decoded, width: 24, height: 24);
  final spatialLuma = <int>[
    for (var y = 0; y < 24; y++)
      for (var x = 0; x < 24; x++)
        _luma(layout.getPixel(x, y)).round().clamp(0, 255).toInt(),
  ];
  final edges = <double>[];
  for (var y = 1; y < 47; y++) {
    for (var x = 1; x < 47; x++) {
      final i = y * 48 + x;
      edges.add(4 * gray[i] - gray[i - 1] - gray[i + 1] -
          gray[i - 48] - gray[i + 48]);
    }
  }
  final mean = edges.reduce((a, b) => a + b) / edges.length;
  final variance = edges.fold<double>(0, (sum, edge) =>
      sum + math.pow(edge - mean, 2).toDouble()) / edges.length;
  const total = 48 * 48;
  return PhotoFingerprint(
    rows: rows,
    averageRgb: [(r / total).round(), (g / total).round(), (b / total).round()],
    sharpness: variance,
    spatialLuma: spatialLuma,
  );
}

/// Analyze a bounded thumbnail batch in one isolate rather than spawning an
/// isolate for each individual Photos asset. A null thumbnail is an
/// unavailable asset, not a blank or blurry photo.
List<PhotoFingerprint?> fingerprintThumbnailBatch(List<Uint8List?> bytes) =>
    [for (final item in bytes) _safeFingerprint(item)];

PhotoFingerprint? _safeFingerprint(Uint8List? bytes) {
  if (bytes == null) { return null; }
  try {
    return fingerprintThumbnail(bytes);
  } catch (_) {
    // A corrupt thumbnail cannot abort the rest of the fast scan batch.
    return null;
  }
}

double _luma(img.Pixel p) =>
    0.2126 * p.r.toDouble() + 0.7152 * p.g.toDouble() + 0.0722 * p.b.toDouble();

int hammingDistance(PhotoFingerprint a, PhotoFingerprint b) {
  var distance = 0;
  for (var i = 0; i < 8; i++) {
    var bits = a.rows[i] ^ b.rows[i];
    while (bits != 0) {
      bits &= bits - 1;
      distance++;
    }
  }
  return distance;
}

bool visuallySimilar(PhotoFingerprint a, PhotoFingerprint b, {
  int maxDistance = 7,
  int maxColorDifference = 32,
  bool requireScreenshotLayout = false,
}) {
  if (hammingDistance(a, b) > maxDistance) return false;
  for (var i = 0; i < 3; i++) {
    if ((a.averageRgb[i] - b.averageRgb[i]).abs() > maxColorDifference) {
      return false;
    }
  }
  if (requireScreenshotLayout && !matchingScreenshotLayout(a, b)) {
    return false;
  }
  return true;
}

/// Screenshots with large blank regions must agree on actual content layout.
/// This is intentionally conservative: a missed suggestion is preferable to
/// grouping two different receipts, messages, documents or app screens.
bool matchingScreenshotLayout(PhotoFingerprint a, PhotoFingerprint b) {
  if (a.spatialLuma.length != 24 * 24 ||
      b.spatialLuma.length != 24 * 24) {
    return false;
  }
  var difference = 0;
  var changed = 0;
  var contrasting = 0;
  for (var i = 0; i < a.spatialLuma.length; i++) {
    final first = a.spatialLuma[i];
    final second = b.spatialLuma[i];
    final delta = (first - second).abs();
    difference += delta;
    if (delta > 20) {
      changed++;
    }
    if ((first > 230 && second < 200) ||
        (second > 230 && first < 200)) {
      contrasting++;
    }
  }
  for (var channel = 0; channel < 3; channel++) {
    if ((a.averageRgb[channel] - b.averageRgb[channel]).abs() > 14) {
      return false;
    }
  }
  return difference / a.spatialLuma.length <= 3.5 &&
      changed <= 18 && contrasting <= 8;
}

/// The score depends on thumbnail resolution and content; suggest review only.
bool potentiallyBlurry(PhotoFingerprint f, {double threshold = 65}) =>
    f.sharpness < threshold;

class ScannedPhoto {
  const ScannedPhoto({
    required this.id,
    required this.fingerprint,
    this.sha256,
    this.hasPeople,
    this.isScreenshot = false,
    this.createdAtMs = 0,
    this.latitude,
    this.longitude,
    this.accidentalReason,
  });
  final String id;
  final PhotoFingerprint fingerprint;
  final String? sha256;
  final bool? hasPeople;
  final bool isScreenshot;
  final int createdAtMs;
  final double? latitude, longitude;
  final String? accidentalReason;
}

/// Local PhotoKit references and a session hint, not moved photo files.
class PropertyTourSuggestion {
  const PropertyTourSuggestion({
    required this.ids, required this.startedAtMs, this.latitude, this.longitude,
  });
  final List<String> ids;
  final int startedAtMs;
  final double? latitude, longitude;
}

/// Quickly proposes *complete* time/location sessions for visual inspection.
/// Five photos is the minimum qualification, never a maximum photo count.
/// No inferred category is accepted until on-device image inspection passes.
List<PropertyTourSuggestion> propertySessionCandidates(
    List<ScannedPhoto> photos, {int minPhotos = 5}) {
  final sorted = photos.where((p) => p.createdAtMs > 0)
      .toList()..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
  final sessions = <PropertyTourSuggestion>[];
  final current = <ScannedPhoto>[];
  double? anchorLat, anchorLon;
  void finish() {
    if (current.length >= minPhotos) {
      sessions.add(PropertyTourSuggestion(
        ids: current.map((p) => p.id).toList(),
        startedAtMs: current.first.createdAtMs,
        latitude: anchorLat, longitude: anchorLon,
      ));
    }
    current.clear();
    anchorLat = null;
    anchorLon = null;
  }
  for (final item in sorted) {
    if (item.isScreenshot) {
      finish();
      continue;
    }
    if (current.isNotEmpty) {
      final gap = item.createdAtMs - current.last.createdAtMs;
      final displaced = item.latitude != null && item.longitude != null &&
          anchorLat != null && anchorLon != null &&
          _geoMeters(item.latitude!, item.longitude!, anchorLat!, anchorLon!) > 200;
      if (gap > const Duration(minutes: 30).inMilliseconds ||
          gap < 0 || displaced) {
        finish();
      }
    }
    current.add(item);
    anchorLat ??= item.latitude;
    anchorLon ??= item.longitude;
  }
  finish();
  return sessions;
}

/// Per-photo on-device residential scene result. Unknown/unavailable
/// images are excluded, and photos with detected people always break a tour.
enum PropertySceneKind { property, neutralInterior, people, notProperty, unknown }

/// Returns uninterrupted, visually validated *full* tour runs. Non-property
/// event frames and every people-containing image split candidate sessions.
/// Neutral indoor views (e.g. a doorway) are retained only when supported by
/// enough clearly residential rooms in the same uninterrupted sequence.
List<PropertyTourSuggestion> confirmedPropertyTourRuns(
    PropertyTourSuggestion candidate, Map<String, PropertySceneKind> evidence,
    {int minimumPhotos = 5}) {
  final result = <PropertyTourSuggestion>[];
  final run = <String>[];
  var residential = 0;
  void finish() {
    if (run.length >= minimumPhotos &&
        residential >= 3 &&
        residential * 5 >= run.length * 3) {
      result.add(PropertyTourSuggestion(ids: List<String>.of(run),
          startedAtMs: candidate.startedAtMs,
          latitude: candidate.latitude, longitude: candidate.longitude));
    }
    run.clear();
    residential = 0;
  }
  for (final id in candidate.ids) {
    final kind = evidence[id] ?? PropertySceneKind.unknown;
    if (kind == PropertySceneKind.people ||
        kind == PropertySceneKind.notProperty ||
        kind == PropertySceneKind.unknown) {
      finish();
      continue;
    }
    run.add(id);
    if (kind == PropertySceneKind.property) residential++;
  }
  finish();
  return result;
}

/// Explains why an accidental screenshot is suggested. Only known reasons
/// generate concrete subcategories, so old scan snapshots still work.
enum ScreenshotSuggestionKind {
  alarms,
  lockScreens,
  messages,
  emails,
  blankScreens,
  repeatedScreens,
  other,
}

ScreenshotSuggestionKind screenshotKindForReason(String? reason) {
  final text = (reason ?? '').toLowerCase();
  if (text.contains('alarm')) return ScreenshotSuggestionKind.alarms;
  if (text.contains('lock-screen') || text.contains('lock screen')) {
    return ScreenshotSuggestionKind.lockScreens;
  }
  if (text.contains('message') || text.contains('chat')) {
    return ScreenshotSuggestionKind.messages;
  }
  if (text.contains('email') || text.contains('mail capture')) {
    return ScreenshotSuggestionKind.emails;
  }
  if (text.contains('blank') || text.contains('empty')) {
    return ScreenshotSuggestionKind.blankScreens;
  }
  if (text.contains('repeat') || text.contains('identical')) {
    return ScreenshotSuggestionKind.repeatedScreens;
  }
  return ScreenshotSuggestionKind.other;
}

extension ScreenshotSuggestionLabels on ScreenshotSuggestionKind {
  String get label => switch (this) {
    ScreenshotSuggestionKind.alarms => 'Alarms',
    ScreenshotSuggestionKind.lockScreens => 'Lock screens',
    ScreenshotSuggestionKind.messages => 'Messages',
    ScreenshotSuggestionKind.emails => 'Emails',
    ScreenshotSuggestionKind.blankScreens => 'Blank captures',
    ScreenshotSuggestionKind.repeatedScreens => 'Repeated captures',
    ScreenshotSuggestionKind.other => 'Other suggestions',
  };
}

double _geoMeters(double lat1, double lon1, double lat2, double lon2) {
  const rad = math.pi / 180;
  final deltaLat = (lat2 - lat1) * rad;
  final deltaLon = (lon2 - lon1) * rad;
  final v = math.pow(math.sin(deltaLat / 2), 2).toDouble() +
      math.cos(lat1 * rad) * math.cos(lat2 * rad) *
      math.pow(math.sin(deltaLon / 2), 2).toDouble();
  return 12742000 * math.asin(math.min(1, math.sqrt(v)));
}

/// A deliberately narrow low-information screenshot detector. Dark photos
/// are excluded by isScreenshot; documents retain visible text/edge contrast.
String? blankScreenshotReason(PhotoFingerprint f) {
  if (f.spatialLuma.length != 576) return null;
  final values = f.spatialLuma;
  final average = values.reduce((a, b) => a + b) / values.length;
  final dark = values.where((v) => v < 35).length;
  final light = values.where((v) => v > 248).length;
  if (dark >= 566 && average < 25) return 'Almost blank dark screenshot';
  if (light >= 570 && average > 251) return 'Almost blank light screenshot';
  return null;
}

class CleanupGroups {
  const CleanupGroups({
    required this.exact,
    required this.similar,
    required this.blurry,
    required this.noPeople,
    this.accidentalScreenshots = const [],
    this.accidentalReasons = const {},
    this.propertyTours = const [],
  });
  final List<List<String>> exact;
  final List<List<String>> similar;
  final List<String> blurry;
  final List<String> noPeople;
  final List<String> accidentalScreenshots;
  final Map<String, String> accidentalReasons;
  final List<PropertyTourSuggestion> propertyTours;
  CleanupGroups withPropertyTours(List<PropertyTourSuggestion> tours) =>
      CleanupGroups(exact: exact, similar: similar, blurry: blurry,
        noPeople: noPeople, accidentalScreenshots: accidentalScreenshots,
        accidentalReasons: accidentalReasons, propertyTours: tours);
}

CleanupGroups classifyPhotos(List<ScannedPhoto> photos) {
  final byHash = <String, List<String>>{};
  for (final item in photos) {
    if (item.sha256 != null) {
      byHash.putIfAbsent(item.sha256!, () => []).add(item.id);
    }
  }
  final exact = byHash.values.where((g) => g.length > 1).toList();

  // With a maximum distance of 7 bits across 8 rows, similar hashes must
  // share at least one identical row (pigeonhole principle). Index those rows
  // to avoid O(n^2) comparisons across large Photos libraries.
  final clusters = <List<ScannedPhoto>>[];
  final candidates = <int, List<int>>{};
  // An image with common/blank row hashes may share buckets with tens of
  // thousands of unrelated screenshots. An unbounded candidate union can
  // turn restoring 26k saved photos into an enormous CPU-heavy operation.
  // Prefer a bounded number of nearby and early representatives. Missing a
  // remote lookalike is safer than freezing a background cleanup scan.
  const recentCandidatesPerRow = 16;
  const earliestCandidatesPerRow = 4;
  for (final item in photos) {
    final possible = <int>{};
    for (var row = 0; row < 8; row++) {
      final bucket = candidates[row * 256 + item.fingerprint.rows[row]];
      if (bucket == null) { continue; }
      for (var i = bucket.length - 1;
          i >= 0 && i >= bucket.length - recentCandidatesPerRow;
          i--) {
        possible.add(bucket[i]);
      }
      final earliest = math.min(earliestCandidatesPerRow, bucket.length);
      for (var i = 0; i < earliest; i++) {
        possible.add(bucket[i]);
      }
    }
    var assigned = false;
    // Compare representatives in stable order so exact duplicates do not
    // arbitrarily replace the group's original keeper after a rescan.
    final orderedCandidates = possible.toList()..sort();
    for (final clusterIndex in orderedCandidates) {
      final group = clusters[clusterIndex];
      final representative = group.first;
      // Do not use a blank-looking screenshot to anchor an unrelated group.
      if (item.isScreenshot != representative.isScreenshot) continue;
      if (item.sha256 != null && item.sha256 == representative.sha256) {
        continue; // Exact duplicates have their own section.
      }
      if (visuallySimilar(item.fingerprint, representative.fingerprint,
          requireScreenshotLayout: item.isScreenshot)) {
        group.add(item);
        assigned = true;
        break;
      }
    }
    if (!assigned) {
      final index = clusters.length;
      clusters.add([item]);
      for (var row = 0; row < 8; row++) {
        candidates.putIfAbsent(row * 256 + item.fingerprint.rows[row], () => [])
            .add(index);
      }
    }
  }
  final similar = clusters.where((g) => g.length > 1)
      .map((g) => g.map((p) => p.id).toList()).toList();
  final screenshotReasons = <String, String>{};
  final screenshots = photos.where((p) => p.isScreenshot).toList()
    ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
  for (var i = 0; i < screenshots.length; i++) {
    final shot = screenshots[i];
    final reason = shot.accidentalReason ?? blankScreenshotReason(shot.fingerprint);
    if (reason != null) { screenshotReasons[shot.id] = reason; continue; }
    if (shot.createdAtMs <= 0) continue;
    // Compare only a few very recent captures, not an unbounded global bucket.
    for (var j = i - 1; j >= 0 && j >= i - 4; j--) {
      final earlier = screenshots[j];
      if (shot.createdAtMs - earlier.createdAtMs > 90000) break;
      if (matchingScreenshotLayout(shot.fingerprint, earlier.fingerprint)) {
        screenshotReasons[shot.id] = 'Repeated screenshot within 90 seconds';
        break;
      }
    }
  }
  return CleanupGroups(
    exact: exact,
    similar: similar,
    blurry: photos.where((p) => potentiallyBlurry(p.fingerprint))
        .map((p) => p.id).toList(),
    noPeople: photos.where((p) => p.hasPeople == false)
        .map((p) => p.id).toList(),
    accidentalScreenshots: screenshotReasons.keys.toList(),
    accidentalReasons: screenshotReasons,
  );
}
