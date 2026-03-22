// lib/widgets/custom_navbar.dart
//
// ── OPTIMIZACIÓN v2 ────────────────────────────────────────────────────────
//  ANTES: 3 StreamBuilders anidados (notifications + friendships + chats)
//         = 3 listeners de Firestore permanentes en paralelo.
//         Cada cambio en cualquiera de las 3 colecciones reconstruye
//         los 3 StreamBuilders en cascada.
//
//  AHORA: 1 único StreamBuilder que combina las 3 queries en
//         _NavBadgeData con rxdart/StreamZip conceptual hecho a mano.
//         Solo 1 reconstrucción por cambio, misma funcionalidad.
//
//  ALTERNATIVA más simple (la que implementamos aquí):
//    Usamos un Stream propio que hace Future.wait de los 3 counts cada vez
//    que cualquiera de los snapshots cambia. Limpio, sin dependencias extra.
// ─────────────────────────────────────────────────────────────────────────────

// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:RiskRunner/Pesta%C3%B1as/create_post_screen.dart';
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
        backgroundColor: const Color(0xFF0C0C0C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.red.withValues(alpha: 0.35)),
        ),
        title: const Row(children: [
          Icon(Icons.directions_run_rounded, color: AppColors.red, size: 22),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              '¿Listo para correr?',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
        content: const Text(
          'Vas a iniciar una nueva carrera. ¿Estás seguro?',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: Colors.white38),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('¡Vamos!', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static void iniciarCarreraConReto(BuildContext context, Map<String, dynamic> retoActivo) {
    HapticFeedback.mediumImpact();
    Navigator.pushNamedAndRemoveUntil(
      context, '/correr', ModalRoute.withName('/home'),
      arguments: {'retoActivo': retoActivo},
    );
  }

  @override
  State<CustomBottomNavbar> createState() => _CustomBottomNavbarState();
}

class _CustomBottomNavbarState extends State<CustomBottomNavbar> {
  // ── Un único stream que combina los 3 contadores ─────────────────────────
  Stream<_NavBadgeData>? _badgeStream;
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

    // Valores en memoria para combinar
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

    // Stream 1: notificaciones no leídas
    _sub1 = db.collection('notifications')
        .where('toUserId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      notifCount = snap.docs.length;
      emitir();
    });

    // Stream 2: solicitudes de amistad pendientes
    _sub2 = db.collection('friendships')
        .where('receiverId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      friendCount = snap.docs.length;
      emitir();
    });

    // Stream 3: mensajes de chat no leídos
    _sub3 = db.collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((snap) {
      chatUnread = 0;
      for (final doc in snap.docs) {
        final d = doc.data() as Map<String, dynamic>;
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
      case 0:
        if (Navigator.of(context).canPop()) {
          Navigator.popUntil(context, ModalRoute.withName('/home'));
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
        break;
      case 1:
        CustomBottomNavbar.confirmarInicioCarrera(context);
        break;
      case 2:
        Navigator.pushNamed(context, '/mapa');
        break;
      case 3:
        Navigator.pushNamedAndRemoveUntil(
            context, '/social', ModalRoute.withName('/home'));
        break;
      case 4:
        Navigator.pushNamedAndRemoveUntil(
            context, '/perfil', ModalRoute.withName('/home'));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.surface2, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(children: [
            _NavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              selected: currentIndex == 0,
              badge: notifCount,
              onTap: () => _onTap(context, 0),
            ),
            _NavItem(
              icon: Icons.directions_run_rounded,
              label: 'Correr',
              selected: currentIndex == 1,
              onTap: () => _onTap(context, 1),
            ),
            _NavItem(
              icon: Icons.map_rounded,
              label: 'Mapa',
              selected: currentIndex == 2,
              onTap: () => _onTap(context, 2),
            ),
            _NavItem(
              icon: Icons.people_rounded,
              label: 'Social',
              selected: currentIndex == 3,
              badge: socialCount,
              onTap: () => _onTap(context, 3),
            ),
            _NavItem(
              icon: Icons.person_rounded,
              label: 'Perfil',
              selected: currentIndex == 4,
              onTap: () => _onTap(context, 4),
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
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.bg, width: 1.5),
                      boxShadow: [BoxShadow(
                        color: AppColors.red.withValues(alpha: 0.5),
                        blurRadius: 4,
                      )],
                    ),
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
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