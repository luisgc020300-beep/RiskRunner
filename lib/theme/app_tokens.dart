// lib/theme/app_tokens.dart
//
// Tokens de diseño globales — espaciados, radios, duraciones.
// REGLA: nunca escribas un número mágico de padding/radius en un widget.
//        Usa AppTokens.xxx.

class AppTokens {
  AppTokens._();

  // ── Radios de borde ──────────────────────────────────────────────────────────
  static const double radiusSm  =  6;   // chips, badges, tags pequeños
  static const double radiusMd  = 10;   // botones, inputs, tooltips
  static const double radiusLg  = 14;   // cards, paneles, sheets
  static const double radiusXl  = 20;   // modales, bottom sheets grandes

  // ── Espaciado ────────────────────────────────────────────────────────────────
  static const double spaceXs   =  4;
  static const double spaceSm   =  8;
  static const double spaceMd   = 16;
  static const double spaceLg   = 24;
  static const double spaceXl   = 32;

  // ── Iconos ───────────────────────────────────────────────────────────────────
  static const double iconXs    = 12;
  static const double iconSm    = 16;
  static const double iconMd    = 20;
  static const double iconLg    = 24;

  // ── Animaciones ──────────────────────────────────────────────────────────────
  static const int durationFast   = 120;  // ms — microinteracciones
  static const int durationNormal = 200;  // ms — transiciones estándar
  static const int durationSlow   = 350;  // ms — entradas/salidas de pantalla

  // ── Bordes ───────────────────────────────────────────────────────────────────
  static const double borderThin   = 0.5;
  static const double borderNormal = 1.0;
}
