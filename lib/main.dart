import 'package:RunnerRisk/Pesta%C3%B1as/onboarding_slides_screen.dart';
import 'package:RunnerRisk/services/onboarding_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'Pestañas/notifications_screen.dart';
import 'Pestañas/Logging.dart';
import 'Pestañas/Home_screen.dart';
import 'Pestañas/social_screen.dart';
import 'Pestañas/Resumen_screen.dart';
import 'Pestañas/LiveActivity_screen.dart';
import 'Pestañas/perfil_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Runner Risk',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SplashLoading();
          }
          if (snapshot.hasData) {
            // Usuario logado → decidir si mostrar onboarding o home
            return const _OnboardingGate();
          }
          return const LoginScreen();
        },
      ),
      routes: {
        '/login':   (context) => const LoginScreen(),
        '/home':    (context) => const HomeScreen(),
        '/social':  (context) => const SocialScreen(),
        '/correr':  (context) => const LiveActivityScreen(),
        '/perfil':  (context) => const PerfilScreen(),
        '/notificaciones': (context) => const NotificationsScreen(),
        '/resumen': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;
          return ResumenScreen(
            distancia: (args?['distancia'] as double?)   ?? 0.0,
            tiempo:    (args?['tiempo']    as Duration?)  ?? Duration.zero,
            ruta:      (args?['ruta']      as List?)?.cast() ?? [],
            esDesdeCarrera: (args?['esDesdeCarrera'] as bool?) ?? false,
          );
        },
      },
    );
  }
}

// =============================================================================
// SPLASH de carga (mientras firebase inicializa)
// =============================================================================
class _SplashLoading extends StatelessWidget {
  const _SplashLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF060608),
      body: Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AnimatedLogo(),
          SizedBox(height: 32),
          SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(
              color: Color(0xFFFF7B1A), strokeWidth: 2)),
        ],
      )),
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
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Opacity(
      opacity: _pulse.value,
      child: const Text('RUNNER RISK', style: TextStyle(
        color: Color(0xFFFF7B1A), fontSize: 22,
        fontWeight: FontWeight.w900, letterSpacing: 5,
      )),
    ),
  );
}

// =============================================================================
// GATE: decide si mostrar slides, o home directamente
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
        slidesVistos: true,
        runActual: _state?.runActual ?? 0,
        tooltipsVistos: _state?.tooltipsVistos ?? {},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _state == null) return const _SplashLoading();

    // ¿Nunca vio los slides? → mostrar slides
    if (!_state!.slidesVistos) {
      return OnboardingSlidesScreen(onComplete: _onSlidesCompleto);
    }

    // Ya vio slides → ir a Home normalmente
    return const HomeScreen();
  }
}