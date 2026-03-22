// lib/theme/app_colors.dart
//
// ══════════════════════════════════════════════════════════════════════════════
//  RUNNER RISK — Paleta de colores centralizada
//
//  CÓMO USAR:
//    import '../theme/app_colors.dart';
//    color: AppColors.red          // en vez de Color(0xFFCC2222)
//    color: AppColors.gold         // en vez de Color(0xFFD4A84C)
//
//  MIGRACIÓN GRADUAL:
//    No hace falta cambiar todos los archivos de golpe.
//    Cuando toques un archivo, sustituye sus colores locales por estos.
//    Los archivos que no toques siguen funcionando igual.
//
//  REGLA: Si necesitas un color nuevo, añádelo AQUÍ antes de usarlo.
//         Nunca escribas Color(0xFF...) directamente en un widget.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class AppColors {

  AppColors._(); // no instanciable

  // ==========================================================================
  // FONDOS — de más oscuro a más claro
  // ==========================================================================

  /// Fondo base de la app — el negro casi puro
  static const Color bg        = Color(0xFF090807);

  /// Variante ligeramente más cálida del fondo base
  static const Color bgWarm    = Color(0xFF0A0806);

  /// Surface principal — cards, contenedores primarios
  static const Color surface   = Color(0xFF0D0D10);

  /// Surface cálido — para pantallas con estética pergamino
  static const Color surfaceWarm = Color(0xFF100D08);

  /// Surface secundario — cards anidadas, fondos de sección
  static const Color surface2  = Color(0xFF161616);

  /// Surface cálido secundario
  static const Color surface2Warm = Color(0xFF161209);

  /// Surface elevado — hover, selected state
  static const Color surface3  = Color(0xFF1E1E24);

  /// Fondo para pantallas de carrera (muy oscuro, cálido)
  static const Color bgRun     = Color(0xFF040302);

  // ==========================================================================
  // BORDES
  // ==========================================================================

  /// Borde estándar oscuro
  static const Color border    = Color(0xFF1E1E24);

  /// Borde cálido (pantallas de pergamino)
  static const Color borderWarm = Color(0xFF2A2218);

  /// Borde más visible
  static const Color border2   = Color(0xFF2A2010);

  // ==========================================================================
  // ROJO — color de marca principal
  // ==========================================================================

  /// Rojo de marca — usar para acciones primarias, navbar activa, CTA
  static const Color red       = Color(0xFFCC2222);

  /// Rojo oscuro — hover, pressed state
  static const Color redDark   = Color(0xFF7A1414);

  /// Rojo glow — para sombras y efectos de brillo
  static const Color redGlow   = Color(0x22CC2222);

  // ==========================================================================
  // ORO / PERGAMINO — tema premium y ligas
  // ==========================================================================

  /// Dorado principal — ligas, premium, conquistas
  static const Color gold      = Color(0xFFD4A84C);

  /// Dorado más claro — texto sobre fondos dorados
  static const Color goldLight = Color(0xFFEDD98A);

  /// Dorado oscuro — texto secundario dorado, subíndices
  static const Color goldDim   = Color(0xFF7A5E28);

  /// Dorado muy oscuro — para fondos sutiles
  static const Color goldDark  = Color(0xFF5A4520);

  /// Pergamino claro — texto principal en pantallas de tema cálido
  static const Color parchment = Color(0xFFEAD9AA);

  /// Pergamino medio
  static const Color parchmentMid = Color(0xFFCAAA6C);

  /// Pergamino oscuro — texto secundario
  static const Color parchmentDark = Color(0xFF8C7242);

  // ==========================================================================
  // NARANJA / TERRACOTA — territorios y conquistas
  // ==========================================================================

  /// Terracota — color por defecto de territorios
  static const Color terracotta = Color(0xFFD4722A);

  /// Naranja — estadísticas, gráficos de rendimiento
  static const Color orange    = Color(0xFFE8500A);

  /// Naranja más suave — variante para carrera
  static const Color orangeRun = Color(0xFFFF7B1A);

  // ==========================================================================
  // COLORES SEMÁNTICOS
  // ==========================================================================

  /// Verde — estado activo, éxito, territorio propio
  static const Color green     = Color(0xFF4CAF50);

  /// Verde oliva — narrador refuerzo
  static const Color greenOlive = Color(0xFF8FAF4A);

  /// Amarillo aviso — warnings
  static const Color warn      = Color(0xFFFF9800);

  /// Azul agua — rival cercano, narrador contacto
  static const Color water     = Color(0xFF5BA3A0);

  /// Azul agua claro
  static const Color waterLight = Color(0xFF8ECFCC);

  // ==========================================================================
  // TEXTO
  // ==========================================================================

  /// Texto primario — blanco suave
  static const Color textPrimary   = Color(0xFFEEEEEE);

  /// Variante texto primario — ligeramente más cálido
  static const Color textPrimaryWarm = Color(0xFFF0F0F2);

  /// Texto secundario — gris medio
  static const Color textSecondary = Color(0xFFB0B0B0);

  /// Texto terciario / subtext — gris oscuro
  static const Color textTertiary  = Color(0xFF666666);

  /// Texto muy atenuado — hints, placeholders
  static const Color textDim       = Color(0xFF4A4A4A);

  /// Texto muted — separadores de sección
  static const Color textMuted     = Color(0xFF333333);

  /// Texto subtext frío (pantallas de stats)
  static const Color textSubCold   = Color(0xFF666680);

  /// Texto atenuado frío
  static const Color textDimCold   = Color(0xFF5A5A70);

  /// Gris puro — iconos inactivos
  static const Color grey          = Color(0xFF888888);

  /// Gris oscuro — números en ranking
  static const Color greyDark      = Color(0xFF444444);

  // ==========================================================================
  // COLORES DE CARRERA (tema pergamino oscuro)
  // ==========================================================================

  /// Fondo tinta — base de la pantalla de carrera
  static const Color ink         = Color(0xFF1E1408);

  /// Pergamino carrera — superficie principal
  static const Color parchRun    = Color(0xFF2A1F0F);

  /// Pergamino carrera medio
  static const Color parchRunMid = Color(0xFF3D2E18);

  // ==========================================================================
  // ALIAS DE COMPATIBILIDAD
  // Estos nombres son los más usados en los archivos actuales.
  // Úsalos cuando migres un archivo para mantener legibilidad.
  // ==========================================================================

  /// Alias de red — el más usado en la app
  static const Color kRed        = red;
  static const Color kRiskRed    = red;
  static const Color kAccent     = red;

  /// Alias de gold
  static const Color kGold       = gold;
  static const Color kGoldLight  = goldLight;
  static const Color kGoldDim    = goldDim;

  /// Alias de fondos
  static const Color kBg         = bg;
  static const Color kSurface    = surface;

  /// Alias de bordes
  static const Color kBorder     = border;

  /// Alias de texto
  static const Color kWhite      = textPrimary;
  static const Color kText       = textSecondary;
  static const Color kSubtext    = textTertiary;
  static const Color kDim        = textDim;
  static const Color kMuted      = textMuted;
  static const Color kSub        = textTertiary;

  /// Alias semánticos
  static const Color kGreen      = green;
  static const Color kSafe       = green;
  static const Color kWarn       = warn;
  static const Color kTerracotta = terracotta;
  static const Color kOrange     = orange;
  static const Color kGrey       = grey;
  static const Color kWater      = water;
  static const Color kVerde      = greenOlive;

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  /// Devuelve el color de territorio por defecto
  static const Color defaultTerritory = terracotta;

  /// Devuelve el color de liga por id
  static Color ligaColor(String ligaId) {
    switch (ligaId.toLowerCase()) {
      case 'bronce':   return const Color(0xFFBF8B5E);
      case 'plata':    return const Color(0xFFB0BEC5);
      case 'oro':      return const Color(0xFFFFD600);
      case 'platino':  return const Color(0xFF40C4FF);
      case 'diamante': return const Color(0xFF00B0FF);
      case 'leyenda':  return const Color(0xFFFF6D00);
      default:         return const Color(0xFFBF8B5E);
    }
  }
}