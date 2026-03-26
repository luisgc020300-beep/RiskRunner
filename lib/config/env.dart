// lib/config/env.dart
//
// ══════════════════════════════════════════════════════════════════════════════
//  RUNNER RISK — Configuración de claves
//
//  IMPORTANTE:
//    - Este archivo está en .gitignore → nunca se sube a GitHub
//    - Si alguien clona el repo, debe pedirte este archivo aparte
// ══════════════════════════════════════════════════════════════════════════════

class Env {
  Env._();

  // ==========================================================================
  // ENTORNO
  // ==========================================================================

  /// Cambia a false antes de publicar en producción
  static const bool isDebug = true;

  // ==========================================================================
  // REVENUECAT
  // ⚠️  Ahora mismo usas el Test Store. Cuando crees las apps reales de
  //     Android e iOS en RevenueCat, reemplaza estas claves por las de producción.
  // ==========================================================================

  static const String revenueCatAndroid = 'test_uPkAErvOEhdfmFYunHaZuAVynlc';
  static const String revenueCatIOS     = 'test_uPkAErvOEhdfmFYunHaZuAVynlc';

  // ==========================================================================
  // MAPBOX
  // ==========================================================================

  static const String mapboxPublicToken =
      'pk.eyJ1IjoibHVpaXNnb29tZXp6MSIsImEiOiJjbW1mNDVoajkwNGNyMnBzNTBiaXNrMm5pIn0.gzN772_GMDx55owCXwsozA';

  static const String mapboxStyleId = 'luiisgoomezz1/cmmdzh1aj00f501r68crag5gv';

  // ==========================================================================
  // REVENUECAT — identificadores de productos
  // Deben coincidir exactamente con los que configures en App Store / Play Store
  // ==========================================================================

  static const String entitlementPremium = 'premium';
  static const String productMonthly     = 'riskrunner_premium_monthly';
  static const String productAnnual      = 'riskrunner_premium_annual';
}