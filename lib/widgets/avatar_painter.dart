import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/avatar_config.dart';

const _kSkin      = Color(0xFFF4C589);
const _kSkinShade = Color(0xFFDBA968);
const _kOutline   = Color(0xFF2A1E14);

class AvatarPainter extends CustomPainter {
  final AvatarConfig config;
  final double runPhase; // 0.0–1.0 drives the running cycle

  const AvatarPainter({required this.config, this.runPhase = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final s  = math.min(size.width, size.height);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outlineW = (s * 0.014).clamp(0.6, 4.0);

    final phase  = runPhase * 2 * math.pi;
    final armSwg = math.sin(phase) * 0.55;
    final legSwg = -math.sin(phase) * 0.45;
    final bob    = math.sin(phase * 2).abs() * s * 0.012;

    // Fondo — disco con degradado radial suave en vez de un tinte plano.
    canvas.drawCircle(
      Offset(cx, cy),
      s / 2,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 1.1,
          colors: [
            Color.lerp(Colors.black, config.jacketColor, 0.26) ?? Colors.black,
            Color.lerp(Colors.black, config.jacketColor, 0.10) ?? Colors.black,
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: s / 2)),
    );

    // Proporciones (fracciones de s)
    final headR  = s * 0.145;
    final headCY = cy - s * 0.235 + bob;
    final neckH  = s * 0.030;
    final neckW  = s * 0.075;
    final torsoT = headCY + headR + neckH;
    final torsoH = s * 0.205;
    final torsoWTop = s * 0.215;
    final torsoWBot = s * 0.175;
    final torsoB = torsoT + torsoH;
    final armLen = s * 0.140;
    final legLen = s * 0.155;
    final limbW  = s * 0.062;
    final legHX  = torsoWBot * 0.32;
    final armShX = torsoWTop * 0.50;
    final armShY = torsoT + s * 0.022;

    // Pierna de atrás (contraria al swing de la de delante)
    _leg(canvas, cx + legHX, torsoB, -legSwg, legLen, limbW, s, outlineW, back: true);

    // Cuello
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, headCY + headR + neckH / 2 - s * 0.006),
          width: neckW, height: neckH + s * 0.012),
      Paint()..color = _kSkinShade,
    );

    // Torso — trapecio redondeado (hombros más anchos que cintura) con
    // degradado vertical sutil + contorno fino.
    final torsoPath = _torsoPath(cx, torsoT, torsoB, torsoWTop, torsoWBot, s);
    canvas.drawPath(
      torsoPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(config.jacketColor, Colors.white, 0.12) ?? config.jacketColor,
            Color.lerp(config.jacketColor, Colors.black, 0.16) ?? config.jacketColor,
          ],
        ).createShader(Rect.fromLTWH(cx - torsoWTop, torsoT, torsoWTop * 2, torsoH)),
    );
    canvas.drawPath(
      torsoPath,
      Paint()
        ..color = _kOutline.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineW,
    );
    // Cremallera / costura central — un detalle simple que rompe la
    // monotonía de la camiseta lisa.
    canvas.drawLine(
      Offset(cx, torsoT + s * 0.02),
      Offset(cx, torsoB - s * 0.015),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..strokeWidth = outlineW * 0.9,
    );

    // Pierna de delante
    _leg(canvas, cx - legHX, torsoB, legSwg, legLen, limbW, s, outlineW, back: false);

    // Brazos (por encima del torso)
    _arm(canvas, cx + armShX, armShY,  armSwg, armLen, limbW * 0.80, s, outlineW, back: true);
    _arm(canvas, cx - armShX, armShY, -armSwg, armLen, limbW * 0.80, s, outlineW, back: false);

    // Cabeza — círculo con sombreado esférico sutil + contorno.
    canvas.drawCircle(
      Offset(cx, headCY),
      headR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [Color.lerp(_kSkin, Colors.white, 0.18) ?? _kSkin, _kSkinShade],
        ).createShader(Rect.fromCircle(center: Offset(cx, headCY), radius: headR)),
    );

    // Cara (cejas, ojos, boca) — antes de pintar el pelo por encima si toca.
    if (s >= 26) _face(canvas, cx, headCY, headR, config.eyesIndex);

    // Pelo (algunos estilos tapan parte de la cabeza/cara)
    _hair(canvas, cx, headCY, headR, config.hairIndex, s, outlineW);

    // Contorno de cabeza — se pinta al final para que quede limpio incluso
    // donde el pelo se solapa con el borde del círculo.
    canvas.drawCircle(
      Offset(cx, headCY),
      headR,
      Paint()
        ..color = _kOutline.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineW,
    );
  }

  Path _torsoPath(double cx, double top, double bottom, double wTop, double wBot, double s) {
    final r = s * 0.05;
    return Path()
      ..moveTo(cx - wTop + r, top)
      ..lineTo(cx + wTop - r, top)
      ..quadraticBezierTo(cx + wTop, top, cx + wTop, top + r)
      ..lineTo(cx + wBot, bottom - r)
      ..quadraticBezierTo(cx + wBot, bottom, cx + wBot - r, bottom)
      ..lineTo(cx - wBot + r, bottom)
      ..quadraticBezierTo(cx - wBot, bottom, cx - wBot, bottom - r)
      ..lineTo(cx - wTop, top + r)
      ..quadraticBezierTo(cx - wTop, top, cx - wTop + r, top)
      ..close();
  }

  // Dibuja un miembro (brazo/pierna) como dos tramos con grosor, con un
  // trazo oscuro de contorno debajo del trazo de color — así las
  // extremidades dejan de leerse como simples líneas y ganan volumen.
  void _limb(Canvas c, Offset from, Offset to1, Offset to2, double w,
      Color color, double outlineW, {bool back = false}) {
    final tone = back ? (Color.lerp(color, Colors.black, 0.22) ?? color) : color;
    final outline = Paint()
      ..color = _kOutline.withValues(alpha: 0.45)
      ..strokeWidth = w + outlineW * 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = tone
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    c.drawLine(from, to1, outline);
    c.drawLine(to1, to2, outline);
    c.drawLine(from, to1, fill);
    c.drawLine(to1, to2, fill);
  }

  void _arm(Canvas c, double ox, double oy, double angle, double len, double w,
      double s, double outlineW, {required bool back}) {
    final elbow = Offset(ox + math.sin(angle) * len, oy + math.cos(angle) * len);
    final foreAngle = angle * 0.2 + (angle >= 0 ? 0.50 : -0.50);
    final hand = Offset(
      elbow.dx + math.sin(foreAngle) * len * 0.78,
      elbow.dy + math.cos(foreAngle) * len * 0.78,
    );
    _limb(c, Offset(ox, oy), elbow, hand, w,
        config.jacketColor.withValues(alpha: 0.92), outlineW, back: back);
    // Mano — pequeño puño para rematar el brazo.
    c.drawCircle(hand, w * 0.42, Paint()..color = _kSkinShade);
  }

  void _leg(Canvas c, double ox, double oy, double angle, double len, double w,
      double s, double outlineW, {required bool back}) {
    final knee = Offset(ox + math.sin(angle) * len, oy + math.cos(angle) * len);
    final shinAngle = angle * 0.35 + (angle >= 0 ? 0.38 : -0.08);
    final ankle = Offset(
      knee.dx + math.sin(shinAngle) * len * 0.84,
      knee.dy + math.cos(shinAngle) * len * 0.84,
    );
    _limb(c, Offset(ox, oy), knee, ankle, w, config.pantsColor, outlineW, back: back);

    // Zapato — forma redondeada en vez de una simple línea perpendicular.
    final toe = Offset(
      ankle.dx + math.sin(angle * 0.2 + 0.15) * s * 0.078,
      ankle.dy + s * 0.006,
    );
    final shoeColor = back
        ? (Color.lerp(config.shoesColor, Colors.black, 0.18) ?? config.shoesColor)
        : config.shoesColor;
    final shoePath = Path()
      ..moveTo(ankle.dx, ankle.dy - w * 0.30)
      ..lineTo(toe.dx, toe.dy - w * 0.22)
      ..quadraticBezierTo(toe.dx + s * 0.02, toe.dy, toe.dx - s * 0.01, toe.dy + w * 0.30)
      ..lineTo(ankle.dx - w * 0.32, ankle.dy + w * 0.34)
      ..quadraticBezierTo(ankle.dx - w * 0.5, ankle.dy, ankle.dx, ankle.dy - w * 0.30)
      ..close();
    c.drawPath(shoePath, Paint()..color = shoeColor);
    c.drawPath(shoePath, Paint()
      ..color = _kOutline.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = outlineW * 0.85);
  }

  void _face(Canvas c, double cx, double cy, double r, int idx) {
    final ey = cy - r * 0.06;
    final ex = r * 0.36;

    // Cejas — un trazo simple da mucha más expresividad a la cara.
    for (final side in [-1, 1]) {
      final bx = cx + side * ex;
      c.drawLine(
        Offset(bx - r * 0.15, ey - r * 0.34),
        Offset(bx + r * 0.15, ey - r * 0.38),
        Paint()
          ..color = const Color(0xFF6B4A2B)
          ..strokeWidth = r * 0.05
          ..strokeCap = StrokeCap.round,
      );
    }

    _eyes(c, cx, ey, r, ex, idx);

    // Boca — pequeña sonrisa curva.
    final mouth = Path()
      ..moveTo(cx - r * 0.22, cy + r * 0.42)
      ..quadraticBezierTo(cx, cy + r * 0.58, cx + r * 0.22, cy + r * 0.42);
    c.drawPath(
      mouth,
      Paint()
        ..color = const Color(0xFF7A4A3A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.055
        ..strokeCap = StrokeCap.round,
    );

    // Mofletes — un toque de color muy sutil.
    for (final side in [-1, 1]) {
      c.drawCircle(
        Offset(cx + side * r * 0.62, cy + r * 0.30),
        r * 0.16,
        Paint()..color = const Color(0xFFE8896B).withValues(alpha: 0.20),
      );
    }
  }

  void _eyes(Canvas c, double cx, double ey, double r, double ex, int idx) {
    switch (idx) {
      case 2: // Gafas de sol — puente + cristales con reflejo
        for (final dx in [-ex, ex]) {
          canvasLens(c, Offset(cx + dx, ey), r);
        }
        c.drawLine(
          Offset(cx - ex + r * 0.28, ey),
          Offset(cx + ex - r * 0.28, ey),
          Paint()
            ..color = Colors.black87
            ..strokeWidth = r * 0.06
            ..strokeCap = StrokeCap.round,
        );
        break;

      case 1: // Intenso — más grande, con brillo marcado
        for (final dx in [-ex, ex]) {
          c.drawCircle(Offset(cx + dx, ey), r * 0.17, Paint()..color = Colors.black87);
          c.drawCircle(
            Offset(cx + dx + r * 0.055, ey - r * 0.055),
            r * 0.055,
            Paint()..color = Colors.white70,
          );
        }
        break;

      default: // Normal — punto simple con micro-brillo
        for (final dx in [-ex, ex]) {
          c.drawCircle(Offset(cx + dx, ey), r * 0.135, Paint()..color = Colors.black87);
          c.drawCircle(
            Offset(cx + dx + r * 0.04, ey - r * 0.04),
            r * 0.035,
            Paint()..color = Colors.white60,
          );
        }
    }
  }

  void canvasLens(Canvas c, Offset center, double r) {
    final rect = Rect.fromCenter(center: center, width: r * 0.62, height: r * 0.42);
    c.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r * 0.10)),
      Paint()..color = Colors.black87,
    );
    c.drawLine(
      Offset(rect.left + rect.width * 0.22, rect.top + rect.height * 0.28),
      Offset(rect.left + rect.width * 0.55, rect.top + rect.height * 0.20),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = r * 0.045
        ..strokeCap = StrokeCap.round,
    );
  }

  void _hair(Canvas c, double cx, double cy, double r, int idx, double s, double outlineW) {
    switch (idx) {
      case 1: // Bandana — banda envolvente con nudo lateral
        final bandRect = Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.02);
        final bandPaint = Paint()
          ..color = const Color(0xFFD32F2F)
          ..strokeWidth = r * 0.34
          ..style = PaintingStyle.stroke;
        c.save();
        c.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r + 1)));
        c.drawArc(bandRect, math.pi * 1.06, math.pi * 0.88, false, bandPaint);
        c.restore();
        c.drawArc(bandRect, math.pi * 1.06, math.pi * 0.88, false, Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..strokeWidth = outlineW
          ..style = PaintingStyle.stroke);
        // Nudo + puntas ondeando a un lado.
        final knotX = cx + r * 0.92;
        final knotY = cy - r * 0.05;
        c.drawCircle(Offset(knotX, knotY), r * 0.14, Paint()..color = const Color(0xFFB71C1C));
        final tail = Path()
          ..moveTo(knotX, knotY)
          ..quadraticBezierTo(knotX + r * 0.35, knotY + r * 0.10, knotX + r * 0.30, knotY + r * 0.45)
          ..lineTo(knotX + r * 0.12, knotY + r * 0.40)
          ..quadraticBezierTo(knotX + r * 0.16, knotY + r * 0.08, knotX, knotY)
          ..close();
        c.drawPath(tail, Paint()..color = const Color(0xFFD32F2F));
        break;

      case 2: // Gorra — visera + cuerpo con botón y sombra de la visera
        final capCenter = Offset(cx, cy - r * 0.10);
        c.drawArc(
          Rect.fromCircle(center: capCenter, radius: r * 1.10),
          math.pi * 1.04, math.pi * 0.92,
          true,
          Paint()..color = const Color(0xFF1A237E),
        );
        c.drawArc(
          Rect.fromCircle(center: capCenter, radius: r * 1.10),
          math.pi * 1.04, math.pi * 0.92,
          false,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.35)
            ..strokeWidth = outlineW
            ..style = PaintingStyle.stroke,
        );
        c.drawCircle(Offset(cx, capCenter.dy - r * 0.62), r * 0.09,
            Paint()..color = const Color(0xFF0D47A1));
        // Visera con ligera sombra debajo.
        final brim = Path()
          ..moveTo(cx - r * 0.98, cy - r * 0.08)
          ..quadraticBezierTo(cx + r * 0.25, cy + r * 0.05, cx + r * 1.42, cy - r * 0.12)
          ..lineTo(cx + r * 1.40, cy + r * 0.02)
          ..quadraticBezierTo(cx + r * 0.25, cy + r * 0.20, cx - r * 0.96, cy + r * 0.06)
          ..close();
        c.drawPath(brim, Paint()..color = const Color(0xFF0D47A1));
        c.drawPath(brim, Paint()
          ..color = Colors.black.withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = outlineW * 0.8);
        break;

      case 3: // Afro — puff con textura (varios lóbulos) en vez de un círculo liso
        const puffColor = Color(0xFF3E2723);
        final puffCenter = Offset(cx, cy - r * 0.20);
        for (final off in [
          const Offset(0, 0), Offset(-r * 0.72, -r * 0.10), Offset(r * 0.72, -r * 0.10),
          Offset(-r * 0.48, r * 0.55), Offset(r * 0.48, r * 0.55),
          Offset(-r * 0.15, -r * 0.62), Offset(r * 0.15, -r * 0.62),
        ]) {
          c.drawCircle(puffCenter + off, r * 0.62, Paint()..color = puffColor);
        }
        c.drawCircle(puffCenter, r * 0.62, Paint()
          ..color = Colors.black.withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = outlineW);
        // Re-pinta la cara por encima del puff (el afro es más ancho que la cabeza).
        c.drawCircle(Offset(cx, cy + r * 0.06), r * 0.86, Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.45),
            radius: 1.05,
            colors: [Color.lerp(_kSkin, Colors.white, 0.18) ?? _kSkin, _kSkinShade],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy + r * 0.06), radius: r * 0.86)));
        break;

      case 4: // Mohicano — púas curvas + laterales rapados sombreados
        c.drawCircle(Offset(cx, cy), r, Paint()..color = Colors.black.withValues(alpha: 0.12));
        c.drawCircle(Offset(cx, cy + r * 0.08), r * 0.9, Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.45),
            radius: 1.05,
            colors: [Color.lerp(_kSkin, Colors.white, 0.18) ?? _kSkin, _kSkinShade],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy + r * 0.08), radius: r * 0.9)));
        final moPaint = Paint()..color = const Color(0xFFE53935);
        for (int i = -2; i <= 2; i++) {
          final bx  = cx + i * r * 0.22;
          final spH = r * 0.58 + (2 - i.abs()) * r * 0.22;
          final baseY = cy - r * 0.50;
          final path = Path()
            ..moveTo(bx - r * 0.13, baseY)
            ..quadraticBezierTo(bx - r * 0.05, baseY - spH * 0.6, bx, baseY - spH)
            ..quadraticBezierTo(bx + r * 0.05, baseY - spH * 0.6, bx + r * 0.13, baseY)
            ..close();
          c.drawPath(path, moPaint);
          c.drawPath(path, Paint()
            ..color = Colors.black.withValues(alpha: 0.30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = outlineW * 0.7);
        }
        break;

      default: // Corto (0) — gorro corto con mechón y highlight
        final capPath = Path()
          ..moveTo(cx - r, cy + r * 0.05)
          ..quadraticBezierTo(cx - r * 1.02, cy - r * 0.75, cx - r * 0.35, cy - r * 0.98)
          ..quadraticBezierTo(cx, cy - r * 1.12, cx + r * 0.35, cy - r * 0.98)
          ..quadraticBezierTo(cx + r * 1.02, cy - r * 0.75, cx + r, cy + r * 0.05)
          ..quadraticBezierTo(cx, cy - r * 0.15, cx - r, cy + r * 0.05)
          ..close();
        c.drawPath(capPath, Paint()..color = const Color(0xFF4E342E));
        c.drawPath(capPath, Paint()
          ..color = Colors.black.withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = outlineW * 0.8);
        c.drawLine(
          Offset(cx - r * 0.30, cy - r * 0.88),
          Offset(cx - r * 0.05, cy - r * 0.70),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.14)
            ..strokeWidth = r * 0.10
            ..strokeCap = StrokeCap.round,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(AvatarPainter old) =>
      old.runPhase        != runPhase        ||
      old.config.hairIndex  != config.hairIndex  ||
      old.config.eyesIndex  != config.eyesIndex  ||
      old.config.jacketColor != config.jacketColor ||
      old.config.pantsColor != config.pantsColor ||
      old.config.shoesColor != config.shoesColor;
}

// ─────────────────────────────────────────────────────────────────────────────

class RunningAvatarWidget extends StatefulWidget {
  final AvatarConfig config;
  final double size;
  final bool running;

  const RunningAvatarWidget({
    super.key,
    required this.config,
    this.size    = 40,
    this.running = true,
  });

  @override
  State<RunningAvatarWidget> createState() => _RunningAvatarWidgetState();
}

class _RunningAvatarWidgetState extends State<RunningAvatarWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    if (widget.running) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(RunningAvatarWidget old) {
    super.didUpdateWidget(old);
    if (widget.running == old.running) return;
    if (widget.running) {
      _ctrl.repeat();
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: AvatarPainter(
          config: widget.config,
          runPhase: widget.running ? _ctrl.value : 0.0,
        ),
      ),
    );
  }
}
