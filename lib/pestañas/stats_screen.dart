import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/stats_service.dart';

// =============================================================================
// PALETA (coherente con War Room / ResumenScreen)
// =============================================================================
const _kBg      = Color(0xFFE8E8ED);
const _kSurface = Color(0xFFFFFFFF);
const _kBorder  = Color(0xFFC6C6C8);
const _kBorder2 = Color(0xFFD1D1D6);
const _kMuted   = Color(0xFFAEAEB2);
const _kDim     = Color(0xFF8E8E93);
const _kOrange  = Color(0xFFE02020);

// =============================================================================
// PANTALLA PRINCIPAL
// =============================================================================

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with TickerProviderStateMixin {

  // ── Estado ─────────────────────────────────────────────────────────────────
  bool _cargando = true;
  List<CarreraStats> _carreras = [];
  List<PuntoTendencia> _tendencia = [];
  PrediccionTiempo? _prediccion;
  Map<ZonaRitmo, _RangoDisplay> _zonas = {};

  // ── Animaciones ────────────────────────────────────────────────────────────
  late AnimationController _entradaCtrl;
  late AnimationController _graficaCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _graficaProg;

  @override
  void initState() {
    super.initState();

    _entradaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _graficaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));

    _fadeAnim    = CurvedAnimation(parent: _entradaCtrl, curve: Curves.easeOut);
    _graficaProg = CurvedAnimation(parent: _graficaCtrl, curve: Curves.easeOutCubic);

    _cargar();
  }

  @override
  void dispose() {
    _entradaCtrl.dispose();
    _graficaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final carreras = await StatsService.cargarCarreras(limite: 50);
    final tendencia = StatsService.calcularTendencia4Semanas(carreras);
    final prediccion = StatsService.calcularPrediccion(carreras);
    final zonasRaw   = StatsService.calcularZonasPersonalizadas(carreras);

    // Construir datos de zonas para la UI
    final zonas = <ZonaRitmo, _RangoDisplay>{};
    int totalCarreras = carreras.length;
    for (final zona in ZonaRitmo.values) {
      final count = carreras.where((c) => c.zona == zona).length;
      final pct   = totalCarreras > 0 ? count / totalCarreras : 0.0;
      zonas[zona] = _RangoDisplay(count: count, pct: pct);
    }

    if (mounted) {
      setState(() {
        _carreras  = carreras;
        _tendencia = tendencia;
        _prediccion = prediccion;
        _zonas     = zonas;
        _cargando  = false;
      });
      _entradaCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 300));
      _graficaCtrl.forward();
    }
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(children: [
        // Grid de fondo
        Positioned.fill(child: CustomPaint(painter: _GridBg())),

        SafeArea(
          child: _cargando
              ? _buildLoader()
              : FadeTransition(
                  opacity: _fadeAnim,
                  child: CustomScrollView(
                    slivers: [
                      _buildAppBar(),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            const SizedBox(height: 24),
                            _buildResumenGlobal(),
                            const SizedBox(height: 24),
                            _buildGraficaTendencia(),
                            const SizedBox(height: 24),
                            _buildZonasRitmo(),
                            const SizedBox(height: 24),
                            _buildPredictor(),
                            const SizedBox(height: 24),
                            _buildHistorialCarreras(),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _buildLoader() {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(
              color: _kOrange, strokeWidth: 2)),
        SizedBox(height: 16),
        Text('Cargando estadísticas…',
            style: TextStyle(color: _kDim, fontSize: 12,
                fontFamily: 'monospace', letterSpacing: 1)),
      ]),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────
  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      backgroundColor: const Color(0xFF0D0D0D),
      elevation: 0,
      pinned: true,
      title: Row(children: [
        Container(width: 3, height: 18,
            color: _kOrange,
            margin: const EdgeInsets.only(right: 10)),
        const Text('ESTADÍSTICAS', style: TextStyle(
            color: Colors.white, fontSize: 15,
            fontWeight: FontWeight.w900, letterSpacing: 3)),
        const SizedBox(width: 8),
        Text('${_carreras.length} CARRERAS', style: const TextStyle(
            color: _kDim, fontSize: 10,
            fontFamily: 'monospace', letterSpacing: 1.5)),
      ]),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded,
            color: Colors.white, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  // ── Resumen global ──────────────────────────────────────────────────────────
  Widget _buildResumenGlobal() {
    final totalKm = _carreras.fold(0.0, (s, c) => s + c.distanciaKm);
    final totalSeg = _carreras.fold(0, (s, c) => s + c.tiempoSeg);
    final ritmoMedio = _carreras.isNotEmpty
        ? _carreras.map((c) => c.ritmoMinKm).reduce((a, b) => a + b) /
              _carreras.length
        : 0.0;
    final ritmoStr = ritmoMedio > 0
        ? "${ritmoMedio.floor()}'${(((ritmoMedio - ritmoMedio.floor()) * 60).round()).toString().padLeft(2, '0')}\""
        : '--';
    final horas = totalSeg ~/ 3600;
    final mins  = (totalSeg % 3600) ~/ 60;

    return _seccion(
      titulo: 'RESUMEN GLOBAL',
      child: Row(children: [
        Expanded(child: _metricaGrande('${totalKm.toStringAsFixed(0)} km',
            'Total corrido', Icons.straighten_rounded, _kOrange)),
        _divV(),
        Expanded(child: _metricaGrande('${horas}h ${mins}m',
            'Tiempo total', Icons.timer_outlined, Colors.purpleAccent)),
        _divV(),
        Expanded(child: _metricaGrande(ritmoStr,
            'Ritmo medio', Icons.speed_rounded, Colors.lightBlueAccent)),
      ]),
    );
  }

  // ── Gráfica de tendencia ────────────────────────────────────────────────────
  Widget _buildGraficaTendencia() {
    final tieneDatos = _tendencia.any((p) => p.ritmoMedio > 0);

    return _seccion(
      titulo: 'TENDENCIA 4 SEMANAS',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        if (!tieneDatos)
          _sinDatos('Necesitas al menos 2 semanas de carreras')
        else
          AnimatedBuilder(
            animation: _graficaCtrl,
            builder: (_, __) => SizedBox(
              height: 140,
              child: CustomPaint(
                painter: _GraficaTendencia(
                  puntos: _tendencia,
                  progress: _graficaProg.value,
                  color: _kOrange,
                ),
                child: Container(),
              ),
            ),
          ),
        const SizedBox(height: 12),
        // Leyenda semanas
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: _tendencia.map((p) {
            final label = p.numCarreras == 0
                ? 'Sin datos'
                : '${p.numCarreras} carrera${p.numCarreras > 1 ? 's' : ''}';
            return Column(children: [
              Text(_semanaLabel(p.semana),
                  style: const TextStyle(color: _kDim, fontSize: 9,
                      letterSpacing: 1, fontFamily: 'monospace')),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(
                  color: Colors.white38, fontSize: 9)),
            ]);
          }).toList(),
        ),
      ]),
    );
  }

  // ── Zonas de ritmo ──────────────────────────────────────────────────────────
  Widget _buildZonasRitmo() {
    return _seccion(
      titulo: 'DISTRIBUCIÓN POR ZONA',
      child: Column(
        children: ZonaRitmo.values.map((zona) {
          final display = _zonas[zona] ?? _RangoDisplay(count: 0, pct: 0);
          final color   = _hexToColor(zona.colorHex);
          return AnimatedBuilder(
            animation: _graficaCtrl,
            builder: (_, __) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Text(zona.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 10),
                SizedBox(width: 90,
                  child: Text(zona.nombre, style: const TextStyle(
                      color: Colors.white70, fontSize: 12))),
                const SizedBox(width: 8),
                Expanded(child: Stack(children: [
                  Container(height: 6,
                      decoration: BoxDecoration(
                          color: _kMuted,
                          borderRadius: BorderRadius.circular(3))),
                  FractionallySizedBox(
                    widthFactor: (display.pct * _graficaProg.value).clamp(0, 1),
                    child: Container(height: 6,
                        decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3))),
                  ),
                ])),
                const SizedBox(width: 10),
                SizedBox(width: 28,
                  child: Text('${display.count}',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: color, fontSize: 11,
                          fontWeight: FontWeight.w700))),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Predictor ──────────────────────────────────────────────────────────────
  Widget _buildPredictor() {
    if (_prediccion == null) {
      return _seccion(
        titulo: 'PREDICTOR DE TIEMPOS',
        child: _sinDatos('Necesitas al menos 3 carreras de +1km'),
      );
    }
    final p = _prediccion!;

    return _seccion(
      titulo: 'PREDICTOR DE TIEMPOS',
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded,
                color: _kDim, size: 12),
            const SizedBox(width: 6),
            Text(
              'Basado en tu ritmo medio de ${p.ritmoBase.floor()}\'${(((p.ritmoBase - p.ritmoBase.floor()) * 60).round()).toString().padLeft(2, '0')}" min/km',
              style: const TextStyle(color: _kDim, fontSize: 11),
            ),
          ]),
        ),
        Row(children: [
          Expanded(child: _prediccionCard('5K',      p.str5k,          Colors.lightBlueAccent)),
          const SizedBox(width: 10),
          Expanded(child: _prediccionCard('10K',     p.str10k,         Colors.purpleAccent)),
          const SizedBox(width: 10),
          Expanded(child: _prediccionCard('1/2 MAR', p.strMediaMaraton, _kOrange)),
        ]),
      ]),
    );
  }

  Widget _prediccionCard(String dist, String tiempo, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(children: [
        Text(dist, style: TextStyle(
            color: color.withValues(alpha: 0.7), fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 2)),
        const SizedBox(height: 6),
        Text(tiempo, style: TextStyle(
            color: color, fontSize: 19, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  // ── Historial de carreras ───────────────────────────────────────────────────
  Widget _buildHistorialCarreras() {
    if (_carreras.isEmpty) return const SizedBox.shrink();

    return _seccion(
      titulo: 'HISTORIAL',
      child: Column(
        children: _carreras.take(20).map((c) => _filaCarrera(c)).toList(),
      ),
    );
  }

  Widget _filaCarrera(CarreraStats c) {
    final color = _hexToColor(c.zona.colorHex);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(children: [
        // Zona indicator
        Container(width: 3, height: 36,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        // Fecha
        SizedBox(width: 44,
          child: Text(_fechaCorta(c.fecha), style: const TextStyle(
              color: _kDim, fontSize: 10, fontFamily: 'monospace')),
        ),
        const SizedBox(width: 10),
        // Distancia
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.distanciaKm.toStringAsFixed(2)} km',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 13)),
            if (c.calles.isNotEmpty)
              Text(c.calles.take(2).join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _kDim, fontSize: 10)),
          ],
        )),
        // Ritmo
        Text(c.ritmoStr, style: TextStyle(
            color: color, fontWeight: FontWeight.w900, fontSize: 13)),
        const SizedBox(width: 12),
        // Tiempo
        Text(c.tiempoStr, style: const TextStyle(
            color: Colors.white54, fontSize: 12)),
      ]),
    );
  }

  // ==========================================================================
  // WIDGETS HELPER
  // ==========================================================================

  Widget _seccion({required String titulo, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 2, height: 12,
              color: _kOrange, margin: const EdgeInsets.only(right: 8)),
          Text(titulo, style: const TextStyle(
              color: _kDim, fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 2.5)),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  Widget _metricaGrande(String valor, String label, IconData ico, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(ico, color: color.withValues(alpha: 0.7), size: 16),
      const SizedBox(height: 6),
      Text(valor, style: TextStyle(
          color: color, fontSize: 20,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: color.withValues(alpha: 0.3), blurRadius: 8)])),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(
          color: _kDim, fontSize: 9, letterSpacing: 1)),
    ]);
  }

  Widget _divV() => Container(
      width: 1, height: 50, color: _kBorder,
      margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _sinDatos(String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(child: Text(msg, style: const TextStyle(
        color: _kDim, fontSize: 12, letterSpacing: 0.5))),
  );

  String _semanaLabel(DateTime d) {
    const meses = ['ENE','FEB','MAR','ABR','MAY','JUN',
                   'JUL','AGO','SEP','OCT','NOV','DIC'];
    return '${d.day} ${meses[d.month - 1]}';
  }

  String _fechaCorta(DateTime d) {
    return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}';
  }

  Color _hexToColor(String hex) {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }
}

// =============================================================================
// CLASE HELPER INTERNA
// =============================================================================

class _RangoDisplay {
  final int count;
  final double pct;
  const _RangoDisplay({required this.count, required this.pct});
}

// =============================================================================
// PAINTER: grid de fondo
// =============================================================================

class _GridBg extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A22)
      ..strokeWidth = 0.5;
    const spacing = 36.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override
  bool shouldRepaint(_GridBg old) => false;
}

// =============================================================================
// PAINTER: gráfica de tendencia de ritmo
// =============================================================================

class _GraficaTendencia extends CustomPainter {
  final List<PuntoTendencia> puntos;
  final double progress;
  final Color color;

  const _GraficaTendencia({
    required this.puntos,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final validos = puntos.where((p) => p.ritmoMedio > 0).toList();
    if (validos.length < 2) return;

    final minRitmo = validos.map((p) => p.ritmoMedio).reduce(math.min);
    final maxRitmo = validos.map((p) => p.ritmoMedio).reduce(math.max);
    final rangoRitmo = (maxRitmo - minRitmo).clamp(0.5, double.infinity);

    final pad = const EdgeInsets.fromLTRB(8, 12, 8, 24);
    final w   = size.width  - pad.left - pad.right;
    final h   = size.height - pad.top  - pad.bottom;

    // Calcular puntos en pantalla (nota: ritmo más bajo = más rápido = arriba)
    final pts = <Offset>[];
    for (int i = 0; i < puntos.length; i++) {
      final p   = puntos[i];
      final x   = pad.left + (i / (puntos.length - 1)) * w;
      final y   = p.ritmoMedio > 0
          ? pad.top + (1 - (maxRitmo - p.ritmoMedio) / rangoRitmo) * h
          : pad.top + h; // sin datos → fondo
      pts.add(Offset(x, y));
    }

    // Líneas de cuadrícula horizontales
    final gridPaint = Paint()
      ..color = const Color(0xFF1E1E28)
      ..strokeWidth = 1;
    for (int i = 0; i <= 3; i++) {
      final y = pad.top + (i / 3) * h;
      canvas.drawLine(Offset(pad.left, y), Offset(pad.left + w, y), gridPaint);
      // Label de ritmo
      final ritmoLabel = maxRitmo - (i / 3) * rangoRitmo;
      final min = ritmoLabel.floor();
      final seg = ((ritmoLabel - min) * 60).round();
      final tp = TextPainter(
        text: TextSpan(
          text: "$min'${seg.toString().padLeft(2, '0')}\"",
          style: const TextStyle(color: Color(0xFF444458), fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - 5));
    }

    // Solo dibujar hasta progress
    final totalPts  = pts.length;
    final drawHasta = (totalPts * progress).round().clamp(1, totalPts);
    final ptsDraw   = pts.sublist(0, drawHasta);

    if (ptsDraw.length < 2) return;

    // Área de relleno
    final fillPath = Path()..moveTo(ptsDraw.first.dx, pad.top + h);
    for (final p in ptsDraw) { fillPath.lineTo(p.dx, p.dy); }
    fillPath.lineTo(ptsDraw.last.dx, pad.top + h);
    fillPath.close();

    canvas.drawPath(fillPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, pad.top, w, h)));

    // Línea principal
    final linePath = Path()..moveTo(ptsDraw.first.dx, ptsDraw.first.dy);
    for (int i = 1; i < ptsDraw.length; i++) {
      // Curva suave con bezier
      final prev = ptsDraw[i - 1];
      final curr = ptsDraw[i];
      final cpX  = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(cpX, prev.dy, cpX, curr.dy, curr.dx, curr.dy);
    }
    canvas.drawPath(linePath, Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round);

    // Puntos
    for (final p in ptsDraw) {
      canvas.drawCircle(p, 4, Paint()..color = _kBg);
      canvas.drawCircle(p, 4, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_GraficaTendencia old) =>
      old.progress != progress || old.puntos != puntos;
}