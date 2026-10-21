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
  });
  final String id;
  final PhotoFingerprint fingerprint;
  final String? sha256;
  final bool? hasPeople;
  final bool isScreenshot;
}

class CleanupGroups {
  const CleanupGroups({
    required this.exact,
    required this.similar,
    required this.blurry,
    required this.noPeople,
  });
  final List<List<String>> exact;
  final List<List<String>> similar;
  final List<String> blurry;
  final List<String> noPeople;
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
  for (final item in photos) {
    final possible = <int>{};
    for (var row = 0; row < 8; row++) {
      possible.addAll(candidates[row * 256 + item.fingerprint.rows[row]] ?? const []);
    }
    var assigned = false;
    for (final clusterIndex in possible) {
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
  return CleanupGroups(
    exact: exact,
    similar: similar,
    blurry: photos.where((p) => potentiallyBlurry(p.fingerprint))
        .map((p) => p.id).toList(),
    noPeople: photos.where((p) => p.hasPeople == false)
        .map((p) => p.id).toList(),
  );
}
