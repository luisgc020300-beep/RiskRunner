import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

// Constantes de mapa — todas apuntan a AppColors
const kMapBg       = AppColors.bg;
const kMapSurface  = AppColors.surface;
const kMapSurface2 = AppColors.surface2;
const kMapBorder   = AppColors.border;
const kMapBorder2  = AppColors.border2;
const kMapDim      = AppColors.textTertiary;
const kMapSub      = AppColors.textDim;
const kMapText     = AppColors.textSecondary;
const kMapWhite    = AppColors.textPrimary;
const kMapRed      = AppColors.red;
const kMapSafe     = AppColors.green;
const kMapWarn     = AppColors.warn;
const kMapGold     = AppColors.gold;
const kMapGoldDim  = AppColors.goldDim;
const kMapCyan     = AppColors.water;
const kMapBlue     = AppColors.blue;

TextStyle mapRaj(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    GoogleFonts.inter(
        fontSize: size, fontWeight: weight, color: color,
        letterSpacing: spacing, height: height);

TextStyle mapCinzel(double size, FontWeight weight, Color color,
    {double spacing = 0}) =>
    GoogleFonts.cinzel(
        fontSize: size, fontWeight: weight, color: color,
        letterSpacing: spacing);
