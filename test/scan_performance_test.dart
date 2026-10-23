import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:siftidy/background/scan_runtime.dart';
import 'package:siftidy/cleanup/photo_analysis.dart';

void main() {
  test('batch fingerprinting preserves individual results', () {
    final photo = img.Image(width: 24, height: 24);
    for (var y = 0; y < photo.height; y++) {
      for (var x = 0; x < photo.width; x++) {
        photo.setPixelRgb(x, y, x * 10, y * 10, 80);
      }
    }
    final bytes = Uint8List.fromList(img.encodePng(photo));
    final individually = fingerprintThumbnail(bytes);
    final batch = fingerprintThumbnailBatch([bytes, bytes, null]);
    expect(batch.length, 3);
    expect(batch[0]?.rows, individually?.rows);
    expect(batch[0]?.averageRgb, individually?.averageRgb);
    expect(batch[0]?.spatialLuma, individually?.spatialLuma);
    expect(batch[1]?.rows, individually?.rows);
    expect(batch[2], isNull);
  });

  test('corrupt thumbnail only fails its own slot', () {
    final photo = img.Image(width: 12, height: 12);
    photo.setPixelRgb(3, 5, 120, 120, 120);
    final valid = Uint8List.fromList(img.encodePng(photo));
    final results = fingerprintThumbnailBatch([
      Uint8List.fromList([0, 1, 2]),
      valid,
      null,
    ]);
    expect(results, hasLength(3));
    expect(results[0], isNull);
    expect(results[1], isNotNull);
    expect(results[2], isNull);
  });

  test('Turbo has bounded batch concurrency without per-photo pacing', () {
    expect(ScanMode.turbo.concurrency, 6);
    expect(ScanMode.turbo.minimumPacing, Duration.zero);
    expect(ScanMode.balanced.concurrency,
        lessThan(ScanMode.turbo.concurrency));
  });
}
