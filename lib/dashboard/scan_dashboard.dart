import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cleanup/cleanup_controller.dart';
import '../background/scan_runtime.dart';
import '../cleanup/cleanup_screen.dart';
import '../cleanup/scan_result_archive.dart';

String scanDuration(int milliseconds) {
  final elapsed = Duration(milliseconds: milliseconds);
  if (elapsed.inHours > 0) {
    return '${elapsed.inHours}h ${elapsed.inMinutes.remainder(60)}m';
  }
  return '${elapsed.inMinutes}m ${elapsed.inSeconds.remainder(60)}s';
}

String scanTimestamp(DateTime date) {
  final local = date.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String scanFileSize(int value) {
  if (value < 1024) return '$value B';
  if (value < 1048576) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '${(value / 1048576).toStringAsFixed(1)} MB';
}

class DashboardHome extends StatelessWidget {
  const DashboardHome({
    super.key,
    required this.controller,
    required this.onScan,
    required this.onPause,
    required this.onStop,
    required this.onReview,
    required this.onToggleHistory,
    this.showAllHistory = false,
    required this.onSettings,
    required this.onOpenSnapshot,
  });

  final CleanupController controller;
  final VoidCallback onScan, onPause, onStop, onToggleHistory, onSettings;
  final bool showAllHistory;
  final ValueChanged<CleanupCategory> onReview;
  final ValueChanged<ScanResultSnapshot> onOpenSnapshot;

  @override
  Widget build(BuildContext context) {
    final finalizing = controller.running && !controller.paused &&
        controller.total > 0 && controller.visited >= controller.total;
    final status = controller.paused ? 'Paused'
        : finalizing ? 'Finalizing results'
        : controller.running ? 'Scanning'
        : controller.starting ? 'Preparing scan'
        : controller.completed ? 'Completed'
        : controller.visited > 0 ? 'Ready to resume' : 'Ready to scan';
    final completePercent = (controller.fraction * 100).round();
    final color = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(26), children: [
      Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dashboard', style: Theme.of(context)
                .textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Your library, scan results, and next steps.'),
          ],
        )),
      ]),
      const SizedBox(height: 20),
      Card(clipBehavior: Clip.antiAlias, child: Padding(
        padding: const EdgeInsets.all(22), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(controller.paused ? Icons.pause_circle_outline
                  : controller.running ? Icons.radar
                  : controller.completed ? Icons.check_circle_outline
                  : Icons.auto_awesome_outlined,
                  color: color.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Text(status, style: Theme.of(context)
                  .textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
              Text('$completePercent%', style: Theme.of(context)
                  .textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: controller.total == 0 ? 0
                : controller.fraction, minHeight: 7, borderRadius:
                BorderRadius.circular(8)),
            const SizedBox(height: 12),
            Wrap(spacing: 18, runSpacing: 6, children: [
              Text('${controller.visited} / ${controller.total} photos scanned'),
              Text('${controller.analyzedCount} analyzed'),
              Text('Speed: ${controller.performance.activeMode.title}'),
              if (controller.checkpointStore?.current != null)
                Text('Elapsed: ${scanDuration(
                  controller.checkpointStore!.current!.elapsedMs)}'),
            ]),
            if (controller.running || controller.starting) ...[
              const SizedBox(height: 8),
              Text(controller.paused ? 'Paused — saved work is retained'
                  : finalizing
                      ? 'All photos indexed. Organizing the results before '
                          'the scan is marked complete.'
                      : controller.scanPhase),
            ],
            if (controller.error != null) ...[
              const SizedBox(height: 8),
              Text(controller.error!, style: TextStyle(color: color.error)),
            ],
            const SizedBox(height: 18),
            Wrap(spacing: 10, runSpacing: 10, children: [
              if (!controller.running)
                FilledButton.icon(
                  onPressed: controller.starting ? null : onScan,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(controller.starting ? 'Preparing…'
                      : controller.completed ? 'Scan again'
                      : controller.visited > 0 ? 'Resume scan'
                      : 'Scan now')),
              if (controller.running)
                OutlinedButton.icon(
                  onPressed: onPause,
                  icon: Icon(controller.paused
                      ? Icons.play_arrow : Icons.pause),
                  label: Text(controller.paused ? 'Resume' : 'Pause')),
              if (controller.running)
                TextButton(onPressed: onStop, child: const Text('Stop')),
              const SizedBox(width: 8),
              const Text('Speed:'),
              DropdownButton<ScanMode>(
                value: controller.performance.activeMode,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final mode in ScanMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.title)),
                ],
                onChanged: (mode) {
                  if (mode != null) {
                    controller.performance.setBaseMode(mode);
                  }
                },
              ),
              PopupMenuButton<int>(
                tooltip: 'Choose timed Turbo duration',
                onSelected: (minutes) => controller.performance.activateTurbo(
                  Duration(minutes: minutes)),
                itemBuilder: (_) => [
                  for (final minutes in [30, 60, 120])
                    PopupMenuItem(value: minutes,
                      child: Text('Turbo for $minutes minutes')),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bolt_outlined, size: 18),
                    Text('Timed Turbo'),
                    Icon(Icons.arrow_drop_down, size: 18),
                  ]),
                ),
              ),
              FilterChip(
                label: const Text('Turbo on idle (AC)'),
                selected: controller.performance.autoTurboOnIdle,
                onSelected: controller.performance.setAutoTurboOnIdle),
            ]),
          ],
        ),
      )),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: Text('Review your results', style:
          Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700))),
        TextButton.icon(onPressed: onToggleHistory,
          icon: const Icon(Icons.history, size: 18),
          label: Text(showAllHistory ? 'Show recent' : 'History & storage')),
      ]),
      const SizedBox(height: 9),
      LayoutBuilder(builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 660;
        final tileWidth = twoColumns
            ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth;
        return Wrap(spacing: 14, runSpacing: 14, children: [
          _resultTile(context, tileWidth, CleanupCategory.exact,
            '${controller.exactCount}', 'Possible identical copies · review safely'),
          _resultTile(context, tileWidth, CleanupCategory.similar,
            '${controller.similarCount}', 'Visually related photos to compare'),
          _resultTile(context, tileWidth, CleanupCategory.blurry,
            '${controller.blurry.length}', 'Review images that may be out of focus'),
          _resultTile(context, tileWidth, CleanupCategory.noPeople,
            controller.result?.peopleDetectionAvailable == true &&
                    controller.analyzingPeople
                ? '${controller.noPeople.length}' : '—',
            controller.result?.peopleDetectionAvailable == true &&
                    controller.analyzingPeople
                ? 'Photos without a detected person · review only'
                : 'Not analyzed · enable people/scene analysis in settings'),
          _resultTile(context, tileWidth, CleanupCategory.accidental,
            controller.result?.smartAnalyzed == true
                ? '${controller.accidentalScreenshots.length}' : '—',
            controller.result?.smartAnalyzed == true
                ? 'Lock screens, empty or repeated captures · review'
                : 'Run the v0.3 smart scan to analyze screenshots'),
          _resultTile(context, tileWidth, CleanupCategory.propertyTours,
            controller.result?.smartAnalyzed == true
                ? '${controller.propertyTours.length}' : '—',
            controller.result?.smartAnalyzed == true
                ? 'Home photo sequences · group by location or address'
                : 'Run the v0.3 smart scan for property sequences'),
        ]);
      }),
      if (controller.running) const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text('Results are provisional while a scan is still running.',
          style: TextStyle(fontSize: 12)),
      ),
      const SizedBox(height: 28),
      RecentScanRuns(controller: controller,
        limit: showAllHistory ? 30 : 5,
        onOpen: onOpenSnapshot, onViewAll: onToggleHistory),
      if (showAllHistory) ...[
        const SizedBox(height: 18),
        DashboardScanStorage(controller: controller),
      ],
    ]);
  }

  Widget _resultTile(BuildContext context, double width,
      CleanupCategory category, String count, String description) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(width: width, child: Card(
      margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onReview(category),
        child: Padding(padding: const EdgeInsets.all(19), child: Row(
          crossAxisAlignment: CrossAxisAlignment.center, children: [
            CircleAvatar(backgroundColor: colors.primaryContainer,
              radius: 23, child: Icon(category.icon, color: colors.primary)),
            const SizedBox(width: 15),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.label, style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(description, maxLines: 2, style:
                    const TextStyle(fontSize: 12)),
              ],
            )),
            const SizedBox(width: 10),
            Column(children: [
              Text(count, style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
              const Text('Review', style: TextStyle(fontSize: 12)),
            ]),
          ],
        )),
      ),
    ));
  }
}

/// Last five actual scan sessions, including stopped/failed summaries.
/// Completed sessions additionally have independent, reviewable snapshots.
class RecentScanRuns extends StatefulWidget {
  const RecentScanRuns({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onViewAll,
    this.limit = 5,
  });

  final CleanupController controller;
  final ValueChanged<ScanResultSnapshot> onOpen;
  final VoidCallback onViewAll;
  final int limit;

  @override
  State<RecentScanRuns> createState() => _RecentScanRunsState();
}

class _RecentScanRunsState extends State<RecentScanRuns> {
  late Future<_HistoryData> _data;
  bool _wasCompleted = false;
  bool _wasRunning = false;

  @override
  void initState() {
    super.initState();
    _wasCompleted = widget.controller.completed;
    _wasRunning = widget.controller.running;
    _refresh();
  }

  void _refresh() {
    _data = _load();
  }

  Future<_HistoryData> _load() async {
    final archive = widget.controller.archive;
    final history = await widget.controller.checkpointStore?.readHistory()
        ?? <Map<String, dynamic>>[];
    final snapshots = await archive?.list() ?? <ScanResultSnapshot>[];
    return _HistoryData(history, snapshots);
  }

  @override
  void didUpdateWidget(covariant RecentScanRuns oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A stopped or interrupted scan has a new history entry even when it
    // never reaches Completed. Refresh after any running -> idle transition.
    if ((_wasRunning && !widget.controller.running) ||
        (widget.controller.completed && !_wasCompleted)) {
      _refresh();
    }
    _wasRunning = widget.controller.running;
    _wasCompleted = widget.controller.completed;
  }

  Future<void> _delete(Map<String, dynamic> record,
      ScanResultSnapshot? snapshot) async {
    final confirmed = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved scan record?'),
        content: const Text('This removes only Siftidy scan history and its '
          'saved result snapshot. Apple Photos and the active resumable '
          'checkpoint are not deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete record')),
        ],
      ));
    if (confirmed != true) return;
    if (snapshot != null) {
      await widget.controller.archive?.delete(snapshot.id);
    }
    await widget.controller.checkpointStore
        ?.deleteHistoryEntry(record['start'] as String);
    if (mounted) setState(_refresh);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Recent scans',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700))),
        IconButton(tooltip: 'Refresh history',
          onPressed: () => setState(_refresh),
          icon: const Icon(Icons.refresh)),
        TextButton(onPressed: widget.onViewAll,
          child: Text(widget.limit > 5 ? 'Show less' : 'View all')),
      ]),
      const SizedBox(height: 8),
      FutureBuilder<_HistoryData>(future: _data,
        builder: (context, state) {
          if (!state.hasData) {
            return const Padding(padding: EdgeInsets.all(16),
              child: Text('Loading local scan history…'));
          }
          final history = state.data!.records.take(widget.limit).toList();
          if (history.isEmpty) {
            return const Card(child: Padding(padding: EdgeInsets.all(18),
              child: Text('No completed or interrupted scans recorded yet.')));
          }
          return Column(children: [
            for (final record in history)
              Builder(builder: (context) {
                final started = record['start'] as String? ?? '';
                ScanResultSnapshot? snapshot;
                for (final entry in state.data!.snapshots) {
                  if (entry.startedAt.toIso8601String() == started) {
                    snapshot = entry;
                    break;
                  }
                }
                final visited = record['visited'] ?? 0;
                final total = record['total'] ?? 0;
                final status = record['status'] ?? 'Unknown';
                return Card(margin: const EdgeInsets.only(bottom: 9),
                  child: Padding(padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(snapshot == null
                          ? Icons.history_outlined
                          : Icons.inventory_2_outlined, size: 22),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(started.isEmpty ? 'Scan'
                              : scanTimestamp(DateTime.parse(started)),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('$status · $visited / $total scanned · '
                            '${scanDuration(
                              (record['elapsedMs'] as num?)?.toInt() ?? 0)}'),
                          if (snapshot != null)
                            Text('Exact ${snapshot.exactCount} · '
                              'Similar ${snapshot.similarCount} · '
                              'Blurry ${snapshot.blurryCount} · '
                              'Scenes ${snapshot.scenesCountLabel} · '
                              'Screenshots ${snapshot.smartAnalyzed ? snapshot.groups.accidentalScreenshots.length.toString() : "—"} · '
                              'Tours ${snapshot.smartAnalyzed ? snapshot.groups.propertyTours.length.toString() : "—"} · '
                              '${scanFileSize(snapshot.bytes)}',
                              style: const TextStyle(fontSize: 12)),
                          if (snapshot == null)
                            const Text('Summary only · no saved result snapshot',
                              style: TextStyle(fontSize: 12)),
                        ],
                      )),
                      if (snapshot != null)
                        TextButton(
                          onPressed: () => widget.onOpen(snapshot!),
                          child: const Text('Open results')),
                      IconButton(
                        tooltip: 'Delete scan history and stored results',
                        onPressed: () => _delete(record, snapshot),
                        icon: const Icon(Icons.delete_outline)),
                    ]),
                  ),
                );
              }),
          ]);
        },
      ),
    ]);
  }
}

class _HistoryData {
  const _HistoryData(this.records, this.snapshots);
  final List<Map<String, dynamic>> records;
  final List<ScanResultSnapshot> snapshots;
}

class DashboardScanStorage extends StatelessWidget {
  const DashboardScanStorage({super.key, required this.controller});
  final CleanupController controller;

  @override
  Widget build(BuildContext context) {
    final store = controller.checkpointStore;
    if (store == null) return const SizedBox.shrink();
    return FutureBuilder(
      future: store.usage(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(child: Padding(
            padding: EdgeInsets.all(16), child: Text('Measuring storage…')));
        }
        final usage = snapshot.data!;
        return Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Scan history & storage',
                style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Local scan files only. Photos are never included.'),
              const SizedBox(height: 8),
              SelectableText(usage.folder),
              const SizedBox(height: 8),
              Text('Active checkpoint: ${scanFileSize(usage.activeBytes)}'
                  ' · Scan history: ${scanFileSize(usage.historyBytes)}'
                  ' · Total with snapshots: ${scanFileSize(usage.totalBytes)}'),
              const SizedBox(height: 8),
              Wrap(spacing: 12, children: [
                TextButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: usage.folder)),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy path'),
                ),
                if (Platform.isMacOS) TextButton.icon(
                  onPressed: () => Process.run('open', [usage.folder]),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Open in Finder'),
                ),
              ]),
            ],
          ),
        ));
      },
    );
  }
}
