/// Build a non-destructive keep-one deletion plan for selected duplicate sets.
/// Exactly one of each selected set is excluded from deletion candidates.
Set<String> duplicateExtras(
  List<List<String>> groups,
  Set<String> selectedGroupKeys,
  String Function(List<String> group) keeperForGroup,
) {
  final extras = <String>{};
  for (final group in groups) {
    if (group.length < 2 || !selectedGroupKeys.contains(group.first)) {
      continue;
    }
    final keeper = keeperForGroup(group);
    if (!group.contains(keeper)) {
      throw StateError('Selected keeper is not in its duplicate group.');
    }
    extras.addAll(group.where((id) => id != keeper));
  }
  return extras;
}