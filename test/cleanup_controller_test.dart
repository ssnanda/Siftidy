import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/cleanup/cleanup_controller.dart';
import 'package:siftidy/cleanup/cleanup_scanner.dart';
import 'package:siftidy/cleanup/photo_analysis.dart';
import 'package:siftidy/cleanup/scan_checkpoint.dart';
import 'package:siftidy/cleanup/scan_result_archive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup displays persisted scan progress before any rescan', () async {
    SharedPreferences.setMockInitialValues({'cleanup_auto_scan_v02': false});
    final directory = await Directory.systemTemp.createTemp('siftidy-restore-');
    try {
      final store = await ScanCheckpointStore.open(folder: directory);
      await store.begin(year: null, people: false, total: 100);
      await store.append([
        const ScanRow('cached-1', 2026, 800, 600),
        const ScanRow('cached-2', 2026, 800, 600),
      ], mode: 'eco', elapsedMs: 1200, cpu: 5, ram: 110);
      final restarted = await ScanCheckpointStore.open(folder: directory);
      final controller = CleanupController()..checkpointStore = restarted;
      await controller.initialize();
      expect(controller.visited, 2);
      expect(controller.total, 100);
      expect(controller.fraction, closeTo(0.02, 0.00001));
      expect(controller.resumeStatus, contains('Restored 2'));
      expect(controller.running, isFalse);
      controller.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('completed sessions restore their result counts without autoscanning',
      () async {
    SharedPreferences.setMockInitialValues({'cleanup_auto_scan_v02': true});
    final directory = await Directory.systemTemp.createTemp('siftidy-complete-');
    try {
      final store = await ScanCheckpointStore.open(folder: directory);
      final session = await store.begin(
        year: null, people: false, total: 4);
      await store.append([
        for (var i = 0; i < 4; i++)
          ScanRow('photo-$i', 2026, 800, 600),
      ], mode: 'eco', elapsedMs: 4000, cpu: 3, ram: 120);
      await ScanResultArchive(directory).save(
        started: session.started, total: 4, analyzed: 4,
        groups: const CleanupGroups(
          exact: [['photo-0', 'photo-1']],
          similar: [], blurry: ['photo-2'], noPeople: [],
        ));
      await store.finish('complete');

      final restored = await ScanCheckpointStore.open(folder: directory);
      final controller = CleanupController()..checkpointStore = restored;
      await controller.initialize();
      expect(controller.completed, isTrue);
      expect(controller.visited, 4);
      expect(controller.exactCount, 1);
      expect(controller.blurry, ['photo-2']);
      await controller.startIfEnabled(const {});
      expect(controller.running, isFalse);
      expect(controller.starting, isFalse);
      expect(controller.scanRevision, 0);
      expect(controller.exactCount, 1);
      controller.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('paused refresh restores its last completed result snapshot', () async {
    SharedPreferences.setMockInitialValues({'cleanup_auto_scan_v02': false});
    final directory = await Directory.systemTemp.createTemp('siftidy-paused-');
    try {
      final store = await ScanCheckpointStore.open(folder: directory);
      final session = await store.begin(
        year: null, people: false, total: 2);
      await store.append([
        const ScanRow('photo-1', 2026, 800, 600),
        const ScanRow('photo-2', 2026, 800, 600),
      ], mode: 'turbo', elapsedMs: 1000, cpu: 3, ram: 120);
      await ScanResultArchive(directory).save(
        started: session.started, total: 2, analyzed: 2,
        groups: const CleanupGroups(
          exact: [['photo-1', 'photo-2']],
          similar: [], blurry: [], noPeople: [],
        ));
      await store.finish('complete');
      await store.begin(year: null, people: false, total: 3);
      await store.finish('paused');

      final restored = await ScanCheckpointStore.open(folder: directory);
      final controller = CleanupController()..checkpointStore = restored;
      await controller.initialize();

      expect(controller.completed, isFalse);
      expect(controller.exactCount, 1);
      controller.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('corrupt metadata is preserved and cannot silently reset a scan',
      () async {
    SharedPreferences.setMockInitialValues({'cleanup_auto_scan_v02': true});
    final directory = await Directory.systemTemp.createTemp('siftidy-corrupt-');
    try {
      final store = await ScanCheckpointStore.open(folder: directory);
      await store.begin(year: null, people: false, total: 50);
      await store.append([
        const ScanRow('important', 2026, 800, 600),
      ], mode: 'eco', elapsedMs: 50, cpu: 3, ram: 90);
      await File('${directory.path}/active-state.json')
          .writeAsString('corrupted metadata');
      final restarted = await ScanCheckpointStore.open(folder: directory);
      final controller = CleanupController()..checkpointStore = restarted;
      await controller.initialize();
      expect(controller.error, contains('preserved'));
      expect(restarted.recoveryIssue, isNotNull);
      await expectLater(
        restarted.begin(year: null, people: false, total: 50),
        throwsStateError,
      );
      expect(await File('${directory.path}/active-rows.jsonl').exists(),
          isTrue);
      controller.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('Pause blocks work and Resume immediately releases the worker',
      () async {
    final controller = CleanupController()..running = true;
    controller.pauseOrResume();
    expect(controller.paused, isTrue);
    final waiting = controller.waitWhilePaused();
    var released = false;
    waiting.then((_) => released = true);
    await Future<void>.delayed(Duration.zero);
    expect(released, isFalse);
    controller.pauseOrResume();
    await waiting.timeout(const Duration(seconds: 1));
    expect(released, isTrue);
    expect(controller.paused, isFalse);
    expect(controller.scanPhase, 'Resuming scan');
    controller.dispose();
  });

  test('Stop releases a paused worker for checkpoint flush', () async {
    final controller = CleanupController()..running = true;
    controller.pauseOrResume();
    final waiting = controller.waitWhilePaused();
    controller.stop();
    await waiting.timeout(const Duration(seconds: 1));
    expect(controller.paused, isFalse);
    controller.dispose();
  });

  CleanupScanResult fixture() => const CleanupScanResult(
    photos: {},
    groups: CleanupGroups(
      exact: [['exact-a', 'exact-b']],
      similar: [['family-1', 'family-2', 'family-3']],
      blurry: ['possibly-blurry'],
      noPeople: ['no-people'],
    ),
    total: 6,
    visited: 6,
    skipped: 0,
    peopleDetectionAvailable: true,
    years: {2026},
  );

  test('incremental progress retains the completed suggestions', () {
    final completed = fixture();
    const progress = CleanupScanResult(
      photos: {},
      groups: CleanupGroups(
        exact: [], similar: [], blurry: [], noPeople: [],
      ),
      total: 8,
      visited: 7,
      skipped: 1,
      peopleDetectionAvailable: false,
      smartAnalyzed: false,
      years: {2026},
      restoring: true,
      restoredIndexed: 6,
      restoredTotal: 6,
    );

    final visible = mergeScanProgress(progress, completed);

    expect(visible.groups, same(completed.groups));
    expect(visible.total, 8);
    expect(visible.visited, 7);
    expect(visible.restoring, isTrue);
    expect(visible.peopleDetectionAvailable, isTrue);
  });

  test('finalization progress stays below complete and advances', () {
    final controller = CleanupController()
      ..result = fixture()
      ..running = true;
    expect(controller.fraction, closeTo(.95, .00001));

    controller
      ..finalizationCurrent = 5
      ..finalizationTotal = 10;
    expect(controller.fraction, closeTo(.975, .00001));
    expect(controller.fraction, lessThan(1));
    controller.dispose();
  });

  test('Keep all suppresses only the selected suggestion', () {
    final controller = CleanupController();
    controller.result = fixture();
    expect(controller.similar, hasLength(1));
    controller.dismissGroup(
      ['family-1', 'family-2', 'family-3'], similar: true,
    );
    expect(controller.similar, isEmpty);
    expect(controller.exact, hasLength(1));
    expect(controller.blurry, ['possibly-blurry']);
    controller.dispose();
  });

  test('Discard scan clears all intelligent results without editing assets', () {
    final controller = CleanupController();
    controller.result = fixture();
    controller.running = true;
    final initialRevision = controller.scanRevision;
    controller.discardScan();
    expect(controller.scanRevision, initialRevision + 1);
    expect(controller.result, isNull);
    expect(controller.running, isFalse);
    expect(controller.completed, isFalse);
    expect(controller.exact, isEmpty);
    expect(controller.similar, isEmpty);
    expect(controller.blurry, isEmpty);
    expect(controller.noPeople, isEmpty);
    controller.dispose();
  });
}
