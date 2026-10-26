import 'dart:async';
import 'dart:convert';

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
    this.smartAnalyzed = false,
    this.restoring = false,
    this.restoredIndexed = 0,
    this.restoredTotal = 0,
  });

  final Map<String, AssetEntity> photos;
  final CleanupGroups groups;
  final int total;
  final int visited;
  final int skipped;
  final bool peopleDetectionAvailable;
  final bool smartAnalyzed;
  final Set<int> years;
  /// Rebuilding in-memory asset references from the saved analysis journal.
  /// Previously analyzed assets must never be re-decoded in this phase.
  final bool restoring;
  final int restoredIndexed;
  final int restoredTotal;
}

class _ThumbnailAnalysis {
  const _ThumbnailAnalysis(this.fingerprint, this.people, this.accidentalReason);
  final PhotoFingerprint? fingerprint;
  final bool? people;
  final String? accidentalReason;
}

/// PhotoKit data stays on the main isolate. Thumbnail decoding and Vision
/// requests can overlap in bounded batches; output bookkeeping remains serial.
/// The runtime paces each batch while Eco/Minimal is active.
class CleanupScanner {
  static const _vision = MethodChannel('siftidy/vision');
  // Use fewer PhotoKit round trips while rebuilding many cached IDs.
  static const _pageSize = 256;
  // Classifying all cached photos every page can stall a resumed scan.
  static const _classifyAfterNewPhotos = 4096;

  Future<CleanupScanResult> scan({
    required bool Function() cancelled,
    required Future<void> Function() waitIfPaused,
    required void Function(CleanupScanResult snapshot) onProgress,
    required void Function(String phase) onPhase,
    required ScanRuntime performance,
    required ScanCheckpointStore checkpointStore,
    Set<String> protectedIds = const {},
    int? year,
    bool analyzePeople = false,
    bool forceFresh = false,
  }) async {
    final all = await PhotoManager.getAssetPathList(
      onlyAll: true, type: RequestType.image,
    );
    final album = all.isEmpty ? null : all.first;
    final total = album == null ? 0 : await album.assetCountAsync;
    final checkpoint = await checkpointStore.begin(
      year: year, people: analyzePeople, total: total,
      forceFresh: forceFresh);
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
    // Availability means Vision returned a real result, not merely that
    // the toggle was enabled. A failed/absent bridge must not yield a zero.
    var smartAnalyzed = false;
    var peopleAvailable = false;
    var visionUsable = analyzePeople;
    String lastPhase = '';
    void reportPhase(String phase) {
      if (phase != lastPhase && !cancelled()) {
        lastPhase = phase;
        onPhase(phase);
      }
    }
    reportPhase(restored.isEmpty ? 'Preparing Photos scan'
        : 'Restoring saved photo references');
    var restoredIndexed = 0;
    var freshAnalyzedSinceClassification = 0;
    var hasReachedUncachedPhoto = restored.isEmpty;
    var groups = const CleanupGroups(
      exact: [], similar: [], blurry: [], noPeople: [],
    );

    CleanupScanResult snapshot(CleanupGroups latestGroups) => CleanupScanResult(
      photos: Map<String, AssetEntity>.of(assets),
      groups: latestGroups,
      restoring: !hasReachedUncachedPhoto && restoredIndexed < restored.length,
      restoredIndexed: restoredIndexed,
      restoredTotal: restored.length,
      total: total,
      visited: visited,
      skipped: skipped,
      peopleDetectionAvailable: peopleAvailable,
      smartAnalyzed: smartAnalyzed,
      years: Set<int>.of(years),
    );

    Future<void> publish({
      bool finalPass = false,
      bool checkpointOnly = false,
    }) async {
      // A quit/cancel must still commit the current page's completed work.
      if (cancelled() && !checkpointOnly) { return; }
      final now = DateTime.now();
      final elapsed = now.difference(lastSavedAt).inMilliseconds;
      lastSavedAt = now;
      if (pending.isNotEmpty || elapsed >= 1000) {
        await checkpointStore.append(List<ScanRow>.of(pending),
          mode: performance.activeMode.name,
          elapsedMs: elapsed,
          cpu: performance.processCpu, ram: performance.ramMb);
        pending.clear();
      }
      if (checkpointOnly || cancelled()) { return; }
      // Restoration can touch 25,000+ cached photos. Repeating classification
      // for each page makes that phase appear frozen for minutes.
      if (finalPass ||
          freshAnalyzedSinceClassification >= _classifyAfterNewPhotos) {
        reportPhase('Updating cleanup suggestions');
        groups = await compute(classifyPhotos, List<ScannedPhoto>.of(scanned))
            .timeout(Duration(seconds: finalPass ? 120 : 30),
                onTimeout: () => throw TimeoutException(
                    'Cleanup grouping exceeded its time limit.'));
        freshAnalyzedSinceClassification = 0;
      }
      if (finalPass && !cancelled()) {
        reportPhase('Finding property tours');
        final candidateTours = propertySessionCandidates(scanned);
        final signature = sha1.convert(utf8.encode(candidateTours.map((tour) =>
          '${tour.startedAtMs}:${tour.ids.join(",")}').join('|'))).toString();
        final savedScan = checkpointStore.current;
        final canResumeTours = savedScan?.propertyTourSignature == signature;
        var propertyTourCursor = canResumeTours
            ? savedScan!.propertyTourCursor
                .clamp(0, candidateTours.length).toInt()
            : 0;
        final confirmedTours = canResumeTours
            ? List<PropertyTourSuggestion>.of(
                savedScan!.confirmedPropertyTours)
            : <PropertyTourSuggestion>[];
        if (!canResumeTours) {
          await checkpointStore.savePropertyTourProgress(
            signature: signature, cursor: 0, total: candidateTours.length,
            confirmed: const []);
        }
        // First cheaply sample each session to avoid full-library Vision
        // passes over birthdays, vacations, and other unrelated sequences.
        // Promising tours then get checked *frame by frame*: nobody may
        // appear in an included photo, and time/location alone never qualify.
        final checked = <String, PropertySceneKind>{};
        Future<PropertySceneKind> inspect(String id) async {
          final cached = checked[id];
          if (cached != null) { return cached; }
          if (cancelled()) { return PropertySceneKind.unknown; }
          await waitIfPaused();
          final asset = assets[id];
          if (asset == null) { return PropertySceneKind.unknown; }
          try {
            final bytes = await asset.thumbnailDataWithSize(
              const ThumbnailSize(288, 288),
              format: ThumbnailFormat.jpeg, quality: 78,
            ).timeout(const Duration(seconds: 12));
            if (bytes == null) { return PropertySceneKind.unknown; }
            final code = await _vision.invokeMethod<int>(
              'propertyScene', bytes).timeout(const Duration(seconds: 12));
            final kind = switch (code) {
              1 => PropertySceneKind.property,
              2 => PropertySceneKind.people,
              3 => PropertySceneKind.neutralInterior,
              0 => PropertySceneKind.notProperty,
              _ => PropertySceneKind.unknown,
            };
            checked[id] = kind;
            return kind;
          } catch (_) {
            checked[id] = PropertySceneKind.unknown;
            return PropertySceneKind.unknown;
          }
        }

        const parallelPhotos = 6;
        for (var sessionIndex = propertyTourCursor;
            sessionIndex < candidateTours.length && !cancelled();
            sessionIndex++) {
          await waitIfPaused();
          final tour = candidateTours[sessionIndex];
          reportPhase('Checking property tours: ${sessionIndex + 1} / '
              '${candidateTours.length} candidate sessions');
          final ids = tour.ids;
          final samplePositions = <int>{
            0, ids.length ~/ 4, ids.length ~/ 2,
            ids.length * 3 ~/ 4, ids.length - 1,
          };
          final sample = await Future.wait(samplePositions.map(
              (index) => inspect(ids[index])));
          final strong = sample.where(
              (kind) => kind == PropertySceneKind.property).length;
          final possible = sample.where((kind) =>
              kind == PropertySceneKind.property ||
              kind == PropertySceneKind.neutralInterior).length;
          if (strong < 2 || possible < 3) {
            propertyTourCursor = sessionIndex + 1;
            if (propertyTourCursor % 10 == 0) {
              await checkpointStore.savePropertyTourProgress(
                signature: signature, cursor: propertyTourCursor,
                total: candidateTours.length,
                confirmed: confirmedTours);
            }
            continue;
          }

          // No artificial maximum tour length or 90-minute total cap.
          // A candidate may contain hundreds of frames if it really is
          // one uninterrupted visit. Every included frame is inspected.
          for (var offset = 0; offset < ids.length && !cancelled();
              offset += parallelPhotos) {
            await waitIfPaused();
            final batch = ids.skip(offset).take(parallelPhotos).toList();
            await Future.wait(batch.map(inspect));
          }
          if (cancelled()) { break; }
          confirmedTours.addAll(confirmedPropertyTourRuns(tour, checked));
          propertyTourCursor = sessionIndex + 1;
          if (propertyTourCursor % 10 == 0) {
            await checkpointStore.savePropertyTourProgress(
              signature: signature, cursor: propertyTourCursor,
              total: candidateTours.length,
              confirmed: confirmedTours);
          }
        }
        await checkpointStore.savePropertyTourProgress(
          signature: signature, cursor: propertyTourCursor,
          total: candidateTours.length,
          confirmed: confirmedTours);
        if (!cancelled()) {
          groups = groups.withPropertyTours(confirmedTours);
          smartAnalyzed = true;
        }
      }
      if (!cancelled()) { onProgress(snapshot(groups)); }
    }

    Future<String?> hashFile(AssetEntity asset) async {
      if (hashes.containsKey(asset.id)) { return hashes[asset.id]; }
      String? hash;
      try {
        reportPhase('Verifying exact duplicates');
        await waitIfPaused();
        if (cancelled()) { return null; }
        final file = await asset.originFile
            .timeout(const Duration(seconds: 12));
        if (file != null) {
          // Crypto's chunked conversion reads the ENTIRE file, not the first
          // chunk, before comparing exact duplicates.
          hash = (await sha256.bind(file.openRead()).first
              .timeout(const Duration(seconds: 12))).toString();
        }
      } catch (_) {
        // Unavailable originals are not treated as verified duplicates.
      }
      hashes[asset.id] = hash;
      return hash;
    }

    /// Fetch a small bounded group of PhotoKit thumbnails, then compute all
    /// fingerprints in a single isolate. Previously one compute() isolate and
    /// an additional 640px PhotoKit read/OCR ran for *every* screenshot.
    Future<List<_ThumbnailAnalysis>> analyzeBatch(
        List<AssetEntity> photos, {required bool screenshot}) async {
      if (photos.isEmpty) { return const []; }
      reportPhase(screenshot ? 'Analyzing screenshot thumbnails'
          : 'Analyzing photo thumbnails');
      final thumbnails = await Future.wait(photos.map((asset) async {
        await waitIfPaused();
        await performance.pace(cancelled: cancelled);
        if (cancelled()) { return null; }
        try {
          return await asset.thumbnailDataWithSize(
            screenshot ? const ThumbnailSize(384, 384)
                : const ThumbnailSize(192, 192),
            format: ThumbnailFormat.jpeg, quality: 78,
          ).timeout(const Duration(seconds: 20));
        } catch (_) {
          return null;
        }
      }));
      if (cancelled()) {
        return [for (final _ in photos)
          const _ThumbnailAnalysis(null, null, null)];
      }
      final fingerprints = await compute(fingerprintThumbnailBatch, thumbnails)
          .timeout(const Duration(seconds: 30));
      return Future.wait(List.generate(photos.length, (index) async {
        final finger = fingerprints[index];
        if (finger == null || cancelled()) {
          return const _ThumbnailAnalysis(null, null, null);
        }
        final asset = photos[index];
        final bytes = thumbnails[index];
        bool? people;
        if (analyzePeople && visionUsable && bytes != null) {
          try {
            people = await _vision.invokeMethod<bool>('hasPeople', bytes)
                .timeout(const Duration(seconds: 12));
            if (people != null) { peopleAvailable = true; }
          } on MissingPluginException {
            visionUsable = false;
          } catch (_) {
            // A failed Vision request is unknown, never "no people".
          }
        }
        String? accidentalReason;
        if (screenshot) {
          accidentalReason = blankScreenshotReason(finger);
          // Lock screens are portrait phone screenshots. Skip unnecessary
          // OCR of desktop screenshots, documents and landscape captures.
          final mobilePortrait = asset.width > 0 &&
              asset.height >= asset.width * 1.6 &&
              asset.height <= asset.width * 2.8;
          if (accidentalReason == null && mobilePortrait && bytes != null) {
            reportPhase('Checking potential lock-screen screenshots');
            try {
              accidentalReason = await _vision.invokeMethod<String>(
                  'screenshotReason', bytes)
                  .timeout(const Duration(seconds: 8));
            } catch (_) {
              // Unknown is not an accidental screenshot.
            }
          }
        }
        return _ThumbnailAnalysis(finger, people, accidentalReason);
      }));
    }

    Future<void> index(AssetPathEntity path, {bool isScreenshot = false}) async {
      for (var page = 0; !cancelled(); page++) {
        await waitIfPaused();
        if (cancelled()) { break; }
        reportPhase('Reading Photos library');
        final batch = await path.getAssetListPaged(page: page, size: _pageSize)
            .timeout(const Duration(seconds: 30),
                onTimeout: () => throw TimeoutException(
                    'Photos library page $page did not respond within 30s'));
        if (batch.isEmpty) { break; }
        var cursor = 0;
        while (cursor < batch.length && !cancelled()) {
          await waitIfPaused();
          if (cancelled()) { break; }
          // Active mode is read for each batch, so a menu-bar Turbo switch
          // changes real work concurrency without restarting the scan.
          final limit = performance.activeMode.concurrency;
          final slice = batch.skip(cursor).take(limit).toList();
          cursor += slice.length;
          final toAnalyze = <AssetEntity>[];
          for (final asset in slice) {
            if (!visitedIds.add(asset.id)) { continue; }
            final cached = restored[asset.id];
            if (cached != null) {
              restoredIndexed++;
              if (restoredIndexed % 512 == 0) {
                reportPhase('Restoring saved photos: $restoredIndexed'
                    ' / ${restored.length}');
              }
              years.add(cached.year);
              if (cached.photo?.hasPeople != null) { peopleAvailable = true; }
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
            hasReachedUncachedPhoto = true;
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
          final results = await analyzeBatch(toAnalyze,
              screenshot: isScreenshot);
          if (cancelled()) { break; }
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
                  createdAtMs: previous.createdAtMs,
                  latitude: previous.latitude, longitude: previous.longitude,
                  accidentalReason: previous.accidentalReason,
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
              createdAtMs: asset.createDateTime.millisecondsSinceEpoch,
              latitude: asset.latLng?.latitude,
              longitude: asset.latLng?.longitude,
              accidentalReason: results[i].accidentalReason,
            );
            scanned.add(analyzedPhoto);
            freshAnalyzedSinceClassification++;
            assets[asset.id] = asset;
            pending.add(ScanRow(asset.id, asset.createDateTime.year,
              asset.width, asset.height, photo: analyzedPhoto));
          }
          // Journal and report independently of grouping. A slow Photos
          // request should not leave the user staring at 0/256 for minutes.
          if (cursor % 96 == 0 || cursor >= batch.length) {
            await publish(checkpointOnly: true);
            if (!cancelled()) { onProgress(snapshot(groups)); }
          }
        }
        await publish();
        if (batch.length < _pageSize) { break; }
      }
    }

    try {
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
        if (!cancelled()) { await index(album); }
      }
      if (!cancelled()) {
        await publish(finalPass: true);
        if (!cancelled()) {
          await checkpointStore.reconcile(visitedIds, total);
          visited = checkpointStore.current?.visited ?? visited;
          skipped = checkpointStore.current?.skipped ?? skipped;
        }
      }
      return snapshot(groups);
    } finally {
      // Graceful shutdown bypasses classification and safely flushes any
      // analyzed photos from an interrupted page before we acknowledge quit.
      if (pending.isNotEmpty) {
        await publish(checkpointOnly: true);
      }
      await checkpointStore.flush();
    }
  }
}
