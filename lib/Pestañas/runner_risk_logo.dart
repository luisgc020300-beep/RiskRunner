// ══════════════════════════════════════════════════════════════
//  runner_risk_logo.dart
//  Widget reutilizable — reemplaza el Icon(Icons.bolt_rounded)
//  en login_screen.dart y donde quieras en la app
// ══════════════════════════════════════════════════════════════

import 'dart:math';
import 'package:flutter/material.dart';

class RunnerRiskLogo extends StatelessWidget {
  final double size;

  const RunnerRiskLogo({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    return Container(
      // Glow exterior — igual que el del rayo original
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.7),
            blurRadius: 30,
            spreadRadius: 5,
          ),
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 60,
            spreadRadius: 10,
          ),
        ],
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _HexSwordsPainter(),
        ),
      ),
    );
  }
}

class _HexSwordsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // ── 1. HEXÁGONO RELLENO (amarillo-naranja como el rayo) ────
    final hexFill = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFD000), // amarillo centro
          const Color(0xFFFF8C00), // naranja-ámbar borde
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));

    final hexPath = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (pi / 180) * (60 * i - 30);
      final x = cx + r * 0.92 * cos(angle);
      final y = cy + r * 0.92 * sin(angle);
      if (i == 0) hexPath.moveTo(x, y);
      else hexPath.lineTo(x, y);
    }
    hexPath.close();
    canvas.drawPath(hexPath, hexFill);

    // ── 2. BORDE DEL HEXÁGONO ──────────────────────────────────
    final hexBorder = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.025;
    canvas.drawPath(hexPath, hexBorder);

    // ── 3. ESPADAS CRUZADAS ────────────────────────────────────
    _drawSword(canvas, size,
      from: Offset(cx - r * 0.42, cy - r * 0.42),
      to:   Offset(cx + r * 0.42, cy + r * 0.42),
    );

    _drawSword(canvas, size,
      from: Offset(cx + r * 0.42, cy - r * 0.42),
      to:   Offset(cx - r * 0.42, cy + r * 0.42),
      mirrorGuard: true,
    );
  }

  void _drawSword(
    Canvas canvas,
    Size size, {
    required Offset from,
    required Offset to,
    bool mirrorGuard = false,
  }) {
    final sw = size.width;

    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = sqrt(dx * dx + dy * dy);
    final ux = dx / len;
    final uy = dy / len;
    final px = -uy;
    final py = ux;

    final bladePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..style = PaintingStyle.fill;

    final bladeWidth = sw * 0.055;
    final bladeStart = 0.22;

    final bBase1 = from + Offset(ux * len * bladeStart + px * bladeWidth, uy * len * bladeStart + py * bladeWidth);
    final bBase2 = from + Offset(ux * len * bladeStart - px * bladeWidth, uy * len * bladeStart - py * bladeWidth);
    final bTip   = to;

    final bladePath = Path()
      ..moveTo(bBase1.dx, bBase1.dy)
      ..lineTo(bBase2.dx, bBase2.dy)
      ..lineTo(bTip.dx,   bTip.dy)
      ..close();

    final bladeHalf1 = from + Offset(ux * len * bladeStart, uy * len * bladeStart);
    final shadowBladePath = Path()
      ..moveTo(bladeHalf1.dx + px * bladeWidth * 0.1, bladeHalf1.dy + py * bladeWidth * 0.1)
      ..lineTo(bladeHalf1.dx - px * bladeWidth, bladeHalf1.dy - py * bladeWidth)
      ..lineTo(bTip.dx, bTip.dy)
      ..close();
    canvas.drawPath(shadowBladePath, shadowPaint);
    canvas.drawPath(bladePath, bladePaint);

    final filoPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..strokeWidth = sw * 0.012
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      from + Offset(ux * len * bladeStart + px * bladeWidth * 0.35, uy * len * bladeStart + py * bladeWidth * 0.35),
      bTip - Offset(ux * sw * 0.04, uy * sw * 0.04),
      filoPaint,
    );

    final guardCenter = from + Offset(ux * len * 0.20, uy * len * 0.20);
    final guardLen = sw * (mirrorGuard ? 0.19 : 0.19);
    final guardWidth = sw * 0.038;

    final g1 = guardCenter + Offset(px * guardLen, py * guardLen);
    final g2 = guardCenter - Offset(px * guardLen, py * guardLen);

    final guardPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = guardWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(g1, g2, guardPaint);

    final guardShadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..strokeWidth = guardWidth * 0.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      g1 + Offset(ux * sw * 0.01, uy * sw * 0.01),
      g2 + Offset(ux * sw * 0.01, uy * sw * 0.01),
      guardShadowPaint,
    );

    final gripPaint = Paint()
      ..color = const Color(0xFFD4D4D4)
      ..strokeWidth = sw * 0.07
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final gripShadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..strokeWidth = sw * 0.07
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final gripStart = from + Offset(ux * len * 0.20, uy * len * 0.20);
    final gripEnd   = from + Offset(ux * len * 0.005, uy * len * 0.005);

    canvas.drawLine(
      gripStart + Offset(px * sw * 0.012, py * sw * 0.012),
      gripEnd   + Offset(px * sw * 0.012, py * sw * 0.012),
      gripShadowPaint,
    );
    canvas.drawLine(gripStart, gripEnd, gripPaint);

    final pommelPaint = Paint()..color = Colors.white;
    canvas.drawCircle(from, sw * 0.045, pommelPaint);
    canvas.drawCircle(
      from + Offset(sw * 0.01, sw * 0.01),
      sw * 0.025,
      Paint()..color = Colors.black.withOpacity(0.25),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}