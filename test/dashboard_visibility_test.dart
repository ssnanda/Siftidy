import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/cleanup/cleanup_controller.dart';
import 'package:siftidy/cleanup/cleanup_scanner.dart';
import 'package:siftidy/cleanup/cleanup_screen.dart';
import 'package:siftidy/cleanup/photo_analysis.dart';
import 'package:siftidy/cleanup/scan_result_archive.dart';
import 'package:siftidy/dashboard/scan_dashboard.dart';

CleanupScanResult scan({
  required CleanupGroups groups,
  bool peopleAnalyzed = false,
  bool smartAnalyzed = false,
}) => CleanupScanResult(
  photos: const {},
  groups: groups,
  total: 12,
  visited: 12,
  skipped: 0,
  peopleDetectionAvailable: peopleAnalyzed,
  smartAnalyzed: smartAnalyzed,
  years: const {2026},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only positive actionable tiles appear for an older saved scan', () {
    final controller = CleanupController();
    controller.result = scan(groups: const CleanupGroups(
      exact: [['a', 'b']],
      similar: [],
      blurry: ['out-of-focus'],
      noPeople: ['scene'],
      accidentalScreenshots: ['accidental'],
      propertyTours: [
        PropertyTourSuggestion(ids: ['home-1', 'home-2', 'home-3',
            'home-4', 'home-5'], startedAtMs: 1000),
      ],
    ));
    expect(
      visibleDashboardSuggestions(controller).map((entry) => entry.category),
      [CleanupCategory.exact, CleanupCategory.blurry],
    );
    controller.dispose();
  });

  test('all zero or unavailable categories produce no dashboard tiles', () {
    final controller = CleanupController();
    expect(visibleDashboardSuggestions(controller), isEmpty);
    controller.result = scan(
      peopleAnalyzed: true, smartAnalyzed: true,
      groups: const CleanupGroups(
        exact: [], similar: [], blurry: [], noPeople: [],
      ),
    );
    controller.analyzingPeople = true;
    expect(visibleDashboardSuggestions(controller), isEmpty);
    controller.dispose();
  });

  test('populated smart categories become visible after completed analysis', () {
    final controller = CleanupController();
    controller.analyzingPeople = true;
    controller.result = scan(
      peopleAnalyzed: true,
      smartAnalyzed: true,
      groups: const CleanupGroups(
        exact: [],
        similar: [],
        blurry: [],
        noPeople: ['scene-1'],
        accidentalScreenshots: ['capture-1'],
        propertyTours: [
          PropertyTourSuggestion(ids: ['photo-1', 'photo-2', 'photo-3',
            'photo-4', 'photo-5'], startedAtMs: 1000),
        ],
      ),
    );
    expect(
      visibleDashboardSuggestions(controller).map((entry) => entry.category),
      [CleanupCategory.noPeople, CleanupCategory.accidental,
        CleanupCategory.propertyTours],
    );
    expect(
      visibleDashboardSuggestions(controller).map((entry) => entry.count),
      [1, 1, 1],
    );
    controller.dispose();
  });

  test('recent scans omit zeros and missing smart results but retain positives',
      () {
    ScanResultSnapshot snapshot(CleanupGroups groups, {bool smart = false}) =>
      ScanResultSnapshot(
        id: 'scan-1',
        startedAt: DateTime(2026, 10, 23),
        savedAt: DateTime(2026, 10, 23),
        total: 12,
        analyzed: 12,
        groups: groups,
        bytes: 1200,
        smartAnalyzed: smart,
      );
    expect(positiveScanResultLabels(snapshot(const CleanupGroups(
      exact: [], similar: [], blurry: [], noPeople: [],
    ))), isEmpty);
    expect(positiveScanResultLabels(snapshot(const CleanupGroups(
      exact: [['one', 'two']],
      similar: [],
      blurry: ['blurry'],
      noPeople: [],
      accidentalScreenshots: ['shot-1'],
    ))), ['Exact 1', 'Blurry 1']);
    expect(positiveScanResultLabels(snapshot(const CleanupGroups(
      exact: [], similar: [], blurry: [], noPeople: [],
      accidentalScreenshots: ['shot-1'],
      propertyTours: [
        PropertyTourSuggestion(ids: ['1', '2', '3', '4', '5'],
          startedAtMs: 1000),
      ],
    ), smart: true)), ['Screenshots 1', 'Tours 1']);
  });
}
