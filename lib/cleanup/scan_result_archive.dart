import 'dart:convert';
import 'dart:io';

import 'photo_analysis.dart';

/// Durable, independent scan result sets. Contains references to Photos
/// assets and groupings, but never original photo data.
class ScanResultSnapshot {
  const ScanResultSnapshot({
    required this.id,
    required this.startedAt,
    required this.savedAt,
    required this.total,
    required this.analyzed,
    required this.groups,
    required this.bytes,
    this.peopleAnalyzed,
    this.smartAnalyzed = false,
  });

  final String id;
  final DateTime startedAt, savedAt;
  final int total, analyzed, bytes;
  final CleanupGroups groups;
  /// Null for older snapshots; unknown is not a confirmed zero.
  final bool? peopleAnalyzed;
  final bool smartAnalyzed;
  String get scenesCountLabel => peopleAnalyzed == true || noPeopleCount > 0
      ? '$noPeopleCount' : '—';

  int get exactCount => groups.exact.fold<int>(
      0, (value, group) => value + group.length - 1);
  int get similarCount => groups.similar.fold<int>(
      0, (value, group) => value + group.length - 1);
  int get blurryCount => groups.blurry.length;
  int get noPeopleCount => groups.noPeople.length;

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'id': id,
    'started': startedAt.toIso8601String(),
    'saved': savedAt.toIso8601String(),
    'total': total, 'analyzed': analyzed,
    'peopleAnalyzed': peopleAnalyzed,
    'smartAnalyzed': smartAnalyzed,
    'accidental': groups.accidentalScreenshots,
    'accidentalReasons': groups.accidentalReasons,
    'propertyTours': [
      for (final tour in groups.propertyTours) {
        'ids': tour.ids, 'start': tour.startedAtMs,
        'lat': tour.latitude, 'lon': tour.longitude,
      }
    ],
    'exact': groups.exact, 'similar': groups.similar,
    'blurry': groups.blurry, 'noPeople': groups.noPeople,
  };

  factory ScanResultSnapshot.fromJson(
      Map<String, dynamic> data, int bytes) {
    List<List<String>> lists(String key) => [
      for (final group in data[key] as List? ?? const [])
        List<String>.from(group as List),
    ];
    return ScanResultSnapshot(
      id: data['id'] as String,
      startedAt: DateTime.parse(data['started'] as String),
      savedAt: DateTime.parse(data['saved'] as String),
      total: (data['total'] as num).toInt(),
      analyzed: (data['analyzed'] as num).toInt(),
      bytes: bytes,
      peopleAnalyzed: data['peopleAnalyzed'] as bool?,
      smartAnalyzed: data['smartAnalyzed'] == true,
      groups: CleanupGroups(
        exact: lists('exact'), similar: lists('similar'),
        blurry: List<String>.from(data['blurry'] as List? ?? const []),
        noPeople: List<String>.from(data['noPeople'] as List? ?? const []),
        accidentalScreenshots: List<String>.from(
            data['accidental'] as List? ?? const []),
        accidentalReasons: Map<String, String>.from(
            data['accidentalReasons'] as Map? ?? const {}),
        propertyTours: [
          for (final item in data['propertyTours'] as List? ?? const [])
            PropertyTourSuggestion(
              ids: List<String>.from((item as Map)['ids'] as List),
              startedAtMs: ((item)['start'] as num).toInt(),
              latitude: (item['lat'] as num?)?.toDouble(),
              longitude: (item['lon'] as num?)?.toDouble(),
            ),
        ],
      ),
    );
  }
}

class ScanResultArchive {
  ScanResultArchive(Directory scanData)
      : folder = Directory('${scanData.path}/snapshots');
  final Directory folder;

  File _file(String id) {
    if (!RegExp(r'^scan-[0-9]+$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid scan ID');
    }
    return File('${folder.path}/$id.json');
  }

  Future<ScanResultSnapshot> save({
    required DateTime started,
    required int total,
    required int analyzed,
    required CleanupGroups groups,
    bool peopleAnalyzed = false,
    bool smartAnalyzed = false,
  }) async {
    await folder.create(recursive: true);
    final id = 'scan-${started.microsecondsSinceEpoch}';
    final provisional = ScanResultSnapshot(
      id: id, startedAt: started, savedAt: DateTime.now(),
      total: total, analyzed: analyzed, groups: groups, bytes: 0,
      peopleAnalyzed: peopleAnalyzed,
      smartAnalyzed: smartAnalyzed,
    );
    final target = _file(id);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(provisional.toJson()),
        flush: true);
    await temporary.rename(target.path);
    final size = await target.length();
    return ScanResultSnapshot(
      id: id, startedAt: provisional.startedAt,
      savedAt: provisional.savedAt, total: total,
      analyzed: analyzed, groups: groups, bytes: size,
      peopleAnalyzed: peopleAnalyzed,
      smartAnalyzed: smartAnalyzed,
    );
  }

  Future<ScanResultSnapshot?> read(String id) async {
    final file = _file(id);
    if (!await file.exists()) return null;
    return ScanResultSnapshot.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      await file.length(),
    );
  }

  Future<List<ScanResultSnapshot>> list() async {
    if (!await folder.exists()) return [];
    final result = <ScanResultSnapshot>[];
    await for (final item in folder.list()) {
      if (item is! File || !item.path.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await item.readAsString())
            as Map<String, dynamic>;
        if (data['schema'] != 1) continue;
        result.add(ScanResultSnapshot.fromJson(
            data, await item.length()));
      } catch (_) {
        // Never delete a damaged file automatically.
      }
    }
    result.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return result;
  }

  /// Only removes Siftidy's saved grouping file, never a Photos asset.
  Future<void> delete(String id) async {
    final file = _file(id);
    if (await file.exists()) await file.delete();
  }
}
