import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kPerfilAccent  = Color(0xFFE02020);
const kPerfilGold    = Color(0xFFFFD60A);
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
  static const light = PerfilPalette._(
    bg:       Color(0xFFE8E8ED),
    surface:  Color(0xFFFFFFFF),
    surface2: Color(0xFFE5E5EA),
    border:   Color(0xFFC6C6C8),
    border2:  Color(0xFFD1D1D6),
    muted:    Color(0xFFAEAEB2),
    dim:      Color(0xFF8E8E93),
    sub:      Color(0xFF636366),
    text:     Color(0xFF3C3C43),
    title:    Color(0xFF1C1C1E),
  );
  static const dark = PerfilPalette._(
    bg:       Color(0xFF090807),
    surface:  Color(0xFF1C1C1E),
    surface2: Color(0xFF2C2C2E),
    border:   Color(0xFF38383A),
    border2:  Color(0xFF2C2C2E),
    muted:    Color(0xFF48484A),
    dim:      Color(0xFF8E8E93),
    sub:      Color(0xFF8E8E93),
    text:     Color(0xFFD1D1D6),
    title:    Color(0xFFEEEEEE),
  );
  static PerfilPalette of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? dark : light;
}

TextStyle perfilStyle(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height, List<Shadow>? shadows}) {
  return GoogleFonts.inter(
    fontSize: size, fontWeight: weight, color: color,
    letterSpacing: spacing, height: height, shadows: shadows,
  );
}
