// lib/theme/app_typography.dart
//
// Escala tipográfica única de RiskRunner.
// REGLA: nunca llames a GoogleFonts directamente en un widget.
//        Usa AppTypography.xxx o los helpers raj() / body().

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTypography {
  AppTypography._();

  // ── Escala Rajdhani (táctica — títulos, labels, botones, stats) ─────────────

  /// Título de pantalla completa — 28px w700 spacing 1.0
  static TextStyle display(Color color) => GoogleFonts.rajdhani(
        fontSize: 28, fontWeight: FontWeight.w700,
        color: color, letterSpacing: 1.0,
      );

  /// Título de sección / panel — 16px w700 spacing 0.5
  static TextStyle heading(Color color) => GoogleFonts.rajdhani(
        fontSize: 16, fontWeight: FontWeight.w700,
        color: color, letterSpacing: 0.5,
      );

  /// Labels, botones, chips activos — 13px w700 spacing 1.5
  static TextStyle label(Color color, {double? size}) => GoogleFonts.rajdhani(
        fontSize: size ?? 13, fontWeight: FontWeight.w700,
        color: color, letterSpacing: 1.5,
      );

  /// Subtítulos, chips secundarios — 10px w600 spacing 1.0
  static TextStyle caption(Color color) => GoogleFonts.rajdhani(
        fontSize: 10, fontWeight: FontWeight.w600,
        color: color, letterSpacing: 1.0,
      );

  /// Badges, contadores, micro-labels — 8px w700 spacing 0.5
  static TextStyle micro(Color color) => GoogleFonts.rajdhani(
        fontSize: 8, fontWeight: FontWeight.w700,
        color: color, letterSpacing: 0.5,
      );

  // ── Escala Inter (lectura — descripciones, mensajes, texto largo) ───────────

  /// Texto de lectura principal — 13px w400
  static TextStyle body(Color color, {double? size, FontWeight? weight}) =>
      GoogleFonts.inter(
        fontSize: size ?? 13, fontWeight: weight ?? FontWeight.w400,
        color: color,
      );

  /// Texto de lectura secundario / meta — 11px w400
  static TextStyle bodySmall(Color color) => GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w400, color: color,
      );

  // ── Helpers cortos (para uso inline en widgets) ──────────────────────────────

  /// Rajdhani con tamaño y peso personalizados — para casos especiales únicamente
  static TextStyle raj(double size, FontWeight weight, Color color,
      {double spacing = 0.5, double? height}) =>
      GoogleFonts.rajdhani(
        fontSize: size, fontWeight: weight, color: color,
        letterSpacing: spacing, height: height,
      );

  /// Inter con tamaño y peso personalizados — para casos especiales únicamente
  static TextStyle inter(double size, FontWeight weight, Color color,
      {double spacing = 0, double? height}) =>
      GoogleFonts.inter(
        fontSize: size, fontWeight: weight, color: color,
        letterSpacing: spacing, height: height,
      );
}
