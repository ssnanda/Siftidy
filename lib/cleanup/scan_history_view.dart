import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'scan_checkpoint.dart';

/// Non-modal history and real storage measurements. Summary history does not
/// retain old photo datasets; the active journal can resume the latest scan.
class ScanHistoryView extends StatefulWidget {
  const ScanHistoryView({super.key, required this.store, required this.onBack});
  final ScanCheckpointStore? store;
  final VoidCallback onBack;
  @override
  State<ScanHistoryView> createState() => _ScanHistoryViewState();
}

class _ScanHistoryViewState extends State<ScanHistoryView> {
  late Future<ScanStorageInfo?> _info;
  @override
  void initState() {
    super.initState();
    _reload();
  }
  void _reload() { _info = widget.store?.usage() ?? Future.value(null); }
  String _size(int n) => n < 1024 ? '$n B' :
      n < 1048576 ? '${(n / 1024).toStringAsFixed(1)} KB' :
      '${(n / 1048576).toStringAsFixed(1)} MB';
  String _duration(int ms) {
    final d = Duration(milliseconds: ms);
    return d.inHours > 0 ? '${d.inHours}h ${d.inMinutes.remainder(60)}m'
        : '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        IconButton(tooltip: 'Back to cleanup', onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back)),
        const SizedBox(width: 10),
        const Text('Scan history & storage',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(tooltip: 'Refresh storage measurements',
          onPressed: () => setState(_reload),
          icon: const Icon(Icons.refresh)),
      ])),
      Expanded(child: FutureBuilder<ScanStorageInfo?>(
        future: _info,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: Text('Loading scan information…'));
          }
          final info = snapshot.data!;
          return ListView(padding: const EdgeInsets.all(24), children: [
            Text('Stored on this Mac only',
              style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(info.folder),
            const SizedBox(height: 12),
            Wrap(spacing: 12, children: [
              OutlinedButton.icon(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: info.folder)),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy folder path')),
              OutlinedButton.icon(
                onPressed: () async {
                  if (Platform.isMacOS) { await Process.run('open', [info.folder]); }
                },
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open in Finder')),
            ]),
            const SizedBox(height: 22),
            Wrap(spacing: 30, runSpacing: 10, children: [
              _stat('Current scan cache', _size(info.activeBytes)),
              _stat('Historical summaries', _size(info.historyBytes)),
              _stat('Total scan storage', _size(info.totalBytes)),
            ]),
            const SizedBox(height: 12),
            const Text('Active checkpoints store fingerprints and progress, '
              'not full-resolution photos. Historical scans keep summaries '
              'only. Discard scan results clears the active checkpoint '
              'without changing Apple Photos.',
              style: TextStyle(fontSize: 12)),
            const Divider(height: 32),
            Text('Scan history (${info.history.length})',
              style: Theme.of(context).textTheme.titleMedium),
            if (info.history.isEmpty) const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Text('No historical scans yet.')),
            for (final record in info.history)
              Card(child: Padding(padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${record['status']} · ${record['start']}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('${record['visited']} / ${record['total']} visited '
                      '· ${record['analyzed']} analyzed '
                      '· ${record['skipped']} unavailable'),
                    Text('Duration: ${_duration(
                      (record['elapsedMs'] as num).toInt())} '
                      '· ${((record['visited'] as num).toDouble() * 60000 /
                        ((record['elapsedMs'] as num).toDouble() == 0
                        ? 1 : (record['elapsedMs'] as num).toDouble()))
                        .toStringAsFixed(0)} photos/min'),
                    Text('Average CPU: ${(record['averageCpu'] as num)
                      .toStringAsFixed(1)}% · Peak RAM: '
                      '${(record['peakRam'] as num).toStringAsFixed(0)} MB'),
                    Text('Time by speed: ${_modes(record['modes'] as Map)}',
                      style: const TextStyle(fontSize: 12)),
                  ]),
              )),
          ]);
        },
      )),
    ]);
  }
  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(
        fontSize: 21, fontWeight: FontWeight.bold)),
      Text(label),
    ]);
  String _modes(Map source) => source.entries.map(
      (e) => '${e.key}: ${_duration((e.value as num).toInt())}'
    ).join(' · ');
}
