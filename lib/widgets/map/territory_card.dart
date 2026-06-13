import 'dart:ui';

import 'package:flutter/material.dart';

import '../../services/territory_service.dart';
import 'map_theme.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Color _tcDificultadColor(int level) {
  if (level <= 3) return kMapSafe;
  if (level <= 6) return kMapWarn;
  return kMapRed;
}

Widget _tcCardStat(IconData icon, String label, Color color) => Expanded(
      child: Column(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(label,
            style: mapRaj(9, FontWeight.w800, color, spacing: 0.5),
            textAlign: TextAlign.center),
      ]),
    );

Widget _tcVDiv(Color borderColor) => Container(
    width: 1,
    height: 36,
    color: borderColor,
    margin: const EdgeInsets.symmetric(horizontal: 4));

Widget _tcMiniStat(
  IconData icon,
  String value,
  String label, {
  Color? color,
  required Color textColor,
  required Color subColor,
}) {
  final c = color ?? subColor;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 9, color: c),
        const SizedBox(width: 3),
        Text(value, style: mapRaj(9, FontWeight.w800, textColor)),
      ]),
      Text(label, style: mapRaj(7, FontWeight.w700, c, spacing: 0.8)),
    ],
  );
}

// ── TerritoryCard ─────────────────────────────────────────────────────────────

class TerritoryCard extends StatelessWidget {
  final TerritoryData t;
  final Animation<double> selAnim;
  final Color bgColor;
  final Color textColor;
  final Color borderColor;
  final Color surfColor;
  final VoidCallback onCerrar;
  final VoidCallback? onAtacar;
  final Widget Function(String docId) historialBuilder;

  const TerritoryCard({
    super.key,
    required this.t,
    required this.selAnim,
    required this.bgColor,
    required this.textColor,
    required this.borderColor,
    required this.surfColor,
    required this.onCerrar,
    this.onAtacar,
    required this.historialBuilder,
  });

  @override
  Widget build(BuildContext context) {
    String estadoLabel = 'ACTIVO';
    Color cEstado = kMapSafe;
    IconData estadoIcon = Icons.check_circle_rounded;
    if (t.estadoHp == EstadoHp.critico) {
      estadoLabel = 'CRÍTICO';
      cEstado = kMapRed;
      estadoIcon = Icons.warning_rounded;
    } else if (t.estadoHp == EstadoHp.danado) {
      estadoLabel = 'DAÑADO';
      cEstado = kMapWarn;
      estadoIcon = Icons.error_rounded;
    }

    final double hpFraction = t.hpActual / kHpMax.toDouble();

    return ScaleTransition(
      scale: selAnim,
      child: FadeTransition(
        opacity: selAnim,
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: t.color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(color: t.color.withValues(alpha: 0.18), blurRadius: 20),
              const BoxShadow(color: Colors.black54, blurRadius: 16),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Cabecera ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                color: t.color.withValues(alpha: 0.10),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
                border: Border(
                    bottom:
                        BorderSide(color: t.color.withValues(alpha: 0.25))),
              ),
              child: Row(children: [
                Container(
                    width: 3,
                    height: 20,
                    color: t.color,
                    margin: const EdgeInsets.only(right: 10)),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  Text(
                      t.esMio ? 'MI TERRITORIO' : t.ownerNickname.toUpperCase(),
                      style: mapRaj(13, FontWeight.w900, textColor,
                          spacing: 1.5)),
                  Text(
                      t.esMio ? 'ZONA CONTROLADA' : 'TERRITORIO RIVAL',
                      style: mapRaj(8, FontWeight.w700,
                          t.esMio ? t.color : kMapSub,
                          spacing: 2)),
                ])),
                GestureDetector(
                  onTap: onCerrar,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                        color: borderColor,
                        borderRadius: BorderRadius.circular(4)),
                    child: Icon(Icons.close_rounded,
                        color: textColor, size: 14),
                  ),
                ),
              ]),
            ),

            // ── Stats row ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(children: [
                _tcCardStat(estadoIcon, estadoLabel, cEstado),
                _tcVDiv(borderColor),
                _tcCardStat(
                    Icons.flag_rounded, '${t.puntos.length} PTS', textColor),
                _tcVDiv(borderColor),
                t.esMio
                    ? _tcCardStat(
                        Icons.shield_rounded, 'DEFENDER', kMapGold)
                    : GestureDetector(
                        onTap: () => onAtacar?.call(),
                        child: _tcCardStat(
                            Icons.flag_rounded, 'ATACAR', kMapRed),
                      ),
              ]),
            ),

            // ── Barra de vida ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: cEstado,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: cEstado.withValues(alpha: 0.6),
                              blurRadius: 4)
                        ],
                      ),
                      margin: const EdgeInsets.only(right: 6),
                    ),
                    Text(
                      t.estadoHp == EstadoHp.saludable
                          ? 'Territorio saludable'
                          : t.estadoHp == EstadoHp.danado
                              ? 'Territorio debilitado'
                              : 'En estado crítico',
                      style: mapRaj(9, FontWeight.w700, cEstado,
                          spacing: 0.5),
                    ),
                    const Spacer(),
                    Text('${t.hpActual}/$kHpMax HP',
                        style: mapRaj(9, FontWeight.w700, cEstado,
                            spacing: 0.5)),
                  ]),
                  const SizedBox(height: 5),
                  Stack(children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: borderColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: hpFraction.clamp(0.0, 1.0),
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: cEstado,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                                color: cEstado.withValues(alpha: 0.5),
                                blurRadius: 6)
                          ],
                        ),
                      ),
                    ),
                  ]),
                  if (!t.esMio) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.schedule_rounded,
                          color: kMapSub, size: 11),
                      const SizedBox(width: 4),
                      Text(
                        'Sin visitar: ${t.diasSinVisitar} día${t.diasSinVisitar == 1 ? '' : 's'}',
                        style: mapRaj(9, FontWeight.w600, kMapSub),
                      ),
                      if (t.esConquistableSinPasar) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: kMapRed.withValues(alpha: 0.12),
                            border: Border.all(
                                color: kMapRed.withValues(alpha: 0.5)),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('CONQUISTABLE',
                              style: mapRaj(8, FontWeight.w900, kMapRed)),
                        ),
                      ],
                    ]),
                  ],
                ],
              ),
            ),

            // ── Stats extra: dominio + velocidad + rey ──────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(children: [
                if (t.fechaDesdeDueno != null)
                  _tcMiniStat(
                    Icons.calendar_today_rounded,
                    '${DateTime.now().difference(t.fechaDesdeDueno!).inDays}d',
                    'DOMINIO',
                    textColor: textColor,
                    subColor: kMapSub,
                  ),
                if (t.fechaDesdeDueno != null) const SizedBox(width: 14),
                _tcMiniStat(
                  Icons.speed_rounded,
                  '${t.velocidadConquistaKmh.toStringAsFixed(1)} km/h',
                  'VELOCIDAD',
                  textColor: textColor,
                  subColor: kMapSub,
                ),
                const Spacer(),
                if (t.tieneRey)
                  _tcMiniStat(
                    Icons.military_tech_rounded,
                    t.reyNickname ?? 'Rey',
                    'REY',
                    color: kMapGold,
                    textColor: textColor,
                    subColor: kMapSub,
                  ),
              ]),
            ),

            // ── Historial de conquistas ───────────────────────────────
            if (!t.esFantasma)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                decoration: BoxDecoration(
                  color: surfColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: historialBuilder(t.docId),
              ),
          ]),
        ),
      ),
    );
  }
}

// ── GlobalTerritoryCard ───────────────────────────────────────────────────────

class GlobalTerritoryCard extends StatelessWidget {
  final GlobalTerritory t;
  final Animation<double> selAnim;
  final VoidCallback onCerrar;
  final void Function(GlobalTerritory) onConquistar;

  const GlobalTerritoryCard({
    super.key,
    required this.t,
    required this.selAnim,
    required this.onCerrar,
    required this.onConquistar,
  });

  @override
  Widget build(BuildContext context) {
    final Color baseColor = t.isMine
        ? kMapGold
        : t.isOwned
            ? (t.ownerColor ?? t.tierColor)
            : t.tierColor;

    return ScaleTransition(
      scale: selAnim,
      child: FadeTransition(
        opacity: selAnim,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: kMapSurface.withValues(alpha: 0.92),
                border: Border.all(color: baseColor.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                      color: baseColor.withValues(alpha: 0.2), blurRadius: 24),
                  const BoxShadow(color: Colors.black87, blurRadius: 16),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // ── Cabecera ────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        baseColor.withValues(alpha: 0.12),
                        Colors.transparent
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8)),
                    border: Border(
                        bottom: BorderSide(
                            color: baseColor.withValues(alpha: 0.2))),
                  ),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: baseColor.withValues(alpha: 0.40)),
                      ),
                      child: Center(
                          child: Text(t.icon,
                              style: const TextStyle(fontSize: 20))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: baseColor.withValues(alpha: 0.12),
                            border: Border.all(
                                color: baseColor.withValues(alpha: 0.35)),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(t.tierLabel,
                              style: mapRaj(7, FontWeight.w900, baseColor,
                                  spacing: 1)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _tcDificultadColor(t.difficultyLevel)
                                .withValues(alpha: 0.1),
                            border: Border.all(
                                color: _tcDificultadColor(t.difficultyLevel)
                                    .withValues(alpha: 0.35)),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('DIF. ${t.difficultyLevel}/10',
                              style: mapRaj(7, FontWeight.w900,
                                  _tcDificultadColor(t.difficultyLevel),
                                  spacing: 0.5)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(t.epicName,
                          style: mapCinzel(12, FontWeight.w700, kMapWhite)),
                      const SizedBox(height: 1),
                      Text(t.inspiration,
                          style: mapRaj(9, FontWeight.w500, kMapSub)),
                    ])),
                    GestureDetector(
                      onTap: onCerrar,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                            color: kMapBorder,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Icon(Icons.close_rounded,
                            color: kMapText, size: 14),
                      ),
                    ),
                  ]),
                ),

                // ── Stats ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(children: [
                    _tcCardStat(
                      Icons.directions_run_rounded,
                      '${t.kmRequired.toStringAsFixed(1)} km',
                      kMapCyan,
                    ),
                    _tcVDiv(kMapBorder),
                    _tcCardStat(Icons.monetization_on_rounded,
                        '+${t.rewardActual}', kMapGold),
                    _tcVDiv(kMapBorder),
                    t.isMine
                        ? _tcCardStat(Icons.stars_rounded, 'TUYO', kMapGold)
                        : t.isOwned
                            ? _tcCardStat(
                                Icons.dangerous_rounded, 'INVADIR', kMapRed)
                            : _tcCardStat(
                                Icons.flag_rounded, 'LIBRE', kMapSafe),
                  ]),
                ),

                if (t.isOwned && !t.isMine)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.06),
                        border: Border.all(
                            color: baseColor.withValues(alpha: 0.25)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: baseColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: baseColor.withValues(alpha: 0.5),
                                  blurRadius: 4)
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Controlado por ',
                            style: mapRaj(10, FontWeight.w500, kMapSub)),
                        Text(t.ownerNickname!.toUpperCase(),
                            style: mapRaj(10, FontWeight.w900, baseColor)),
                      ]),
                    ),
                  ),

                // ── Botón conquistar ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: GestureDetector(
                    onTap: () {
                      onCerrar();
                      Future.delayed(const Duration(milliseconds: 300), () {
                        onConquistar(t);
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: t.isMine
                            ? kMapGold.withValues(alpha: 0.08)
                            : baseColor.withValues(alpha: 0.15),
                        border: Border.all(
                            color: t.isMine
                                ? kMapGold.withValues(alpha: 0.3)
                                : baseColor.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                          child: Text(
                        t.isMine
                            ? 'TERRITORIO CONTROLADO'
                            : 'CONQUISTAR · ${t.kmRequired.toStringAsFixed(1)} KM',
                        style: mapRaj(11, FontWeight.w900,
                            t.isMine ? kMapGoldDim : baseColor,
                            spacing: 1),
                      )),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
