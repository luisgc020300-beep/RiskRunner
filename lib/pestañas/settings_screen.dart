// lib/pestañas/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/theme_notifier.dart';
import '../models/avatar_config.dart';
import '../services/league_service.dart';
import '../services/zona_service.dart';
import '../scripts/seed_fantasmas_granada.dart';
import 'avatar_customizer_screen.dart';
import 'blocked_users_screen.dart';
import 'package:RiskRunner/theme/app_colors.dart';

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
  Color?       _colorTerritorio;
  bool         _savingColor     = false;
  bool         _esAdmin         = false;
  bool         _perfilPrivado   = false;
  bool         _savingPrivado   = false;
  AvatarConfig _avatarConfig    = const AvatarConfig();
  int          _monedas         = 0;

  bool get _tieneAuthPassword => FirebaseAuth.instance.currentUser?.providerData
          .any((p) => p.providerId == 'password') ??
      false;

  final Map<String, bool> _notifPrefs = {
    'social':      true,
    'desafios':    true,
    'clanes':      true,
    'territorios': true,
  };

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players')
          .doc(uid)
          .get();
      final d = doc.data() ?? {};
      final colorInt = (d['territorio_color'] as num?)?.toInt();
      final avatarJson = d['avatar'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          if (colorInt != null) _colorTerritorio = Color(colorInt);
          _esAdmin       = d['esAdmin'] as bool? ?? false;
          _monedas       = (d['monedas'] as num?)?.toInt() ?? 0;
          _perfilPrivado = d['perfilPrivado'] as bool? ?? false;
          final prefsGuardadas = d['notifPrefs'] as Map<String, dynamic>?;
          if (prefsGuardadas != null) {
            for (final k in _notifPrefs.keys) {
              if (prefsGuardadas[k] is bool) _notifPrefs[k] = prefsGuardadas[k] as bool;
            }
          }
          if (avatarJson != null) {
            try { _avatarConfig = AvatarConfig.fromMap(avatarJson); } catch (_) {}
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _abrirCustomizador() async {
    final nuevaConfig = await Navigator.push<AvatarConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => AvatarCustomizerScreen(
          initialConfig: _avatarConfig,
          monedas: _monedas,
        ),
      ),
    );
    if (nuevaConfig != null && mounted) {
      setState(() => _avatarConfig = nuevaConfig);
    }
  }

  // Diagnóstico temporal — lista TODOS mis territorios competitivos sin
  // límite geográfico (a diferencia de "Territorios en zona" del mapa, que
  // solo muestra los cercanos a la cámara), con borrado directo por fila.
  // Pensado para limpiar territorios de pruebas antiguas (sin 'modo' o con
  // pocos vértices, a diferencia de una carrera real).
  Future<void> _listarMisTerritorios(Color surface, Color textPri, Color textSec) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cargando tus territorios...')));
    try {
      final snap = await FirebaseFirestore.instance
          .collection('territories')
          .where('userId', isEqualTo: uid)
          .get();
      var propios = snap.docs.where((d) {
        final modo = d.data()['modo'] as String?;
        return modo == null || modo == 'competitivo';
      }).toList()
        ..sort((a, b) {
          final va = (a.data()['puntos'] as List?)?.length ?? 0;
          final vb = (b.data()['puntos'] as List?)?.length ?? 0;
          return va.compareTo(vb);
        });

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text('Mis territorios (${propios.length})',
                style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: textPri)),
            content: SizedBox(
              width: double.maxFinite,
              child: propios.isEmpty
                  ? Text('No queda ninguno.', style: GoogleFonts.inter(color: textSec))
                  : ListView.separated(
                shrinkWrap: true,
                itemCount: propios.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: textSec.withValues(alpha: 0.2)),
                itemBuilder: (_, i) {
                  final doc      = propios[i];
                  final d        = doc.data();
                  final vertices = (d['puntos'] as List?)?.length ?? 0;
                  final areaM2   = (d['area_m2'] as num?)?.toDouble();
                  final modo     = d['modo'] as String? ?? '(sin modo)';
                  final nombre   = d['nombre_territorio'] as String? ?? '(sin nombre)';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('$nombre — ${doc.id}',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textPri)),
                          Text(
                              '$vertices vértices'
                              '${areaM2 != null ? ' · ${areaM2.toStringAsFixed(0)} m²' : ''}'
                              ' · $modo',
                              style: GoogleFonts.inter(fontSize: 11, color: textSec)),
                        ]),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: ctx,
                            builder: (c2) => AlertDialog(
                              backgroundColor: surface,
                              title: Text('¿Borrar este territorio?',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textPri)),
                              content: Text('$nombre — $vertices vértices. No se puede deshacer.',
                                  style: GoogleFonts.inter(color: textSec)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c2, false),
                                  child: Text('Cancelar', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(c2, true),
                                  child: Text('Borrar',
                                      style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          try {
                            await doc.reference.delete();
                            propios = List.from(propios)..removeAt(i);
                            setDialogState(() {});
                          } catch (e) {
                            debugPrint('_listarMisTerritorios delete: $e');
                          }
                        },
                      ),
                    ]),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cerrar', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('_listarMisTerritorios: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _inicializarLiga(Color surface) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Inicializar liga',
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600)),
        content: Text('Se migrarán todos los jugadores sin liga asignada.',
            style: GoogleFonts.inter(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Confirmar',
                style: GoogleFonts.inter(color: Colors.tealAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicializando ligas...')));
    await LeagueService.migrarJugadoresSinLiga();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ligas inicializadas')));
    }
  }

  Future<void> _mostrarDialogoCerrarTemporada(Color surface, Color textPri, Color textSec) async {
    final temporada = await ZonaService.getTemporadaActiva();
    if (!mounted) return;
    if (temporada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay temporada activa')));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.gold, size: 18),
          const SizedBox(width: 10),
          Text('Cerrar ${temporada.label}',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: textPri)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Se calculará el rey de cada barrio y se entregarán las recompensas.',
              style: GoogleFonts.inter(fontSize: 13, color: textSec)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.20)),
            ),
            child: Row(children: [
              const Icon(Icons.monetization_on_rounded, color: AppColors.gold, size: 12),
              const SizedBox(width: 5),
              Expanded(child: Text(
                'Recompensa: ${temporada.monedasBase} monedas + corona',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.gold),
              )),
            ]),
          ),
          const SizedBox(height: 8),
          Text('Esta acción no se puede deshacer.',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.redAccent)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: textSec)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Calculando reyes...')));
              try {
                final n = await ZonaService.cerrarTemporada(temporada.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$n títulos otorgados. Temporada cerrada.')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: Text('CERRAR TEMPORADA',
                style: GoogleFonts.inter(color: AppColors.gold, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _seedFantasmas() async {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Creando fantasmas...')));
    await SeedFantasmasGranada.ejecutar();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fantasmas creados')));
    }
  }

  Future<void> _togglePerfilPrivado(bool val) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() { _perfilPrivado = val; _savingPrivado = true; });
    try {
      await FirebaseFirestore.instance
          .collection('players')
          .doc(uid)
          .update({'perfilPrivado': val});
    } catch (_) {
      if (mounted) setState(() => _perfilPrivado = !val);
    }
    if (mounted) setState(() => _savingPrivado = false);
  }

  Future<void> _cambiarContrasena(Color surface, Color textPri, Color textSec) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    final actualCtrl   = TextEditingController();
    final nuevaCtrl    = TextEditingController();
    final confirmarCtrl = TextEditingController();
    final loading      = ValueNotifier(false);
    final error        = ValueNotifier<String?>(null);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ValueListenableBuilder<bool>(
        valueListenable: loading,
        builder: (_, cargando, __) => AlertDialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Cambiar contraseña',
              style: GoogleFonts.inter(color: textPri, fontSize: 17, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: actualCtrl,
              obscureText: true,
              style: GoogleFonts.inter(color: textPri, fontSize: 14),
              decoration: InputDecoration(
                  labelText: 'Contraseña actual',
                  labelStyle: GoogleFonts.inter(color: textSec, fontSize: 13)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nuevaCtrl,
              obscureText: true,
              style: GoogleFonts.inter(color: textPri, fontSize: 14),
              decoration: InputDecoration(
                  labelText: 'Nueva contraseña (mín. 6 caracteres)',
                  labelStyle: GoogleFonts.inter(color: textSec, fontSize: 13)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmarCtrl,
              obscureText: true,
              style: GoogleFonts.inter(color: textPri, fontSize: 14),
              decoration: InputDecoration(
                  labelText: 'Confirmar nueva contraseña',
                  labelStyle: GoogleFonts.inter(color: textSec, fontSize: 13)),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: error,
              builder: (_, msg, __) => msg == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(msg,
                          style: GoogleFonts.inter(color: const Color(0xFFFF453A), fontSize: 12)),
                    ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: cargando ? null : () => Navigator.pop(ctx),
              child: Text('Cancelar', style: GoogleFonts.inter(color: textSec, fontWeight: FontWeight.w500)),
            ),
            TextButton(
              onPressed: cargando ? null : () async {
                final actual    = actualCtrl.text;
                final nueva     = nuevaCtrl.text;
                final confirmar = confirmarCtrl.text;
                if (nueva.length < 6) {
                  error.value = 'La nueva contraseña debe tener al menos 6 caracteres.';
                  return;
                }
                if (nueva != confirmar) {
                  error.value = 'Las contraseñas no coinciden.';
                  return;
                }
                loading.value = true;
                error.value   = null;
                try {
                  final cred = EmailAuthProvider.credential(email: user.email!, password: actual);
                  await user.reauthenticateWithCredential(cred);
                  await user.updatePassword(nueva);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Contraseña actualizada correctamente.')));
                  }
                } on FirebaseAuthException catch (e) {
                  loading.value = false;
                  error.value = switch (e.code) {
                    'wrong-password' || 'invalid-credential' => 'La contraseña actual no es correcta.',
                    'weak-password' => 'La nueva contraseña es demasiado débil.',
                    'requires-recent-login' => 'Por seguridad, cierra sesión y vuelve a entrar antes de cambiarla.',
                    _ => 'Error: ${e.message}',
                  };
                } catch (_) {
                  loading.value = false;
                  error.value = 'Error al cambiar la contraseña. Inténtalo de nuevo.';
                }
              },
              child: cargando
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Cambiar', style: GoogleFonts.inter(color: const Color(0xFFCC2222), fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleNotifPref(String categoria, bool val) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _notifPrefs[categoria] = val);
    try {
      await FirebaseFirestore.instance
          .collection('players')
          .doc(uid)
          .update({'notifPrefs.$categoria': val});
    } catch (_) {
      if (mounted) setState(() => _notifPrefs[categoria] = !val);
    }
  }

  Future<void> _reportarProblema(Color surface, Color textPri, Color textSec) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ctrl    = TextEditingController();
    final loading = ValueNotifier(false);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (bCtx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(bCtx).viewInsets.bottom + 28,
        ),
        child: ValueListenableBuilder<bool>(
          valueListenable: loading,
          builder: (_, cargando, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reportar un problema',
                  style: GoogleFonts.inter(color: textPri, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Cuéntanos qué ha fallado. Lo revisaremos lo antes posible.',
                  style: GoogleFonts.inter(color: textSec, fontSize: 12)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                maxLines: 5,
                maxLength: 500,
                style: GoogleFonts.inter(color: textPri, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Describe el problema...',
                  hintStyle: GoogleFonts.inter(color: textSec, fontSize: 13),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: cargando ? null : () async {
                    final mensaje = ctrl.text.trim();
                    if (mensaje.isEmpty) return;
                    loading.value = true;
                    try {
                      await FirebaseFirestore.instance.collection('soporte_mensajes').add({
                        'uid':       uid,
                        'email':     FirebaseAuth.instance.currentUser?.email,
                        'mensaje':   mensaje,
                        'estado':    'pendiente',
                        'timestamp': FieldValue.serverTimestamp(),
                      });
                      if (bCtx.mounted) Navigator.pop(bCtx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Gracias, hemos recibido tu reporte.')));
                      }
                    } catch (_) {
                      loading.value = false;
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('No se pudo enviar. Inténtalo de nuevo.'),
                          backgroundColor: Color(0xFFFF453A),
                        ));
                      }
                    }
                  },
                  child: cargando
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Enviar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace.')),
      );
    }
  }

  Future<void> _guardarColor(Color color) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() { _colorTerritorio = color; _savingColor = true; });
    try {
      await FirebaseFirestore.instance
          .collection('players')
          .doc(uid)
          .update({'territorio_color': color.toARGB32()});
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
                  final sel = _colorTerritorio?.toARGB32() == color.toARGB32();
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
    const accent  = Color(0xFFCC2222);

    final colorActual = _colorTerritorio;
    final (_, nombreColor) = colorActual != null
        ? _kTerritoryColors.firstWhere(
            (e) => e.$1.toARGB32() == colorActual.toARGB32(),
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

          // ── NOTIFICACIONES ─────────────────────────────────────────
          _SectionHeader(text: 'NOTIFICACIONES', color: textSec),
          _SettingsGroup(surface: surface, border: border, children: [
            _SwitchTile(
              icon: Icons.people_alt_rounded,
              iconColor: const Color(0xFF30D158),
              title: 'Social',
              subtitle: 'Seguidores, likes y comentarios',
              value: _notifPrefs['social']!,
              textPri: textPri,
              textSec: textSec,
              accentColor: accent,
              onChanged: (v) => _toggleNotifPref('social', v),
            ),
            _Divider(color: border),
            _SwitchTile(
              icon: Icons.sports_kabaddi_rounded,
              iconColor: const Color(0xFFFF9F0A),
              title: 'Desafíos',
              subtitle: 'Retos 1v1 recibidos y resueltos',
              value: _notifPrefs['desafios']!,
              textPri: textPri,
              textSec: textSec,
              accentColor: accent,
              onChanged: (v) => _toggleNotifPref('desafios', v),
            ),
            _Divider(color: border),
            _SwitchTile(
              icon: Icons.groups_rounded,
              iconColor: const Color(0xFF5E5CE6),
              title: 'Clanes',
              subtitle: 'Invitaciones y guerras de clan',
              value: _notifPrefs['clanes']!,
              textPri: textPri,
              textSec: textSec,
              accentColor: accent,
              onChanged: (v) => _toggleNotifPref('clanes', v),
            ),
            _Divider(color: border),
            _SwitchTile(
              icon: Icons.flag_rounded,
              iconColor: Colors.redAccent,
              title: 'Territorios',
              subtitle: 'Ataques, conquistas y Guerra Global',
              value: _notifPrefs['territorios']!,
              textPri: textPri,
              textSec: textSec,
              accentColor: accent,
              onChanged: (v) => _toggleNotifPref('territorios', v),
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
              icon: Icons.palette_rounded,
              iconColor: const Color(0xFF5E5CE6),
              title: 'Personalizar avatar',
              textPri: textPri,
              textSec: textSec,
              onTap: _abrirCustomizador,
            ),
            if (_tieneAuthPassword) ...[
              _Divider(color: border),
              _NavTile(
                icon: Icons.password_rounded,
                iconColor: const Color(0xFF5E5CE6),
                title: 'Cambiar contraseña',
                textPri: textPri,
                textSec: textSec,
                onTap: () => _cambiarContrasena(surface, textPri, textSec),
              ),
            ],
          ]),

          const SizedBox(height: 24),

          // ── PRIVACIDAD ────────────────────────────────────────────
          _SectionHeader(text: 'PRIVACIDAD', color: textSec),
          _SettingsGroup(surface: surface, border: border, children: [
            _SwitchTile(
              icon: Icons.lock_person_rounded,
              iconColor: const Color(0xFF636AE8),
              title: 'Perfil privado',
              subtitle: _perfilPrivado
                  ? 'Solo seguidores ven tus stats y posts'
                  : 'Cualquier jugador puede ver tu perfil',
              value: _perfilPrivado,
              textPri: textPri,
              textSec: textSec,
              accentColor: accent,
              onChanged: (v) { if (!_savingPrivado) _togglePerfilPrivado(v); },
            ),
            _Divider(color: border),
            _NavTile(
              icon: Icons.block_rounded,
              iconColor: const Color(0xFFFF453A),
              title: 'Usuarios bloqueados',
              textPri: textPri,
              textSec: textSec,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BlockedUsersScreen())),
            ),
            _Divider(color: border),
            _NavTile(
              icon: Icons.shield_outlined,
              iconColor: const Color(0xFF636AE8),
              title: 'Política de privacidad',
              textPri: textPri,
              textSec: textSec,
              onTap: () => _abrirUrl('https://fastidious-salmiakki-235a71.netlify.app/privacy.html'),
            ),
            _Divider(color: border),
            _NavTile(
              icon: Icons.description_outlined,
              iconColor: const Color(0xFF636AE8),
              title: 'Términos de uso',
              textPri: textPri,
              textSec: textSec,
              onTap: () => _abrirUrl('https://fastidious-salmiakki-235a71.netlify.app/terms.html'),
            ),
          ]),

          const SizedBox(height: 24),

          // ── AYUDA ──────────────────────────────────────────────────
          _SectionHeader(text: 'AYUDA', color: textSec),
          _SettingsGroup(surface: surface, border: border, children: [
            _NavTile(
              icon: Icons.flag_outlined,
              iconColor: const Color(0xFFFF9F0A),
              title: 'Reportar un problema',
              textPri: textPri,
              textSec: textSec,
              onTap: () => _reportarProblema(surface, textPri, textSec),
            ),
          ]),

          // ── ADMIN (solo si esAdmin) ───────────────────────────────
          if (_esAdmin) ...[
            const SizedBox(height: 24),
            _SectionHeader(text: 'ADMINISTRACIÓN', color: textSec),
            _SettingsGroup(surface: surface, border: border, children: [
              _NavTile(
                icon: Icons.sync_rounded,
                iconColor: Colors.tealAccent,
                title: 'Inicializar puntos de liga',
                textPri: textPri,
                textSec: textSec,
                showChevron: false,
                onTap: () => _inicializarLiga(surface),
              ),
              _Divider(color: border),
              _NavTile(
                icon: Icons.emoji_events_rounded,
                iconColor: AppColors.gold,
                title: 'Cerrar temporada',
                textPri: textPri,
                textSec: textSec,
                showChevron: false,
                onTap: () => _mostrarDialogoCerrarTemporada(surface, textPri, textSec),
              ),
              _Divider(color: border),
              _NavTile(
                icon: Icons.blur_on,
                iconColor: Colors.purpleAccent,
                title: 'Seed fantasmas Granada',
                textPri: textPri,
                textSec: textSec,
                showChevron: false,
                onTap: _seedFantasmas,
              ),
            ]),
          ],

          // ── HERRAMIENTAS (siempre visible — solo toca tus propios datos) ──
          const SizedBox(height: 24),
          _SectionHeader(text: 'HERRAMIENTAS', color: textSec),
          _SettingsGroup(surface: surface, border: border, children: [
            _NavTile(
              icon: Icons.list_alt_rounded,
              iconColor: Colors.tealAccent,
              title: 'Listar mis territorios (diagnóstico)',
              textPri: textPri,
              textSec: textSec,
              showChevron: false,
              onTap: () => _listarMisTerritorios(surface, textPri, textSec),
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
            _Divider(color: border),
            _NavTile(
              icon: Icons.delete_forever_rounded,
              iconColor: const Color(0xFFFF453A),
              title: 'Eliminar cuenta',
              titleColor: const Color(0xFFFF453A),
              textPri: textPri,
              textSec: textSec,
              showChevron: false,
              onTap: () => _eliminarCuenta(surface, textPri, textSec),
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

  Future<void> _eliminarCuenta(Color surface, Color textPri, Color textSec) async {
    final uid  = FirebaseAuth.instance.currentUser?.uid;
    final user = FirebaseAuth.instance.currentUser;
    if (uid == null || user == null) return;

    final loading = ValueNotifier(false);

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ValueListenableBuilder<bool>(
        valueListenable: loading,
        builder: (_, cargando, __) => AlertDialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(children: [
            const Icon(Icons.warning_rounded, color: Color(0xFFFF453A), size: 20),
            const SizedBox(width: 8),
            Text('Eliminar cuenta',
                style: GoogleFonts.inter(
                    color: const Color(0xFFFF453A),
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Esta acción es permanente e irreversible:',
                style: GoogleFonts.inter(color: textPri, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _BulletItem('Tu perfil y estadísticas serán eliminados', textSec),
            _BulletItem('Tus territorios quedarán libres', textSec),
            _BulletItem('No podrás recuperar tu progreso', textSec),
            const SizedBox(height: 4),
          ]),
          actions: [
            TextButton(
              onPressed: cargando ? null : () => Navigator.pop(ctx, false),
              child: Text('Cancelar',
                  style: GoogleFonts.inter(color: textSec, fontWeight: FontWeight.w500)),
            ),
            TextButton(
              onPressed: cargando ? null : () => Navigator.pop(ctx, true),
              child: Text('ELIMINAR',
                  style: GoogleFonts.inter(
                      color: const Color(0xFFFF453A), fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (confirmar != true || !mounted) return;

    try {
      final db = FirebaseFirestore.instance;

      // Liberar territorios del usuario
      final territorios = await db.collection('territories')
          .where('ownerUid', isEqualTo: uid)
          .get();
      final batch = db.batch();
      for (final doc in territorios.docs) {
        batch.update(doc.reference, {
          'ownerUid':      null,
          'ownerNickname': null,
          'color':         null,
        });
      }
      await batch.commit();

      // Borrar documento del jugador
      await db.collection('players').doc(uid).delete();

      // Borrar cuenta de Firebase Auth
      await user.delete();

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Por seguridad, cierra sesión, vuelve a iniciarla y repite esta acción.'),
          backgroundColor: Color(0xFFFF453A),
          duration: Duration(seconds: 5),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: ${e.message}'),
          backgroundColor: const Color(0xFFFF453A),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error al eliminar la cuenta. Inténtalo de nuevo.'),
        backgroundColor: Color(0xFFFF453A),
      ));
    }
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
              final nav = Navigator.of(context);
              await FirebaseAuth.instance.signOut();
              if (mounted) nav.pushNamedAndRemoveUntil('/login', (r) => false);
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
            activeThumbColor: accentColor,
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

class _BulletItem extends StatelessWidget {
  final String text;
  final Color color;
  const _BulletItem(this.text, this.color);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 4, height: 4,
              decoration: BoxDecoration(
                color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text,
              style: GoogleFonts.inter(color: color, fontSize: 13))),
        ]),
      );
}
