// lib/screens/rutas_explorador_screen.dart
//
// Pantalla de exploración y descubrimiento de rutas:
// Popular | Nuevas | Amigos | Guardadas
//
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../services/route_service.dart';
import '../pestañas/LiveActivity_screen.dart';
import '../pestañas/perfil_screen.dart';

// =============================================================================
//  PALETA
// =============================================================================
class _RP {
  final Color bg, surface, surface2, surface3;
  final Color line, line2, dim, subtext, text3, text2, text1;
  const _RP._({
    required this.bg, required this.surface,
    required this.surface2, required this.surface3,
    required this.line, required this.line2,
    required this.dim, required this.subtext,
    required this.text3, required this.text2, required this.text1,
  });
  static const light = _RP._(
    bg: Color(0xFFE8E8ED), surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFE5E5EA), surface3: Color(0xFFF2F2F7),
    line: Color(0xFFC6C6C8), line2: Color(0xFFD1D1D6),
    dim: Color(0xFFAEAEB2), subtext: Color(0xFF8E8E93),
    text3: Color(0xFF636366), text2: Color(0xFF3C3C43), text1: Color(0xFF1C1C1E),
  );
  static const dark = _RP._(
    bg: Color(0xFF090807), surface: Color(0xFF1C1C1E),
    surface2: Color(0xFF2C2C2E), surface3: Color(0xFF38383A),
    line: Color(0xFF38383A), line2: Color(0xFF2C2C2E),
    dim: Color(0xFF636366), subtext: Color(0xFF8E8E93),
    text3: Color(0xFF8E8E93), text2: Color(0xFFD1D1D6), text1: Color(0xFFEEEEEE),
  );
  static _RP of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? dark : light;
}

const Color _kPurple = Color(0xFFAF52DE);
const Color _kLegend = Color(0xFFFFD700);

// =============================================================================
//  SCREEN
// =============================================================================
class RutasExploradorScreen extends StatefulWidget {
  final Color accent;
  const RutasExploradorScreen({required this.accent, super.key});

  @override
  State<RutasExploradorScreen> createState() => _RutasExploradorScreenState();
}

class _RutasExploradorScreenState extends State<RutasExploradorScreen>
    with SingleTickerProviderStateMixin {

  late final TabController _tabs = TabController(length: 4, vsync: this);
  _RP get _p => _RP.of(context);

  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Datos de cada tab
  List<RouteData> _populares  = [];
  List<RouteData> _nuevas     = [];
  List<RouteData> _amigos     = [];
  List<RouteData> _guardadas  = [];

  // IDs de rutas guardadas (para botón de corazón en listas)
  Set<String> _savedIds = {};

  // Estados de carga
  bool _loadingPopulares = true;
  bool _loadingNuevas    = true;
  bool _loadingAmigos    = true;
  bool _loadingGuardadas = true;

  // IDs de amigos (para query rutasDeAmigos)
  List<String> _friendIds = [];

  // Búsqueda
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChange);
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onTabChange() {
    if (!_tabs.indexIsChanging) return;
    // Carga lazy por tab
    switch (_tabs.index) {
      case 0: if (_loadingPopulares && _populares.isEmpty) _cargarPopulares(); break;
      case 1: if (_loadingNuevas    && _nuevas.isEmpty)    _cargarNuevas();    break;
      case 2: if (_loadingAmigos    && _amigos.isEmpty)    _cargarAmigos();    break;
      case 3: if (_loadingGuardadas && _guardadas.isEmpty) _cargarGuardadas(); break;
    }
  }

  Future<void> _init() async {
    await Future.wait([
      _cargarSavedIds(),
      _cargarFriendIds(),
      _cargarPopulares(),
    ]);
    _cargarNuevas();
  }

  Future<void> _cargarSavedIds() async {
    final ids = await RouteService.cargarIdsGuardadas(_uid);
    if (mounted) setState(() => _savedIds = ids);
  }

  Future<void> _cargarFriendIds() async {
    try {
      final sentSnap = await FirebaseFirestore.instance
          .collection('friendships')
          .where('senderId', isEqualTo: _uid)
          .where('status', isEqualTo: 'accepted')
          .get();
      final recvSnap = await FirebaseFirestore.instance
          .collection('friendships')
          .where('receiverId', isEqualTo: _uid)
          .where('status', isEqualTo: 'accepted')
          .get();
      final ids = <String>{};
      for (final d in sentSnap.docs) {
        final rid = d.data()['receiverId'] as String?;
        if (rid != null && rid != _uid) ids.add(rid);
      }
      for (final d in recvSnap.docs) {
        final sid = d.data()['senderId'] as String?;
        if (sid != null && sid != _uid) ids.add(sid);
      }
      if (mounted) setState(() => _friendIds = ids.toList());
    } catch (_) {}
  }

  Future<void> _cargarPopulares() async {
    if (!mounted) return;
    setState(() => _loadingPopulares = true);
    final list = await RouteService.rutasPopulares();
    if (mounted) setState(() { _populares = list; _loadingPopulares = false; });
  }

  Future<void> _cargarNuevas() async {
    if (!mounted) return;
    setState(() => _loadingNuevas = true);
    final list = await RouteService.rutasNuevas();
    if (mounted) setState(() { _nuevas = list; _loadingNuevas = false; });
  }

  Future<void> _cargarAmigos() async {
    if (!mounted) return;
    setState(() => _loadingAmigos = true);
    final list = await RouteService.rutasDeAmigos(_friendIds);
    if (mounted) setState(() { _amigos = list; _loadingAmigos = false; });
  }

  Future<void> _cargarGuardadas() async {
    if (!mounted) return;
    setState(() => _loadingGuardadas = true);
    final list = await RouteService.rutasGuardadas(_uid);
    if (mounted) setState(() { _guardadas = list; _loadingGuardadas = false; });
  }

  List<RouteData> _filtrar(List<RouteData> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((r) {
      final nombre  = (r.nombre ?? '').toLowerCase();
      final creador = r.ownerNickname.toLowerCase();
      return nombre.contains(q) || creador.contains(q);
    }).toList();
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
        style: TextStyle(color: _p.text1, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Buscar rutas o creador...',
          hintStyle: TextStyle(color: _p.dim, fontSize: 15),
          prefixIcon: Icon(Icons.search_rounded, color: _p.dim, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () => setState(() {
                    _searchCtrl.clear();
                    _searchQuery = '';
                  }),
                  child: Icon(Icons.cancel_rounded, color: _p.dim, size: 18))
              : null,
          filled: true,
          fillColor: _p.surface2,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _kPurple.withValues(alpha: 0.5), width: 1)),
        ),
      ),
    );
  }

  Future<void> _toggleGuardar(RouteData ruta) async {
    final estaba = _savedIds.contains(ruta.id);
    // Optimistic update
    setState(() {
      if (estaba) _savedIds.remove(ruta.id);
      else        _savedIds.add(ruta.id);
    });
    if (estaba) {
      await RouteService.quitarFavorita(_uid, ruta.id);
      if (mounted) setState(() => _guardadas.removeWhere((r) => r.id == ruta.id));
    } else {
      await RouteService.marcarFavorita(_uid, ruta.id);
      if (mounted) setState(() { if (!_guardadas.any((r) => r.id == ruta.id)) _guardadas.insert(0, ruta); });
    }
  }

  void _abrirDetalle(RouteData ruta) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteDetailSheet(
        ruta: ruta,
        guardada: _savedIds.contains(ruta.id),
        accent: widget.accent,
        onToggleGuardar: () => _toggleGuardar(ruta),
        onCorrer: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => LiveActivityScreen(rutaGuiada: ruta),
          ));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      backgroundColor: _p.bg,
      appBar: AppBar(
        backgroundColor: _p.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: _p.text1, size: 18),
          onPressed: () => Navigator.pop(ctx),
        ),
        title: Text('Explorar Rutas',
          style: TextStyle(color: _p.text1, fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabs,
          labelColor: _kPurple,
          unselectedLabelColor: _p.subtext,
          indicatorColor: _kPurple,
          indicatorWeight: 2,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.2),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
          tabs: const [
            Tab(text: 'POPULAR'),
            Tab(text: 'NUEVAS'),
            Tab(text: 'AMIGOS'),
            Tab(text: 'GUARDADAS'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: TabBarView(
            controller: _tabs,
            children: [
              _buildTab(_populares, _loadingPopulares, _cargarPopulares,
                emptyIcon: Icons.local_fire_department_rounded,
                emptyTitle: 'Sin rutas populares aún',
                emptySubtitulo: 'Las rutas más corridas aparecerán aquí'),
              _buildTab(_nuevas, _loadingNuevas, _cargarNuevas,
                emptyIcon: Icons.fiber_new_rounded,
                emptyTitle: 'Sin rutas nuevas',
                emptySubtitulo: 'Las últimas rutas publicadas aparecerán aquí'),
              _buildTab(_amigos, _loadingAmigos, _cargarAmigos,
                emptyIcon: Icons.group_rounded,
                emptyTitle: 'Tus amigos no han publicado rutas',
                emptySubtitulo: 'Añade amigos para ver sus recorridos'),
              _buildTab(_guardadas, _loadingGuardadas, _cargarGuardadas,
                emptyIcon: Icons.bookmark_outline_rounded,
                emptyTitle: 'No tienes rutas guardadas',
                emptySubtitulo: 'Guarda rutas de otros exploradores\npara correrlas después'),
            ],
          )),
        ],
      ),
    );
  }

  Widget _buildTab(
    List<RouteData> list,
    bool loading,
    Future<void> Function() onRefresh, {
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptySubtitulo,
  }) {
    if (loading && list.isEmpty) return _buildSkels();
    final filtered = _filtrar(list);
    if (filtered.isEmpty) {
      if (_searchQuery.isNotEmpty) {
        return _buildEmpty(Icons.search_off_rounded,
          'Sin resultados',
          'No hay rutas que coincidan con "$_searchQuery"');
      }
      return _buildEmpty(emptyIcon, emptyTitle, emptySubtitulo);
    }
    return RefreshIndicator(
      color: _kPurple,
      backgroundColor: _p.surface2,
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: filtered.length,
        itemBuilder: (ctx, i) => _RouteCard(
          ruta: filtered[i],
          guardada: _savedIds.contains(filtered[i].id),
          accent: widget.accent,
          p: _p,
          onTap: () => _abrirDetalle(filtered[i]),
          onToggleGuardar: () => _toggleGuardar(filtered[i]),
          onTapCreador: filtered[i].userId == _uid ? null : () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => PerfilScreen(targetUserId: filtered[i].userId))),
        ),
      ),
    );
  }

  Widget _buildSkels() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), itemCount: 6,
    itemBuilder: (_, __) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 100,
      decoration: BoxDecoration(
        color: _p.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _p.line2)),
    ));

  Widget _buildEmpty(IconData icon, String title, String sub) => Center(
    child: Padding(padding: const EdgeInsets.all(40), child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _p.dim, size: 44),
        const SizedBox(height: 16),
        Text(title, style: TextStyle(color: _p.text2, fontWeight: FontWeight.w700, fontSize: 15),
          textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(sub, style: TextStyle(color: _p.subtext, fontSize: 13),
          textAlign: TextAlign.center),
      ],
    )));
}

// =============================================================================
//  ROUTE CARD
// =============================================================================
class _RouteCard extends StatelessWidget {
  final RouteData  ruta;
  final bool       guardada;
  final Color      accent;
  final _RP        p;
  final VoidCallback  onTap;
  final VoidCallback  onToggleGuardar;
  final VoidCallback? onTapCreador;

  const _RouteCard({
    required this.ruta, required this.guardada, required this.accent,
    required this.p, required this.onTap, required this.onToggleGuardar,
    this.onTapCreador,
  });

  @override
  Widget build(BuildContext ctx) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border.all(color: ruta.esLegendaria
            ? _kLegend.withValues(alpha: 0.25) : p.line2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(children: [
          // Barra lateral de color
          Positioned(left: 0, top: 0, bottom: 0,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: ruta.esLegendaria ? _kLegend : _kPurple,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
              ))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(children: [
              // Mini sketch de la ruta
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 76, height: 76,
                  color: p.surface2,
                  child: ruta.coords.length >= 2
                    ? CustomPaint(
                        painter: _RoutePainter(
                          coords: ruta.coords,
                          color: ruta.esLegendaria ? _kLegend : _kPurple,
                          strokeWidth: 2.0))
                    : Icon(Icons.route_rounded, color: p.dim, size: 32),
                )),
              const SizedBox(width: 12),
              // Info
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nombre + badge legendaria
                  Row(children: [
                    if (ruta.esLegendaria) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kLegend.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4)),
                        child: const Text('LEGENDARIA',
                          style: TextStyle(color: _kLegend, fontSize: 8,
                            fontWeight: FontWeight.w800, letterSpacing: 1))),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        ruta.nombre ?? 'Ruta sin nombre',
                        style: TextStyle(color: p.text1, fontWeight: FontWeight.w700,
                          fontSize: 14),
                        overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 3),
                  // Creador
                  GestureDetector(
                    onTap: onTapCreador,
                    child: Text('por ${ruta.ownerNickname}',
                      style: TextStyle(color: p.subtext, fontSize: 11))),
                  const SizedBox(height: 8),
                  // Stats
                  Row(children: [
                    _StatChip(icon: Icons.straighten_rounded, label: ruta.distanciaStr, p: p),
                    const SizedBox(width: 8),
                    _StatChip(icon: Icons.timer_outlined, label: ruta.tiempoStr, p: p),
                    const SizedBox(width: 8),
                    _StatChip(icon: Icons.speed_rounded, label: ruta.ritmoStr, p: p),
                  ]),
                  const SizedBox(height: 6),
                  // Footer: runners + saves
                  Row(children: [
                    Icon(Icons.directions_run_rounded, color: p.dim, size: 11),
                    const SizedBox(width: 3),
                    Text('${ruta.runsCount}',
                      style: TextStyle(color: p.dim, fontSize: 10)),
                    const SizedBox(width: 10),
                    Icon(Icons.bookmark_rounded, color: p.dim, size: 11),
                    const SizedBox(width: 3),
                    Text('${ruta.savesCount}',
                      style: TextStyle(color: p.dim, fontSize: 10)),
                    const Spacer(),
                    Text(_fechaRelativa(ruta.fecha),
                      style: TextStyle(color: p.dim, fontSize: 10)),
                  ]),
                ],
              )),
              // Botón guardar
              GestureDetector(
                onTap: onToggleGuardar,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    guardada ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                    color: guardada ? _kPurple : p.dim,
                    size: 20))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final _RP p;
  const _StatChip({required this.icon, required this.label, required this.p});

  @override
  Widget build(BuildContext ctx) => Row(children: [
    Icon(icon, color: p.subtext, size: 10),
    const SizedBox(width: 2),
    Text(label, style: TextStyle(color: p.text3, fontSize: 10, fontWeight: FontWeight.w600)),
  ]);
}

String _fechaRelativa(DateTime fecha) {
  final diff = DateTime.now().difference(fecha);
  if (diff.inDays == 0) return 'hoy';
  if (diff.inDays == 1) return 'ayer';
  if (diff.inDays < 7)  return 'hace ${diff.inDays}d';
  if (diff.inDays < 30) return 'hace ${diff.inDays ~/ 7}sem';
  return 'hace ${diff.inDays ~/ 30}mes';
}

// =============================================================================
//  ROUTE PAINTER (CustomPainter)
// =============================================================================
class _RoutePainter extends CustomPainter {
  final List<LatLng> coords;
  final Color        color;
  final double       strokeWidth;

  const _RoutePainter({
    required this.coords,
    required this.color,
    this.strokeWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (coords.length < 2) return;

    // Bounding box
    double minLat = coords.first.latitude,  maxLat = coords.first.latitude;
    double minLng = coords.first.longitude, maxLng = coords.first.longitude;
    for (final c in coords) {
      if (c.latitude  < minLat) minLat = c.latitude;
      if (c.latitude  > maxLat) maxLat = c.latitude;
      if (c.longitude < minLng) minLng = c.longitude;
      if (c.longitude > maxLng) maxLng = c.longitude;
    }

    final latSpan = maxLat - minLat;
    final lngSpan = maxLng - minLng;
    if (latSpan == 0 && lngSpan == 0) return;

    const pad = 8.0;
    final w = size.width  - pad * 2;
    final h = size.height - pad * 2;

    // Normalización manteniendo aspect ratio
    final scaleX = lngSpan == 0 ? 1.0 : w / lngSpan;
    final scaleY = latSpan == 0 ? 1.0 : h / latSpan;
    final scale  = math.min(scaleX, scaleY);
    final offsetX = (w - lngSpan * scale) / 2 + pad;
    final offsetY = (h - latSpan * scale) / 2 + pad;

    Offset toOffset(LatLng c) => Offset(
      (c.longitude - minLng) * scale + offsetX,
      (maxLat - c.latitude)  * scale + offsetY, // Y invertido
    );

    // Subsamplear si hay muchos puntos
    final step = coords.length > 200 ? (coords.length / 100).ceil() : 1;
    final pts = [
      for (var i = 0; i < coords.length; i += step) toOffset(coords[i]),
      toOffset(coords.last),
    ];

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final pt in pts.skip(1)) path.lineTo(pt.dx, pt.dy);
    canvas.drawPath(path, paint);

    // Punto de inicio (verde) y fin (rojo)
    canvas.drawCircle(pts.first, 3, Paint()..color = color);
    canvas.drawCircle(pts.last,  3, Paint()..color = Colors.redAccent);
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.coords != coords || old.color != color;
}

// =============================================================================
//  ROUTE DETAIL SHEET
// =============================================================================
class _RouteDetailSheet extends StatefulWidget {
  final RouteData    ruta;
  final bool         guardada;
  final Color        accent;
  final VoidCallback onToggleGuardar;
  final VoidCallback onCorrer;

  const _RouteDetailSheet({
    required this.ruta, required this.guardada, required this.accent,
    required this.onToggleGuardar, required this.onCorrer,
  });

  @override
  State<_RouteDetailSheet> createState() => _RouteDetailSheetState();
}

class _RouteDetailSheetState extends State<_RouteDetailSheet> {
  late bool _guardada = widget.guardada;
  _RP get _p => _RP.of(context);

  @override
  Widget build(BuildContext ctx) {
    final ruta = widget.ruta;
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: _p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36, height: 4,
            decoration: BoxDecoration(color: _p.dim, borderRadius: BorderRadius.circular(2))),
          Expanded(child: ListView(controller: ctrl, padding: EdgeInsets.zero, children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                if (ruta.esLegendaria)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kLegend.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5)),
                    child: const Text('LEGENDARIA',
                      style: TextStyle(color: _kLegend, fontSize: 9,
                        fontWeight: FontWeight.w800, letterSpacing: 1.2))),
                Expanded(
                  child: Text(
                    ruta.nombre ?? 'Ruta sin nombre',
                    style: TextStyle(color: _p.text1, fontWeight: FontWeight.w800,
                      fontSize: 20))),
                GestureDetector(
                  onTap: () {
                    setState(() => _guardada = !_guardada);
                    widget.onToggleGuardar();
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      _guardada ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                      key: ValueKey(_guardada),
                      color: _guardada ? _kPurple : _p.dim, size: 24))),
              ])),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('por ${ruta.ownerNickname}',
                style: TextStyle(color: _p.subtext, fontSize: 13))),
            // Mapa grande de la ruta
            if (ruta.coords.length >= 2)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                height: 220,
                decoration: BoxDecoration(
                  color: _p.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ruta.esLegendaria
                    ? _kLegend.withValues(alpha: 0.3) : _p.line2)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _MapaRuta(ruta: ruta))),
            // Stats
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(children: [
                _StatCard(label: 'DISTANCIA', value: ruta.distanciaStr,
                  icon: Icons.straighten_rounded, p: _p, accent: _kPurple),
                const SizedBox(width: 10),
                _StatCard(label: 'TIEMPO', value: ruta.tiempoStr,
                  icon: Icons.timer_outlined, p: _p, accent: _kPurple),
                const SizedBox(width: 10),
                _StatCard(label: 'RITMO', value: ruta.ritmoStr,
                  icon: Icons.speed_rounded, p: _p, accent: _kPurple),
                const SizedBox(width: 10),
                _StatCard(label: 'CORREDORES', value: '${ruta.runsCount}',
                  icon: Icons.directions_run_rounded, p: _p,
                  accent: ruta.esLegendaria ? _kLegend : _kPurple),
              ])),
            // Descripción
            if (ruta.descripcion != null && ruta.descripcion!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _p.surface,
                    border: Border.all(color: _p.line2),
                    borderRadius: BorderRadius.circular(10)),
                  child: Text(ruta.descripcion!,
                    style: TextStyle(color: _p.text2, fontSize: 13, height: 1.5)))),
            // Guardar + Correr
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              child: Column(children: [
                GestureDetector(
                  onTap: () {
                    setState(() => _guardada = !_guardada);
                    widget.onToggleGuardar();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: _guardada ? _kPurple.withValues(alpha: 0.1) : _p.surface,
                      border: Border.all(
                        color: _guardada ? _kPurple.withValues(alpha: 0.5) : _p.line2),
                      borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(
                        _guardada ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                        color: _guardada ? _kPurple : _p.text3, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        _guardada ? 'Guardada' : 'Guardar ruta',
                        style: TextStyle(
                          color: _guardada ? _kPurple : _p.text3,
                          fontWeight: FontWeight.w700, fontSize: 14)),
                    ]))),
                GestureDetector(
                  onTap: widget.onCorrer,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: _kPurple,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(
                        color: _kPurple.withValues(alpha: 0.35),
                        blurRadius: 12, offset: const Offset(0, 4))]),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('Correr esta ruta',
                        style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w800, fontSize: 16)),
                    ]))),
              ])),
          ])),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String   label, value;
  final IconData icon;
  final Color    accent;
  final _RP      p;
  const _StatCard({
    required this.label, required this.value, required this.icon,
    required this.accent, required this.p,
  });

  @override
  Widget build(BuildContext ctx) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.line2),
        borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Icon(icon, color: accent, size: 16),
        const SizedBox(height: 4),
        Text(value,
          style: TextStyle(color: p.text1, fontWeight: FontWeight.w800, fontSize: 13),
          textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(label,
          style: TextStyle(color: p.dim, fontSize: 8, letterSpacing: 0.8),
          textAlign: TextAlign.center),
      ]),
    ));
}

// =============================================================================
//  MAPA RUTA (flutter_map con OSM)
// =============================================================================
class _MapaRuta extends StatelessWidget {
  final RouteData ruta;
  const _MapaRuta({required this.ruta});

  @override
  Widget build(BuildContext ctx) {
    if (ruta.coords.length < 2) return const SizedBox.shrink();

    // Bounding box para el mapa
    double minLat = ruta.coords.first.latitude,  maxLat = ruta.coords.first.latitude;
    double minLng = ruta.coords.first.longitude, maxLng = ruta.coords.first.longitude;
    for (final c in ruta.coords) {
      if (c.latitude  < minLat) minLat = c.latitude;
      if (c.latitude  > maxLat) maxLat = c.latitude;
      if (c.longitude < minLng) minLng = c.longitude;
      if (c.longitude > maxLng) maxLng = c.longitude;
    }
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(minLat, minLng),
            LatLng(maxLat, maxLng)),
          padding: const EdgeInsets.all(32)),
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.riskrunner.app',
        ),
        PolylineLayer(polylines: [
          Polyline(
            points: ruta.coords,
            color: _kPurple,
            strokeWidth: 4,
            strokeCap: StrokeCap.round),
        ]),
        MarkerLayer(markers: [
          Marker(
            point: ruta.coords.first,
            width: 14, height: 14,
            child: Container(
              decoration: const BoxDecoration(
                color: _kPurple, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]))),
          Marker(
            point: ruta.coords.last,
            width: 14, height: 14,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.redAccent, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]))),
        ]),
      ],
    );
  }
}
