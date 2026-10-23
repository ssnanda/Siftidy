import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/cleanup/photo_analysis.dart';
import 'package:siftidy/cleanup/scan_result_archive.dart';

void main() {
  late Directory folder;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('siftidy-snapshots-');
  });

  tearDown(() async {
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
  });

  test('completed results are independent and can be reopened', () async {
    final archive = ScanResultArchive(folder);
    final saved = await archive.save(
      started: DateTime(2026, 10, 23, 10),
      total: 49305,
      analyzed: 49297,
      groups: const CleanupGroups(
        exact: [['a', 'b', 'c']],
        similar: [['d', 'e']],
        blurry: ['f', 'g'],
        noPeople: ['h'],
      ),
    );
    expect(saved.exactCount, 2);
    expect(saved.similarCount, 1);
    expect(saved.blurryCount, 2);
    expect(saved.noPeopleCount, 1);
    expect(saved.bytes, greaterThan(0));

    final otherProcess = ScanResultArchive(folder);
    final recovered = await otherProcess.read(saved.id);
    expect(recovered!.total, 49305);
    expect(recovered.groups.exact.single, ['a', 'b', 'c']);
    expect((await otherProcess.list()).single.id, saved.id);
  });

  test('deleting one result set does not delete other snapshots', () async {
    final archive = ScanResultArchive(folder);
    Future<ScanResultSnapshot> save(int day) => archive.save(
      started: DateTime(2026, 10, day),
      total: 100, analyzed: 100,
      groups: const CleanupGroups(
        exact: [], similar: [], blurry: [], noPeople: [],
      ),
    );
    final first = await save(22);
    final second = await save(23);
    expect((await archive.list()).length, 2);
    await archive.delete(first.id);
    expect((await archive.list()).single.id, second.id);
    expect(await archive.read(first.id), isNull);
    expect(await folder.exists(), isTrue);
  });

  test('invalid snapshot identifiers cannot escape the storage folder',
      () async {
    final archive = ScanResultArchive(folder);
    await expectLater(archive.delete('../outside'), throwsArgumentError);
  });
}
