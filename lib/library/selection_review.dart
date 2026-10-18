import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'filtering.dart';

/// A review step is always shown before a destructive Photos API call.
class SelectionReview extends StatefulWidget {
  final List<AssetEntity> items;

  const SelectionReview({super.key, required this.items});

  @override
  State<SelectionReview> createState() => _SelectionReviewState();
}

class _SelectionReviewState extends State<SelectionReview> {
  bool _measuring = false;
  int _processed = 0;
  int _knownBytes = 0;
  int _unknownCount = 0;

  Future<void> _measure() async {
    if (_measuring) return;
    setState(() {
      _measuring = true;
      _processed = 0;
      _knownBytes = 0;
      _unknownCount = 0;
    });
    for (final entity in widget.items) {
      if (!mounted) return;
      int? length;
      try {
        // PhotoManager may resolve an iCloud asset to a temporary local file.
        final file = await entity.file;
        if (file != null) length = await file.length();
      } catch (_) {
        // Continue estimating the remaining files even if one is unavailable.
      }
      if (!mounted) return;
      setState(() {
        _processed++;
        if (length == null) {
          _unknownCount++;
        } else {
          _knownBytes += length;
        }
      });
    }
    if (mounted) setState(() => _measuring = false);
  }

  Future<void> _confirmDelete() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete from Photos?'),
        content: Text('This removes ${widget.items.length} item(s) from the Apple Photos '
            'library, including any devices synced through iCloud Photos. '
            'The Photos system may ask for confirmation. Items normally move '
            'to Recently Deleted, not an immediate permanent erase.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep photos')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue to Photos'),
          ),
        ],
      ),
    );
    if (shouldDelete == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.items.where((item) => item.type == AssetType.video).length;
    return AlertDialog(
      title: const Text('Review before deleting'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.items.length} selected · '
                '${widget.items.length - duration} photos · $duration videos'),
            const SizedBox(height: 12),
            SizedBox(height: 90, child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (_, index) => ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: AssetEntityImage(
                  widget.items[index],
                  width: 88, height: 88,
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize(176, 176),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 88, height: 88,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            )),
            const SizedBox(height: 12),
            if (_measuring) ...[
              LinearProgressIndicator(value: _processed / widget.items.length),
              Text('Checking sizes: $_processed / ${widget.items.length}'),
            ] else if (_processed > 0) ...[
              Text('${formatByteCount(_knownBytes)} measured'
                  '${_unknownCount > 0 ? " · $_unknownCount unavailable" : ""}'),
            ],
            TextButton.icon(
              onPressed: _measuring ? null : _measure,
              icon: const Icon(Icons.straighten),
              label: const Text('Estimate selected media size (optional)'),
            ),
            const Text('Sizes may exclude cloud-only files or use local copies. '
                'Actual free space is managed by Photos and may not change immediately.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            const Text('Siftidy never auto-deletes. This action affects your '
                'Apple Photos library and synced devices.'),
          ],
        )),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _confirmDelete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete selected…'),
        ),
      ],
    );
  }
}
