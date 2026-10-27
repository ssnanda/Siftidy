import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/cleanup/duplicate_selection.dart';

void main() {
  test('five pairs keep five photos and delete exactly five extras', () {
    final groups = [
      ['a1', 'a2'],
      ['b1', 'b2'],
      ['c1', 'c2'],
      ['d1', 'd2'],
      ['e1', 'e2'],
    ];
    final candidates = duplicateExtras(groups,
        {'a1', 'b1', 'c1', 'd1', 'e1'}, (group) => group.first);
    expect(candidates, {'a2', 'b2', 'c2', 'd2', 'e2'});
    for (final group in groups) {
      expect(group.where((id) => !candidates.contains(id)), hasLength(1));
    }
  });

  test('unselected groups remain untouched, custom keeper respected', () {
    final groups = [
      ['a', 'b', 'c'],
      ['d', 'e'],
    ];
    expect(duplicateExtras(groups, {'a'}, (_) => 'c'), {'a', 'b'});
  });

  test('invalid keeper rejects plan without candidates', () {
    expect(() => duplicateExtras([['a', 'b']], {'a'}, (_) => 'x'),
        throwsStateError);
  });

  test('cross-category deletion protects keepers without blocking others', () {
    final safe = protectDuplicateKeepers(
      {'a', 'b', 'c', 'unrelated'},
      [['a', 'b'], ['b', 'c']],
      (group) => group.first,
    );
    expect(safe, {'c', 'unrelated'});
    expect(['a', 'b'].every(safe.contains), isFalse);
    expect(['b', 'c'].every(safe.contains), isTrue);
  });
}
