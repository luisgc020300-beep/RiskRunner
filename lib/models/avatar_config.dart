// lib/models/avatar_config.dart
//
// Modelo de configuración del avatar personalizable.
// Se guarda en Firestore en players/{uid}/avatar_config
import 'package:flutter/material.dart' show Color;
class AvatarConfig {
  final int hairIndex;       // 0-2 gratis, 3+ premium
  final int eyesIndex;       // 0-1 gratis, 2+ premium
  final Color jacketColor;
  final Color pantsColor;
  final Color shoesColor;

  const AvatarConfig({
    this.hairIndex = 0,
    this.eyesIndex = 0,
    this.jacketColor = const Color(0xFF4CAF50),  // verde por defecto
    this.pantsColor  = const Color(0xFF795548),  // marrón por defecto
    this.shoesColor  = const Color(0xFF8D6E63),  // marrón claro
  });

  // ── Opciones disponibles ───────────────────────────────────────────

  // Peinados: asset path + nombre + si es premium + coste
  static const List<Map<String, dynamic>> hairOptions = [
    {'asset': 'assets/avatars/hair/hair_1.png', 'name': 'Corto',     'premium': false, 'cost': 0},
    {'asset': 'assets/avatars/hair/hair_2.png', 'name': 'Bandana',   'premium': false, 'cost': 0},
    {'asset': 'assets/avatars/hair/hair_3.png', 'name': 'Gorra',     'premium': false, 'cost': 0},
    {'asset': 'assets/avatars/hair/hair_4.png', 'name': 'Afro',      'premium': true,  'cost': 200},
    {'asset': 'assets/avatars/hair/hair_5.png', 'name': 'Mohicano',  'premium': true,  'cost': 300},
  ];

  // Ojos
  static const List<Map<String, dynamic>> eyesOptions = [
    {'asset': 'assets/avatars/eyes/eyes_1.png', 'name': 'Normal',    'premium': false, 'cost': 0},
    {'asset': 'assets/avatars/eyes/eyes_2.png', 'name': 'Intenso',   'premium': false, 'cost': 0},
    {'asset': 'assets/avatars/eyes/eyes_3.png', 'name': 'Gafas sol', 'premium': true,  'cost': 150},
  ];

  // Colores gratis de ropa
  static const List<Color> freeColors = [
    Color(0xFF4CAF50), // verde
    Color(0xFF2196F3), // azul
    Color(0xFFE53935), // rojo
    Color(0xFFFF9800), // naranja
    Color(0xFF9C27B0), // morado
    Color(0xFF000000), // negro
    Color(0xFFFFFFFF), // blanco
    Color(0xFF795548), // marrón
  ];

  // Colores premium (neón)
  static const List<Map<String, dynamic>> premiumColors = [
    {'color': Color(0xFF00FF41), 'name': 'Matrix',    'cost': 100},
    {'color': Color(0xFFFF006E), 'name': 'Rosa neón', 'cost': 100},
    {'color': Color(0xFF00F5FF), 'name': 'Cian neón', 'cost': 100},
    {'color': Color(0xFFFFD700), 'name': 'Oro',       'cost': 200},
  ];

  // ── Serialización Firestore ────────────────────────────────────────

  Map<String, dynamic> toMap() => {
    'hairIndex':    hairIndex,
    'eyesIndex':    eyesIndex,
    'jacketColor':  jacketColor.value,
    'pantsColor':   pantsColor.value,
    'shoesColor':   shoesColor.value,
  };

  factory AvatarConfig.fromMap(Map<String, dynamic> map) => AvatarConfig(
  hairIndex:   (map['hairIndex']   as num?)?.toInt() ?? 0,
  eyesIndex:   (map['eyesIndex']   as num?)?.toInt() ?? 0,
  jacketColor: Color((map['jacketColor'] as num?)?.toInt() ?? 0xFF4CAF50),
  pantsColor:  Color((map['pantsColor']  as num?)?.toInt() ?? 0xFF795548),
  shoesColor:  Color((map['shoesColor']  as num?)?.toInt() ?? 0xFF8D6E63),
);

  AvatarConfig copyWith({
    int?   hairIndex,
    int?   eyesIndex,
    Color? jacketColor,
    Color? pantsColor,
    Color? shoesColor,
  }) => AvatarConfig(
    hairIndex:    hairIndex   ?? this.hairIndex,
    eyesIndex:    eyesIndex   ?? this.eyesIndex,
    jacketColor:  jacketColor ?? this.jacketColor,
    pantsColor:   pantsColor  ?? this.pantsColor,
    shoesColor:   shoesColor  ?? this.shoesColor,
  );
}

// necesario para que compile sin importar flutter
