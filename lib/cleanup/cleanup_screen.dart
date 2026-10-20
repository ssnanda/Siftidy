import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../library/library_repository.dart';
import 'cleanup_scanner.dart';

/// Review-first cleanup. No photo is deleted or moved by scanning.
class CleanupScreen extends StatefulWidget {
  const CleanupScreen({super.key});

  @override
  State<CleanupScreen> createState() => _CleanupScreenState();
}

enum _Suggestion { exact, similar, blurry, noPeople }

extension on _Suggestion {
  String get label => switch (this) {
    _Suggestion.exact => 'Exact duplicates',
    _Suggestion.similar => 'Similar photos',
    _Suggestion.blurry => 'Possibly blurry',
    _Suggestion.noPeople => 'No people detected',
  };
}

class _CleanupScreenState extends State<CleanupScreen> {
  final _repository = LibraryRepository();
  final _scanner = CleanupScanner();
  final _selected = <String>{};
  final _excluded = <String>{};
  CleanupScanResult? _result;
  _Suggestion _view = _Suggestion.exact;
  bool _scanning = false;
  bool _working = false;
  bool _cancelled = false;
  int _progress = 0;
  int _total = 0;
  String? _error;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning || _working) return;
    final permission = await _repository.requestAccess();
    if (!mounted) return;
    if (!permission.hasAccess) {
      setState(() => _error = 'Photos access is needed to scan your library.');
      return;
    }
    setState(() {
      _error = null;
      _result = null;
      _selected.clear();
      _excluded.clear();
      _scanning = true;
      _cancelled = false;
      _progress = 0;
      _total = 0;
    });
    try {
      final paths = await _repository.collections(oldestFirst: false);
      final keepers = LibraryRepository.keepersAlbum(paths);
      final protected = keepers == null ? <String>{} :
        await _repository.keeperAssetIds(keepers);
      if (_cancelled) return;
      final result = await _scanner.scan(
        cancelled: () => _cancelled,
        protectedIds: protected,
        progress: (done, total) {
          if (!mounted) return;
          if (done == total || done % 10 == 0 || done == 1) {
            setState(() { _progress = done; _total = total; });
          }
        },
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = 'Scan failed: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<List<String>> _groupsFor(_Suggestion view) {
    final groups = _result?.groups;
    if (groups == null) return [];
    final source = switch (view) {
      _Suggestion.exact => groups.exact,
      _Suggestion.similar => groups.similar,
      _Suggestion.blurry => _chunk(groups.blurry, 24),
      _Suggestion.noPeople => _chunk(groups.noPeople, 24),
    };
    return source.map((g) => g.where((id) => !_excluded.contains(id) &&
      (_result?.photos.containsKey(id) ?? false)).toList()).where((g) =>
        g.length >= (view == _Suggestion.exact || view == _Suggestion.similar ? 2 : 1))
      .toList();
  }

  static List<List<String>> _chunk(List<String> items, int size) => [
    for (var i = 0; i < items.length; i += size)
      items.sublist(i, i + size > items.length ? items.length : i + size),
  ];

  void _toggle(String id) => setState(() {
    if (!_selected.add(id)) _selected.remove(id);
  });

  Future<void> _keep() async {
    if (_working || _selected.isEmpty) return;
    final chosen = _selected.map((id) => _result?.photos[id])
        .whereType<AssetEntity>().toList();
    setState(() => _working = true);
    try {
      await _repository.addToKeepers(chosen);
      if (!mounted) return;
      setState(() {
        _excluded.addAll(chosen.map((a) => a.id));
        _selected.clear();
      });
      _notice('Saved ${chosen.length} photos to Siftidy Keepers.');
    } catch (e) {
      if (mounted) _notice('Could not save to Keepers: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete() async {
    if (_working || _selected.isEmpty) return;
    // The system Photos sheet is responsible for final delete confirmation.
    setState(() => _working = true);
    try {
      final removed = await _repository.delete(_selected.toList());
      if (!mounted) return;
      setState(() {
        _excluded.addAll(removed);
        _selected.removeAll(removed);
      });
      if (removed.isNotEmpty) {
        _notice('Deleted ${removed.length} photos using Apple Photos.');
      }
    } catch (e) {
      if (mounted) _notice('Delete failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupsFor(_view);
    final result = _result;
    final isDisabled = _working || _scanning;
    return Scaffold(
      appBar: AppBar(title: const Text('Intelligent Cleanup')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Review suggestions. Nothing is deleted automatically.',
              style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Scanning uses local thumbnails, Apple Vision, and original-file hashes. '
                'iCloud-only originals may be downloaded by Apple Photos. '
                'Blur and people results are suggestions, not guarantees.',
              style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton.icon(
                onPressed: isDisabled ? null : _scan,
                icon: const Icon(Icons.search),
                label: Text(result == null ? 'Scan Photos library' : 'Scan again'),
              ),
              if (_scanning) ...[
                const SizedBox(width: 12),
                OutlinedButton(onPressed: () => setState(() => _cancelled = true),
                  child: const Text('Stop scan')),
                const SizedBox(width: 12),
                Expanded(child: LinearProgressIndicator(value: _total == 0 ? null :
                    _progress / _total)),
                const SizedBox(width: 8),
                Text('$_progress / $_total'),
              ],
            ]),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red))),
            if (result != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Scanned ${result.photos.length} of ${result.total} photos; '
                  '${result.skipped} unavailable. '
                  '${result.peopleDetectionAvailable ? 'People review available.' : 'Apple Vision unavailable; no-people review disabled.'}',
                style: const TextStyle(fontSize: 12)),
            ),
            if (result != null) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(
                children: [for (final kind in _Suggestion.values)
                  Padding(padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text('${kind.label} (${_count(kind)})'),
                      selected: kind == _view,
                      onSelected: (_) => setState(() {
                        _view = kind;
                        _selected.clear();
                      }))),
                ],
              )),
            ],
          ]),
        ),
        Expanded(child: result == null ? Center(child: Text(
          _scanning ? 'Analyzing photos locally…' : 'Run a scan to see cleanup suggestions.',
        )) : groups.isEmpty ? Center(child: Text('No ${_view.label.toLowerCase()} suggestions.')) :
          ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final ids = groups[index];
              return Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((_view == _Suggestion.exact || _view == _Suggestion.similar)
                      ? 'Group ${index + 1} · ${ids.length} photos'
                      : '${_view.label} · ${ids.length} photos',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8,
                      children: [for (final id in ids) _tile(result.photos[id]!)],
                    ),
                    const Divider(height: 22),
                  ]),
              );
            },
          )),
      ]),
      bottomNavigationBar: _selected.isEmpty ? null : SafeArea(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('${_selected.length} selected'),
          const SizedBox(width: 16),
          OutlinedButton.icon(onPressed: isDisabled ? null : _keep,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Keep in Keepers')),
          const SizedBox(width: 12),
          FilledButton.icon(onPressed: isDisabled ? null : _delete,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42333)),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete selected')),
        ]),
      )),
    );
  }

  int _count(_Suggestion kind) => _groupsFor(kind)
      .fold(0, (sum, group) => sum + group.length);

  Widget _tile(AssetEntity asset) {
    final selected = _selected.contains(asset.id);
    return SizedBox(width: 150, height: 162, child: InkWell(
      onTap: () => _toggle(asset.id),
      onDoubleTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _PhotoReview(asset: asset),
      )),
      child: Stack(children: [
        Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(8),
          child: AssetEntityImage(asset, isOriginal: false,
            thumbnailSize: const ThumbnailSize(320, 320), fit: BoxFit.cover))),
        Positioned(top: 5, right: 5, child: Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          color: selected ? const Color(0xFF76FFE0) : Colors.white,
          shadows: const [Shadow(blurRadius: 5, color: Colors.black87)],
        )),
        if (asset.isFavorite) const Positioned(left: 5, bottom: 5,
          child: Icon(Icons.favorite, color: Color(0xFFE94E70))),
      ]),
    ));
  }
}

class _PhotoReview extends StatelessWidget {
  const _PhotoReview({required this.asset});
  final AssetEntity asset;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review photo')),
    backgroundColor: Colors.black,
    body: Center(child: InteractiveViewer(
      child: AssetEntityImage(asset, isOriginal: true, fit: BoxFit.contain),
    )),
  );
}
