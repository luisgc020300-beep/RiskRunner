// lib/screens/avatar_customizer_screen.dart
//
// Pantalla de personalización del avatar.
// Se abre desde perfil_screen.dart
// Guarda la configuración en Firestore: players/{uid}/avatar_config (como subcampo)

import 'package:RunnerRisk/Widgets/avatar_widget.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/avatar_config.dart';

class AvatarCustomizerScreen extends StatefulWidget {
  final AvatarConfig initialConfig;
  final int monedas; // para saber qué puede comprar

  const AvatarCustomizerScreen({
    super.key,
    required this.initialConfig,
    required this.monedas,
  });

  @override
  State<AvatarCustomizerScreen> createState() => _AvatarCustomizerScreenState();
}

class _AvatarCustomizerScreenState extends State<AvatarCustomizerScreen>
    with TickerProviderStateMixin {

  late AvatarConfig _config;
  late int _monedas;
  bool _guardando = false;

  // Qué sección está activa: 'hair', 'eyes', 'jacket', 'pants', 'shoes'
  String _seccionActiva = 'hair';

  late AnimationController _previewAnim;
  late Animation<double> _previewScale;

  @override
  void initState() {
    super.initState();
    _config  = widget.initialConfig;
    _monedas = widget.monedas;

    _previewAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _previewScale = Tween<double>(begin: 0.95, end: 1.0).animate(
        CurvedAnimation(parent: _previewAnim, curve: Curves.easeOut));
    _previewAnim.forward();
  }

  @override
  void dispose() {
    _previewAnim.dispose();
    super.dispose();
  }

  // ── Guardar en Firestore ───────────────────────────────────────────
  Future<void> _guardar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _guardando = true);
    try {
      await FirebaseFirestore.instance
          .collection('players')
          .doc(user.uid)
          .update({'avatar_config': _config.toMap()});
      if (mounted) Navigator.pop(context, _config);
    } catch (e) {
      debugPrint('Error guardando avatar: $e');
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ── Comprar item premium ───────────────────────────────────────────
  Future<bool> _comprar(int coste, String nombre) async {
    if (_monedas < coste) {
      _mostrarSnack('No tienes suficientes monedas 😅', error: true);
      return false;
    }
    // Confirmación
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Desbloquear',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          '¿Gastar $coste 🪙 para desbloquear "$nombre"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Comprar',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmar != true) return false;

    // Descontar monedas en Firestore
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await FirebaseFirestore.instance
          .collection('players')
          .doc(user.uid)
          .update({'monedas': FieldValue.increment(-coste)});
      setState(() => _monedas -= coste);
      _mostrarSnack('¡$nombre desbloqueado! 🎉');
      return true;
    } catch (e) {
      _mostrarSnack('Error al comprar', error: true);
      return false;
    }
  }

  void _mostrarSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: error ? Colors.redAccent : Colors.orange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _animarCambio() {
    _previewAnim.forward(from: 0);
  }

  // ── BUILD ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Fondo degradado
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A0A0A), Color(0xFF1A0A00), Color(0xFF0A0A0A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            _buildHeader(),
            Expanded(
              child: Column(children: [
                const SizedBox(height: 16),
                _buildPreview(),
                const SizedBox(height: 20),
                _buildSectionTabs(),
                const SizedBox(height: 16),
                Expanded(child: _buildOptions()),
                _buildBotonGuardar(),
                const SizedBox(height: 16),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        const Expanded(
          child: Text(
            'PERSONALIZAR AVATAR',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('🪙', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              '$_monedas',
              style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w900,
                  fontSize: 14),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Preview del avatar ─────────────────────────────────────────────
  Widget _buildPreview() {
    return ScaleTransition(
      scale: _previewScale,
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.orange.withValues(alpha: 0.15),
                blurRadius: 30,
                spreadRadius: 5),
          ],
        ),
        child: Center(
          child: AvatarWidget(config: _config, size: 120),
        ),
      ),
    );
  }

  // ── Tabs de sección ────────────────────────────────────────────────
  Widget _buildSectionTabs() {
    final secciones = [
      {'id': 'hair',   'icon': '💇', 'label': 'Pelo'},
      {'id': 'eyes',   'icon': '👁️',  'label': 'Ojos'},
      {'id': 'jacket', 'icon': '🧥', 'label': 'Chaqueta'},
      {'id': 'pants',  'icon': '👖', 'label': 'Pantalón'},
      {'id': 'shoes',  'icon': '👟', 'label': 'Zapatillas'},
    ];

    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: secciones.map((s) {
          final bool activa = _seccionActiva == s['id'];
          return GestureDetector(
            onTap: () => setState(() => _seccionActiva = s['id'] as String),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: activa
                    ? Colors.orange.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: activa
                      ? Colors.orange.withValues(alpha: 0.6)
                      : Colors.white12,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s['icon'] as String,
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 2),
                  Text(
                    s['label'] as String,
                    style: TextStyle(
                      color: activa ? Colors.orange : Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Opciones según sección activa ──────────────────────────────────
  Widget _buildOptions() {
    switch (_seccionActiva) {
      case 'hair':
        return _buildHairOptions();
      case 'eyes':
        return _buildEyesOptions();
      case 'jacket':
        return _buildColorOptions(
          currentColor: _config.jacketColor,
          onColorSelected: (c) {
            setState(() => _config = _config.copyWith(jacketColor: c));
            _animarCambio();
          },
        );
      case 'pants':
        return _buildColorOptions(
          currentColor: _config.pantsColor,
          onColorSelected: (c) {
            setState(() => _config = _config.copyWith(pantsColor: c));
            _animarCambio();
          },
        );
      case 'shoes':
        return _buildColorOptions(
          currentColor: _config.shoesColor,
          onColorSelected: (c) {
            setState(() => _config = _config.copyWith(shoesColor: c));
            _animarCambio();
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Opciones de pelo ───────────────────────────────────────────────
  Widget _buildHairOptions() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: AvatarConfig.hairOptions.length,
      itemBuilder: (context, i) {
        final opt = AvatarConfig.hairOptions[i];
        final bool seleccionado = _config.hairIndex == i;
        final bool esPremium = opt['premium'] as bool;
        final int coste = opt['cost'] as int;

        return GestureDetector(
          onTap: () async {
            if (esPremium) {
              final comprado = await _comprar(coste, opt['name'] as String);
              if (!comprado) return;
            }
            setState(() => _config = _config.copyWith(hairIndex: i));
            _animarCambio();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: seleccionado
                  ? Colors.orange.withValues(alpha: 0.15)
                  : const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: seleccionado
                    ? Colors.orange
                    : Colors.white.withValues(alpha: 0.08),
                width: seleccionado ? 2 : 1,
              ),
            ),
            child: Stack(children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(
                    opt['asset'] as String,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.person_rounded,
                        color: Colors.white24,
                        size: 40),
                  ),
                ),
              ),
              // Nombre
              Positioned(
                bottom: 6,
                left: 0,
                right: 0,
                child: Text(
                  opt['name'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: seleccionado ? Colors.orange : Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Badge premium
              if (esPremium)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$coste 🪙',
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 8,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              // Check si está seleccionado
              if (seleccionado)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.orange, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 10),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }

  // ── Opciones de ojos ───────────────────────────────────────────────
  Widget _buildEyesOptions() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: AvatarConfig.eyesOptions.length,
      itemBuilder: (context, i) {
        final opt = AvatarConfig.eyesOptions[i];
        final bool seleccionado = _config.eyesIndex == i;
        final bool esPremium = opt['premium'] as bool;
        final int coste = opt['cost'] as int;

        return GestureDetector(
          onTap: () async {
            if (esPremium) {
              final comprado = await _comprar(coste, opt['name'] as String);
              if (!comprado) return;
            }
            setState(() => _config = _config.copyWith(eyesIndex: i));
            _animarCambio();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: seleccionado
                  ? Colors.orange.withValues(alpha: 0.15)
                  : const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: seleccionado ? Colors.orange : Colors.white.withValues(alpha: 0.08),
                width: seleccionado ? 2 : 1,
              ),
            ),
            child: Stack(children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(
                    opt['asset'] as String,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.remove_red_eye_rounded,
                        color: Colors.white24,
                        size: 40),
                  ),
                ),
              ),
              Positioned(
                bottom: 6, left: 0, right: 0,
                child: Text(
                  opt['name'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: seleccionado ? Colors.orange : Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (esPremium)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('$coste 🪙',
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 8,
                            fontWeight: FontWeight.w900)),
                  ),
                ),
              if (seleccionado)
                Positioned(
                  top: 6, left: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.orange, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 10),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }

  // ── Opciones de color (ropa) ───────────────────────────────────────
  Widget _buildColorOptions({
    required Color currentColor,
    required Function(Color) onColorSelected,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Colores gratis
          const Text('GRATIS',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AvatarConfig.freeColors.map((color) {
              final bool sel = currentColor.value == color.value;
              return GestureDetector(
                onTap: () => onColorSelected(color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: sel
                        ? [BoxShadow(
                            color: color.withValues(alpha: 0.6),
                            blurRadius: 12,
                            spreadRadius: 2)]
                        : [],
                  ),
                  child: sel
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 22)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Colores premium
          Row(children: [
            const Text('PREMIUM',
                style: TextStyle(
                    color: Colors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4))),
              child: const Text('🪙 Monedas',
                  style: TextStyle(
                      color: Colors.amber, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AvatarConfig.premiumColors.map((opt) {
              final Color color = opt['color'] as Color;
              final int coste = opt['cost'] as int;
              final bool sel = currentColor.value == color.value;
              return GestureDetector(
                onTap: () async {
                  final comprado =
                      await _comprar(coste, opt['name'] as String);
                  if (comprado) onColorSelected(color);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: color.withValues(alpha: 0.7),
                              blurRadius: sel ? 16 : 8,
                              spreadRadius: sel ? 3 : 1),
                        ],
                      ),
                      child: sel
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 22)
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text('$coste 🪙',
                        style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Botón guardar ──────────────────────────────────────────────────
  Widget _buildBotonGuardar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            elevation: 8,
            shadowColor: Colors.orange.withValues(alpha: 0.4),
          ),
          child: _guardando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.black, strokeWidth: 2))
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('GUARDAR AVATAR',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5)),
                  ],
                ),
        ),
      ),
    );
  }
}