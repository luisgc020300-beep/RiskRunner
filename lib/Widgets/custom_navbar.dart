// ignore_for_file: deprecated_member_use
import 'package:RunnerRisk/Pestañas/create_post_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CustomBottomNavbar extends StatelessWidget {
  final int currentIndex;
  const CustomBottomNavbar({super.key, required this.currentIndex});

  // ── Helpers estáticos ────────────────────────────────────────────────────
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
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        title: const Row(children: [
          Icon(Icons.directions_run_rounded, color: Colors.orange, size: 22),
          SizedBox(width: 10),
          Flexible(child: Text('¿Listo para correr?',
              style: TextStyle(color: Colors.white, fontSize: 17,
                  fontWeight: FontWeight.bold))),
        ]),
        content: const Text(
          'Vas a iniciar una nueva carrera. ¿Estás seguro?',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamedAndRemoveUntil(
                  context, '/correr', ModalRoute.withName('/home'));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('¡Vamos!',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('toUserId', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, notifSnap) {
        final int notifCount =
            notifSnap.hasData ? notifSnap.data!.docs.length : 0;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('friendships')
              .where('receiverId', isEqualTo: uid)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, friendSnap) {
            final int friendCount =
                friendSnap.hasData ? friendSnap.data!.docs.length : 0;

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('participants', arrayContains: uid)
                  .snapshots(),
              builder: (context, chatSnap) {
                int chatUnread = 0;
                if (chatSnap.hasData) {
                  for (final doc in chatSnap.data!.docs) {
                    final d = doc.data() as Map<String, dynamic>;
                    chatUnread += (d['unread_$uid'] as num? ?? 0).toInt();
                  }
                }
                return _NavbarContent(
                  currentIndex: currentIndex,
                  notifCount: notifCount,
                  socialCount: friendCount + chatUnread,
                );
              },
            );
          },
        );
      },
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
        Navigator.pushNamedAndRemoveUntil(
            context, '/resumen', ModalRoute.withName('/home'));
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
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        border: Border(top: BorderSide(color: Color(0xFF252525), width: 0.5)),
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
              icon: Icons.map_rounded,
              label: 'Correr',
              selected: currentIndex == 1,
              onTap: () => _onTap(context, 1),
            ),
            _NavItem(
              icon: Icons.bar_chart_rounded,
              label: 'Resumen',
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
    final Color color = selected ? Colors.orange : Colors.white38;
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
                      ? Colors.orange.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              if (badge > 0)
                Positioned(
                  top: -2, right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF111111), width: 1.5),
                    ),
                    child: Text(badge > 9 ? '9+' : '$badge',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 8, fontWeight: FontWeight.w900)),
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
                letterSpacing: 0.3,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}