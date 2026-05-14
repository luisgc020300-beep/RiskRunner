import 'package:flutter/material.dart';

class OperativeBgPainter extends CustomPainter {
  const OperativeBgPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.03);
    const spacing = 32.0;
    for (double x = spacing / 2; x < size.width; x += spacing)
      for (double y = spacing / 2; y < size.height; y += spacing)
        canvas.drawCircle(Offset(x, y), 0.8, dot);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.9, -0.8),
          radius: 0.9,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.025),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(OperativeBgPainter old) => false;
}
