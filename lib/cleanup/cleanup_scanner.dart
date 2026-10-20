import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import 'photo_analysis.dart';

class CleanupScanResult {
  const CleanupScanResult({
    required this.photos,
    required this.groups,
    required this.total,
    required this.skipped,
    required this.peopleDetectionAvailable,
  });
  final Map<String, AssetEntity> photos;
  final CleanupGroups groups;
  final int total;
  final int skipped;
  final bool peopleDetectionAvailable;
}

/// User-initiated scan. Reads thumbnails and original files locally, serially,
/// so a large iCloud-backed library does not trigger hundreds of downloads.
class CleanupScanner {
  static const _vision = MethodChannel('siftidy/vision');

  Future<CleanupScanResult> scan({
    required bool Function() cancelled,
    required void Function(int done, int total) progress,
    Set<String> protectedIds = const {},
  }) async {
    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true, type: RequestType.image,
    );
    if (paths.isEmpty) {
      final empty = classifyPhotos([]);
      return CleanupScanResult(photos: {}, groups: empty, total: 0,
        skipped: 0, peopleDetectionAvailable: true);
    }
    final album = paths.first;
    final total = await album.assetCountAsync;
    final scanned = <ScannedPhoto>[];
    final indexed = <String, AssetEntity>{};
    var skipped = 0;
    var scannedCount = 0;
    var peopleAvailable = true;

    for (var page = 0; scannedCount < total && !cancelled(); page++) {
      final batch = await album.getAssetListPaged(page: page, size: 50);
      if (batch.isEmpty) break;
      for (final asset in batch) {
        if (cancelled()) break;
        scannedCount++;
        if (protectedIds.contains(asset.id)) {
          progress(scannedCount, total);
          continue;
        }
        try {
          final bytes = await asset.thumbnailDataWithSize(
            const ThumbnailSize(192, 192),
            format: ThumbnailFormat.jpeg,
            quality: 85,
          );
          if (bytes == null) {
            skipped++;
            continue;
          }
          final fingerprint = await compute(fingerprintThumbnail, bytes);
          if (fingerprint == null) {
            skipped++;
            continue;
          }
          bool? people;
          if (peopleAvailable) {
            try {
              people = await _vision.invokeMethod<bool>(
                'hasPeople', Uint8List.fromList(bytes));
            } on MissingPluginException {
              peopleAvailable = false;
            } on PlatformException {
              // A failed Vision request is unknown, not 'no people'.
            }
          }
          String? digest;
          try {
            final original = await asset.originFile;
            if (original != null) {
              digest = (await sha256.bind(original.openRead()).first).toString();
            }
          } catch (_) {
            // iCloud or PhotoKit may not expose an original. Never guess exact.
          }
          scanned.add(ScannedPhoto(id: asset.id, fingerprint: fingerprint,
            sha256: digest, hasPeople: people));
          indexed[asset.id] = asset;
        } catch (_) {
          skipped++;
        } finally {
          progress(scannedCount, total);
        }
      }
      if (batch.length < 50) break;
    }
    return CleanupScanResult(photos: indexed,
      groups: await compute(classifyPhotos, scanned), total: total,
      skipped: skipped, peopleDetectionAvailable: peopleAvailable);
  }
}
