// lib/main.dart
import 'package:RiskRunner/pesta%C3%B1as/coin_shop_screen.dart';
import 'package:RiskRunner/pesta%C3%B1as/fullscreen_map_screen.dart';
import 'package:RiskRunner/pesta%C3%B1as/onboarding_slides_screen.dart';
import 'package:RiskRunner/services/notification_service.dart';
import 'package:RiskRunner/services/onboarding_service.dart';
import 'package:RiskRunner/services/subscription_service.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/theme_notifier.dart';
import 'firebase_options.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ThemeNotifier.instance.init();

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
      // ── Tema de fallback (antiguo) eliminado — darkTheme lo cubre ──
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
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const HomeScreen(),
            );

          case '/social':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const SocialScreen(),
            );

          case '/perfil':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const PerfilScreen(),
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
              ),
            );

          case '/mapa':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => FullscreenMapScreen(
                territorios:     (args?['territorios']     as List?)?.cast() ?? [],
                colorTerritorio: (args?['colorTerritorio'] as Color?)
                    ?? const Color(0xFFD4722A),
                centroInicial:   args?['centroInicial'] as LatLng?,
                ruta:            (args?['ruta']         as List?)?.cast() ?? [],
                mostrarRuta:     (args?['mostrarRuta']  as bool?) ?? false,
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
class _SplashLoading extends StatelessWidget {
  const _SplashLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF090807),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AnimatedLogo(),
            SizedBox(height: 32),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Color(0xFFCC7C3A), strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedLogo extends StatefulWidget {
  const _AnimatedLogo();
  @override
  State<_AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<_AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: _pulse.value,
          child: Text(
            'RISK RUNNER',
            style: GoogleFonts.inter(
              color: const Color(0xFFCC7C3A),
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
            ),
          ),
        ),
      );
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
    return const HomeScreen();
  }
}