// lib/widgets/premium_gate.dart
//
// ══════════════════════════════════════════════════════════════════════════════
//  RUNNER RISK — PremiumGate
//
//  Widget que envuelve cualquier feature premium.
//  Si el usuario no tiene premium → muestra overlay con candado y abre paywall.
//  Si tiene premium → renderiza el hijo normalmente.
//
//  USO:
//    PremiumGate(
//      feature: 'Radar de operativos',
//      child: RadarWidget(),
//    )
//
//  También puedes verificar de forma imperativa:
//    if (!PremiumGate.check(context, feature: 'Narrador')) return;
// ══════════════════════════════════════════════════════════════════════════════

import 'package:RiskRunner/pesta%C3%B1as/paywall_screen.dart';
import 'package:flutter/material.dart';
import '../services/subscription_service.dart';

// =============================================================================
// WIDGET DECLARATIVO
// =============================================================================

class PremiumGate extends StatelessWidget {
  final Widget child;
  final String feature;           // Nombre del feature para mostrar en paywall
  final Widget? lockedPlaceholder; // Placeholder custom (opcional)
  final bool showLockOverlay;     // Si false, solo bloquea el tap

  const PremiumGate({
    super.key,
    required this.child,
    required this.feature,
    this.lockedPlaceholder,
    this.showLockOverlay = true,
  });

  // Verificación imperativa — usar en onPressed, etc.
  static Future<bool> check(
    BuildContext context, {
    required String feature,
  }) async {
    if (SubscriptionService.currentStatus.isPremium) return true;
    final comprado = await PaywallScreen.mostrar(context, featureOrigen: feature);
    return comprado;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SubscriptionStatus>(
      stream: SubscriptionService.statusStream,
      initialData: SubscriptionService.currentStatus,
      builder: (context, snapshot) {
        final isPremium = snapshot.data?.isPremium ?? false;

        if (isPremium) return child;

        if (!showLockOverlay) {
          return GestureDetector(
            onTap: () => PaywallScreen.mostrar(context, featureOrigen: feature),
            child: AbsorbPointer(child: child),
          );
        }

        return lockedPlaceholder != null
            ? GestureDetector(
                onTap: () => PaywallScreen.mostrar(context, featureOrigen: feature),
                child: lockedPlaceholder!,
              )
            : _LockedOverlay(
                feature: feature,
                child: child,
              );
      },
    );
  }
}

// =============================================================================
// OVERLAY DE CANDADO
// =============================================================================

class _LockedOverlay extends StatelessWidget {
  final String feature;
  final Widget child;

  const _LockedOverlay({required this.feature, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => PaywallScreen.mostrar(context, featureOrigen: feature),
      child: Stack(children: [
        // El hijo se renderiza pero bloqueado
        AbsorbPointer(
          child: Opacity(opacity: 0.3, child: child),
        ),

        // Overlay con candado
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF090807).withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFCAAA6C).withOpacity(0.3),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCC7C3A).withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFCC7C3A).withOpacity(0.4),
                    ),
                  ),
                  child: const Icon(Icons.lock_rounded,
                      color: Color(0xFFCC7C3A), size: 22),
                ),
                const SizedBox(height: 10),
                const Text('PREMIUM',
                  style: TextStyle(
                    color: Color(0xFFDECA46),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Toca para desbloquear',
                  style: TextStyle(
                    color: const Color(0xFFCAAA6C).withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
// BADGE PREMIUM — para mostrar en perfil, leaderboard, etc.
// =============================================================================

class PremiumBadge extends StatelessWidget {
  final double size;
  final bool showLabel;

  const PremiumBadge({super.key, this.size = 16, this.showLabel = false});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SubscriptionStatus>(
      stream: SubscriptionService.statusStream,
      initialData: SubscriptionService.currentStatus,
      builder: (context, snap) {
        if (!(snap.data?.isPremium ?? false)) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.military_tech_rounded,
                color: const Color(0xFFDECA46), size: size),
            if (showLabel) ...[
              const SizedBox(width: 4),
              Text('PREMIUM',
                style: TextStyle(
                  color: const Color(0xFFDECA46),
                  fontSize: size * 0.65,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                )),
            ],
          ],
        );
      },
    );
  }
}

// =============================================================================
// BANNER PREMIUM — tira compacta para secciones bloqueadas
// =============================================================================

class PremiumBanner extends StatelessWidget {
  final String texto;
  final String? subtexto;

  const PremiumBanner({
    super.key,
    required this.texto,
    this.subtexto,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => PaywallScreen.mostrar(context, featureOrigen: texto),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1C1410), Color(0xFF2A1E0E)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFCC7C3A).withOpacity(0.4)),
        ),
        child: Row(children: [
          const Text('👑', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texto,
                  style: const TextStyle(
                    color: Color(0xFFEAD9AA),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  )),
                if (subtexto != null) ...[
                  const SizedBox(height: 2),
                  Text(subtexto!,
                    style: const TextStyle(
                      color: Color(0xFF8C7242), fontSize: 11)),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFCC7C3A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('VER',
              style: TextStyle(
                color: Color(0xFF090807),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              )),
          ),
        ]),
      ),
    );
  }
}