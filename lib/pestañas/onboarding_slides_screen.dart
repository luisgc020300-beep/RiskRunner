import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:RiskRunner/services/onboarding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// PALETA (coherente con ResumenScreen y ConquistaOverlay)
// =============================================================================
const _kBg       = Color(0xFFE8E8ED);
const _kSurface  = Color(0xFFFFFFFF);
const _kBorder   = Color(0xFFC6C6C8);
const _kDim      = Color(0xFF8E8E93);
const _kAccent   = Color(0xFFE02020);

// =============================================================================
// MODELO DE SLIDE
// =============================================================================
class _SlideData {
  final String tag;          // Ej: "MISIÓN 01"
  final String headline;     // Línea grande
  final String sub;          // Descripción
  final String emoji;        // Icono grande
  final Color accentColor;
  final String mechanic;     // Qué mecánica se desbloquea

  const _SlideData({
    required this.tag,
    required this.headline,
    required this.sub,
    required this.emoji,
    required this.accentColor,
    required this.mechanic,
  });
}

const _slides = [
  _SlideData(
    tag: 'BIENVENIDO A RUNNER RISK',
    headline: 'La ciudad\nes tuya.',
    sub: 'Cada kilómetro que corres conquista territorio real. Marca el mapa. Defiende lo que es tuyo.',
    emoji: '🏙️',
    accentColor: _kAccent,
    mechanic: 'CONQUISTA',
  ),
  _SlideData(
    tag: 'MECÁNICA 01',
    headline: 'Corre.\nConquista.',
    sub: 'Tu ruta de hoy se convierte en zona tuya en el mapa. Cuanto más corres, más territorio controlas.',
    emoji: '🗺️',
    accentColor: Color(0xFFFF7B1A),
    mechanic: 'RUN → ZONA',
  ),
  _SlideData(
    tag: 'MECÁNICA 02',
    headline: 'Las zonas\nse deterioran.',
    sub: 'Si no vuelves a correr por tu territorio en 5 días, empieza a desvanecerse. En 10 días, cualquiera puede invadirlo.',
    emoji: '⏳',
    accentColor: Color(0xFFEAB308),
    mechanic: 'DETERIORO',
  ),
  _SlideData(
    tag: 'MECÁNICA 03',
    headline: 'Invade.\nSé invadido.',
    sub: 'Otros runners compiten por el mismo mapa. Si corren por tu zona deteriorada, te la roban. Tú puedes hacer lo mismo.',
    emoji: '⚔️',
    accentColor: Color(0xFFEF4444),
    mechanic: 'INVASIÓN',
  ),
  _SlideData(
    tag: 'PRIMER OBJETIVO',
    headline: 'Empieza\nahora.',
    sub: 'Tu primera carrera define tu color de territorio. Sal a correr y marca el mapa por primera vez.',
    emoji: '🚀',
    accentColor: Color(0xFF22C55E),
    mechanic: 'PRIMER RUN',
  ),
];

// =============================================================================
// PANTALLA PRINCIPAL
// =============================================================================
class OnboardingSlidesScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingSlidesScreen({super.key, required this.onComplete});

  @override
  State<OnboardingSlidesScreen> createState() => _OnboardingSlidesScreenState();
}

class _OnboardingSlidesScreenState extends State<OnboardingSlidesScreen>
    with TickerProviderStateMixin {

  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  // Por cada slide: animación de entrada
  late AnimationController _slideAnimCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideUpAnim;
  late Animation<double> _emojiScaleAnim;

  // Pulso continuo para el indicador
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  // Partículas de fondo
  late AnimationController _particleCtrl;

  @override
  void initState() {
    super.initState();

    _slideAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _slideAnimCtrl, curve: Curves.easeOut);
    _slideUpAnim = Tween<double>(begin: 40, end: 0).animate(
        CurvedAnimation(parent: _slideAnimCtrl, curve: Curves.easeOutCubic));
    _emojiScaleAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _slideAnimCtrl,
            curve: const Interval(0.0, 0.6, curve: Curves.elasticOut)));

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.3, end: 0.9).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _particleCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))
      ..repeat();

    _slideAnimCtrl.forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _slideAnimCtrl.dispose();
    _pulseCtrl.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  void _nextPage() {
    HapticFeedback.lightImpact();
    if (_currentPage < _slides.length - 1) {
      _slideAnimCtrl.reset();
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutCubic);
    } else {
      _completar();
    }
  }

  void _skipToLast() {
    HapticFeedback.lightImpact();
    _slideAnimCtrl.reset();
    _pageCtrl.animateToPage(_slides.length - 1,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic);
  }

  Future<void> _completar() async {
    HapticFeedback.mediumImpact();
    await OnboardingService.marcarSlidesVistos();
    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(children: [

        // Fondo animado con partículas
        Positioned.fill(child: AnimatedBuilder(
          animation: _particleCtrl,
          builder: (_, __) => CustomPaint(
            painter: _ParticleBg(
              progress: _particleCtrl.value,
              accentColor: _slides[_currentPage].accentColor,
            ),
          ),
        )),

        // PageView de slides
        PageView.builder(
          controller: _pageCtrl,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (i) {
            setState(() => _currentPage = i);
            _slideAnimCtrl.forward(from: 0);
          },
          itemCount: _slides.length,
          itemBuilder: (_, i) => _buildSlide(_slides[i]),
        ),

        // HUD superior: skip + progreso
        SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(children: [
            // Indicadores de punto
            Row(children: List.generate(_slides.length, (i) =>
              AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) =>
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: i == _currentPage ? 24 : 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i == _currentPage
                        ? _slides[_currentPage].accentColor
                        : _kBorder,
                    boxShadow: i == _currentPage ? [BoxShadow(
                        color: _slides[_currentPage].accentColor
                            .withValues(alpha: _pulse.value * 0.7),
                        blurRadius: 8)] : [],
                  ),
                ),
              ),
            )),
            const Spacer(),
            // Skip (solo si no es el último)
            if (_currentPage < _slides.length - 1)
              GestureDetector(
                onTap: _skipToLast,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kBorder),
                  ),
                  child: const Text('SALTAR', style: TextStyle(
                      color: _kDim, fontSize: 10,
                      fontWeight: FontWeight.w800, letterSpacing: 2)),
                ),
              ),
          ]),
        )),

        // Botón de acción (inferior)
        Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: _buildBoton(),
          ),
        )),
      ]),
    );
  }

  Widget _buildSlide(_SlideData slide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 100, 28, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Emoji con scale elástico
          AnimatedBuilder(animation: _slideAnimCtrl, builder: (_, __) =>
            Transform.scale(
              scale: _emojiScaleAnim.value,
              alignment: Alignment.centerLeft,
              child: Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  color: slide.accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: slide.accentColor.withValues(alpha: 0.25)),
                  boxShadow: [BoxShadow(
                      color: slide.accentColor.withValues(alpha: 0.15),
                      blurRadius: 30)],
                ),
                child: Center(child: Text(slide.emoji,
                    style: const TextStyle(fontSize: 40))),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Tag
          AnimatedBuilder(animation: _slideAnimCtrl, builder: (_, __) =>
            Opacity(opacity: _fadeAnim.value,
              child: Row(children: [
                Container(width: 3, height: 12, decoration: BoxDecoration(
                    color: slide.accentColor, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text(slide.tag, style: TextStyle(
                    color: slide.accentColor, fontSize: 9,
                    fontWeight: FontWeight.w900, letterSpacing: 3)),
                const SizedBox(width: 12),
                // Badge de mecánica
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: slide.accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: slide.accentColor.withValues(alpha: 0.2)),
                  ),
                  child: Text(slide.mechanic, style: TextStyle(
                      color: slide.accentColor.withValues(alpha: 0.8),
                      fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 16),

          // Headline grande
          AnimatedBuilder(animation: _slideAnimCtrl, builder: (_, __) =>
            Opacity(opacity: _fadeAnim.value,
              child: Transform.translate(
                offset: Offset(0, _slideUpAnim.value),
                child: Text(slide.headline,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    letterSpacing: -1.5,
                    shadows: [
                      Shadow(color: slide.accentColor.withValues(alpha: 0.3),
                          blurRadius: 30),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Descripción
          AnimatedBuilder(animation: _slideAnimCtrl, builder: (_, __) =>
            Opacity(opacity: (_fadeAnim.value - 0.3).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, _slideUpAnim.value * 1.3),
                child: Text(slide.sub,
                  style: const TextStyle(
                    color: _kDim,
                    fontSize: 16,
                    height: 1.6,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),

          // Separador decorativo
          const SizedBox(height: 32),
          AnimatedBuilder(animation: _slideAnimCtrl, builder: (_, __) =>
            Opacity(opacity: _fadeAnim.value,
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  width: 40, height: 1,
                  color: slide.accentColor.withValues(alpha: 0.4)),
                const SizedBox(width: 8),
                Text('${_currentPage + 1} / ${_slides.length}',
                    style: TextStyle(color: slide.accentColor.withValues(alpha: 0.5),
                        fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoton() {
    final slide  = _slides[_currentPage];
    final ultimo = _currentPage == _slides.length - 1;
    return GestureDetector(
      onTap: _nextPage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: ultimo ? slide.accentColor : Colors.transparent,
          border: Border.all(
              color: slide.accentColor.withValues(alpha: ultimo ? 1.0 : 0.5),
              width: 1.5),
          boxShadow: ultimo ? [BoxShadow(
              color: slide.accentColor.withValues(alpha: 0.35),
              blurRadius: 24, offset: const Offset(0, 8))] : [],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(
            ultimo ? 'EMPEZAR A CONQUISTAR' : 'SIGUIENTE',
            style: TextStyle(
              color: ultimo ? Colors.black : slide.accentColor,
              fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2.5,
            ),
          ),
          const SizedBox(width: 10),
          Icon(ultimo ? Icons.flag_rounded : Icons.arrow_forward_rounded,
              color: ultimo ? Colors.black : slide.accentColor, size: 16),
        ]),
      ),
    );
  }
}

// =============================================================================
// PAINTER: Fondo con partículas flotantes
// =============================================================================
class _ParticleBg extends CustomPainter {
  final double progress;
  final Color accentColor;

  static final _rng = math.Random(42);
  static late final List<_Particle> _particles = List.generate(28, (_) => _Particle(
    x:     _rng.nextDouble(),
    y:     _rng.nextDouble(),
    size:  _rng.nextDouble() * 2.5 + 0.5,
    speed: _rng.nextDouble() * 0.008 + 0.002,
    phase: _rng.nextDouble(),
  ));

  const _ParticleBg({required this.progress, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    // Gradiente radial de fondo
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.6, -0.8), radius: 1.4,
        colors: [accentColor.withValues(alpha: 0.07), Colors.transparent],
      ).createShader(rect));

    // Grid de puntos
    final dotPaint = Paint()..color = accentColor.withValues(alpha: 0.045);
    const spacing = 40.0;
    for (double x = spacing / 2; x < size.width; x += spacing) {
      for (double y = spacing / 2; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }

    // Partículas flotantes
    for (final p in _particles) {
      final currentY = (p.y - progress * p.speed * 20) % 1.0;
      final opacity  = (math.sin((currentY + p.phase) * math.pi * 2) * 0.5 + 0.5) * 0.35;
      canvas.drawCircle(
        Offset(p.x * size.width, currentY * size.height),
        p.size,
        Paint()..color = accentColor.withValues(alpha: opacity),
      );
    }

    // Línea diagonal decorativa
    final lp = Paint()..color = accentColor.withValues(alpha: 0.04)..strokeWidth = 1;
    for (int i = 0; i < 8; i++) {
      final o = i * 24.0;
      canvas.drawLine(Offset(o, 0), Offset(0, o), lp);
    }
  }

  @override
  bool shouldRepaint(_ParticleBg old) =>
      old.progress != progress || old.accentColor != accentColor;
}

class _Particle {
  final double x, y, size, speed, phase;
  const _Particle({
    required this.x, required this.y,
    required this.size, required this.speed, required this.phase,
  });
}