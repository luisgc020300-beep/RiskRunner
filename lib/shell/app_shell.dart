// lib/shell/app_shell.dart
//
// AppShell — Scaffold persistente con PageView deslizable para las 5
// pestañas principales (Home, Correr, Mapa, Social, Perfil). Un solo
// Scaffold = una sola navbar = cero parpadeo, y ahora también se puede
// cambiar de pestaña deslizando la pantalla, no solo tocando la navbar.
//
// Mapeo navbar ↔ página del PageView (es 1:1, no hace falta traducir índices):
//   navIndex 0 → Home
//   navIndex 1 → Correr   (se activa perezosamente: no se monta la sesión
//                          GPS/mapa hasta la primera vez que se visita)
//   navIndex 2 → Mapa
//   navIndex 3 → Social
//   navIndex 4 → Perfil
//
// Mientras hay una carrera activa (corriendo, sin pausa) el deslizamiento
// se bloquea y la navbar se oculta, igual que pasaba antes cuando Correr
// era una ruta empujada aparte — así no se puede salir sin querer.

import 'dart:async';

import 'package:flutter/material.dart';

import '../pestañas/Home_screen.dart';
import '../pestañas/LiveActivity_screen.dart';
import '../pestañas/fullscreen_map_screen.dart';
import '../pestañas/Social_screen.dart';
import '../pestañas/perfil_screen.dart';
import '../services/last_seen_service.dart';
import '../theme/app_colors.dart';
import '../widgets/custom_navbar.dart';

class AppShell extends StatefulWidget {
  final int initialNavIndex;
  const AppShell({super.key, this.initialNavIndex = 0});

  // ── Acceso estático al estado desde cualquier descendiente ─────────────────
  static _AppShellState? _stateOf(BuildContext context) =>
      context.findAncestorStateOfType<_AppShellState>();

  /// true cuando el widget está dentro del árbol del shell (en el PageView).
  /// false cuando está en una ruta empujada encima del shell.
  static bool isActive(BuildContext context) => _stateOf(context) != null;

  /// Cambia la pestaña activa desde cualquier widget descendiente del shell.
  static void selectTab(BuildContext context, int navIndex) =>
      _stateOf(context)?._selectTab(navIndex);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late int _navIndex;
  late final PageController _pageController;

  // Correr se activa perezosamente: hasta la primera visita se muestra un
  // placeholder ligero en vez de montar LiveActivityScreen (GPS, mapa 3D,
  // animaciones en bucle), para no gastar batería si el usuario nunca
  // entra a esa pestaña.
  bool _correrActivado = false;

  // true = hay una carrera en curso sin pausar. Bloquea el swipe y oculta
  // la navbar para no poder salir sin querer de la pantalla de carrera.
  bool _correrSesionActiva = false;

  // Latido de "última vez visto en la app" — independiente de la pestaña en
  // la que esté el usuario. Social lo usa para saber quién está realmente
  // en línea (ver LastSeenService).
  Timer? _latidoTimer;

  @override
  void initState() {
    super.initState();
    _navIndex = widget.initialNavIndex;
    _pageController = PageController(initialPage: _navIndex);
    if (_navIndex == 1) _correrActivado = true;
    WidgetsBinding.instance.addObserver(this);
    LastSeenService.latido();
    _latidoTimer = Timer.periodic(
        const Duration(seconds: 90), (_) => LastSeenService.latido());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) LastSeenService.latido();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _latidoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _selectTab(int navIndex) {
    // Si hay pantallas apiladas encima del shell, volver al root primero
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
    if (navIndex == _navIndex) return;
    setState(() {
      if (navIndex == 1) _correrActivado = true;
    });
    _pageController.animateToPage(
      navIndex,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int i) {
    setState(() {
      _navIndex = i;
      if (i == 1) _correrActivado = true;
    });
  }

  void _onCorrerSesionActivaChanged(bool activa) {
    if (activa == _correrSesionActiva) return;
    setState(() => _correrSesionActiva = activa);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: _correrSesionActiva
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        children: [
          TickerMode(enabled: _navIndex == 0, child: const HomeScreen()),
          TickerMode(
            enabled: _navIndex == 1,
            child: _correrActivado
                ? LiveActivityScreen(
                    onSessionActiveChanged: _onCorrerSesionActivaChanged)
                : const _CorrerTabPlaceholder(),
          ),
          TickerMode(
              enabled: _navIndex == 2, child: const FullscreenMapScreen()),
          TickerMode(enabled: _navIndex == 3, child: const SocialScreen()),
          TickerMode(enabled: _navIndex == 4, child: const PerfilScreen()),
        ],
      ),
      bottomNavigationBar: _correrSesionActiva
          ? null
          : CustomBottomNavbar(
              currentIndex: _navIndex,
              onTabSelected: _selectTab,
            ),
    );
  }
}

/// Placeholder ligero mostrado en el hueco de Correr hasta la primera
/// visita — evita montar la sesión GPS/mapa mientras el usuario navega
/// por las demás pestañas.
class _CorrerTabPlaceholder extends StatelessWidget {
  const _CorrerTabPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: Colors.white24),
        ),
      ),
    );
  }
}
