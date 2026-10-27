import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_sizes.dart';

class DeletionEvent {
  const DeletionEvent({
    required this.deletedAt,
    required this.source,
    required this.count,
    required this.measuredBytes,
    required this.unknownSizeCount,
    this.items = const [],
  });

  final DateTime deletedAt;
  final String source;
  final int count;
  final int measuredBytes;
  final int unknownSizeCount;
  final List<DeletionItem> items;

  Map<String, Object> toJson() => {
        'deletedAt': deletedAt.toIso8601String(),
        'source': source,
        'count': count,
        'measuredBytes': measuredBytes,
        'unknownSizeCount': unknownSizeCount,
        'items': items.map((item) => item.toJson()).toList(),
      };

  factory DeletionEvent.fromJson(Map<String, dynamic> json) => DeletionEvent(
        deletedAt: DateTime.parse(json['deletedAt'] as String),
        source: json['source'] as String? ?? 'Siftidy',
        count: (json['count'] as num).toInt(),
        measuredBytes: (json['measuredBytes'] as num?)?.toInt() ?? 0,
        unknownSizeCount: (json['unknownSizeCount'] as num?)?.toInt() ?? 0,
        items: [
          for (final item in json['items'] as List<dynamic>? ?? const [])
            DeletionItem.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
      );
}

class DeletionItem {
  const DeletionItem({
    required this.id,
    required this.name,
    required this.capturedAt,
    required this.mediaType,
    this.bytes,
  });

  final String id;
  final String name;
  final DateTime? capturedAt;
  final String mediaType;
  final int? bytes;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'capturedAt': capturedAt?.toIso8601String(),
        'mediaType': mediaType,
        'bytes': bytes,
      };

  factory DeletionItem.fromJson(Map<String, dynamic> json) => DeletionItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Untitled item',
        capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? ''),
        mediaType: json['mediaType'] as String? ?? 'Media',
        bytes: (json['bytes'] as num?)?.toInt(),
      );
}

/// Records only deletions successfully requested through Siftidy.
/// Not a live view of Apple Photos' protected Recently Deleted album.
class DeletionStats extends ChangeNotifier {
  DeletionStats._();
  static final DeletionStats instance = DeletionStats._();

  static const _countKey = 'siftidy_deleted_count_v02';
  static const _measuredKey = 'siftidy_deleted_bytes_v02';
  static const _unknownKey = 'siftidy_deleted_unknown_v02';
  static const _lastKey = 'siftidy_deleted_last_v02';
  static const _eventsKey = 'siftidy_deleted_events_v03';

  int count = 0;
  int measuredBytes = 0;
  int unknownSizeCount = 0;
  DateTime? lastDeletion;
  final List<DeletionEvent> events = [];
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
    final encodedEvents = prefs.getString(_eventsKey);
    if (encodedEvents != null) {
      try {
        final decoded = jsonDecode(encodedEvents) as List<dynamic>;
        events.addAll(decoded.map((item) =>
            DeletionEvent.fromJson(Map<String, dynamic>.from(item as Map))));
      } catch (_) {
        // Keep the lifetime totals if a future/invalid event payload is found.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> record(Iterable<String> deleted, Map<String, int> knownSizes,
      {String source = 'Library',
      Iterable<DeletionItem> itemDetails = const []}) async {
    final ids = deleted.toSet();
    if (ids.isEmpty) return;
    await load();
    if (events.isEmpty && count > 0 && lastDeletion != null) {
      events.add(DeletionEvent(
        deletedAt: lastDeletion!,
        source: 'Earlier Siftidy deletions',
        count: count,
        measuredBytes: measuredBytes,
        unknownSizeCount: unknownSizeCount,
      ));
    }
    var eventBytes = 0;
    var eventUnknown = 0;
    count += ids.length;
    for (final id in ids) {
      final bytes = knownSizes[id];
      if (bytes == null) {
        unknownSizeCount++;
        eventUnknown++;
      } else {
        measuredBytes += bytes;
        eventBytes += bytes;
      }
    }
    lastDeletion = DateTime.now();
    final detailsById = {for (final item in itemDetails) item.id: item};
    events.insert(
        0,
        DeletionEvent(
          deletedAt: lastDeletion!,
          source: source,
          count: ids.length,
          measuredBytes: eventBytes,
          unknownSizeCount: eventUnknown,
          items: [
            for (final id in ids)
              detailsById[id] ??
                  DeletionItem(
                    id: id,
                    name: 'Untitled item',
                    capturedAt: null,
                    mediaType: 'Media',
                    bytes: knownSizes[id],
                  ),
          ],
        ));
    if (events.length > 100) events.removeRange(100, events.length);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_countKey, count);
    await prefs.setInt(_measuredKey, measuredBytes);
    await prefs.setInt(_unknownKey, unknownSizeCount);
    await prefs.setString(_lastKey, lastDeletion!.toIso8601String());
    await prefs.setString(
        _eventsKey, jsonEncode(events.map((event) => event.toJson()).toList()));
  }

  List<DeletionEvent> get visibleEvents {
    if (events.isNotEmpty || count == 0 || lastDeletion == null) return events;
    return [
      DeletionEvent(
        deletedAt: lastDeletion!,
        source: 'Earlier Siftidy deletions',
        count: count,
        measuredBytes: measuredBytes,
        unknownSizeCount: unknownSizeCount,
      )
    ];
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
      Text('Deletion activity',
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text(
          'Siftidy records successful deletion requests. Apple Photos manages Recently Deleted; these figures are not a live count of that protected album.'),
      const SizedBox(height: 24),
      Wrap(spacing: 30, runSpacing: 20, children: [
        _stat('Deleted using Siftidy', '${stats.count} photos or videos'),
        _stat('Measured original sizes', formatBytes(stats.measuredBytes)),
        _stat('Size unavailable', '${stats.unknownSizeCount} items'),
      ]),
      const SizedBox(height: 18),
      if (stats.visibleEvents.isNotEmpty) ...[
        Text('Deletion history',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const _DeletionHistoryHeader(),
        for (final event in stats.visibleEvents) _DeletionHistoryRow(event),
        const SizedBox(height: 18),
      ],
      const Text(
          'Measured size represents items removed from the Photos library through Siftidy, not confirmed freed disk space. Items may remain in Recently Deleted for up to 30 days or be restored, and iCloud can affect local storage usage.'),
      const SizedBox(height: 24),
      Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              if (Platform.isMacOS) {
                await Process.run('/usr/bin/open', ['-a', 'Photos']);
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Photos · Recently Deleted'),
          )),
      const SizedBox(height: 8),
      const Text(
          'In Photos, open Recently Deleted to see its actual current item count and permanently delete its contents if desired. Siftidy cannot empty that album on your behalf.'),
    ]);
  }

  Widget _stat(String title, String value) => SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(title, style: const TextStyle(fontSize: 12)),
        ],
      ));
}

class _DeletionHistoryHeader extends StatelessWidget {
  const _DeletionHistoryHeader();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: _DeletionHistoryCells(
            date: 'Date', source: 'Category', items: 'Items', size: 'Size'),
      );
}

class _DeletionHistoryRow extends StatelessWidget {
  const _DeletionHistoryRow(this.event);
  final DeletionEvent event;

  @override
  Widget build(BuildContext context) {
    final date = event.deletedAt.toLocal();
    final dateText = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    final size = event.measuredBytes == 0
        ? 'Unavailable'
        : formatBytes(event.measuredBytes);
    final sizeText = event.unknownSizeCount == 0
        ? size
        : '$size · ${event.unknownSizeCount} unknown';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        title: _DeletionHistoryCells(
          date: dateText,
          source: event.source,
          items: '${event.count}',
          size: sizeText,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: event.items.isEmpty
            ? const [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Individual file details were not recorded.'),
                )
              ]
            : [
                const Divider(),
                const _DeletionItemHeader(),
                for (final item in event.items) _DeletionItemRow(item),
              ],
      ),
    );
  }
}

class _DeletionItemHeader extends StatelessWidget {
  const _DeletionItemHeader();

  @override
  Widget build(BuildContext context) => const _DeletionItemCells(
      name: 'Name', captured: 'Captured', type: 'Type', size: 'Size');
}

class _DeletionItemRow extends StatelessWidget {
  const _DeletionItemRow(this.item);
  final DeletionItem item;

  @override
  Widget build(BuildContext context) {
    final captured = item.capturedAt?.toLocal();
    final capturedText = captured == null
        ? 'Unknown'
        : '${captured.year}-${captured.month.toString().padLeft(2, '0')}-'
            '${captured.day.toString().padLeft(2, '0')} '
            '${captured.hour.toString().padLeft(2, '0')}:'
            '${captured.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: _DeletionItemCells(
        name: item.name,
        captured: capturedText,
        type: item.mediaType,
        size: item.bytes == null ? 'Unknown' : formatBytes(item.bytes!),
      ),
    );
  }
}

class _DeletionItemCells extends StatelessWidget {
  const _DeletionItemCells({
    required this.name,
    required this.captured,
    required this.type,
    required this.size,
  });
  final String name;
  final String captured;
  final String type;
  final String size;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            flex: 4,
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        SizedBox(width: 150, child: Text(captured)),
        SizedBox(width: 70, child: Text(type)),
        SizedBox(width: 90, child: Text(size)),
      ]);
}

class _DeletionHistoryCells extends StatelessWidget {
  const _DeletionHistoryCells({
    required this.date,
    required this.source,
    required this.items,
    required this.size,
  });
  final String date;
  final String source;
  final String items;
  final String size;

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(width: 150, child: Text(date)),
        Expanded(flex: 3, child: Text(source)),
        SizedBox(width: 70, child: Text(items)),
        Expanded(flex: 2, child: Text(size)),
      ]);
}
