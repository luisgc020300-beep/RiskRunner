import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

import 'package:RunnerRisk/models/notif_item.dart';
import 'package:RunnerRisk/widgets/mini_mapa_notif.dart';

class HistorialGuerraScreen extends StatefulWidget {
  const HistorialGuerraScreen({super.key});

  @override
  State<HistorialGuerraScreen> createState() => _HistorialGuerraScreenState();
}

class _HistorialGuerraScreenState extends State<HistorialGuerraScreen>
    with SingleTickerProviderStateMixin {
  final String? userId = FirebaseAuth.instance.currentUser?.uid;
  late TabController _tabController;

  List<NotifItem> _perdidos = [];
  List<NotifItem> _ganados = [];
  bool _isLoading = true;

  Color _colorTerritorio = Colors.orange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargarTodo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    if (userId == null) return;
    setState(() => _isLoading = true);
    await Future.wait([
      _cargarColor(),
      _cargarHistorial(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _cargarColor() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players')
          .doc(userId)
          .get();
      if (doc.exists) {
        final colorInt =
            (doc.data()?['territorio_color'] as num?)?.toInt();
        if (colorInt != null && mounted) {
          setState(() => _colorTerritorio = Color(colorInt));
        }
      }
    } catch (e) {
      debugPrint('Error cargando color: $e');
    }
  }

  // ✅ FIX: Eliminado orderBy('timestamp') de Firestore — causa fallo silencioso
  // al combinarse con where('toUserId') sin índice compuesto.
  // Ahora se obtienen todos los docs del usuario y se ordena en memoria.
  // También se amplió el límite de 100 a 500 para mostrar todo el historial.
  Future<void> _cargarHistorial() async {
    if (userId == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('toUserId', isEqualTo: userId)
          .get(); // ← sin orderBy ni limit, para no necesitar índice compuesto

      final List<NotifItem> perdidos = [];
      final List<NotifItem> ganados = [];

      for (final doc in snap.docs) {
        final item = NotifItem.fromFirestore(doc);
        if (item.tipo == 'territory_lost') {
          perdidos.add(item);
        } else if (item.tipo == 'territory_conquered' ||
            item.tipo == 'territory_steal_success') {
          ganados.add(item);
        }
      }

      // Ordenar por timestamp descendente en memoria
      perdidos.sort((a, b) {
        if (a.timestamp == null || b.timestamp == null) return 0;
        return b.timestamp!.compareTo(a.timestamp!);
      });
      ganados.sort((a, b) {
        if (a.timestamp == null || b.timestamp == null) return 0;
        return b.timestamp!.compareTo(a.timestamp!);
      });

      if (mounted) {
        setState(() {
          _perdidos = perdidos;
          _ganados = ganados;
        });
      }
    } catch (e) {
      debugPrint('Error cargando historial: $e');
    }
  }

  String _formatearTiempo(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final ahora = DateTime.now();
    final fecha = timestamp.toDate();
    final dif = ahora.difference(fecha);
    if (dif.inMinutes < 1) return 'Ahora mismo';
    if (dif.inMinutes < 60) return 'Hace ${dif.inMinutes} min';
    if (dif.inHours < 24) return 'Hace ${dif.inHours} h';
    if (dif.inDays == 1) return 'Ayer';
    if (dif.inDays < 7) return 'Hace ${dif.inDays} días';
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }

  Future<void> _abrirDetalle(NotifItem item) async {
    if (item.territoryId == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('territories')
          .doc(item.territoryId)
          .get();

      List<LatLng> puntos = [];
      if (doc.exists) {
        final rawPuntos = doc.data()?['puntos'] as List?;
        if (rawPuntos != null) {
          puntos = rawPuntos
              .map((p) => LatLng(
                    (p['lat'] as num).toDouble(),
                    (p['lng'] as num).toDouble(),
                  ))
              .toList();
        }
      }

      if (!mounted) return;

      final bool esGanado = item.tipo == 'territory_conquered' ||
          item.tipo == 'territory_steal_success';
      final Color color =
          esGanado ? _colorTerritorio : Colors.redAccent;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => _DetalleBottomSheet(
          item: item,
          puntos: puntos,
          color: color,
          tiempoRelativo: _formatearTiempo(item.timestamp),
        ),
      );
    } catch (e) {
      debugPrint('Error abriendo detalle: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'HISTORIAL DE GUERRA',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orange),
            onPressed: _cargarTodo,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _colorTerritorio,
          indicatorWeight: 2,
          labelColor: _colorTerritorio,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 1.5),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('💀  PERDIDOS'),
                  if (_perdidos.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _Badge(
                        count: _perdidos.length,
                        color: Colors.redAccent),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('⚔️  GANADOS'),
                  if (_ganados.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _Badge(
                        count: _ganados.length,
                        color: _colorTerritorio),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orange))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildLista(_perdidos, esPerdidos: true),
                _buildLista(_ganados, esPerdidos: false),
              ],
            ),
    );
  }

  Widget _buildLista(List<NotifItem> items,
      {required bool esPerdidos}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              esPerdidos ? '🛡️' : '🏆',
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 16),
            Text(
              esPerdidos
                  ? 'Aún no has perdido ningún territorio'
                  : 'Aún no has conquistado territorios rivales',
              style: const TextStyle(
                  color: Colors.white38, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildResumenBanner(items, esPerdidos: esPerdidos),
        Expanded(
          child: ListView.builder(
            padding:
                const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: items.length,
            itemBuilder: (context, i) {
              return _buildTarjeta(items[i],
                  esPerdidos: esPerdidos);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResumenBanner(List<NotifItem> items,
      {required bool esPerdidos}) {
    final Color color =
        esPerdidos ? Colors.redAccent : _colorTerritorio;
    final int total = items.length;

    String ultimaVez = '--';
    if (items.isNotEmpty && items.first.timestamp != null) {
      ultimaVez = _formatearTiempo(items.first.timestamp);
    }

    final Map<String, int> frecuencia = {};
    for (final item in items) {
      final nick = item.fromNickname ?? '?';
      frecuencia[nick] = (frecuencia[nick] ?? 0) + 1;
    }
    String rivalTop = '--';
    if (frecuencia.isNotEmpty) {
      rivalTop = frecuencia.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _miniStat(color, total.toString(),
              esPerdidos ? 'Perdidos' : 'Ganados'),
          _verticalDivider(),
          _miniStat(color, ultimaVez, 'Última vez'),
          _verticalDivider(),
          _miniStat(
              color,
              rivalTop,
              esPerdidos
                  ? 'Rival + activo'
                  : 'Víctima + freq.'),
        ],
      ),
    );
  }

  Widget _miniStat(Color color, String value, String label) {
    return Expanded(
      child: Column(children: [
        Text(
          value,
          style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: Colors.white38, fontSize: 9),
            textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _verticalDivider() {
    return Container(
      width: 1,
      height: 32,
      color: Colors.white12,
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildTarjeta(NotifItem item,
      {required bool esPerdidos}) {
    final Color color =
        esPerdidos ? Colors.redAccent : _colorTerritorio;
    final String tiempo = _formatearTiempo(item.timestamp);
    final bool tieneDetalle = item.territoryId != null;

    return GestureDetector(
      onTap: tieneDetalle ? () => _abrirDetalle(item) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Icon(
                esPerdidos
                    ? Icons.shield_outlined
                    : Icons.flag_rounded,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.mensaje,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    if (item.fromNickname != null) ...[
                      Icon(Icons.person_outline,
                          color: color.withValues(alpha: 0.7),
                          size: 11),
                      const SizedBox(width: 3),
                      Text(
                        item.fromNickname!,
                        style: TextStyle(
                            color: color.withValues(alpha: 0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      tiempo,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10),
                    ),
                  ]),
                  if (item.distancia != null ||
                      item.tiempoSegundos != null) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      if (item.distancia != null)
                        _statChip(
                          Icons.straighten_outlined,
                          '${item.distancia!.toStringAsFixed(2)} km',
                          color,
                        ),
                      if (item.distancia != null &&
                          item.tiempoSegundos != null)
                        const SizedBox(width: 6),
                      if (item.distancia != null &&
                          item.tiempoSegundos != null &&
                          item.tiempoSegundos! > 0)
                        _statChip(
                          Icons.speed_outlined,
                          '${(item.distancia! / (item.tiempoSegundos! / 3600)).toStringAsFixed(1)} km/h',
                          color,
                        ),
                    ]),
                  ],
                ],
              ),
            ),
            if (tieneDetalle)
              Icon(Icons.chevron_right_rounded,
                  color: color.withValues(alpha: 0.5), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String value, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ── Bottom sheet de detalle ───────────────────────────────────────────────────
class _DetalleBottomSheet extends StatelessWidget {
  final NotifItem item;
  final List<LatLng> puntos;
  final Color color;
  final String tiempoRelativo;

  const _DetalleBottomSheet({
    required this.item,
    required this.puntos,
    required this.color,
    required this.tiempoRelativo,
  });

  String _calcVel() {
    if (item.distancia != null &&
        item.tiempoSegundos != null &&
        item.tiempoSegundos! > 0) {
      return '${(item.distancia! / (item.tiempoSegundos! / 3600)).toStringAsFixed(1)} km/h';
    }
    return '--';
  }

  @override
  Widget build(BuildContext context) {
    final bool esGanado = item.tipo == 'territory_conquered' ||
        item.tipo == 'territory_steal_success';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            CircleAvatar(radius: 5, backgroundColor: color),
            const SizedBox(width: 10),
            Text(
              (item.fromNickname ?? '?').toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1),
            ),
            const Spacer(),
            Text(tiempoRelativo,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 11)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.close,
                  color: Colors.white24, size: 20),
            ),
          ]),
          const SizedBox(height: 14),
          if (puntos.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 170,
                child: MiniMapaNotif(
                  puntos: puntos,
                  centro: puntos[0],
                  color: color,
                  label: '',
                ),
              ),
            ),
          if (puntos.isEmpty)
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text('Sin ubicación guardada',
                    style: TextStyle(
                        color: Colors.white24, fontSize: 12)),
              ),
            ),
          const SizedBox(height: 16),
          Row(children: [
            _statTile(Icons.info_outline, 'Estado',
                esGanado ? 'Conquistado' : 'Perdido', color),
            const SizedBox(width: 8),
            _statTile(
              Icons.straighten_outlined,
              'Distancia',
              item.distancia != null
                  ? '${item.distancia!.toStringAsFixed(2)} km'
                  : '--',
              Colors.lightBlueAccent,
            ),
            const SizedBox(width: 8),
            _statTile(Icons.speed_outlined, 'Vel. media',
                _calcVel(), Colors.purpleAccent),
            const SizedBox(width: 8),
            _statTile(
              Icons.timer_outlined,
              'Tiempo',
              item.tiempoSegundos != null
                  ? '${(item.tiempoSegundos! / 60).floor()} min'
                  : '--',
              Colors.orangeAccent,
            ),
          ]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _statTile(
      IconData icon, String label, String value, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: c, size: 14),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 9)),
            Text(value,
                style: TextStyle(
                    color: c,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

// ── Badge ─────────────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final int count;
  final Color color;
  const _Badge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$count',
        style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900),
      ),
    );
  }
}