import 'dart:math' as math;
import 'package:flutter/material.dart';

class MapStar {
  final double x, y, r, opacity;
  const MapStar(this.x, this.y, this.r, this.opacity);
}

class MapStarfieldPainter extends CustomPainter {
  final List<MapStar> stars;
  const MapStarfieldPainter(this.stars);

  static List<MapStar> generate({int count = 220}) {
    final rng = math.Random(0xCAFE);
    return List.generate(count, (_) {
      final large = rng.nextDouble() < 0.07;
      final r = large
          ? (rng.nextDouble() * 0.7 + 1.3)
          : (rng.nextDouble() * 0.55 + 0.25);
      final opacity = rng.nextDouble() * 0.45 + 0.50;
      return MapStar(rng.nextDouble(), rng.nextDouble(), r, opacity);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final s in stars) {
      paint.color = Color.fromRGBO(210, 220, 255, s.opacity);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(MapStarfieldPainter old) => false;
}
