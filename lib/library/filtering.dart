import 'package:photo_manager/photo_manager.dart';

enum MediaFilter { screenshots, keepers, all, photos, videos, favorites, screenRecordings }

enum MediaSort { newest, oldest }

extension MediaFilterDetails on MediaFilter {
  String get label => switch (this) {
    MediaFilter.screenshots => 'Screenshots',
    MediaFilter.keepers => 'Keepers',
    MediaFilter.all => 'All Media',
    MediaFilter.photos => 'Photos',
    MediaFilter.videos => 'Videos',
    MediaFilter.favorites => 'Favorites',
    MediaFilter.screenRecordings => 'Screen Recordings',
  };

  RequestType get requestType => switch (this) {
    MediaFilter.screenshots => RequestType.image,
    MediaFilter.photos => RequestType.image,
    MediaFilter.videos => RequestType.video,
    MediaFilter.screenRecordings => RequestType.video,
    _ => RequestType.common,
  };
}

bool isVisible({
  required MediaFilter filter,
  required AssetType type,
  required bool favorite,
}) => switch (filter) {
  MediaFilter.all => type == AssetType.image || type == AssetType.video,
  MediaFilter.screenshots => type == AssetType.image,
  MediaFilter.keepers => type == AssetType.image || type == AssetType.video,
  MediaFilter.photos => type == AssetType.image,
  MediaFilter.videos || MediaFilter.screenRecordings => type == AssetType.video,
  MediaFilter.favorites => favorite &&
      (type == AssetType.image || type == AssetType.video),
};

String formatByteCount(int count) {
  if (count < 1024) return '$count B';
  if (count < 1024 * 1024) return '${(count / 1024).toStringAsFixed(1)} KB';
  if (count < 1024 * 1024 * 1024) {
    return '${(count / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(count / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Approximately 25% larger thumbnails than the original 160px grid.
int galleryColumnCount(double windowWidth) {
  final available = windowWidth - (windowWidth >= 850 ? 244 : 0) - 24;
  return (available / 205).floor().clamp(2, 8);
}
