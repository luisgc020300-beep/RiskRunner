import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/desafios_service.dart';
import 'perfil_theme.dart';

class PerfilDuelosTab extends StatelessWidget {
  final String uid;
  final bool isOwnProfile;
  final Animation<double> fadeAnim;

  const PerfilDuelosTab({
    super.key,
    required this.uid,
    required this.isOwnProfile,
    required this.fadeAnim,
  });

  @override
  Widget build(BuildContext context) {
    final p = PerfilPalette.of(context);
    return FadeTransition(
      opacity: fadeAnim,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: StreamBuilder<List<DesafioInfo>>(
          stream: DesafiosService.streamActivos(uid),
          builder: (ctx, snapActivos) {
            return StreamBuilder<List<DesafioInfo>>(
              stream: DesafiosService.streamHistorial(uid),
              builder: (ctx, snapHistorial) {
                final activos   = snapActivos.data ?? [];
                final historial = snapHistorial.data ?? [];

                final ganados  = historial.where((d) => d.ganadorId == uid).length;
                final perdidos = historial.length - ganados;
                final winPct   = historial.isEmpty ? 0.0 : ganados / historial.length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    if (historial.isNotEmpty) ...[
                      _buildDuelosResumen(context, p, ganados, perdidos, winPct),
                      const SizedBox(height: 20),
                    ],

                    _panelLabel(p, 'DUELOS EN CURSO', Icons.sports_mma_rounded),
                    const SizedBox(height: 12),

                    if (!snapActivos.hasData)
                      _dueloLoader()
                    else if (activos.isEmpty)
                      _dueloEmpty(p, isOwnProfile
                          ? 'Sin duelos activos\nReta a alguien desde su perfil'
                          : 'Sin duelos activos')
                    else
                      ...activos.map((d) => _buildDueloCard(context, p, d, uid)),

                    const SizedBox(height: 28),

                    if (historial.isNotEmpty) ...[
                      _panelLabel(p, 'HISTORIAL DE DUELOS', Icons.history_rounded),
                      const SizedBox(height: 12),
                      ...historial.take(5).map((d) => _buildDueloHistorialCard(context, p, d, uid)),
                      if (historial.length > 5)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: GestureDetector(
                            onTap: () => Navigator.pushNamed(
                                context, '/desafios',
                                arguments: {'desafioId': null}),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text('Ver todos los duelos', style: perfilStyle(11, FontWeight.w600, p.text)),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right_rounded, color: p.dim, size: 14),
                            ]),
                          ),
                        ),
                    ],

                    const SizedBox(height: 100),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ── Resumen estadístico de duelos ─────────────────────────────────────────
  Widget _buildDuelosResumen(BuildContext context, PerfilPalette p, int ganados, int perdidos, double winPct) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border2),
      ),
      child: Row(children: [
        Expanded(child: _dueloStat(p, '$ganados', 'VICTORIAS', kPerfilGold)),
        Container(width: 1, height: 44, color: p.border2, margin: const EdgeInsets.symmetric(horizontal: 8)),
        Expanded(child: _dueloStat(p, '$perdidos', 'DERROTAS', kPerfilAccent)),
        Container(width: 1, height: 44, color: p.border2, margin: const EdgeInsets.symmetric(horizontal: 8)),
        Expanded(child: _dueloStat(p, '${(winPct * 100).toStringAsFixed(0)}%', 'WIN RATE', p.text)),
      ]),
    );
  }

  Widget _dueloStat(PerfilPalette p, String val, String label, Color color) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(val, style: GoogleFonts.inter(
            fontSize: 28, fontWeight: FontWeight.w900,
            color: color, height: 1)),
        Text(label, style: perfilStyle(8, FontWeight.w700, p.sub, spacing: 1.5)),
      ]);

  // ── Card de duelo activo ──────────────────────────────────────────────────
  Widget _buildDueloCard(BuildContext context, PerfilPalette p, DesafioInfo info, String uid) {
    final misPuntos   = info.puntosDeUsuario(uid);
    final rivalPuntos = info.puntosDeRival(uid);
    final rivalNick   = info.nickRival(uid);
    final voy         = misPuntos >= rivalPuntos;
    final total       = misPuntos + rivalPuntos;
    final miPct       = total > 0 ? misPuntos / total : 0.5;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/desafios',
          arguments: {'desafioId': info.id}),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: voy
                  ? kPerfilGold.withValues(alpha: 0.25)
                  : kPerfilAccent.withValues(alpha: 0.20)),
          boxShadow: [
            BoxShadow(
                color: (voy ? kPerfilGold : kPerfilAccent).withValues(alpha: 0.06),
                blurRadius: 16),
          ],
        ),
        child: Column(children: [

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(children: [
              Container(width: 2, height: 14, color: voy ? kPerfilGold : kPerfilAccent),
              const SizedBox(width: 10),
              Icon(Icons.bolt_rounded, color: voy ? kPerfilGold : kPerfilAccent, size: 13),
              const SizedBox(width: 6),
              Text('DUELO ACTIVO',
                  style: perfilStyle(9, FontWeight.w900,
                      voy ? kPerfilGold : kPerfilAccent, spacing: 2)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: p.border2.withValues(alpha: 0.5),
                  border: Border.all(color: p.border2),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.timer_outlined, color: p.sub, size: 10),
                  const SizedBox(width: 4),
                  Text(info.tiempoRestante,
                      style: perfilStyle(10, FontWeight.w700, p.text)),
                ]),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: p.dim, size: 14),
            ]),
          ),

          // Marcador
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(children: [
              Expanded(child: Column(children: [
                Text('TÚ', style: perfilStyle(8, FontWeight.w700, p.sub, spacing: 2)),
                const SizedBox(height: 4),
                _AnimatedCounter(
                  value: misPuntos.toDouble(),
                  style: GoogleFonts.inter(
                      fontSize: 40, fontWeight: FontWeight.w900,
                      color: voy ? p.title : p.sub, height: 1,
                      shadows: voy
                          ? [Shadow(color: kPerfilGold.withValues(alpha: 0.4), blurRadius: 12)]
                          : []),
                  duration: const Duration(milliseconds: 900),
                ),
                Text('PTS', style: perfilStyle(8, FontWeight.w700,
                    voy ? kPerfilGold : p.dim, spacing: 2)),
              ])),

              Column(children: [
                Text('VS', style: perfilStyle(11, FontWeight.w900, p.muted, spacing: 3)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kPerfilGold.withValues(alpha: 0.06),
                    border: Border.all(color: kPerfilGold.withValues(alpha: 0.25)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${info.apuesta}', style: perfilStyle(10, FontWeight.w900, kPerfilGold)),
                    const SizedBox(width: 3),
                    const Icon(Icons.monetization_on_rounded, color: kPerfilGold, size: 10),
                  ]),
                ),
              ]),

              Expanded(child: Column(children: [
                Text(rivalNick.toUpperCase(),
                    style: perfilStyle(8, FontWeight.w700, p.sub, spacing: 1),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                _AnimatedCounter(
                  value: rivalPuntos.toDouble(),
                  style: GoogleFonts.inter(
                      fontSize: 40, fontWeight: FontWeight.w900,
                      color: !voy ? p.title : p.sub, height: 1,
                      shadows: !voy
                          ? [Shadow(color: kPerfilAccent.withValues(alpha: 0.4), blurRadius: 12)]
                          : []),
                  duration: const Duration(milliseconds: 900),
                ),
                Text('PTS', style: perfilStyle(8, FontWeight.w700,
                    !voy ? kPerfilAccent : p.dim, spacing: 2)),
              ])),
            ]),
          ),

          // Barra progreso
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 5,
                  child: Row(children: [
                    Flexible(
                      flex: (miPct * 100).round().clamp(1, 99),
                      child: Container(color: voy ? kPerfilGold : kPerfilAccent),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (voy ? kPerfilGold : kPerfilAccent).withValues(alpha: 0.08),
                    border: Border.all(
                        color: (voy ? kPerfilGold : kPerfilAccent).withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(voy ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        color: voy ? kPerfilGold : kPerfilAccent, size: 9),
                    const SizedBox(width: 3),
                    Text(voy ? 'Ganando' : 'Perdiendo',
                        style: perfilStyle(9, FontWeight.w800, voy ? kPerfilGold : kPerfilAccent)),
                  ]),
                ),
                const Spacer(),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Premio: ${info.apuesta * 2}', style: perfilStyle(9, FontWeight.w600, p.sub)),
                  const SizedBox(width: 3),
                  const Icon(Icons.monetization_on_rounded, color: kPerfilGold, size: 9),
                ]),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Card historial de duelos ──────────────────────────────────────────────
  Widget _buildDueloHistorialCard(BuildContext context, PerfilPalette p, DesafioInfo info, String uid) {
    final gane       = info.ganadorId == uid;
    final rival      = info.nickRival(uid);
    final misPuntos  = info.puntosDeUsuario(uid);
    final rivalPts   = info.puntosDeRival(uid);
    final color      = gane ? kPerfilGold : kPerfilAccent;
    final premio     = gane ? '+${info.apuesta * 2}' : '-${info.apuesta}';

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/desafios',
          arguments: {'desafioId': info.id}),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: color.withValues(alpha: 0.6), width: 2),
            top: BorderSide(color: p.border2),
            right: BorderSide(color: p.border2),
            bottom: BorderSide(color: p.border2),
          ),
        ),
        child: Row(children: [
          Text(gane ? '' : '', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              gane
                  ? 'Victoria vs ${rival.toUpperCase()}'
                  : 'Derrota vs ${rival.toUpperCase()}',
              style: perfilStyle(13, FontWeight.w800, p.title),
            ),
            const SizedBox(height: 3),
            Text('$misPuntos pts vs $rivalPts pts',
                style: perfilStyle(10, FontWeight.w500, p.sub)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              border: Border.all(color: color.withValues(alpha: 0.28)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(premio, style: perfilStyle(12, FontWeight.w900, color)),
              const SizedBox(width: 3),
              Icon(Icons.monetization_on_rounded, color: color, size: 11),
            ]),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: p.dim, size: 14),
        ]),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _panelLabel(PerfilPalette p, String label, IconData icon) => Row(children: [
    Container(width: 2, height: 13, decoration: BoxDecoration(
        color: p.border2, borderRadius: BorderRadius.circular(1))),
    const SizedBox(width: 9),
    Icon(icon, color: p.dim, size: 11),
    const SizedBox(width: 6),
    Text(label, style: perfilStyle(10, FontWeight.w700, p.dim, spacing: 2.5)),
  ]);

  Widget _dueloLoader() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: Center(child: SizedBox(width: 16, height: 16,
        child: CircularProgressIndicator(color: kPerfilAccent, strokeWidth: 1.5))),
  );

  Widget _dueloEmpty(PerfilPalette p, String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.sports_mma_rounded, color: p.muted, size: 36),
      const SizedBox(height: 12),
      Text(msg, textAlign: TextAlign.center,
          style: perfilStyle(12, FontWeight.w500, p.sub, height: 1.5)),
    ])),
  );
}

// ── AnimatedCounter privado — copia local para este tab ──────────────────────
class _AnimatedCounter extends StatefulWidget {
  final double value;
  final int decimals;
  final TextStyle style;
  final Duration duration;

  const _AnimatedCounter({
    required this.value,
    required this.style,
    this.decimals = 1,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<_AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<_AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _prevValue = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween<double>(begin: 0, end: widget.value).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    if (widget.value > 0) _ctrl.forward();
  }

  @override
  void didUpdateWidget(_AnimatedCounter old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _anim = Tween<double>(begin: _prevValue, end: widget.value).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _ctrl.forward(from: 0);
    }
    _prevValue = widget.value;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) {
      final val = _anim.value;
      final text = widget.decimals > 0
          ? val.toStringAsFixed(widget.decimals)
          : val.toInt().toString();
      return Text(text, style: widget.style);
    },
  );
}
