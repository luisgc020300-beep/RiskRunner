// lib/Pestañas/clan_war_screen.dart
// ═══════════════════════════════════════════════════════════
//  CLAN WAR SCREEN — Pantalla de guerra en curso
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/clan_service.dart';

const _kBg       = Color(0xFFE8E8ED);
const _kSurface  = Color(0xFFFFFFFF);
const _kSurface2 = Color(0xFFE5E5EA);
const _kSubtext  = Color(0xFF8E8E93);
const _kText     = Color(0xFF3C3C43);
const _kWhite    = Color(0xFF1C1C1E);
const _kAccent   = Color(0xFFE02020);
const _kBlue     = Color(0xFFE02020);

TextStyle _dm(double size, FontWeight w, Color c, {double sp = 0}) =>
    GoogleFonts.dmSans(fontSize: size, fontWeight: w, color: c, letterSpacing: sp);

TextStyle _raj(double size, FontWeight w, Color c, {double sp = 0}) =>
    GoogleFonts.rajdhani(fontSize: size, fontWeight: w, color: c, letterSpacing: sp);

class ClanWarScreen extends StatefulWidget {
  final ClanWar war;
  const ClanWarScreen({super.key, required this.war});
  @override
  State<ClanWarScreen> createState() => _ClanWarScreenState();
}

class _ClanWarScreenState extends State<ClanWarScreen>
    with SingleTickerProviderStateMixin {

  late AnimationController _pulse;
  Timer? _timer;
  Duration _restante = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);

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
    // Determinar cuál es mi clan en esta guerra
    // (en prod cargaríamos el clanId del jugador desde Firestore)
    final _ = war.clanA['id'] as String;
    final clanAColor = Color((war.clanA['color'] as num? ?? 0xFFCC2222).toInt());
    final clanBColor = Color((war.clanB['color'] as num? ?? 0xFF3B6BBF).toInt());

    final pA = war.puntuacion['clanA'] ?? 0;
    final pB = war.puntuacion['clanB'] ?? 0;
    final total = (pA + pB) == 0 ? 1 : (pA + pB);
    final ratioA = pA / total;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Guerra en curso', style: _dm(15, FontWeight.w600, Colors.white)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kAccent),
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
          ),
          child: Center(child: Text(
            war.clanA['emoji'] as String? ?? '🛡',
            style: const TextStyle(fontSize: 30),
          )),
        ),
        const SizedBox(height: 8),
        Text('[${war.clanA['tag']}]', style: _dm(11, FontWeight.w600, colorA)),
        Text(war.clanA['nombre'] as String? ?? '',
            style: _dm(13, FontWeight.w500, _kWhite),
            textAlign: TextAlign.center, maxLines: 2),
      ])),

      // VS central
      Column(children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.06 + _pulse.value * 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('VS', style: _raj(20, FontWeight.w900, _kAccent, sp: 2)),
          ),
        ),
        const SizedBox(height: 8),
        Text('$pA  —  $pB', style: _raj(26, FontWeight.w900, _kWhite)),
      ]),

      // Clan B
      Expanded(child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: colorB.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(child: Text(
            war.clanB['emoji'] as String? ?? '🛡',
            style: const TextStyle(fontSize: 30),
          )),
        ),
        const SizedBox(height: 8),
        Text('[${war.clanB['tag']}]', style: _dm(11, FontWeight.w600, colorB)),
        Text(war.clanB['nombre'] as String? ?? '',
            style: _dm(13, FontWeight.w500, _kWhite),
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
          color: colorB.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            width: (MediaQuery.of(context).size.width - 40) * ratioA,
            decoration: BoxDecoration(color: colorA, borderRadius: BorderRadius.circular(6)),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('$pA territorios', style: _dm(11, FontWeight.w500, colorA)),
        Text('$pB territorios', style: _dm(11, FontWeight.w500, colorB)),
      ]),
    ]);
  }

  Widget _buildTemporizador() {
    final ended = _restante.isNegative;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Text(ended ? 'Guerra finalizada' : 'Tiempo restante',
            style: _dm(12, FontWeight.w500, ended ? _kSubtext : _kAccent)),
        const SizedBox(height: 6),
        Text(_tiempoStr, style: _raj(38, FontWeight.w900,
            ended ? _kSubtext : _kWhite, sp: 2)),
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
      ),
      child: Row(children: [
        Icon(info.icon, color: _kAccent, size: 28),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(war.tipo, style: _dm(11, FontWeight.w600, _kAccent)),
          const SizedBox(height: 2),
          Text(info.titulo, style: _dm(14, FontWeight.w500, _kWhite)),
        ])),
      ]),
    );
  }

  ({IconData icon, String titulo}) _tipoInfo(String tipo) {
    switch (tipo) {
      case 'asedio':
        return (icon: Icons.location_city_rounded, titulo: 'Conquista el mayor territorio posible');
      case 'resistencia':
        return (icon: Icons.shield_rounded, titulo: 'Defiende tus territorios el máximo tiempo');
      default:
        return (icon: Icons.map_outlined, titulo: 'Conquista más zonas que el rival');
    }
  }

  Widget _buildInstrucciones(ClanWar war) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.info_outline_rounded, color: _kBlue, size: 16),
          const SizedBox(width: 8),
          Text('Cómo sumar puntos', style: _dm(13, FontWeight.w600, _kBlue)),
        ]),
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
          color: _kBlue.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(child: Text(num, style: _dm(10, FontWeight.w700, _kBlue))),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(texto, style: _dm(13, FontWeight.w400, _kText))),
    ]),
  );

  Widget _buildRankingContribucion(ClanWar war, Color colorA, Color colorB) {
    // En producción esto vendría de un subcolección war_contributions/
    // Aquí mostramos la estructura lista para conectar
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Ranking de contribución', style: _dm(12, FontWeight.w600, _kSubtext)),
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
        color: _kSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(clan['emoji'] as String? ?? '🛡', style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text('[${clan['tag']}]', style: _dm(11, FontWeight.w600, color)),
        ]),
        const SizedBox(height: 8),
        ...(clan['miembros'] as List<dynamic>? ?? []).take(4).map((m) {
          final mm = m as Map<String, dynamic>;
          final pts = mm['puntosAportados'] ?? mm['puntos'];
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
                child: Center(child: Text(
                  (mm['nickname'] as String? ?? '?')[0].toUpperCase(),
                  style: _raj(10, FontWeight.w700, color),
                )),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(mm['nickname'] as String? ?? '?',
                  style: _dm(12, FontWeight.w400, _kText),
                  overflow: TextOverflow.ellipsis)),
              Text(pts != null ? '$pts pts' : '— pts',
                  style: _dm(11, FontWeight.w500, _kSubtext)),
            ]),
          );
        }),
      ]),
    ),
  );
}