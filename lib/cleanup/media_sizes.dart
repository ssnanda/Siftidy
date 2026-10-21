import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// Optional original-file sizes, measured lazily only for user selections.
/// Photos/iCloud may have to fetch an original. Missing sizes stay unknown.
class MediaSizes extends ChangeNotifier {
  MediaSizes._();
  static final MediaSizes instance = MediaSizes._();

  final Map<String, int?> _bytes = {};
  final Set<String> _pending = {};
  final List<AssetEntity> _queue = [];
  bool _busy = false;

  int? bytesFor(String id) => _bytes[id];
  bool isPending(String id) => _pending.contains(id);

  Map<String, int> knownFor(Iterable<String> ids) => {
        for (final id in ids)
          if (_bytes[id] case final int size) id: size,
      };

  void inspect(Iterable<AssetEntity> assets) {
    for (final asset in assets) {
      if (_bytes.containsKey(asset.id) || !_pending.add(asset.id)) {
        continue;
      }
      _queue.add(asset);
    }
    if (!_busy && _queue.isNotEmpty) {
      unawaited(_drain());
    }
  }

  Future<void> _drain() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_queue.isNotEmpty) {
        final asset = _queue.removeAt(0);
        int? measured;
        try {
          final file = await asset.originFile;
          if (file != null) {
            measured = await file.length();
          }
        } catch (_) {
          // iCloud-only and inaccessible originals have no known byte size.
        }
        _bytes[asset.id] = measured;
        _pending.remove(asset.id);
        notifyListeners();
      }
    } finally {
      _busy = false;
    }
  }
}

class SizeSummary {
  const SizeSummary(this.knownBytes, this.unknown, this.pending);
  final int knownBytes;
  final int unknown;
  final int pending;
  bool get complete => unknown == 0;
}

SizeSummary summarizeSizes(Iterable<String> ids, MediaSizes sizes) {
  var bytes = 0;
  var unknown = 0;
  var pending = 0;
  for (final id in ids) {
    final value = sizes.bytesFor(id);
    if (value == null) {
      unknown++;
      if (sizes.isPending(id)) pending++;
    } else {
      bytes += value;
    }
  }
  return SizeSummary(bytes, unknown, pending);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KB';
  final mib = kib / 1024;
  if (mib < 1024) return '${mib.toStringAsFixed(1)} MB';
  return '${(mib / 1024).toStringAsFixed(2)} GB';
}

String sizeSummaryLabel(SizeSummary summary) {
  final known = formatBytes(summary.knownBytes);
  if (summary.complete) return known;
  if (summary.knownBytes == 0) {
    return summary.pending > 0
        ? 'Size being measured (${summary.pending} pending)'
        : 'Size unavailable (${summary.unknown} items)';
  }
  return '$known measured; ${summary.unknown} unknown';
}