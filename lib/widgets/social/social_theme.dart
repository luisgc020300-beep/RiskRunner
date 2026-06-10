import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

// ── Colores fijos (accent + tiers) ──────────────────────────────────────────
const Color kSocAccent     = AppColors.red;
const Color kSocAccentGlow = AppColors.redGlow;
const Color kSocGreen      = Color(0xFF1A4A35);
const Color kSocGreenFg    = Color(0xFF3DBF82);
const Color kSocGold       = AppColors.gold;
const Color kSocSilver     = Color(0xFFC0C0C0);
const Color kSocBronze     = Color(0xFFCD7F32);
const Color kSocGoldTier   = Color(0xFFF0CC40);
const Color kSocPlatinum   = Color(0xFF6CA8E0);
const Color kSocDiamond    = Color(0xFF70E0F8);
const Color kSocBlue       = Color(0xFF0A84FF);

// ── Paleta adaptativa (solo dark mode activo) ────────────────────────────────
class SocialPalette {
  final Color bg, surface, surface2, surface3;
  final Color line, line2, dim, subtext, text3, text2, text1;
  const SocialPalette._({
    required this.bg,       required this.surface,
    required this.surface2, required this.surface3,
    required this.line,     required this.line2,
    required this.dim,      required this.subtext,
    required this.text3,    required this.text2,
    required this.text1,
  });

  static const dark = SocialPalette._(
    bg:       AppColors.bg,
    surface:  AppColors.surface,
    surface2: AppColors.surface2,
    surface3: AppColors.surface3,
    line:     AppColors.border,
    line2:    AppColors.border2,
    dim:      AppColors.textTertiary,
    subtext:  AppColors.textDim,
    text3:    AppColors.textTertiary,
    text2:    AppColors.textSecondary,
    text1:    AppColors.textPrimary,
  );

  // Alias — la app solo usa dark mode
  static SocialPalette of(BuildContext ctx) => dark;
}
