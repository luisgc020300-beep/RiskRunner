// lib/core/flavor_config.dart
//
// Configuración por entorno. Se inyecta en build time con:
//   flutter run  --dart-define=FLAVOR=dev
//   flutter build ipa --dart-define=FLAVOR=staging
//   flutter build ipa --dart-define=FLAVOR=prod
//
// Si no se pasa FLAVOR, asume 'dev' (nunca se despliega a producción por error).

enum Flavor { dev, staging, prod }

class FlavorConfig {
  FlavorConfig._();

  static const String _rawFlavor =
      String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  static final Flavor current = _parse(_rawFlavor);

  static Flavor _parse(String s) {
    switch (s) {
      case 'staging': return Flavor.staging;
      case 'prod':    return Flavor.prod;
      default:        return Flavor.dev;
    }
  }

  // ── Flags de conveniencia ─────────────────────────────────────────────────

  static bool get isDev     => current == Flavor.dev;
  static bool get isStaging => current == Flavor.staging;
  static bool get isProd    => current == Flavor.prod;
  static bool get isRelease => current == Flavor.prod || current == Flavor.staging;

  // ── Nombre legible — para AppError.setKey y Analytics ────────────────────

  static String get name => _rawFlavor;

  // ── Feature flags por entorno ─────────────────────────────────────────────

  /// En dev/staging se puede resetear el onboarding desde el perfil.
  static bool get showDevTools => !isProd;

  /// Logs de anticheat detallados solo en dev.
  static bool get verboseAnticheat => isDev;
}
