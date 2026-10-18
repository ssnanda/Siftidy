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

  Future<List<AssetEntity>> page(AssetPathEntity album, int page, int size) =>
      album.getAssetListPaged(page: page, size: size);

  Future<int> count(AssetPathEntity album) => album.assetCountAsync;

  /// System handles confirmation and moves deleted items to Recently Deleted.
  Future<List<String>> delete(List<String> ids) =>
      PhotoManager.editor.deleteWithIds(ids);
}
