// lib/Widgets/parch_background.dart
//
// Uso:
//   import '../Widgets/parch_background.dart';
//
//   Scaffold(
//     body: ParchBackground(child: tuContenido),
//   )
//
// Opcionalmente con accentColor dinámico:
//   ParchBackground(accentColor: _accentColor, child: tuContenido)

import 'dart:math' as math;
import 'package:flutter/material.dart';

class ParchBackground extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  final bool showHexWatermark;

  const ParchBackground({
    super.key,
    required this.child,
    this.accentColor = const Color(0xFFE62E2E),
    this.showHexWatermark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── 1. Fondo base con gradiente radial cálido pergamino
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, -0.7),
              radius: 1.5,
              colors: [
                const Color(0xFF1A120A), // cálido pergamino oscuro
                const Color(0xFF090807), // negro casi puro
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),

        // ── 2. Tinte muy sutil del color del usuario (3% opacidad)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.2, -0.5),
                radius: 1.2,
                colors: [
                  accentColor.withOpacity(0.04),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // ── 3. Textura de ruido pergamino (CustomPainter)
        const Positioned.fill(
          child: _NoisePainterWidget(),
        ),

        // ── 4. Watermark hexagonal opcional (como en Resumen)
        if (showHexWatermark)
          Positioned(
            right: -60,
            top: 80,
            child: _HexWatermark(color: accentColor),
          ),

        // ── 5. Líneas de escaneo horizontales muy sutiles (estilo militar)
        const Positioned.fill(
          child: _ScanlinesPainterWidget(),
        ),

        // ── 6. El contenido encima de todo
        child,
      ],
    );
  }
}

// =============================================================================
// NOISE PAINTER — ruido orgánico tipo pergamino
// =============================================================================
class _NoisePainterWidget extends StatelessWidget {
  const _NoisePainterWidget();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _NoisePainter(),
    );
  }
}

class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42); // seed fija → mismo patrón siempre
    final paint = Paint()..strokeWidth = 1;

    // Puntos de ruido dispersos — simula grano de papel
    for (int i = 0; i < 600; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final opacity = rng.nextDouble() * 0.025; // muy sutil: 0–2.5%

      paint.color = Color.fromRGBO(202, 170, 108, opacity); // parchm

      // Mezcla de puntos y pequeñas líneas para textura orgánica
      if (i % 3 == 0) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      } else {
        canvas.drawLine(
          Offset(x, y),
          Offset(x + rng.nextDouble() * 3 - 1.5,
                 y + rng.nextDouble() * 3 - 1.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_NoisePainter oldDelegate) => false;
}

// =============================================================================
// SCANLINES — líneas horizontales tipo pantalla CRT militar
// =============================================================================
class _ScanlinesPainterWidget extends StatelessWidget {
  const _ScanlinesPainterWidget();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanlinesPainter(),
    );
  }
}

class _ScanlinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x05CAAA6C) // dorado al 2%
      ..strokeWidth = 0.5;

    // Una línea cada 4px — muy sutil, da profundidad
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinesPainter oldDelegate) => false;
}

// =============================================================================
// HEX WATERMARK — hexágono decorativo de fondo (como en Resumen)
// =============================================================================
class _HexWatermark extends StatelessWidget {
  final Color color;
  const _HexWatermark({required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(200, 200),
      painter: _HexPainter(color: color),
    );
  }
}

class _HexPainter extends CustomPainter {
  final Color color;
  const _HexPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 6;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // Solo borde, sin relleno — muy tenue
    final paint = Paint()
      ..color = color.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawPath(path, paint);

    // Segundo hexágono interior
    final path2 = Path();
    final r2 = r * 0.75;
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 6;
      final x = cx + r2 * math.cos(angle);
      final y = cy + r2 * math.sin(angle);
      if (i == 0) {
        path2.moveTo(x, y);
      } else {
        path2.lineTo(x, y);
      }
    }
    path2.close();

    paint.color = color.withOpacity(0.04);
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.color != color;
}