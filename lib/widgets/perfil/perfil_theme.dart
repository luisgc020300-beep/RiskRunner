import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

const kPerfilAccent  = AppColors.red;
const kPerfilGold    = AppColors.gold;
const kPerfilMorado  = Color(0xFF6A4A9B);

class PerfilPalette {
  final Color bg, surface, surface2;
  final Color border, border2, muted, dim, sub, text, title;
  const PerfilPalette._({
    required this.bg,      required this.surface,  required this.surface2,
    required this.border,  required this.border2,
    required this.muted,   required this.dim,      required this.sub,
    required this.text,    required this.title,
  });

  static const dark = PerfilPalette._(
    bg:       AppColors.bg,
    surface:  AppColors.surface,
    surface2: AppColors.surface2,
    border:   AppColors.border,
    border2:  AppColors.border2,
    muted:    AppColors.textMuted,
    dim:      AppColors.textDim,
    sub:      AppColors.textTertiary,
    text:     AppColors.textSecondary,
    title:    AppColors.textPrimary,
  );

  // Alias — la app solo usa dark mode
  static PerfilPalette of(BuildContext ctx) => dark;
}

TextStyle perfilStyle(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height, List<Shadow>? shadows}) {
  return GoogleFonts.inter(
    fontSize: size, fontWeight: weight, color: color,
    letterSpacing: spacing, height: height, shadows: shadows,
  );
}
