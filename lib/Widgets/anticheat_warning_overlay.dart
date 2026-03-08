import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// PALETA (coherente con el resto de la app)
// =============================================================================
const _kBg      = Color(0xFF060608);
const _kSurface = Color(0xFF0D0D10);
const _kBorder  = Color(0xFF1E1E24);
const _kRed     = Color(0xFFEF4444);
const _kRedDim  = Color(0xFF7F1D1D);

// =============================================================================
// OVERLAY DE AVISO
// =============================================================================

class AntiCheatWarningOverlay {
  /// Muestra el overlay de trampa detectada.
  /// Devuelve true si el usuario acepta cancelar, false si intenta continuar.
  static Future<bool> mostrar(
    BuildContext context, {
    required String motivo,
  }) async {
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    HapticFeedback.heavyImpact();

    final resultado = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, anim, __) => FadeTransition(
          opacity: anim,
          child: _AntiCheatWarningPage(motivo: motivo),
        ),
      ),
    );
    return resultado ?? true;
  }
}

// =============================================================================
// PÁGINA INTERNA
// =============================================================================

class _AntiCheatWarningPage extends StatefulWidget {
  final String motivo;
  const _AntiCheatWarningPage({required this.motivo});

  @override
  State<_AntiCheatWarningPage> createState() => _AntiCheatWarningPageState();
}

class _AntiCheatWarningPageState extends State<_AntiCheatWarningPage>
    with TickerProviderStateMixin {

  late AnimationController _entradaCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _scanCtrl;
  late AnimationController _glitchCtrl;

  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _slideAnim;
  late Animation<double> _pulse;
  late Animation<double> _scan;
  late Animation<double> _glitch;

  @override
  void initState() {
    super.initState();

    _entradaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim  = CurvedAnimation(parent: _entradaCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _entradaCtrl, curve: Curves.easeOutBack));
    _slideAnim = Tween<double>(begin: 40.0, end: 0.0).animate(
        CurvedAnimation(parent: _entradaCtrl, curve: Curves.easeOutCubic));

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _scanCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _scan = CurvedAnimation(parent: _scanCtrl, curve: Curves.linear);

    _glitchCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80))
      ..repeat(reverse: true);
    _glitch = Tween<double>(begin: 0, end: 1).animate(_glitchCtrl);

    _entradaCtrl.forward();

    // Para el glitch después de 800ms
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _glitchCtrl.stop();
    });
  }

  @override
  void dispose() {
    _entradaCtrl.dispose();
    _pulseCtrl.dispose();
    _scanCtrl.dispose();
    _glitchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.92),
      body: Stack(children: [

        // Fondo con scanner y grid
        Positioned.fill(child: AnimatedBuilder(
          animation: _scanCtrl,
          builder: (_, __) => CustomPaint(
            painter: _ScanBg(progress: _scan.value),
          ),
        )),

        SafeArea(child: Center(
          child: AnimatedBuilder(
            animation: _entradaCtrl,
            builder: (_, child) => Opacity(
              opacity: _fadeAnim.value,
              child: Transform.scale(
                scale: _scaleAnim.value,
                child: Transform.translate(
                  offset: Offset(0, _slideAnim.value),
                  child: child,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIcono(),
                  const SizedBox(height: 32),
                  _buildTitulo(),
                  const SizedBox(height: 16),
                  _buildMotivo(),
                  const SizedBox(height: 40),
                  _buildInfoCards(),
                  const SizedBox(height: 40),
                  _buildBoton(),
                ],
              ),
            ),
          ),
        )),
      ]),
    );
  }

  Widget _buildIcono() {
    return AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) =>
      Stack(alignment: Alignment.center, children: [
        // Anillos pulsantes
        Container(width: 120, height: 120,
          decoration: BoxDecoration(shape: BoxShape.circle,
              border: Border.all(
                  color: _kRed.withValues(alpha: _pulse.value * 0.2),
                  width: 1))),
        Container(width: 96, height: 96,
          decoration: BoxDecoration(shape: BoxShape.circle,
              border: Border.all(
                  color: _kRed.withValues(alpha: _pulse.value * 0.35),
                  width: 1.5))),
        // Icono central
        Container(width: 72, height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kRed.withValues(alpha: 0.1),
            border: Border.all(color: _kRed.withValues(alpha: 0.6), width: 2),
            boxShadow: [BoxShadow(
                color: _kRed.withValues(alpha: _pulse.value * 0.4),
                blurRadius: 20)],
          ),
          child: const Center(child: Text('⚠️',
              style: TextStyle(fontSize: 30)))),
      ]),
    );
  }

  Widget _buildTitulo() {
    return AnimatedBuilder(animation: _glitchCtrl, builder: (_, __) {
      final s = (_glitch.value > 0.5) ? 2.0 : 0.0;
      return Stack(alignment: Alignment.center, children: [
        Transform.translate(offset: Offset(s, 0),
          child: Text('TRAMPA DETECTADA', style: TextStyle(
              color: _kRed.withValues(alpha: 0.4), fontSize: 26,
              fontWeight: FontWeight.w900, letterSpacing: 2))),
        const Text('TRAMPA DETECTADA', style: TextStyle(
            color: Colors.white, fontSize: 26,
            fontWeight: FontWeight.w900, letterSpacing: 2)),
      ]);
    });
  }

  Widget _buildMotivo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kRed.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 3, height: 14, decoration: BoxDecoration(
            color: _kRed, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Flexible(child: Text(widget.motivo, textAlign: TextAlign.center,
            style: TextStyle(color: _kRed.withValues(alpha: 0.8),
                fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
      ]),
    );
  }

  Widget _buildInfoCards() {
    return Column(children: [
      _infoCard('🗺️', 'SESIÓN CANCELADA',
          'Esta carrera no contará en el mapa. Los territorios no se han modificado.'),
      const SizedBox(height: 10),
      _infoCard('📋', 'REGISTRO GUARDADO',
          'La actividad ha sido marcada para revisión. Las infracciones repetidas pueden resultar en suspensión.'),
      const SizedBox(height: 10),
      _infoCard('📍', 'GPS REAL REQUERIDO',
          'Runner Risk requiere ubicación real. Desactiva cualquier app de ubicación falsa y vuelve a intentarlo.'),
    ]);
  }

  Widget _infoCard(String emoji, String titulo, String sub) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(
                color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(
                color: Color(0xFF666680), fontSize: 12, height: 1.45)),
          ])),
        ]),
      );

  Widget _buildBoton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(true);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: _kRed,
          boxShadow: [BoxShadow(
              color: _kRed.withValues(alpha: 0.35),
              blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.logout_rounded, color: Colors.white, size: 18),
          SizedBox(width: 10),
          Text('ENTENDIDO — SALIR', style: TextStyle(
              color: Colors.white, fontSize: 13,
              fontWeight: FontWeight.w900, letterSpacing: 2.5)),
        ]),
      ),
    );
  }
}

// =============================================================================
// PAINTER: scanner de fondo
// =============================================================================

class _ScanBg extends CustomPainter {
  final double progress;
  const _ScanBg({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // Grid rojo tenue
    final gridPaint = Paint()
      ..color = _kRed.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Línea de scan
    final scanY = size.height * progress;
    final scanGrad = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [
          _kRed.withValues(alpha: 0.0),
          _kRed.withValues(alpha: 0.3),
          _kRed.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, scanY - 40, size.width, 80));

    canvas.drawRect(
        Rect.fromLTWH(0, scanY - 40, size.width, 80), scanGrad);

    // Gradiente radial rojo desde el centro
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, Paint()
      ..shader = RadialGradient(
        center: Alignment.center, radius: 1.0,
        colors: [
          _kRed.withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(_ScanBg old) => old.progress != progress;
}