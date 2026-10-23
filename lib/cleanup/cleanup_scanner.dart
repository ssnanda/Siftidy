import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../background/scan_runtime.dart';
import '../library/library_repository.dart';
import 'photo_analysis.dart';
import 'scan_checkpoint.dart';

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

class _ThumbnailAnalysis {
  const _ThumbnailAnalysis(this.fingerprint, this.people);
  final PhotoFingerprint? fingerprint;
  final bool? people;
}

/// PhotoKit data stays on the main isolate. Thumbnail decoding and Vision
/// requests can overlap in bounded batches; output bookkeeping remains serial.
/// The runtime paces each batch while Eco/Minimal is active.
class CleanupScanner {
  static const _vision = MethodChannel('siftidy/vision');
  static const _pageSize = 64;

  Future<CleanupScanResult> scan({
    required bool Function() cancelled,
    required Future<void> Function() waitIfPaused,
    required void Function(CleanupScanResult snapshot) onProgress,
    required ScanRuntime performance,
    required ScanCheckpointStore checkpointStore,
    Set<String> protectedIds = const {},
    int? year,
    bool analyzePeople = false,
  }) async {
    final all = await PhotoManager.getAssetPathList(
      onlyAll: true, type: RequestType.image,
    );
    final album = all.isEmpty ? null : all.first;
    final total = album == null ? 0 : await album.assetCountAsync;
    final checkpoint = await checkpointStore.begin(
      year: year, people: analyzePeople, total: total);
    final restored = Map<String, ScanRow>.of(checkpoint.rows);
    final pending = <ScanRow>[];
    var lastSavedAt = DateTime.now();
    final scanned = <ScannedPhoto>[];
    final assets = <String, AssetEntity>{};
    final years = <int>{};
    final visitedIds = <String>{};
    final candidates = <String, AssetEntity>{};
    final positions = <String, int>{};
    final hashes = <String, String?>{};
    var skipped = checkpoint.skipped;
    var visited = restored.length;
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
      if (cancelled()) return;
      final now = DateTime.now();
      final elapsed = now.difference(lastSavedAt).inMilliseconds;
      lastSavedAt = now;
      await checkpointStore.append(List<ScanRow>.of(pending),
        mode: performance.activeMode.name,
        elapsedMs: elapsed,
        cpu: performance.processCpu, ram: performance.ramMb);
      pending.clear();
      if (cancelled()) return;
      final groups = await compute(classifyPhotos, List<ScannedPhoto>.of(scanned));
      if (!cancelled()) onProgress(snapshot(groups));
    }

    Future<String?> hashFile(AssetEntity asset) async {
      if (hashes.containsKey(asset.id)) return hashes[asset.id];
      String? hash;
      try {
        final file = await asset.originFile;
        if (file != null) {
          // Crypto's chunked conversion reads the ENTIRE file, not the first
          // chunk, before comparing exact duplicates.
          hash = (await sha256.bind(file.openRead()).first).toString();
        }
      } catch (_) {
        // Unavailable originals are not treated as verified duplicates.
      }
      hashes[asset.id] = hash;
      return hash;
    }

    Future<_ThumbnailAnalysis> analyze(AssetEntity asset) async {
      await performance.pace(cancelled: cancelled);
      if (cancelled()) return const _ThumbnailAnalysis(null, null);
      final bytes = await asset.thumbnailDataWithSize(
        const ThumbnailSize(192, 192),
        format: ThumbnailFormat.jpeg,
        quality: 80,
      );
      if (bytes == null) return const _ThumbnailAnalysis(null, null);
      final fingerprint = await compute(fingerprintThumbnail, bytes);
      if (fingerprint == null) return const _ThumbnailAnalysis(null, null);
      bool? people;
      if (analyzePeople && peopleAvailable) {
        try {
          people = await _vision.invokeMethod<bool>('hasPeople', bytes);
        } on MissingPluginException {
          peopleAvailable = false;
        } on PlatformException {
          // Unknown result is not proof that no person is in the photo.
        }
      }
      return _ThumbnailAnalysis(fingerprint, people);
    }

    Future<void> index(AssetPathEntity path, {bool isScreenshot = false}) async {
      for (var page = 0; !cancelled(); page++) {
        await waitIfPaused();
        if (cancelled()) break;
        final batch = await path.getAssetListPaged(page: page, size: _pageSize);
        if (batch.isEmpty) break;
        var cursor = 0;
        while (cursor < batch.length && !cancelled()) {
          await waitIfPaused();
          if (cancelled()) break;
          // Active mode is read for each batch, so a menu-bar Turbo switch
          // changes real work concurrency without restarting the scan.
          final limit = performance.activeMode.concurrency;
          final slice = batch.skip(cursor).take(limit).toList();
          cursor += slice.length;
          final toAnalyze = <AssetEntity>[];
          for (final asset in slice) {
            if (!visitedIds.add(asset.id)) continue;
            final cached = restored[asset.id];
            if (cached != null) {
              years.add(cached.year);
              if (cached.photo != null &&
                  !protectedIds.contains(asset.id) &&
                  (year == null || cached.year == year)) {
                positions[asset.id] = scanned.length;
                scanned.add(cached.photo!);
                assets[asset.id] = asset;
                final f = cached.photo!.fingerprint;
                final signature = '${asset.width}x${asset.height}:'
                    '${f.rows.join(",")}:${f.averageRgb.join(",")}:'
                    '${cached.photo!.isScreenshot ? sha1.convert(f.spatialLuma) : ""}';
                candidates.putIfAbsent(signature, () => asset);
              }
              continue;
            }
            visited++;
            final y = asset.createDateTime.year;
            years.add(y);
            if (protectedIds.contains(asset.id) ||
                (year != null && y != year)) {
              pending.add(ScanRow(asset.id, y, asset.width, asset.height));
              continue;
            }
            toAnalyze.add(asset);
          }
          final results = await Future.wait(toAnalyze.map((asset) async {
            try {
              return await analyze(asset);
            } catch (_) {
              return const _ThumbnailAnalysis(null, null);
            }
          }));
          if (cancelled()) break;
          for (var i = 0; i < results.length && !cancelled(); i++) {
            final asset = toAnalyze[i];
            final fingerprint = results[i].fingerprint;
            if (fingerprint == null) {
              skipped++;
              pending.add(ScanRow(asset.id, asset.createDateTime.year,
                  asset.width, asset.height, skipped: true));
              continue;
            }
            final signature = '${asset.width}x${asset.height}:'
                '${fingerprint.rows.join(",")}:'
                '${fingerprint.averageRgb.join(",")}:'
                '${isScreenshot ? sha1.convert(fingerprint.spatialLuma) : ""}';
            final peer = candidates.putIfAbsent(signature, () => asset);
            String? digest;
            if (peer.id != asset.id) {
              digest = await hashFile(asset);
              final originalDigest = await hashFile(peer);
              final index = positions[peer.id];
              if (index != null && scanned[index].sha256 != originalDigest) {
                final previous = scanned[index];
                scanned[index] = ScannedPhoto(
                  id: previous.id,
                  fingerprint: previous.fingerprint,
                  sha256: originalDigest,
                  hasPeople: previous.hasPeople,
                  isScreenshot: previous.isScreenshot,
                );
                final previousAsset = assets[peer.id];
                if (previousAsset != null) {
                  pending.add(ScanRow(peer.id,
                    previousAsset.createDateTime.year,
                    previousAsset.width, previousAsset.height,
                    photo: scanned[index]));
                }
              }
            }
            positions[asset.id] = scanned.length;
            final analyzedPhoto = ScannedPhoto(
              id: asset.id,
              fingerprint: fingerprint,
              sha256: digest,
              hasPeople: results[i].people,
              isScreenshot: isScreenshot,
            );
            scanned.add(analyzedPhoto);
            assets[asset.id] = asset;
            pending.add(ScanRow(asset.id, asset.createDateTime.year,
              asset.width, asset.height, photo: analyzedPhoto));
          }
        }
        await publish();
        if (batch.length < _pageSize) break;
      }
    }

    if (album != null) {
      final collections = await PhotoManager.getAssetPathList(
        hasAll: true, type: RequestType.image,
      );
      final screenshots = LibraryRepository.smartAlbum(
        collections,
        PMDarwinAssetCollectionSubtype.smartAlbumScreenshots,
      );
      if (screenshots != null && screenshots.id != album.id) {
        await index(screenshots, isScreenshot: true);
      }
      if (!cancelled()) await index(album);
    }
    if (!cancelled()) {
      await publish();
      if (!cancelled()) {
        await checkpointStore.reconcile(visitedIds, total);
        visited = checkpointStore.current?.visited ?? visited;
        skipped = checkpointStore.current?.skipped ?? skipped;
      }
    }
    final groups = await compute(classifyPhotos, List<ScannedPhoto>.of(scanned));
    return snapshot(groups);
  }
}
