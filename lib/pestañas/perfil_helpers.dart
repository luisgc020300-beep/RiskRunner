// lib/pestañas/perfil_helpers.dart
// Clases auxiliares de PerfilScreen extraídas para reducir el tamaño del archivo principal.
part of 'perfil_screen.dart';

// ── Contador animado ──────────────────────────────────────────────────────────

class _AnimatedCounter extends StatefulWidget {
  final double value;
  final int decimals;
  final TextStyle style;
  final Duration duration;

  const _AnimatedCounter({
    required this.value,
    required this.style,
    this.decimals = 0,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<_AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<_AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _prevValue = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween<double>(begin: 0, end: widget.value).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    if (widget.value > 0) _ctrl.forward();
  }

  @override
  void didUpdateWidget(_AnimatedCounter old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _anim = Tween<double>(begin: _prevValue, end: widget.value).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _ctrl.forward(from: 0);
    }
    _prevValue = widget.value;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          final val = _anim.value;
          final text = widget.decimals > 0
              ? val.toStringAsFixed(widget.decimals)
              : val.toInt().toString();
          return Text(text, style: widget.style);
        },
      );
}

// ── Panel genérico ────────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  final Color accent;
  final String label;
  final IconData icon;
  final Widget child;
  const _Panel({required this.accent, required this.label, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = _PP.of(context);
    return Container(
      decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: accent.withValues(alpha: 0.12)))),
          child: Row(children: [
            Container(
                width: 2,
                height: 13,
                decoration: BoxDecoration(
                    color: p.border2, borderRadius: BorderRadius.circular(1))),
            const SizedBox(width: 9),
            Icon(icon, color: p.muted, size: 11),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: p.dim,
                    letterSpacing: 2.5)),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(18), child: child),
      ]),
    );
  }
}

// ── Painters ──────────────────────────────────────────────────────────────────

class _RachaGaugePainter extends CustomPainter {
  final double progress, pulse;
  final Color accent;
  final bool activa;
  _RachaGaugePainter(
      {required this.progress,
      required this.pulse,
      required this.accent,
      required this.activa});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final startAngle = -math.pi * 0.75;
    final sweepTotal = math.pi * 1.5;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        startAngle,
        sweepTotal,
        false,
        Paint()
          ..color = const Color(0xFF1A1A1A)
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
    if (progress > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          startAngle,
          sweepTotal * progress,
          false,
          Paint()
            ..color = accent
            ..strokeWidth = 5
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round);
    }
    final dotPaint = Paint()
      ..color = accent.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    for (final angle in [startAngle, startAngle + sweepTotal]) {
      canvas.drawCircle(
          Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle)),
          1.5,
          dotPaint);
    }
  }

  @override
  bool shouldRepaint(_RachaGaugePainter o) =>
      o.progress != progress || o.pulse != pulse || o.accent != accent;
}

class _LoaderPainter extends CustomPainter {
  final Color accent;
  final double progress, pulse;
  _LoaderPainter({required this.accent, required this.progress, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(
          c,
          7.0 * i * 1.1,
          Paint()
            ..color = accent.withValues(alpha: 0.03 + 0.015 * pulse * (4 - i))
            ..strokeWidth = 0.6
            ..style = PaintingStyle.stroke);
    }
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: 18),
        progress * 2 * math.pi,
        1.2,
        false,
        Paint()
          ..color = accent
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_LoaderPainter o) =>
      o.progress != progress || o.pulse != pulse;
}

// ── Modelo hito ───────────────────────────────────────────────────────────────

class _Hito {
  final String label;
  final IconData icon;
  final Color color;
  final bool unlocked;
  const _Hito(this.label, this.icon, this.color, this.unlocked);
}

// ── Botón de foto ─────────────────────────────────────────────────────────────

class _BotonFoto extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  const _BotonFoto(
      {required this.icon,
      required this.label,
      required this.accent,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = _PP.of(context);
    return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.18))),
          child: Column(children: [
            Icon(icon, color: accent, size: 22),
            const SizedBox(height: 8),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: p.dim))
          ]),
        ));
  }
}
