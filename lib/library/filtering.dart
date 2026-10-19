import 'package:photo_manager/photo_manager.dart';

enum MediaFilter { screenshots, all, photos, videos, favorites, screenRecordings }

enum MediaSort { newest, oldest }

extension MediaFilterDetails on MediaFilter {
  String get label => switch (this) {
    MediaFilter.screenshots => 'Screenshots',
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
