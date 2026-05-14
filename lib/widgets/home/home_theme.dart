import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  static const light = HomePalette._(
    bg0: Color(0xFFE8E8ED), bg1: Color(0xFFFFFFFF), bg2: Color(0xFFE5E5EA),
    bg3: Color(0xFFE8E8ED), bg4: Color(0xFFFFFFFF),
    parch: Color(0xFF1C1C1E), gold: Color(0xFFFFD60A),
    bronze: Color(0xFF636366), terra: Color(0xFFAEAEB2),
    white: Color(0xFF1C1C1E), text: Color(0xFF3C3C43),
    sub: Color(0xFF636366), dim: Color(0xFF8E8E93), muted: Color(0xFFAEAEB2),
    border: Color(0xFFC6C6C8), border2: Color(0xFFD1D1D6),
    safe: Color(0xFF30D158), warn: Color(0xFFFF9800),
    red: Color(0xFFE02020), redD: Color(0xFFFF6B6B), redGlow: Color(0x22E02020),
  );

  static const dark = HomePalette._(
    bg0: Color(0xFF090807), bg1: Color(0xFF1C1C1E), bg2: Color(0xFF2C2C2E),
    bg3: Color(0xFF090807), bg4: Color(0xFF1C1C1E),
    parch: Color(0xFFEAD9AA), gold: Color(0xFFFFD60A),
    bronze: Color(0xFF8E8E93), terra: Color(0xFF636366),
    white: Color(0xFFEEEEEE), text: Color(0xFFD1D1D6),
    sub: Color(0xFF8E8E93), dim: Color(0xFF636366), muted: Color(0xFF48484A),
    border: Color(0xFF38383A), border2: Color(0xFF2C2C2E),
    safe: Color(0xFF30D158), warn: Color(0xFFFF9800),
    red: Color(0xFFE02020), redD: Color(0xFFFF6B6B), redGlow: Color(0x22E02020),
  );

  static HomePalette of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? dark : light;
}

TextStyle homeStyle(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    GoogleFonts.inter(
      fontSize: size, fontWeight: weight, color: color,
      letterSpacing: spacing, height: height,
    );
