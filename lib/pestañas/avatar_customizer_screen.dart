import 'package:RiskRunner/widgets/avatar_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/avatar_config.dart';
import '../services/subscription_service.dart';
import 'paywall_screen.dart';

// ── Paleta iOS dark (igual que Login / Register / Perfil) ──────────────────
const _kBg      = Color(0xFF090807);
const _kSurf    = Color(0xFF1C1C1E);
const _kSurf2   = Color(0xFF2C2C2E);
const _kBorder  = Color(0xFF38383A);
const _kBorder2 = Color(0xFF48484A);
const _kText    = Color(0xFFEEEEEE);
const _kSub     = Color(0xFF8E8E93);
const _kDim     = Color(0xFF636366);
const _kAccent  = Color(0xFFE02020);
const _kGold    = Color(0xFFFFD60A);

TextStyle _s(double size, FontWeight weight, Color color, {double spacing = 0}) =>
    GoogleFonts.inter(
      fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing);

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

  bool get _esPremium => SubscriptionService.currentStatus.isPremium;

  @override
  void initState() {
    super.initState();
    _config  = widget.initialConfig;
    _monedas = widget.monedas;

    _previewAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _previewScale = Tween<double>(begin: 0.93, end: 1.0).animate(
        CurvedAnimation(parent: _previewAnim, curve: Curves.easeOut));
    _previewAnim.forward();
  }

  @override
  void dispose() {
    _previewAnim.dispose();
    super.dispose();
  }

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
      if (mounted) {
        setState(() => _guardando = false);
        _mostrarSnack('Error al guardar el avatar', error: true);
      }
    }
  }

  Future<bool> _accederItemPremium(String nombre) async {
    if (_esPremium) return true;
    final comprado = await PaywallScreen.mostrar(
      context,
      featureOrigen: 'Avatar — $nombre',
    );
    if (comprado) {
      setState(() {});
      return true;
    }
    return false;
  }

  void _mostrarSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: _kSurf,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: error ? _kAccent.withValues(alpha: 0.4) : _kBorder),
        ),
        child: Text(msg, style: _s(13, FontWeight.w500, _kSub)),
      ),
    ));
  }

  void _animarCambio() => _previewAnim.forward(from: 0);

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SubscriptionStatus>(
      stream: SubscriptionService.statusStream,
      initialData: SubscriptionService.currentStatus,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: _kBg,
          body: SafeArea(
            child: Column(children: [
              _buildHeader(),
              Expanded(
                child: Column(children: [
                  const SizedBox(height: 20),
                  _buildPreview(),
                  const SizedBox(height: 24),
                  _buildSectionTabs(),
                  const SizedBox(height: 16),
                  Expanded(child: _buildOptions()),
                  _buildBotonGuardar(),
                  const SizedBox(height: 16),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _kSurf,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: _kSub, size: 14),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text('PERSONALIZAR AVATAR',
              style: _s(12, FontWeight.w800, _kText, spacing: 1.5)),
        ),
        _esPremium
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kGold.withValues(alpha: 0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.workspace_premium_rounded,
                      color: _kGold, size: 13),
                  const SizedBox(width: 5),
                  Text('PREMIUM',
                      style: _s(10, FontWeight.w800, _kGold, spacing: 0.8)),
                ]),
              )
            : Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _kSurf,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.toll_rounded, color: _kSub, size: 13),
                  const SizedBox(width: 5),
                  Text('$_monedas',
                      style: _s(13, FontWeight.w700, _kText)),
                ]),
              ),
      ]),
    );
  }

  // ── Preview ────────────────────────────────────────────────────────────────
  Widget _buildPreview() {
    return ScaleTransition(
      scale: _previewScale,
      child: Container(
        width: 148, height: 148,
        decoration: BoxDecoration(
          color: _kSurf,
          shape: BoxShape.circle,
          border: Border.all(color: _kBorder2, width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.5), blurRadius: 24),
          ],
        ),
        child: Center(
          child: AvatarWidget(config: _config, size: 110, fallbackLabel: 'TÚ'),
        ),
      ),
    );
  }

  // ── Tabs de sección ────────────────────────────────────────────────────────
  Widget _buildSectionTabs() {
    final secciones = [
      {'id': 'hair',   'icon': Icons.face_rounded,             'label': 'Pelo'},
      {'id': 'eyes',   'icon': Icons.remove_red_eye_rounded,   'label': 'Ojos'},
      {'id': 'jacket', 'icon': Icons.checkroom_rounded,        'label': 'Chaqueta'},
      {'id': 'pants',  'icon': Icons.accessibility_new_rounded,'label': 'Pantalón'},
      {'id': 'shoes',  'icon': Icons.directions_run_rounded,   'label': 'Zapatillas'},
    ];

    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: secciones.length,
        itemBuilder: (context, i) {
          final s = secciones[i];
          final bool activa = _seccionActiva == s['id'];
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _seccionActiva = s['id'] as String);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: activa
                    ? _kAccent.withValues(alpha: 0.10)
                    : _kSurf,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: activa
                      ? _kAccent.withValues(alpha: 0.50)
                      : _kBorder,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(s['icon'] as IconData,
                    color: activa ? _kAccent : _kDim, size: 13),
                const SizedBox(width: 6),
                Text(s['label'] as String,
                    style: _s(11,
                        activa ? FontWeight.w700 : FontWeight.w500,
                        activa ? _kAccent : _kSub)),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Opciones según sección activa ──────────────────────────────────────────
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

  // ── Grid de pelo ───────────────────────────────────────────────────────────
  Widget _buildHairOptions() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: AvatarConfig.hairOptions.length,
      itemBuilder: (context, i) {
        final opt = AvatarConfig.hairOptions[i];
        final bool sel = _config.hairIndex == i;
        final bool esPremium = opt['premium'] as bool;
        final bool bloqueado = esPremium && !_esPremium;

        return GestureDetector(
          onTap: () async {
            HapticFeedback.selectionClick();
            if (esPremium) {
              final acceso = await _accederItemPremium(opt['name'] as String);
              if (!acceso) return;
            }
            setState(() => _config = _config.copyWith(hairIndex: i));
            _animarCambio();
          },
          child: _buildGridItem(
            asset: opt['asset'] as String,
            name: opt['name'] as String,
            selected: sel,
            bloqueado: bloqueado,
            esPremium: esPremium,
            fallbackIcon: Icons.face_rounded,
          ),
        );
      },
    );
  }

  // ── Grid de ojos ───────────────────────────────────────────────────────────
  Widget _buildEyesOptions() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: AvatarConfig.eyesOptions.length,
      itemBuilder: (context, i) {
        final opt = AvatarConfig.eyesOptions[i];
        final bool sel = _config.eyesIndex == i;
        final bool esPremium = opt['premium'] as bool;
        final bool bloqueado = esPremium && !_esPremium;

        return GestureDetector(
          onTap: () async {
            HapticFeedback.selectionClick();
            if (esPremium) {
              final acceso = await _accederItemPremium(opt['name'] as String);
              if (!acceso) return;
            }
            setState(() => _config = _config.copyWith(eyesIndex: i));
            _animarCambio();
          },
          child: _buildGridItem(
            asset: opt['asset'] as String,
            name: opt['name'] as String,
            selected: sel,
            bloqueado: bloqueado,
            esPremium: esPremium,
            fallbackIcon: Icons.remove_red_eye_rounded,
          ),
        );
      },
    );
  }

  // ── Widget de item en grid ─────────────────────────────────────────────────
  Widget _buildGridItem({
    required String asset,
    required String name,
    required bool selected,
    required bool bloqueado,
    required bool esPremium,
    required IconData fallbackIcon,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected ? _kAccent.withValues(alpha: 0.08) : _kSurf,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? _kAccent.withValues(alpha: 0.65) : _kBorder,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Stack(children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
            child: Opacity(
              opacity: bloqueado ? 0.25 : 1.0,
              child: Image.asset(
                asset,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    Icon(fallbackIcon, color: _kDim, size: 36),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 6, left: 0, right: 0,
          child: Text(name,
              textAlign: TextAlign.center,
              style: _s(9, FontWeight.w700,
                  selected ? _kAccent : _kSub)),
        ),
        if (bloqueado)
          Positioned(
            top: 5, right: 5,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: _kGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: _kGold.withValues(alpha: 0.35)),
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: _kGold, size: 9),
            ),
          )
        else if (esPremium)
          Positioned(
            top: 5, right: 5,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: _kGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: _kGold.withValues(alpha: 0.30)),
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: _kGold, size: 9),
            ),
          ),
        if (selected)
          Positioned(
            top: 5, left: 5,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                  color: _kAccent, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 9),
            ),
          ),
      ]),
    );
  }

  // ── Opciones de color ──────────────────────────────────────────────────────
  Widget _buildColorOptions({
    required Color currentColor,
    required Function(Color) onColorSelected,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GRATIS',
              style: _s(10, FontWeight.w700, _kDim, spacing: 2)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: AvatarConfig.freeColors.map((color) {
              final bool sel = currentColor.toARGB32() == color.toARGB32();
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onColorSelected(color);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel ? Colors.white : Colors.transparent,
                      width: 2.5,
                    ),
                    boxShadow: sel
                        ? [BoxShadow(
                            color: color.withValues(alpha: 0.55),
                            blurRadius: 10, spreadRadius: 1)]
                        : [],
                  ),
                  child: sel
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          Row(children: [
            Text('PREMIUM',
                style: _s(10, FontWeight.w700, _kGold, spacing: 2)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _esPremium
                    ? _kGold.withValues(alpha: 0.10)
                    : _kSurf2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _esPremium
                      ? _kGold.withValues(alpha: 0.35)
                      : _kBorder,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.workspace_premium_rounded,
                    color: _esPremium ? _kGold : _kSub, size: 10),
                const SizedBox(width: 4),
                Text(_esPremium ? 'Incluido' : 'Suscripción',
                    style: _s(9, FontWeight.w700,
                        _esPremium ? _kGold : _kSub)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),

          Wrap(
            spacing: 12, runSpacing: 16,
            children: AvatarConfig.premiumColors.map((opt) {
              final Color color = opt['color'] as Color;
              final bool sel = currentColor.toARGB32() == color.toARGB32();
              final bool bloqueado = !_esPremium;

              return GestureDetector(
                onTap: () async {
                  if (bloqueado) {
                    final acceso =
                        await _accederItemPremium(opt['name'] as String);
                    if (!acceso) return;
                  }
                  HapticFeedback.selectionClick();
                  onColorSelected(color);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(
                                alpha: bloqueado ? 0.2 : (sel ? 0.7 : 0.45)),
                            blurRadius: sel ? 14 : 7,
                            spreadRadius: sel ? 2 : 0,
                          ),
                        ],
                      ),
                      child: bloqueado
                          ? Icon(Icons.lock_rounded,
                              color: Colors.white.withValues(alpha: 0.75),
                              size: 18)
                          : sel
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 20)
                              : null,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      bloqueado ? '' : opt['name'] as String,
                      style: _s(9, FontWeight.w700, _kGold),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          if (!_esPremium) ...[
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => PaywallScreen.mostrar(context,
                  featureOrigen: 'Colores neón y accesorios premium'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kGold.withValues(alpha: 0.22)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.workspace_premium_rounded,
                        color: _kGold, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Desbloquea todos los colores neón',
                            style: _s(13, FontWeight.w700, _kText)),
                        const SizedBox(height: 2),
                        Text(
                            'Matrix, Rosa neón, Cian, Oro — incluidos en Premium',
                            style: _s(11, FontWeight.w400, _kSub)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, color: _kDim),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Botón guardar (estilo Login) ───────────────────────────────────────────
  Widget _buildBotonGuardar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GestureDetector(
        onTap: _guardando
            ? null
            : () {
                HapticFeedback.mediumImpact();
                _guardar();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: _guardando ? _kSurf2 : _kText,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: _guardando
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: _kSub, strokeWidth: 2))
                : Text('Guardar avatar',
                    style: _s(16, FontWeight.w600, _kBg)),
          ),
        ),
      ),
    );
  }
}
