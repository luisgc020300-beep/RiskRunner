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
            return const Scaffold(
              body: Center(child: CircularProgressIndicator(color: Colors.orange)),
            );
          }
          if (snapshot.hasData) return const HomeScreen();
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
            distancia: (args?['distancia'] as double?) ?? 0.0,
            tiempo:    (args?['tiempo']    as Duration?) ?? Duration.zero,
            ruta:      (args?['ruta']      as List?)?.cast() ?? [],
            esDesdeCarrera: (args?['esDesdeCarrera'] as bool?) ?? false, 
          );
        },
      },
    );
  }
}
