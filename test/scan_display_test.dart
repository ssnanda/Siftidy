import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/library/scan_display.dart';

void main() {
  testWidgets('scan badge has no animated spinner while scanning', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ScanProgressButton(
        running: true, completed: false, visited: 93, total: 100,
      )),
    ));
    expect(find.text('Scan 93%'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });

  testWidgets('saved partial scan has same static badge while paused',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ScanProgressButton(
        running: false, completed: false, visited: 93, total: 100,
      )),
    ));
    expect(find.text('Scan 93%'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

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

  test('finalization fraction keeps the top indicator below 100', () {
    expect(
      scanButtonLabel(
        running: true, completed: false, visited: 49306, total: 49306,
        fraction: .975),
      'Scan 98%',
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
