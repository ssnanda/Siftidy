import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// The image stays mounted while selection/focus overlays change.
/// Repaint boundaries isolate image decoding and overlay redraws.
class PhotoGalleryTile extends StatefulWidget {
  const PhotoGalleryTile({
    super.key,
    required this.asset,
    required this.selected,
    required this.focused,
    required this.onClick,
    required this.onPreview,
    required this.keeper,
  });

  final AssetEntity asset;
  final ValueNotifier<bool> selected;
  final ValueNotifier<bool> focused;
  final VoidCallback onClick;
  final VoidCallback onPreview;
  final bool keeper;

  @override
  State<PhotoGalleryTile> createState() => _PhotoGalleryTileState();
}

class _PhotoGalleryTileState extends State<PhotoGalleryTile> {
  late final Widget _thumbnail;

  @override
  void initState() {
    super.initState();
    _thumbnail = RepaintBoundary(
      child: AssetEntityImage(
        widget.asset,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize(480, 480),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Color(0xFFE2E9E8),
          child: Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Semantics(
        label: widget.asset.type == AssetType.video ? 'Video' : 'Photo',
        child: InkWell(
          onTap: widget.onClick,
          onDoubleTap: widget.onPreview,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(fit: StackFit.expand, children: [
              _thumbnail,
              ValueListenableBuilder<bool>(
                valueListenable: widget.selected,
                builder: (context, selected, _) => IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0x0A007982)
                          : Colors.transparent,
                      border: selected
                          ? Border.all(
                              color: const Color(0xFF007982), width: 3)
                          : null,
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 24,
                          color: selected
                              ? const Color(0xFFB6FFF8)
                              : Colors.white,
                          shadows: const [
                            Shadow(color: Colors.black87, blurRadius: 7),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: widget.focused,
                builder: (context, focused, _) => focused
                    ? IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFFFFC64B),
                              width: 3,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (widget.asset.isFavorite)
                const Positioned(
                  bottom: 7, left: 7,
                  child: Icon(Icons.favorite,
                      color: Color(0xFFF04B6E), size: 20),
                ),
              if (widget.keeper)
                const Positioned(
                  bottom: 7, right: 7,
                  child: Icon(Icons.bookmark_rounded,
                      color: Color(0xFFFFCA62), size: 22),
                ),
              if (widget.asset.type == AssetType.video)
                const Positioned(
                  bottom: 7, right: 7,
                  child: Icon(Icons.videocam, color: Colors.white),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
