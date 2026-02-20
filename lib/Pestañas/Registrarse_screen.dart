import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Controladores para capturar lo que escribe el usuario
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  // Función principal de Registro
  Future<void> _register() async {
    final String nickname = _nicknameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();
    final String confirmPass = _confirmPasswordController.text.trim();

    // 1. Validaciones básicas antes de llamar a Firebase
    if (nickname.isEmpty || email.isEmpty || password.isEmpty) {
      _showError("Comandante, rellene todos los campos.");
      return;
    }

    if (password != confirmPass) {
      _showError("Las contraseñas no coinciden.");
      return;
    }

    if (password.length < 6) {
      _showError("La contraseña debe tener al menos 6 caracteres.");
      return;
    }

    try {
      // 2. Crear el usuario en Firebase Authentication
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 3. Crear el documento del jugador en Cloud Firestore
      // Usamos el UID único que Firebase le asignó al crear la cuenta
      await FirebaseFirestore.instance.collection('players').doc(userCredential.user!.uid).set({
        'nickname': nickname,
        'email': email,
        'victorias': 0,
        'nivel': 1,
        'monedas': 100,
        'fecha_registro': FieldValue.serverTimestamp(), // Fecha exacta del servidor
      });

      if (!mounted) return;

      // Éxito: Volver al Login
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("¡Registro completado! Bienvenido a la batalla."), backgroundColor: Colors.green),
      );
      Navigator.pop(context);

    } on FirebaseAuthException catch (e) {
      String errorMsg = "Ocurrió un error en el registro.";
      
      if (e.code == 'email-already-in-use') {
        errorMsg = "Este correo ya está registrado.";
      } else if (e.code == 'invalid-email') {
        errorMsg = "El formato del correo no es válido.";
      }
      
      _showError(errorMsg);
    } catch (e) {
      _showError("Error inesperado: $e");
    }
  }

  void _showError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ALTA DE COMANDANTE"),
        backgroundColor: Colors.redAccent,
        elevation: 0,
      ),
      body: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.redAccent, Colors.orangeAccent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Icon(Icons.shield, size: 80, color: Colors.white),
              const SizedBox(height: 20),
              
              // CAMPO NICKNAME
              TextField(
                controller: _nicknameController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputStyle("Nombre de Guerrero (Nickname)", Icons.person),
              ),
              const SizedBox(height: 16),

              // CAMPO EMAIL
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputStyle("Correo Electrónico", Icons.email),
              ),
              const SizedBox(height: 16),

              // CAMPO PASSWORD
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: _inputStyle("Contraseña", Icons.lock),
              ),
              const SizedBox(height: 16),

              // CAMPO CONFIRMAR PASSWORD
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: _inputStyle("Confirmar Contraseña", Icons.lock_outline),
              ),
              const SizedBox(height: 30),

              ElevatedButton(
                onPressed: _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.redAccent,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("UNIRSE A LA BATALLA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Estilo reutilizable para los campos de texto
  InputDecoration _inputStyle(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white),
      prefixIcon: Icon(icon, color: Colors.white),
      filled: true,
      fillColor: Colors.white.withOpacity(0.2),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white30),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white),
      ),
    );
  }
}