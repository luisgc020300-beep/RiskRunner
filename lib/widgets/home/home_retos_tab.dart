import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'home_theme.dart';

typedef OnConfirmarReto = void Function({
  required String id,
  required String titulo,
  required String desc,
  required int premio,
  required int objetivoMetros,
});

class HomeRetosTab extends StatefulWidget {
  final List<Map<String, dynamic>> completedChallenges;
  final bool loadingChallenges;
  final List<QueryDocumentSnapshot> dailyChallenges;
  final ValueListenable<Duration> timeUntilReset;
  final OnConfirmarReto onConfirmarReto;

  const HomeRetosTab({
    super.key,
    required this.completedChallenges,
    required this.loadingChallenges,
    required this.dailyChallenges,
    required this.timeUntilReset,
    required this.onConfirmarReto,
  });

  @override
  State<HomeRetosTab> createState() => _HomeRetosTabState();
}

class _HomeRetosTabState extends State<HomeRetosTab> {
  bool _mostrarTodosLosLogros = false;

  @override
  Widget build(BuildContext context) {
    final T = HomePalette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionHeader(T,
            'LOGROS DE HOY', Icons.emoji_events_outlined,
            widget.completedChallenges.length > 3
                ? (_mostrarTodosLosLogros
                    ? 'VER MENOS'
                    : 'VER TODOS (${widget.completedChallenges.length})')
                : '',
            () => setState(() => _mostrarTodosLosLogros = !_mostrarTodosLosLogros)),
        const SizedBox(height: 14),
        _buildCompletedChallengesList(T),
        const SizedBox(height: 28),
        _buildSectionHeader(T, 'MISIONES DEL DÍA', Icons.bolt_outlined, '', null),
        const SizedBox(height: 8),
        _buildDailyResetTimer(T),
        const SizedBox(height: 14),
        _buildDailyChallengesList(T),
      ]),
    );
  }

  Widget _buildSectionHeader(HomePalette T, String title, IconData icon,
      String action, VoidCallback? onAction) {
    return Row(children: [
      Container(width: 2, height: 14, color: T.bronze),
      const SizedBox(width: 9),
      Icon(icon, color: T.dim, size: 11),
      const SizedBox(width: 7),
      Text(title, style: homeStyle(10, FontWeight.w700, T.dim, spacing: 2.5)),
      const Spacer(),
      if (action.isNotEmpty)
        GestureDetector(
          onTap: onAction,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: T.bg2, border: Border.all(color: T.border2)),
            child: Text(action,
                style: homeStyle(9, FontWeight.w800, T.sub, spacing: 1.2)),
          ),
        ),
    ]);
  }

  Widget _buildDailyResetTimer(HomePalette T) {
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.timeUntilReset,
      builder: (_, remaining, __) {
        final h = remaining.inHours.toString().padLeft(2, '0');
        final m = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
        final s = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: T.bg1, border: Border.all(color: T.border2)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.timer_outlined, color: T.muted, size: 12),
            const SizedBox(width: 6),
            Text('RESET EN $h:$m:$s',
                style: homeStyle(11, FontWeight.w700, T.text, spacing: 1.5)),
          ]),
        );
      },
    );
  }

  Widget _buildCompletedChallengesList(HomePalette T) {
    if (widget.completedChallenges.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: T.bg1, border: Border.all(color: T.border2)),
        child: Row(children: [
          Icon(Icons.hourglass_empty_rounded, color: T.muted, size: 14),
          const SizedBox(width: 10),
          Text('Ningún reto completado hoy todavía',
              style: homeStyle(13, FontWeight.w500, T.muted)),
        ]),
      );
    }
    final lista = _mostrarTodosLosLogros
        ? widget.completedChallenges
        : widget.completedChallenges.take(3).toList();
    return Column(children: lista.map((data) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: T.bg1,
          border: Border(
              left: BorderSide(color: T.safe, width: 2),
              top: BorderSide(color: T.border2),
              right: BorderSide(color: T.border2),
              bottom: BorderSide(color: T.border2))),
      child: Row(children: [
        Icon(Icons.check_circle_outline_rounded, color: T.safe, size: 17),
        const SizedBox(width: 12),
        Expanded(child: Text(data['titulo'] ?? 'Reto completado',
            style: homeStyle(13, FontWeight.w600, T.white))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: T.bg2, border: Border.all(color: T.border2)),
          child: Text('+${data['recompensa']}',
              style: homeStyle(12, FontWeight.w900, T.gold)),
        ),
      ]),
    )).toList());
  }

  Widget _buildDailyChallengesList(HomePalette T) {
    if (widget.loadingChallenges) {
      return Center(child: CircularProgressIndicator(color: T.bronze, strokeWidth: 1.5));
    }
    if (widget.dailyChallenges.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: T.bg1,
            border: Border(
                left: BorderSide(color: T.safe, width: 2),
                top: BorderSide(color: T.border2),
                right: BorderSide(color: T.border2),
                bottom: BorderSide(color: T.border2))),
        child: Row(children: [
          Icon(Icons.check_circle_outline_rounded, color: T.safe, size: 14),
          const SizedBox(width: 10),
          Text('¡Todos los desafíos completados!',
              style: homeStyle(13, FontWeight.w600, T.safe)),
        ]),
      );
    }
    return Column(children: widget.dailyChallenges.map((doc) {
      final data       = (doc.data() ?? {}) as Map<String, dynamic>;
      final esPremium  = data['es_premium'] as bool? ?? false;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onConfirmarReto(
            id:             doc.id,
            titulo:         data['titulo'] as String? ?? 'Misión',
            desc:           data['descripcion'] as String? ?? '',
            premio:         (data['recompensas_monedas'] as num?)?.toInt() ?? 0,
            objetivoMetros: (data['objetivo_valor'] as num?)?.toInt() ?? 0,
          ),
          splashColor: T.bronze.withValues(alpha: 0.08),
          highlightColor: T.bronze.withValues(alpha: 0.04),
          child: _buildMissionCard(T,
              data['titulo'] ?? 'Misión',
              data['descripcion'] ?? '',
              '${data['recompensas_monedas'] ?? 0}',
              esPremium: esPremium),
        ),
      );
    }).toList());
  }

  Widget _buildMissionCard(HomePalette T, String title, String desc, String reward,
      {bool esPremium = false}) {
    const goldColor = Color(0xFFDECA46);
    final borderColor = esPremium ? goldColor : T.bronze;
    final iconBg      = esPremium
        ? goldColor.withValues(alpha: 0.08)
        : T.bronze.withValues(alpha: 0.07);
    final iconBorder  = esPremium
        ? goldColor.withValues(alpha: 0.3)
        : T.bronze.withValues(alpha: 0.20);
    final icon = esPremium ? Icons.workspace_premium_rounded : Icons.bolt_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: esPremium ? goldColor.withValues(alpha: 0.04) : T.bg1,
        border: Border(
          left: BorderSide(color: borderColor, width: 2),
          top: BorderSide(color: T.border2),
          right: BorderSide(color: T.border2),
          bottom: BorderSide(color: T.border2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              border: Border.all(color: iconBorder),
            ),
            child: Icon(icon, color: borderColor, size: 17),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (esPremium) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: goldColor.withValues(alpha: 0.12),
                    border: Border.all(color: goldColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(' PREMIUM',
                      style: homeStyle(7, FontWeight.w900, goldColor, spacing: 0.8)),
                ),
              ],
              Expanded(child: Text(title,
                  style: homeStyle(13, FontWeight.w800, T.white),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 4),
            Text(desc, style: homeStyle(11, FontWeight.w500, T.sub, height: 1.3)),
          ])),
          const SizedBox(width: 10),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('+$reward', style: GoogleFonts.inter(
                fontSize: 22, fontWeight: FontWeight.w700,
                color: esPremium ? goldColor : T.gold, height: 1)),
            Text('PTS', style: homeStyle(8, FontWeight.w800, T.muted, spacing: 2)),
          ]),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: T.muted, size: 15),
        ]),
      ),
    );
  }
}
