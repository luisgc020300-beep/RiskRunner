// lib/theme/app_colors.dart
//
// ══════════════════════════════════════════════════════════════════════════════
//  RUNNER RISK — Paleta de colores centralizada v2
//
//  MIGRACIÓN:
//    Sustituye todas las constantes _kXxx locales de cada archivo por
//    AppColors.xxx. Los alias de compatibilidad al final del archivo
//    te permiten hacer la migración gradualmente — los nombres que ya
//    usabas siguen funcionando.
//
//  REGLA: nunca escribas Color(0xFF...) directamente en un widget.
//         Si necesitas un color nuevo, añádelo aquí primero.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class AppColors {

  AppColors._();

  // ==========================================================================
  // FONDOS
  // ==========================================================================

  /// Fondo base de la app — negro casi puro
  static const Color bg          = Color(0xFF090807);

  /// Fondo base frío (pantallas de stats / anticheat)
  static const Color bgCold      = Color(0xFF060608);

  /// Fondo base extra oscuro (rey_widgets, pantallas muy oscuras)
  static const Color bgDeep      = Color(0xFF030303);

  /// Fondo carrera (el más oscuro, cálido)
  static const Color bgRun       = Color(0xFF040302);

  /// Variante cálida del fondo base
  static const Color bgWarm      = Color(0xFF0A0806);

  // --------------------------------------------------------------------------

  /// Surface principal — cards primarias
  static const Color surface     = Color(0xFF0D0D10);

  /// Surface cálido — cards pantallas pergamino
  static const Color surfaceWarm = Color(0xFF0F0D0A);

  /// Surface oscuro — pantallas rey / muy oscuras
  static const Color surfaceDark = Color(0xFF0C0C0C);

  /// Surface neutro — variante intermedia
  static const Color surfaceMid  = Color(0xFF111111);

  /// Surface secundario — cards anidadas
  static const Color surface2    = Color(0xFF161616);

  /// Surface secundario frío
  static const Color surface2Cold = Color(0xFF131318);

  /// Surface secundario cálido
  static const Color surface2Warm = Color(0xFF101010);

  /// Surface elevado / hover
  static const Color surface3    = Color(0xFF1E1E24);

  // --------------------------------------------------------------------------

  /// Fondo pergamino cálido (LiveActivity)
  static const Color ink         = Color(0xFF1E1408);

  /// Surface pergamino
  static const Color parchRun    = Color(0xFF2A1F0F);

  /// Surface pergamino medio
  static const Color parchRunMid = Color(0xFF3D2E18);

  /// Fondo pantalla carrera cálido medio
  static const Color cosmicMid   = Color(0xFF1A0F08);

  // ==========================================================================
  // BORDES
  // ==========================================================================

  /// Borde estándar frío
  static const Color border      = Color(0xFF1E1E24);

  /// Borde cálido (pantallas pergamino)
  static const Color borderWarm  = Color(0xFF2A2218);

  /// Borde oscuro
  static const Color borderDark  = Color(0xFF161616);

  /// Borde visible
  static const Color border2     = Color(0xFF1F1F1F);

  /// Borde más claro (pantallas frías)
  static const Color borderCold  = Color(0xFF2A2A35);

  /// Línea separadora sutil
  static const Color line        = Color(0xFF1C1C24);

  /// Línea separadora 2
  static const Color line2       = Color(0xFF242430);

  // ==========================================================================
  // ROJO — color de marca
  // ==========================================================================

  /// Rojo de marca (pantallas principales)
  static const Color red         = Color(0xFFCC2222);

  /// Rojo oscuro — hover, pressed
  static const Color redDark     = Color(0xFF7A1414);

  /// Rojo error / anticheat
  static const Color redError    = Color(0xFFEF4444);

  /// Rojo error oscuro
  static const Color redErrorDark = Color(0xFF7F1D1D);

  /// Rojo glow — sombras
  static const Color redGlow     = Color(0x22CC2222);

  // ==========================================================================
  // ORO / PERGAMINO — premium y ligas
  // ==========================================================================

  /// Dorado principal
  static const Color gold        = Color(0xFFD4A84C);

  /// Dorado oscuro (rey_widgets)
  static const Color goldAlt     = Color(0xFFD4A017);

  /// Dorado claro — texto sobre fondos dorados
  static const Color goldLight   = Color(0xFFEDD98A);

  /// Dorado atenuado
  static const Color goldDim     = Color(0xFF7A5E28);

  /// Dorado atenuado oscuro
  static const Color goldDimDark = Color(0xFF5A4520);

  /// Dorado rey (más oscuro)
  static const Color goldKing    = Color(0xFF8B6914);

  /// Pergamino claro — texto principal pantallas cálidas
  static const Color parchment   = Color(0xFFEAD9AA);

  /// Pergamino medio
  static const Color parchmentMid = Color(0xFFCAAA6C);

  /// Pergamino oscuro — texto secundario
  static const Color parchmentDark = Color(0xFF8C7242);

  // ==========================================================================
  // NARANJA / TERRACOTA — territorios
  // ==========================================================================

  /// Terracota — color por defecto de territorios
  static const Color terracotta  = Color(0xFFD4722A);

  /// Naranja — estadísticas y rendimiento
  static const Color orange      = Color(0xFFE8500A);

  /// Naranja carrera
  static const Color orangeRun   = Color(0xFFFF7B1A);

  // ==========================================================================
  // COLORES SEMÁNTICOS
  // ==========================================================================

  /// Verde — éxito, territorio propio
  static const Color green       = Color(0xFF4CAF50);

  /// Verde oliva — narrador refuerzo
  static const Color greenOlive  = Color(0xFF8FAF4A);

  /// Amarillo — advertencias
  static const Color warn        = Color(0xFFFF9800);

  /// Azul — datos, info
  static const Color blue        = Color(0xFF3B6BBF);

  /// Azul agua — rival, narrador contacto
  static const Color water       = Color(0xFF5BA3A0);

  /// Azul agua claro
  static const Color waterLight  = Color(0xFF8ECFCC);

  // ==========================================================================
  // TEXTO
  // ==========================================================================

  /// Texto primario — casi blanco
  static const Color textPrimary      = Color(0xFFEEEEEE);

  /// Variante texto primario cálido
  static const Color textPrimaryWarm  = Color(0xFFF0F0F2);

  /// Texto secundario
  static const Color textSecondary    = Color(0xFFB0B0B0);

  /// Texto secundario frío
  static const Color textSecondaryCold = Color(0xFFAAAAAC);

  /// Texto terciario
  static const Color textTertiary     = Color(0xFF666666);

  /// Texto frío atenuado (stats)
  static const Color textSubCold      = Color(0xFF666680);

  /// Texto atenuado frío
  static const Color textDimCold      = Color(0xFF5A5A70);

  /// Texto muy atenuado
  static const Color textDim          = Color(0xFF4A4A4A);

  /// Texto atenuado cálido
  static const Color textDimWarm      = Color(0xFF5A5040);

  /// Texto muted
  static const Color textMuted        = Color(0xFF333333);

  /// Texto muted frío
  static const Color textMutedCold    = Color(0xFF3A3A4A);

  /// Texto muted frío 2
  static const Color textMutedCold2   = Color(0xFF3A3A48);

  /// Gris iconos inactivos
  static const Color grey             = Color(0xFF888888);

  // ==========================================================================
  // ALIAS DE COMPATIBILIDAD
  // Mantienen compilando los archivos que aún usan nombres locales.
  // Cuando migres un archivo, sustituye _kXxx por AppColors.xxx y borra el _k.
  // ==========================================================================

  // Fondos
  static const Color kBg         = bg;
  static const Color kBgCold     = bgCold;
  static const Color kBgDeep     = bgDeep;
  static const Color kSurface    = surface;
  static const Color kSurface2   = surface2;
  static const Color kInk        = ink;
  static const Color kParchment  = parchRun;
  static const Color kParchMid   = parchRunMid;
  static const Color kCosmicBg   = bgRun;
  static const Color kCosmicMid  = cosmicMid;

  // Bordes
  static const Color kBorder     = border;
  static const Color kBorder2    = border2;
  static const Color kLine       = line;
  static const Color kLine2      = line2;

  // Rojos
  static const Color kRed        = red;
  static const Color kAccent     = red;
  static const Color kRiskRed    = red;
  static const Color kRedDim     = redDark;

  // Oros
  static const Color kGold       = gold;
  static const Color kGoldLight  = goldLight;
  static const Color kGoldDim    = goldDim;

  // Naranjas
  static const Color kTerracotta = terracotta;
  static const Color kOrange     = orange;

  // Semánticos
  static const Color kGreen      = green;
  static const Color kSafe       = green;
  static const Color kVerde      = greenOlive;
  static const Color kWarn       = warn;
  static const Color kBlue       = blue;
  static const Color kWater      = water;
  static const Color kWaterLight = waterLight;

  // Textos
  static const Color kWhite      = textPrimary;
  static const Color kText       = textSecondary;
  static const Color kSubtext    = textTertiary;
  static const Color kSub        = textTertiary;
  static const Color kDim        = textDim;
  static const Color kMuted      = textMuted;

  // Grises
  static const Color kGrey       = grey;

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  static const Color defaultTerritory = terracotta;

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