import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── Modelo ────────────────────────────────────────────────────────────────────
class LiveStarData {
  final double x;
  final double y;
  final double r;
  final double speed;
  final double phase;
  final int    type; // 0=normal, 1=grande con halo, 2=gigante con destello
  const LiveStarData({
    required this.x,
    required this.y,
    required this.r,
    required this.speed,
    required this.phase,
    required this.type,
  });
}

// ── Painter ───────────────────────────────────────────────────────────────────
class LiveStarfieldPainter extends CustomPainter {
  final List<LiveStarData> stars;
  final double animValue;
  final bool nightMode;
  final double globeRotation;

  const LiveStarfieldPainter({
    required this.stars,
    required this.animValue,
    required this.nightMode,
    this.globeRotation = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final s in stars) {
      final twinkle = (math.sin((animValue * math.pi * 2 * s.speed) + s.phase) + 1) / 2;

      final double baseOpacity = nightMode
          ? (s.type == 2 ? 0.75 : s.type == 1 ? 0.65 : 0.45)
          : (s.type == 2 ? 0.30 : s.type == 1 ? 0.22 : 0.14);
      final double twinkleAmp  = nightMode ? 0.25 : 0.12;
      final double opacity = (baseOpacity + twinkle * twinkleAmp).clamp(0.0, 1.0);

      final cx = ((s.x + globeRotation) % 1.0) * size.width;
      final cy = s.y * size.height;

      final int r, g, b;
      final tintSeed = (s.phase * 3).floor() % 4;
      if (nightMode) {
        switch (tintSeed) {
          case 0:  r = 210; g = 230; b = 255; break;
          case 1:  r = 255; g = 248; b = 235; break;
          case 2:  r = 200; g = 220; b = 255; break;
          default: r = 240; g = 240; b = 255; break;
        }
      } else {
        r = 255; g = 245; b = 200;
      }

      final Color starColor = Color.fromRGBO(r, g, b, opacity);

      // ── Tipo 2: GIGANTE con destello en cruz ──────────────────────────────
      if (s.type == 2) {
        final haloPaint = Paint()
          ..shader = RadialGradient(colors: [
            Color.fromRGBO(r, g, b, opacity * 0.35),
            Color.fromRGBO(r, g, b, 0),
          ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: s.r * 5.5));
        canvas.drawCircle(Offset(cx, cy), s.r * 5.5, haloPaint);

        final haloIn = Paint()
          ..shader = RadialGradient(colors: [
            Color.fromRGBO(r, g, b, opacity * 0.55),
            Color.fromRGBO(r, g, b, 0),
          ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: s.r * 2.8));
        canvas.drawCircle(Offset(cx, cy), s.r * 2.8, haloIn);

        final crossLen = s.r * (1.8 + twinkle * 1.2);
        final crossPaint = Paint()
          ..strokeWidth = 0.9 + twinkle * 0.4
          ..style       = PaintingStyle.stroke;

        crossPaint.shader = LinearGradient(colors: [
          Color.fromRGBO(r, g, b, 0),
          Color.fromRGBO(r, g, b, opacity * 0.85),
          Color.fromRGBO(r, g, b, 0),
        ]).createShader(Rect.fromPoints(Offset(cx - crossLen, cy), Offset(cx + crossLen, cy)));
        canvas.drawLine(Offset(cx - crossLen, cy), Offset(cx + crossLen, cy), crossPaint);

        crossPaint.shader = LinearGradient(
          colors: [
            Color.fromRGBO(r, g, b, 0),
            Color.fromRGBO(r, g, b, opacity * 0.85),
            Color.fromRGBO(r, g, b, 0),
          ],
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
        ).createShader(Rect.fromPoints(Offset(cx, cy - crossLen), Offset(cx, cy + crossLen)));
        canvas.drawLine(Offset(cx, cy - crossLen), Offset(cx, cy + crossLen), crossPaint);

        final diagLen = crossLen * 0.55;
        final diagPaint = Paint()
          ..color       = Color.fromRGBO(r, g, b, opacity * 0.35)
          ..strokeWidth = 0.6
          ..style       = PaintingStyle.stroke;
        canvas.drawLine(Offset(cx - diagLen, cy - diagLen), Offset(cx + diagLen, cy + diagLen), diagPaint);
        canvas.drawLine(Offset(cx + diagLen, cy - diagLen), Offset(cx - diagLen, cy + diagLen), diagPaint);

        paint.color = Color.fromRGBO(r, g, b, (opacity * 1.0).clamp(0, 1));
        canvas.drawCircle(Offset(cx, cy), s.r * (0.8 + twinkle * 0.4), paint);

        paint.color = Color.fromRGBO(255, 255, 255, (opacity * 0.9).clamp(0, 1));
        canvas.drawCircle(Offset(cx, cy), s.r * 0.4, paint);
      }

      // ── Tipo 1: GRANDE con halo suave ─────────────────────────────────────
      else if (s.type == 1) {
        final haloPaint = Paint()
          ..shader = RadialGradient(colors: [
            Color.fromRGBO(r, g, b, opacity * 0.30),
            Color.fromRGBO(r, g, b, 0),
          ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: s.r * 3.2));
        canvas.drawCircle(Offset(cx, cy), s.r * 3.2, haloPaint);

        paint.color = starColor;
        canvas.drawCircle(Offset(cx, cy), s.r * (0.75 + twinkle * 0.5), paint);

        paint.color = Color.fromRGBO(255, 255, 255, (opacity * 0.7).clamp(0, 1));
        canvas.drawCircle(Offset(cx, cy), s.r * 0.35, paint);
      }

      // ── Tipo 0: NORMAL ────────────────────────────────────────────────────
      else {
        if (s.r > 1.2) {
          paint.color = Color.fromRGBO(r, g, b, opacity * 0.20);
          canvas.drawCircle(Offset(cx, cy), s.r * 2.0, paint);
        }
        paint.color = starColor;
        canvas.drawCircle(Offset(cx, cy), s.r * (0.65 + twinkle * 0.55), paint);
      }
    }
  }

  @override
  bool shouldRepaint(LiveStarfieldPainter old) =>
      old.animValue != animValue || old.nightMode != nightMode || old.globeRotation != globeRotation;
}

// ── Widget ────────────────────────────────────────────────────────────────────
class LiveStarfieldWidget extends StatefulWidget {
  final bool nightMode;
  final Animation<double>? globeAnim;
  const LiveStarfieldWidget({super.key, required this.nightMode, this.globeAnim});

  @override
  State<LiveStarfieldWidget> createState() => _LiveStarfieldWidgetState();
}

class _LiveStarfieldWidgetState extends State<LiveStarfieldWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<LiveStarData> _stars;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(12345);
    _stars = List.generate(120, (i) {
      final x     = rnd.nextDouble();
      final y     = rnd.nextDouble();
      final speed = 0.2 + rnd.nextDouble() * 0.8;
      final phase = rnd.nextDouble() * math.pi * 2;

      final int type;
      final double r;
      final roll = rnd.nextDouble();
      if (roll > 0.98) {
        type = 2; r = 1.0 + rnd.nextDouble() * 0.6;
      } else if (roll > 0.92) {
        type = 1; r = 0.6 + rnd.nextDouble() * 0.5;
      } else {
        type = 0; r = 0.2 + rnd.nextDouble() * 0.6;
      }

      return LiveStarData(x: x, y: y, r: r, speed: speed, phase: phase, type: type);
    });

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.globeAnim != null
        ? Listenable.merge([_ctrl, widget.globeAnim!])
        : _ctrl as Listenable;
    return AnimatedBuilder(
      animation: listenable,
      builder: (_, __) => CustomPaint(
        painter: LiveStarfieldPainter(
          stars:         _stars,
          animValue:     _ctrl.value,
          nightMode:     widget.nightMode,
          globeRotation: widget.globeAnim?.value ?? 0.0,
        ),
        size: Size.infinite,
      ),
    );
  }
}
