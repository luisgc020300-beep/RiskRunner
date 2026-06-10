import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

class HomePalette {
  final Color bg0, bg1, bg2, bg3, bg4;
  final Color parch, gold, bronze, terra;
  final Color white, text, sub, dim, muted;
  final Color border, border2;
  final Color safe, warn, red, redD, redGlow;

  const HomePalette._({
    required this.bg0, required this.bg1, required this.bg2,
    required this.bg3, required this.bg4,
    required this.parch, required this.gold, required this.bronze, required this.terra,
    required this.white, required this.text, required this.sub,
    required this.dim, required this.muted,
    required this.border, required this.border2,
    required this.safe, required this.warn,
    required this.red, required this.redD, required this.redGlow,
  });

  static const dark = HomePalette._(
    bg0:    AppColors.bg,
    bg1:    AppColors.surface,
    bg2:    AppColors.surface2,
    bg3:    AppColors.bg,
    bg4:    AppColors.surface,
    parch:  AppColors.parchment,
    gold:   AppColors.gold,
    bronze: AppColors.textSecondary,
    terra:  AppColors.textTertiary,
    white:  AppColors.textPrimary,
    text:   AppColors.textSecondary,
    sub:    AppColors.textTertiary,
    dim:    AppColors.textDim,
    muted:  AppColors.textMuted,
    border: AppColors.border,
    border2: AppColors.border2,
    safe:   AppColors.green,
    warn:   AppColors.warn,
    red:    AppColors.red,
    redD:   AppColors.redError,
    redGlow: AppColors.redGlow,
  );

  // Alias — la app solo usa dark mode
  static HomePalette of(BuildContext ctx) => dark;
}

TextStyle homeStyle(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    GoogleFonts.inter(
      fontSize: size, fontWeight: weight, color: color,
      letterSpacing: spacing, height: height,
    );
