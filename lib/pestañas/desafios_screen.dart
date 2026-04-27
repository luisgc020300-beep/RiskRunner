// lib/screens/desafios_screen.dart
//
// Pantalla de desafíos: activos con marcador en vivo, pendientes y historial.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/desafios_service.dart';

// =============================================================================
// PALETA ADAPTATIVA (dark / light)
// =============================================================================
const _kRed   = Color(0xFFE02020);
const _kGold  = Color(0xFFFFD60A);
const _kGreen = Color(0xFF30D158);

class _DP {
  final Color surface, surface2, sep, muted, dim, sub, text, title;
  final Color appBar, appBarFg, tabBg, tabSelected;
  const _DP._({
    required this.surface,  required this.surface2,
    required this.sep,      required this.muted,
    required this.dim,      required this.sub,
    required this.text,     required this.title,
    required this.appBar,   required this.appBarFg,
    required this.tabBg,    required this.tabSelected,
  });
  static const light = _DP._(
    surface:     Color(0xFFFFFFFF),
    surface2:    Color(0xFFE5E5EA),
    sep:         Color(0xFFC6C6C8),
    muted:       Color(0xFFD1D1D6),
    dim:         Color(0xFFAEAEB2),
    sub:         Color(0xFF8E8E93),
    text:        Color(0xFF3C3C43),
    title:       Color(0xFF1C1C1E),
    appBar:      Color(0xFFFFFFFF),
    appBarFg:    Color(0xFF1C1C1E),
    tabBg:       Color(0xFFE5E5EA),
    tabSelected: Color(0xFFFFFFFF),
  );
  static const dark = _DP._(
    surface:     Color(0xFF1C1C1E),
    surface2:    Color(0xFF2C2C2E),
    sep:         Color(0xFF38383A),
    muted:       Color(0xFF48484A),
    dim:         Color(0xFF636366),
    sub:         Color(0xFF8E8E93),
    text:        Color(0xFFD1D1D6),
    title:       Color(0xFFEEEEEE),
    appBar:      Color(0xFF0D0D0D),
    appBarFg:    Color(0xFFEEEEEE),
    tabBg:       Color(0xFF2A2A2A),
    tabSelected: Color(0xFF444444),
  );
  static _DP of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? dark : light;
}

TextStyle _raj(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    GoogleFonts.inter(
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
    if (widget.desafioId != null) _resolverTabInicial();
    if (uid != null) DesafiosService.verificarExpirados(uid!);
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
    if (info.estado == 'activo')          _tabCtrl.animateTo(0);
    else if (info.estado == 'finalizado') _tabCtrl.animateTo(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(context),
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

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final p = _DP.of(context);
    return AppBar(
      backgroundColor: p.appBar,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: p.appBarFg, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text('Desafíos', style: _dm(16, FontWeight.w600, p.appBarFg)),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            height: 34,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: p.tabBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: TabBar(
              controller: _tabCtrl,
              indicator: BoxDecoration(
                color: p.tabSelected,
                borderRadius: BorderRadius.circular(7),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: _dm(12, FontWeight.w600, p.title),
              unselectedLabelStyle: _dm(12, FontWeight.w400, p.sub),
              labelColor: p.title,
              unselectedLabelColor: p.sub,
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
    if (uid == null) return _emptyState(context, 'Sin sesión');
    return StreamBuilder<List<DesafioInfo>>(
      stream: DesafiosService.streamActivos(uid!),
      builder: (context, snap) {
        if (snap.hasError) return _emptyState(context, 'Error al cargar desafíos');
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: _kRed, strokeWidth: 1.5));
        final lista = snap.data!;
        if (lista.isEmpty) return _emptyState(context, 'No tienes desafíos activos\nReta a un rival desde su perfil');
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
    final p = _DP.of(context);
    final misPuntos   = info.puntosDeUsuario(uid);
    final rivalPuntos = info.puntosDeRival(uid);
    final rivalNick   = info.nickRival(uid);
    final voy         = misPuntos >= rivalPuntos;
    final totalPuntos = misPuntos + rivalPuntos;
    final miPct       = totalPuntos > 0 ? misPuntos / totalPuntos : 0.5;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: resaltado
              ? _kRed.withValues(alpha: 0.55)
              : p.sep.withValues(alpha: 0.6),
          width: resaltado ? 1.5 : 1,
        ),
        boxShadow: resaltado
            ? [BoxShadow(color: _kRed.withValues(alpha: 0.08), blurRadius: 16)]
            : null,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: info.haExpirado
                    ? _kRed.withValues(alpha: 0.12)
                    : _kGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: info.haExpirado
                      ? _kRed.withValues(alpha: 0.4)
                      : _kGold.withValues(alpha: 0.35),
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.timer_rounded,
                    color: info.haExpirado ? _kRed : _kGold, size: 13),
                const SizedBox(width: 5),
                Text(info.tiempoRestante,
                    style: _raj(13, FontWeight.w700,
                        info.haExpirado ? _kRed : _kGold)),
              ]),
            ),
          ]),
        ),
        Container(height: 0.5, color: p.sep),

        // ── Marcador ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Expanded(child: Column(children: [
              Text('Tú', style: _dm(11, FontWeight.w500, p.sub)),
              const SizedBox(height: 4),
              Text('$misPuntos',
                  style: _raj(52, FontWeight.w900,
                      voy ? p.title : p.sub, height: 1)),
              Text('pts', style: _dm(10, FontWeight.w500,
                  voy ? _kRed : p.dim)),
            ])),
            Column(children: [
              Text('VS', style: _raj(14, FontWeight.w900, p.muted, spacing: 2)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.monetization_on_rounded, color: _kGold, size: 13),
                  const SizedBox(width: 4),
                  Text('${info.apuesta}',
                      style: _raj(12, FontWeight.w900, _kGold)),
                ]),
              ),
            ]),
            Expanded(child: Column(children: [
              Text(rivalNick, style: _dm(11, FontWeight.w500, p.sub),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('$rivalPuntos',
                  style: _raj(52, FontWeight.w900,
                      !voy ? p.title : p.sub, height: 1)),
              Text('pts', style: _dm(10, FontWeight.w500,
                  !voy ? _kRed : p.dim)),
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
                    child: Container(color: p.muted),
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
                  style: _dm(11, FontWeight.w400, p.sub)),
            ]),
          ]),
        ),

        // ── Cómo sumar puntos ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _puntoTip(p, Icons.flag_rounded, 'Conquista', '×10 pts'),
            Container(width: 0.5, height: 28, color: p.sep),
            _puntoTip(p, Icons.straighten_rounded, 'Kilómetro', '×5 pts'),
            Container(width: 0.5, height: 28, color: p.sep),
            _puntoTip(p, Icons.timer_outlined, 'Tiempo', info.tiempoRestante),
          ]),
        ),
      ]),
    );
  }

  Widget _puntoTip(_DP p, IconData icon, String label, String valor) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: p.sub, size: 15),
        const SizedBox(height: 3),
        Text(label, style: _dm(10, FontWeight.w400, p.sub)),
        Text(valor,  style: _raj(11, FontWeight.w700, p.text)),
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
    if (uid == null) return _emptyState(context, 'Sin sesión');
    return StreamBuilder<List<DesafioInfo>>(
      stream: DesafiosService.streamPendientes(uid!),
      builder: (context, snap) {
        if (snap.hasError) return _emptyState(context, 'Error al cargar desafíos');
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: _kRed, strokeWidth: 1.5));
        final lista = snap.data!;
        if (lista.isEmpty) return _emptyState(context,
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
    final p = _DP.of(context);
    final rival = info.nickRival(uid);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.sep.withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        Icon(Icons.hourglass_top_rounded, color: p.sub, size: 22),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Esperando a $rival',
              style: _dm(13, FontWeight.w600, p.title)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.monetization_on_rounded, color: p.sub, size: 11),
            const SizedBox(width: 3),
            Text('${info.apuesta}  ·  ${info.duracionHoras}h',
                style: _dm(11, FontWeight.w400, p.sub)),
          ]),
        ])),
        GestureDetector(
          onTap: () => _cancelar(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Cancelar', style: _dm(12, FontWeight.w500, p.dim)),
          ),
        ),
      ]),
    );
  }

  Future<void> _cancelar(BuildContext context) async {
    try {
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
    final p = _DP.of(context);
    if (uid == null) return _emptyState(context, 'Sin sesión');
    return StreamBuilder<List<DesafioInfo>>(
      stream: DesafiosService.streamHistorial(uid!),
      builder: (context, snap) {
        if (snap.hasError) return _emptyState(context, 'Error al cargar historial');
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: _kRed, strokeWidth: 1.5));
        final lista = snap.data!;
        if (lista.isEmpty) return _emptyState(context, 'Sin desafíos completados todavía');

        final ganados  = lista.where((d) => d.ganadorId == uid).length;
        final perdidos = lista.length - ganados;
        final winPct   = lista.isEmpty ? 0.0 : ganados / lista.length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                _statCol('$ganados', 'Victorias', _kGold),
                _vDivider(p.sep),
                _statCol('$perdidos', 'Derrotas', _kRed),
                _vDivider(p.sep),
                _statCol('${(winPct * 100).toStringAsFixed(0)}%', 'Win rate', p.text),
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
      Text(val, style: _raj(32, FontWeight.w900, color, height: 1)),
      Text(label, style: _dm(10, FontWeight.w500, const Color(0xFF8E8E93))),
    ]),
  );

  Widget _vDivider(Color color) =>
      Container(width: 1, height: 40, color: color,
          margin: const EdgeInsets.symmetric(horizontal: 8));
}

class _CardHistorial extends StatelessWidget {
  final DesafioInfo info;
  final String uid;
  const _CardHistorial({required this.info, required this.uid});

  @override
  Widget build(BuildContext context) {
    final p      = _DP.of(context);
    final gane   = info.ganadorId == uid;
    final rival  = info.nickRival(uid);
    final misPts = info.puntosDeUsuario(uid);
    final rivalP = info.puntosDeRival(uid);
    final color  = gane ? _kGold : _kRed;
    final premio = gane ? '+${info.apuesta * 2}' : '-${info.apuesta}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.20),
        ),
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
              style: _dm(13, FontWeight.w600, p.title),
            ),
            const SizedBox(height: 4),
            Text('$misPts pts  vs  $rivalP pts',
                style: _dm(11, FontWeight.w400, p.sub)),
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
Widget _emptyState(BuildContext context, String msg) {
  final p = _DP.of(context);
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.sports_mma_rounded, color: p.muted, size: 44),
        const SizedBox(height: 16),
        Text(msg, textAlign: TextAlign.center,
            style: _dm(14, FontWeight.w400, p.sub, height: 1.5)),
      ]),
    ),
  );
}
