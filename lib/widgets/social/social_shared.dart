import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'social_theme.dart';

// ── Shimmer ──────────────────────────────────────────────────────────────────
class SocialShimmer extends StatefulWidget {
  final double width, height, borderRadius;
  const SocialShimmer({required this.width, required this.height, this.borderRadius = 4});
  @override State<SocialShimmer> createState() => _SocialShimmerState();
}
class _SocialShimmerState extends State<SocialShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _anim = Tween<double>(begin: -1, end: 2).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width, height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0), end: Alignment(_anim.value, 0),
            colors: [p.surface, p.surface2, const Color(0xFF1E1E28), p.surface2, p.surface],
            stops: const [0.0, 0.3, 0.5, 0.7, 1.0]))));
  }
}

// ── Pulse Badge ───────────────────────────────────────────────────────────────
class SocialPulseBadge extends StatefulWidget {
  final int count; final Color color;
  const SocialPulseBadge({required this.count, required this.color});
  @override State<SocialPulseBadge> createState() => _SocialPulseBadgeState();
}
class _SocialPulseBadgeState extends State<SocialPulseBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx) => ScaleTransition(
    scale: _scale,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(3)),
      child: Text(widget.count > 9 ? '9+' : '${widget.count}',
        style: TextStyle(
          color: widget.color.computeLuminance() > 0.4 ? Colors.black : Colors.white,
          fontSize: 8, fontWeight: FontWeight.w900))));
}

// ── Stagger ───────────────────────────────────────────────────────────────────
class SocialStagger extends StatefulWidget {
  final Widget child; final int index;
  const SocialStagger({required this.child, required this.index});
  @override State<SocialStagger> createState() => _SocialStaggerState();
}
class _SocialStaggerState extends State<SocialStagger> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;
  @override void initState() {
    super.initState();
    final delay = math.min(widget.index * 60, 400);
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _opacity = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: delay), () { if (mounted) _ctrl.forward(); });
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx) => FadeTransition(
    opacity: _opacity, child: SlideTransition(position: _slide, child: widget.child));
}

// ── Press Scale ───────────────────────────────────────────────────────────────
class SocialPress extends StatefulWidget {
  final Widget child; final VoidCallback? onTap;
  const SocialPress({required this.child, this.onTap});
  @override State<SocialPress> createState() => _SocialPressState();
}
class _SocialPressState extends State<SocialPress> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx) => GestureDetector(
    onTapDown: (_) => _ctrl.forward(),
    onTapUp: (_) { _ctrl.reverse(); widget.onTap?.call(); },
    onTapCancel: () => _ctrl.reverse(),
    child: ScaleTransition(scale: _scale, child: widget.child));
}

// ── Avatar ────────────────────────────────────────────────────────────────────
class SocialAvatar extends StatelessWidget {
  final String? fotoBase64;
  final String? nickname;
  final double size;
  final Color? ringColor;
  final bool glow;
  const SocialAvatar({this.fotoBase64, this.nickname, this.size = 40, this.ringColor, this.glow = false});

  static Color colorFromNick(String nick) {
    if (nick.isEmpty) return const Color(0xFF2A2A35);
    int hash = 0;
    for (final c in nick.codeUnits) hash = (hash * 31 + c) & 0xFFFFFFFF;
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.55, 0.26).toColor();
  }

  static Color fgFromBg(Color bg) =>
      HSLColor.fromColor(bg).withLightness(0.78).toColor();

  @override
  Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    final ring = ringColor ?? p.line2;
    final String nick = nickname ?? '';
    final String initials = nick.isNotEmpty
        ? nick.substring(0, math.min(2, nick.length)).toUpperCase() : '?';
    final Color bgColor = colorFromNick(nick);
    final Color fgColor = fgFromBg(bgColor);

    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: p.surface3, shape: BoxShape.circle,
        border: Border.all(color: ring, width: 1.5),
        boxShadow: glow ? [BoxShadow(color: ring.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 1)] : null),
      child: ClipOval(child: fotoBase64 != null
        ? Image.memory(base64Decode(fotoBase64!), fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _Initials(initials: initials, bg: bgColor, fg: fgColor, size: size))
        : _Initials(initials: initials, bg: bgColor, fg: fgColor, size: size)));
  }
}

class _Initials extends StatelessWidget {
  final String initials; final Color bg, fg; final double size;
  const _Initials({required this.initials, required this.bg, required this.fg, required this.size});
  @override Widget build(BuildContext ctx) => Container(
    width: size, height: size, color: bg,
    alignment: Alignment.center,
    child: Text(initials, style: TextStyle(
      color: fg, fontSize: size * 0.33,
      fontWeight: FontWeight.w800, letterSpacing: 0.5, height: 1)));
}

// ── Pill Tag ──────────────────────────────────────────────────────────────────
class SocialPill extends StatelessWidget {
  final String label; final Color color; final Widget? leading;
  const SocialPill({required this.label, required this.color, this.leading});
  @override Widget build(BuildContext ctx) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      border: Border.all(color: color.withValues(alpha: 0.25)),
      borderRadius: BorderRadius.circular(4)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (leading != null) ...[
        leading!,
        const SizedBox(width: 3),
      ],
      Text(label, style: TextStyle(
        color: color.withValues(alpha: 0.9),
        fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5))]));
}

// ── Skeleton ──────────────────────────────────────────────────────────────────
class SocialSkel extends StatelessWidget {
  final double height;
  const SocialSkel({this.height = 68});
  @override Widget build(BuildContext ctx) {
    final p = SocialPalette.of(ctx);
    return Container(
    height: height, margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: p.line2)),
    clipBehavior: Clip.hardEdge,
    child: Row(children: [
      SocialShimmer(width: 58, height: height),
      const SizedBox(width: 14),
      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SocialShimmer(width: 110, height: 12), const SizedBox(height: 8), const SocialShimmer(width: 75, height: 9)])),
      const SocialShimmer(width: 56, height: 30, borderRadius: 6),
      const SizedBox(width: 14)]));
  }
}
