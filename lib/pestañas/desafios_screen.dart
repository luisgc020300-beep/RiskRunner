// lib/screens/desafios_screen.dart
//
// Pantalla de desafíos: activos con marcador en vivo, pendientes y historial.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/desafios_service.dart';

// =============================================================================
// PALETA
// =============================================================================
const _kBg       = Color(0xFFE8E8ED);
const _kSurface  = Color(0xFFFFFFFF);
const _kSurface2 = Color(0xFFE5E5EA);
const _kSep      = Color(0xFFC6C6C8);
const _kMuted    = Color(0xFFD1D1D6);
const _kDim      = Color(0xFFAEAEB2);
const _kSub      = Color(0xFF8E8E93);
const _kText     = Color(0xFF3C3C43);
const _kWhite    = Color(0xFF1C1C1E);
const _kRed      = Color(0xFFE02020);
const _kBlue     = Color(0xFFE02020);
const _kGold     = Color(0xFFFFD60A);
const _kGoldDim  = Color(0xFFB8960A);
const _kGreen    = Color(0xFF30D158);

TextStyle _raj(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    GoogleFonts.rajdhani(
        fontSize: size, fontWeight: weight, color: color,
        letterSpacing: spacing, height: height);

TextStyle _dm(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    GoogleFonts.dmSans(
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
    backgroundColor: const Color(0xFF0D0D0D),
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
      onPressed: () => Navigator.pop(context),
    ),
    title: Text('Desafíos', style: _dm(16, FontWeight.w600, Colors.white)),
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          height: 34,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(9),
          ),
          child: TabBar(
            controller: _tabCtrl,
            indicator: BoxDecoration(
              color: const Color(0xFF444444),
              borderRadius: BorderRadius.circular(7),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelStyle: _dm(12, FontWeight.w600, Colors.white),
            unselectedLabelStyle: _dm(12, FontWeight.w400, _kSub),
            labelColor: Colors.white,
            unselectedLabelColor: _kSub,
            tabs: const [
              Tab(text: 'Activos'),
              Tab(text: 'Pendientes'),
              Tab(text: 'Historial'),
            ],
          ),
        ),
        Container(height: 1, color: _kRed),
      ]),
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(children: [
            const Icon(Icons.bolt_rounded, color: _kRed, size: 15),
            const SizedBox(width: 6),
            Text('Duelo activo', style: _dm(12, FontWeight.w600, _kRed)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: info.haExpirado
                    ? _kRed.withValues(alpha: 0.12) : _kSurface2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.timer_outlined,
                    color: info.haExpirado ? _kRed : _kSub, size: 11),
                const SizedBox(width: 4),
                Text(info.tiempoRestante,
                    style: _dm(11, FontWeight.w500,
                        info.haExpirado ? _kRed : _kText)),
              ]),
            ),
          ]),
        ),
        Container(height: 0.5, color: _kSep),

        // ── Marcador ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            // Yo
            Expanded(child: Column(children: [
              Text('Tú', style: _dm(11, FontWeight.w500, _kSub)),
              const SizedBox(height: 4),
              Text('$misPuntos',
                  style: _raj(52, FontWeight.w900,
                      voy ? _kWhite : _kSub, height: 1)),
              Text('pts', style: _dm(10, FontWeight.w500,
                  voy ? _kRed : _kDim)),
            ])),

            // VS
            Column(children: [
              Text('VS', style: _raj(14, FontWeight.w900, _kMuted, spacing: 2)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.monetization_on_rounded,
                      color: _kGold, size: 13),
                  const SizedBox(width: 4),
                  Text('${info.apuesta}',
                      style: _raj(12, FontWeight.w900, _kGold)),
                ]),
              ),
            ]),

            // Rival
            Expanded(child: Column(children: [
              Text(rivalNick, style: _dm(11, FontWeight.w500, _kSub),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('$rivalPuntos',
                  style: _raj(52, FontWeight.w900,
                      !voy ? _kWhite : _kSub, height: 1)),
              Text('pts', style: _dm(10, FontWeight.w500,
                  !voy ? _kRed : _kDim)),
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
              Icon(voy ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  color: voy ? _kGreen : _kRed, size: 12),
              const SizedBox(width: 4),
              Text(voy ? 'Vas ganando' : 'Vas perdiendo',
                  style: _dm(11, FontWeight.w500, voy ? _kGreen : _kRed)),
              const Spacer(),
              const Icon(Icons.monetization_on_rounded, color: _kGold, size: 11),
              const SizedBox(width: 3),
              Text('${info.apuesta * 2} premio',
                  style: _dm(11, FontWeight.w400, _kSub)),
            ]),
          ]),
        ),

        // ── Cómo sumar puntos ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _puntoTip(Icons.flag_rounded, 'Conquista', '×10 pts'),
            Container(width: 0.5, height: 28, color: _kSep),
            _puntoTip(Icons.straighten_rounded, 'Kilómetro', '×5 pts'),
            Container(width: 0.5, height: 28, color: _kSep),
            _puntoTip(Icons.timer_outlined, 'Tiempo', info.tiempoRestante),
          ]),
        ),
      ]),
    );
  }

  Widget _puntoTip(IconData icon, String label, String valor) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: _kSub, size: 15),
        const SizedBox(height: 3),
        Text(label, style: _dm(10, FontWeight.w400, _kSub)),
        Text(valor,  style: _raj(11, FontWeight.w700, _kText)),
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.hourglass_top_rounded, color: _kSub, size: 22),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Esperando a $rival',
              style: _dm(13, FontWeight.w600, _kWhite)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.monetization_on_rounded, color: _kSub, size: 11),
            const SizedBox(width: 3),
            Text('${info.apuesta}  ·  ${info.duracionHoras}h',
                style: _dm(11, FontWeight.w400, _kSub)),
          ]),
        ])),
        GestureDetector(
          onTap: () => _cancelar(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kSurface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Cancelar', style: _dm(12, FontWeight.w500, _kDim)),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: const Text('Desafío cancelado — monedas devueltas'),
    backgroundColor: Color.fromRGBO(255, 69, 58, 0.15)));
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
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                _statCol('$ganados', 'Victorias', _kGold),
                _vDivider(),
                _statCol('$perdidos', 'Derrotas', _kRed),
                _vDivider(),
                _statCol('${(winPct * 100).toStringAsFixed(0)}%', 'Win rate', _kText),
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
      Text(label, style: _dm(10, FontWeight.w500, _kSub)),
    ]),
  );

  Widget _vDivider() =>
      Container(width: 1, height: 40, color: _kSep,
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(
            gane ? Icons.emoji_events_rounded : Icons.close_rounded,
            color: color, size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              gane ? 'Victoria vs $rival' : 'Derrota vs $rival',
              style: _dm(13, FontWeight.w600, _kWhite),
            ),
            const SizedBox(height: 4),
            Text('$misPuntos pts  vs  $rivalPts pts',
                style: _dm(11, FontWeight.w400, _kSub)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(premio, style: _dm(13, FontWeight.w600, color)),
              const SizedBox(width: 3),
              Icon(Icons.monetization_on_rounded, color: color, size: 12),
            ]),
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
          style: _dm(14, FontWeight.w400, _kSub, height: 1.5)),
    ]),
  ),
);