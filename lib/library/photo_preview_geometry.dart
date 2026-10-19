import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Return a content-sized preview frame without opaque letterbox panels.
Size photoPreviewFrameSize({
  required Size image,
  required Size viewport,
}) {
  final width = image.width > 0 ? image.width : 1.0;
  final height = image.height > 0 ? image.height : 1.0;
  final availableWidth = math.max(1.0, viewport.width - 48);
  final availableHeight = math.max(1.0, viewport.height - 64);
  final scale = math.min(availableWidth / width, availableHeight / height);
  return Size(width * scale, height * scale);
}

/// Focus next surviving photo, falling back to the preceding photo.
/// Returns -1 if no visible photos remain.
int nextIndexAfterDeletion(
  List<String> previousIds,
  Set<String> deletedIds,
  int focusedIndex,
) {
  final survivors = previousIds.where((id) => !deletedIds.contains(id)).toList();
  if (survivors.isEmpty) return -1;
  final origin = focusedIndex >= 0 &&
          focusedIndex < previousIds.length &&
          deletedIds.contains(previousIds[focusedIndex])
      ? focusedIndex
      : previousIds.indexWhere(deletedIds.contains);
  if (origin < 0) return focusedIndex.clamp(0, survivors.length - 1);
  for (var i = origin; i < previousIds.length; i++) {
    final id = previousIds[i];
    if (!deletedIds.contains(id)) return survivors.indexOf(id);
  }
  for (var i = origin - 1; i >= 0; i--) {
    final id = previousIds[i];
    if (!deletedIds.contains(id)) return survivors.indexOf(id);
  }
  return -1;
}
