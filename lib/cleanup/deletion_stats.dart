import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_sizes.dart';

/// Records only deletions successfully requested through Siftidy.
/// Not a live view of Apple Photos' protected Recently Deleted album.
class DeletionStats extends ChangeNotifier {
  DeletionStats._();
  static final DeletionStats instance = DeletionStats._();

  static const _countKey = 'siftidy_deleted_count_v02';
  static const _measuredKey = 'siftidy_deleted_bytes_v02';
  static const _unknownKey = 'siftidy_deleted_unknown_v02';
  static const _lastKey = 'siftidy_deleted_last_v02';

  int count = 0;
  int measuredBytes = 0;
  int unknownSizeCount = 0;
  DateTime? lastDeletion;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    if (_loaded) return;
    count = prefs.getInt(_countKey) ?? 0;
    measuredBytes = prefs.getInt(_measuredKey) ?? 0;
    unknownSizeCount = prefs.getInt(_unknownKey) ?? 0;
    final last = prefs.getString(_lastKey);
    lastDeletion = last == null ? null : DateTime.tryParse(last);
    _loaded = true;
    notifyListeners();
  }

  Future<void> record(Iterable<String> deleted, Map<String, int> knownSizes) async {
    final ids = deleted.toSet();
    if (ids.isEmpty) return;
    await load();
    count += ids.length;
    for (final id in ids) {
      final bytes = knownSizes[id];
      if (bytes == null) {
        unknownSizeCount++;
      } else {
        measuredBytes += bytes;
      }
    }
    lastDeletion = DateTime.now();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_countKey, count);
    await prefs.setInt(_measuredKey, measuredBytes);
    await prefs.setInt(_unknownKey, unknownSizeCount);
    await prefs.setString(_lastKey, lastDeletion!.toIso8601String());
  }
}

class DeletionActivityView extends StatefulWidget {
  const DeletionActivityView({super.key});

  @override
  State<DeletionActivityView> createState() => _DeletionActivityViewState();
}

class _DeletionActivityViewState extends State<DeletionActivityView> {
  @override
  void initState() {
    super.initState();
    DeletionStats.instance.addListener(_refresh);
    DeletionStats.instance.load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    DeletionStats.instance.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = DeletionStats.instance;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Deletion activity', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Siftidy records successful deletion requests. Apple Photos manages Recently Deleted; these figures are not a live count of that protected album.'),
      const SizedBox(height: 24),
      Wrap(spacing: 30, runSpacing: 20, children: [
        _stat('Deleted using Siftidy', '${stats.count} photos or videos'),
        _stat('Measured original sizes', formatBytes(stats.measuredBytes)),
        _stat('Size unavailable', '${stats.unknownSizeCount} items'),
      ]),
      const SizedBox(height: 18),
      const Text('Measured size represents items removed from the Photos library through Siftidy, not confirmed freed disk space. Items may remain in Recently Deleted for up to 30 days or be restored, and iCloud can affect local storage usage.'),
      const SizedBox(height: 24),
      Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
        onPressed: () async {
          if (Platform.isMacOS) {
            await Process.run('/usr/bin/open', ['-a', 'Photos']);
          }
        },
        icon: const Icon(Icons.open_in_new),
        label: const Text('Open Photos · Recently Deleted'),
      )),
      const SizedBox(height: 8),
      const Text('In Photos, open Recently Deleted to see its actual current item count and permanently delete its contents if desired. Siftidy cannot empty that album on your behalf.'),
    ]);
  }

  Widget _stat(String title, String value) => SizedBox(width: 240, child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      Text(title, style: const TextStyle(fontSize: 12)),
    ],
  ));
}