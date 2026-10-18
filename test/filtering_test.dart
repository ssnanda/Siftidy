import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:siftidy/library/filtering.dart';

void main() {
  test('filters distinguish photo, video, and favorites', () {
    expect(isVisible(filter: MediaFilter.all, type: AssetType.image, favorite: false), isTrue);
    expect(isVisible(filter: MediaFilter.photos, type: AssetType.video, favorite: true), isFalse);
    expect(isVisible(filter: MediaFilter.videos, type: AssetType.video, favorite: false), isTrue);
    expect(isVisible(filter: MediaFilter.favorites, type: AssetType.image, favorite: false), isFalse);
    expect(isVisible(filter: MediaFilter.favorites, type: AssetType.video, favorite: true), isTrue);
  });

  test('human-readable sizes handle zero and GB', () {
    expect(formatByteCount(0), '0 B');
    expect(formatByteCount(1024), '1.0 KB');
    expect(formatByteCount(1024 * 1024), '1.0 MB');
    expect(formatByteCount(1024 * 1024 * 1024), '1.00 GB');
  });
}
