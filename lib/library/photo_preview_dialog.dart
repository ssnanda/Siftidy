import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'photo_preview_geometry.dart';

/// A content-sized preview. Images retain their aspect ratio, with no
/// permanent black side panels, footer, or letterbox stage.
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
  /// Delete only the image currently being previewed, not the grid selection.
  final Future<bool> Function(AssetEntity) delete;
  final VoidCallback keep;

  @override
  State<PhotoPreviewDialog> createState() => _PhotoPreviewDialogState();
}

class _PhotoPreviewDialogState extends State<PhotoPreviewDialog> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Photo preview shortcuts');
  late int _index;
  bool _fetching = false;
  bool _deleting = false;
  bool _controlsVisible = false;

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
    if (_fetching || _deleting) return;
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
    widget.visit(photos[next]); // Arrows select; only Space deselects.
    setState(() => _index = next);
    _focusNode.requestFocus();
  }

  void _toggle() {
    if (_fetching || _deleting) return;
    final photos = widget.items();
    if (_index >= 0 && _index < photos.length) {
      widget.toggle(photos[_index]);
      setState(() {});
    }
    _focusNode.requestFocus();
  }

  Future<void> _deleteCurrent() async {
    if (_fetching || _deleting) return;
    final photos = widget.items();
    if (_index < 0 || _index >= photos.length) return;
    final current = photos[_index];
    setState(() => _deleting = true);
    try {
      final deleted = await widget.delete(current);
      if (!mounted || !deleted) return;
      var remaining = widget.items();
      if (_index >= remaining.length && widget.hasMore()) {
        await widget.loadMore();
        if (!mounted) return;
        remaining = widget.items();
      }
      if (remaining.isEmpty) {
        _close(); // Nothing left in this view.
        return;
      }
      // Same index now points to next image; at end use the previous one.
      final next = math.min(_index, remaining.length - 1);
      widget.visit(remaining[next]);
      setState(() => _index = next);
      _focusNode.requestFocus();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _close() => Navigator.of(context).pop();

  void _closeThen(VoidCallback action) {
    if (_fetching || _deleting) return;
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
      if (event is KeyDownEvent && !_deleting) _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (event is KeyDownEvent) _deleteCurrent();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.items();
    if (photos.isEmpty || _index >= photos.length) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Image unavailable'),
        ),
      );
    }
    final asset = photos[_index];
    final checked = widget.selected(asset.id);
    final frame = photoPreviewFrameSize(
      image: Size(asset.width.toDouble(), asset.height.toDouble()),
      viewport: MediaQuery.sizeOf(context),
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.zero,
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: Center(
          child: SizedBox(
            width: frame.width,
            height: frame.height,
            child: MouseRegion(
              onEnter: (_) => setState(() => _controlsVisible = true),
              onExit: (_) => setState(() => _controlsVisible = false),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
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
                          child: Icon(Icons.broken_image_outlined, size: 48),
                        ),
                      ),
                    ),
                    // Controls live over the image, never in side gutters.
                    IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: AnimatedOpacity(
                        opacity: _controlsVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 110),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton.filled(
                                tooltip: 'Previous (Left arrow)',
                                onPressed: _deleting || _fetching || _index == 0
                                    ? null : () => _navigate(-1),
                                icon: const Icon(Icons.chevron_left),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton.filled(
                                tooltip: 'Next (Right arrow)',
                                onPressed: _deleting || _fetching ||
                                    (_index + 1 >= photos.length && !widget.hasMore())
                                    ? null : () => _navigate(1),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: IconButton.filledTonal(
                                tooltip: 'Close (Enter)',
                                onPressed: _deleting ? null : _close,
                                icon: const Icon(Icons.close),
                              ),
                            ),
                            Positioned(
                              bottom: 10,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: const Color(0xDD121B1D),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: checked
                                              ? 'Unselect (Space)' : 'Select (Space)',
                                          onPressed: _deleting ? null : _toggle,
                                          color: Colors.white,
                                          icon: Icon(checked
                                              ? Icons.check_box
                                              : Icons.check_box_outline_blank),
                                        ),
                                        IconButton(
                                          tooltip: 'Keep in Keepers',
                                          onPressed: _deleting
                                              ? null : () => _closeThen(widget.keep),
                                          color: Colors.white,
                                          icon: const Icon(Icons.bookmark_add_outlined),
                                        ),
                                        _deleting
                                            ? const SizedBox(
                                                width: 48,
                                                height: 48,
                                                child: Center(
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              )
                                            : IconButton(
                                                tooltip: 'Delete this photo (Delete)',
                                                onPressed: _deleteCurrent,
                                                color: const Color(0xFFFFB2B2),
                                                icon: const Icon(Icons.delete_outline),
                                              ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
