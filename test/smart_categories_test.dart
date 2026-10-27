import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/cleanup/photo_analysis.dart';
import 'package:siftidy/cleanup/property_tours_view.dart';

const ms = 1000;
PhotoFingerprint finger({int value = 95}) => PhotoFingerprint(
  rows: List<int>.filled(8, 0),
  averageRgb: [value, value, value],
  sharpness: 150,
  spatialLuma: List<int>.filled(576, value),
);
ScannedPhoto photo(String id, int minute, {double? latitude,
  double? longitude, bool screenshot = false,
  String? reason}) => ScannedPhoto(
    id: id, fingerprint: finger(),
    createdAtMs: DateTime(2026, 10, 23, 10)
        .add(Duration(minutes: minute)).millisecondsSinceEpoch,
    latitude: latitude, longitude: longitude,
    isScreenshot: screenshot, accidentalReason: reason,
  );

void main() {
  test('Screenshots: known lock screens are suggestions only', () {
    final output = classifyPhotos([
      photo('lock', 0, screenshot: true,
          reason: 'Possible lock-screen capture'),
      photo('camera', 1),
    ]);
    expect(output.accidentalScreenshots, contains('lock'));
    expect(output.accidentalScreenshots, isNot(contains('camera')));
    expect(output.accidentalReasons['lock'], contains('lock-screen'));
  });

  test('near-identical screenshots in a short burst flag extras', () {
    final same = PhotoFingerprint(
      rows: List<int>.filled(8, 5), averageRgb: [90, 90, 90],
      sharpness: 90, spatialLuma: List<int>.filled(576, 90));
    ScannedPhoto shot(String id, int seconds) => ScannedPhoto(
      id: id, fingerprint: same, isScreenshot: true,
      createdAtMs: 1700000000000 + seconds * ms,
    );
    final result = classifyPhotos([shot('original', 0), shot('extra', 30)]);
    expect(result.accidentalScreenshots, ['extra']);
    expect(result.accidentalReasons['extra'], contains('Repeated'));
  });

  test('blank-looking camera photos never become accidental screenshots', () {
    expect(classifyPhotos([
      ScannedPhoto(id: 'dark-photo', fingerprint: finger(value: 0)),
    ]).accidentalScreenshots, isEmpty);
  });

  test('Five related geotagged home pictures form one candidate', () {
    final batch = [
      for (var i = 0; i < 6; i++)
        photo('$i', i * 4,
          latitude: 35.3501 + i * 0.00001, longitude: -80.8301),
    ];
    final suggestions = propertySessionCandidates(batch);
    expect(suggestions, hasLength(1));
    expect(suggestions.single.ids, hasLength(6));
    expect(suggestions.single.latitude, closeTo(35.3501, 0.00001));
  });

  test('Location changes split property sessions', () {
    final batch = [
      for (var i = 0; i < 6; i++)
        photo('a$i', i, latitude: 35.35, longitude: -80.83),
      for (var i = 0; i < 6; i++)
        photo('b$i', i + 6, latitude: 35.40, longitude: -80.83),
    ];
    expect(propertySessionCandidates(batch), hasLength(2));
  });

  test('Four-photo bursts are excluded; screenshots break eligibility', () {
    expect(propertySessionCandidates([
      for (var i = 0; i < 4; i++) photo('$i', i),
    ]), isEmpty);
    expect(propertySessionCandidates([
      for (var i = 0; i < 3; i++) photo('a$i', i),
      photo('screenshot', 3, screenshot: true),
      for (var i = 0; i < 3; i++) photo('b$i', i + 4),
    ]), isEmpty);
  });

  test('A property tour keeps every photo even after 100 and 90 minutes', () {
    final photos = [
      for (var i = 0; i < 180; i++)
        photo('room-$i', i * 2, latitude: 35.3501, longitude: -80.8301),
    ];
    final candidates = propertySessionCandidates(photos);
    expect(candidates, hasLength(1));
    expect(candidates.single.ids, hasLength(180));
    expect(candidates.single.ids.first, 'room-0');
    expect(candidates.single.ids.last, 'room-179');
    final classified = confirmedPropertyTourRuns(candidates.single, {
      for (final item in candidates.single.ids)
        item: item.endsWith('0')
            ? PropertySceneKind.neutralInterior
            : PropertySceneKind.property,
    });
    expect(classified, hasLength(1));
    expect(classified.single.ids, hasLength(180));
  });

  test('Event pictures containing people never become property tours', () {
    final tour = PropertyTourSuggestion(
      startedAtMs: 1000,
      ids: ['event-1', 'event-2', 'event-3', 'event-4',
            'event-5', 'event-6'],
    );
    final result = confirmedPropertyTourRuns(tour, {
      for (final id in tour.ids) id: PropertySceneKind.people,
    });
    expect(result, isEmpty);
  });

  test('A person/event frame separates home visits without joining them',
      () {
    final ids = [
      for (var i = 0; i < 9; i++) 'house-$i',
      'person-at-event',
      for (var i = 9; i < 15; i++) 'house-$i',
    ];
    final candidate = PropertyTourSuggestion(
        ids: ids, startedAtMs: 1000);
    final results = confirmedPropertyTourRuns(candidate, {
      for (final id in ids)
        id: id == 'person-at-event'
            ? PropertySceneKind.people
            : PropertySceneKind.property,
    });
    expect(results, hasLength(2));
    expect(results.first.ids, hasLength(9));
    expect(results.last.ids, hasLength(6));
    expect(results.expand((tour) => tour.ids),
        isNot(contains('person-at-event')));
  });

  test('Neutral closet and hallway views stay in the complete home tour',
      () {
    const candidate = PropertyTourSuggestion(
      ids: ['closet', 'bedroom', 'hallway', 'bathroom',
            'second-bedroom', 'second-closet'],
      startedAtMs: 1000,
    );
    final found = confirmedPropertyTourRuns(candidate, {
      'closet': PropertySceneKind.property,
      'bedroom': PropertySceneKind.property,
      'hallway': PropertySceneKind.neutralInterior,
      'bathroom': PropertySceneKind.property,
      'second-bedroom': PropertySceneKind.property,
      'second-closet': PropertySceneKind.neutralInterior,
    });
    expect(found, hasLength(1));
    expect(found.single.ids, candidate.ids);
  });

  test('Non-property scenes split a tour, not just photos with people', () {
    const candidate = PropertyTourSuggestion(
      ids: ['room1', 'room2', 'room3', 'room4', 'room5',
            'party', 'room6', 'room7', 'room8', 'room9', 'room10'],
      startedAtMs: 1000,
    );
    final found = confirmedPropertyTourRuns(candidate, {
      for (final id in candidate.ids)
        id: id == 'party'
            ? PropertySceneKind.notProperty
            : PropertySceneKind.property,
    });
    expect(found.map((tour) => tour.ids.length), [5, 5]);
    expect(found.expand((tour) => tour.ids), isNot(contains('party')));
  });

  test('Unverified or predominantly generic indoor scenes do not qualify',
      () {
    const candidate = PropertyTourSuggestion(
      ids: ['a', 'b', 'c', 'd', 'e', 'f'],
      startedAtMs: 1000,
    );
    expect(confirmedPropertyTourRuns(candidate, {
      for (final id in candidate.ids)
        id: PropertySceneKind.neutralInterior,
    }), isEmpty);
    expect(confirmedPropertyTourRuns(candidate, {
      'a': PropertySceneKind.property,
      'b': PropertySceneKind.property,
      'c': PropertySceneKind.unknown,
      'd': PropertySceneKind.property,
      'e': PropertySceneKind.property,
      'f': PropertySceneKind.property,
    }), isEmpty);
  });

  test('Screenshot suggestions expose consistent review subcategories', () {
    expect(screenshotKindForReason('Possible alarm capture'),
        ScreenshotSuggestionKind.alarms);
    expect(screenshotKindForReason('Possible lock-screen capture'),
        ScreenshotSuggestionKind.lockScreens);
    expect(screenshotKindForReason('Possible message capture'),
        ScreenshotSuggestionKind.messages);
    expect(screenshotKindForReason('Possible email capture'),
        ScreenshotSuggestionKind.emails);
    expect(screenshotKindForReason('Almost blank dark screenshot'),
        ScreenshotSuggestionKind.blankScreens);
    expect(screenshotKindForReason('Repeated screenshot within 90 seconds'),
        ScreenshotSuggestionKind.repeatedScreens);
    expect(screenshotKindForReason('Unknown suggestion'),
        ScreenshotSuggestionKind.other);
  });

  test('Missing GPS remains unassigned and never invents an address', () {
    final tours = propertySessionCandidates([
      for (var i = 0; i < 5; i++) photo('interior$i', i),
    ]);
    expect(tours, hasLength(1));
    expect(tours.single.latitude, isNull);
    expect(tours.single.longitude, isNull);
  });

  test('dated visits to one address group under the same property', () {
    const older = PropertyTourSuggestion(
      ids: ['old-1', 'old-2', 'old-3', 'old-4', 'old-5'],
      startedAtMs: 1000, latitude: 35.1, longitude: -80.1);
    const newer = PropertyTourSuggestion(
      ids: ['new-1', 'new-2', 'new-3', 'new-4', 'new-5'],
      startedAtMs: 2000, latitude: 35.1, longitude: -80.1);

    final groups = groupPropertyTours(const [older, newer], const {
      'old-1': '6822 Trimbach Way',
      'new-1': '6822 Trimbach Way',
    });

    expect(groups, hasLength(1));
    expect(groups.single.title, '6822 Trimbach Way');
    expect(groups.single.tours, [newer, older]);
  });

  test('split runs from one visit count as one property tour', () {
    const fragments = [
      PropertyTourSuggestion(ids: ['a', 'b', 'c', 'd', 'e'],
        startedAtMs: 1000, latitude: 35.1, longitude: -80.1),
      PropertyTourSuggestion(ids: ['f', 'g', 'h', 'i', 'j'],
        startedAtMs: 1000, latitude: 35.1, longitude: -80.1),
      PropertyTourSuggestion(ids: ['k', 'l', 'm', 'n', 'o'],
        startedAtMs: 1000, latitude: 35.1, longitude: -80.1),
    ];
    final groups = groupPropertyTours(fragments, const {
      'a': '4116 Austin Rd',
      'f': '4116 Austin Rd',
      'k': '4116 Austin Rd',
    });

    expect(groups, hasLength(1));
    expect(groups.single.tours, hasLength(1));
    expect(groups.single.tours.single.ids, hasLength(15));
  });

  test('properties sort by their most recent visit', () {
    const older = PropertyTourSuggestion(
      ids: ['old-a', 'old-b', 'old-c', 'old-d', 'old-e'],
      startedAtMs: 1000);
    const newer = PropertyTourSuggestion(
      ids: ['new-a', 'new-b', 'new-c', 'new-d', 'new-e'],
      startedAtMs: 2000);

    final groups = groupPropertyTours(const [older, newer], const {
      'old-a': 'A Property',
      'new-a': 'Z Property',
    });

    expect(groups.map((group) => group.title), ['Z Property', 'A Property']);
  });
}
