// lib/pestañas/onboarding_gps_gate.dart
//
// Pantalla one-shot de permiso GPS, mostrada UNA vez tras los slides de
// onboarding. Aparece solo si el permiso nunca fue solicitado.
// El resultado (granted / denied / skipped) se registra en Analytics.

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_error.dart';
import '../theme/app_colors.dart';
import '../widgets/operative_bg.dart';

class OnboardingGpsGate extends StatefulWidget {
  final VoidCallback onContinue;
  const OnboardingGpsGate({super.key, required this.onContinue});

  @override
  State<OnboardingGpsGate> createState() => _OnboardingGpsGateState();
}

class _OnboardingGpsGateState extends State<OnboardingGpsGate>
    with SingleTickerProviderStateMixin {

  bool _loading = false;
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideAnim = Tween<double>(begin: 24, end: 0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static Future<void> _marcarMostrada() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gps_gate_shown', true);
  }

  Future<void> _activar() async {
    setState(() => _loading = true);
    try {
      final result = await Geolocator.requestPermission();
      await _marcarMostrada();
      AppError.log('gps_gate:activar result=${result.name}');
      FirebaseAnalytics.instance.logEvent(
        name: 'onboarding_gps_permission',
        parameters: {'result': result.name},
      );
    } catch (e, st) {
      AppError.record(e, st, reason: 'gps_gate_request_permission');
    }
    if (mounted) widget.onContinue();
  }

  Future<void> _saltar() async {
    AppError.log('gps_gate:skip');
    await _marcarMostrada();
    FirebaseAnalytics.instance.logEvent(
      name: 'onboarding_gps_permission',
      parameters: {'result': 'skipped'},
    );
    if (mounted) widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090807),
      body: Stack(children: [

        // Fondo táctico
        const Positioned.fill(
          child: CustomPaint(painter: OperativeBgPainter()),
        ),

        SafeArea(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => FadeTransition(
              opacity: _fadeAnim,
              child: Transform.translate(
                offset: Offset(0, _slideAnim.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [

                      const Spacer(flex: 2),

                      // Icono
                      Container(
                        width: 96, height: 96,
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: AppColors.red.withValues(alpha: 0.30),
                              width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.red.withValues(alpha: 0.20),
                              blurRadius: 32,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.location_on_rounded,
                            color: AppColors.red, size: 44),
                      ),

                      const SizedBox(height: 40),

                      // Eyebrow
                      Text(
                        'PERMISO DE UBICACIÓN',
                        style: GoogleFonts.rajdhani(
                          color: AppColors.red.withValues(alpha: 0.80),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.5,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Título
                      Text(
                        'Activa tu\nubicación',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.rajdhani(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                          letterSpacing: 0.5,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Descripción
                      Text(
                        'RiskRunner mapea el territorio que conquistas en tiempo real mientras corres. Sin tu ubicación, no hay conquista.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF8E8E93),
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Detalle técnico
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.lock_outline_rounded,
                              color: Color(0xFF48484A), size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Solo se usa durante la carrera. No se comparte con terceros.',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF636366),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ]),
                      ),

                      const Spacer(flex: 2),

                      // CTA principal
                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: _loading ? null : _activar,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            decoration: BoxDecoration(
                              color: AppColors.red,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.red.withValues(alpha: 0.35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: _loading
                                ? const Center(
                                    child: SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                            Colors.white),
                                      ),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.location_on_rounded,
                                          color: Colors.white, size: 18),
                                      const SizedBox(width: 10),
                                      Text(
                                        'ACTIVAR UBICACIÓN',
                                        style: GoogleFonts.rajdhani(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Skip
                      GestureDetector(
                        onTap: _saltar,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Quizás más tarde',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF636366),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
