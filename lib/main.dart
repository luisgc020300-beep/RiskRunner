// lib/main.dart
import 'package:RiskRunner/pesta%C3%B1as/coin_shop_screen.dart';
import 'package:RiskRunner/pesta%C3%B1as/fullscreen_map_screen.dart';
import 'package:RiskRunner/services/territory_service.dart' show TerritoryData;
import 'package:RiskRunner/pesta%C3%B1as/onboarding_slides_screen.dart';
import 'package:RiskRunner/services/notification_service.dart';
import 'package:RiskRunner/services/local_notif_service.dart';
import 'package:RiskRunner/services/onboarding_service.dart';
import 'package:RiskRunner/services/subscription_service.dart';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'theme/theme_notifier.dart';
import 'firebase_options.dart';
import 'config/env.dart';
import 'pestañas/notifications_screen.dart';
import 'pestañas/Logging.dart';
import 'pestañas/Home_screen.dart';
import 'pestañas/Social_screen.dart';
import 'pestañas/Resumen_screen.dart';
import 'pestañas/LiveActivity_screen.dart';
import 'pestañas/perfil_screen.dart';
import 'package:latlong2/latlong.dart';
import 'pestañas/clan_screen.dart';
import 'pestañas/desafios_screen.dart';
import 'services/desafios_service.dart';
import 'widgets/operative_bg.dart';
import 'widgets/offline_banner.dart';
import 'core/service_locator.dart';
import 'shell/app_shell.dart';

// Clave global para navegar desde notificaciones sin context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check: Play Integrity (Android) y App Attest (iOS) en producción.
  // En debug se usa el proveedor de depuración automáticamente.
  await FirebaseAppCheck.instance.activate(
    providerAndroid: const AndroidPlayIntegrityProvider(),
    providerApple: const AppleAppAttestProvider(),
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!Env.isDebug);
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(!Env.isDebug);

  await setupLocator();
  await LocalNotifService.init();
  mapbox.MapboxOptions.setAccessToken(Env.mapboxPublicToken);

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      NotificationService.inicializar();
      SubscriptionService.inicializar(user.uid);
      DesafiosService.verificarExpirados(user.uid);
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    ThemeNotifier.instance.addListener(_onThemeChange);
  }

  @override
  void dispose() {
    ThemeNotifier.instance.removeListener(_onThemeChange);
    super.dispose();
  }

  void _onThemeChange() => setState(() {});

  ThemeData _buildDarkTheme() {
    final base = GoogleFonts.interTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    );
    return ThemeData(
      brightness: Brightness.dark,
      primarySwatch: Colors.orange,
      scaffoldBackgroundColor: const Color(0xFF090807),
      textTheme: base,
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF090807),
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
          color: const Color(0xFFEAD9AA),
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    final base = GoogleFonts.interTextTheme(
      ThemeData(brightness: Brightness.light).textTheme,
    );
    return ThemeData(
      brightness: Brightness.light,
      primarySwatch: Colors.orange,
      scaffoldBackgroundColor: const Color(0xFFF2F2F7),
      textTheme: base,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          color: const Color(0xFF1C1C1E),
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Risk Runner',
      themeMode: ThemeNotifier.instance.mode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      builder: (context, child) => OfflineBanner(child: child!),
      // ── Tema de fallback (antiguo) eliminado — darkTheme lo cubre ──
      navigatorKey: navigatorKey,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SplashLoading();
          }
          if (snapshot.hasData) return const _OnboardingGate();
          return const LoginScreen();
        },
      ),
      onGenerateRoute: (settings) {
        switch (settings.name) {

          case '/login':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const LoginScreen(),
            );

          case '/home':
            return PageRouteBuilder(
              settings: settings,
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, __, ___) => const HomeScreen(),
            );

          case '/social':
            return PageRouteBuilder(
              settings: settings,
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, __, ___) => const SocialScreen(),
            );

          case '/perfil':
            return PageRouteBuilder(
              settings: settings,
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, __, ___) => const PerfilScreen(),
            );

          case '/notificaciones':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const NotificationsScreen(),
            );

          case '/clan':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const ClanScreen(),
            );

          case '/desafios':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => DesafiosScreen(
                desafioId: args?['desafioId'] as String?,
              ),
            );

          case '/correr':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const LiveActivityScreen(),
            );

          case '/resumen':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => ResumenScreen(
                distancia:              (args?['distancia']     as double?)   ?? 0.0,
                tiempo:                 (args?['tiempo']        as Duration?)  ?? Duration.zero,
                ruta:                   (args?['ruta']          as List?)?.cast<LatLng>() ?? [],
                esDesdeCarrera:         (args?['esDesdeCarrera'] as bool?)    ?? false,
                territoriosConquistados:(args?['territoriosConquistados'] as int?) ?? 0,
                puntosLigaGanados:      (args?['puntosLigaGanados']      as int?) ?? 0,
                objetivoGlobal:         args?['objetivoGlobal']  as Map<String, dynamic>?,
                globalConquistado:      (args?['globalConquistado'] as bool?) ?? false,
                nuevaClausula:          (args?['nuevaClausula'] as num?)?.toDouble(),
                modoRuta:               (args?['modoRuta']      as bool?)     ?? false,
                monedasRuta:            (args?['monedasRuta']   as int?)      ?? 0,
                modoInicial:            args?['modoInicial']    as String?,
                splitsPorKm:            (args?['splitsPorKm']   as List?)?.cast<double>(),
                velocidadMaxima:        (args?['velocidadMaxima'] as double?) ?? 0.0,
                elevacionGanada:        (args?['elevacionGanada'] as double?) ?? 0.0,
                elevacionPerdida:       (args?['elevacionPerdida'] as double?) ?? 0.0,
              ),
            );

          case '/mapa':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => FullscreenMapScreen(
                territorios:     (args?['territorios']     as List?)?.cast<TerritoryData>() ?? [],
                colorTerritorio: (args?['colorTerritorio'] as Color?)
                    ?? const Color(0xFFD4722A),
                centroInicial:   args?['centroInicial'] as LatLng?,
                ruta:            (args?['ruta']         as List?)?.cast<LatLng>() ?? [],
                mostrarRuta:     (args?['mostrarRuta']  as bool?) ?? false,
              ),
            );

          case '/ver-mapa':
            final verMapaArgs = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => FullscreenMapScreen(
                territorios:     (verMapaArgs?['territorios']     as List?)?.cast<TerritoryData>() ?? [],
                colorTerritorio: (verMapaArgs?['colorTerritorio'] as Color?)
                    ?? const Color(0xFFD4722A),
                centroInicial:   verMapaArgs?['centroInicial'] as LatLng?,
                ruta:            (verMapaArgs?['ruta']         as List?)?.cast<LatLng>() ?? [],
                mostrarRuta:     (verMapaArgs?['mostrarRuta']  as bool?) ?? false,
              ),
            );

          case '/tienda':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const CoinShopScreen(),
            );

          default:
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const HomeScreen(),
            );
        }
      },
    );
  }
}

// =============================================================================
// SPLASH
// =============================================================================
class _SplashLoading extends StatefulWidget {
  const _SplashLoading();
  @override
  State<_SplashLoading> createState() => _SplashLoadingState();
}

class _SplashLoadingState extends State<_SplashLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fade;
  late Animation<double>   _scale;
  late Animation<double>   _slideY;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.82, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _slideY = Tween<double>(begin: 18, end: 0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bg     = Color(0xFFE8E8ED);
    const dark   = Color(0xFF1C1C1E);
    const red    = Color(0xFFE02020);
    const dimmed = Color(0xFF8E8E93);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(children: [

        // Fondo con cuadrícula de puntos
        const Positioned.fill(
          child: CustomPaint(painter: OperativeBgPainter()),
        ),

        SafeArea(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Column(
              children: [
                const Spacer(flex: 3),

                // Icono
                Opacity(
                  opacity: _fade.value,
                  child: Transform.scale(
                    scale: _scale.value,
                    child: Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: red.withValues(alpha: 0.15),
                            blurRadius: 32,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Título + subtítulo
                Opacity(
                  opacity: _fade.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideY.value),
                    child: Column(children: [
                      Text(
                        'RISK RUNNER',
                        style: GoogleFonts.inter(
                          color:         dark,
                          fontSize:      26,
                          fontWeight:    FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'CONQUISTA TU CIUDAD',
                        style: GoogleFonts.inter(
                          color:         red,
                          fontSize:      10,
                          fontWeight:    FontWeight.w700,
                          letterSpacing: 3,
                        ),
                      ),
                    ]),
                  ),
                ),

                const Spacer(flex: 3),

                // Barra de carga
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 0, 40, 48),
                  child: Column(children: [
                    Text(
                      'Cargando...',
                      style: GoogleFonts.inter(
                          color: dimmed, fontSize: 11,
                          letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: const LinearProgressIndicator(
                        backgroundColor: Color(0xFFD1D1D6),
                        valueColor: AlwaysStoppedAnimation<Color>(red),
                        minHeight: 2,
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
// GATE: decide si mostrar slides o home
// =============================================================================
class _OnboardingGate extends StatefulWidget {
  const _OnboardingGate();
  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  OnboardingState? _state;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargarEstado();
  }

  Future<void> _cargarEstado() async {
    final state = await OnboardingService.cargarEstado();
    if (mounted) setState(() { _state = state; _loading = false; });
  }

  void _onSlidesCompleto() {
    setState(() {
      _state = OnboardingState(
        slidesVistos:    true,
        runActual:       _state?.runActual ?? 0,
        tooltipsVistos:  _state?.tooltipsVistos ?? {},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _state == null) return const _SplashLoading();
    if (!_state!.slidesVistos) {
      return OnboardingSlidesScreen(onComplete: _onSlidesCompleto);
    }
    return const AppShell();
  }
}