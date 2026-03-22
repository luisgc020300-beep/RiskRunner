// lib/screens/desafios_screen.dart
//
// Pantalla de desafíos: activos con marcador en vivo, pendientes y historial.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/desafios_service.dart';

// =============================================================================
// PALETA
// =============================================================================
const _kBg       = Color(0xFF030303);
const _kSurface  = Color(0xFF0C0C0C);
const _kSurface2 = Color(0xFF111111);
const _kBorder   = Color(0xFF161616);
const _kBorder2  = Color(0xFF1F1F1F);
const _kMuted    = Color(0xFF333333);
const _kDim      = Color(0xFF4A4A4A);
const _kSub      = Color(0xFF666666);
const _kText     = Color(0xFFB0B0B0);
const _kWhite    = Color(0xFFEEEEEE);
const _kRed      = Color(0xFFCC2222);
const _kRedDim   = Color(0xFF7A1414);
const _kGold     = Color(0xFFD4A84C);
const _kGoldDim  = Color(0xFF5A4520);
const _kGreen    = Color(0xFF4CAF50);

TextStyle _raj(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    GoogleFonts.rajdhani(
        fontSize: size, fontWeight: weight, color: color,
        letterSpacing: spacing, height: height);

// =============================================================================
// PANTALLA
// =============================================================================
class DesafiosScreen extends StatefulWidget {
  /// Si se pasa un desafioId, la pantalla abre directamente ese desafío
  final String? desafioId;
  const DesafiosScreen({super.key, this.desafioId});

  @override
  State<DesafiosScreen> createState() => _DesafiosScreenState();
}

class _DesafiosScreenState extends State<DesafiosScreen>
    with SingleTickerProviderStateMixin {
  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);

    // Si viene con un desafioId concreto, verificar en qué tab está
    if (widget.desafioId != null) {
      _resolverTabInicial();
    }

    // Verificar desafíos expirados al abrir
    if (uid != null) {
      DesafiosService.verificarExpirados(uid!);
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolverTabInicial() async {
    if (widget.desafioId == null || uid == null) return;
    final info = await DesafiosService.getDesafio(widget.desafioId!);
    if (!mounted || info == null) return;
    if (info.estado == 'activo')      _tabCtrl.animateTo(0);
    else if (info.estado == 'finalizado') _tabCtrl.animateTo(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _TabActivos(uid: uid, desafioId: widget.desafioId),
          _TabPendientes(uid: uid),
          _TabHistorial(uid: uid),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: _kSurface,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 18),
      onPressed: () => Navigator.pop(context),
    ),
    title: Text('DESAFÍOS', style: _raj(14, FontWeight.w900, _kWhite, spacing: 3)),
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(44),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        height: 36,
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _kBorder2),
        ),
        child: TabBar(
          controller: _tabCtrl,
          indicator: BoxDecoration(
            color: _kSurface2,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: _kBorder2),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelStyle: _raj(10, FontWeight.w900, _kWhite, spacing: 1),
          unselectedLabelStyle: _raj(10, FontWeight.w600, _kDim, spacing: 1),
          labelColor: _kWhite,
          unselectedLabelColor: _kDim,
          tabs: const [
            Tab(text: 'ACTIVOS'),
            Tab(text: 'PENDIENTES'),
            Tab(text: 'HISTORIAL'),
          ],
        ),
      ),
    ),
  );
}

// =============================================================================
// TAB: ACTIVOS
// =============================================================================
class _TabActivos extends StatelessWidget {
  final String? uid;
  final String? desafioId;
  const _TabActivos({this.uid, this.desafioId});

  @override
  Widget build(BuildContext context) {
    if (uid == null) return _emptyState('Sin sesión');
    return StreamBuilder<List<DesafioInfo>>(
      stream: DesafiosService.streamActivos(uid!),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: _kRed, strokeWidth: 1.5));
        final lista = snap.data!;
        if (lista.isEmpty) return _emptyState('No tienes desafíos activos\nReta a un rival desde su perfil');
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          itemCount: lista.length,
          itemBuilder: (_, i) => _CardActivo(
            info: lista[i], uid: uid!,
            resaltado: lista[i].id == desafioId,
          ),
        );
      },
    );
  }
}

class _CardActivo extends StatelessWidget {
  final DesafioInfo info;
  final String uid;
  final bool resaltado;
  const _CardActivo({required this.info, required this.uid, this.resaltado = false});

  @override
  Widget build(BuildContext context) {
    final misPuntos    = info.puntosDeUsuario(uid);
    final rivalPuntos  = info.puntosDeRival(uid);
    final rivalNick    = info.nickRival(uid);
    final voy          = misPuntos >= rivalPuntos;
    final totalPuntos  = misPuntos + rivalPuntos;
    final miPct        = totalPuntos > 0 ? misPuntos / totalPuntos : 0.5;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border.all(
            color: resaltado ? _kRed.withOpacity(0.6) : _kBorder2),
        boxShadow: resaltado
            ? [BoxShadow(color: _kRed.withOpacity(0.12), blurRadius: 20)]
            : [],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorder2))),
          child: Row(children: [
            Container(width: 2, height: 14, color: _kRed),
            const SizedBox(width: 10),
            const Text('⚔️', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Text('DUELO ACTIVO', style: _raj(10, FontWeight.w900, _kRed, spacing: 2)),
            const Spacer(),
            // Tiempo restante
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: info.haExpirado
                    ? _kRedDim.withOpacity(0.3)
                    : _kBorder2,
                border: Border.all(
                    color: info.haExpirado ? _kRed.withOpacity(0.5) : _kBorder2),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.timer_outlined,
                    color: info.haExpirado ? _kRed : _kSub, size: 11),
                const SizedBox(width: 4),
                Text(info.tiempoRestante,
                    style: _raj(10, FontWeight.w700,
                        info.haExpirado ? _kRed : _kText)),
              ]),
            ),
          ]),
        ),

        // ── Marcador ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            // Yo
            Expanded(child: Column(children: [
              Text('TÚ', style: _raj(9, FontWeight.w700, _kSub, spacing: 2)),
              const SizedBox(height: 6),
              Text('$misPuntos',
                  style: GoogleFonts.rajdhani(
                      fontSize: 52, fontWeight: FontWeight.w900,
                      color: voy ? _kWhite : _kSub, height: 1,
                      shadows: voy
                          ? [const Shadow(color: _kRed, blurRadius: 16)]
                          : [])),
              Text('PTS', style: _raj(9, FontWeight.w700,
                  voy ? _kRed : _kDim, spacing: 2)),
            ])),

            // VS
            Column(children: [
              Text('VS', style: _raj(14, FontWeight.w900, _kMuted, spacing: 3)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _kGoldDim.withOpacity(0.2),
                  border: Border.all(color: _kGoldDim.withOpacity(0.4)),
                ),
                child: Text('${info.apuesta} 🪙',
                    style: _raj(11, FontWeight.w900, _kGold)),
              ),
            ]),

            // Rival
            Expanded(child: Column(children: [
              Text(rivalNick.toUpperCase(),
                  style: _raj(9, FontWeight.w700, _kSub, spacing: 1),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Text('$rivalPuntos',
                  style: GoogleFonts.rajdhani(
                      fontSize: 52, fontWeight: FontWeight.w900,
                      color: !voy ? _kWhite : _kSub, height: 1,
                      shadows: !voy
                          ? [const Shadow(color: _kRed, blurRadius: 16)]
                          : [])),
              Text('PTS', style: _raj(9, FontWeight.w700,
                  !voy ? _kRed : _kDim, spacing: 2)),
            ])),
          ]),
        ),

        // ── Barra de progreso ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 6,
                child: Row(children: [
                  Flexible(
                    flex: (miPct * 100).round().clamp(1, 99),
                    child: Container(color: _kRed),
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    flex: ((1 - miPct) * 100).round().clamp(1, 99),
                    child: Container(color: _kMuted),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Text(voy ? '⬆ Vas ganando' : '⬇ Vas perdiendo',
                  style: _raj(10, FontWeight.w700,
                      voy ? _kGreen : _kRed)),
              const Spacer(),
              Text('Premio: ${info.apuesta * 2} 🪙',
                  style: _raj(10, FontWeight.w600, _kSub)),
            ]),
          ]),
        ),

        // ── Cómo sumar puntos ────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kBg,
            border: Border.all(color: _kBorder2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _puntoTip('⚔️', 'Conquista', '×10 pts'),
              Container(width: 1, height: 24, color: _kBorder2),
              _puntoTip('🏃', 'Kilómetro', '×5 pts'),
              Container(width: 1, height: 24, color: _kBorder2),
              _puntoTip('⏱', 'Tiempo', info.tiempoRestante),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _puntoTip(String emoji, String label, String valor) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 2),
        Text(label, style: _raj(8, FontWeight.w600, _kSub, spacing: 0.5)),
        Text(valor, style: _raj(10, FontWeight.w900, _kText)),
      ]);
}

// =============================================================================
// TAB: PENDIENTES
// =============================================================================
class _TabPendientes extends StatelessWidget {
  final String? uid;
  const _TabPendientes({this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid == null) return _emptyState('Sin sesión');
    return StreamBuilder<List<DesafioInfo>>(
      stream: DesafiosService.streamPendientes(uid!),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: _kRed, strokeWidth: 1.5));
        final lista = snap.data!;
        if (lista.isEmpty) return _emptyState(
            'No tienes desafíos enviados pendientes\nde respuesta');
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          itemCount: lista.length,
          itemBuilder: (_, i) => _CardPendiente(info: lista[i], uid: uid!),
        );
      },
    );
  }
}

class _CardPendiente extends StatelessWidget {
  final DesafioInfo info;
  final String uid;
  const _CardPendiente({required this.info, required this.uid});

  @override
  Widget build(BuildContext context) {
    final rival = info.nickRival(uid);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border(left: const BorderSide(color: _kRed, width: 2),
            top: BorderSide(color: _kBorder2),
            right: BorderSide(color: _kBorder2),
            bottom: BorderSide(color: _kBorder2)),
      ),
      child: Row(children: [
        const Text('⏳', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Esperando a ${rival.toUpperCase()}',
              style: _raj(13, FontWeight.w800, _kWhite)),
          const SizedBox(height: 4),
          Text('${info.apuesta} 🪙 · ${info.duracionHoras}h',
              style: _raj(11, FontWeight.w500, _kSub)),
        ])),
        // Botón cancelar
        GestureDetector(
          onTap: () => _cancelar(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: _kBorder2),
            ),
            child: Text('CANCELAR', style: _raj(9, FontWeight.w900, _kDim, spacing: 1.5)),
          ),
        ),
      ]),
    );
  }

  Future<void> _cancelar(BuildContext context) async {
    try {
      // Devolver monedas al retador
      await FirebaseFirestore.instance
          .collection('players').doc(uid)
          .update({'monedas': FieldValue.increment(info.apuesta)});
      await FirebaseFirestore.instance
          .collection('desafios').doc(info.id)
          .update({'estado': 'cancelado'});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Desafío cancelado — monedas devueltas'),
            backgroundColor: _kRedDim));
      }
    } catch (e) {
      debugPrint('Error cancelando: $e');
    }
  }
}

// =============================================================================
// TAB: HISTORIAL
// =============================================================================
class _TabHistorial extends StatelessWidget {
  final String? uid;
  const _TabHistorial({this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid == null) return _emptyState('Sin sesión');
    return StreamBuilder<List<DesafioInfo>>(
      stream: DesafiosService.streamHistorial(uid!),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: _kRed, strokeWidth: 1.5));
        final lista = snap.data!;
        if (lista.isEmpty) return _emptyState(
            'Sin desafíos completados todavía');

        // Stats
        final ganados  = lista.where((d) => d.ganadorId == uid).length;
        final perdidos = lista.length - ganados;
        final winPct   = lista.isEmpty ? 0.0 : ganados / lista.length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            // Resumen
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kSurface,
                border: Border.all(color: _kBorder2),
              ),
              child: Row(children: [
                _statCol('$ganados', 'VICTORIAS', _kGold),
                _vDivider(),
                _statCol('$perdidos', 'DERROTAS', _kRed),
                _vDivider(),
                _statCol('${(winPct * 100).toStringAsFixed(0)}%', 'WIN RATE', _kText),
              ]),
            ),
            ...lista.map((d) => _CardHistorial(info: d, uid: uid!)),
          ],
        );
      },
    );
  }

  Widget _statCol(String val, String label, Color color) => Expanded(
    child: Column(children: [
      Text(val, style: GoogleFonts.rajdhani(
          fontSize: 32, fontWeight: FontWeight.w900, color: color, height: 1)),
      Text(label, style: _raj(8, FontWeight.w700, _kSub, spacing: 1.5)),
    ]),
  );

  Widget _vDivider() =>
      Container(width: 1, height: 40, color: _kBorder2,
          margin: const EdgeInsets.symmetric(horizontal: 8));
}

class _CardHistorial extends StatelessWidget {
  final DesafioInfo info;
  final String uid;
  const _CardHistorial({required this.info, required this.uid});

  @override
  Widget build(BuildContext context) {
    final gane       = info.ganadorId == uid;
    final rival      = info.nickRival(uid);
    final misPuntos  = info.puntosDeUsuario(uid);
    final rivalPts   = info.puntosDeRival(uid);
    final color      = gane ? _kGold : _kRed;
    final premio     = gane ? '+${info.apuesta * 2}' : '-${info.apuesta}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border(
          left: BorderSide(color: color.withOpacity(0.6), width: 2),
          top: BorderSide(color: _kBorder2),
          right: BorderSide(color: _kBorder2),
          bottom: BorderSide(color: _kBorder2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Text(gane ? '🏆' : '💀', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              gane ? 'Victoria vs ${rival.toUpperCase()}'
                   : 'Derrota vs ${rival.toUpperCase()}',
              style: _raj(13, FontWeight.w800, _kWhite),
            ),
            const SizedBox(height: 4),
            Text('$misPuntos pts vs $rivalPts pts',
                style: _raj(11, FontWeight.w500, _kSub)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text('$premio 🪙',
                style: _raj(13, FontWeight.w900, color)),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
// HELPERS
// =============================================================================
Widget _emptyState(String msg) => Center(
  child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.sports_mma_rounded, color: _kMuted, size: 44),
      const SizedBox(height: 16),
      Text(msg, textAlign: TextAlign.center,
          style: _raj(13, FontWeight.w500, _kSub, height: 1.5)),
    ]),
  ),
);