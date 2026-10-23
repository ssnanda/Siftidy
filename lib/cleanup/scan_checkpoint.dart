import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'photo_analysis.dart';

/// Journal entries are keyed by stable PhotoKit asset IDs.
class ScanRow {
  const ScanRow(this.id, this.year, this.width, this.height,
      {this.photo, this.skipped = false});
  final String id;
  final int year, width, height;
  final ScannedPhoto? photo;
  final bool skipped;
  Map<String, dynamic> toJson() => {
    'id': id, 'y': year, 'w': width, 'h': height, 'skip': skipped,
    if (photo != null) 'p': {
      'r': photo!.fingerprint.rows, 'c': photo!.fingerprint.averageRgb,
      's': photo!.fingerprint.sharpness,
      'l': base64Encode(photo!.fingerprint.spatialLuma),
      'hash': photo!.sha256, 'people': photo!.hasPeople,
      'ss': photo!.isScreenshot,
    }
  };
  factory ScanRow.fromJson(Map<String, dynamic> d) {
    final p = d['p'] as Map<String, dynamic>?;
    final id = d['id'] as String;
    ScannedPhoto? photo;
    if (p != null) {
      photo = ScannedPhoto(
        id: id,
        fingerprint: PhotoFingerprint(
          rows: List<int>.from(p['r'] as List),
          averageRgb: List<int>.from(p['c'] as List),
          sharpness: (p['s'] as num).toDouble(),
          spatialLuma: base64Decode(p['l'] as String),
        ),
        sha256: p['hash'] as String?,
        hasPeople: p['people'] as bool?,
        isScreenshot: p['ss'] == true,
      );
    }
    return ScanRow(id, (d['y'] as num).toInt(),
        (d['w'] as num).toInt(), (d['h'] as num).toInt(),
        photo: photo, skipped: d['skip'] == true);
  }
}

class ScanCheckpoint {
  ScanCheckpoint({required this.started, required this.year,
    required this.people, required this.total});
  final DateTime started;
  final int? year;
  final bool people;
  int total;
  bool complete = false;
  int elapsedMs = 0;
  double cpuSum = 0, peakRam = 0;
  int samples = 0;
  final Map<String, int> modes = {};
  final Map<String, ScanRow> rows = {};
  int get visited => rows.length;
  int get analyzed => rows.values.where((r) => r.photo != null).length;
  int get skipped => rows.values.where((r) => r.skipped).length;
  double get averageCpu => samples == 0 ? 0 : cpuSum / samples;
  double get perMinute => elapsedMs == 0 ? 0 : visited * 60000 / elapsedMs;
  Map<String, dynamic> toJson() => {
    'schema': 1, 'algorithm': 3, 'started': started.toIso8601String(),
    'year': year, 'people': people, 'total': total, 'complete': complete,
    'elapsedMs': elapsedMs, 'cpuSum': cpuSum, 'peakRam': peakRam,
    'samples': samples, 'modes': modes,
  };
  factory ScanCheckpoint.fromJson(Map<String, dynamic> d) {
    final item = ScanCheckpoint(
      started: DateTime.parse(d['started'] as String),
      year: (d['year'] as num?)?.toInt(),
      people: d['people'] == true, total: (d['total'] as num).toInt());
    item.complete = d['complete'] == true;
    item.elapsedMs = (d['elapsedMs'] as num?)?.toInt() ?? 0;
    item.cpuSum = (d['cpuSum'] as num?)?.toDouble() ?? 0;
    item.peakRam = (d['peakRam'] as num?)?.toDouble() ?? 0;
    item.samples = (d['samples'] as num?)?.toInt() ?? 0;
    item.modes.addAll(Map<String, int>.from(d['modes'] as Map? ?? {}));
    return item;
  }
}

class ScanStorageInfo {
  const ScanStorageInfo(this.folder, this.activeBytes, this.historyBytes,
      this.totalBytes, this.history);
  final String folder;
  final int activeBytes, historyBytes, totalBytes;
  final List<Map<String, dynamic>> history;
}

/// Active photo fingerprints are retained only on device. History stores
/// summaries, not copies of old photos or old full scan datasets.
class ScanCheckpointStore {
  ScanCheckpointStore(this.folder);
  final Directory folder;
  File get _state => File('${folder.path}/active-state.json');
  File get _journal => File('${folder.path}/active-rows.jsonl');
  File get _history => File('${folder.path}/history.json');
  ScanCheckpoint? current;
  Future<void> _pendingAppend = Future<void>.value();

  static Future<ScanCheckpointStore> open({Directory? folder}) async {
    final base = folder ?? Directory(
      '${(await getApplicationSupportDirectory()).path}/ScanData');
    await base.create(recursive: true);
    return ScanCheckpointStore(base);
  }

  Future<ScanCheckpoint?> load() async {
    if (!await _state.exists()) { return null; }
    try {
      final d = jsonDecode(await _state.readAsString()) as Map<String, dynamic>;
      if (d['schema'] != 1 || d['algorithm'] != 3) { return null; }
      final scan = ScanCheckpoint.fromJson(d);
      if (await _journal.exists()) {
        for (final line in await _journal.readAsLines()) {
          if (line.isEmpty) { continue; }
          try {
            final row = ScanRow.fromJson(
              jsonDecode(line) as Map<String, dynamic>);
            scan.rows[row.id] = row; // Updated hashes use last-write-wins.
          } catch (_) {
            // A partially written last line must not lose earlier records.
          }
        }
      }
      current = scan;
      return scan;
    } catch (_) {
      return null; // Corrupt/old schema: re-analyze rather than guess.
    }
  }

  Future<ScanCheckpoint> begin({required int? year,
      required bool people, required int total}) async {
    final old = current ?? await load();
    if (old != null && old.year == year && old.people == people) {
      // A new/deleted asset changes the library size, not the validity
      // of previously analyzed stable PhotoKit IDs.
      if (old.total != total) {
        old.total = total;
        old.complete = false;
        await _writeState(old);
      }
      return old;
    }
    if (old != null) { await finish('replaced'); }
    final fresh = ScanCheckpoint(started: DateTime.now(),
        year: year, people: people, total: total);
    await _journal.writeAsString('', flush: true);
    await _writeState(fresh);
    current = fresh;
    return fresh;
  }

  Future<void> append(List<ScanRow> entries, {required String mode,
      required int elapsedMs, required double cpu, required double ram}) {
    final write = _pendingAppend.then((_) => _appendNow(entries,
      mode: mode, elapsedMs: elapsedMs, cpu: cpu, ram: ram));
    _pendingAppend = write;
    return write;
  }

  Future<void> _appendNow(List<ScanRow> entries, {required String mode,
      required int elapsedMs, required double cpu, required double ram}) async {
    final scan = current;
    if (scan == null) { return; }
    if (entries.isNotEmpty) {
      final data = '${entries.map((e) => jsonEncode(e.toJson())).join('\n')}\n';
      await _journal.writeAsString(data, mode: FileMode.append, flush: true);
      for (final entry in entries) { scan.rows[entry.id] = entry; }
    }
    scan.elapsedMs += elapsedMs;
    scan.modes[mode] = (scan.modes[mode] ?? 0) + elapsedMs;
    scan.cpuSum += cpu;
    scan.samples++;
    if (ram > scan.peakRam) { scan.peakRam = ram; }
    await _writeState(scan);
  }

  Future<void> finish(String status) async {
    // Final reports and explicit discard wait for the in-flight journal
    // flush; they must never race its metadata update.
    await _pendingAppend;
    final scan = current;
    if (scan == null) { return; }
    if (status == 'complete') {
      scan.complete = true;
      await _writeState(scan);
    }
    final history = await readHistory();
    history.removeWhere((r) => r['start'] == scan.started.toIso8601String());
    history.insert(0, {
      'start': scan.started.toIso8601String(),
      'end': DateTime.now().toIso8601String(),
      'status': status, 'total': scan.total, 'visited': scan.visited,
      'analyzed': scan.analyzed, 'skipped': scan.skipped,
      'elapsedMs': scan.elapsedMs, 'averageCpu': scan.averageCpu,
      'peakRam': scan.peakRam, 'modes': Map.of(scan.modes),
    });
    await _atomic(_history, jsonEncode(history.take(30).toList()));
  }

  Future<void> discard() async {
    await _pendingAppend;
    if (current != null) { await finish('discarded'); }
    current = null;
    if (await _journal.exists()) { await _journal.delete(); }
    if (await _state.exists()) { await _state.delete(); }
  }

  /// Prune assets that no longer exist after a complete PhotoKit enumeration.
  /// Rewriting the journal also removes superseded hash-update records.
  Future<void> reconcile(Set<String> presentIds, int total) async {
    await _pendingAppend;
    final scan = current;
    if (scan == null) { return; }
    final missing = scan.rows.keys.where(
      (id) => !presentIds.contains(id)).toList();
    if (missing.isNotEmpty) {
      final kept = scan.rows.values.where(
        (row) => presentIds.contains(row.id)).toList();
      final data = kept.map((row) => jsonEncode(row.toJson())).join('\n');
      await _atomic(_journal, data.isEmpty ? '' : '$data\n');
      for (final id in missing) { scan.rows.remove(id); }
    }
    scan.total = total;
    await _writeState(scan);
  }

  Future<List<Map<String, dynamic>>> readHistory() async {
    try {
      if (!await _history.exists()) { return []; }
      return (jsonDecode(await _history.readAsString()) as List)
        .map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (_) { return []; }
  }

  Future<ScanStorageInfo> usage() async {
    int bytes(File file) => file.existsSync() ? file.lengthSync() : 0;
    final children = folder.listSync().whereType<File>();
    return ScanStorageInfo(
      folder.path, bytes(_state) + bytes(_journal), bytes(_history),
      children.fold<int>(0, (sum, file) => sum + bytes(file)),
      await readHistory());
  }

  Future<void> _writeState(ScanCheckpoint scan) async =>
      _atomic(_state, jsonEncode(scan.toJson()));

  Future<void> _atomic(File destination, String data) async {
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(data, flush: true);
    await temporary.rename(destination.path);
  }
}
