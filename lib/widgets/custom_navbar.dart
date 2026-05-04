// lib/widgets/custom_navbar.dart
// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:RiskRunner/pesta%C3%B1as/create_post_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';

// =============================================================================
// MODELO de badges
// =============================================================================
class _NavBadgeData {
  final int notifCount;
  final int socialCount;
  const _NavBadgeData({required this.notifCount, required this.socialCount});
  static const empty = _NavBadgeData(notifCount: 0, socialCount: 0);
}

// =============================================================================
// NAVBAR PRINCIPAL
// =============================================================================
class CustomBottomNavbar extends StatefulWidget {
  final int currentIndex;
  const CustomBottomNavbar({super.key, required this.currentIndex});

  static void abrirCrearPost(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CreatePostScreen(),
      ),
    );
  }

  static void confirmarInicioCarrera(BuildContext context) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.red.withValues(alpha: 0.6)),
        ),
        title: const Row(children: [
          Icon(Icons.directions_run_rounded, color: AppColors.red, size: 22),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              '¿Listo para correr?',
              style: TextStyle(
                  color: Color(0xFF1C1C1E),
                  fontSize: 17,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ]),
        content: const Text(
          'Vas a iniciar una nueva carrera. ¿Estás seguro?',
          style: TextStyle(color: Color(0xFF636366), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF8E8E93)),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamedAndRemoveUntil(
                  context, '/correr', ModalRoute.withName('/home'));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('¡Vamos!',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static void iniciarCarreraConReto(
      BuildContext context, Map<String, dynamic> retoActivo) {
    HapticFeedback.mediumImpact();
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/correr',
      ModalRoute.withName('/home'),
      arguments: {'retoActivo': retoActivo},
    );
  }

  @override
  State<CustomBottomNavbar> createState() => _CustomBottomNavbarState();
}

class _CustomBottomNavbarState extends State<CustomBottomNavbar> {
  StreamSubscription? _sub1, _sub2, _sub3;
  _NavBadgeData _badges = _NavBadgeData.empty;

  @override
  void initState() {
    super.initState();
    _setupStream();
  }

  void _setupStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final db = FirebaseFirestore.instance;

    int notifCount  = 0;
    int friendCount = 0;
    int chatUnread  = 0;

    void emitir() {
      if (!mounted) return;
      setState(() {
        _badges = _NavBadgeData(
          notifCount:  notifCount,
          socialCount: friendCount + chatUnread,
        );
      });
    }

    _sub1 = db
        .collection('notifications')
        .where('toUserId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      notifCount = snap.docs.length;
      emitir();
    });

    _sub2 = db
        .collection('friendships')
        .where('receiverId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      friendCount = snap.docs.length;
      emitir();
    });

    _sub3 = db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((snap) {
      chatUnread = 0;
      for (final doc in snap.docs) {
        final d = doc.data();
        chatUnread += (d['unread_$uid'] as num? ?? 0).toInt();
      }
      emitir();
    });
  }

  @override
  void dispose() {
    _sub1?.cancel();
    _sub2?.cancel();
    _sub3?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _NavbarContent(
      currentIndex: widget.currentIndex,
      notifCount:   _badges.notifCount,
      socialCount:  _badges.socialCount,
    );
  }
}

// =============================================================================
class _NavbarContent extends StatelessWidget {
  final int currentIndex;
  final int notifCount;
  final int socialCount;

  const _NavbarContent({
    required this.currentIndex,
    required this.notifCount,
    required this.socialCount,
  });

  void _onTap(BuildContext context, int index) {
    HapticFeedback.selectionClick();
    switch (index) {

      // ── HOME ──────────────────────────────────────────────────────────────
      // Usamos pushNamedAndRemoveUntil para limpiar toda la pila y llegar a
      // /home sin importar desde qué pantalla venimos (mapa, social, etc.).
      // Si ya estamos en /home el Navigator simplemente no apila nada extra
      // porque la predicada devuelve false para todas las rutas anteriores.
      case 0:
        if (currentIndex == 0) return; // ya estamos en Home, no hacemos nada
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/home',
          (route) => false, // elimina toda la pila
        );
        break;

      case 1:
        Navigator.pushNamedAndRemoveUntil(
            context, '/correr', ModalRoute.withName('/home'));
        break;

      case 2:
        if (currentIndex == 2) return; // ya estamos en Mapa
        Navigator.pushNamed(context, '/mapa');
        break;

      case 3:
        if (currentIndex == 3) return; // ya estamos en Social
        Navigator.pushNamedAndRemoveUntil(
            context, '/social', ModalRoute.withName('/home'));
        break;

      case 4:
        if (currentIndex == 4) return; // ya estamos en Perfil
        Navigator.pushNamedAndRemoveUntil(
            context, '/perfil', ModalRoute.withName('/home'));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg : const Color(0xEAD1D1D6),
        border: Border(top: BorderSide(
          color: isDark ? AppColors.surface2 : const Color(0xFFC6C6C8),
          width: 1,
        )),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 46,
          child: Row(children: [
            _NavItem(
              icon:     Icons.home_rounded,
              label:    'Home',
              selected: currentIndex == 0,
              badge:    notifCount,
              onTap:    () => _onTap(context, 0),
            ),
            _NavItem(
              icon:     Icons.directions_run_rounded,
              label:    'Correr',
              selected: currentIndex == 1,
              onTap:    () => _onTap(context, 1),
            ),
            _NavItem(
              icon:     Icons.map_rounded,
              label:    'Mapa',
              selected: currentIndex == 2,
              onTap:    () => _onTap(context, 2),
            ),
            _NavItem(
              icon:     Icons.people_rounded,
              label:    'Social',
              selected: currentIndex == 3,
              badge:    socialCount,
              onTap:    () => _onTap(context, 3),
            ),
            _NavItem(
              icon:     Icons.person_rounded,
              label:    'Perfil',
              selected: currentIndex == 4,
              onTap:    () => _onTap(context, 4),
            ),
          ]),
        ),
      ),
    );
  }
}

// =============================================================================
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppColors.red : AppColors.textDim;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.red.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              if (badge > 0)
                Positioned(
                  top: -2,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.bg, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.red.withValues(alpha: 0.5),
                          blurRadius: 4,
                        )
                      ],
                    ),
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color:       color,
                fontSize:    10,
                fontWeight:  selected ? FontWeight.w700 : FontWeight.w400,
                letterSpacing: selected ? 0.5 : 0.3,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}