// lib/pestañas/settings_screen.dart
//
// Pantalla de Configuración — estilo iOS/Instagram
// Accesible desde el botón de engranaje en la barra superior.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/theme_notifier.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  /// Abre la pantalla de ajustes como modal sheet desde cualquier contexto.
  static Future<void> mostrar(BuildContext context) {
    return Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SettingsScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            SlideTransition(
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
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg       = isDark ? const Color(0xFF090807) : const Color(0xFFF2F2F7);
    final surface  = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final border   = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFD1D1D6);
    final textPri  = isDark ? const Color(0xFFEEEEEE) : const Color(0xFF1C1C1E);
    final textSec  = isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366);
    final accent   = const Color(0xFFCC2222);

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
        title: Text(
          'Configuración',
          style: GoogleFonts.inter(
            color: textPri,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
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
                subtitle: ThemeNotifier.instance.isDark ? 'Activado' : 'Desactivado',
                value: ThemeNotifier.instance.isDark,
                textPri: textPri,
                textSec: textSec,
                accentColor: accent,
                onChanged: (_) => ThemeNotifier.instance.toggle(),
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
              onTap: () => _confirmarCerrarSesion(context, textPri, textSec, surface),
            ),
          ]),

          const SizedBox(height: 40),

          // ── VERSIÓN ───────────────────────────────────────────────
          Center(
            child: Text(
              'RISK RUNNER v1.0.0',
              style: GoogleFonts.inter(
                color: textSec,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _confirmarCerrarSesion(
    BuildContext context,
    Color textPri,
    Color textSec,
    Color surface,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Cerrar sesión',
            style: GoogleFonts.inter(
                color: textPri, fontSize: 17, fontWeight: FontWeight.w600)),
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
            color: color, fontSize: 12, fontWeight: FontWeight.w500,
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
      border: Border.all(color: border.withValues(alpha: 0.5)),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: GoogleFonts.inter(
                  color: textPri, fontSize: 15, fontWeight: FontWeight.w400)),
          Text(subtitle,
              style: GoogleFonts.inter(
                  color: textSec, fontSize: 12, fontWeight: FontWeight.w400)),
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
