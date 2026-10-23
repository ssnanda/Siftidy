import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/library/scan_display.dart';

void main() {
  test('while running the top indicator has scan percent only', () {
    expect(
      scanButtonLabel(
        running: true, completed: false, visited: 30000, total: 49306),
      'Scan 61%',
    );
    expect(
      scanButtonLabel(
        running: true, completed: false, visited: 0, total: 49306),
      'Scan 0%',
    );
  });

  test('completed scan remains a percent, never a duplicate count', () {
    expect(
      scanButtonLabel(
        running: false, completed: true, visited: 49306, total: 49306),
      'Scan 100%',
    );
  });

  test('saved partial checkpoint still displays its percentage', () {
    expect(
      scanButtonLabel(
        running: false, completed: false, visited: 28000, total: 49306),
      'Scan 57%',
    );
  });

  test('before any scan the button keeps its original useful name', () {
    expect(
      scanButtonLabel(
        running: false, completed: false, visited: 0, total: 0),
      'Intelligent Cleanup',
    );
  });
}
