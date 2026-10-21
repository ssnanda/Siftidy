import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/cleanup/cleanup_controller.dart';
import 'package:siftidy/cleanup/cleanup_scanner.dart';
import 'package:siftidy/cleanup/photo_analysis.dart';

void main() {
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
