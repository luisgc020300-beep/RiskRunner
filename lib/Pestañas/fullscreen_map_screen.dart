import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/territory_service.dart';
import '../widgets/custom_navbar.dart';

// =============================================================================
// MAPBOX
// =============================================================================
const String _kMapboxToken = String.fromEnvironment('MAPBOX_TOKEN');
const String _kMapboxUrl =
    'https://api.mapbox.com/styles/v1/luiisgoomezz1/cmmdzh1aj00f501r68crag5gv'
    '/tiles/256/{z}/{x}/{y}@2x?access_token=$_kMapboxToken';

// =============================================================================
// PALETA
// =============================================================================
const _kBg      = Color(0xFF060606);
const _kSurface = Color(0xFF0C0C0C);
const _kBorder2 = Color(0xFF1F1F1F);
const _kRed     = Color(0xFFCC2222);
const _kWhite   = Color(0xFFEEEEEE);
const _kText    = Color(0xFFB0B0B0);
const _kSub     = Color(0xFF666666);
const _kDim     = Color(0xFF4A4A4A);
const _kSafe    = Color(0xFF4CAF50);
const _kWarn    = Color(0xFFFF9800);

TextStyle _raj(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    GoogleFonts.rajdhani(fontSize: size, fontWeight: weight, color: color,
        letterSpacing: spacing, height: height);

// =============================================================================
// MODELOS
// =============================================================================
class _UserGroup {
  final String ownerId, nickname;
  final int nivel;
  final bool esMio;
  final List<_TerDet> territorios;
  _UserGroup({required this.ownerId, required this.nickname,
      required this.nivel, required this.esMio, required this.territorios});
}

class _TerDet {
  final String docId;
  final double dist;
  final int? diasSinVisitar;
  final List<LatLng> puntos;
  _TerDet({required this.docId, required this.dist,
      this.diasSinVisitar, this.puntos = const []});
}

// =============================================================================
// PANTALLA
// =============================================================================
class FullscreenMapScreen extends StatefulWidget {
  final List<TerritoryData> territorios;
  final Color colorTerritorio;
  final LatLng? centroInicial;
  final List<LatLng> ruta;
  final bool mostrarRuta;

  const FullscreenMapScreen({
    super.key,
    this.territorios = const [],
    this.colorTerritorio = const Color(0xFFCC2222),
    this.centroInicial,
    this.ruta = const [],
    this.mostrarRuta = false,
  });

  @override
  State<FullscreenMapScreen> createState() => _FullscreenMapScreenState();
}

class _FullscreenMapScreenState extends State<FullscreenMapScreen>
    with SingleTickerProviderStateMixin {

  final MapController _mapController = MapController();
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  LatLng _centro = const LatLng(40.4167, -3.70325);
  List<TerritoryData> _territorios = [];
  bool _loadingTerritorios = true;

  Map<String, Map<String, dynamic>> _jugadoresEnVivo = {};
  StreamSubscription? _presenciaStream;
  StreamSubscription? _desafioStream;
  Map<String, dynamic>? _desafioActivo;

  List<_UserGroup> _grupos = [];
  bool _loadingCercanos = false;
  bool _panelExpanded = false;
  String? _userExpandido;
  final Map<String, List<_TerDet>> _detallesPorUser = {};

  bool _mapaExpandido = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _initData();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _presenciaStream?.cancel();
    _desafioStream?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    await _resolverCentro();
    await _cargarTerritorios();
    _escucharJugadores();
    _escucharDesafio();
  }

  Future<void> _resolverCentro() async {
    if (widget.centroInicial != null) {
      setState(() => _centro = widget.centroInicial!);
      return;
    }
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));
        if (mounted) setState(() => _centro = LatLng(pos.latitude, pos.longitude));
      }
    } catch (_) {}
  }

  Future<void> _cargarTerritorios() async {
    if (widget.territorios.isNotEmpty) {
      setState(() { _territorios = widget.territorios; _loadingTerritorios = false; });
      return;
    }
    if (mounted) setState(() => _loadingTerritorios = true);
    try {
      final lista = await TerritoryService.cargarTodosLosTerritorios();
      if (mounted) setState(() { _territorios = lista; _loadingTerritorios = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingTerritorios = false);
    }
  }

  void _escucharJugadores() {
    _presenciaStream = FirebaseFirestore.instance
        .collection('presencia_activa').snapshots().listen((snap) {
      if (!mounted) return;
      final nuevos = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        if (doc.id == _uid) continue;
        final d = doc.data();
        final ts = d['timestamp'] as Timestamp?;
        if (ts != null && DateTime.now().difference(ts.toDate()).inMinutes < 5)
          nuevos[doc.id] = d;
      }
      setState(() => _jugadoresEnVivo = nuevos);
    });
  }

  void _escucharDesafio() {
    if (_uid == null) return;
    _desafioStream = FirebaseFirestore.instance
        .collection('desafios').where('estado', isEqualTo: 'activo')
        .snapshots().listen((snap) {
      if (!mounted) return;
      try {
        final doc = snap.docs.firstWhere((d) {
          final data = d.data();
          return data['retadorId'] == _uid || data['retadoId'] == _uid;
        });
        setState(() => _desafioActivo = doc.data());
      } catch (_) {
        setState(() => _desafioActivo = null);
      }
    });
  }

  Future<void> _cargarCercanos() async {
    if (mounted) setState(() => _loadingCercanos = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('territories').get();
      final Map<String, _UserGroup> grupos = {};
      final myUid = _uid ?? '';

      for (final doc in snap.docs) {
        final data = doc.data();
        final rawPts = data['puntos'] as List<dynamic>?;
        if (rawPts == null || rawPts.isEmpty) continue;
        final pts = rawPts.map((p) {
          final m = p as Map<String, dynamic>;
          return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
        }).toList();
        final latC = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
        final lngC = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
        final dist = Geolocator.distanceBetween(_centro.latitude, _centro.longitude, latC, lngC);
        if (dist > 5000) continue;
        final ownerId = data['userId'] as String? ?? '';
        if (ownerId.isEmpty) continue;
        if (!grupos.containsKey(ownerId)) {
          String nick = ownerId == myUid ? 'YO' : ownerId;
          int nivel = 1;
          try {
            final pd = await FirebaseFirestore.instance.collection('players').doc(ownerId).get();
            if (pd.exists) { nick = pd.data()?['nickname'] ?? nick; nivel = pd.data()?['nivel'] ?? 1; }
          } catch (_) {}
          grupos[ownerId] = _UserGroup(ownerId: ownerId, nickname: nick,
              nivel: nivel, esMio: ownerId == myUid, territorios: []);
        }
        grupos[ownerId]!.territorios.add(_TerDet(docId: doc.id, dist: dist / 1000, puntos: pts));
      }

      final lista = grupos.values.toList()
        ..sort((a, b) { if (a.esMio) return -1; if (b.esMio) return 1; return a.nickname.compareTo(b.nickname); });
      if (mounted) setState(() { _grupos = lista; _loadingCercanos = false; _panelExpanded = true; });
    } catch (_) {
      if (mounted) setState(() => _loadingCercanos = false);
    }
  }

  Future<void> _cargarDetalles(String ownerId) async {
    if (_detallesPorUser.containsKey(ownerId)) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('territories').where('userId', isEqualTo: ownerId).get();
      final List<_TerDet> dets = [];
      for (final doc in snap.docs) {
        final data = doc.data();
        final rawPts = data['puntos'] as List<dynamic>?;
        List<LatLng> pts = [];
        double dist = 0;
        if (rawPts != null && rawPts.isNotEmpty) {
          pts = rawPts.map((p) { final m = p as Map<String, dynamic>; return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()); }).toList();
          final latC = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
          final lngC = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
          dist = Geolocator.distanceBetween(_centro.latitude, _centro.longitude, latC, lngC) / 1000;
        }
        final tsV = data['ultima_visita'] as Timestamp?;
        final dias = tsV == null ? 0 : DateTime.now().difference(tsV.toDate()).inDays;
        dets.add(_TerDet(docId: doc.id, dist: dist, diasSinVisitar: dias, puntos: pts));
      }
      if (mounted) setState(() => _detallesPorUser[ownerId] = dets);
    } catch (_) {}
  }

  void _mostrarDialogo(_TerDet det, String ownerNick) {
    final centro = det.puntos.isNotEmpty
        ? LatLng(det.puntos.map((p) => p.latitude).reduce((a, b) => a + b) / det.puntos.length,
                 det.puntos.map((p) => p.longitude).reduce((a, b) => a + b) / det.puntos.length)
        : _centro;
    String estado = 'ACTIVO'; Color cEstado = _kSafe;
    if (det.diasSinVisitar != null && det.diasSinVisitar! >= 10) { estado = 'CRÍTICO'; cEstado = _kRed; }
    else if (det.diasSinVisitar != null && det.diasSinVisitar! >= 5) { estado = 'DESGASTE'; cEstado = _kWarn; }

    showDialog(context: context, barrierColor: Colors.black.withOpacity(0.88),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: Container(
          decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kBorder2),
              boxShadow: [const BoxShadow(color: Colors.black54, blurRadius: 32)]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _kBorder2))),
              child: Row(children: [
                Container(width: 2, height: 16, color: _kRed),
                const SizedBox(width: 10),
                Text(ownerNick.toUpperCase(), style: _raj(14, FontWeight.w900, _kWhite, spacing: 1.5)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: _kSub, size: 18)),
              ]),
            ),
            if (det.puntos.isNotEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(height: 150, child: ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: FlutterMap(
                    options: MapOptions(initialCenter: centro, initialZoom: 15,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
                    children: [
                      TileLayer(urlTemplate: _kMapboxUrl,
                          userAgentPackageName: 'com.runner_risk.app', tileSize: 256),
                      PolygonLayer(polygons: [Polygon(points: det.puntos,
                          color: _kRed.withOpacity(0.2), borderColor: _kRed, borderStrokeWidth: 2)]),
                    ])))),
            Padding(padding: const EdgeInsets.all(16),
              child: Row(children: [
                _dStat('ESTADO', estado, cEstado),
                _dStat('SIN VISITAR', det.diasSinVisitar != null ? '${det.diasSinVisitar}d' : '--', _kDim),
                _dStat('DISTANCIA', '${det.dist.toStringAsFixed(1)} km', _kText),
              ])),
          ]),
        ),
      ));
  }

  Widget _dStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(l, style: _raj(8, FontWeight.w700, _kSub, spacing: 1.5)),
    const SizedBox(height: 4),
    Text(v, style: _raj(13, FontWeight.w900, c)),
  ]));

  // ==========================================================================
  // BUILD
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    final mios        = _territorios.where((t) => t.esMio).length;
    final deteriorados = _territorios.where((t) => t.esMio && t.estaDeterirado).length;
    final enPeligro   = _territorios.where((t) => t.esMio && t.esConquistableSinPasar).length;

    return Scaffold(
      backgroundColor: _kBg,
      body: Column(children: [
        _buildAppBar(mios, deteriorados, enPeligro),
        Expanded(flex: _mapaExpandido ? 10 : 5, child: _buildMapa()),
        if (!_mapaExpandido)
          Expanded(flex: 5, child: _buildPanel(mios, deteriorados, enPeligro)),
      ]),
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 2),
    );
  }

  Widget _buildAppBar(int mios, int det, int pel) => Container(
    color: _kBg,
    child: SafeArea(bottom: false, child: Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _kBorder2))),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('MAPA DE GUERRA', style: _raj(16, FontWeight.w900, _kWhite, spacing: 1.5)),
          Text('${_territorios.length} territorios · ${_jugadoresEnVivo.length} en vivo',
              style: _raj(9, FontWeight.w600, _kSub, spacing: 1)),
        ]),
        const Spacer(),
        if (det > 0) _chip('$det', Icons.warning_amber_rounded, _kWarn),
        if (pel > 0) ...[const SizedBox(width: 6), _chip('$pel', Icons.dangerous_rounded, _kRed)],
        const SizedBox(width: 8),
        _iconBtn(_mapaExpandido ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            () => setState(() => _mapaExpandido = !_mapaExpandido)),
        const SizedBox(width: 6),
        _iconBtn(Icons.refresh_rounded, _cargarTerritorios),
      ]),
    )),
  );

  Widget _chip(String v, IconData icon, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(color: c.withOpacity(0.08), border: Border.all(color: c.withOpacity(0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: c, size: 11), const SizedBox(width: 4),
      Text(v, style: _raj(10, FontWeight.w900, c)),
    ]));

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(onTap: onTap,
    child: Container(width: 36, height: 36,
      decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kBorder2)),
      child: Icon(icon, color: _kText, size: 18)));

  Widget _buildMapa() {
    final tieneRuta = widget.ruta.length > 1 && widget.mostrarRuta;
    return Stack(children: [
      FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: _centro, initialZoom: 14,
            minZoom: 3, maxZoom: 19,
            onMapReady: () {
              if (tieneRuta) {
                try { _mapController.fitCamera(CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(widget.ruta),
                    padding: const EdgeInsets.all(60))); } catch (_) {}
              }
            }),
        children: [
          TileLayer(urlTemplate: _kMapboxUrl,
              userAgentPackageName: 'com.runner_risk.app', tileSize: 256),
          if (_territorios.isNotEmpty)
            PolygonLayer(polygons: _territorios.map((t) => Polygon(
                points: t.puntos,
                color: t.color.withOpacity(t.opacidadRelleno),
                borderColor: t.color.withOpacity(t.opacidadBorde),
                borderStrokeWidth: t.estaDeterirado ? 1.5 : 2.5)).toList()),
          if (tieneRuta)
            PolylineLayer(polylines: [Polyline(points: widget.ruta, strokeWidth: 4, color: _kRed)]),
          MarkerLayer(markers: [
            Marker(point: _centro, width: 16, height: 16,
                child: Container(decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.white24, blurRadius: 8)]))),
          ]),
          if (_territorios.isNotEmpty)
            MarkerLayer(markers: _territorios.map((t) => Marker(
              point: t.centro, width: 80, height: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    border: Border.all(color: t.color, width: 1.2)),
                child: Text(t.esMio ? 'YO' : t.ownerNickname,
                    textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.color, fontSize: 8, fontWeight: FontWeight.bold))),
            )).toList()),
          if (_jugadoresEnVivo.isNotEmpty)
            MarkerLayer(markers: _jugadoresEnVivo.entries.map((e) {
              final d = e.value;
              final lat = (d['lat'] as num?)?.toDouble();
              final lng = (d['lng'] as num?)?.toDouble();
              final color = d['color'] != null ? Color(d['color'] as int) : _kRed;
              final nick = d['nickname'] as String? ?? '';
              if (lat == null || lng == null) return null;
              return Marker(point: LatLng(lat, lng), width: 40, height: 48,
                child: Column(children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(
                      color: color, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: color.withOpacity(0.7), blurRadius: 8, spreadRadius: 2)])),
                  const SizedBox(height: 2),
                  Text(nick, style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.w700)),
                ]));
            }).whereType<Marker>().toList()),
        ],
      ),
      if (_loadingTerritorios)
        Positioned.fill(child: Container(color: Colors.black45,
            child: const Center(child: CircularProgressIndicator(color: _kRed, strokeWidth: 2)))),
      Positioned(bottom: 12, left: 12,
        child: AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: _kBg.withOpacity(0.85), border: Border.all(color: _kBorder2)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(
                color: _kSafe.withOpacity(0.4 + 0.6 * _pulse.value), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('EN VIVO · ${_jugadoresEnVivo.length} activos',
                style: _raj(8, FontWeight.w700, _kText, spacing: 1.5)),
          ])))),
      Positioned(top: 12, right: 12,
        child: GestureDetector(onTap: () => _mapController.move(_centro, 14),
          child: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: _kBg.withOpacity(0.9), border: Border.all(color: _kBorder2)),
            child: const Icon(Icons.my_location_rounded, color: _kText, size: 16)))),
    ]);
  }

  Widget _buildPanel(int mios, int det, int pel) => Container(
    decoration: const BoxDecoration(color: _kBg,
        border: Border(top: BorderSide(color: _kBorder2))),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_desafioActivo != null) ...[
          _buildBannerDesafio(_desafioActivo!), const SizedBox(height: 12)],
        Row(children: [
          _statChip('$mios', 'ZONAS', Icons.flag_rounded, _kText),
          if (det > 0) ...[const SizedBox(width: 8),
            _statChip('$det', 'DESGASTE', Icons.warning_amber_rounded, _kWarn)],
          if (pel > 0) ...[const SizedBox(width: 8),
            _statChip('$pel', 'CRÍTICO', Icons.dangerous_rounded, _kRed)],
        ]),
        if (det > 0 || pel > 0) ...[const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: _kRed.withOpacity(0.05),
                border: Border(left: const BorderSide(color: _kRed, width: 2),
                    top: const BorderSide(color: _kBorder2), right: const BorderSide(color: _kBorder2),
                    bottom: const BorderSide(color: _kBorder2))),
            child: Row(children: [
              const Icon(Icons.shield_outlined, color: _kRed, size: 13),
              const SizedBox(width: 10),
              Expanded(child: Text(
                pel > 0
                    ? '⚔ Tienes $pel ${pel == 1 ? 'territorio' : 'territorios'} que cualquiera puede conquistar.'
                    : '⚠ $det ${det == 1 ? 'territorio debilitado' : 'territorios debilitados'}. Visítalos.',
                style: _raj(11, FontWeight.w600, _kRed))),
            ]))],
        const SizedBox(height: 10),
        _buildBotonCercanos(),
        if (_panelExpanded) _buildPanelCercanos(),
      ]),
    ),
  );

  Widget _statChip(String v, String l, IconData icon, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kBorder2)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: c, size: 12), const SizedBox(width: 6),
      Text('$v $l', style: _raj(10, FontWeight.w800, c, spacing: 1)),
    ]));

  Widget _buildBotonCercanos() => GestureDetector(
    onTap: () {
      if (_panelExpanded) setState(() { _panelExpanded = false; _userExpandido = null; });
      else _cargarCercanos();
    },
    child: Container(width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kBorder2)),
      child: Row(children: [
        AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) => Container(
            width: 6, height: 6, decoration: BoxDecoration(
            color: _kSafe.withOpacity(0.4 + 0.6 * _pulse.value), shape: BoxShape.circle))),
        const SizedBox(width: 10),
        _loadingCercanos
            ? const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(color: _kRed, strokeWidth: 1.5))
            : Text(_panelExpanded ? 'TERRITORIOS EN ZONA (5KM) ▲' : 'TERRITORIOS EN ZONA (5KM) ▼',
                style: _raj(10, FontWeight.w700, _kSub, spacing: 1.5)),
        const Spacer(),
        const Icon(Icons.people_alt_outlined, color: _kDim, size: 13),
      ])));

  Widget _buildPanelCercanos() {
    if (_grupos.isEmpty) return Container(margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kBorder2)),
        child: Text('No hay territorios en 5 km', style: _raj(12, FontWeight.w500, _kSub)));

    return Container(margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kBorder2)),
      child: Column(children: _grupos.asMap().entries.map((entry) {
        final idx = entry.key; final g = entry.value;
        final isExp = _userExpandido == g.ownerId;
        final dets = _detallesPorUser[g.ownerId];
        final isLast = idx == _grupos.length - 1;
        return Column(children: [
          InkWell(onTap: () async {
            if (isExp) setState(() => _userExpandido = null);
            else { setState(() => _userExpandido = g.ownerId); await _cargarDetalles(g.ownerId); }
          }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(
                  color: g.esMio ? _kRed : _kSub, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(g.esMio ? '${g.nickname.toUpperCase()} (TÚ)' : g.nickname.toUpperCase(),
                  style: _raj(12, FontWeight.w800, g.esMio ? _kWhite : _kText, spacing: 1.5))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(border: Border.all(color: _kBorder2)),
                child: Text('NIV.${g.nivel}', style: _raj(8, FontWeight.w900, g.esMio ? _kRed : _kSub))),
              const SizedBox(width: 8),
              Text('${g.territorios.length} 🏴', style: _raj(11, FontWeight.w600, _kDim)),
              const SizedBox(width: 6),
              Icon(isExp ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: _kDim, size: 18),
            ]))),
          if (isExp) Container(margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: _kBorder2)),
            child: dets == null
                ? const Center(child: Padding(padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(color: _kRed, strokeWidth: 1.5)))
                : dets.isEmpty ? Text('Sin territorios', style: _raj(12, FontWeight.w500, _kSub))
                : Column(children: dets.asMap().entries.map((e) =>
                    _terCard(e.key, e.value, g.esMio ? 'YO' : g.nickname)).toList())),
          if (!isLast) Divider(color: _kBorder2, height: 1),
        ]);
      }).toList()));
  }

  Widget _terCard(int i, _TerDet det, String nick) {
    String est = 'ACTIVO'; Color c = _kSafe;
    if (det.diasSinVisitar != null && det.diasSinVisitar! >= 10) { est = 'CRÍTICO'; c = _kRed; }
    else if (det.diasSinVisitar != null && det.diasSinVisitar! >= 5) { est = 'DESGASTE'; c = _kWarn; }
    return GestureDetector(onTap: () => _mostrarDialogo(det, nick),
      child: Container(margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: _kSurface, border: Border.all(color: _kBorder2)),
        child: Row(children: [
          const Icon(Icons.crop_square_rounded, color: _kRed, size: 12),
          const SizedBox(width: 8),
          Text('ZONA #${i + 1}', style: _raj(11, FontWeight.w800, _kRed, spacing: 0.5)),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              color: c.withOpacity(0.08),
              child: Text(est, style: _raj(8, FontWeight.w800, c, spacing: 1))),
          const Spacer(),
          Text('${det.dist.toStringAsFixed(1)} km', style: _raj(10, FontWeight.w600, _kSub)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: _kRed.withOpacity(0.5), size: 13),
        ])));
  }

  Widget _buildBannerDesafio(Map<String, dynamic> data) {
    final bool soyR = data['retadorId'] == _uid;
    final String rival = soyR ? (data['retadoNick'] ?? 'Rival') : (data['retadorNick'] ?? 'Rival');
    final int misPts = soyR ? (data['puntosRetador'] as num? ?? 0).toInt() : (data['puntosRetado'] as num? ?? 0).toInt();
    final int rivalPts = soyR ? (data['puntosRetado'] as num? ?? 0).toInt() : (data['puntosRetador'] as num? ?? 0).toInt();
    final int apuesta = (data['apuesta'] as num? ?? 0).toInt();
    final Timestamp? finTs = data['fin'] as Timestamp?;
    final bool ganando = misPts >= rivalPts;
    String tiempo = '';
    if (finTs != null) {
      final diff = finTs.toDate().difference(DateTime.now());
      tiempo = diff.isNegative ? 'FINALIZADO' : diff.inHours > 0 ? '${diff.inHours}h ${diff.inMinutes.remainder(60)}m' : '${diff.inMinutes}m';
    }
    final int total = misPts + rivalPts;
    final double pct = total > 0 ? misPts / total : 0.5;

    return Container(decoration: BoxDecoration(color: _kSurface,
        border: Border(left: const BorderSide(color: _kRed, width: 2),
            top: const BorderSide(color: _kBorder2), right: const BorderSide(color: _kBorder2),
            bottom: const BorderSide(color: _kBorder2))),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Row(children: [
            const Text('⚔️', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            Text('DESAFÍO ACTIVO', style: _raj(9, FontWeight.w900, _kRed, spacing: 2)),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(border: Border.all(color: _kBorder2)),
                child: Text(tiempo, style: _raj(9, FontWeight.w700, _kText, spacing: 1))),
          ])),
        Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TÚ', style: _raj(7, FontWeight.w700, _kSub, spacing: 2)),
              Text('$misPts', style: _raj(22, FontWeight.w900, ganando ? _kWhite : _kSub, height: 1)),
            ])),
            Column(children: [
              Text('VS', style: _raj(10, FontWeight.w900, _kDim, spacing: 2)),
              Text('$apuesta 🪙', style: _raj(9, FontWeight.w700, _kText)),
            ]),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(rival.toString().toUpperCase(), style: _raj(7, FontWeight.w700, _kSub, spacing: 2)),
              Text('$rivalPts', style: _raj(22, FontWeight.w900, !ganando ? _kWhite : _kSub, height: 1)),
            ])),
          ])),
        Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Stack(children: [
            Container(height: 3, color: _kBorder2),
            FractionallySizedBox(widthFactor: pct.clamp(0.0, 1.0),
                child: Container(height: 3, color: _kRed)),
          ])),
      ]));
  }
}