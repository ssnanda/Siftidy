import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siftidy/branding/siftidy_mark.dart';

void main() {
  testWidgets('Siftidy header mark uses a fixed, crisp paint surface',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: SiftidyMark(size: 42))),
    ));
    expect(tester.getSize(find.byType(SiftidyMark)), const Size(42, 42));
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
