import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import 'Registrarse_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  // ... (Tus animaciones se mantienen igual que antes)
  late AnimationController _controller;
  late Animation<double> _contentOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _contentOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.45, 1.0, curve: Curves.easeIn)),
    );
    _controller.forward();
  }

  // --- FUNCIÓN PARA RECUPERAR CONTRASEÑA ---
Future<void> _resetPassword() async {
  if (_emailController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Escribe tu email arriba para enviarte el enlace"),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  try {
    await FirebaseAuth.instance.sendPasswordResetEmail(
      email: _emailController.text.trim(),
    );
    
    // MENSAJE MEJORADO
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.mark_email_read, color: Colors.white),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "¡Email enviado! Revisa tu bandeja de entrada o la carpeta de SPAM.",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blueAccent,
        duration: Duration(seconds: 6), // Más tiempo para leerlo
      ),
    );
  } on FirebaseAuthException catch (e) {
    String msg = "Error al enviar el email";
    if (e.code == 'user-not-found') msg = "No existe ningún usuario con este email";
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }
}
  // --- FUNCIÓN DE LOGIN ---
  Future<void> _login() async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomeScreen()));
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email o contraseña incorrectos"), backgroundColor: Colors.black87),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Colors.redAccent, Colors.deepOrange], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // (Aquí iría tu título animado que ya tienes)
              const Text("RUNNER RISK", style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              
              FadeTransition(
                opacity: _contentOpacity,
                child: Column(
                  children: [
                    TextField(
                      controller: _emailController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Email', filled: true, fillColor: Colors.white24),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Contraseña', filled: true, fillColor: Colors.white24),
                    ),

                    // BOTÓN DE RECUPERAR CONTRASEÑA
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _resetPassword,
                        child: const Text("¿Olvidaste tu contraseña?", style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                    ),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _login,
                        child: const Text('Iniciar sesión'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterScreen()));
                      },
                      child: const Text('¿No tienes cuenta? Regístrate', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}