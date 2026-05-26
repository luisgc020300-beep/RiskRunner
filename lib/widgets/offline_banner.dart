// lib/widgets/offline_banner.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';

/// Envuelve cualquier widget hijo y muestra un banner rojo animado en la
/// parte superior cuando no hay conexión a internet.
class OfflineBanner extends StatefulWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner>
    with SingleTickerProviderStateMixin {
  late bool _isOnline;
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  StreamSubscription<bool>? _sub;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    if (!_isOnline) _ctrl.value = 1.0;

    _sub = ConnectivityService.instance.onlineStream.listen((online) {
      if (!mounted) return;
      _hideTimer?.cancel();
      setState(() => _isOnline = online);
      if (online) {
        // Muestra "Conexión restaurada" 1.8 s y luego oculta el banner
        _ctrl.forward();
        _hideTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted) _ctrl.reverse();
        });
      } else {
        _ctrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _sub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      SlideTransition(
        position: _slide,
        child: Align(
          alignment: Alignment.topCenter,
          child: _OfflineBannerBar(isOnline: _isOnline),
        ),
      ),
    ]);
  }
}

class _OfflineBannerBar extends StatelessWidget {
  final bool isOnline;
  const _OfflineBannerBar({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      color: isOnline ? const Color(0xFF34C759) : AppColors.red,
      padding: EdgeInsets.fromLTRB(16, topPad + 6, 16, 8),
      child: Row(children: [
        Icon(
          isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
          color: Colors.white,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          isOnline ? 'Conexión restaurada' : 'Sin conexión a internet',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]),
    );
  }
}
