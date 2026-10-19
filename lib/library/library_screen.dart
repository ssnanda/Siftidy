import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'photo_gallery_tile.dart';
import 'photo_preview_dialog.dart';

import 'filtering.dart';
import 'library_repository.dart';
import '../updates/update_button.dart';
import '../updates/mac_quick_updater.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const int _pageSize = 25;
  final LibraryRepository _repository = LibraryRepository();
  final ScrollController _scroll = ScrollController();
  final FocusNode _gridFocus = FocusNode(debugLabel: 'Siftidy photo grid');
  int _focusedIndex = -1;
  final List<AssetEntity> _assets = <AssetEntity>[];
  final List<AssetEntity> _visibleCache = <AssetEntity>[];
  final Set<String> _keeperIds = <String>{};
  Map<String, ValueNotifier<bool>> _selectedSignals = {};
  Map<String, ValueNotifier<bool>> _focusedSignals = {};
  final Set<String> _selected = <String>{};

  AssetPathEntity? _album;
  PermissionState? _permission;
  MediaFilter _filter = MediaFilter.screenshots;
  List<AssetPathEntity> _userAlbums = <AssetPathEntity>[];
  String? _albumId;
  bool _showRecordings = false;
  MediaSort _sort = MediaSort.newest;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _deleting = false;
  int _nextPage = 0;
  int _libraryCount = 0;
  int _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reload(requestPermission: true);
  }

  @override
  void dispose() {
    _generation++;
    _gridFocus.dispose();
    for (final value in _selectedSignals.values) { value.dispose(); }
    for (final value in _focusedSignals.values) { value.dispose(); }
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || _loadingMore || !_hasMore) return;
    if (_scroll.position.extentAfter < 700) _fetchNext(_generation);
  }

  Future<void> _reload({bool requestPermission = false}) async {
    final generation = ++_generation;
    final oldSelection = _selectedSignals;
    final oldFocus = _focusedSignals;
    _selectedSignals = {};
    _focusedSignals = {};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final value in oldSelection.values) { value.dispose(); }
      for (final value in oldFocus.values) { value.dispose(); }
    });
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = true;
      _nextPage = 0;
      _libraryCount = 0;
      _album = null;
      _error = null;
      _assets.clear();
      _visibleCache.clear();
      _selected.clear();
      _keeperIds.clear();
      _focusedIndex = -1;
    });
    try {
      if (requestPermission || _permission == null || !_permission!.hasAccess) {
        final permission = await _repository.requestAccess();
        if (!mounted || generation != _generation) return;
        _permission = permission;
      }
      if (!_permission!.hasAccess) {
        setState(() => _loading = false);
        return;
      }
      final collections = await _repository.collections(
        oldestFirst: _sort == MediaSort.oldest,
      );
      if (!mounted || generation != _generation) return;
      final userAlbums = LibraryRepository.userAlbums(collections);
      final keepers = LibraryRepository.keepersAlbum(collections);
      final keeperIds = keepers == null
          ? <String>{}
          : await _repository.keeperAssetIds(keepers);
      if (!mounted || generation != _generation) return;
      final screenshots = LibraryRepository.smartAlbum(
        collections, PMDarwinAssetCollectionSubtype.smartAlbumScreenshots,
      );
      final favorites = LibraryRepository.smartAlbum(
        collections, PMDarwinAssetCollectionSubtype.smartAlbumFavorites,
      );
      final recordings = LibraryRepository.smartAlbum(
        collections, PMDarwinAssetCollectionSubtype.smartAlbumScreenRecordings,
      );
      setState(() {
        _userAlbums = userAlbums;
        _keeperIds.addAll(keeperIds);
        _showRecordings = recordings != null;
      });
      AssetPathEntity? album;
      if (_albumId != null) {
        for (final item in userAlbums) {
          if (item.id == _albumId) {
            album = item;
            break;
          }
        }
      } else if (_filter == MediaFilter.screenshots) {
        album = screenshots;
      } else if (_filter == MediaFilter.keepers) {
        album = keepers;
      } else if (_filter == MediaFilter.favorites && favorites != null) {
        album = favorites;
      } else if (_filter == MediaFilter.screenRecordings) {
        album = recordings;
      } else {
        album = await _repository.openAll(
          type: _filter.requestType,
          oldestFirst: _sort == MediaSort.oldest,
        );
      }
      if (!mounted || generation != _generation) return;
      if (album == null) {
        setState(() {
          _hasMore = false;
          _loading = false;
        });
        return;
      }
      final count = await _repository.count(album);
      if (!mounted || generation != _generation) return;
      setState(() {
        _album = album;
        _libraryCount = count;
        _loading = false;
      });
      await _fetchNext(generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _fetchNext(int generation) async {
    final album = _album;
    if (album == null || !_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final batch = await _repository.page(album, _nextPage, _pageSize);
      if (!mounted || generation != _generation) return;
      setState(() {
        _assets.addAll(batch);
        _visibleCache.addAll(batch.where(_isVisibleAsset));
        _nextPage++;
        _hasMore = batch.length == _pageSize && _assets.length < _libraryCount;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error.toString();
        _loadingMore = false;
      });
    }
  }

  bool _isVisibleAsset(AssetEntity asset) =>
      (_filter != MediaFilter.screenshots || _albumId != null ||
          !_keeperIds.contains(asset.id)) &&
      isVisible(
        filter: _albumId != null ? MediaFilter.all : _filter,
        type: asset.type,
        favorite: asset.isFavorite,
      );

  /// Cached once per batch; selection never refilters the whole library.
  List<AssetEntity> get _visible => _visibleCache;

  String get _viewName {
    if (_albumId != null) {
      for (final album in _userAlbums) {
        if (album.id == _albumId) return album.name;
      }
    }
    return _filter.label;
  }

  void _chooseView(MediaFilter filter, {String? albumId, bool closeDrawer = false}) {
    if (_deleting || (_filter == filter && _albumId == albumId)) return;
    setState(() {
      _filter = filter;
      _albumId = albumId;
    });
    if (closeDrawer) Navigator.pop(context);
    _reload();
  }

  Widget _sidebarTile(
    BuildContext context,
    IconData icon,
    String title,
    MediaFilter filter, {
    String? albumId,
    bool closeDrawer = false,
  }) {
    final selected = _filter == filter && _albumId == albumId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        leading: Icon(icon, size: 20),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: _deleting ? null : () => _chooseView(
          filter, albumId: albumId, closeDrawer: closeDrawer,
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, {bool closeDrawer = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 10),
          child: Text('BROWSE', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2,
          )),
        ),
        Expanded(child: ListView(children: [
          _sidebarTile(context, Icons.screenshot_monitor_outlined,
            'Screenshots', MediaFilter.screenshots, closeDrawer: closeDrawer),
          _sidebarTile(context, Icons.bookmark_rounded,
            'Keepers', MediaFilter.keepers, closeDrawer: closeDrawer),
          _sidebarTile(context, Icons.photo_library_outlined,
            'All Media', MediaFilter.all, closeDrawer: closeDrawer),
          _sidebarTile(context, Icons.photo_outlined,
            'Photos', MediaFilter.photos, closeDrawer: closeDrawer),
          _sidebarTile(context, Icons.movie_outlined,
            'Videos', MediaFilter.videos, closeDrawer: closeDrawer),
          _sidebarTile(context, Icons.favorite_outline,
            'Favorites', MediaFilter.favorites, closeDrawer: closeDrawer),
          if (_showRecordings)
            _sidebarTile(context, Icons.videocam_outlined,
              'Screen Recordings', MediaFilter.screenRecordings,
              closeDrawer: closeDrawer),
          const Divider(height: 28, indent: 12, endIndent: 12),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 4, 18, 8),
            child: Text('APPLE PHOTOS ALBUMS', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1,
            )),
          ),
          if (_userAlbums.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Text('No albums found', style: TextStyle(fontSize: 12)),
            ),
          for (final album in _userAlbums)
            if (album.name != LibraryRepository.keeperAlbumName)
            _sidebarTile(context, Icons.folder_outlined, album.name,
              MediaFilter.all, albumId: album.id, closeDrawer: closeDrawer),
        ])),
        const Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'Browse existing Photos albums. Selection never changes an album.',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Future<void> _keepSelected() async {
    if (_deleting) return;
    final chosen = _assets.where(
        (asset) => _selected.contains(asset.id)).toList();
    if (chosen.isEmpty) return;
    setState(() => _deleting = true);
    try {
      final saved = await _repository.addToKeepers(chosen);
      if (!mounted) return;
      setState(() {
        _keeperIds.addAll(chosen.map((item) => item.id));
        if (_filter == MediaFilter.screenshots && _albumId == null) {
          _visibleCache.removeWhere((item) => _keeperIds.contains(item.id));
        }
        _selected.clear();
        for (final signal in _selectedSignals.values) {
          signal.value = false;
        }
        _deleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $saved to Siftidy Keepers in Apple Photos.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save to Keepers: $error')),
      );
    }
  }

  ValueNotifier<bool> _selectedSignal(String id) =>
      _selectedSignals.putIfAbsent(
        id, () => ValueNotifier<bool>(_selected.contains(id)));

  ValueNotifier<bool> _focusedSignal(String id) =>
      _focusedSignals.putIfAbsent(id, () => ValueNotifier<bool>(false));

  void _setSelected(AssetEntity asset, bool value) {
    if (_deleting || _selected.contains(asset.id) == value) return;
    setState(() {
      if (value) {
        _selected.add(asset.id);
      } else {
        _selected.remove(asset.id);
      }
      _selectedSignal(asset.id).value = value;
    });
  }

  void _toggleAsset(AssetEntity asset) {
    _setSelected(asset, !_selected.contains(asset.id));
  }

  void _focusAndSelectWithoutScroll(
      int index, List<AssetEntity> items) {
    if (index < 0 || index >= items.length) return;
    final old = _focusedIndex;
    setState(() {
      _focusedIndex = index;
      _selected.add(items[index].id);
      _selectedSignal(items[index].id).value = true;
    });
    if (old >= 0 && old != index && old < items.length) {
      _focusedSignal(items[old].id).value = false;
    }
    _focusedSignal(items[index].id).value = true;
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      for (final notifier in _selectedSignals.values) {
        notifier.value = false;
      }
    });
  }

  void _toggleAllLoaded(List<AssetEntity> visible, bool select) {
    if (_deleting) return;
    setState(() {
      for (final asset in visible) {
        if (select) {
          _selected.add(asset.id);
        } else {
          _selected.remove(asset.id);
        }
        _selectedSignal(asset.id).value = select;
      }
    });
  }

  void _showPreview(AssetEntity asset) {
    final items = _visible;
    final index = items.indexWhere((item) => item.id == asset.id);
    if (index < 0) return;
    _focusAndSelectWithoutScroll(index, items);
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => PhotoPreviewDialog(
        initialIndex: index,
        items: () => _visible,
        hasMore: () => _hasMore,
        loadMore: () => _fetchNext(_generation),
        selected: (id) => _selected.contains(id),
        visit: (item) {
          final current = _visible;
          final next = current.indexWhere((value) => value.id == item.id);
          if (next >= 0) {
            _focusAndSelect(next, current,
                galleryColumnCount(MediaQuery.sizeOf(context).width));
          }
        },
        toggle: _toggleAsset,
        delete: _deleteSelected,
        keep: _keepSelected,
      ),
    ).whenComplete(() {
      if (mounted) _gridFocus.requestFocus();
    });
  }

  KeyEventResult _handleGridKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _loading || _deleting) {
      return KeyEventResult.ignored;
    }
    final items = _visible;
    if (items.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      final index = _focusedIndex < 0 ? 0 : _focusedIndex;
      _toggleAsset(items[index]); // Space alone toggles keyboard selection.
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final index = _focusedIndex < 0 ? 0 : _focusedIndex;
      _showPreview(items[index]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (_selected.isNotEmpty) _deleteSelected();
      return KeyEventResult.handled;
    }
    final cols = galleryColumnCount(MediaQuery.sizeOf(context).width);
    int delta;
    if (key == LogicalKeyboardKey.arrowRight) {
      delta = 1;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      delta = -1;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      delta = cols;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      delta = -cols;
    } else {
      return KeyEventResult.ignored;
    }
    final next = _focusedIndex < 0 ? 0 : _focusedIndex + delta;
    if (next < 0) return KeyEventResult.handled;
    if (next >= items.length) {
      if (_hasMore && !_loadingMore) {
        final wanted = next;
        _fetchNext(_generation).then((_) {
          if (!mounted) return;
          final updated = _visible;
          if (wanted >= updated.length) return;
          _focusAndSelect(wanted, updated, cols);
        });
      }
      return KeyEventResult.handled;
    }
    _focusAndSelect(next, items, cols);
    return KeyEventResult.handled;
  }

  void _focusAndSelect(int index, List<AssetEntity> items, int cols) {
    _focusAndSelectWithoutScroll(index, items);
    if (!_scroll.hasClients) return;
    final window = MediaQuery.sizeOf(context).width;
    final available = window - (window >= 850 ? 244 : 0);
    final edge = (available - 24 - (cols - 1) * 6) / cols;
    final position = 8 + (index ~/ cols) * (edge + 6);
    final low = _scroll.offset;
    final high = low + _scroll.position.viewportDimension - edge - 18;
    if (position < low || position > high) {
      final target = position < low
          ? position - 12
          : position - _scroll.position.viewportDimension + edge + 20;
      _scroll.animateTo(
        target.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _deleteSelected() async {
    final chosen = _assets.where((asset) => _selected.contains(asset.id)).toList();
    if (chosen.isEmpty || _deleting) return;
    if (chosen.any((item) => _keeperIds.contains(item.id))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Keepers are protected from deletion in Siftidy.'),
      ));
      return;
    }
    setState(() => _deleting = true);
    try {
      final deleted = await _repository.delete(chosen.map((e) => e.id).toList());
      if (!mounted) return;
      final deletedSet = deleted.toSet();
      setState(() {
        _assets.removeWhere((item) => deletedSet.contains(item.id));
        _visibleCache.removeWhere((item) => deletedSet.contains(item.id));
        _selected.removeAll(deletedSet);
        _libraryCount = (_libraryCount - deletedSet.length).clamp(0, 1 << 30).toInt();
        _deleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(deletedSet.isEmpty
            ? 'No media was deleted.'
            : 'Deleted ${deletedSet.length} item(s). Check Photos → Recently Deleted.'),
      ));
      if (deletedSet.isNotEmpty) await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 850;
    final cols = galleryColumnCount(width);
    final allLoadedSelected = visible.isNotEmpty &&
        visible.every((item) => _selected.contains(item.id));
    return Scaffold(
      drawer: isWide ? null : Drawer(child: SafeArea(
        child: _buildSidebar(context, closeDrawer: true),
      )),
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Siftidy', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('Your photos. Your choice. On your device.',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
        ]),
        actions: [
          const UpdateButton(),
          IconButton(
            tooltip: 'Refresh library',
            icon: const Icon(Icons.refresh),
            onPressed: _deleting ? null : () => _reload(requestPermission: true),
          ),
          if (_permission?.isLimited == true)
            IconButton(
              tooltip: 'Choose more photos',
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: () async {
                await PhotoManager.presentLimited();
                if (mounted) await _reload(requestPermission: true);
              },
            ),
        ],
      ),
      body: Row(children: [
        if (isWide) ...[
          SizedBox(width: 244, child: _buildSidebar(context)),
          const VerticalDivider(width: 1),
        ],
        Expanded(child: Column(children: [
        if (_permission?.isLimited == true)
          const MaterialBanner(
            content: Text('Limited Photos access: only selected assets are visible.'),
            actions: [SizedBox.shrink()],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_viewName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            )),
            const SizedBox(height: 4),
            Wrap(spacing: 18, runSpacing: 4, children: [
              Text('Loaded: ${_visible.length} of $_libraryCount',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: Color(0xFF27383D))),
              const Text('25 at a time',
                style: TextStyle(fontSize: 13, color: Color(0xFF27383D))),
            ]),
            const SizedBox(height: 9),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<MediaSort>(
                  value: _sort,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: MediaSort.newest, child: Text('Newest first')),
                    DropdownMenuItem(value: MediaSort.oldest, child: Text('Oldest first')),
                  ],
                  onChanged: _deleting ? null : (value) {
                    if (value == null || value == _sort) return;
                    setState(() => _sort = value);
                    _reload();
                  },
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(
                    value: allLoadedSelected,
                    onChanged: _deleting || visible.isEmpty ? null :
                        (value) => _toggleAllLoaded(visible, value ?? false),
                  ),
                  Text('All loaded (${visible.length})'),
                ]),
                if (_selected.isNotEmpty) ...[
                  Text('${_selected.length} selected',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    onPressed: _deleting ? null : _clearSelection,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ]),
        ),
        Expanded(child: Focus(
          focusNode: _gridFocus,
          autofocus: true,
          onKeyEvent: _handleGridKeys,
          child: _buildContent(visible, cols),
        )),
      ])),
      ]),
      bottomNavigationBar: _selected.isEmpty ? null : SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: SizedBox(
            height: 64,
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(200, 56),
                        foregroundColor: const Color(0xFF005C62),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _deleting ? null : _keepSelected,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Keep in Keepers'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(265, 56),
                        backgroundColor: const Color(0xFFB42333),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _deleting ? null : _deleteSelected,
                      icon: _deleting
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.delete_forever_outlined, size: 24),
                      label: Text(_deleting ? 'Working…'
                          : 'Delete ${_selected.length} selected'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(List<AssetEntity> visible, int cols) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_permission?.hasAccess != true) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.photo_library_outlined, size: 60),
          const SizedBox(height: 10),
          const Text('Photos permission is required to browse your library.',
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: PhotoManager.openSetting,
              child: const Text('Photos Permissions')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: openMacPrivacySecurity,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Privacy & Security'),
          ),
          TextButton(onPressed: () => _reload(requestPermission: true),
              child: const Text('Try again')),
        ]),
      ));
    }
    if (_error != null && visible.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline),
        const SizedBox(height: 8),
        const Text('Unable to load media.'),
        TextButton(onPressed: () => _reload(), child: const Text('Retry')),
      ]));
    }
    if (visible.isEmpty && !_loadingMore && !_hasMore) {
      return Center(child: Text(_filter == MediaFilter.screenshots
          ? 'No screenshots found in Apple Photos.'
          : 'No matching media found.'));
    }
    return CustomScrollView(
      controller: _scroll,
      cacheExtent: 900,
      slivers: [

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          sliver: SliverGrid.builder(
            itemCount: visible.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              final asset = visible[index];
              return PhotoGalleryTile(
                key: ValueKey(asset.id),
                asset: asset,
                selected: _selectedSignal(asset.id),
                focused: _focusedSignal(asset.id),
                keeper: _keeperIds.contains(asset.id),
                onClick: () {
                  _gridFocus.requestFocus();
                  _focusAndSelectWithoutScroll(index, visible);
                  _setSelected(asset, true);
                },
                onPreview: () {
                  _gridFocus.requestFocus();
                  _showPreview(asset);
                },
              );
            },
          ),
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(child: _loadingMore
              ? const CircularProgressIndicator()
              : _hasMore
                  ? OutlinedButton(
                      onPressed: () => _fetchNext(_generation),
                      child: const Text('Load more'),
                    )
                  : const Text('End of loaded library', style: TextStyle(fontSize: 12))),
        )),
      ],
    );
  }
}
