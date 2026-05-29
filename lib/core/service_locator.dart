// lib/core/service_locator.dart
//
// Service Locator — punto único de acceso a los servicios de la app.
//
// PATRÓN:
//   Registro (una vez en main): await setupLocator();
//   Acceso en cualquier lugar:  sl<ConnectivityService>().isOnline
//
// Los servicios se inicializan aquí antes de registrarse, de modo que
// main() solo necesita llamar setupLocator() en lugar de inicializar
// cada servicio por separado.

import 'package:get_it/get_it.dart';

import '../services/connectivity_service.dart';
import '../services/game_state_service.dart';
import '../theme/theme_notifier.dart';

final GetIt sl = GetIt.instance;

Future<void> setupLocator() async {
  // ── Theme ─────────────────────────────────────────────────────────────────
  final theme = ThemeNotifier.instance;
  await theme.init();
  sl.registerSingleton<ThemeNotifier>(theme);

  // ── Game state ────────────────────────────────────────────────────────────
  final gameState = GameStateService.instance;
  await gameState.initAsync();
  sl.registerSingleton<GameStateService>(gameState);

  // ── Connectivity ──────────────────────────────────────────────────────────
  final connectivity = ConnectivityService.instance;
  await connectivity.init();
  sl.registerSingleton<ConnectivityService>(connectivity);
}
