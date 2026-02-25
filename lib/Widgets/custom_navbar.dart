import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CustomBottomNavbar extends StatelessWidget {
  final int currentIndex;
  const CustomBottomNavbar({super.key, required this.currentIndex});

  void _confirmarInicioCarrera(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        title: const Row(
          children: [
            Icon(Icons.directions_run, color: Colors.orange, size: 24),
            SizedBox(width: 10),
            Text('¿Listo para correr?',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('Vas a iniciar una nueva carrera. ¿Estás seguro?',
            style: TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12)),
            child: const Text('Cancelar', style: TextStyle(fontSize: 15)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamedAndRemoveUntil(
                  context, '/correr', ModalRoute.withName('/home'));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('¡Vamos!',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? currentUserId =
        FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      // Badge Home: notificaciones de territorio no leídas
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('toUserId', isEqualTo: currentUserId)
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, notifSnap) {
        final int notifCount =
            notifSnap.hasData ? notifSnap.data!.docs.length : 0;

        return StreamBuilder<QuerySnapshot>(
          // Badge Social: solicitudes de amistad pendientes
          stream: FirebaseFirestore.instance
              .collection('friendships')
              .where('receiverId', isEqualTo: currentUserId)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, friendSnap) {
            final int friendCount =
                friendSnap.hasData ? friendSnap.data!.docs.length : 0;

            return BottomNavigationBar(
              backgroundColor: const Color(0xFF1A1A1A),
              selectedItemColor: Colors.orange,
              unselectedItemColor: Colors.white54,
              currentIndex: currentIndex,
              type: BottomNavigationBarType.fixed,
              onTap: (index) {
                if (index == currentIndex) return;
                switch (index) {
                  case 0:
                    if (Navigator.of(context).canPop()) {
                      Navigator.popUntil(
                          context, ModalRoute.withName('/home'));
                    } else {
                      Navigator.pushReplacementNamed(context, '/home');
                    }
                    break;
                  case 1:
                    _confirmarInicioCarrera(context);
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
              },
              items: [
                // Home — badge rojo con notifs de territorio
                BottomNavigationBarItem(
                  icon: Badge(
                    isLabelVisible: notifCount > 0,
                    backgroundColor: Colors.redAccent,
                    label: Text(
                      notifCount > 9 ? '9+' : notifCount.toString(),
                      style: const TextStyle(fontSize: 9),
                    ),
                    child: const Icon(Icons.home),
                  ),
                  label: 'Home',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.map_rounded),
                  label: 'Correr',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.bar_chart),
                  label: 'Resumen',
                ),
                // Social — badge rojo con solicitudes de amistad
                BottomNavigationBarItem(
                  icon: Badge(
                    isLabelVisible: friendCount > 0,
                    backgroundColor: Colors.red,
                    label: Text(
                      friendCount.toString(),
                      style: const TextStyle(fontSize: 9),
                    ),
                    child: const Icon(Icons.people),
                  ),
                  label: 'Social',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: 'Perfil',
                ),
              ],
            );
          },
        );
      },
    );
  }
}