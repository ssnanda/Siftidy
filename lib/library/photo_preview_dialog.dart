import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// Light-weight keyboard-driven viewer over the existing paged gallery.
class PhotoPreviewDialog extends StatefulWidget {
  const PhotoPreviewDialog({
    super.key,
    required this.initialIndex,
    required this.items,
    required this.hasMore,
    required this.loadMore,
    required this.selected,
    required this.visit,
    required this.toggle,
    required this.delete,
    required this.keep,
  });

  final int initialIndex;
  final List<AssetEntity> Function() items;
  final bool Function() hasMore;
  final Future<void> Function() loadMore;
  final bool Function(String) selected;
  final ValueChanged<AssetEntity> visit;
  final ValueChanged<AssetEntity> toggle;
  final VoidCallback delete;
  final VoidCallback keep;

  @override
  State<PhotoPreviewDialog> createState() => _PhotoPreviewDialogState();
}

class _PhotoPreviewDialogState extends State<PhotoPreviewDialog> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Photo preview shortcuts');
  late int _index;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _navigate(int direction) async {
    if (_fetching) return;
    final next = _index + direction;
    if (next < 0) return;
    var photos = widget.items();
    if (next >= photos.length && widget.hasMore()) {
      setState(() => _fetching = true);
      try {
        await widget.loadMore();
      } finally {
        if (mounted) setState(() => _fetching = false);
      }
      if (!mounted) return;
      photos = widget.items();
    }
    if (next >= photos.length) return;
    widget.visit(photos[next]); // Add selection; never remove it while navigating.
    setState(() => _index = next);
    _focusNode.requestFocus();
  }

  void _toggle() {
    final photos = widget.items();
    if (_index < photos.length) {
      widget.toggle(photos[_index]);
      setState(() {});
    }
    _focusNode.requestFocus();
  }

  void _close() => Navigator.of(context).pop();

  void _closeThen(VoidCallback action) {
    _close();
    action();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      _navigate(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      _navigate(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) _toggle();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (event is KeyDownEvent) _closeThen(widget.delete);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.items();
    if (photos.isEmpty || _index >= photos.length) {
      return const Dialog(child: Padding(
        padding: EdgeInsets.all(20), child: Text('Image unavailable'),
      ));
    }
    final asset = photos[_index];
    final isChecked = widget.selected(asset.id);
    return Dialog(
      backgroundColor: const Color(0xFF101619),
      insetPadding: const EdgeInsets.all(24),
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1300, maxHeight: 900),
          child: SizedBox(
            width: 1200,
            height: 780,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: AssetEntityImage(
                    asset,
                    key: ValueKey(asset.id),
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize(2100, 2100),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.white, size: 48),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton.filled(
                    tooltip: 'Previous (Left)',
                    onPressed: _fetching || _index == 0 ? null : () => _navigate(-1),
                    icon: const Icon(Icons.chevron_left, size: 32),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton.filled(
                    tooltip: 'Next (Right)',
                    onPressed: _fetching ||
                            (_index + 1 >= photos.length && !widget.hasMore())
                        ? null : () => _navigate(1),
                    icon: const Icon(Icons.chevron_right, size: 32),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filledTonal(
                    tooltip: 'Close (Enter)',
                    icon: const Icon(Icons.close),
                    onPressed: _close,
                  ),
                ),
                Positioned(
                  left: 64,
                  top: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xDD182326),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      child: Text(
                        '${_index + 1} / ${photos.length} loaded',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _toggle,
                        icon: Icon(isChecked
                            ? Icons.check_box
                            : Icons.check_box_outline_blank),
                        label: Text(isChecked
                            ? 'Selected · Space to unselect'
                            : 'Unselected · Space to select'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _closeThen(widget.keep),
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Keep in Keepers'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFB42333),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _closeThen(widget.delete),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete selected'),
                      ),
                      const Text(
                        'Arrows: next/previous · Enter: close',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
