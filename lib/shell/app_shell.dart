// lib/shell/app_shell.dart
//
// AppShell — Scaffold persistente con IndexedStack para las 4 pestañas
// principales. Un solo Scaffold = una sola navbar = cero parpadeo.
//
// Mapeo navbar ↔ stack:
//   navIndex 0 (Home)        → stackIndex 0
//   navIndex 1 (Correr)      → muestra diálogo, sin cambio de stack
//   navIndex 2 (Mapa)        → stackIndex 1
//   navIndex 3 (Social)      → stackIndex 2
//   navIndex 4 (Perfil)      → stackIndex 3

import 'package:flutter/material.dart';

import '../pestañas/Home_screen.dart';
import '../pestañas/fullscreen_map_screen.dart';
import '../pestañas/Social_screen.dart';
import '../pestañas/perfil_screen.dart';
import '../widgets/custom_navbar.dart';

class AppShell extends StatefulWidget {
  final int initialNavIndex;
  const AppShell({super.key, this.initialNavIndex = 0});

  // ── Acceso estático al estado desde cualquier descendiente ─────────────────
  static _AppShellState? _stateOf(BuildContext context) =>
      context.findAncestorStateOfType<_AppShellState>();

  /// true cuando el widget está dentro del árbol del shell (en IndexedStack).
  /// false cuando está en una ruta empujada encima del shell.
  static bool isActive(BuildContext context) => _stateOf(context) != null;

  /// Cambia la pestaña activa desde cualquier widget descendiente del shell.
  static void selectTab(BuildContext context, int navIndex) =>
      _stateOf(context)?._selectTab(navIndex);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _navIndex;

  static int _toStackIndex(int navIndex) =>
      navIndex <= 0 ? 0 : navIndex - 1; // 0→0, 2→1, 3→2, 4→3

  @override
  void initState() {
    super.initState();
    _navIndex = widget.initialNavIndex;
  }

  void _selectTab(int navIndex) {
    if (navIndex == 1) {
      // Correr — delega al diálogo de confirmación existente
      CustomBottomNavbar.confirmarInicioCarrera(context);
      return;
    }
    if (navIndex == _navIndex) return;
    setState(() => _navIndex = navIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _toStackIndex(_navIndex),
        children: const [
          HomeScreen(),
          FullscreenMapScreen(), // parámetros opcionales → defaults del constructor
          SocialScreen(),
          PerfilScreen(),
        ],
      ),
      bottomNavigationBar: CustomBottomNavbar(
        currentIndex: _navIndex,
        onTabSelected: _selectTab,
      ),
    );
  }
}
