import 'package:photo_manager/photo_manager.dart';

enum MediaFilter { all, photos, videos, favorites }

enum MediaSort { newest, oldest }

extension MediaFilterDetails on MediaFilter {
  String get label => switch (this) {
    MediaFilter.all => 'All',
    MediaFilter.photos => 'Photos',
    MediaFilter.videos => 'Videos',
    MediaFilter.favorites => 'Favorites',
  };

  RequestType get requestType => switch (this) {
    MediaFilter.photos => RequestType.image,
    MediaFilter.videos => RequestType.video,
    _ => RequestType.common,
  };
}

bool isVisible({
  required MediaFilter filter,
  required AssetType type,
  required bool favorite,
}) => switch (filter) {
  MediaFilter.all => type == AssetType.image || type == AssetType.video,
  MediaFilter.photos => type == AssetType.image,
  MediaFilter.videos => type == AssetType.video,
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
