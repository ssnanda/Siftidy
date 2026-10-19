import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Compact vector wordmark icon sharing the Dock icon's photo-stack motif.
/// Drawn once at display resolution; no image decoding or external assets.
class SiftidyMark extends StatelessWidget {
  const SiftidyMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: RepaintBoundary(
          child: CustomPaint(painter: const _SiftidyMarkPainter()),
        ),
      );
}

class _SiftidyMarkPainter extends CustomPainter {
  const _SiftidyMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final white = Paint()..color = Colors.white;
    final rear = Paint()..color = const Color(0xFF087882);
    final front = Paint()..color = const Color(0xFF12ADBA);
    final sky = Paint()..color = const Color(0xFFB6EDFB);
    final mountain = Paint()..color = const Color(0xFF55ABD8);
    final sun = Paint()..color = const Color(0xFFFFC63F);

    canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 1, 98, 98),
        const Radius.circular(22)), white);
    canvas.save();
    canvas.translate(52, 51);
    canvas.rotate(9 * math.pi / 180);
    canvas.translate(-52, -51);
    canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(23, 20, 66, 69),
        const Radius.circular(11)), rear);
    canvas.restore();

    canvas.save();
    canvas.translate(48, 49);
    canvas.rotate(-8 * math.pi / 180);
    canvas.translate(-48, -49);
    canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(13, 14, 72, 72),
        const Radius.circular(12)), white);
    canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(16, 17, 66, 66),
        const Radius.circular(10)), front);
    canvas.drawCircle(const Offset(65, 33), 8, sun);
    canvas.drawPath(Path()
      ..moveTo(19, 76)
      ..lineTo(39, 45)
      ..lineTo(52, 63)
      ..lineTo(64, 53)
      ..lineTo(80, 75)
      ..close(), sky);
    canvas.drawPath(Path()
      ..moveTo(33, 80)
      ..lineTo(61, 52)
      ..lineTo(80, 76)
      ..close(), mountain);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
