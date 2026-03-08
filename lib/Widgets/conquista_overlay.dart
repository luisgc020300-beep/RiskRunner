// ══════════════════════════════════════════════════════════════
//  conquista_overlay.dart
//  Coloca este archivo en: lib/widgets/conquista_overlay.dart
//
//  Uso:
//    // Conquista normal:
//    await ConquistaOverlay.mostrar(context);
//
//    // Invasión (robaste territorio a alguien):
//    await ConquistaOverlay.mostrar(
//      context,
//      esInvasion: true,
//      nombreTerritorio: 'Parque del Retiro',
//    );
// ══════════════════════════════════════════════════════════════

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// ENTRY POINT PÚBLICO
// =============================================================================

class ConquistaOverlay {
  static Future<void> mostrar(
    BuildContext context, {
    bool esInvasion = false,
    String? nombreTerritorio,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, __) => _ConquistaWidget(
        esInvasion: esInvasion,
        nombreTerritorio: nombreTerritorio,
      ),
    );
  }
}

// =============================================================================
// WIDGET PRINCIPAL
// =============================================================================

class _ConquistaWidget extends StatefulWidget {
  final bool esInvasion;
  final String? nombreTerritorio;

  const _ConquistaWidget({
    required this.esInvasion,
    this.nombreTerritorio,
  });

  @override
  State<_ConquistaWidget> createState() => _ConquistaWidgetState();
}

class _ConquistaWidgetState extends State<_ConquistaWidget>
    with TickerProviderStateMixin {

  late AnimationController _ondaCtrl;
  late AnimationController _flashCtrl;
  late AnimationController _textCtrl;
  late AnimationController _particleCtrl;
  late AnimationController _exitCtrl;

  late Animation<double> _ondaScale;
  late Animation<double> _ondaOpacity;
  late Animation<double> _flashOpacity;
  late Animation<double> _textScale;
  late Animation<double> _textOpacity;
  late Animation<double> _subtitleOffset;
  late Animation<double> _exitOpacity;

  final List<_Particle> _particles = [];
  final Random _rng = Random();

  Color get _colorPrimario =>
      widget.esInvasion ? Colors.redAccent : Colors.orange;
  Color get _colorSecundario =>
      widget.esInvasion ? const Color(0xFFFF6B00) : const Color(0xFFFFD000);

  @override
  void initState() {
    super.initState();
    _generarParticulas();
    _inicializarAnimaciones();
    _playSecuencia();
  }

  void _inicializarAnimaciones() {
    _ondaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _ondaScale = Tween<double>(begin: 0.0, end: 4.0).animate(
        CurvedAnimation(parent: _ondaCtrl, curve: Curves.easeOut));
    _ondaOpacity = Tween<double>(begin: 0.7, end: 0.0).animate(
        CurvedAnimation(parent: _ondaCtrl, curve: Curves.easeIn));

    _flashCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _flashOpacity = Tween<double>(begin: 0.5, end: 0.0).animate(
        CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut));

    _textCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _textScale = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _textCtrl, curve: Curves.elasticOut));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _textCtrl,
            curve: const Interval(0.0, 0.4, curve: Curves.easeIn)));
    _subtitleOffset = Tween<double>(begin: 24.0, end: 0.0).animate(
        CurvedAnimation(
            parent: _textCtrl,
            curve: const Interval(0.35, 0.85, curve: Curves.easeOut)));

    _particleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));

    _exitCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn));
  }

  Future<void> _playSecuencia() async {
    HapticFeedback.heavyImpact();

    _ondaCtrl.forward();
    _flashCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 160));

    HapticFeedback.mediumImpact();

    _textCtrl.forward();
    _particleCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 1900));

    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 200));

    _exitCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 380));

    if (mounted) Navigator.of(context).pop();
  }

  void _generarParticulas() {
    final coloresInvasion = [
      Colors.redAccent,
      Colors.deepOrangeAccent,
      Colors.orangeAccent,
      Colors.white,
      const Color(0xFFFF6B00),
    ];
    final coloresConquista = [
      Colors.orange,
      const Color(0xFFFFD000),
      Colors.amber,
      Colors.white,
      const Color(0xFFFF8C00),
    ];
    final lista = widget.esInvasion ? coloresInvasion : coloresConquista;

    for (int i = 0; i < 34; i++) {
      _particles.add(_Particle(
        angle: _rng.nextDouble() * 2 * pi,
        speed: 0.2 + _rng.nextDouble() * 0.8,
        size: 4.0 + _rng.nextDouble() * 10.0,
        color: lista[_rng.nextInt(lista.length)],
        delay: _rng.nextDouble() * 0.28,
      ));
    }
  }

  @override
  void dispose() {
    _ondaCtrl.dispose();
    _flashCtrl.dispose();
    _textCtrl.dispose();
    _particleCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return FadeTransition(
      opacity: _exitOpacity,
      child: Material(
        color: Colors.black.withOpacity(0.85),
        child: Stack(
          alignment: Alignment.center,
          children: [

            // ── 1. OLEADA DE COLOR ──────────────────────────────────────
            AnimatedBuilder(
              animation: _ondaCtrl,
              builder: (_, __) => Transform.scale(
                scale: _ondaScale.value,
                child: Container(
                  width: size.width,
                  height: size.width,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _colorPrimario.withOpacity(_ondaOpacity.value),
                  ),
                ),
              ),
            ),

            // ── 2. SEGUNDO ANILLO DESFASADO ─────────────────────────────
            AnimatedBuilder(
              animation: _ondaCtrl,
              builder: (_, __) {
                final p = (_ondaCtrl.value - 0.2).clamp(0.0, 1.0);
                return Transform.scale(
                  scale: p * 3.2,
                  child: Container(
                    width: size.width,
                    height: size.width,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _colorSecundario
                            .withOpacity((1.0 - p).clamp(0.0, 0.45)),
                        width: 3,
                      ),
                    ),
                  ),
                );
              },
            ),

            // ── 3. FLASH BLANCO ─────────────────────────────────────────
            AnimatedBuilder(
              animation: _flashCtrl,
              builder: (_, __) => IgnorePointer(
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.white.withOpacity(_flashOpacity.value),
                ),
              ),
            ),

            // ── 4. PARTÍCULAS ────────────────────────────────────────────
            AnimatedBuilder(
              animation: _particleCtrl,
              builder: (_, __) => CustomPaint(
                size: size,
                painter: _ParticlePainter(
                  particles: _particles,
                  progress: _particleCtrl.value,
                  center: Offset(size.width / 2, size.height / 2),
                ),
              ),
            ),

            // ── 5. TEXTO PRINCIPAL ───────────────────────────────────────
            AnimatedBuilder(
              animation: _textCtrl,
              builder: (_, __) => Opacity(
                opacity: _textOpacity.value,
                child: Transform.scale(
                  scale: _textScale.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      // Icono
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _colorPrimario.withOpacity(0.15),
                          border: Border.all(
                              color: _colorPrimario.withOpacity(0.6),
                              width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: _colorPrimario.withOpacity(0.5),
                              blurRadius: 40,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            widget.esInvasion ? '⚔️' : '🏴',
                            style: const TextStyle(fontSize: 42),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Título
                      Text(
                        widget.esInvasion
                            ? '¡TERRITORIO\nCONQUISTADO!'
                            : '¡TERRITORIO\nASEGURADO!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          height: 1.1,
                          shadows: [
                            Shadow(
                                color: _colorPrimario.withOpacity(0.8),
                                blurRadius: 24),
                            Shadow(
                                color: _colorPrimario.withOpacity(0.4),
                                blurRadius: 48),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Subtítulo
                      Transform.translate(
                        offset: Offset(0, _subtitleOffset.value),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          decoration: BoxDecoration(
                            color: _colorPrimario.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                                color: _colorPrimario.withOpacity(0.4),
                                width: 1),
                          ),
                          child: Text(
                            widget.nombreTerritorio != null
                                ? widget.nombreTerritorio!.toUpperCase()
                                : widget.esInvasion
                                    ? 'INVASIÓN EXITOSA'
                                    : 'ZONA BAJO CONTROL',
                            style: TextStyle(
                              color: _colorPrimario,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Puntos
                      Transform.translate(
                        offset: Offset(0, _subtitleOffset.value * 1.4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt_rounded,
                                color: _colorSecundario, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              widget.esInvasion
                                  ? '+25 puntos de liga'
                                  : '+15 puntos de liga',
                              style: TextStyle(
                                color: _colorSecundario,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MODELO PARTÍCULA
// =============================================================================

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double delay;

  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.delay,
  });
}

// =============================================================================
// PAINTER DE PARTÍCULAS
// =============================================================================

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Offset center;

  _ParticlePainter({
    required this.particles,
    required this.progress,
    required this.center,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = ((progress - p.delay) / (1.0 - p.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final eased = Curves.easeOut.transform(t);
      final maxDist = size.width * 0.52 * p.speed;
      final dist = eased * maxDist;

      final dx = center.dx + cos(p.angle) * dist;
      final dy = center.dy + sin(p.angle) * dist;

      final opacity = t < 0.3
          ? (t / 0.3)
          : (1.0 - ((t - 0.3) / 0.7)).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = p.color.withOpacity(opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      final currentSize = p.size * (1.0 - eased * 0.5);
      canvas.drawCircle(Offset(dx, dy), currentSize / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}