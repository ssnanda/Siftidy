import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/cleanup/photo_analysis.dart';
import 'package:siftidy/cleanup/scan_checkpoint.dart';

void main() {
  late Directory folder;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('siftidy-checkpoint-');
  });
  tearDown(() async {
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  test('restart preserves visited assets, fingerprints, and CPU metrics',
      () async {
    final first = await ScanCheckpointStore.open(folder: folder);
    await first.begin(year: null, people: false, total: 49303);
    final fingerprint = PhotoFingerprint(
      rows: List<int>.filled(8, 1), averageRgb: [22, 33, 44],
      sharpness: 30, spatialLuma: List<int>.filled(576, 88));
    await first.append([
      ScanRow('a', 2026, 1200, 800,
        photo: ScannedPhoto(id: 'a', fingerprint: fingerprint)),
      const ScanRow('b', 2026, 1200, 800, skipped: true),
    ], mode: 'turbo', elapsedMs: 5000, cpu: 50, ram: 280);
    final restarted = await ScanCheckpointStore.open(folder: folder);
    final restored = await restarted.load();
    expect(restored, isNotNull);
    expect(restored!.visited, 2);
    expect(restored.analyzed, 1);
    expect(restored.skipped, 1);
    expect(restored.rows['a']!.photo!.fingerprint.spatialLuma.length, 576);
    expect(restored.modes['turbo'], 5000);
    expect(restored.peakRam, 280);
    final continued = await restarted.begin(
      year: null, people: false, total: 49303);
    expect(identical(restored, continued), isTrue);
    await restarted.append([
      const ScanRow('c', 2025, 1600, 1000),
    ], mode: 'eco', elapsedMs: 2000, cpu: 2, ram: 140);
    expect((await restarted.load())!.visited, 3);
    final usage = await restarted.usage();
    expect(usage.activeBytes, greaterThan(0));
    expect(usage.folder, folder.path);
  });

  test('completed scan has history; discard only removes active cache',
      () async {
    final store = await ScanCheckpointStore.open(folder: folder);
    await store.begin(year: 2025, people: true, total: 2);
    await store.append([const ScanRow('asset', 2025, 100, 100)],
      mode: 'balanced', elapsedMs: 1500, cpu: 9, ram: 190);
    await store.finish('complete');
    final info = await store.usage();
    expect(info.history.length, 1);
    expect(info.history.first['status'], 'complete');
    expect(info.history.first['modes'], {'balanced': 1500});
    await store.discard();
    final after = await store.usage();
    expect(after.activeBytes, 0);
    expect(after.history.length, 1);
    expect((await store.load()), isNull);
  });

  test('photo library count changes reuse cached work and prune removed IDs',
      () async {
    final store = await ScanCheckpointStore.open(folder: folder);
    final before = await store.begin(year: null, people: false, total: 3);
    await store.append([
      const ScanRow('survivor', 2025, 100, 100),
      const ScanRow('deleted', 2025, 100, 100),
    ], mode: 'eco', elapsedMs: 120, cpu: 3, ram: 90);
    final resumed = await store.begin(
      year: null, people: false, total: 4);
    expect(identical(before, resumed), isTrue);
    expect(resumed.visited, 2);
    expect(resumed.total, 4);
    await store.reconcile({'survivor', 'new-photo'}, 4);
    expect(store.current!.rows.keys, {'survivor'});
    final restarted = await ScanCheckpointStore.open(folder: folder);
    expect((await restarted.load())!.rows.keys, {'survivor'});
  });

  test('discard waits for pending checkpoint writes', () async {
    final store = await ScanCheckpointStore.open(folder: folder);
    await store.begin(year: null, people: false, total: 100);
    final write = store.append([
      for (var i = 0; i < 100; i++)
        ScanRow('asset-$i', 2026, 100, 100),
    ], mode: 'turbo', elapsedMs: 500, cpu: 30, ram: 120);
    final discard = store.discard();
    await Future.wait([write, discard]);
    expect((await store.usage()).activeBytes, 0);
    expect((await (await ScanCheckpointStore.open(folder: folder))
      .load()), isNull);
  });

  test('truncated final journal entry does not erase earlier checkpoints',
      () async {
    final store = await ScanCheckpointStore.open(folder: folder);
    await store.begin(year: null, people: false, total: 10);
    await store.append([const ScanRow('safe', 2026, 100, 100)],
      mode: 'eco', elapsedMs: 100, cpu: 1, ram: 40);
    await File('${folder.path}/active-rows.jsonl')
      .writeAsString('{"id":', mode: FileMode.append, flush: true);
    final other = await ScanCheckpointStore.open(folder: folder);
    expect((await other.load())!.rows.keys, contains('safe'));
  });
}
