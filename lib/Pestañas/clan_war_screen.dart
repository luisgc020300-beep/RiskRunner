// lib/Pestañas/clan_war_screen.dart
// ═══════════════════════════════════════════════════════════
//  CLAN WAR SCREEN — Pantalla de guerra en curso
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/clan_service.dart';

const _kBg      = Color(0xFF060608);
const _kSurface = Color(0xFF0D0D10);
const _kLine    = Color(0xFF1C1C24);
const _kLine2   = Color(0xFF242430);
const _kSubtext = Color(0xFF5A5A70);
const _kText    = Color(0xFFAAAAAC);
const _kWhite   = Color(0xFFF0F0F2);
const _kAccent  = Color(0xFFCC2222);
const _kGold    = Color(0xFFD4A84C);

class ClanWarScreen extends StatefulWidget {
  final ClanWar war;
  const ClanWarScreen({super.key, required this.war});
  @override
  State<ClanWarScreen> createState() => _ClanWarScreenState();
}

class _ClanWarScreenState extends State<ClanWarScreen>
    with SingleTickerProviderStateMixin {

  late AnimationController _pulse;
  late Stream<ClanWar?>    _warStream;
  Timer? _timer;
  Duration _restante = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);

    _warStream = ClanService.clanStream(widget.war.clanA['id'] as String).map((_) => null)
        .asBroadcastStream(); // placeholder — en prod usaría clan_wars stream directo

    _restante = widget.war.fin.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _restante = widget.war.fin.difference(DateTime.now()));
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String get _tiempoStr {
    if (_restante.isNegative) return 'FINALIZADA';
    final h = _restante.inHours;
    final m = _restante.inMinutes.remainder(60);
    final s = _restante.inSeconds.remainder(60);
    if (h >= 24) return '${_restante.inDays}d ${h.remainder(24)}h';
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final war = widget.war;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Determinar cuál es mi clan en esta guerra
    // (en prod cargaríamos el clanId del jugador desde Firestore)
    final clanAId    = war.clanA['id'] as String;
    final clanAColor = Color((war.clanA['color'] as num? ?? 0xFFCC2222).toInt());
    final clanBColor = Color((war.clanB['color'] as num? ?? 0xFF3B6BBF).toInt());

    final pA = war.puntuacion['clanA'] ?? 0;
    final pB = war.puntuacion['clanB'] ?? 0;
    final total = (pA + pB) == 0 ? 1 : (pA + pB);
    final ratioA = pA / total;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 16),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('GUERRA EN CURSO', style: GoogleFonts.rajdhani(
            fontSize: 13, fontWeight: FontWeight.w900, color: _kWhite, letterSpacing: 3)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kLine),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [

          // ── Cabecera de la guerra ────────────────────────
          _buildCabecera(war, clanAColor, clanBColor, pA, pB),
          const SizedBox(height: 24),

          // ── Barra de progreso ────────────────────────────
          _buildBarraProgreso(ratioA, clanAColor, clanBColor, pA, pB),
          const SizedBox(height: 24),

          // ── Temporizador ─────────────────────────────────
          _buildTemporizador(),
          const SizedBox(height: 28),

          // ── Tipo de guerra ───────────────────────────────
          _buildTipoGuerra(war),
          const SizedBox(height: 28),

          // ── Instrucciones ────────────────────────────────
          _buildInstrucciones(war),
          const SizedBox(height: 28),

          // ── Ranking de contribución ──────────────────────
          _buildRankingContribucion(war, clanAColor, clanBColor),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _buildCabecera(ClanWar war, Color colorA, Color colorB, int pA, int pB) {
    return Row(children: [
      // Clan A
      Expanded(child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: colorA.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorA.withValues(alpha: 0.5), width: 2),
            boxShadow: [BoxShadow(color: colorA.withValues(alpha: 0.2), blurRadius: 16)],
          ),
          child: Center(child: Text(
            war.clanA['emoji'] as String? ?? '⚔️',
            style: const TextStyle(fontSize: 30),
          )),
        ),
        const SizedBox(height: 8),
        Text('[${war.clanA['tag']}]', style: GoogleFonts.rajdhani(
            fontSize: 10, fontWeight: FontWeight.w900, color: colorA, letterSpacing: 1)),
        Text(war.clanA['nombre'] as String? ?? '',
            style: GoogleFonts.rajdhani(fontSize: 13, fontWeight: FontWeight.w800, color: _kWhite),
            textAlign: TextAlign.center, maxLines: 2),
      ])),

      // VS central
      Column(children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.08 + _pulse.value * 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kAccent.withValues(alpha: 0.4)),
            ),
            child: Text('VS', style: GoogleFonts.rajdhani(
                fontSize: 20, fontWeight: FontWeight.w900, color: _kAccent, letterSpacing: 2)),
          ),
        ),
        const SizedBox(height: 8),
        Text('$pA  —  $pB', style: GoogleFonts.rajdhani(
            fontSize: 26, fontWeight: FontWeight.w900, color: _kWhite)),
      ]),

      // Clan B
      Expanded(child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: colorB.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorB.withValues(alpha: 0.5), width: 2),
            boxShadow: [BoxShadow(color: colorB.withValues(alpha: 0.2), blurRadius: 16)],
          ),
          child: Center(child: Text(
            war.clanB['emoji'] as String? ?? '⚔️',
            style: const TextStyle(fontSize: 30),
          )),
        ),
        const SizedBox(height: 8),
        Text('[${war.clanB['tag']}]', style: GoogleFonts.rajdhani(
            fontSize: 10, fontWeight: FontWeight.w900, color: colorB, letterSpacing: 1)),
        Text(war.clanB['nombre'] as String? ?? '',
            style: GoogleFonts.rajdhani(fontSize: 13, fontWeight: FontWeight.w800, color: _kWhite),
            textAlign: TextAlign.center, maxLines: 2),
      ])),
    ]);
  }

  Widget _buildBarraProgreso(double ratioA, Color colorA, Color colorB, int pA, int pB) {
    return Column(children: [
      Container(
        height: 10,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colorB.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            width: (MediaQuery.of(context).size.width - 40) * ratioA,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [colorA.withValues(alpha: 0.7), colorA]),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('$pA territorios', style: GoogleFonts.rajdhani(
            fontSize: 10, color: colorA.withValues(alpha: 0.8), fontWeight: FontWeight.w700)),
        Text('$pB territorios', style: GoogleFonts.rajdhani(
            fontSize: 10, color: colorB.withValues(alpha: 0.8), fontWeight: FontWeight.w700)),
      ]),
    ]);
  }

  Widget _buildTemporizador() {
    final ended = _restante.isNegative;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: ended ? _kSurface : _kAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ended ? _kLine : _kAccent.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text(ended ? 'GUERRA FINALIZADA' : 'TIEMPO RESTANTE',
            style: GoogleFonts.rajdhani(fontSize: 9, fontWeight: FontWeight.w800,
                color: ended ? _kSubtext : _kAccent, letterSpacing: 2.5)),
        const SizedBox(height: 6),
        Text(_tiempoStr, style: GoogleFonts.rajdhani(
            fontSize: 38, fontWeight: FontWeight.w900,
            color: ended ? _kSubtext : _kWhite, letterSpacing: 2)),
      ]),
    );
  }

  Widget _buildTipoGuerra(ClanWar war) {
    final info = _tipoInfo(war.tipo);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kLine2),
      ),
      child: Row(children: [
        Text(info['emoji']!, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
              ),
              child: Text(war.tipo.toUpperCase(), style: GoogleFonts.rajdhani(
                  fontSize: 9, fontWeight: FontWeight.w900, color: _kAccent, letterSpacing: 1.5)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(info['titulo']!, style: GoogleFonts.rajdhani(
              fontSize: 15, fontWeight: FontWeight.w800, color: _kWhite)),
        ])),
      ]),
    );
  }

  Map<String, String> _tipoInfo(String tipo) {
    switch (tipo) {
      case 'asedio':
        return {'emoji': '🏰', 'titulo': 'Conquista el mayor territorio posible'};
      case 'resistencia':
        return {'emoji': '🛡️', 'titulo': 'Defiende tus territorios el máximo tiempo'};
      default:
        return {'emoji': '🗺️', 'titulo': 'Conquista más zonas que el rival'};
    }
  }

  Widget _buildInstrucciones(ClanWar war) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3B6BBF).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3B6BBF).withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📋  CÓMO SUMAR PUNTOS', style: GoogleFonts.rajdhani(
            fontSize: 10, fontWeight: FontWeight.w900,
            color: const Color(0xFF3B6BBF), letterSpacing: 2)),
        const SizedBox(height: 10),
        _instruccion('1', 'Sal a correr y activa el modo carrera'),
        _instruccion('2', 'Cada territorio conquistado suma +1 punto al clan'),
        _instruccion('3', 'Los territorios de zonas disputadas valen doble'),
        _instruccion('4', 'El clan con más puntos al final gana la guerra'),
      ]),
    );
  }

  Widget _instruccion(String num, String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          color: const Color(0xFF3B6BBF).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(child: Text(num, style: GoogleFonts.rajdhani(
            fontSize: 10, fontWeight: FontWeight.w900,
            color: const Color(0xFF3B6BBF)))),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(texto, style: GoogleFonts.rajdhani(
          fontSize: 12, color: _kText))),
    ]),
  );

  Widget _buildRankingContribucion(ClanWar war, Color colorA, Color colorB) {
    // En producción esto vendría de un subcolección war_contributions/
    // Aquí mostramos la estructura lista para conectar
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 3, height: 12, color: _kAccent, margin: const EdgeInsets.only(right: 8)),
        Text('RANKING DE CONTRIBUCIÓN', style: GoogleFonts.rajdhani(
            fontSize: 9, fontWeight: FontWeight.w800, color: _kSubtext, letterSpacing: 2.5)),
      ]),
      const SizedBox(height: 12),
      // Cabecera: dos columnas, una por clan
      Row(children: [
        _cabeceraClan(war.clanA, colorA),
        const SizedBox(width: 8),
        _cabeceraClan(war.clanB, colorB),
      ]),
    ]);
  }

  Widget _cabeceraClan(Map<String, dynamic> clan, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(clan['emoji'] as String? ?? '⚔️', style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text('[${clan['tag']}]', style: GoogleFonts.rajdhani(
              fontSize: 10, fontWeight: FontWeight.w900, color: color)),
        ]),
        const SizedBox(height: 8),
        // Placeholder de miembros
        ...(clan['miembros'] as List<dynamic>? ?? []).take(4).map((m) {
          final mm = m as Map<String, dynamic>;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.12),
                ),
                child: Center(child: Text(
                  (mm['nickname'] as String? ?? '?')[0].toUpperCase(),
                  style: GoogleFonts.rajdhani(fontSize: 10, fontWeight: FontWeight.w900, color: color),
                )),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(mm['nickname'] as String? ?? '?',
                  style: GoogleFonts.rajdhani(fontSize: 11, color: _kText),
                  overflow: TextOverflow.ellipsis)),
              Text('— pts', style: GoogleFonts.rajdhani(fontSize: 10, color: _kSubtext)),
            ]),
          );
        }),
      ]),
    ),
  );
}