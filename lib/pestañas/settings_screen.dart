// lib/pestañas/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/theme_notifier.dart';

// ── Colores de territorio disponibles ──────────────────────────────���─────────
const _kTerritoryColors = [
  (Color(0xFFD63B3B), 'Rojo'),
  (Color(0xFF3B6BBF), 'Azul'),
  (Color(0xFF4FA830), 'Verde'),
  (Color(0xFFC49430), 'Ocre'),
  (Color(0xFF8B35CC), 'Violeta'),
  (Color(0xFF2EAAAA), 'Teal'),
  (Color(0xFFA85820), 'Marrón'),
  (Color(0xFF7A8A96), 'Gris'),
  (Color(0xFFC46830), 'Bronce'),
  (Color(0xFF2A9470), 'Selva'),
  (Color(0xFFB03070), 'Granate'),
  (Color(0xFF5050B0), 'Noche'),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static Future<void> mostrar(BuildContext context) {
    return Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SettingsScreen(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Color? _colorTerritorio;
  bool   _savingColor = false;

  @override
  void initState() {
    super.initState();
    _cargarColor();
  }

  Future<void> _cargarColor() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players')
          .doc(uid)
          .get();
      final colorInt = (doc.data()?['territorio_color'] as num?)?.toInt();
      if (mounted && colorInt != null) {
        setState(() => _colorTerritorio = Color(colorInt));
      }
    } catch (_) {}
  }

  Future<void> _guardarColor(Color color) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() { _colorTerritorio = color; _savingColor = true; });
    try {
      await FirebaseFirestore.instance
          .collection('players')
          .doc(uid)
          .update({'territorio_color': color.value});
    } catch (_) {}
    if (mounted) setState(() => _savingColor = false);
  }

  void _mostrarColorPicker(Color bg, Color surface, Color border,
      Color textPri, Color textSec) {
    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(
                width: 32, height: 3,
                decoration: BoxDecoration(
                    color: border, borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 20),
              Text('Color de territorio',
                  style: GoogleFonts.inter(
                      color: textPri,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Así te verán otros jugadores en el mapa',
                  style: GoogleFonts.inter(
                      color: textSec, fontSize: 13)),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 16,
                children: _kTerritoryColors.map((entry) {
                  final (color, nombre) = entry;
                  final sel = _colorTerritorio?.value == color.value;
                  return GestureDetector(
                    onTap: () {
                      _guardarColor(color);
                      setM(() {});
                      Navigator.pop(ctx);
                    },
                    child: SizedBox(
                      width: 52,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width:  sel ? 44 : 38,
                            height: sel ? 44 : 38,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel ? Colors.white : border,
                                width: sel ? 2.5 : 1,
                              ),
                              boxShadow: sel
                                  ? [BoxShadow(
                                      color: color.withValues(alpha: 0.5),
                                      blurRadius: 10)]
                                  : [],
                            ),
                            child: sel
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 18)
                                : null,
                          ),
                          const SizedBox(height: 6),
                          Text(nombre,
                              style: GoogleFonts.inter(
                                color: sel ? color : textSec,
                                fontSize: 9,
                                fontWeight: sel
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                              textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg      = isDark ? const Color(0xFF090807) : const Color(0xFFF2F2F7);
    final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final border  = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFD1D1D6);
    final textPri = isDark ? const Color(0xFFEEEEEE) : const Color(0xFF1C1C1E);
    final textSec = isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366);
    final accent  = const Color(0xFFCC2222);

    final colorActual = _colorTerritorio;
    final (_, nombreColor) = colorActual != null
        ? _kTerritoryColors.firstWhere(
            (e) => e.$1.value == colorActual.value,
            orElse: () => (colorActual, 'Personalizado'))
        : (Colors.transparent, 'Cargando...');

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: border),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPri, size: 16),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Configuración',
            style: GoogleFonts.inter(
                color: textPri, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),

          // ── APARIENCIA ─────────────────────────────────────────────
          _SectionHeader(text: 'APARIENCIA', color: textSec),
          _SettingsGroup(surface: surface, border: border, children: [
            ListenableBuilder(
              listenable: ThemeNotifier.instance,
              builder: (_, __) => _SwitchTile(
                icon: ThemeNotifier.instance.isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                iconColor: ThemeNotifier.instance.isDark
                    ? const Color(0xFF636AE8)
                    : const Color(0xFFFFCC00),
                title: 'Modo oscuro',
                subtitle: ThemeNotifier.instance.isDark
                    ? 'Activado'
                    : 'Desactivado',
                value: ThemeNotifier.instance.isDark,
                textPri: textPri,
                textSec: textSec,
                accentColor: accent,
                onChanged: (_) => ThemeNotifier.instance.toggle(),
              ),
            ),
          ]),

          const SizedBox(height: 24),

          // ── JUEGO ──────────────────────────────────────────────────
          _SectionHeader(text: 'JUEGO', color: textSec),
          _SettingsGroup(surface: surface, border: border, children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () =>
                  _mostrarColorPicker(bg, surface, border, textPri, textSec),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 13),
                child: Row(children: [
                  // Swatch del color actual
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: colorActual ?? const Color(0xFF8B1A1A),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                          color: border.withValues(alpha: 0.6)),
                    ),
                    child: _savingColor
                        ? const Center(
                            child: SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 1.5),
                            ))
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Color de territorio',
                            style: GoogleFonts.inter(
                                color: textPri,
                                fontSize: 15,
                                fontWeight: FontWeight.w400)),
                        Text(nombreColor,
                            style: GoogleFonts.inter(
                                color: textSec,
                                fontSize: 12,
                                fontWeight: FontWeight.w400)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: textSec, size: 20),
                ]),
              ),
            ),
          ]),

          const SizedBox(height: 24),

          // ── CUENTA ─────────────────────────────────────────────────
          _SectionHeader(text: 'CUENTA', color: textSec),
          _SettingsGroup(surface: surface, border: border, children: [
            _NavTile(
              icon: Icons.person_outline_rounded,
              iconColor: const Color(0xFF30D158),
              title: 'Perfil',
              textPri: textPri,
              textSec: textSec,
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/perfil');
              },
            ),
            _Divider(color: border),
            _NavTile(
              icon: Icons.notifications_none_rounded,
              iconColor: const Color(0xFFFF9F0A),
              title: 'Notificaciones',
              textPri: textPri,
              textSec: textSec,
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/notificaciones');
              },
            ),
          ]),

          const SizedBox(height: 24),

          // ── PRIVACIDAD ────────────────────────────────────────────
          _SectionHeader(text: 'PRIVACIDAD', color: textSec),
          _SettingsGroup(surface: surface, border: border, children: [
            _NavTile(
              icon: Icons.shield_outlined,
              iconColor: const Color(0xFF636AE8),
              title: 'Política de privacidad',
              textPri: textPri,
              textSec: textSec,
              onTap: () {},
            ),
            _Divider(color: border),
            _NavTile(
              icon: Icons.description_outlined,
              iconColor: const Color(0xFF636AE8),
              title: 'Términos de uso',
              textPri: textPri,
              textSec: textSec,
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 24),

          // ── SESIÓN ────────────────────────────────────────────────
          _SectionHeader(text: 'SESIÓN', color: textSec),
          _SettingsGroup(surface: surface, border: border, children: [
            _NavTile(
              icon: Icons.logout_rounded,
              iconColor: accent,
              title: 'Cerrar sesión',
              titleColor: accent,
              textPri: textPri,
              textSec: textSec,
              showChevron: false,
              onTap: () =>
                  _confirmarCerrarSesion(context, textPri, textSec, surface),
            ),
          ]),

          const SizedBox(height: 40),

          Center(
            child: Text('RISK RUNNER v1.0.0',
                style: GoogleFonts.inter(
                    color: textSec, fontSize: 11, letterSpacing: 1.5)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _confirmarCerrarSesion(BuildContext context, Color textPri,
      Color textSec, Color surface) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: Text('Cerrar sesión',
            style: GoogleFonts.inter(
                color: textPri,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        content: Text('¿Estás seguro de que quieres cerrar sesión?',
            style: GoogleFonts.inter(color: textSec, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: GoogleFonts.inter(
                    color: textSec, fontWeight: FontWeight.w500)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/login', (r) => false);
              }
            },
            child: Text('Cerrar sesión',
                style: GoogleFonts.inter(
                    color: const Color(0xFFCC2222),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionHeader({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(text,
            style: GoogleFonts.inter(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5)),
      );
}

class _SettingsGroup extends StatelessWidget {
  final Color surface, border;
  final List<Widget> children;
  const _SettingsGroup(
      {required this.surface, required this.border, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: border.withValues(alpha: 0.5)),
        ),
        child: Column(children: children),
      );
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final Color textPri, textSec;
  final bool showChevron;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    required this.textPri,
    required this.textSec,
    this.showChevron = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title,
                  style: GoogleFonts.inter(
                      color: titleColor ?? textPri,
                      fontSize: 15,
                      fontWeight: FontWeight.w400)),
            ),
            if (showChevron)
              Icon(Icons.chevron_right_rounded, color: textSec, size: 20),
          ]),
        ),
      );
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final bool value;
  final Color textPri, textSec, accentColor;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.textPri,
    required this.textSec,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title,
                  style: GoogleFonts.inter(
                      color: textPri,
                      fontSize: 15,
                      fontWeight: FontWeight.w400)),
              Text(subtitle,
                  style: GoogleFonts.inter(
                      color: textSec,
                      fontSize: 12,
                      fontWeight: FontWeight.w400)),
            ]),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: accentColor,
          ),
        ]),
      );
}

class _Divider extends StatelessWidget {
  final Color color;
  const _Divider({required this.color});
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.only(left: 60),
        color: color.withValues(alpha: 0.5),
      );
}
