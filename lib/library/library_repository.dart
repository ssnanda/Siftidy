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

  static const String keeperAlbumName = 'Siftidy Keepers';

  /// PhotoKit album membership: no new image file is duplicated on macOS.
  static AssetPathEntity? keepersAlbum(List<AssetPathEntity> paths) {
    for (final path in userAlbums(paths)) {
      if (path.name == keeperAlbumName) return path;
    }
    // Fall back to an exact name lookup if PhotoKit did not label its type.
    for (final path in paths) {
      if (!path.isAll && path.name == keeperAlbumName) return path;
    }
    return null;
  }

  Future<Set<String>> keeperAssetIds(AssetPathEntity album) async {
    final ids = <String>{};
    for (var pageIndex = 0; ; pageIndex++) {
      final batch = await album.getAssetListPaged(page: pageIndex, size: 200);
      ids.addAll(batch.map((asset) => asset.id));
      if (batch.length < 200) break;
    }
    return ids;
  }

  /// Add existing Photos assets to a persistent Apple Photos album.
  /// This does not remove screenshots from the system Screenshots smart album.
  Future<int> addToKeepers(List<AssetEntity> assets) async {
    if (assets.isEmpty) return 0;
    final paths = await collections(oldestFirst: false);
    final keeper = keepersAlbum(paths) ??
        await PhotoManager.editor.darwin.createAlbum(keeperAlbumName);
    if (keeper == null) {
      throw StateError('Unable to create Siftidy Keepers album in Photos.');
    }
    var added = 0;
    for (final asset in assets) {
      final result = await PhotoManager.editor.copyAssetToPath(
        asset: asset,
        pathEntity: keeper,
      );
      if (result != null) added++;
    }
    return added;
  }

  Future<int> count(AssetPathEntity album) => album.assetCountAsync;

  /// System handles confirmation and moves deleted items to Recently Deleted.
  Future<List<String>> delete(List<String> ids) =>
      PhotoManager.editor.deleteWithIds(ids);
}
