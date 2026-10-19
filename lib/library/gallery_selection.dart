/// Toggle a photo on click or Space without reloading thumbnail images.
/// Returns the new membership; modifies the selection set in place.
bool togglePhotoMembership(Set<String> selected, String id) {
  if (selected.remove(id)) return false;
  selected.add(id);
  return true;
}

/// Merge an overlapping PhotoKit page without duplicating or skipping IDs
/// after items are deleted and page offsets shift.
List<T> unseenPageItems<T>(
  Iterable<T> loaded,
  Iterable<T> page,
  String Function(T) identifier,
) {
  final seen = loaded.map(identifier).toSet();
  return page.where((item) => seen.add(identifier(item))).toList(growable: false);
}
