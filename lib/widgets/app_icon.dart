// lib/widgets/app_icon.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

enum AppIconType {
  territory,  // hexágono táctico — territorios
  attack,     // diana — conquista y ataque
  defense,    // escudo — zona propia
  run,        // rayo — carrera activa
  hp,         // corazón — vida del territorio
  coin,       // moneda hexagonal — moneda del juego
}

class AppIcon extends StatelessWidget {
  final AppIconType type;
  final double size;
  final Color color;
  final bool filled;

  const AppIcon({
    super.key,
    required this.type,
    required this.color,
    this.size = 24,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AppIconPainter(type: type, color: color, filled: filled),
      ),
    );
  }
}

class _AppIconPainter extends CustomPainter {
  final AppIconType type;
  final Color color;
  final bool filled;

  const _AppIconPainter({
    required this.type,
    required this.color,
    required this.filled,
  });

  Paint _stroke(double sw) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = sw
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _fill => Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    switch (type) {
      case AppIconType.territory:
        _drawHexagon(canvas, size);
      case AppIconType.attack:
        _drawTarget(canvas, size);
      case AppIconType.defense:
        _drawShield(canvas, size);
      case AppIconType.run:
        _drawBolt(canvas, size);
      case AppIconType.hp:
        _drawHeart(canvas, size);
      case AppIconType.coin:
        _drawCoin(canvas, size);
    }
  }

  // ── Hexágono plano ──────────────────────────────────────────────────────────
  void _drawHexagon(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.44;
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60 - 30) * math.pi / 180;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    if (filled) {
      canvas.drawPath(path, _fill);
    } else {
      canvas.drawPath(path, _stroke(size.width * 0.09));
      canvas.drawCircle(Offset(cx, cy), size.width * 0.07, _fill);
    }
  }

  // ── Diana de ataque ─────────────────────────────────────────────────────────
  void _drawTarget(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = size.width * 0.42;
    final innerR = size.width * 0.20;
    final sw = size.width * 0.085;
    final gap = size.width * 0.14;

    canvas.drawCircle(Offset(cx, cy), outerR, _stroke(sw));
    canvas.drawCircle(Offset(cx, cy), innerR, filled ? _fill : _stroke(sw));

    final cs = _stroke(sw);
    canvas.drawLine(Offset(cx - outerR, cy), Offset(cx - gap, cy), cs);
    canvas.drawLine(Offset(cx + gap, cy), Offset(cx + outerR, cy), cs);
    canvas.drawLine(Offset(cx, cy - outerR), Offset(cx, cy - gap), cs);
    canvas.drawLine(Offset(cx, cy + gap), Offset(cx, cy + outerR), cs);
  }

  // ── Escudo ──────────────────────────────────────────────────────────────────
  void _drawShield(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.50, h * 0.06)
      ..lineTo(w * 0.92, h * 0.24)
      ..lineTo(w * 0.92, h * 0.54)
      ..cubicTo(w * 0.92, h * 0.72, w * 0.72, h * 0.85, w * 0.50, h * 0.94)
      ..cubicTo(w * 0.28, h * 0.85, w * 0.08, h * 0.72, w * 0.08, h * 0.54)
      ..lineTo(w * 0.08, h * 0.24)
      ..close();

    canvas.drawPath(path, filled ? _fill : _stroke(size.width * 0.09));
  }

  // ── Rayo (carrera activa) ───────────────────────────────────────────────────
  void _drawBolt(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.62, h * 0.05)
      ..lineTo(w * 0.28, h * 0.52)
      ..lineTo(w * 0.50, h * 0.52)
      ..lineTo(w * 0.38, h * 0.95)
      ..lineTo(w * 0.72, h * 0.48)
      ..lineTo(w * 0.50, h * 0.48)
      ..close();

    // El rayo siempre se rellena — es más legible a pequeños tamaños
    canvas.drawPath(path, _fill);
    if (!filled) {
      canvas.drawPath(path, _stroke(size.width * 0.06)
        ..color = color.withValues(alpha: 0.5));
    }
  }

  // ── Corazón (HP) ────────────────────────────────────────────────────────────
  void _drawHeart(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.50, h * 0.82)
      ..cubicTo(w * 0.10, h * 0.58, w * 0.05, h * 0.28, w * 0.28, h * 0.16)
      ..cubicTo(w * 0.40, h * 0.09, w * 0.50, h * 0.22, w * 0.50, h * 0.22)
      ..cubicTo(w * 0.50, h * 0.22, w * 0.60, h * 0.09, w * 0.72, h * 0.16)
      ..cubicTo(w * 0.95, h * 0.28, w * 0.90, h * 0.58, w * 0.50, h * 0.82)
      ..close();

    canvas.drawPath(path, filled ? _fill : _stroke(size.width * 0.09));
  }

  // ── Moneda hexagonal ────────────────────────────────────────────────────────
  void _drawCoin(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = size.width * 0.44;
    final innerR = size.width * 0.26;
    final sw = size.width * 0.085;

    final hexPath = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60 - 30) * math.pi / 180;
      final x = cx + outerR * math.cos(angle);
      final y = cy + outerR * math.sin(angle);
      i == 0 ? hexPath.moveTo(x, y) : hexPath.lineTo(x, y);
    }
    hexPath.close();

    canvas.drawPath(hexPath, filled ? _fill : _stroke(sw));
    canvas.drawCircle(Offset(cx, cy), innerR, _stroke(sw));
  }

  @override
  bool shouldRepaint(_AppIconPainter old) =>
      old.type != type || old.color != color || old.filled != filled;
}
