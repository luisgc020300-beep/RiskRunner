// lib/main.dart
import 'package:RiskRunner/Pesta%C3%B1as/coin_shop_screen.dart';
import 'package:RiskRunner/Pesta%C3%B1as/fullscreen_map_screen.dart';
import 'package:RiskRunner/Pesta%C3%B1as/onboarding_slides_screen.dart';
import 'package:RiskRunner/services/notification_service.dart';
import 'package:RiskRunner/services/onboarding_service.dart';
import 'package:RiskRunner/services/subscription_service.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'Pestañas/notifications_screen.dart';
import 'Pestañas/Logging.dart';
import 'Pestañas/Home_screen.dart';
import 'Pestañas/social_screen.dart';
import 'Pestañas/Resumen_screen.dart';
import 'Pestañas/LiveActivity_screen.dart';
import 'Pestañas/perfil_screen.dart';
import 'package:latlong2/latlong.dart';
import 'Pestañas/clan_screen.dart';
import 'Pestañas/desafios_screen.dart';
import 'services/desafios_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final rajdhaniBase = GoogleFonts.rajdhaniTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Risk Runner',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: const Color(0xFF090807),
        textTheme: rajdhaniBase.copyWith(
          displayLarge: rajdhaniBase.displayLarge?.copyWith(
              fontWeight: FontWeight.w700, letterSpacing: 1.0),
          displayMedium: rajdhaniBase.displayMedium?.copyWith(
              fontWeight: FontWeight.w700, letterSpacing: 0.8),
          headlineLarge: rajdhaniBase.headlineLarge?.copyWith(
              fontWeight: FontWeight.w900, letterSpacing: 2.5),
          headlineMedium: rajdhaniBase.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900, letterSpacing: 2.0),
          headlineSmall: rajdhaniBase.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800, letterSpacing: 1.5),
          bodyLarge: rajdhaniBase.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500, letterSpacing: 0.3),
          bodyMedium: rajdhaniBase.bodyMedium?.copyWith(
              fontWeight: FontWeight.w400),
          labelLarge: rajdhaniBase.labelLarge?.copyWith(
              fontWeight: FontWeight.w800, letterSpacing: 1.5),
          labelMedium: rajdhaniBase.labelMedium?.copyWith(
              fontWeight: FontWeight.w700, letterSpacing: 1.2),
          labelSmall: rajdhaniBase.labelSmall?.copyWith(
              fontWeight: FontWeight.w700, letterSpacing: 1.5),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF090807),
          elevation: 0,
          titleTextStyle: GoogleFonts.rajdhani(
            color: const Color(0xFFEAD9AA),
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 3.0,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            textStyle: GoogleFonts.rajdhani(
                fontWeight: FontWeight.w800, letterSpacing: 1.5),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: GoogleFonts.rajdhani(
                fontWeight: FontWeight.w700, letterSpacing: 1.2),
          ),
        ),
      ),
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

          // ── /resumen ahora acepta todos los campos extras de Guerra Global
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
                // ── Guerra Global
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
            style: GoogleFonts.rajdhani(
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