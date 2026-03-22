// lib/screens/avatar_customizer_screen.dart
//
// Pantalla de personalización del avatar.
// Se abre desde perfil_screen.dart
// Guarda la configuración en Firestore: players/{uid}/avatar_config (como subcampo)

import 'package:RiskRunner/Widgets/avatar_widget.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/avatar_config.dart';
import '../services/subscription_service.dart'; // ← NUEVO
import 'paywall_screen.dart';                   // ← NUEVO

class AvatarCustomizerScreen extends StatefulWidget {
  final AvatarConfig initialConfig;
  final int monedas;

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
  String _seccionActiva = 'hair';

  late AnimationController _previewAnim;
  late Animation<double> _previewScale;

  // ── Getter de conveniencia ─────────────────────────────────────────
  bool get _esPremium => SubscriptionService.currentStatus.isPremium;

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

  // ── Acceso a item premium ──────────────────────────────────────────
  // Devuelve true si puede usar el item (tiene premium o lo compra ahora)
  Future<bool> _accederItemPremium(String nombre) async {
    // Si ya tiene suscripción premium → acceso directo, sin coste de monedas
    if (_esPremium) return true;

    // Si no tiene premium → abrir paywall
    final comprado = await PaywallScreen.mostrar(
      context,
      featureOrigen: 'Avatar — $nombre',
    );

    // Si acaba de suscribirse → refrescar estado y permitir
    if (comprado) {
      setState(() {}); // rebuild para reflejar nuevo estado premium
      return true;
    }
    return false;
  }

  // ── Comprar con monedas (solo para items NO premium) ───────────────
  // Mantenemos este método por si en el futuro quieres items de monedas
  Future<bool> _comprarConMonedas(int coste, String nombre) async {
    if (_monedas < coste) {
      _mostrarSnack('No tienes suficientes monedas 😅', error: true);
      return false;
    }
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
            child: const Text('Comprar',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmar != true) return false;

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
    return StreamBuilder<SubscriptionStatus>(
      // Rebuild automático si el usuario se suscribe dentro de esta pantalla
      stream: SubscriptionService.statusStream,
      initialData: SubscriptionService.currentStatus,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(children: [
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
      },
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
        // Si es premium mostramos corona, si no mostramos monedas
        _esPremium
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDECA46).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDECA46).withOpacity(0.4)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('👑', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 4),
                  Text('PREMIUM',
                      style: TextStyle(
                          color: Color(0xFFDECA46),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 1)),
                ]),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🪙', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text('$_monedas',
                      style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w900,
                          fontSize: 14)),
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
          border: Border.all(color: Colors.orange.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.orange.withOpacity(0.15),
                blurRadius: 30,
                spreadRadius: 5),
          ],
        ),
        child: Center(
          child: AvatarWidget(config: _config, size: 120, fallbackLabel: 'TÚ'),
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
                    ? Colors.orange.withOpacity(0.15)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: activa ? Colors.orange.withOpacity(0.6) : Colors.white12,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s['icon'] as String, style: const TextStyle(fontSize: 18)),
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
      case 'hair':   return _buildHairOptions();
      case 'eyes':   return _buildEyesOptions();
      case 'jacket': return _buildColorOptions(
        currentColor: _config.jacketColor,
        onColorSelected: (c) {
          setState(() => _config = _config.copyWith(jacketColor: c));
          _animarCambio();
        },
      );
      case 'pants': return _buildColorOptions(
        currentColor: _config.pantsColor,
        onColorSelected: (c) {
          setState(() => _config = _config.copyWith(pantsColor: c));
          _animarCambio();
        },
      );
      case 'shoes': return _buildColorOptions(
        currentColor: _config.shoesColor,
        onColorSelected: (c) {
          setState(() => _config = _config.copyWith(shoesColor: c));
          _animarCambio();
        },
      );
      default: return const SizedBox.shrink();
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

        // Si es premium y el usuario NO tiene suscripción → mostrar candado
        final bool bloqueado = esPremium && !_esPremium;

        return GestureDetector(
          onTap: () async {
            if (esPremium) {
              final acceso = await _accederItemPremium(opt['name'] as String);
              if (!acceso) return;
            }
            setState(() => _config = _config.copyWith(hairIndex: i));
            _animarCambio();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: seleccionado
                  ? Colors.orange.withOpacity(0.15)
                  : const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: seleccionado
                    ? Colors.orange
                    : Colors.white.withOpacity(0.08),
                width: seleccionado ? 2 : 1,
              ),
            ),
            child: Stack(children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Opacity(
                    opacity: bloqueado ? 0.35 : 1.0,
                    child: Image.asset(
                      opt['asset'] as String,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.person_rounded, color: Colors.white24, size: 40),
                    ),
                  ),
                ),
              ),
              // Nombre
              Positioned(
                bottom: 6, left: 0, right: 0,
                child: Text(
                  opt['name'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: seleccionado ? Colors.orange : Colors.white54,
                    fontSize: 10, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Badge: candado si bloqueado, corona si premium desbloqueado
              if (bloqueado)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCC7C3A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('👑',
                        style: TextStyle(fontSize: 9)),
                  ),
                )
              else if (esPremium && _esPremium)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDECA46).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFFDECA46).withOpacity(0.5)),
                    ),
                    child: const Text('👑', style: TextStyle(fontSize: 9)),
                  ),
                ),
              // Check si seleccionado
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
        final bool bloqueado = esPremium && !_esPremium;

        return GestureDetector(
          onTap: () async {
            if (esPremium) {
              final acceso = await _accederItemPremium(opt['name'] as String);
              if (!acceso) return;
            }
            setState(() => _config = _config.copyWith(eyesIndex: i));
            _animarCambio();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: seleccionado
                  ? Colors.orange.withOpacity(0.15)
                  : const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: seleccionado
                    ? Colors.orange
                    : Colors.white.withOpacity(0.08),
                width: seleccionado ? 2 : 1,
              ),
            ),
            child: Stack(children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Opacity(
                    opacity: bloqueado ? 0.35 : 1.0,
                    child: Image.asset(
                      opt['asset'] as String,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.remove_red_eye_rounded,
                          color: Colors.white24, size: 40),
                    ),
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
                    fontSize: 10, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (bloqueado)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCC7C3A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('👑', style: TextStyle(fontSize: 9)),
                  ),
                )
              else if (esPremium && _esPremium)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDECA46).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('👑', style: TextStyle(fontSize: 9)),
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
          // Colores gratis — siempre disponibles
          const Text('GRATIS',
              style: TextStyle(color: Colors.white38, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 2)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: AvatarConfig.freeColors.map((color) {
              final bool sel = currentColor.value == color.value;
              return GestureDetector(
                onTap: () => onColorSelected(color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: sel
                        ? [BoxShadow(color: color.withOpacity(0.6),
                            blurRadius: 12, spreadRadius: 2)]
                        : [],
                  ),
                  child: sel
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Colores premium (neón) — requieren suscripción
          Row(children: [
            const Text('PREMIUM',
                style: TextStyle(color: Color(0xFFDECA46), fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 2)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _esPremium
                    ? const Color(0xFFDECA46).withOpacity(0.15)
                    : const Color(0xFFCC7C3A).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _esPremium
                      ? const Color(0xFFDECA46).withOpacity(0.4)
                      : const Color(0xFFCC7C3A).withOpacity(0.4),
                ),
              ),
              child: Text(
                _esPremium ? '👑 Incluido' : '👑 Suscripción',
                style: TextStyle(
                  color: _esPremium
                      ? const Color(0xFFDECA46)
                      : const Color(0xFFCC7C3A),
                  fontSize: 9, fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: AvatarConfig.premiumColors.map((opt) {
              final Color color = opt['color'] as Color;
              final bool sel = currentColor.value == color.value;
              final bool bloqueado = !_esPremium;

              return GestureDetector(
                onTap: () async {
                  if (bloqueado) {
                    final acceso = await _accederItemPremium(opt['name'] as String);
                    if (!acceso) return;
                  }
                  onColorSelected(color);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: sel ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(bloqueado ? 0.3 : 0.7),
                                blurRadius: sel ? 16 : 8,
                                spreadRadius: sel ? 3 : 1,
                              ),
                            ],
                          ),
                          child: bloqueado
                              ? Center(
                                  child: Icon(Icons.lock_rounded,
                                      color: Colors.white.withOpacity(0.8),
                                      size: 18))
                              : sel
                                  ? const Icon(Icons.check_rounded,
                                      color: Colors.white, size: 22)
                                  : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bloqueado ? '🔒' : opt['name'] as String,
                      style: TextStyle(
                        color: bloqueado
                            ? const Color(0xFFCC7C3A)
                            : const Color(0xFFDECA46),
                        fontSize: 9, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Banner si no es premium
          if (!_esPremium) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => PaywallScreen.mostrar(context,
                  featureOrigen: 'Colores neón y accesorios premium'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1C1410), Color(0xFF2A1E0E)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFCC7C3A).withOpacity(0.4)),
                ),
                child: const Row(children: [
                  Text('👑', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Desbloquea todos los colores neón',
                          style: TextStyle(color: Color(0xFFEAD9AA),
                              fontSize: 13, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text('Matrix, Rosa neón, Cian, Oro — incluidos en Premium',
                          style: TextStyle(
                              color: Color(0xFF8C7242), fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: Color(0xFFCC7C3A)),
                ]),
              ),
            ),
          ],
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
            shadowColor: Colors.orange.withOpacity(0.4),
          ),
          child: _guardando
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.black, strokeWidth: 2))
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('GUARDAR AVATAR',
                        style: TextStyle(fontSize: 15,
                            fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ],
                ),
        ),
      ),
    );
  }
}