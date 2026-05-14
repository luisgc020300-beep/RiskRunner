import 'package:flutter/material.dart';

class Reveal extends StatelessWidget {
  final Animation<double> anim;
  final Widget child;
  const Reveal({super.key, required this.anim, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: anim,
    builder: (_, __) => Opacity(
      opacity: anim.value.clamp(0.0, 1.0),
      child: Transform.translate(
          offset: Offset(0, 20 * (1 - anim.value)), child: child),
    ),
  );
}
