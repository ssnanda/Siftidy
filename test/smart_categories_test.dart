import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/cleanup/photo_analysis.dart';

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
    ]), hasLength(1));
  });

  test('Missing GPS remains unassigned and never invents an address', () {
    final tours = propertySessionCandidates([
      for (var i = 0; i < 5; i++) photo('interior$i', i),
    ]);
    expect(tours, hasLength(1));
    expect(tours.single.latitude, isNull);
    expect(tours.single.longitude, isNull);
  });
}
