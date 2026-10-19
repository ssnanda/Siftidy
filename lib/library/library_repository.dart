import 'package:photo_manager/photo_manager.dart';

/// PhotoKit-backed repository, kept separate from Flutter widgets for v0.2.
class LibraryRepository {
  Future<PermissionState> requestAccess() => PhotoManager.requestPermissionExtend();

  Future<AssetPathEntity?> openAll({
    required RequestType type,
    required bool oldestFirst,
  }) async {
    final albums = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: type,
      filterOption: FilterOptionGroup(
        orders: <OrderOption>[
          OrderOption(type: OrderOptionType.createDate, asc: oldestFirst),
        ],
      ),
    );
    return albums.isEmpty ? null : albums.first;
  }

  /// Read PhotoKit smart albums plus user-created albums for navigation.
  Future<List<AssetPathEntity>> collections({required bool oldestFirst}) =>
      PhotoManager.getAssetPathList(
        hasAll: true,
        type: RequestType.common,
        filterOption: FilterOptionGroup(
          orders: <OrderOption>[
            OrderOption(type: OrderOptionType.createDate, asc: oldestFirst),
          ],
        ),
      );

  static AssetPathEntity? smartAlbum(
      List<AssetPathEntity> paths, PMDarwinAssetCollectionSubtype subtype) {
    for (final path in paths) {
      if (path.albumTypeEx?.darwin?.subtype == subtype) return path;
    }
    // Some Photos installations omit the subtype on their screenshot album.
    if (subtype == PMDarwinAssetCollectionSubtype.smartAlbumScreenshots) {
      for (final path in paths) {
        if (path.name.toLowerCase() == 'screenshots') return path;
      }
    }
    return null;
  }

  static List<AssetPathEntity> userAlbums(List<AssetPathEntity> paths) {
    final result = paths.where((path) =>
      !path.isAll &&
      path.albumTypeEx?.darwin?.type == PMDarwinAssetCollectionType.album
    ).toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<List<AssetEntity>> page(AssetPathEntity album, int page, int size) =>
      album.getAssetListPaged(page: page, size: size);

  Future<int> count(AssetPathEntity album) => album.assetCountAsync;

  /// System handles confirmation and moves deleted items to Recently Deleted.
  Future<List<String>> delete(List<String> ids) =>
      PhotoManager.editor.deleteWithIds(ids);
}
