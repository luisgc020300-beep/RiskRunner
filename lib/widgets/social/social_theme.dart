import 'package:flutter/material.dart';

// ── Colores fijos (accent + tiers) ──────────────────────────────────────────
const Color kSocAccent     = Color(0xFFE02020);
const Color kSocAccentGlow = Color(0x33E02020);
const Color kSocGreen      = Color(0xFF1A4A35);
const Color kSocGreenFg    = Color(0xFF3DBF82);
const Color kSocGold       = Color(0xFFFFD700);
const Color kSocSilver     = Color(0xFFC0C0C0);
const Color kSocBronze     = Color(0xFFCD7F32);
const Color kSocGoldTier   = Color(0xFFF0CC40);
const Color kSocPlatinum   = Color(0xFF6CA8E0);
const Color kSocDiamond    = Color(0xFF70E0F8);
const Color kSocBlue       = Color(0xFF0A84FF);

// ── Paleta adaptativa dark / light ─────────────────────────────────────────
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
  static const light = SocialPalette._(
    bg:       Color(0xFFE8E8ED),
    surface:  Color(0xFFFFFFFF),
    surface2: Color(0xFFE5E5EA),
    surface3: Color(0xFFF2F2F7),
    line:     Color(0xFFC6C6C8),
    line2:    Color(0xFFD1D1D6),
    dim:      Color(0xFFAEAEB2),
    subtext:  Color(0xFF8E8E93),
    text3:    Color(0xFF636366),
    text2:    Color(0xFF3C3C43),
    text1:    Color(0xFF1C1C1E),
  );
  static const dark = SocialPalette._(
    bg:       Color(0xFF090807),
    surface:  Color(0xFF1C1C1E),
    surface2: Color(0xFF2C2C2E),
    surface3: Color(0xFF38383A),
    line:     Color(0xFF38383A),
    line2:    Color(0xFF2C2C2E),
    dim:      Color(0xFF636366),
    subtext:  Color(0xFF8E8E93),
    text3:    Color(0xFF8E8E93),
    text2:    Color(0xFFD1D1D6),
    text1:    Color(0xFFEEEEEE),
  );
  static SocialPalette of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? dark : light;
}
