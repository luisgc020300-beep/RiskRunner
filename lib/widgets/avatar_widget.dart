import 'package:flutter/material.dart';
import '../models/avatar_config.dart';
import 'avatar_painter.dart';

class AvatarWidget extends StatelessWidget {
  final AvatarConfig config;
  final double size;

  // Kept for API compatibility — the painter no longer needs a text label.
  final String? fallbackLabel;

  const AvatarWidget({
    super.key,
    required this.config,
    this.size = 110,
    this.fallbackLabel,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: AvatarPainter(config: config),
    );
  }
}
