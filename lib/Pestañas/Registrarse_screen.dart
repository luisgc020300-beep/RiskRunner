// lib/screens/register_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  Future<void> _register() async {
    final String nickname = _nicknameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();
    final String confirmPass = _confirmPasswordController.text.trim();

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
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await FirebaseFirestore.instance
          .collection('players')
          .doc(userCredential.user!.uid)
          .set({
        'nickname': nickname,
        'email': email,
        'victorias': 0,
        'nivel': 1,
        'monedas': 100,
        'fecha_registro': FieldValue.serverTimestamp(),
        // Protección de 7 días: el territorio no puede ser robado
        'proteccion_hasta': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 7)),
        ),
        // Liga inicial: todos empiezan en bronce con 0 puntos
        // ★ minúsculas para coincidir con LeagueSystem
        'liga': 'bronce',
        'puntos_liga': 0,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("¡Registro completado! Bienvenido a la batalla."),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String errorMsg = "Ocurrió un error en el registro.";
      if (e.code == 'email-already-in-use') {
        errorMsg = "Este correo ya está registrado.";
      }
      if (e.code == 'invalid-email') {
        errorMsg = "El formato del correo no es válido.";
      }
      _showError(errorMsg);
    } catch (e) {
      _showError("Error inesperado: $e");
    }
  }

  void _showError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black, Colors.grey.shade900],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.orange),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const Icon(Icons.shield_moon_outlined,
                    color: Colors.orange, size: 70),
                const SizedBox(height: 20),
                const Text(
                  "NUEVO RECLUTA",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const Text(
                  "RELLENA TUS DATOS DE COMBATE",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 40),
                _buildTextField(
                  controller: _nicknameController,
                  label: "Nombre de Guerrero (Nickname)",
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _emailController,
                  label: "Correo Electrónico",
                  icon: Icons.email_outlined,
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _passwordController,
                  label: "Contraseña",
                  icon: Icons.lock_outline,
                  isPassword: true,
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _confirmPasswordController,
                  label: "Confirmar Contraseña",
                  icon: Icons.lock_reset_outlined,
                  isPassword: true,
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 5,
                      shadowColor: Colors.orange.withValues(alpha: 0.4),
                    ),
                    child: const Text(
                      "UNIRSE A LA BATALLA",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.orange, size: 22),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.orange, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
      ),
    );
  }
}