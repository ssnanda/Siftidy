import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../background/scan_runtime.dart';
import '../cleanup/cleanup_controller.dart';
import '../cleanup/cleanup_screen.dart';
import '../cleanup/scan_result_archive.dart';
import 'scan_dashboard.dart';

/// Dedicated scan operations page. The dashboard deliberately excludes
/// advanced tuning controls and destructive cache actions.
class ScanCenterHome extends StatelessWidget {
  const ScanCenterHome({
    super.key, required this.controller, required this.onBack,
    required this.onStart, required this.onSettings,
    required this.onPause, required this.onStop,
    required this.onReview, required this.onOpenSnapshot,
  });

  final CleanupController controller;
  final VoidCallback onBack, onStart, onSettings, onPause, onStop;
  final ValueChanged<CleanupCategory> onReview;
  final ValueChanged<ScanResultSnapshot> onOpenSnapshot;

  @override
  Widget build(BuildContext context) {
    final progress = (controller.fraction * 100).round();
    final current = controller.checkpointStore?.current;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        IconButton(onPressed: onBack, tooltip: 'Dashboard',
          icon: const Icon(Icons.arrow_back)),
        const SizedBox(width: 7),
        Expanded(child: Text('Scan Center', style:
            Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700))),
        OutlinedButton.icon(onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Scan settings')),
      ]),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(20), child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(controller.paused ? 'Paused'
                  : controller.running ? 'Scanning'
                  : controller.completed ? 'Completed' : 'Ready',
              style: Theme.of(context).textTheme.titleLarge)),
            Text('$progress%', style: Theme.of(context)
                .textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: controller.fraction,
            minHeight: 8, borderRadius: BorderRadius.circular(6)),
          const SizedBox(height: 11),
          Text('${controller.visited} / ${controller.total} scanned · '
              '${controller.analyzedCount} analyzed'),
          const SizedBox(height: 5),
          Text(controller.scanPhase),
          if (current != null) ...[
            const SizedBox(height: 6),
            Text('Elapsed: ${scanDuration(current.elapsedMs)} · '
                'Rate: ${current.perMinute.toStringAsFixed(0)} photos/min · '
                'Skipped: ${current.skipped}'),
          ],
          if (controller.error != null) ...[
            const SizedBox(height: 6),
            Text(controller.error!, style: TextStyle(
              color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 9, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: controller.running
                  ? (controller.paused ? onPause : null) : onStart,
              icon: Icon(controller.paused ? Icons.play_arrow
                  : Icons.play_circle_outline),
              label: Text(controller.paused ? 'Resume' : 'Scan now')),
            if (controller.running && !controller.paused)
              OutlinedButton.icon(onPressed: onPause,
                icon: const Icon(Icons.pause), label: const Text('Pause')),
            if (controller.running)
              TextButton(onPressed: onStop, child: const Text('Stop')),
            if (controller.completed)
              TextButton.icon(
                onPressed: () => onReview(CleanupCategory.exact),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Review results')),
          ]),
        ]),
      )),
      const SizedBox(height: 24),
      RecentScanRuns(controller: controller, limit: 30,
          onOpen: onOpenSnapshot, onViewAll: onBack),
      const SizedBox(height: 18),
      _StoragePanel(controller: controller),
    ]);
  }
}

class ScanSettingsHome extends StatelessWidget {
  const ScanSettingsHome({
    super.key, required this.controller, required this.onBack,
  });
  final CleanupController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final mode = controller.performance.activeMode;
    return ListView(padding: const EdgeInsets.all(26), children: [
      Row(children: [
        IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back),
          tooltip: 'Scan Center'),
        const SizedBox(width: 8),
        Text('Scan settings', style: Theme.of(context)
            .textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(18), child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Performance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          DropdownButtonFormField<ScanMode>(
            initialValue: mode,
            decoration: const InputDecoration(labelText: 'Scanning speed',
              border: OutlineInputBorder()),
            items: [
              for (final value in ScanMode.values)
                DropdownMenuItem(value: value, child: Text(value.title)),
            ],
            onChanged: (value) {
              if (value != null) { controller.performance.setBaseMode(value); }
            },
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 10, children: [
            for (final minutes in [30, 60, 120])
              OutlinedButton.icon(
                onPressed: () => controller.performance.activateTurbo(
                  Duration(minutes: minutes)),
                icon: const Icon(Icons.bolt_outlined),
                label: Text('Turbo ${minutes}m'),
              ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Turbo when idle on AC power'),
            subtitle: const Text(
              'Switch to Turbo after 10 minutes idle, return to normal '
              'speed when you use the Mac.'),
            value: controller.performance.autoTurboOnIdle,
            onChanged: controller.performance.setAutoTurboOnIdle,
          ),
        ]),
      )),
      const SizedBox(height: 14),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Startup & scope', style: Theme.of(context).textTheme.titleLarge),
          SwitchListTile(contentPadding: EdgeInsets.zero,
            title: const Text('Auto scan on launch'),
            value: controller.autoScan,
            onChanged: controller.setAutoScan),
          SwitchListTile(contentPadding: EdgeInsets.zero,
            title: const Text('Analyze people & scenes (slower)'),
            subtitle: const Text('Applied on the next scan; '
                'scene suggestions are review-only; enabling requires a new scan.'),
            value: controller.analyzingPeople,
            onChanged: controller.running ? null : (value) =>
              controller.setNextScanOptions(
                scopeYear: controller.year, people: value),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: controller.year ?? 0,
            decoration: const InputDecoration(
              labelText: 'Years to scan next time',
              border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: 0, child: Text('All years')),
              for (var year = DateTime.now().year;
                  year >= DateTime.now().year - 15; year--)
                DropdownMenuItem(value: year, child: Text('$year')),
            ],
            onChanged: controller.running ? null : (value) =>
                controller.setNextScanOptions(
                  scopeYear: value == 0 ? null : value,
                  people: controller.analyzingPeople),
          ),
          const SizedBox(height: 10),
          const Text('Scheduled overnight scans remain a separate v0.2 '
            'milestone. This page does not silently schedule a scan.',
            style: TextStyle(fontSize: 12)),
        ]),
      )),
      const SizedBox(height: 14),
      const Card(child: Padding(padding: EdgeInsets.all(16),
        child: Text('Closing the window or pressing ⌘Q keeps scanning in the '
          'menu bar. Quit Completely offers Pause & Quit to save a checkpoint. '
          'Deleting saved history never deletes Apple Photos.'))),
    ]);
  }
}

class _StoragePanel extends StatefulWidget {
  const _StoragePanel({required this.controller});
  final CleanupController controller;
  @override
  State<_StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends State<_StoragePanel> {
  @override
  Widget build(BuildContext context) {
    final store = widget.controller.checkpointStore;
    if (store == null) return const SizedBox.shrink();
    return FutureBuilder(
      future: store.usage(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(child: Padding(padding: EdgeInsets.all(12),
            child: Text('Measuring scan storage…')));
        }
        final usage = snapshot.data!;
        return Card(child: Padding(padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Local scan storage', style:
                Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(usage.folder),
            const SizedBox(height: 8),
            Text('Resumable checkpoint: '
              '${scanFileSize(usage.activeBytes)} · '
              'History: ${scanFileSize(usage.historyBytes)} · '
              'Total (including snapshots): ${scanFileSize(usage.totalBytes)}'),
            const SizedBox(height: 8),
            const Text('Stored locally. Saved result snapshots can be '
              'deleted individually above; originals are never included.'),
          ]),
        ));
      },
    );
  }
}

/// Historical results are inspectable without loading them into the
/// active scan or permitting operations against stale Photos references.
class SavedSnapshotView extends StatefulWidget {
  const SavedSnapshotView({
    super.key, required this.snapshot, required this.onBack,
  });
  final ScanResultSnapshot snapshot;
  final VoidCallback onBack;
  @override
  State<SavedSnapshotView> createState() => _SavedSnapshotViewState();
}

class _SavedSnapshotViewState extends State<SavedSnapshotView> {
  CleanupCategory _category = CleanupCategory.exact;

  List<List<String>> get _groups => switch (_category) {
    CleanupCategory.exact => widget.snapshot.groups.exact,
    CleanupCategory.similar => widget.snapshot.groups.similar,
    CleanupCategory.blurry => [
      for (final id in widget.snapshot.groups.blurry) [id],
    ],
    CleanupCategory.noPeople => [
      for (final id in widget.snapshot.groups.noPeople) [id],
    ],
  };

  @override
  Widget build(BuildContext context) {
    final item = widget.snapshot;
    return Column(children: [
      Padding(padding: const EdgeInsets.all(18), child: Row(children: [
        IconButton(onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back), tooltip: 'Back to Scan Center'),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saved scan results', style:
              Theme.of(context).textTheme.headlineSmall),
            Text('${scanTimestamp(item.startedAt)} · '
              '${item.analyzed} analyzed · ${scanFileSize(item.bytes)}'),
          ],
        )),
        const Chip(label: Text('Read only')),
      ])),
      SingleChildScrollView(scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(children: [
          for (final category in CleanupCategory.values)
            Padding(padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${category.label}  '
                  '${switch(category) {
                    CleanupCategory.exact => item.exactCount,
                    CleanupCategory.similar => item.similarCount,
                    CleanupCategory.blurry => item.blurryCount,
                    CleanupCategory.noPeople => item.scenesCountLabel,
                  }}'),
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
              )),
        ]),
      ),
      const SizedBox(height: 10),
      Expanded(child: _groups.isEmpty
        ? const Center(child: Text('No matches in this saved category.'))
        : ListView.builder(
            padding: const EdgeInsets.all(18),
            itemCount: _groups.length,
            itemBuilder: (context, index) {
              final ids = _groups[index];
              return Card(child: Padding(padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_category == CleanupCategory.exact ||
                      _category == CleanupCategory.similar
                        ? 'Group ${index + 1} · ${ids.length} photos'
                        : 'Photo ${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final id in ids.take(6))
                        _SnapshotThumbnail(assetId: id),
                      if (ids.length > 6)
                        SizedBox(width: 110, height: 105,
                          child: Center(child: Text('+${ids.length - 6} more'))),
                    ]),
                  ],
                ),
              ));
            },
          )),
      const Padding(padding: EdgeInsets.all(10),
        child: Text('Saved results are references to your Photos library. '
          'Review is read-only; deleting a scan record only deletes '
          'Siftidy’s result file.', style: TextStyle(fontSize: 11))),
    ]);
  }
}

class _SnapshotThumbnail extends StatefulWidget {
  const _SnapshotThumbnail({required this.assetId});
  final String assetId;
  @override
  State<_SnapshotThumbnail> createState() => _SnapshotThumbnailState();
}

class _SnapshotThumbnailState extends State<_SnapshotThumbnail> {
  late Future<AssetEntity?> _photo;
  @override
  void initState() {
    super.initState();
    _photo = AssetEntity.fromId(widget.assetId);
  }
  @override
  void didUpdateWidget(covariant _SnapshotThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId) {
      _photo = AssetEntity.fromId(widget.assetId);
    }
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<AssetEntity?>(
    future: _photo,
    builder: (context, snapshot) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 110, height: 105,
        child: snapshot.data == null
            ? Container(color: Theme.of(context).colorScheme.surfaceContainer,
                alignment: Alignment.center,
                child: Icon(snapshot.connectionState == ConnectionState.done
                    ? Icons.broken_image_outlined : Icons.photo_outlined))
            : AssetEntityImage(snapshot.data!,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize(220, 210),
                fit: BoxFit.cover)),
    ),
  );
}
