// lib/widgets/avatar_widget.dart
//
// Widget que renderiza el avatar en capas superpuestas.
// Uso:
//   AvatarWidget(config: miConfig, size: 110)
//   AvatarWidget(config: miConfig, size: 110, fallbackLabel: 'L')
//
// Si los assets no existen (desarrollo / capas no generadas aún),
// muestra un fallback con la inicial del jugador y su color de chaqueta.
// Cuando los assets estén listos el fallback desaparece automáticamente.

import 'package:flutter/material.dart';
import '../models/avatar_config.dart';

class AvatarWidget extends StatelessWidget {
  final AvatarConfig config;
  final double size;

  /// Inicial o texto corto que se muestra cuando los assets no están disponibles.
  /// Si es null se muestra un icono genérico de persona.
  final String? fallbackLabel;

  const AvatarWidget({
    super.key,
    required this.config,
    this.size = 110,
    this.fallbackLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Cuerpo base — si falla, muestra el fallback completo
          _baseLayer('assets/avatars/base/body.png'),

          // 2. Ojos
          _layer(AvatarConfig.eyesOptions[config.eyesIndex]['asset']),

          // 3. Pelo
          _layer(AvatarConfig.hairOptions[config.hairIndex]['asset']),

          // 4. Chaqueta (coloreada)
          _coloredLayer('assets/avatars/jacket/jacket.png', config.jacketColor),

          // 5. Pantalones (coloreados)
          _coloredLayer('assets/avatars/pants/pants.png', config.pantsColor),

          // 6. Zapatillas (coloreadas)
          _coloredLayer('assets/avatars/shoes/shoes.png', config.shoesColor),
        ],
      ),
    );
  }

  // ── Capa base: si falla muestra el fallback visual completo ──────────
  Widget _baseLayer(String asset) {
    return Image.asset(
      asset,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _buildFallback(),
    );
  }

  // ── Capas secundarias: si fallan simplemente no se pintan ────────────
  Widget _layer(String asset) {
    return Image.asset(
      asset,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  Widget _coloredLayer(String asset, Color color) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.modulate),
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }

  // ── Fallback visual ───────────────────────────────────────────────────
  // Se muestra cuando body.png no existe.
  // Usa el color de la chaqueta como acento para mantener coherencia
  // con el color de territorio del jugador.
  Widget _buildFallback() {
    final Color accent = config.jacketColor;
    final Color bg     = Color.lerp(Colors.black, accent, 0.12) ?? Colors.black;
    final double iconSize = size * 0.42;
    final double fontSize = size * 0.38;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(
          color: accent.withValues(alpha: 0.35),
          width: size * 0.025,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.20),
            blurRadius: size * 0.18,
          ),
        ],
      ),
      child: Center(
        child: fallbackLabel != null && fallbackLabel!.isNotEmpty
            ? Text(
                fallbackLabel![0].toUpperCase(),
                style: TextStyle(
                  color: accent,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  shadows: [
                    Shadow(
                      color: accent.withValues(alpha: 0.5),
                      blurRadius: size * 0.12,
                    ),
                  ],
                ),
              )
            : Icon(
                Icons.person_rounded,
                color: accent.withValues(alpha: 0.7),
                size: iconSize,
              ),
      ),
    );
  }
}