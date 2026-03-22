// lib/Pestañas/clan_screen.dart
// ═══════════════════════════════════════════════════════════
//  CLAN SCREEN — Pantalla principal del clan del usuario
// ═══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/clan_service.dart';
import 'create_clan_screen.dart';
import 'clan_war_screen.dart';
import 'clan_invite_screen.dart';

const _kBg       = Color(0xFF060608);
const _kSurface  = Color(0xFF0D0D10);
const _kSurface2 = Color(0xFF131318);
const _kLine     = Color(0xFF1C1C24);
const _kLine2    = Color(0xFF242430);
const _kDim      = Color(0xFF3A3A4A);
const _kSubtext  = Color(0xFF5A5A70);
const _kText     = Color(0xFFAAAAAC);
const _kWhite    = Color(0xFFF0F0F2);
const _kAccent   = Color(0xFFCC2222);
const _kGold     = Color(0xFFD4A84C);

TextStyle _raj(double size, FontWeight w, Color c, {double sp = 0}) =>
    GoogleFonts.rajdhani(fontSize: size, fontWeight: w, color: c, letterSpacing: sp);

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
      backgroundColor: _kBg,
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
                const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 14),
                const SizedBox(width: 4),
                Text('VOLVER', style: _raj(11, FontWeight.w700, _kText, sp: 1.5)),
              ]),
            ),
          ],

          const SizedBox(height: 32),

          // ── Icono central ────────────────────────────────
          Center(child: Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kLine2),
            ),
            child: const Center(child: Text('⚔️', style: TextStyle(fontSize: 40))),
          )),
          const SizedBox(height: 24),
          Center(child: Text('SIN AFILIACIÓN', style: _raj(22, FontWeight.w900, _kWhite, sp: 3))),
          const SizedBox(height: 8),
          Center(child: Text(
            'Únete a un clan para conquistar\nterritorios en equipo',
            textAlign: TextAlign.center,
            style: _raj(13, FontWeight.w400, _kSubtext),
          )),
          const SizedBox(height: 32),

          // ── Invitaciones pendientes ──────────────────────
          _InvitacionesBanner(),
          const SizedBox(height: 16),

          // ── Botón crear ──────────────────────────────────
          _BotonAccion(
            label: 'FUNDAR UN CLAN',
            sub: 'Sé el líder. Define el territorio.',
            emoji: '🏴',
            color: _kAccent,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CreateClanScreen())),
          ),
          const SizedBox(height: 12),

          // ── Botón buscar ─────────────────────────────────
          _BotonAccion(
            label: 'BUSCAR CLANES',
            sub: 'Encuentra tu tribu en la ciudad.',
            emoji: '🔍',
            color: const Color(0xFF3B6BBF),
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
          backgroundColor: _kBg,
          expandedHeight: 180,
          pinned: true,
          elevation: 0,
          // ── Back si viene de perfil ──────────────────────
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 18),
                  onPressed: () => Navigator.pop(context),
                )
              : const SizedBox(),
          flexibleSpace: FlexibleSpaceBar(
            background: _buildHeroClan(clan, clanColor, esLider),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: _kLine),
          ),
          actions: [
            if (esLider)
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: _kText, size: 18),
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
              _buildLabel('OPERACIONES'),
              const SizedBox(height: 12),
              _buildAccionesGrid(clan, clanColor, esLider),
              const SizedBox(height: 24),
            ],
            _buildLabel('MIEMBROS  ${clan.miembros.length}/${clan.maxMiembros}'),
            const SizedBox(height: 12),
            _MiembrosLista(clan: clan, yo: yo, esLider: esLider, esCapitan: esCapitan),
            const SizedBox(height: 24),
            _buildLabel('HISTORIAL DE GUERRAS'),
            const SizedBox(height: 12),
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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [clanColor.withValues(alpha: 0.25), _kBg],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Row(children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: clanColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: clanColor.withValues(alpha: 0.5), width: 2),
              ),
              child: Center(child: Text(clan.emoji, style: const TextStyle(fontSize: 34))),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: clanColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: clanColor.withValues(alpha: 0.5)),
                ),
                child: Text('[${clan.tag}]', style: _raj(10, FontWeight.w900, clanColor, sp: 1)),
              ),
              const SizedBox(height: 4),
              Text(clan.nombre, style: _raj(22, FontWeight.w900, _kWhite, sp: 0.5)),
              if (clan.descripcion.isNotEmpty)
                Text(clan.descripcion, style: _raj(11, FontWeight.w400, _kSubtext),
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
        emoji: '⚔️', label: 'GUERRA', color: _kAccent,
        onTap: () => _mostrarDeclarar(clan),
      ),
      const SizedBox(width: 8),
      _AccionBtn(
        emoji: '📨', label: 'INVITAR', color: const Color(0xFF3B6BBF),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ClanInviteScreen())),
      ),
      const SizedBox(width: 8),
      if (esLider) _AccionBtn(
        emoji: '⚙️', label: 'EDITAR', color: _kDim,
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => CreateClanScreen(clanExistente: clan))),
      ),
    ]);
  }

  void _mostrarDeclarar(ClanData miClan) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
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
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kLine2),
        ),
        child: Center(child: Text(
          esUnico ? '💀  DISOLVER CLAN' : '🚪  ABANDONAR CLAN',
          style: _raj(12, FontWeight.w700, _kSubtext, sp: 1.5),
        )),
      ),
    );
  }

  Widget _buildLabel(String text) => Row(children: [
    Container(width: 3, height: 12, color: _kAccent, margin: const EdgeInsets.only(right: 8)),
    Text(text, style: _raj(9, FontWeight.w800, _kSubtext, sp: 2.5)),
  ]);
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(children: [
        Text(value, style: GoogleFonts.rajdhani(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.rajdhani(fontSize: 8, fontWeight: FontWeight.w800,
            color: color.withValues(alpha: 0.6), letterSpacing: 1.5)),
      ]),
    ),
  );
}

class _AccionBtn extends StatelessWidget {
  final String emoji, label;
  final Color color;
  final VoidCallback onTap;
  const _AccionBtn({required this.emoji, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.rajdhani(fontSize: 9, fontWeight: FontWeight.w800,
              color: color, letterSpacing: 1.5)),
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
    return Column(
      children: sorted.asMap().entries.map((e) =>
          _MiembroTile(
            miembro: e.value, posicion: e.key + 1,
            clanColor: clan.colorObj, clan: clan,
            yo: yo, esLider: esLider, esCapitan: esCapitan,
          )).toList(),
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
        : miembro.rol == ClanRol.capitan ? const Color(0xFF8B9CC0) : _kDim;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final esYo  = miembro.uid == myUid;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: esYo ? clanColor.withValues(alpha: 0.06) : _kSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: esYo ? clanColor.withValues(alpha: 0.25) : _kLine),
      ),
      child: Row(children: [
        SizedBox(width: 22,
          child: Text('$posicion', style: GoogleFonts.rajdhani(
              fontSize: 13, fontWeight: FontWeight.w900,
              color: posicion == 1 ? const Color(0xFFD4A84C) : _kSubtext))),
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: clanColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: clanColor.withValues(alpha: 0.3)),
          ),
          child: Center(child: Text(
            miembro.nickname.isNotEmpty ? miembro.nickname[0].toUpperCase() : '?',
            style: GoogleFonts.rajdhani(fontSize: 16, fontWeight: FontWeight.w900, color: clanColor),
          )),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(miembro.nickname, style: GoogleFonts.rajdhani(
                fontSize: 14, fontWeight: FontWeight.w700, color: _kWhite)),
            if (esYo) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: clanColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3)),
                child: Text('TÚ', style: GoogleFonts.rajdhani(
                    fontSize: 8, fontWeight: FontWeight.w900, color: clanColor, letterSpacing: 1)),
              ),
            ],
          ]),
          Text(miembro.rol.nombre, style: GoogleFonts.rajdhani(
              fontSize: 9, fontWeight: FontWeight.w800, color: rolColor, letterSpacing: 1.5)),
        ])),
        Text('${miembro.puntosAportados} pts',
            style: GoogleFonts.rajdhani(fontSize: 12, fontWeight: FontWeight.w700, color: _kSubtext)),
        if (esCapitan && !esYo && miembro.rol != ClanRol.lider) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showOpciones(context),
            child: const Icon(Icons.more_vert_rounded, color: _kDim, size: 16),
          ),
        ],
      ]),
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
        Text(miembro.nickname, style: GoogleFonts.rajdhani(
            fontSize: 16, fontWeight: FontWeight.w900, color: _kWhite)),
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
            color: _kDim,
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
    leading: Icon(icon, color: color, size: 18),
    title: Text(label, style: GoogleFonts.rajdhani(
        fontSize: 13, fontWeight: FontWeight.w900, color: color, letterSpacing: 1.5)),
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
              gradient: LinearGradient(
                colors: [_kAccent.withValues(alpha: 0.15), _kSurface],
                begin: Alignment.topLeft,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kAccent.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              const Text('⚔️', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('GUERRA ACTIVA', style: GoogleFonts.rajdhani(
                    fontSize: 9, fontWeight: FontWeight.w900, color: _kAccent, letterSpacing: 2)),
                const SizedBox(height: 2),
                Text('vs [${rival['tag']}] ${rival['nombre']}',
                    style: GoogleFonts.rajdhani(fontSize: 14, fontWeight: FontWeight.w800, color: _kWhite)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$miPun - $rivalPun', style: GoogleFonts.rajdhani(
                    fontSize: 20, fontWeight: FontWeight.w900, color: _kWhite)),
                Text(war.tiempoRestanteStr, style: GoogleFonts.rajdhani(
                    fontSize: 9, fontWeight: FontWeight.w700, color: _kAccent, letterSpacing: 1)),
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
            decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text('No hay guerras registradas',
                style: GoogleFonts.rajdhani(fontSize: 12, color: _kSubtext))),
          );
        }
        return Column(children: lista.map((w) {
          final ganamos   = w.ganadorId == clanId;
          final empate    = w.ganadorId == null;
          final rival     = w.clanA['id'] == clanId ? w.clanB : w.clanA;
          final miPun     = (w.clanA['id'] == clanId ? w.puntuacion['clanA'] : w.puntuacion['clanB']) ?? 0;
          final rivalPun  = (w.clanA['id'] == clanId ? w.puntuacion['clanB'] : w.puntuacion['clanA']) ?? 0;
          final resultColor = empate ? _kDim : ganamos ? const Color(0xFF4FA830) : _kAccent;
          final resultLabel = empate ? 'EMPATE' : ganamos ? 'VICTORIA' : 'DERROTA';

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: resultColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: resultColor.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              SizedBox(width: 52,
                child: Text(resultLabel, style: GoogleFonts.rajdhani(
                    fontSize: 9, fontWeight: FontWeight.w900, color: resultColor, letterSpacing: 1))),
              Expanded(child: Text('vs [${rival['tag']}] ${rival['nombre']}',
                  style: GoogleFonts.rajdhani(fontSize: 12, fontWeight: FontWeight.w700, color: _kText))),
              Text('$miPun — $rivalPun', style: GoogleFonts.rajdhani(
                  fontSize: 14, fontWeight: FontWeight.w900, color: _kWhite)),
            ]),
          );
        }).toList());
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
              color: const Color(0xFF3B6BBF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3B6BBF).withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              const Text('📨', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(child: Text(
                '${invites.length} invitación${invites.length > 1 ? 'es' : ''} pendiente${invites.length > 1 ? 's' : ''}',
                style: GoogleFonts.rajdhani(fontSize: 14, fontWeight: FontWeight.w700,
                    color: const Color(0xFF3B6BBF)),
              )),
              const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF3B6BBF), size: 12),
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
            Container(width: 3, height: 12, color: _kAccent, margin: const EdgeInsets.only(right: 8)),
            Text('TOP CLANES', style: GoogleFonts.rajdhani(
                fontSize: 9, fontWeight: FontWeight.w800, color: _kSubtext, letterSpacing: 2.5)),
          ]),
          const SizedBox(height: 10),
          ...clanes.asMap().entries.map((e) {
            final c = e.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kSurface, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kLine),
              ),
              child: Row(children: [
                Text('${e.key + 1}', style: GoogleFonts.rajdhani(
                    fontSize: 14, fontWeight: FontWeight.w900,
                    color: e.key == 0 ? _kGold : _kSubtext)),
                const SizedBox(width: 10),
                Text(c.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.nombre, style: GoogleFonts.rajdhani(
                      fontSize: 13, fontWeight: FontWeight.w800, color: _kWhite)),
                  Text('[${c.tag}]  ${c.miembros.length} miembros',
                      style: GoogleFonts.rajdhani(fontSize: 10, color: _kSubtext)),
                ])),
                Text('${c.puntos} pts', style: GoogleFonts.rajdhani(
                    fontSize: 13, fontWeight: FontWeight.w800, color: _kGold)),
              ]),
            );
          }),
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
            style: GoogleFonts.rajdhani(color: Colors.white)),
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
        Text('⚔️  DECLARAR GUERRA', style: GoogleFonts.rajdhani(
            fontSize: 16, fontWeight: FontWeight.w900, color: _kWhite, letterSpacing: 2)),
        const SizedBox(height: 16),
        if (_rival == null) ...[
          TextField(
            controller: _buscarCtrl,
            onChanged: _buscar,
            style: GoogleFonts.rajdhani(color: _kWhite),
            decoration: InputDecoration(
              hintText: 'Buscar clan rival...',
              hintStyle: GoogleFonts.rajdhani(color: _kDim),
              filled: true, fillColor: _kSurface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kLine2)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kLine2)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kAccent)),
              prefixIcon: const Icon(Icons.search_rounded, color: _kSubtext, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          ..._resultados.map((c) => ListTile(
            dense: true,
            leading: Text(c.emoji, style: const TextStyle(fontSize: 20)),
            title: Text('[${c.tag}] ${c.nombre}', style: GoogleFonts.rajdhani(
                fontSize: 13, fontWeight: FontWeight.w700, color: _kWhite)),
            subtitle: Text('${c.miembros.length} miembros  ·  ${c.puntos} pts',
                style: GoogleFonts.rajdhani(fontSize: 10, color: _kSubtext)),
            onTap: () => setState(() { _rival = c; _resultados = []; }),
          )),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _kSurface2, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kAccent.withValues(alpha: 0.3))),
            child: Row(children: [
              Text(_rival!.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(child: Text('[${_rival!.tag}] ${_rival!.nombre}',
                  style: GoogleFonts.rajdhani(fontSize: 14, fontWeight: FontWeight.w800, color: _kWhite))),
              GestureDetector(onTap: () => setState(() => _rival = null),
                  child: const Icon(Icons.close_rounded, color: _kSubtext, size: 16)),
            ]),
          ),
          const SizedBox(height: 16),
          Text('TIPO', style: GoogleFonts.rajdhani(fontSize: 9, fontWeight: FontWeight.w800,
              color: _kSubtext, letterSpacing: 2)),
          const SizedBox(height: 8),
          Row(children: ['conquista', 'asedio', 'resistencia'].map((t) {
            final sel = t == _tipo;
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _tipo = t),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? _kAccent.withValues(alpha: 0.15) : _kSurface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel ? _kAccent : _kLine2),
                ),
                child: Center(child: Text(t.toUpperCase(), style: GoogleFonts.rajdhani(
                    fontSize: 9, fontWeight: FontWeight.w900,
                    color: sel ? _kAccent : _kSubtext, letterSpacing: 1.5))),
              ),
            ));
          }).toList()),
          const SizedBox(height: 16),
          Text('DURACIÓN  $_durHoras HORAS', style: GoogleFonts.rajdhani(fontSize: 9,
              fontWeight: FontWeight.w800, color: _kSubtext, letterSpacing: 2)),
          Slider(
            value: _durHoras.toDouble(), min: 24, max: 168, divisions: 6,
            activeColor: _kAccent, inactiveColor: _kLine2,
            onChanged: (v) => setState(() => _durHoras = v.round()),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _loading ? null : _declarar,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF991A1A), _kAccent]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: _kAccent.withValues(alpha: 0.3), blurRadius: 15)],
              ),
              child: _loading
                  ? const Center(child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                  : Center(child: Text('⚔️  DECLARAR GUERRA',
                      style: GoogleFonts.rajdhani(fontSize: 14, fontWeight: FontWeight.w900,
                          color: Colors.white, letterSpacing: 2))),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _BotonAccion extends StatelessWidget {
  final String label, sub, emoji;
  final Color color;
  final VoidCallback onTap;
  const _BotonAccion({required this.label, required this.sub, required this.emoji,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.lightImpact(); onTap(); },
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.rajdhani(fontSize: 15, fontWeight: FontWeight.w900,
              color: color, letterSpacing: 1.5)),
          Text(sub, style: GoogleFonts.rajdhani(fontSize: 11, color: _kSubtext)),
        ]),
        const Spacer(),
        Icon(Icons.arrow_forward_ios_rounded, color: color.withValues(alpha: 0.5), size: 14),
      ]),
    ),
  );
}

class _ConfirmDialog extends StatelessWidget {
  final String titulo, mensaje, accion;
  const _ConfirmDialog({required this.titulo, required this.mensaje, required this.accion});

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF0D0D10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    title: Text(titulo, style: GoogleFonts.rajdhani(
        fontSize: 16, fontWeight: FontWeight.w900, color: _kWhite, letterSpacing: 1.5)),
    content: Text(mensaje, style: GoogleFonts.rajdhani(fontSize: 13, color: _kText)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false),
          child: Text('CANCELAR', style: GoogleFonts.rajdhani(color: _kSubtext))),
      TextButton(onPressed: () => Navigator.pop(context, true),
          child: Text(accion, style: GoogleFonts.rajdhani(
              color: _kAccent, fontWeight: FontWeight.w900))),
    ],
  );
}