// lib/Pestañas/clan_screen.dart
// ═══════════════════════════════════════════════════════════
//  CLAN SCREEN — Pantalla principal del clan del usuario
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/clan_service.dart';
import 'create_clan_screen.dart';
import 'clan_war_screen.dart';
import 'clan_invite_screen.dart';

// Fixed accent colors — never change with theme
const _kAccent = Color(0xFFE02020);
const _kBlue   = Color(0xFFE02020);
const _kGreen  = Color(0xFF30D158);
const _kGold   = Color(0xFFFFD60A);

// Adaptive palette
class _CP {
  final Color bg, surface, surface2, sep, line2, dim, subtext, text, white;
  const _CP._({
    required this.bg, required this.surface, required this.surface2,
    required this.sep, required this.line2,
    required this.dim, required this.subtext, required this.text, required this.white,
  });
  static const light = _CP._(
    bg:       Color(0xFFE8E8ED),
    surface:  Color(0xFFFFFFFF),
    surface2: Color(0xFFE5E5EA),
    sep:      Color(0xFFC6C6C8),
    line2:    Color(0xFFD1D1D6),
    dim:      Color(0xFFAEAEB2),
    subtext:  Color(0xFF8E8E93),
    text:     Color(0xFF3C3C43),
    white:    Color(0xFF1C1C1E),
  );
  static const dark = _CP._(
    bg:       Color(0xFF090807),
    surface:  Color(0xFF1C1C1E),
    surface2: Color(0xFF2C2C2E),
    sep:      Color(0xFF38383A),
    line2:    Color(0xFF2C2C2E),
    dim:      Color(0xFF636366),
    subtext:  Color(0xFF8E8E93),
    text:     Color(0xFFD1D1D6),
    white:    Color(0xFFEEEEEE),
  );
  static _CP of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? dark : light;
}

TextStyle _raj(double size, FontWeight w, Color c, {double sp = 0}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, letterSpacing: sp);

TextStyle _dm(double size, FontWeight w, Color c, {double sp = 0}) =>
    GoogleFonts.dmSans(fontSize: size, fontWeight: w, color: c, letterSpacing: sp);

class ClanScreen extends StatefulWidget {
  const ClanScreen({super.key});
  @override
  State<ClanScreen> createState() => _ClanScreenState();
}

class _ClanScreenState extends State<ClanScreen>
    with SingleTickerProviderStateMixin {

  late AnimationController _anim;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StreamBuilder<ClanData?>(
        stream: ClanService.miClanStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2));
          }
          final clan = snap.data;
          return FadeTransition(
            opacity: _fade,
            child: clan == null ? _buildSinClan() : _buildConClan(clan),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  SIN CLAN
  // ══════════════════════════════════════════════════════════
  Widget _buildSinClan() {
    final canPop = Navigator.canPop(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Back si viene de perfil ──────────────────────
          if (canPop) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Row(children: [
                Icon(Icons.arrow_back_ios_new_rounded, color: _CP.of(context).text, size: 14),
                const SizedBox(width: 4),
                Text('VOLVER', style: _raj(11, FontWeight.w700, _CP.of(context).text, sp: 1.5)),
              ]),
            ),
          ],

          const SizedBox(height: 32),

          // ── Icono central ────────────────────────────────
          Center(child: Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              color: _CP.of(context).surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(child: Icon(Icons.shield_outlined, color: _CP.of(context).subtext, size: 40)),
          )),
          const SizedBox(height: 24),
          Center(child: Text('Sin afiliación', style: _dm(22, FontWeight.w700, _CP.of(context).white))),
          const SizedBox(height: 8),
          Center(child: Text(
            'Únete a un clan para conquistar\nterritorios en equipo',
            textAlign: TextAlign.center,
            style: _dm(14, FontWeight.w400, _CP.of(context).subtext),
          )),
          const SizedBox(height: 32),

          // ── Invitaciones pendientes ──────────────────────
          _InvitacionesBanner(),
          const SizedBox(height: 16),

          // ── Botón crear ──────────────────────────────────
          _BotonAccion(
            label: 'Fundar un clan',
            sub: 'Sé el líder. Define el territorio.',
            icon: Icons.flag_rounded,
            color: _kAccent,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CreateClanScreen())),
          ),
          const SizedBox(height: 1),

          // ── Botón buscar ─────────────────────────────────
          _BotonAccion(
            label: 'Buscar clanes',
            sub: 'Encuentra tu tribu en la ciudad.',
            icon: Icons.search_rounded,
            color: _kBlue,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ClanInviteScreen())),
          ),
          const SizedBox(height: 32),

          // ── Ranking global ───────────────────────────────
          _TopClanesWidget(),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  CON CLAN
  // ══════════════════════════════════════════════════════════
  Widget _buildConClan(ClanData clan) {
    final uid       = FirebaseAuth.instance.currentUser?.uid ?? '';
    final yo        = clan.miembro(uid);
    final esLider   = yo?.rol == ClanRol.lider;
    final esCapitan = yo?.rol == ClanRol.capitan || esLider;
    final clanColor = clan.colorObj;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: const Color(0xFF0D0D0D),
          expandedHeight: 180,
          pinned: true,
          elevation: 0,
          // ── Back si viene de perfil ──────────────────────
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                  onPressed: () => Navigator.pop(context),
                )
              : const SizedBox(),
          flexibleSpace: FlexibleSpaceBar(
            background: _buildHeroClan(clan, clanColor, esLider),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(0.5),
            child: Container(height: 0.5, color: _CP.of(context).sep),
          ),
          actions: [
            if (esLider)
              IconButton(
                icon: Icon(Icons.edit_outlined, color: _CP.of(context).text, size: 18),
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => CreateClanScreen(clanExistente: clan))),
              ),
          ],
        ),

        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _GuerraActivaBanner(clanId: clan.clanId, clanColor: clanColor),
            const SizedBox(height: 20),
            _buildStatsRow(clan, clanColor),
            const SizedBox(height: 24),
            if (esCapitan) ...[
              _buildLabel('Operaciones'),
              _buildAccionesGrid(clan, clanColor, esLider),
              const SizedBox(height: 24),
            ],
            _buildLabel('Miembros  ${clan.miembros.length}/${clan.maxMiembros}'),
            _MiembrosLista(clan: clan, yo: yo, esLider: esLider, esCapitan: esCapitan),
            const SizedBox(height: 24),
            _buildLabel('Historial de guerras'),
            _HistorialGuerras(clanId: clan.clanId),
            const SizedBox(height: 24),
            _buildBotonAbandonar(clan),
            const SizedBox(height: 40),
          ]),
        )),
      ],
    );
  }

  Widget _buildHeroClan(ClanData clan, Color clanColor, bool esLider) {
    return ColoredBox(
      color: _CP.of(context).bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Row(children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: clanColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(child: Text(clan.emoji, style: const TextStyle(fontSize: 34))),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('[${clan.tag}]', style: _dm(12, FontWeight.w600, clanColor)),
              const SizedBox(height: 2),
              Text(clan.nombre, style: _dm(20, FontWeight.w700, _CP.of(context).white)),
              if (clan.descripcion.isNotEmpty)
                Text(clan.descripcion, style: _dm(12, FontWeight.w400, _CP.of(context).subtext),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _buildStatsRow(ClanData clan, Color clanColor) {
    final winRate = (clan.winRate * 100).toStringAsFixed(0);
    return Row(children: [
      _StatChip(label: 'PUNTOS',    value: _formatNum(clan.puntos), color: _kGold),
      const SizedBox(width: 8),
      _StatChip(label: 'VICTORIAS', value: '${clan.victorias}',    color: const Color(0xFF4FA830)),
      const SizedBox(width: 8),
      _StatChip(label: 'WIN RATE',  value: '$winRate%',            color: clanColor),
    ]);
  }

  String _formatNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Widget _buildAccionesGrid(ClanData clan, Color clanColor, bool esLider) {
    return Row(children: [
      _AccionBtn(
        icon: Icons.bolt_rounded, label: 'GUERRA', color: _kAccent,
        onTap: () => _mostrarDeclarar(clan),
      ),
      const SizedBox(width: 8),
      _AccionBtn(
        icon: Icons.person_add_outlined, label: 'INVITAR', color: _kBlue,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ClanInviteScreen())),
      ),
      const SizedBox(width: 8),
      if (esLider) _AccionBtn(
        icon: Icons.tune_rounded, label: 'EDITAR', color: _CP.of(context).dim,
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => CreateClanScreen(clanExistente: clan))),
      ),
    ]);
  }

  void _mostrarDeclarar(ClanData miClan) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _CP.of(context).surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DeclararGuerraSheet(miClan: miClan),
    );
  }

  Widget _buildBotonAbandonar(ClanData clan) {
    final esUnico = clan.miembros.length == 1;
    return GestureDetector(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => _ConfirmDialog(
            titulo:  esUnico ? 'DISOLVER CLAN' : 'ABANDONAR CLAN',
            mensaje: esUnico
                ? 'Eres el último miembro. El clan se disolverá.'
                : 'Perderás todos tus puntos aportados al clan.',
            accion:  esUnico ? 'DISOLVER' : 'ABANDONAR',
          ),
        );
        if (confirm != true) return;
        try {
          await ClanService.abandonarClan(clan);
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', ''),
                style: _raj(13, FontWeight.w700, Colors.white)),
            backgroundColor: _kAccent,
          ));
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _CP.of(context).surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _CP.of(context).line2),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(esUnico ? Icons.delete_outline_rounded : Icons.logout_rounded,
              color: _CP.of(context).subtext, size: 16),
          const SizedBox(width: 8),
          Text(esUnico ? 'Disolver clan' : 'Abandonar clan',
              style: _dm(13, FontWeight.w500, _CP.of(context).subtext)),
        ]),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Text(text.toUpperCase(),
        style: _dm(11, FontWeight.w500, _CP.of(context).subtext, sp: 0.4)),
  );
}

// ══════════════════════════════════════════════════════════
//  WIDGETS INTERNOS — sin cambios
// ══════════════════════════════════════════════════════════

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: _CP.of(context).surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        Text(value, style: _raj(20, FontWeight.w900, color)),
        const SizedBox(height: 2),
        Text(label, style: _dm(9, FontWeight.w600, _CP.of(context).subtext, sp: 0.3)),
      ]),
    ),
  );
}

class _AccionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AccionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _CP.of(context).surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(label, style: _dm(9, FontWeight.w700, color, sp: 0.5)),
        ]),
      ),
    ),
  );
}

class _MiembrosLista extends StatelessWidget {
  final ClanData clan;
  final ClanMiembro? yo;
  final bool esLider, esCapitan;
  const _MiembrosLista({required this.clan, this.yo, required this.esLider, required this.esCapitan});

  @override
  Widget build(BuildContext context) {
    final sorted = [...clan.miembros]
      ..sort((a, b) => b.puntosAportados.compareTo(a.puntosAportados));
    return Container(
      decoration: BoxDecoration(color: _CP.of(context).surface, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: sorted.asMap().entries.map((e) =>
            _MiembroTile(
              miembro: e.value, posicion: e.key + 1,
              clanColor: clan.colorObj, clan: clan,
              yo: yo, esLider: esLider, esCapitan: esCapitan,
            )).toList(),
      ),
    );
  }
}

class _MiembroTile extends StatelessWidget {
  final ClanMiembro miembro;
  final int posicion;
  final Color clanColor;
  final ClanData clan;
  final ClanMiembro? yo;
  final bool esLider, esCapitan;

  const _MiembroTile({
    required this.miembro, required this.posicion, required this.clanColor,
    required this.clan, this.yo, required this.esLider, required this.esCapitan,
  });

  @override
  Widget build(BuildContext context) {
    final rolColor = miembro.rol == ClanRol.lider ? const Color(0xFFD4A84C)
        : miembro.rol == ClanRol.capitan ? const Color(0xFF8B9CC0) : _CP.of(context).dim;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final esYo  = miembro.uid == myUid;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(children: [
            SizedBox(width: 20,
              child: Text('$posicion', style: _raj(13, FontWeight.w700,
                  posicion == 1 ? _kGold : _CP.of(context).dim))),
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: esYo ? clanColor.withValues(alpha: 0.15) : _CP.of(context).surface2,
                shape: BoxShape.circle,
              ),
              child: Center(child: Text(
                miembro.nickname.isNotEmpty ? miembro.nickname[0].toUpperCase() : '?',
                style: _raj(15, FontWeight.w700, esYo ? clanColor : _CP.of(context).text),
              )),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(miembro.nickname, style: _dm(14, FontWeight.w500, _CP.of(context).white)),
                if (esYo) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: clanColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('tú', style: _dm(10, FontWeight.w600, clanColor)),
                  ),
                ],
              ]),
              Text(miembro.rol.nombre, style: _dm(12, FontWeight.w400, rolColor)),
            ])),
            Text('${miembro.puntosAportados} pts',
                style: _raj(12, FontWeight.w700, _CP.of(context).subtext)),
            if (esCapitan && !esYo && miembro.rol != ClanRol.lider) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showOpciones(context),
                child: Icon(Icons.more_horiz_rounded, color: _CP.of(context).dim, size: 20),
              ),
            ],
          ]),
        ),
        Container(height: 0.5, color: _CP.of(context).sep, margin: const EdgeInsets.only(left: 66)),
      ],
    );
  }

  void _showOpciones(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D10),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _MiembroOpcionesSheet(clan: clan, miembro: miembro, esLider: esLider),
    );
  }
}

class _MiembroOpcionesSheet extends StatelessWidget {
  final ClanData clan;
  final ClanMiembro miembro;
  final bool esLider;
  const _MiembroOpcionesSheet({required this.clan, required this.miembro, required this.esLider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(miembro.nickname, style: _dm(16, FontWeight.w600, _CP.of(context).white)),
        const SizedBox(height: 16),
        if (esLider && miembro.rol == ClanRol.miembro)
          _OpcionBtn(
            icon: Icons.arrow_upward_rounded, label: 'ASCENDER A CAPITÁN',
            color: const Color(0xFF8B9CC0),
            onTap: () async {
              Navigator.pop(context);
              await ClanService.promoverMiembro(
                  clan: clan, miembro: miembro, nuevoRol: ClanRol.capitan);
            },
          ),
        if (esLider && miembro.rol == ClanRol.capitan)
          _OpcionBtn(
            icon: Icons.arrow_downward_rounded, label: 'DEGRADAR A MIEMBRO',
            color: _CP.of(context).dim,
            onTap: () async {
              Navigator.pop(context);
              await ClanService.promoverMiembro(
                  clan: clan, miembro: miembro, nuevoRol: ClanRol.miembro);
            },
          ),
        _OpcionBtn(
          icon: Icons.person_remove_outlined, label: 'EXPULSAR DEL CLAN',
          color: _kAccent,
          onTap: () async {
            Navigator.pop(context);
            await ClanService.expulsarMiembro(clan: clan, miembro: miembro);
          },
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _OpcionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _OpcionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color, size: 20),
    title: Text(label, style: _dm(14, FontWeight.w500, color)),
    onTap: onTap,
  );
}

class _GuerraActivaBanner extends StatelessWidget {
  final String clanId;
  final Color clanColor;
  const _GuerraActivaBanner({required this.clanId, required this.clanColor});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClanWar>>(
      stream: ClanService.guerrasActivasDeMiClan(clanId),
      builder: (_, snap) {
        final guerras = snap.data ?? [];
        if (guerras.isEmpty) return const SizedBox();
        final war    = guerras.first;
        final rival  = war.clanA['id'] == clanId ? war.clanB : war.clanA;
        final miPun  = (war.clanA['id'] == clanId ? war.puntuacion['clanA'] : war.puntuacion['clanB']) ?? 0;
        final rivalPun = (war.clanA['id'] == clanId ? war.puntuacion['clanB'] : war.puntuacion['clanA']) ?? 0;

        return GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => ClanWarScreen(war: war))),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _CP.of(context).surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.bolt_rounded, color: _kAccent, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('GUERRA ACTIVA', style: _dm(11, FontWeight.w700, _kAccent, sp: 0.5)),
                const SizedBox(height: 2),
                Text('vs [${rival['tag']}] ${rival['nombre']}',
                    style: _dm(14, FontWeight.w600, _CP.of(context).white)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$miPun - $rivalPun', style: GoogleFonts.inter(
                    fontSize: 20, fontWeight: FontWeight.w900, color: _CP.of(context).white)),
                Text(war.tiempoRestanteStr, style: _dm(11, FontWeight.w500, _kAccent)),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

class _HistorialGuerras extends StatelessWidget {
  final String clanId;
  const _HistorialGuerras({required this.clanId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ClanWar>>(
      future: ClanService.historialGuerras(clanId),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _kAccent, strokeWidth: 2));
        }
        final lista = snap.data ?? [];
        if (lista.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: _CP.of(context).surface, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text('No hay guerras registradas',
                style: _dm(13, FontWeight.w400, _CP.of(context).subtext))),
          );
        }
        return Container(
          decoration: BoxDecoration(color: _CP.of(context).surface, borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.hardEdge,
          child: Column(children: lista.asMap().entries.map((entry) {
            final w         = entry.value;
            final ganamos   = w.ganadorId == clanId;
            final empate    = w.ganadorId == null;
            final rival     = w.clanA['id'] == clanId ? w.clanB : w.clanA;
            final miPun     = (w.clanA['id'] == clanId ? w.puntuacion['clanA'] : w.puntuacion['clanB']) ?? 0;
            final rivalPun  = (w.clanA['id'] == clanId ? w.puntuacion['clanB'] : w.puntuacion['clanA']) ?? 0;
            final resultColor = empate ? _CP.of(context).subtext : ganamos ? _kGreen : _kAccent;
            final resultLabel = empate ? 'Empate' : ganamos ? 'Victoria' : 'Derrota';

            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(children: [
                  SizedBox(width: 62,
                    child: Text(resultLabel, style: _dm(12, FontWeight.w600, resultColor))),
                  Expanded(child: Text('vs [${rival['tag']}] ${rival['nombre']}',
                      style: _dm(13, FontWeight.w400, _CP.of(context).text))),
                  Text('$miPun — $rivalPun', style: _raj(14, FontWeight.w700, _CP.of(context).white)),
                ]),
              ),
              if (entry.key < lista.length - 1)
                Container(height: 0.5, color: _CP.of(context).sep, margin: const EdgeInsets.only(left: 16)),
            ]);
          }).toList()),
        );
      },
    );
  }
}

class _InvitacionesBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClanInvite>>(
      stream: ClanService.misInvitacionesPendientes(),
      builder: (_, snap) {
        final invites = snap.data ?? [];
        if (invites.isEmpty) return const SizedBox();
        return GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ClanInviteScreen())),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.mail_outline_rounded, color: _kBlue, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(
                '${invites.length} invitación${invites.length > 1 ? 'es' : ''} pendiente${invites.length > 1 ? 's' : ''}',
                style: _dm(14, FontWeight.w600, _kBlue),
              )),
              const Icon(Icons.chevron_right_rounded, color: _kBlue, size: 18),
            ]),
          ),
        );
      },
    );
  }
}

class _TopClanesWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClanData>>(
      stream: ClanService.topClanes(limit: 5),
      builder: (_, snap) {
        final clanes = snap.data ?? [];
        if (clanes.isEmpty) return const SizedBox();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Top clanes', style: _dm(12, FontWeight.w600, _CP.of(context).subtext)),
          ]),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(color: _CP.of(context).surface, borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.hardEdge,
            child: Column(children: clanes.asMap().entries.map((e) {
              final c = e.value;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  child: Row(children: [
                    SizedBox(width: 22, child: Text('${e.key + 1}', style: _raj(14, FontWeight.w700,
                        e.key == 0 ? _kGold : _CP.of(context).dim))),
                    Text(c.emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.nombre, style: _dm(13, FontWeight.w600, _CP.of(context).white)),
                      Text('[${c.tag}]  ·  ${c.miembros.length} miembros',
                          style: _dm(11, FontWeight.w400, _CP.of(context).subtext)),
                    ])),
                    Text('${c.puntos} pts', style: _raj(13, FontWeight.w700, _kGold)),
                  ]),
                ),
                if (e.key < clanes.length - 1)
                  Container(height: 0.5, color: _CP.of(context).sep, margin: const EdgeInsets.only(left: 16)),
              ]);
            }).toList()),
          ),
        ]);
      },
    );
  }
}

class _DeclararGuerraSheet extends StatefulWidget {
  final ClanData miClan;
  const _DeclararGuerraSheet({required this.miClan});
  @override
  State<_DeclararGuerraSheet> createState() => _DeclararGuerraSheetState();
}

class _DeclararGuerraSheetState extends State<_DeclararGuerraSheet> {
  final _buscarCtrl = TextEditingController();
  List<ClanData> _resultados = [];
  ClanData? _rival;
  String _tipo     = 'conquista';
  int    _durHoras = 48;
  bool   _loading  = false;

  Future<void> _buscar(String q) async {
    if (q.length < 2) { setState(() => _resultados = []); return; }
    final r = await ClanService.buscarClanes(q);
    setState(() => _resultados = r.where((c) => c.clanId != widget.miClan.clanId).toList());
  }

  Future<void> _declarar() async {
    if (_rival == null) return;
    setState(() => _loading = true);
    try {
      await ClanService.declararGuerra(
        miClan: widget.miClan, rivalClan: _rival!,
        tipo: _tipo, duracion: Duration(hours: _durHoras),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', ''),
            style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: _kAccent,
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Declarar guerra', style: _dm(17, FontWeight.w700, _CP.of(context).white)),
        const SizedBox(height: 16),
        if (_rival == null) ...[
          TextField(
            controller: _buscarCtrl,
            onChanged: _buscar,
            style: _dm(14, FontWeight.w400, _CP.of(context).white),
            decoration: InputDecoration(
              hintText: 'Buscar clan rival...',
              hintStyle: _dm(14, FontWeight.w400, _CP.of(context).dim),
              filled: true, fillColor: _CP.of(context).surface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _CP.of(context).line2)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _CP.of(context).line2)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kAccent)),
              prefixIcon: Icon(Icons.search_rounded, color: _CP.of(context).subtext, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          ..._resultados.map((c) => ListTile(
            dense: true,
            leading: Text(c.emoji, style: const TextStyle(fontSize: 20)),
            title: Text('[${c.tag}] ${c.nombre}', style: _dm(13, FontWeight.w600, _CP.of(context).white)),
            subtitle: Text('${c.miembros.length} miembros  ·  ${c.puntos} pts',
                style: _dm(11, FontWeight.w400, _CP.of(context).subtext)),
            onTap: () => setState(() { _rival = c; _resultados = []; }),
          )),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _CP.of(context).surface2, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kAccent.withValues(alpha: 0.3))),
            child: Row(children: [
              Text(_rival!.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(child: Text('[${_rival!.tag}] ${_rival!.nombre}',
                  style: _dm(14, FontWeight.w600, _CP.of(context).white))),
              GestureDetector(onTap: () => setState(() => _rival = null),
                  child: Icon(Icons.close_rounded, color: _CP.of(context).subtext, size: 16)),
            ]),
          ),
          const SizedBox(height: 16),
          Text('Tipo', style: _dm(12, FontWeight.w600, _CP.of(context).subtext)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: _CP.of(context).surface2,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(children: ['conquista', 'asedio', 'resistencia'].map((t) {
              final sel = t == _tipo;
              return Expanded(child: GestureDetector(
                onTap: () => setState(() => _tipo = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? _CP.of(context).surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Center(child: Text(t,
                      style: _dm(12, sel ? FontWeight.w600 : FontWeight.w400,
                          sel ? _CP.of(context).white : _CP.of(context).subtext))),
                ),
              ));
            }).toList()),
          ),
          const SizedBox(height: 16),
          Text('Duración  ·  $_durHoras horas', style: _dm(12, FontWeight.w600, _CP.of(context).subtext)),
          Slider(
            value: _durHoras.toDouble(), min: 24, max: 168, divisions: 6,
            activeColor: _kAccent, inactiveColor: _CP.of(context).line2,
            onChanged: (v) => setState(() => _durHoras = v.round()),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _declarar,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _CP.of(context).surface2,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Declarar guerra', style: _dm(15, FontWeight.w600, Colors.white)),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _BotonAccion extends StatelessWidget {
  final String label, sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _BotonAccion({required this.label, required this.sub, required this.icon,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.lightImpact(); onTap(); },
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: _CP.of(context).surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _dm(15, FontWeight.w600, _CP.of(context).white)),
          Text(sub, style: _dm(12, FontWeight.w400, _CP.of(context).subtext)),
        ])),
        Icon(Icons.chevron_right_rounded, color: _CP.of(context).dim, size: 20),
      ]),
    ),
  );
}

class _ConfirmDialog extends StatelessWidget {
  final String titulo, mensaje, accion;
  const _ConfirmDialog({required this.titulo, required this.mensaje, required this.accion});

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _CP.of(context).surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    title: Text(titulo, style: _dm(16, FontWeight.w600, _CP.of(context).white)),
    content: Text(mensaje, style: _dm(14, FontWeight.w400, _CP.of(context).text)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false),
          child: Text('Cancelar', style: _dm(15, FontWeight.w400, _CP.of(context).subtext))),
      TextButton(onPressed: () => Navigator.pop(context, true),
          child: Text(accion, style: _dm(15, FontWeight.w600, _kAccent))),
    ],
  );
}