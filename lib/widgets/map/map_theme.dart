import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kMapBg       = Color(0xFFE8E8ED);
const kMapSurface  = Color(0xFFFFFFFF);
const kMapSurface2 = Color(0xFFE5E5EA);
const kMapBorder   = Color(0xFFC6C6C8);
const kMapBorder2  = Color(0xFFD1D1D6);
const kMapDim      = Color(0xFFAEAEB2);
const kMapSub      = Color(0xFF8E8E93);
const kMapText     = Color(0xFF3C3C43);
const kMapWhite    = Color(0xFF1C1C1E);
const kMapRed      = Color(0xFFE02020);
const kMapSafe     = Color(0xFF30D158);
const kMapWarn     = Color(0xFFFF9500);
const kMapGold     = Color(0xFFFFD60A);
const kMapGoldDim  = Color(0xFFAEAEB2);
const kMapCyan     = Color(0xFF636366);
const kMapBlue     = Color.fromARGB(255, 16, 154, 235);

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
