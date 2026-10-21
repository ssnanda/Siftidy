import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../library/library_repository.dart';
import 'photo_analysis.dart';

/// Snapshot of a progressive local scan. All suggestions need review.
class CleanupScanResult {
  const CleanupScanResult({
    required this.photos,
    required this.groups,
    required this.total,
    required this.visited,
    required this.skipped,
    required this.peopleDetectionAvailable,
    required this.years,
  });

  final Map<String, AssetEntity> photos;
  final CleanupGroups groups;
  final int total;
  final int visited;
  final int skipped;
  final bool peopleDetectionAvailable;
  final Set<int> years;
}

/// Mac PhotoKit is accessed serially; only near-identical thumbnail candidates
/// require original-file hashing. Normal browsing stays responsive.
class CleanupScanner {
  static const _vision = MethodChannel('siftidy/vision');
  static const _pageSize = 64;
  static const _publishEvery = 64;

  Future<CleanupScanResult> scan({
    required bool Function() cancelled,
    required Future<void> Function() waitIfPaused,
    required void Function(CleanupScanResult snapshot) onProgress,
    Set<String> protectedIds = const {},
    int? year,
    bool analyzePeople = false,
  }) async {
    final all = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.image,
    );
    final album = all.isEmpty ? null : all.first;
    final total = album == null ? 0 : await album.assetCountAsync;
    final scanned = <ScannedPhoto>[];
    final assets = <String, AssetEntity>{};
    final years = <int>{};
    final visitedIds = <String>{};
    final duplicateCandidates = <String, AssetEntity>{};
    final scannedPosition = <String, int>{};
    final knownHashes = <String, String?>{};
    var skipped = 0;
    var visited = 0;
    var peopleAvailable = analyzePeople;

    CleanupScanResult snapshot(CleanupGroups groups) => CleanupScanResult(
      photos: Map<String, AssetEntity>.of(assets),
      groups: groups,
      total: total,
      visited: visited,
      skipped: skipped,
      peopleDetectionAvailable: peopleAvailable,
      years: Set<int>.of(years),
    );

    Future<void> publish() async {
      final groups = await compute(classifyPhotos, List<ScannedPhoto>.of(scanned));
      if (!cancelled()) onProgress(snapshot(groups));
    }

    Future<String?> hashFile(AssetEntity asset) async {
      if (knownHashes.containsKey(asset.id)) return knownHashes[asset.id];
      String? value;
      try {
        final original = await asset.originFile;
        if (original != null) {
          value = (await sha256.bind(original.openRead()).first).toString();
        }
      } catch (_) {
        // iCloud originals may not be locally accessible. Unknown != exact.
      }
      knownHashes[asset.id] = value;
      return value;
    }

    Future<void> index(AssetPathEntity path) async {
      for (var page = 0; !cancelled(); page++) {
        await waitIfPaused();
        if (cancelled()) break;
        final batch = await path.getAssetListPaged(page: page, size: _pageSize);
        if (batch.isEmpty) break;
        for (final asset in batch) {
          await waitIfPaused();
          if (cancelled()) break;
          if (!visitedIds.add(asset.id)) continue;
          visited++;
          final assetYear = asset.createDateTime.year;
          years.add(assetYear);
          if (protectedIds.contains(asset.id) ||
              (year != null && assetYear != year)) {
            continue;
          }
          try {
            final bytes = await asset.thumbnailDataWithSize(
              const ThumbnailSize(192, 192),
              format: ThumbnailFormat.jpeg,
              quality: 80,
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
            bool? hasPeople;
            if (analyzePeople && peopleAvailable) {
              try {
                hasPeople = await _vision.invokeMethod<bool>(
                  'hasPeople', bytes,
                );
              } on MissingPluginException {
                peopleAvailable = false;
              } on PlatformException {
                // Failed recognition means unknown, never 'no people'.
              }
            }

            // Hash original files only when thumbnails look *identical* and
            // original dimensions also match, not for every library photo.
            // This can save tens of thousands of large iCloud downloads.
            final signature = '${asset.width}x${asset.height}:'
                '${fingerprint.rows.join(",")}:${fingerprint.averageRgb.join(",")}';
            final peer = duplicateCandidates.putIfAbsent(
              signature, () => asset);
            String? digest;
            if (peer.id != asset.id) {
              digest = await hashFile(asset);
              final peerDigest = await hashFile(peer);
              final prior = scannedPosition[peer.id];
              if (prior != null && scanned[prior].sha256 != peerDigest) {
                final previous = scanned[prior];
                scanned[prior] = ScannedPhoto(
                  id: previous.id,
                  fingerprint: previous.fingerprint,
                  sha256: peerDigest,
                  hasPeople: previous.hasPeople,
                );
              }
            }
            scannedPosition[asset.id] = scanned.length;
            scanned.add(ScannedPhoto(
              id: asset.id,
              fingerprint: fingerprint,
              sha256: digest,
              hasPeople: hasPeople,
            ));
            assets[asset.id] = asset;
          } catch (_) {
            skipped++;
          }
          if (visited % _publishEvery == 0) await publish();
        }
        if (batch.length < _pageSize) break;
        await publish();
      }
    }

    if (album != null) {
      // Screenshots are scanned first so the first sidebar results arrive fast.
      final collections = await PhotoManager.getAssetPathList(
        hasAll: true, type: RequestType.image,
      );
      final screenshots = LibraryRepository.smartAlbum(
        collections,
        PMDarwinAssetCollectionSubtype.smartAlbumScreenshots,
      );
      if (screenshots != null && screenshots.id != album.id) {
        await index(screenshots);
      }
      if (!cancelled()) {
      await index(album);
    }
    }
    final groups = await compute(classifyPhotos, List<ScannedPhoto>.of(scanned));
    return snapshot(groups);
  }
}