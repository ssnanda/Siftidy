import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../library/library_repository.dart';
import '../library/photo_preview_dialog.dart';
import 'cleanup_controller.dart';
import '../background/scan_runtime.dart';
import 'duplicate_selection.dart';
import 'media_sizes.dart';
import 'scan_history_view.dart';

enum CleanupCategory { exact, similar, blurry, noPeople, accidental, propertyTours }

extension CleanupCategoryLabel on CleanupCategory {
  String get label => switch (this) {
        CleanupCategory.exact => 'Exact duplicates',
        CleanupCategory.similar => 'Similar photos',
        CleanupCategory.blurry => 'Possibly blurry',
        CleanupCategory.noPeople => 'Scenes & objects',
        CleanupCategory.accidental => 'Accidental screenshots',
        CleanupCategory.propertyTours => 'Property tours',
      };

  IconData get icon => switch (this) {
        CleanupCategory.exact => Icons.content_copy_outlined,
        CleanupCategory.similar => Icons.filter_none_outlined,
        CleanupCategory.blurry => Icons.blur_on_outlined,
        CleanupCategory.noPeople => Icons.person_off_outlined,
        CleanupCategory.accidental => Icons.screenshot_outlined,
        CleanupCategory.propertyTours => Icons.home_outlined,
      };
}

/// All Siftidy cleanup views share the gallery selection and preview model.
/// Duplicate sets show ONE thumbnail each; deletion always retains a keeper.
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
  final MediaSizes _sizes = MediaSizes.instance;
  final Set<String> _selectedGroups = {};
  final Set<String> _selectedPhotos = {};
  final Map<String, String> _keeperChoices = {};
  String? _expanded;
  ScreenshotSuggestionKind? _screenshotFilter;
  late int _observedRevision;
  bool _busy = false;
  String? _message;

  bool get _groupMode => widget.category == CleanupCategory.exact ||
      widget.category == CleanupCategory.similar;

  @override
  void initState() {
    super.initState();
    _observedRevision = widget.controller.scanRevision;
    _sizes.addListener(_onSizes);
  }

  void _onSizes() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sizes.removeListener(_onSizes);
    super.dispose();
  }

  @override
  void didUpdateWidget(CleanupWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category ||
        _observedRevision != widget.controller.scanRevision ||
        oldWidget.controller != widget.controller) {
      _observedRevision = widget.controller.scanRevision;
      _selectedGroups.clear();
      _selectedPhotos.clear();
      _keeperChoices.clear();
      _expanded = null;
      _screenshotFilter = null;
      _message = null;
    }
  }

  List<List<String>> get _groups => switch (widget.category) {
        CleanupCategory.exact => widget.controller.exact,
        CleanupCategory.similar => widget.controller.similar,
        CleanupCategory.blurry => _chunk(widget.controller.blurry),
        CleanupCategory.noPeople => _chunk(widget.controller.noPeople),
        CleanupCategory.accidental => _chunk([
          for (final id in widget.controller.accidentalScreenshots)
            if (_screenshotFilter == null ||
                screenshotKindForReason(widget.controller.result?.groups
                    .accidentalReasons[id]) == _screenshotFilter)
              id,
        ]),
        CleanupCategory.propertyTours => const <List<String>>[],
      };

  static List<List<String>> _chunk(List<String> items) => [
        for (var i = 0; i < items.length; i += 50)
          items.sublist(i, i + 50 > items.length ? items.length : i + 50),
      ];

  List<AssetEntity> get _visible => [
        for (final group in _groups)
          for (final id in group)
            if (widget.controller.result?.photos[id]
                case final AssetEntity photo)
              photo,
      ];

  String _key(List<String> group) => group.first;

  String _bestKeeper(List<String> group) {
    final assets = widget.controller.result!.photos;
    final sorted = [...group]
      ..sort((a, b) {
        final x = assets[a]!;
        final y = assets[b]!;
        if (x.isFavorite != y.isFavorite) {
          return x.isFavorite ? -1 : 1;
        }
        final dimensionDifference = (y.width * y.height)
            .compareTo(x.width * x.height);
        return dimensionDifference != 0
            ? dimensionDifference
            : y.createDateTime.compareTo(x.createDateTime);
      });
    return sorted.first;
  }

  String _keeper(List<String> group) {
    final preferred = _keeperChoices[_key(group)];
    return preferred != null && group.contains(preferred)
        ? preferred
        : _bestKeeper(group);
  }

  List<List<String>> get _selectedSets => [
        for (final group in _groups)
          if (_selectedGroups.contains(_key(group))) group,
      ];

  Set<String> get _plannedExtras =>
      duplicateExtras(_groups, _selectedGroups, _keeper);

  Set<String> get _currentlySelectedPhotoIds => {
        for (final photo in _visible)
          if (_selectedPhotos.contains(photo.id)) photo.id,
      };

  void _inspect(Iterable<String> ids) {
    final assets = widget.controller.result?.photos;
    if (assets == null) return;
    _sizes.inspect([
      for (final id in ids)
        if (assets[id] case final AssetEntity photo) photo,
    ]);
  }

  void _toggleGroup(List<String> group) {
    if (_busy) return;
    setState(() {
      if (!_selectedGroups.add(_key(group))) {
        _selectedGroups.remove(_key(group));
      }
      _message = null;
    });
    if (_selectedGroups.contains(_key(group))) _inspect(_plannedExtras);
  }

  void _togglePhoto(AssetEntity photo) {
    if (_busy) return;
    setState(() {
      if (!_selectedPhotos.add(photo.id)) {
        _selectedPhotos.remove(photo.id);
      }
      _message = null;
    });
    if (_selectedPhotos.contains(photo.id)) _inspect([photo.id]);
  }

  void _keepEntireGroup(List<String> group) {
    if (_busy) return;
    widget.controller.dismissGroup(group,
      similar: widget.category == CleanupCategory.similar);
    setState(() {
      _selectedGroups.remove(_key(group));
      _keeperChoices.remove(_key(group));
      _expanded = null;
      _message = 'All ${group.length} photos kept; this suggestion was dismissed.';
    });
  }

  void _discardScan() {
    if (_busy) return;
    widget.controller.discardScan();
    setState(() {
      _selectedGroups.clear();
      _selectedPhotos.clear();
      _keeperChoices.clear();
      _expanded = null;
      _observedRevision = widget.controller.scanRevision;
      _message = 'Scan results discarded. No photos were changed.';
    });
  }

  void _selectAll(bool value) {
    if (_busy) return;
    setState(() {
      if (_groupMode) {
        _selectedGroups
          ..clear()
          ..addAll(value ? _groups.map(_key) : const <String>[]);
      } else {
        _selectedPhotos
          ..clear()
          ..addAll(value ? _visible.map((item) => item.id) : const <String>[]);
      }
      _message = null;
    });
    if (value) {
      _inspect(_groupMode ? _plannedExtras : _currentlySelectedPhotoIds);
    }
  }

  void _chooseKeeper(List<String> group, String id) {
    setState(() {
      _keeperChoices[_key(group)] = id;
      _message = null;
    });
    if (_selectedGroups.contains(_key(group))) _inspect(_plannedExtras);
  }

  bool _safeToDelete(Set<String> requested) {
    // Prevent removing every member of any recognized duplicate set.
    for (final group in [
      ...widget.controller.exact,
      ...widget.controller.similar,
    ]) {
      if (group.isNotEmpty && group.every(requested.contains)) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _deleteIds(Set<String> requested) async {
    if (_busy || requested.isEmpty) return false;
    final currentIds = _visible.map((photo) => photo.id).toSet();
    if (!currentIds.containsAll(requested) || !_safeToDelete(requested)) {
      setState(() => _message =
          'Selection changed. Keep at least one copy of each duplicate set.');
      return false;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // PhotoKit owns final confirmation and Recently Deleted semantics.
      final removed = await _repository.delete(
        requested.toList(),
        knownSizes: _sizes.knownFor(requested),
      );
      if (!mounted) return false;
      widget.controller.exclude(removed);
      setState(() {
        _selectedGroups.removeWhere((key) =>
            !_groups.any((group) => _key(group) == key));
        _selectedPhotos.removeAll(removed);
        _message = removed.isEmpty ? 'Nothing was deleted.' : null;
      });
      if (removed.isNotEmpty) widget.onLibraryChanged();
      return removed.isNotEmpty;
    } catch (e) {
      if (mounted) setState(() => _message = 'Deletion failed: $e');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected() async {
    final requested = _groupMode ? _plannedExtras : _currentlySelectedPhotoIds;
    if (requested.isEmpty) return;
    final worked = await _deleteIds(requested);
    if (worked && mounted) {
      setState(() {
        _selectedGroups.clear();
        _selectedPhotos.clear();
        _expanded = null;
      });
    }
  }

  Future<bool> _keepIds(List<AssetEntity> assets) async {
    if (_busy || assets.isEmpty) return false;
    setState(() => _busy = true);
    try {
      await _repository.addToKeepers(assets);
      if (!mounted) return false;
      widget.controller.exclude(assets.map((photo) => photo.id));
      setState(() {
        _selectedPhotos.removeAll(assets.map((photo) => photo.id));
        _message = null;
      });
      widget.onLibraryChanged();
      return true;
    } catch (e) {
      if (mounted) setState(() => _message = 'Unable to save to Keepers: $e');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(AssetEntity photo) async {
    final index = _visible.indexWhere((asset) => asset.id == photo.id);
    if (index < 0) return;
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => PhotoPreviewDialog(
        initialIndex: index,
        items: () => _visible,
        hasMore: () => false,
        loadMore: () async {},
        selected: (id) => _groupMode
            ? _groups.any((group) => group.contains(id) &&
                _selectedGroups.contains(_key(group)))
            : _selectedPhotos.contains(id),
        visit: (_) {},
        toggle: (asset) {
          if (_groupMode) {
            for (final group in _groups) {
              if (group.contains(asset.id)) {
                _toggleGroup(group);
                break;
              }
            }
          } else {
            _togglePhoto(asset);
          }
        },
        delete: (asset) => _deleteIds({asset.id}),
        keep: (asset) => _keepIds([asset]),
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
    if (controller.showHistory) {
      return ScanHistoryView(
        store: controller.checkpointStore,
        onBack: controller.toggleHistory,
      );
    }
    final result = controller.result;
    final groups = _groups;
    final selectedCount = _groupMode
        ? _selectedSets.length
        : _currentlySelectedPhotoIds.length;
    final allCount = _groupMode ? groups.length : _visible.length;
    final selectedIds = _groupMode ? _plannedExtras : _currentlySelectedPhotoIds;
    final canDelete = selectedCount > 0 && !_busy && selectedIds.isNotEmpty;

    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.category.label,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              )),
          const SizedBox(height: 5),
          Text(_groupMode
              ? 'One tile = one set. Select sets, then keep one photo from each and delete the extras.'
              : 'Select the photos you want to review or delete. No automatic removal.',
            style: const TextStyle(fontSize: 12)),
          if (widget.category == CleanupCategory.accidental &&
              widget.controller.accidentalScreenshots.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 6, children: [
              FilterChip(
                label: Text('All ${widget.controller.accidentalScreenshots.length}'),
                selected: _screenshotFilter == null,
                onSelected: (_) => setState(() {
                  _screenshotFilter = null;
                  _selectedPhotos.clear();
                }),
              ),
              for (final kind in ScreenshotSuggestionKind.values)
                if (widget.controller.accidentalScreenshots.where(
                    (id) => screenshotKindForReason(widget.controller
                        .result?.groups.accidentalReasons[id]) == kind)
                    .isNotEmpty)
                  FilterChip(
                    label: Text('${kind.label} · ${widget.controller
                        .accidentalScreenshots.where((id) =>
                            screenshotKindForReason(widget.controller.result
                                ?.groups.accidentalReasons[id]) == kind)
                        .length}'),
                    selected: _screenshotFilter == kind,
                    onSelected: (_) => setState(() {
                      _screenshotFilter = kind;
                      _selectedPhotos.clear();
                    }),
                  ),
            ]),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: controller.running || _busy ? null : () => controller.start(
                  scopeYear: controller.year, people: controller.analyzingPeople,
                ),
                icon: const Icon(Icons.radar_outlined),
                label: Text(controller.running ? 'Scanning…' : 'Scan / Rescan'),
              ),
              DropdownButton<ScanMode>(
                value: controller.performance.activeMode,
                underline: const SizedBox.shrink(),
                items: [
                  for (final mode in ScanMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(mode == ScanMode.turbo
                          ? 'Turbo (temporary)' : mode.title),
                    ),
                ],
                onChanged: (mode) {
                  if (mode == null) return;
                  controller.performance.setBaseMode(mode);
                },
              ),
              PopupMenuButton<int>(
                tooltip: 'Run Turbo for a chosen duration',
                onSelected: (minutes) => controller.performance.activateTurbo(
                  Duration(minutes: minutes),
                ),
                itemBuilder: (_) => [
                  for (final minutes in [30, 60, 120])
                    PopupMenuItem(value: minutes,
                      child: Text('Turbo · $minutes minutes')),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bolt_outlined, size: 18),
                    SizedBox(width: 3),
                    Text('Turbo'),
                    Icon(Icons.arrow_drop_down, size: 18),
                  ]),
                ),
              ),
              FilterChip(
                label: const Text('Turbo when idle (AC)'),
                selected: controller.performance.autoTurboOnIdle,
                onSelected: controller.performance.setAutoTurboOnIdle,
              ),
              if (controller.running) ...[
                OutlinedButton.icon(
                  onPressed: controller.pauseOrResume,
                  icon: Icon(controller.paused ? Icons.play_arrow : Icons.pause),
                  label: Text(controller.paused ? 'Resume' : 'Pause'),
                ),
                TextButton(onPressed: controller.stop, child: const Text('Stop')),
              ],
              TextButton.icon(
                onPressed: controller.openHistory,
                icon: const Icon(Icons.history),
                label: const Text('History & storage'),
              ),
              if (controller.running || controller.result != null ||
                  controller.error != null)
                TextButton.icon(
                  onPressed: _busy ? null : _discardScan,
                  icon: const Icon(Icons.layers_clear_outlined),
                  label: const Text('Discard scan results'),
                ),
              DropdownButton<int?>(
                value: controller.year,
                underline: const SizedBox.shrink(),
                hint: const Text('All years'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All years')),
                  for (final year in {
                    ...?result?.years,
                    ...List<int>.generate(12, (i) => DateTime.now().year - i),
                  }.toList()..sort((a, b) => b.compareTo(a)))
                    DropdownMenuItem<int?>(value: year, child: Text('$year')),
                ],
                onChanged: controller.running || _busy ? null : (year) =>
                    controller.start(scopeYear: year,
                      people: controller.analyzingPeople),
              ),
              FilterChip(
                label: const Text('Analyze people (slower)'),
                selected: controller.analyzingPeople,
                onSelected: controller.running || _busy ? null : (enabled) =>
                    controller.start(scopeYear: controller.year, people: enabled),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(value: controller.autoScan,
                  onChanged: (enabled) => controller.setAutoScan(enabled ?? false)),
                const Text('Auto scan on launch'),
              ]),
            ],
          ),
          if (controller.running || controller.paused) ...[
            const SizedBox(height: 7),
            LinearProgressIndicator(value: controller.total == 0
                ? null : controller.fraction),
          ],
          Padding(padding: const EdgeInsets.only(top: 5), child: Text(
            controller.running
                ? '${controller.paused ? "PAUSED" : "RUNNING"} · '
                  '${controller.performance.activeMode.title} · '
                  '${controller.visited} / ${controller.total} · '
                  '${controller.paused ? "Scan paused" : _etaLabel(controller.eta)} '
                  '· ${controller.analyzedCount} analyzed'
                : controller.completed
                    ? 'Scan complete · ${controller.analyzedCount} analyzed '
                      '· ${result?.skipped ?? 0} unavailable'
                    : controller.visited > 0
                        ? 'Saved checkpoint: ${controller.visited} / '
                          '${controller.total} photos · available to resume'
                        : 'Scan stopped or not started.',
            style: const TextStyle(fontSize: 12),
          )),
          if (controller.running)
            Text(controller.paused
                ? 'Paused · safe to resume, stop, or quit'
                : 'Working: ${controller.scanPhase}',
              style: const TextStyle(fontSize: 12)),
          if (controller.resumeStatus != null)
            Text(controller.resumeStatus!,
              style: TextStyle(fontSize: 12,
                color: Theme.of(context).colorScheme.primary)),
          if (controller.error != null)
            Text(controller.error!, style: const TextStyle(color: Colors.red)),
          if (_message != null)
            Text(_message!, style: TextStyle(color:
              _message!.contains('failed') || _message!.contains('Unable')
                  ? Colors.red
                  : Theme.of(context).colorScheme.primary)),
          if (widget.category == CleanupCategory.accidental &&
              result?.smartAnalyzed != true)
            const Text('These suggestions require a new v0.3 smart scan. '
              'Older scan results did not analyze accidental screenshots.',
              style: TextStyle(fontSize: 12)),
          if (widget.category == CleanupCategory.noPeople &&
              (!controller.analyzingPeople ||
                  result?.peopleDetectionAvailable != true))
            const Text('Scenes & objects were not analyzed in this scan. '
              'Enable people/scene analysis in Scan settings and rescan. '
              'A zero count does not mean every photo contains people.',
              style: TextStyle(fontSize: 12)),
          if (allCount > 0) ...[
            const SizedBox(height: 5),
            Row(children: [
              Checkbox(value: selectedCount == allCount,
                onChanged: _busy ? null : (value) => _selectAll(value ?? false)),
              Text(_groupMode
                  ? 'Select all $allCount sets'
                  : 'Select all $allCount photos'),
              const SizedBox(width: 12),
              if (selectedCount > 0)
                TextButton(onPressed: _busy ? null : () => _selectAll(false),
                  child: const Text('Clear selection')),
            ]),
          ],
        ],
      )),
      const Divider(height: 1),
      Expanded(child: result == null
        ? Center(child: Text(controller.running
            ? 'Finding matches in the background…' : 'Start scanning to find photos.'))
        : groups.isEmpty
            ? Center(child: Text(controller.running
                ? 'No matches yet. New results will appear as scanning continues.'
                : 'No ${widget.category.label.toLowerCase()} in this scan.'))
            : Column(children: [
              if (_groupMode && _expanded != null)
                _expandedReview(groups),
              Expanded(child: LayoutBuilder(builder: (context, constraints) {
                final columns = (constraints.maxWidth / 210).floor().clamp(1, 9).toInt();
                return GridView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _groupMode ? groups.length : _visible.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: _groupMode ? 0.91 : 1.0,
                  ),
                  itemBuilder: (context, index) => _groupMode
                      ? _groupCard(groups[index])
                      : _photoCard(_visible[index]),
                );
              })),
            ])),
      if (selectedCount > 0)
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Wrap(spacing: 12, runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_groupMode ? '$selectedCount sets selected'
                  : '$selectedCount photos selected',
                style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(sizeSummaryLabel(summarizeSizes(selectedIds, _sizes)),
                style: const TextStyle(fontSize: 12)),
              if (!_groupMode)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () async {
                    await _keepIds([
                      for (final asset in _visible)
                        if (_selectedPhotos.contains(asset.id)) asset,
                    ]);
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Keep in Keepers'),
                ),
              FilledButton.icon(
                onPressed: canDelete ? _deleteSelected : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB42333)),
                icon: const Icon(Icons.delete_outline),
                label: Text(_groupMode
                    ? 'Keep $selectedCount · Delete ${selectedIds.length} extras'
                    : 'Delete ${selectedIds.length} selected'),
              ),
            ],
          ),
        )),
    ]);
  }

  Widget _groupCard(List<String> group) {
    final key = _key(group);
    final selected = _selectedGroups.contains(key);
    final representative = widget.controller.result?.photos[_keeper(group)];
    if (representative == null) return const SizedBox.shrink();
    return Column(children: [
      Expanded(child: InkWell(
        onTap: () => _toggleGroup(group),
        onDoubleTap: () => _preview(representative),
        child: ClipRRect(borderRadius: BorderRadius.circular(9), child: Stack(
          fit: StackFit.expand, children: [
            AssetEntityImage(representative, isOriginal: false,
              thumbnailSize: const ThumbnailSize(400, 400), fit: BoxFit.cover),
            if (selected)
              DecoratedBox(decoration: BoxDecoration(border: Border.all(
                color: const Color(0xFF007982), width: 4))),
            Positioned(top: 7, left: 7, child: DecoratedBox(
              decoration: BoxDecoration(color: const Color(0xE7003035),
                borderRadius: BorderRadius.circular(6)),
              child: Padding(padding: const EdgeInsets.symmetric(
                horizontal: 9, vertical: 5), child: Text('×${group.length}',
                style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold))),
            )),
            Positioned(top: 5, right: 5, child: Icon(selected
                ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? const Color(0xFF76FFE0) : Colors.white,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
            if (representative.isFavorite)
              const Positioned(left: 7, bottom: 7, child: Icon(
                Icons.favorite, color: Color(0xFFE94E70))),
          ],
        )),
      )),
      SizedBox(height: 35, child: TextButton.icon(
        onPressed: () => setState(() =>
            _expanded = _expanded == key ? null : key),
        icon: Icon(_expanded == key ? Icons.expand_less : Icons.expand_more,
          size: 18),
        label: const Text('Review copies'),
      )),
    ]);
  }

  Widget _expandedReview(List<List<String>> groups) {
    final matching = groups.where((group) => _key(group) == _expanded);
    if (matching.isEmpty) return const SizedBox.shrink();
    final group = matching.first;
    final chosen = _keeper(group);
    return Container(
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      height: 245,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(
            'Review ${group.length} copies · choose which to keep',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600))),
          TextButton.icon(
            onPressed: _busy ? null : () => _keepEntireGroup(group),
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('Keep all photos'),
          ),
          if (widget.category == CleanupCategory.similar)
            TextButton(
              onPressed: _busy ? null : () => _keepEntireGroup(group),
              child: const Text('Not similar'),
            ),
          IconButton(tooltip: 'Close review', icon: const Icon(Icons.close),
            onPressed: () => setState(() => _expanded = null)),
        ]),
        Expanded(child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final id in group)
            if (widget.controller.result?.photos[id]
                case final AssetEntity photo)
              SizedBox(width: 156, child: Padding(
                padding: const EdgeInsets.only(right: 9),
                child: Column(children: [
                  Expanded(child: InkWell(
                    onTap: () => _chooseKeeper(group, photo.id),
                    onDoubleTap: () => _preview(photo),
                    child: ClipRRect(borderRadius: BorderRadius.circular(8),
                      child: Stack(fit: StackFit.expand, children: [
                        AssetEntityImage(photo, isOriginal: false,
                          thumbnailSize: const ThumbnailSize(300, 300),
                          fit: BoxFit.cover),
                        if (chosen == photo.id)
                          DecoratedBox(decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF007982), width: 4))),
                      ])),
                  )),
                  SizedBox(height: 34, child: TextButton.icon(
                    onPressed: () => _chooseKeeper(group, photo.id),
                    icon: Icon(chosen == photo.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked, size: 17),
                    label: Text(chosen == photo.id ? 'Keep this' : 'Keep instead'),
                  )),
                ]),
              )),
        ])),
      ]),
    );
  }

  Widget _photoCard(AssetEntity photo) {
    final selected = _selectedPhotos.contains(photo.id);
    return InkWell(
      onTap: () => _togglePhoto(photo),
      onDoubleTap: () => _preview(photo),
      child: ClipRRect(borderRadius: BorderRadius.circular(8),
        child: Stack(fit: StackFit.expand, children: [
          AssetEntityImage(photo, isOriginal: false,
            thumbnailSize: const ThumbnailSize(400, 400), fit: BoxFit.cover),
          if (selected)
            DecoratedBox(decoration: BoxDecoration(border: Border.all(
              color: const Color(0xFF007982), width: 4))),
          Positioned(top: 5, right: 5, child: Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected ? const Color(0xFF76FFE0) : Colors.white,
            shadows: const [Shadow(blurRadius: 6, color: Colors.black87)],
          )),
          if (photo.isFavorite)
            const Positioned(bottom: 5, left: 5,
              child: Icon(Icons.favorite, color: Color(0xFFE94E70))),
          if (widget.category == CleanupCategory.accidental)
            Positioned(bottom: 0, left: 0, right: 0,
              child: Container(color: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.controller.result?.groups
                          .accidentalReasons[photo.id] ?? 'Review suggestion',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  TextButton(
                    onPressed: () {
                      widget.controller.dismissAccidental(photo.id);
                    },
                    child: const Text('Not accidental',
                      style: TextStyle(color: Colors.white)),
                  ),
                ]),
              ),
            ),
        ])),
    );
  }
}