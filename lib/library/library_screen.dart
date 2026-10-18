import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'filtering.dart';
import 'library_repository.dart';
import 'selection_review.dart';
import '../updates/update_button.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const int _pageSize = 100;
  final LibraryRepository _repository = LibraryRepository();
  final ScrollController _scroll = ScrollController();
  final List<AssetEntity> _assets = <AssetEntity>[];
  final Set<String> _selected = <String>{};

  AssetPathEntity? _album;
  PermissionState? _permission;
  MediaFilter _filter = MediaFilter.all;
  MediaSort _sort = MediaSort.newest;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _deleting = false;
  bool _selecting = false;
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
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || _loadingMore || !_hasMore) return;
    if (_scroll.position.extentAfter < 700) _fetchNext(_generation);
  }

  Future<void> _reload({bool requestPermission = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = true;
      _nextPage = 0;
      _libraryCount = 0;
      _album = null;
      _error = null;
      _assets.clear();
      _selected.clear();
      _selecting = false;
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
      final album = await _repository.openAll(
        type: _filter.requestType,
        oldestFirst: _sort == MediaSort.oldest,
      );
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

  List<AssetEntity> get _visible => _assets.where((asset) => isVisible(
        filter: _filter,
        type: asset.type,
        favorite: asset.isFavorite,
      )).toList(growable: false);

  void _toggleAsset(AssetEntity asset) {
    setState(() {
      _selecting = true;
      if (!_selected.add(asset.id)) _selected.remove(asset.id);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _showPreview(AssetEntity asset) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 780),
          child: Stack(children: <Widget>[
            Center(child: AssetEntityImage(
              asset,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize(1600, 1600),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined, color: Colors.white,
              ),
            )),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: 'Close preview',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
            if (asset.type == AssetType.video)
              const Positioned(
                bottom: 16,
                left: 16,
                child: Text('Video thumbnail • playback follows in a later release',
                    style: TextStyle(color: Colors.white)),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _reviewDeletion() async {
    final chosen = _assets.where((asset) => _selected.contains(asset.id)).toList();
    if (chosen.isEmpty || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SelectionReview(items: chosen),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      final deleted = await _repository.delete(chosen.map((e) => e.id).toList());
      if (!mounted) return;
      final deletedSet = deleted.toSet();
      setState(() {
        _assets.removeWhere((item) => deletedSet.contains(item.id));
        _selected.removeAll(deletedSet);
        _libraryCount = (_libraryCount - deletedSet.length).clamp(0, 1 << 30).toInt();
        _deleting = false;
        _selecting = _selected.isNotEmpty;
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
    final cols = (width / 145).floor().clamp(3, 8);
    return Scaffold(
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
      body: Column(children: [
        if (_permission?.isLimited == true)
          const MaterialBanner(
            content: Text('Limited Photos access: only selected assets are visible.'),
            actions: [SizedBox.shrink()],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Library', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            )),
            const SizedBox(height: 4),
            Text('${_assets.length} loaded · $_libraryCount in this view',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              for (final filter in MediaFilter.values) ...[
                ChoiceChip(
                  label: Text(filter.label),
                  selected: _filter == filter,
                  onSelected: _deleting ? null : (_) {
                    if (_filter == filter) return;
                    setState(() => _filter = filter);
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ])),
            const SizedBox(height: 9),
            Row(children: [
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
              const Spacer(),
              TextButton.icon(
                onPressed: visible.isEmpty ? null : () => setState(() {
                  _selecting = true;
                  _selected.addAll(visible.map((asset) => asset.id));
                }),
                icon: const Icon(Icons.checklist),
                label: const Text('Select loaded'),
              ),
              if (_selecting)
                TextButton(
                  onPressed: () => setState(() {
                    _selected.clear();
                    _selecting = false;
                  }),
                  child: const Text('Cancel'),
                ),
            ]),
          ]),
        ),
        Expanded(child: _buildContent(visible, cols)),
      ]),
      bottomNavigationBar: _selected.isEmpty ? null : SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _deleting ? null : _reviewDeletion,
            icon: _deleting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_outline),
            label: Text(_deleting
                ? 'Waiting for Photos…'
                : 'Review ${_selected.length} selected'),
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
              child: const Text('Open Settings')),
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
      return const Center(child: Text('No matching media found.'));
    }
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        if (_filter == MediaFilter.favorites)
          const SliverToBoxAdapter(child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Text('Favorites filter searches loaded batches; load more for older favorites.',
                style: TextStyle(fontSize: 12)),
          )),
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
              final selected = _selected.contains(asset.id);
              return Semantics(
                label: '${asset.type == AssetType.video ? "Video" : "Photo"} '
                    '${selected ? "selected" : "not selected"}',
                child: InkWell(
                  onLongPress: () => _toggleAsset(asset),
                  onTap: () => _selecting ? _toggleAsset(asset) : _showPreview(asset),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(fit: StackFit.expand, children: [
                      AssetEntityImage(
                        asset,
                        isOriginal: false,
                        thumbnailSize: const ThumbnailSize(350, 350),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xFFDEE5E5),
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                      if (selected) Container(
                        decoration: BoxDecoration(
                          color: const Color(0x44008790),
                          border: Border.all(color: const Color(0xFF008790), width: 4),
                        ),
                      ),
                      Positioned(
                        top: 5, right: 5,
                        child: Icon(selected ? Icons.check_circle :
                            (_selecting ? Icons.circle_outlined : null),
                            color: Colors.white),
                      ),
                      if (asset.type == AssetType.video)
                        const Positioned(bottom: 5, right: 5,
                          child: Icon(Icons.videocam, color: Colors.white, size: 19)),
                      if (asset.isFavorite)
                        const Positioned(bottom: 5, left: 5,
                          child: Icon(Icons.favorite, color: Colors.white, size: 17)),
                    ]),
                  ),
                ),
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
