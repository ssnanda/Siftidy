import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/cleanup/photo_analysis.dart';

PhotoFingerprint fingerprint(List<int> rows, {int r = 100, double sharpness = 100}) =>
    PhotoFingerprint(rows: rows, averageRgb: [r, r, r], sharpness: sharpness);

void main() {
  final zeros = List<int>.filled(8, 0);
  test('perceptual hash distance and color guard', () {
    final a = fingerprint(zeros);
    final b = fingerprint([1, ...zeros.skip(1)]);
    expect(hammingDistance(a, b), 1);
    expect(visuallySimilar(a, b), isTrue);
    expect(visuallySimilar(a, fingerprint(zeros, r: 220)), isFalse);
  });

  test('exact results require the same original SHA256', () {
    final photos = [
      ScannedPhoto(id: 'a', fingerprint: fingerprint(zeros), sha256: 'hash1'),
      ScannedPhoto(id: 'b', fingerprint: fingerprint(zeros), sha256: 'hash1'),
      ScannedPhoto(id: 'c', fingerprint: fingerprint(zeros), sha256: 'hash2'),
    ];
    final result = classifyPhotos(photos);
    expect(result.exact, [['a', 'b']]);
    expect(result.similar, [['a', 'c']]);
  });

  test('unrelated white screenshots are not similar', () {
    final white = List<int>.filled(24 * 24, 245);
    final differentContent = List<int>.of(white);
    for (var i = 100; i < 130; i++) {
      differentContent[i] = 30;
    }
    final first = PhotoFingerprint(rows: zeros, averageRgb: [245, 245, 245],
        sharpness: 100, spatialLuma: white);
    final second = PhotoFingerprint(rows: zeros, averageRgb: [245, 245, 245],
        sharpness: 100, spatialLuma: differentContent);
    expect(visuallySimilar(first, second), isTrue);
    expect(matchingScreenshotLayout(first, second), isFalse);
    final result = classifyPhotos([
      ScannedPhoto(id: 'screenshot-a', fingerprint: first,
          isScreenshot: true),
      ScannedPhoto(id: 'screenshot-b', fingerprint: second,
          isScreenshot: true),
    ]);
    expect(result.similar, isEmpty);
  });

  test('near-identical screenshots remain candidates', () {
    final white = List<int>.filled(24 * 24, 245);
    final slightVariation = List<int>.of(white)..[200] = 240;
    final first = PhotoFingerprint(rows: zeros, averageRgb: [245, 245, 245],
        sharpness: 100, spatialLuma: white);
    final second = PhotoFingerprint(rows: zeros, averageRgb: [245, 245, 245],
        sharpness: 100, spatialLuma: slightVariation);
    expect(matchingScreenshotLayout(first, second), isTrue);
    expect(classifyPhotos([
      ScannedPhoto(id: 's1', fingerprint: first, isScreenshot: true),
      ScannedPhoto(id: 's2', fingerprint: second, isScreenshot: true),
    ]).similar, [['s1', 's2']]);
  });

  test('screenshots do not group with normal photos', () {
    final photo = fingerprint(zeros);
    expect(classifyPhotos([
      ScannedPhoto(id: 'regular', fingerprint: photo),
      ScannedPhoto(id: 'screen', fingerprint: photo, isScreenshot: true),
    ]).similar, isEmpty);
  });

  test('unknown people status is never interpreted as no people', () {
    final photos = [
      ScannedPhoto(id: 'unknown', fingerprint: fingerprint(zeros)),
      ScannedPhoto(id: 'none', fingerprint: fingerprint(zeros), hasPeople: false),
      ScannedPhoto(id: 'seen', fingerprint: fingerprint(zeros), hasPeople: true),
    ];
    expect(classifyPhotos(photos).noPeople, ['none']);
  });

  test('blur is a review suggestion, not a delete decision', () {
    expect(potentiallyBlurry(fingerprint(zeros, sharpness: 3)), isTrue);
    expect(potentiallyBlurry(fingerprint(zeros, sharpness: 600)), isFalse);
  });
}
