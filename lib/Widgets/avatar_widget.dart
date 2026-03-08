// lib/widgets/avatar_widget.dart
//
// Widget que renderiza el avatar en capas superpuestas.
// Uso:
//   AvatarWidget(config: miConfig, size: 110)
//
// Las capas de ropa (jacket, pants, shoes) se colorean dinámicamente
// con ColorFiltered — un único PNG gris sirve para cualquier color.

import 'package:flutter/material.dart';
import '../models/avatar_config.dart';

class AvatarWidget extends StatelessWidget {
  final AvatarConfig config;
  final double size;

  const AvatarWidget({
    super.key,
    required this.config,
    this.size = 110,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Cuerpo base (siempre presente)
          _layer('assets/avatars/base/body.png'),

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

  /// Capa simple sin colorización
  Widget _layer(String asset) {
    return Image.asset(
      asset,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  /// Capa con colorización dinámica.
  /// El PNG debe ser gris (#808080) para que el color se aplique correctamente.
  /// Usa BlendMode.modulate: multiplica el color del pixel por el color dado.
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
}