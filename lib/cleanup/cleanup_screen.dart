import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../library/library_repository.dart';
import '../library/photo_preview_dialog.dart';
import 'cleanup_controller.dart';

enum CleanupCategory { exact, similar, blurry, noPeople }

extension CleanupCategoryLabel on CleanupCategory {
  String get label => switch (this) {
        CleanupCategory.exact => 'Exact duplicates',
        CleanupCategory.similar => 'Similar photos',
        CleanupCategory.blurry => 'Possibly blurry',
        CleanupCategory.noPeople => 'No people detected',
      };

  IconData get icon => switch (this) {
        CleanupCategory.exact => Icons.content_copy_outlined,
        CleanupCategory.similar => Icons.filter_none_outlined,
        CleanupCategory.blurry => Icons.blur_on_outlined,
        CleanupCategory.noPeople => Icons.person_off_outlined,
      };
}

/// Inline in the primary gallery: no separate page or modal for suggestions.
/// Preview is the identical PhotoPreviewDialog used by the photo browser.
class CleanupWorkspace extends StatefulWidget {
  const CleanupWorkspace({
    super.key,
    required this.controller,
    required this.category,
    required this.onLibraryChanged,
  });
  final CleanupController controller;
  final CleanupCategory category;
  final VoidCallback onLibraryChanged;

  @override
  State<CleanupWorkspace> createState() => _CleanupWorkspaceState();
}

class _CleanupWorkspaceState extends State<CleanupWorkspace> {
  final LibraryRepository _repository = LibraryRepository();
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  void didUpdateWidget(CleanupWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) _selected.clear();
  }

  List<List<String>> get _groups => switch (widget.category) {
        CleanupCategory.exact => widget.controller.exact,
        CleanupCategory.similar => widget.controller.similar,
        CleanupCategory.blurry => _chunk(widget.controller.blurry),
        CleanupCategory.noPeople => _chunk(widget.controller.noPeople),
      };

  static List<List<String>> _chunk(List<String> items) => [
        for (var i = 0; i < items.length; i += 24)
          items.sublist(i, i + 24 > items.length ? items.length : i + 24),
      ];

  List<AssetEntity> get _visible => [
        for (final group in _groups)
          for (final id in group)
            if (widget.controller.result?.photos[id] case final AssetEntity asset)
              asset,
      ];

  void _toggle(String id) => setState(() {
        if (!_selected.add(id)) _selected.remove(id);
      });

  void _notice(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  /// Select the redundant copies. The keeper itself is never selected.
  void _keepOne(List<String> group, String keeperId) {
    setState(() {
      _selected.removeAll(group);
      _selected.addAll(group.where((id) => id != keeperId));
    });
    _notice('Keeping one. Review ${group.length - 1} selected copies before deleting.');
  }

  String _bestKeeper(List<String> group) {
    final photos = widget.controller.result!.photos;
    final sorted = [...group]..sort((a, b) {
        final x = photos[a]!;
        final y = photos[b]!;
        if (x.isFavorite != y.isFavorite) return x.isFavorite ? -1 : 1;
        final sizeX = x.width * x.height;
        final sizeY = y.width * y.height;
        final diff = sizeY.compareTo(sizeX);
        return diff == 0 ? y.createDateTime.compareTo(x.createDateTime) : diff;
      });
    return sorted.first;
  }

  bool _safeToDelete(Set<String> requested) {
    for (final group in [...widget.controller.exact, ...widget.controller.similar]) {
      if (group.isNotEmpty && group.every(requested.contains)) return false;
    }
    return true;
  }

  Future<bool> _deleteIds(Set<String> ids) async {
    if (_busy || ids.isEmpty) return false;
    final currentIds = _visible.map((item) => item.id).toSet();
    if (!currentIds.containsAll(ids)) {
      _notice('Some selected photos are no longer in this scan. Select again.');
      setState(() => _selected.removeAll(ids));
      return false;
    }
    if (!_safeToDelete(ids)) {
      _notice('Select at least one photo to keep in each duplicate group.');
      return false;
    }
    setState(() => _busy = true);
    try {
      // Apple Photos owns its normal deletion confirmation. Never delete on scan.
      final removed = await _repository.delete(ids.toList());
      if (!mounted) return false;
      widget.controller.exclude(removed);
      setState(() => _selected.removeAll(removed));
      widget.onLibraryChanged();
      _notice(removed.isEmpty ? 'No photos deleted.' :
          '${removed.length} photo(s) sent to Apple Photos Recently Deleted.');
      return removed.isNotEmpty;
    } catch (e) {
      if (mounted) _notice('Delete failed: $e');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _keepIds(List<AssetEntity> assets) async {
    if (_busy || assets.isEmpty) return false;
    setState(() => _busy = true);
    try {
      await _repository.addToKeepers(assets);
      if (!mounted) return false;
      widget.controller.exclude(assets.map((e) => e.id));
      setState(() => _selected.removeAll(assets.map((e) => e.id)));
      widget.onLibraryChanged();
      _notice('Saved ${assets.length} photos to Siftidy Keepers.');
      return true;
    } catch (e) {
      if (mounted) _notice('Could not save to Keepers: $e');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _keepSelected() => _keepIds([
        for (final id in _selected)
          if (widget.controller.result?.photos[id] case final AssetEntity asset)
            asset,
      ]).then((_) {});

  Future<void> _preview(AssetEntity asset) async {
    final items = _visible;
    final index = items.indexWhere((e) => e.id == asset.id);
    if (index == -1) return;
    // Match the main browser's double-click preview, keyboard and zoom behavior.
    setState(() => _selected.add(asset.id));
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => PhotoPreviewDialog(
        initialIndex: index,
        items: () => _visible,
        hasMore: () => false,
        loadMore: () async {},
        selected: (id) => _selected.contains(id),
        visit: (item) { if (mounted) setState(() => _selected.add(item.id)); },
        toggle: (item) => _toggle(item.id),
        delete: (item) => _deleteIds({item.id}),
        keep: (item) => _keepIds([item]),
      ),
    );
  }

  String _etaLabel(Duration? duration) {
    if (duration == null) return 'Estimating time…';
    if (duration.inMinutes >= 60) {
      return '~${duration.inHours}h ${duration.inMinutes.remainder(60)}m left';
    }
    if (duration.inMinutes >= 1) return '~${duration.inMinutes}m left';
    return '~${duration.inSeconds}s left';
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final groups = _groups;
    final result = controller.result;
    final progress = controller.total > 0
        ? '${controller.visited} / ${controller.total}' : 'Preparing photos…';
    final canReview = widget.category == CleanupCategory.exact ||
        widget.category == CleanupCategory.similar;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.category.label,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              )),
          const SizedBox(height: 4),
          const Text('Suggestions appear as scanning progresses. Review each photo; nothing is removed automatically.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 7, crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: controller.running || _busy ? null : () => controller.start(
                  scopeYear: controller.year,
                  people: controller.analyzingPeople,
                ),
                icon: const Icon(Icons.radar_outlined),
                label: Text(controller.running ? 'Scanning…' : 'Scan / Rescan'),
              ),
              if (controller.running) ...[
                OutlinedButton.icon(
                  onPressed: controller.pauseOrResume,
                  icon: Icon(controller.paused ? Icons.play_arrow : Icons.pause),
                  label: Text(controller.paused ? 'Resume' : 'Pause'),
                ),
                TextButton(onPressed: controller.stop, child: const Text('Stop')),
              ],
              DropdownButton<int?>(
                value: controller.year,
                underline: const SizedBox.shrink(),
                hint: const Text('All years'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All years')),
                  for (final year in {
                    ...?result?.years,
                    ...List<int>.generate(12, (i) => DateTime.now().year - i),
                  }.toList()..sort((a,b) => b.compareTo(a)))
                    DropdownMenuItem<int?>(value: year, child: Text('$year')),
                ],
                onChanged: controller.running || _busy ? null : (year) => controller.start(
                  scopeYear: year, people: controller.analyzingPeople,
                ),
              ),
              FilterChip(
                label: const Text('Analyze people (slower)'),
                selected: controller.analyzingPeople,
                onSelected: controller.running || _busy ? null : (value) => controller.start(
                  scopeYear: controller.year, people: value,
                ),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(
                  value: controller.autoScan,
                  onChanged: (value) => controller.setAutoScan(value ?? false),
                ),
                const Text('Auto scan on launch'),
              ]),
            ],
          ),
          if (controller.running || controller.paused) ...[
            const SizedBox(height: 7),
            LinearProgressIndicator(value: controller.total == 0 ? null : controller.fraction),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              controller.running
                  ? '$progress · ${controller.paused ? "Paused" : _etaLabel(controller.eta)} · ${result?.photos.length ?? 0} analyzed'
                  : controller.completed
                      ? 'Scan complete · ${result?.photos.length ?? 0} analyzed · ${result?.skipped ?? 0} unavailable'
                      : 'Scan is not running. You can start or resume it here.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (controller.error != null)
            Text(controller.error!, style: const TextStyle(color: Colors.red)),
          if (widget.category == CleanupCategory.noPeople &&
              !controller.analyzingPeople)
            const Text('Enable “Analyze people” to populate this category. A quick duplicate scan does not classify people.',
              style: TextStyle(fontSize: 12)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: result == null
          ? Center(child: Text(controller.running
              ? 'Finding photos in the background…'
              : 'Choose Scan to look for suggestions.'))
          : groups.isEmpty
              ? Center(child: Text(controller.running
                  ? 'No matches yet. More results may appear during the scan.'
                  : 'No ${widget.category.label.toLowerCase()} found in this scan.'))
              : ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(spacing: 12, runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(canReview
                                  ? 'Group ${index + 1} · ${group.length} copies'
                                  : '${group.length} photos',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (canReview) OutlinedButton.icon(
                                onPressed: _busy ? null : () => _keepOne(
                                  group, _bestKeeper(group)),
                                icon: const Icon(Icons.auto_fix_high, size: 16),
                                label: const Text('Keep best · review others'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Wrap(spacing: 7, runSpacing: 7, children: [
                            for (final id in group)
                              if (result.photos[id] case final AssetEntity photo)
                                _tile(photo, canReview ? group : null),
                          ]),
                          const Divider(height: 20),
                        ],
                      ),
                    );
                  },
                )),
      if (_selected.isNotEmpty)
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 10, runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${_selected.length} selected'),
              TextButton(onPressed: _busy ? null : () => setState(_selected.clear),
                child: const Text('Clear')),
              OutlinedButton.icon(
                onPressed: _busy ? null : _keepSelected,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Keep in Keepers')),
              FilledButton.icon(
                onPressed: _busy ? null : () => _deleteIds(Set.of(_selected)),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42333)),
                icon: const Icon(Icons.delete_outline),
                label: Text('Delete ${_selected.length} selected')),
            ],
          ),
        )),
    ]);
  }

  Widget _tile(AssetEntity photo, List<String>? group) {
    final selected = _selected.contains(photo.id);
    return SizedBox(width: 160, height: 183, child: Column(children: [
      Expanded(child: InkWell(
        onTap: () => _toggle(photo.id),
        onDoubleTap: () => _preview(photo),
        child: ClipRRect(borderRadius: BorderRadius.circular(8),
          child: Stack(fit: StackFit.expand, children: [
            AssetEntityImage(photo, isOriginal: false,
              thumbnailSize: const ThumbnailSize(320, 320), fit: BoxFit.cover),
            Positioned(top: 5, right: 5, child: Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? const Color(0xFF76FFE0) : Colors.white,
              shadows: const [Shadow(blurRadius: 5, color: Colors.black87)],
            )),
            if (photo.isFavorite)
              const Positioned(bottom: 5, left: 5,
                child: Icon(Icons.favorite, color: Color(0xFFE94E70))),
          ]),
        ),
      )),
      if (group != null)
        SizedBox(height: 27, child: TextButton(
          onPressed: _busy ? null : () => _keepOne(group, photo.id),
          child: const Text('Keep this one', style: TextStyle(fontSize: 11)),
        )),
    ]));
  }
}