import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/library/photo_preview_geometry.dart';

void main() {
  test('portrait preview is image-sized without black side panels', () {
    final result = photoPreviewFrameSize(
      image: const Size(1170, 2532),
      viewport: const Size(1512, 982),
    );
    expect(result.height, closeTo(918, 0.001));
    expect(result.width, closeTo(424.2, 0.2));
  });

  test('landscape preview uses the available width', () {
    final result = photoPreviewFrameSize(
      image: const Size(1920, 1080),
      viewport: const Size(1300, 800),
    );
    expect(result.width, closeTo(1252, 0.1));
    expect(result.height, closeTo(704.25, 0.1));
  });

  test('deleting the active photo selects the next photo', () {
    expect(nextIndexAfterDeletion(
      ['a', 'b', 'c', 'd'], {'b'}, 1), 1);
  });

  test('deleting the last photo falls back to the previous one', () {
    expect(nextIndexAfterDeletion(
      ['a', 'b', 'c'], {'c'}, 2), 1);
  });

  test('batch delete skips deleted neighbors to the right', () {
    expect(nextIndexAfterDeletion(
      ['a', 'b', 'c', 'd', 'e'], {'b', 'c'}, 1), 1);
  });

  test('deleting all loaded photos returns no focus', () {
    expect(nextIndexAfterDeletion(['a', 'b'], {'a', 'b'}, 0), -1);
  });
}
