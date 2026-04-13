import 'package:flutter/material.dart';

import '../services/stats_service.dart';

// =============================================================================
// PALETA (idéntica a ResumenScreen / War Room)
// =============================================================================
const _kBg      = Color(0xFF060608);
const _kSurface = Color(0xFF0D0D10);
const _kBorder  = Color(0xFF1E1E24);
const _kDim     = Color(0xFF666680);
const _kOrange  = Color(0xFFE8500A);

// =============================================================================
// WIDGET PRINCIPAL
// Se embebe en ResumenScreen pasándole la carrera actual y el historial.
// =============================================================================

class StatsResumenWidget extends StatefulWidget {
  final CarreraStats carreraActual;
  final List<CarreraStats> historial;

  const StatsResumenWidget({
    super.key,
    required this.carreraActual,
    required this.historial,
  });

  @override
  State<StatsResumenWidget> createState() => _StatsResumenWidgetState();
}

class _StatsResumenWidgetState extends State<StatsResumenWidget>
    with SingleTickerProviderStateMixin {

  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _slide;

  ComparativaRuta? _comparativa;
  PrediccionTiempo? _prediccion;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 20, end: 0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _comparativa = StatsService.compararConAnterior(
        widget.carreraActual, widget.historial);
    _prediccion  = StatsService.calcularPrediccion(widget.historial);

    // Animar con delay para no chocar con las animaciones del ResumenScreen
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Opacity(
        opacity: _fade.value,
        child: Transform.translate(
          offset: Offset(0, _slide.value),
          child: child,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildCabeceraSeccion(),
        const SizedBox(height: 12),
        _buildZonaHoy(),
        const SizedBox(height: 10),
        if (_comparativa != null) ...[
          _buildComparativa(_comparativa!),
          const SizedBox(height: 10),
        ],
        if (_prediccion != null)
          _buildPrediccionRapida(_prediccion!),
      ]),
    );
  }

  // ── Cabecera ────────────────────────────────────────────────────────────────
  Widget _buildCabeceraSeccion() {
    return Row(children: [
      Container(width: 2, height: 12, color: _kOrange,
          margin: const EdgeInsets.only(right: 8)),
      const Text('ANÁLISIS DE CARRERA', style: TextStyle(
          color: _kDim, fontSize: 9,
          fontWeight: FontWeight.w700, letterSpacing: 2.5)),
    ]);
  }

  // ── Zona de ritmo de hoy ────────────────────────────────────────────────────
  Widget _buildZonaHoy() {
    final zona  = widget.carreraActual.zona;
    final color = _hexToColor(zona.colorHex);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Text(zona.emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Zona ${zona.nombre}', style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              'Ritmo de hoy: ${widget.carreraActual.ritmoStr} min/km',
              style: const TextStyle(color: _kDim, fontSize: 11),
            ),
          ],
        )),
        // Ritmo grande
        Text(widget.carreraActual.ritmoStr, style: TextStyle(
            color: color, fontSize: 22, fontWeight: FontWeight.w900,
            shadows: [Shadow(color: color.withValues(alpha: 0.3), blurRadius: 8)])),
      ]),
    );
  }

  // ── Comparativa con carrera anterior ───────────────────────────────────────
  Widget _buildComparativa(ComparativaRuta comp) {
    final esMejor = comp.esMasRapido;
    final color   = esMejor ? Colors.greenAccent : Colors.redAccent;
    final icono   = esMejor ? Icons.trending_up_rounded : Icons.trending_down_rounded;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.compare_arrows_rounded, color: _kDim, size: 13),
          const SizedBox(width: 6),
          const Text('VS CARRERA ANTERIOR (MISMA RUTA)',
              style: TextStyle(color: _kDim, fontSize: 9,
                  letterSpacing: 1.5, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          // Delta ritmo
          Expanded(child: _deltaCard(
            titulo: 'RITMO',
            valor: comp.deltaRitmoStr,
            color: color,
            icono: icono,
          )),
          const SizedBox(width: 10),
          // Delta distancia
          Expanded(child: _deltaCard(
            titulo: 'DISTANCIA',
            valor: '${comp.deltaDistanciaKm >= 0 ? '+' : ''}${comp.deltaDistanciaKm.toStringAsFixed(2)} km',
            color: comp.deltaDistanciaKm >= 0
                ? Colors.greenAccent : Colors.white38,
            icono: comp.deltaDistanciaKm >= 0
                ? Icons.add_rounded : Icons.remove_rounded,
          )),
          const SizedBox(width: 10),
          // Fecha anterior
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('REFERENCIA', style: TextStyle(
                  color: _kDim, fontSize: 9, letterSpacing: 1.5)),
              const SizedBox(height: 4),
              Text(_fechaRelativa(comp.anterior.fecha),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Text(comp.anterior.ritmoStr, style: const TextStyle(
                  color: _kDim, fontSize: 11)),
            ],
          )),
        ]),
        if (esMejor) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: Colors.greenAccent.withValues(alpha: 0.2)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.emoji_events_rounded,
                  color: Colors.greenAccent, size: 14),
              const SizedBox(width: 6),
              Text('¡Nuevo récord en esta ruta!', style: TextStyle(
                  color: Colors.greenAccent.withValues(alpha: 0.8),
                  fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _deltaCard({
    required String titulo,
    required String valor,
    required Color color,
    required IconData icono,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: const TextStyle(
            color: _kDim, fontSize: 9, letterSpacing: 1.5)),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, color: color, size: 14),
          const SizedBox(width: 4),
          Flexible(child: Text(valor, style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w800))),
        ]),
      ]);

  // ── Proyección rápida ───────────────────────────────────────────────────────
  Widget _buildPrediccionRapida(PrediccionTiempo p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_graph_rounded, color: _kDim, size: 13),
          const SizedBox(width: 6),
          const Text('PROYECCIÓN ACTUALIZADA',
              style: TextStyle(color: _kDim, fontSize: 9,
                  letterSpacing: 1.5, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _miniProyeccion('5K', p.str5k, Colors.lightBlueAccent),
          const SizedBox(width: 8),
          _miniProyeccion('10K', p.str10k, Colors.purpleAccent),
          const SizedBox(width: 8),
          _miniProyeccion('21K', p.strMediaMaraton, _kOrange),
        ]),
      ]),
    );
  }

  Widget _miniProyeccion(String dist, String tiempo, Color color) =>
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Text(dist, style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2)),
          const SizedBox(height: 4),
          Text(tiempo, style: TextStyle(
              color: color, fontSize: 14, fontWeight: FontWeight.w900)),
        ]),
      ));

  // ── Helpers ─────────────────────────────────────────────────────────────────
  Color _hexToColor(String hex) =>
      Color(int.parse(hex.replaceFirst('#', '0xFF')));

  String _fechaRelativa(DateTime d) {
    final diff = DateTime.now().difference(d).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    if (diff < 7)  return 'Hace $diff días';
    if (diff < 30) return 'Hace ${diff ~/ 7} sem.';
    return '${d.day}/${d.month}';
  }
}