// lib/widgets/rey_widgets.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/zona_service.dart';

const _kBg      = Color(0xFF030303);
const _kSurface = Color(0xFF0C0C0C);
const _kSurface2= Color(0xFF101010);
const _kBorder  = Color(0xFF161616);
const _kBorder2 = Color(0xFF1F1F1F);
const _kMuted   = Color(0xFF333333);
const _kDim     = Color(0xFF4A4A4A);
const _kSubtext = Color(0xFF666666);
const _kText    = Color(0xFFB0B0B0);
const _kWhite   = Color(0xFFEEEEEE);
const _kAccent  = Color(0xFFCC2222);
const _kGold    = Color(0xFFD4A017);
const _kGoldDim = Color(0xFF8B6914);

TextStyle _raj(double size, FontWeight w, Color c,
    {double spacing = 0, double? height}) =>
    GoogleFonts.rajdhani(
        fontSize: size,
        fontWeight: w,
        color: c,
        letterSpacing: spacing,
        height: height);

// ═══════════════════════════════════════════════════════════
//  BANNER ACTIVO — se muestra en la zona de identidad
//  cuando el usuario es rey en la temporada actual
// ═══════════════════════════════════════════════════════════

class ReyBannerActivo extends StatelessWidget {
  final List<TituloRey> titulosActivos;
  const ReyBannerActivo({super.key, required this.titulosActivos});

  @override
  Widget build(BuildContext context) {
    if (titulosActivos.isEmpty) return const SizedBox.shrink();

    // Si tiene varios reinos, mostramos el primero y un contador
    final titulo = titulosActivos.first;
    final extras = titulosActivos.length - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: _kGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _kGold.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('👑', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 7),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('REY DE ${titulo.zonaNombreDisplay.toUpperCase()}',
              style: _raj(10, FontWeight.w900, _kGold, spacing: 1.5)),
          Text('Temporada ${titulo.temporada} · en curso',
              style: _raj(8, FontWeight.w500, _kGoldDim)),
        ]),
        if (extras > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _kGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('+$extras', style: _raj(9, FontWeight.w800, _kGold)),
          ),
        ],
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PALMARÉS — sección completa para la tab de Stats
// ═══════════════════════════════════════════════════════════

class PalmaresPanel extends StatelessWidget {
  final List<TituloRey> titulos;
  final List<TituloRey> titulosActivos;

  const PalmaresPanel({
    super.key,
    required this.titulos,
    required this.titulosActivos,
  });

  @override
  Widget build(BuildContext context) {
    if (titulos.isEmpty && titulosActivos.isEmpty) {
      return _PanelVacio();
    }

    // Agrupamos por temporada
    final Map<int, List<TituloRey>> porTemporada = {};
    for (final t in titulos) {
porTemporada.putIfAbsent(t.temporada, () => []).add(t);    }
    final temporadasOrdenadas = porTemporada.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: _kGold.withValues(alpha: 0.12))),
            ),
            child: Row(children: [
              Container(
                width: 2,
                height: 13,
                decoration: BoxDecoration(
                    color: _kGold, borderRadius: BorderRadius.circular(1)),
              ),
              const SizedBox(width: 9),
              const Text('👑', style: TextStyle(fontSize: 11)),
              const SizedBox(width: 6),
              Text('PALMARÉS',
                  style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _kGoldDim,
                      letterSpacing: 2.5)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: _kGold.withValues(alpha: 0.20)),
                ),
                child: Text('${titulos.length} título${titulos.length == 1 ? '' : 's'}',
                    style: _raj(9, FontWeight.w700, _kGold)),
              ),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Títulos activos (temporada en curso)
                if (titulosActivos.isNotEmpty) ...[
                  _SectionLabel(label: 'EN CURSO', color: _kGold),
                  const SizedBox(height: 8),
                  ...titulosActivos.map((t) => _TituloCard(titulo: t, activo: true)),
                  const SizedBox(height: 16),
                ],

                // Histórico por temporada
                ...temporadasOrdenadas.map((temp) {
                  final lista = porTemporada[temp]!;
                  // No mostrar de nuevo los activos si coincide la temporada
                  final listaFiltrada = lista
                      .where((t) =>
                          !titulosActivos.any((a) => a.id == t.id))
                      .toList();
                  if (listaFiltrada.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionLabel(
                          label: 'TEMPORADA $temp', color: _kSubtext),
                      const SizedBox(height: 8),
                      ...listaFiltrada
                          .map((t) => _TituloCard(titulo: t, activo: false)),
                      const SizedBox(height: 12),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelVacio extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _kGold.withValues(alpha: 0.05),
            shape: BoxShape.circle,
            border:
                Border.all(color: _kGold.withValues(alpha: 0.12)),
          ),
          child: const Center(
              child: Text('👑', style: TextStyle(fontSize: 20))),
        ),
        const SizedBox(height: 12),
        Text('SIN TÍTULOS AÚN',
            style: _raj(10, FontWeight.w700, _kDim, spacing: 2)),
        const SizedBox(height: 4),
        Text('Domina un barrio al final de temporada para\nconvertirte en rey',
            style: _raj(11, FontWeight.w400, _kSubtext),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 16, height: 1, color: color.withValues(alpha: 0.3)),
      const SizedBox(width: 8),
      Text(label, style: _raj(8, FontWeight.w700, color, spacing: 2)),
      const SizedBox(width: 8),
      Expanded(
          child:
              Container(height: 1, color: color.withValues(alpha: 0.1))),
    ]);
  }
}

class _TituloCard extends StatelessWidget {
  final TituloRey titulo;
  final bool activo;
  const _TituloCard({required this.titulo, required this.activo});

  @override
  Widget build(BuildContext context) {
    final color = activo ? _kGold : _kText;
    final bgColor = activo
        ? _kGold.withValues(alpha: 0.06)
        : _kSurface2;
    final borderColor = activo
        ? _kGold.withValues(alpha: 0.30)
        : _kBorder2;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border(
            left: BorderSide(color: color.withValues(alpha: 0.5), width: 2)),
      ),
      child: Row(children: [
        Text(activo ? '👑' : '🏅',
            style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo.zonaNombreDisplay.toUpperCase(),
                  style: _raj(13, FontWeight.w800, color, spacing: 0.5),
                ),
                const SizedBox(height: 2),
                Row(children: [
                  Text(
                    activo
                        ? 'Temporada ${titulo.temporada} · en curso'
                        : 'Temporada ${titulo.temporada}',
                    style: _raj(10, FontWeight.w500, _kSubtext),
                  ),
                  if (titulo.areaM2 > 0) ...[
                    Container(
                        width: 1,
                        height: 8,
                        color: _kBorder2,
                        margin:
                            const EdgeInsets.symmetric(horizontal: 6)),
                    Text(
                      '${_formatArea(titulo.areaM2)} dominados',
                      style: _raj(10, FontWeight.w500, _kDim),
                    ),
                  ],
                ]),
              ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Text(
              '+${titulo.monedasRecompensa} 🪙',
              style: _raj(10, FontWeight.w800, color),
            ),
          ),
        ]),
      ]),
    );
  }

  String _formatArea(double m2) {
    if (m2 >= 1000000) return '${(m2 / 1000000).toStringAsFixed(1)} km²';
    if (m2 >= 10000) return '${(m2 / 10000).toStringAsFixed(1)} ha';
    return '${m2.toStringAsFixed(0)} m²';
  }
}

// ═══════════════════════════════════════════════════════════
//  MINI BADGE para mostrar junto al nickname en chats/social
// ═══════════════════════════════════════════════════════════

class ReyMiniBadge extends StatelessWidget {
  final String zonaNombre;
  final int temporada;
  final bool activo;

  const ReyMiniBadge({
    super.key,
    required this.zonaNombre,
    required this.temporada,
    this.activo = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: activo
            ? _kGold.withValues(alpha: 0.10)
            : _kMuted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
            color: activo
                ? _kGold.withValues(alpha: 0.30)
                : _kBorder2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(activo ? '👑' : '🏅',
            style: const TextStyle(fontSize: 8)),
        const SizedBox(width: 3),
        Text(
          activo ? zonaNombre.toUpperCase() : '$zonaNombre T$temporada',
          style: _raj(
              8,
              FontWeight.w700,
              activo ? _kGold : _kDim,
              spacing: 0.5),
        ),
      ]),
    );
  }
}