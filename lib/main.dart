import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

// Importaciones
import 'main_wrapper.dart'; 
import 'Pestañas/Logging.dart'; 
import 'Pestañas/Home_screen.dart';
import 'Pestañas/social_screen.dart';
import 'Pestañas/Resumen_screen.dart';
import 'Pestañas/LiveActivity_screen.dart';

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
            return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));
          }
          if (snapshot.hasData) return const MainWrapper();
          return const LoginScreen(); 
        },
      ),

      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/social': (context) => const SocialScreen(),
        // QUITAMOS EL CONST AQUÍ PARA QUE NO DE ERROR:
        '/correr': (context) => LiveActivityScreen(), 
        '/resumen': (context) => const ResumenScreen(
          distancia: 0.0, 
          tiempo: Duration.zero, 
          ruta: [],
        ),
      },
    );
  }
}