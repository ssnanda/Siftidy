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
