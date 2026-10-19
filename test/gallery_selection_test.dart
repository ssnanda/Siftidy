import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/library/gallery_selection.dart';

void main() {
  test('click toggles selected and unchecked without losing other choices', () {
    final selected = <String>{'photo-a', 'photo-c'};
    expect(togglePhotoMembership(selected, 'photo-a'), isFalse);
    expect(selected, {'photo-c'});
    expect(togglePhotoMembership(selected, 'photo-a'), isTrue);
    expect(selected, {'photo-c', 'photo-a'});
  });

  test('page reload after deletion appends only new photos', () {
    // A 25-item page has one deletion and the offset shifts left.
    final loaded = List.generate(25, (index) => 'photo-${index + 1}')
        ..remove('photo-8');
    final shiftedPage = List.generate(25, (index) => 'photo-${index + 1}')
        ..remove('photo-8')
        ..add('photo-26');
    expect(
      unseenPageItems(loaded, shiftedPage, (String id) => id),
      ['photo-26'],
    );
  });

  test('multi-page overlap preserves order and never duplicates photos', () {
    final loaded = ['a', 'b', 'c', 'd'];
    final more = unseenPageItems(loaded, ['c', 'd', 'e', 'e', 'f'],
        (String id) => id);
    expect(more, ['e', 'f']);
    expect([...loaded, ...more], ['a', 'b', 'c', 'd', 'e', 'f']);
  });
}
