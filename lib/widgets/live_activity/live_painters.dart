import 'dart:math' as math;
import 'package:flutter/material.dart';

class LiveSpeedLinesPainter extends CustomPainter {
  final Color color;
  const LiveSpeedLinesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color.withValues(alpha: 0.32)
      ..strokeWidth = 1.5
      ..style       = PaintingStyle.stroke;
    final rnd = math.Random(42);
    for (int i = 0; i < 10; i++) {
      final x   = rnd.nextDouble() * size.width;
      final y   = rnd.nextDouble() * size.height;
      final len = 12.0 + rnd.nextDouble() * 22;
      canvas.drawLine(Offset(x, y), Offset(x - len, y + 3), paint);
    }
  }

  @override
  bool shouldRepaint(LiveSpeedLinesPainter old) => old.color != color;
}
