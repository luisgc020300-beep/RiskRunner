import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/avatar_config.dart';

const _kSkin = Color(0xFFF4C589);

class AvatarPainter extends CustomPainter {
  final AvatarConfig config;
  final double runPhase; // 0.0–1.0 drives the running cycle

  const AvatarPainter({required this.config, this.runPhase = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final s  = math.min(size.width, size.height);
    final cx = size.width / 2;
    final cy = size.height / 2;

    final phase  = runPhase * 2 * math.pi;
    final armSwg = math.sin(phase) * 0.55;
    final legSwg = -math.sin(phase) * 0.45;
    final bob    = math.sin(phase * 2).abs() * s * 0.012;

    // Background circle (jacket-tinted dark)
    canvas.drawCircle(
      Offset(cx, cy),
      s / 2,
      Paint()..color = Color.lerp(Colors.black, config.jacketColor, 0.18) ?? Colors.black,
    );

    // Proportions (all as fractions of s)
    final headR  = s * 0.135;
    final headCY = cy - s * 0.22 + bob;
    final torsoT = headCY + headR + s * 0.012;
    final torsoH = s * 0.205;
    final torsoW = s * 0.190;
    final torsoB = torsoT + torsoH;
    final armLen = s * 0.140;
    final legLen = s * 0.155;
    final limbW  = s * 0.065;
    final legHX  = torsoW * 0.28;
    final armShX = torsoW * 0.52;
    final armShY = torsoT + s * 0.025;

    // Back leg (opposite swing to front)
    _leg(canvas, cx + legHX, torsoB, -legSwg, legLen, limbW, s);

    // Torso (jacket color)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, (torsoT + torsoB) / 2),
          width: torsoW, height: torsoH,
        ),
        Radius.circular(s * 0.036),
      ),
      Paint()..color = config.jacketColor,
    );

    // Front leg
    _leg(canvas, cx - legHX, torsoB, legSwg, legLen, limbW, s);

    // Arms (drawn after torso so they appear over it)
    _arm(canvas, cx + armShX, armShY,  armSwg, armLen, limbW * 0.82);
    _arm(canvas, cx - armShX, armShY, -armSwg, armLen, limbW * 0.82);

    // Head
    canvas.drawCircle(Offset(cx, headCY), headR, Paint()..color = _kSkin);

    // Hair (drawn over head)
    _hair(canvas, cx, headCY, headR, config.hairIndex, s);

    // Eyes (only at sizes large enough to be meaningful)
    if (s >= 30) _eyes(canvas, cx, headCY, headR, config.eyesIndex);
  }

  void _arm(Canvas c, double ox, double oy, double angle, double len, double w) {
    final p = Paint()
      ..color = config.jacketColor.withValues(alpha: 0.90)
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final elbow = Offset(ox + math.sin(angle) * len, oy + math.cos(angle) * len);
    c.drawLine(Offset(ox, oy), elbow, p);

    final foreAngle = angle * 0.2 + (angle >= 0 ? 0.50 : -0.50);
    c.drawLine(elbow, Offset(
      elbow.dx + math.sin(foreAngle) * len * 0.78,
      elbow.dy + math.cos(foreAngle) * len * 0.78,
    ), p);
  }

  void _leg(Canvas c, double ox, double oy, double angle, double len, double w, double s) {
    final pPants = Paint()
      ..color = config.pantsColor
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final knee = Offset(ox + math.sin(angle) * len, oy + math.cos(angle) * len);
    c.drawLine(Offset(ox, oy), knee, pPants);

    final shinAngle = angle * 0.35 + (angle >= 0 ? 0.38 : -0.08);
    final ankle = Offset(
      knee.dx + math.sin(shinAngle) * len * 0.84,
      knee.dy + math.cos(shinAngle) * len * 0.84,
    );
    c.drawLine(knee, ankle, pPants);

    // Shoe
    c.drawLine(ankle, Offset(
      ankle.dx + math.sin(angle * 0.2 + 0.15) * s * 0.075,
      ankle.dy,
    ), Paint()
      ..color = config.shoesColor
      ..strokeWidth = w * 0.85
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke,
    );
  }

  void _hair(Canvas c, double cx, double cy, double r, int idx, double s) {
    switch (idx) {
      case 1: // Bandana — red stripe across upper head
        c.save();
        c.clipRect(Rect.fromLTWH(cx - r - 2, cy - r - 2, (r + 2) * 2, r + 2));
        c.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
          -math.pi, math.pi,
          false,
          Paint()
            ..color = const Color(0xFFD32F2F)
            ..strokeWidth = r * 0.28
            ..style = PaintingStyle.stroke,
        );
        c.restore();
        break;

      case 2: // Gorra — cap body + brim
        c.drawArc(
          Rect.fromCircle(center: Offset(cx, cy - r * 0.08), radius: r * 1.07),
          math.pi * 1.05, math.pi * 0.90,
          true,
          Paint()..color = const Color(0xFF1A237E),
        );
        c.drawLine(
          Offset(cx - r * 0.95, cy - r * 0.08),
          Offset(cx + r * 1.44, cy - r * 0.08),
          Paint()
            ..color = const Color(0xFF0D47A1)
            ..strokeWidth = r * 0.17
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
        break;

      case 3: // Afro — large puff, then re-draw face
        c.drawCircle(Offset(cx, cy - r * 0.22), r * 1.18, Paint()..color = const Color(0xFF3E2723));
        c.drawCircle(Offset(cx, cy + r * 0.05), r * 0.83, Paint()..color = _kSkin);
        break;

      case 4: // Mohicano — five red spikes
        final moPaint = Paint()..color = const Color(0xFFE53935);
        for (int i = -2; i <= 2; i++) {
          final bx  = cx + i * r * 0.22;
          final spH = r * 0.56 + (2 - i.abs()) * r * 0.21;
          final path = Path()
            ..moveTo(bx - r * 0.12, cy - r * 0.52)
            ..lineTo(bx + r * 0.12, cy - r * 0.52)
            ..lineTo(bx, cy - r * 0.52 - spH)
            ..close();
          c.drawPath(path, moPaint);
        }
        break;

      default: // Corto (0) — dark cap on top half of head
        c.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
          math.pi * 1.02, math.pi * 0.96,
          true,
          Paint()..color = const Color(0xFF4E342E),
        );
        break;
    }
  }

  void _eyes(Canvas c, double cx, double cy, double r, int idx) {
    final ey = cy - r * 0.08;
    final ex = r * 0.35;

    switch (idx) {
      case 2: // Gafas sol — dark bar
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, ey), width: r * 1.26, height: r * 0.30),
            Radius.circular(r * 0.07),
          ),
          Paint()..color = Colors.black87,
        );
        break;

      case 1: // Intenso — sharp with glint
        for (final dx in [-ex, ex]) {
          c.drawCircle(Offset(cx + dx, ey), r * 0.165, Paint()..color = Colors.black87);
          c.drawCircle(
            Offset(cx + dx + r * 0.05, ey - r * 0.05),
            r * 0.052,
            Paint()..color = Colors.white54,
          );
        }
        break;

      default: // Normal
        for (final dx in [-ex, ex]) {
          c.drawCircle(Offset(cx + dx, ey), r * 0.14, Paint()..color = Colors.black87);
        }
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
