import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:custom_timer/custom_timer.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../services/territory_service.dart';
import '../services/league_service.dart';
import '../services/anticheat_service.dart';
import '../services/stats_service.dart';
import '../widgets/conquista_overlay.dart';
import '../widgets/anticheat_warning_overlay.dart';

// =============================================================================
// PALETA ACUARELA — extraída del mapa
// =============================================================================
const _kInk         = Color(0xFF1E1408); // negro tinta oscura
const _kParchment   = Color(0xFF2A1F0F); // pergamino oscuro fondo
const _kParchMid    = Color(0xFF3D2E18); // superficie media
const _kGold        = Color(0xFFD4A84C); // dorado ocre (carreteras)
const _kGoldLight   = Color(0xFFEDD98A); // dorado claro
const _kGoldDim     = Color(0xFF7A5E28); // dorado apagado/borde
const _kTerracotta  = Color(0xFFD4722A); // naranja carretera
const _kWater       = Color(0xFF5BA3A0); // azul agua acuarela
const _kWaterLight  = Color(0xFF8ECFCC); // agua clara
const _kVerde       = Color(0xFF8FAF4A); // vegetación
const _kBorderWarm  = Color(0xFF4A3520); // borde cálido

// =============================================================================
// CONSTANTES GPS / CÁMARA (sin tocar)
// =============================================================================
const double _kPitchCorrer = 50.0;
const double _kPitchNormal = 0.0;
const double _kZoomCorrer  = 18.5;
const double _kZoomNormal  = 15.0;
const double _kZoomPausado = 16.5;
const double _kZoomGlobo   = 2.5;

const String _kEstiloPersonalizado =
    'mapbox://styles/luiisgoomezz1/cmmdzh1aj00f501r68crag5gv';

const _kGpsMovimiento = LocationSettings(
  accuracy: LocationAccuracy.bestForNavigation,
  distanceFilter: 8,
);
const _kGpsPausado = LocationSettings(
  accuracy: LocationAccuracy.reduced,
  distanceFilter: 20,
  timeLimit: Duration(seconds: 30),
);

const _kPresenciaMovimientoSeg = 10;
const _kPresenciaPausadoSeg    = 30;
final Map<int, Uint8List> _avatarCache = {};

// =============================================================================
// WIDGET PRINCIPAL
// =============================================================================
class LiveActivityScreen extends StatefulWidget {
  final Function(double distancia, Duration tiempo, List<LatLng> ruta)? onFinish;
  const LiveActivityScreen({super.key, this.onFinish});

  @override
  State<LiveActivityScreen> createState() => _LiveActivityScreenState();
}

class _LiveActivityScreenState extends State<LiveActivityScreen>
    with TickerProviderStateMixin {

  // ── Timer ──────────────────────────────────────────────────────────────────
  late final CustomTimerController _timerController = CustomTimerController(
    vsync: this,
    begin: const Duration(),
    end: const Duration(hours: 24),
    initialState: CustomTimerState.reset,
    interval: CustomTimerInterval.milliseconds,
  );
  final Stopwatch _stopwatch = Stopwatch();

  // ── Mapbox ─────────────────────────────────────────────────────────────────
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _annotationManager;
  final Map<String, mapbox.PointAnnotation> _anotacionesJugadores = {};

  // ── GPS ────────────────────────────────────────────────────────────────────
  List<LatLng> routePoints       = [];
  bool isTracking                = false;
  bool isPaused                  = false;
  double _distanciaTotal         = 0.0;
  double _velocidadActualKmh     = 0.0;
  double _bearing                = 0.0;
  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;
  Position? _ultimaPosicionVelocidad;

  int _puntosDesdeUltimoUpdate   = 0;
  static const int _kActualizarMapaCadaN = 3;
  DateTime _ultimoMovCamara = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kMinMsCamara = 800;

  // ── Jugador ────────────────────────────────────────────────────────────────
  Color  _colorTerritorio      = _kTerracotta;
  List<TerritoryData> _territorios = [];
  bool   _territoriosCargados  = false;
  String _miNickname           = 'Alguien';
  bool   _boostXpActivo        = false;

  final Set<String> _territoriosNotificadosEnSesion = {};
  final Set<String> _territoriosVisitadosEnSesion   = {};

  StreamSubscription? _jugadoresStream;
  final Map<String, Map<String, dynamic>> _jugadoresActivos = {};

  Timer? _timerPublicarPosicion;
  int    _presenciaIntervaloSeg = _kPresenciaMovimientoSeg;

  // ── Anti-cheat ─────────────────────────────────────────────────────────────
  final AntiCheatService _antiCheat = AntiCheatService();
  bool _sesionInvalidadaPorCheat    = false;

  // ── Modo noche ─────────────────────────────────────────────────────────────
  late bool _modoNoche;
  bool _modoManual = false;

  // ── Animaciones ────────────────────────────────────────────────────────────
  late AnimationController _cuentaAtrasAnim;
  late Animation<double>   _cuentaAtrasScale;
  bool   _mostrandoCuentaAtras = false;
  int    _cuentaAtras          = 3;
  Timer? _timerCuentaAtras;

  late AnimationController _hudAnim;
  late Animation<double>   _hudFade;
  bool _hudMinimizado = false;

  late AnimationController _bounceAnim;
  late Animation<double>   _bounceOffset;

  late AnimationController _pulsoAnim;
  late Animation<double>   _pulso;

  // ── Mapa ───────────────────────────────────────────────────────────────────
  static const String _routeSourceId    = 'route-source';
  static const String _routeLayerId     = 'route-layer';
  static const String _buildingsLayerId = 'buildings-3d';
  bool _routeLayerCreated   = false;
  bool _buildings3dCreated  = false;

  // ==========================================================================
  // INIT / DISPOSE
  // ==========================================================================
  @override
  void initState() {
    super.initState();
    _modoNoche = _esHoraNoche();

    StatsService.mapboxToken =
        'pk.eyJ1IjoibHVpaXNnb29tZXp6MSIsImEiOiJjbW1keTI1bjkwN25qMm9zNzFlOXZkeG9wIn0.l186BxbIhi6-vAXtBjIzsw';

    _cuentaAtrasAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _cuentaAtrasScale = CurvedAnimation(
        parent: _cuentaAtrasAnim, curve: Curves.elasticOut);

    _hudAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _hudFade = CurvedAnimation(parent: _hudAnim, curve: Curves.easeOut);
    _hudAnim.forward();

    _bounceAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _bounceOffset = Tween<double>(begin: 0, end: -7).animate(
        CurvedAnimation(parent: _bounceAnim, curve: Curves.easeInOut));
    _bounceAnim.repeat(reverse: true);

    _pulsoAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _pulso = Tween<double>(begin: 0.2, end: 1.0).animate(
        CurvedAnimation(parent: _pulsoAnim, curve: Curves.easeInOut));

    _determinePosition();
    _cargarDatosIniciales();
    _escucharJugadoresActivos();
  }

  @override
  void dispose() {
    _timerController.dispose();
    _timerCuentaAtras?.cancel();
    _positionStream?.cancel();
    _jugadoresStream?.cancel();
    _timerPublicarPosicion?.cancel();
    _cuentaAtrasAnim.dispose();
    _hudAnim.dispose();
    _bounceAnim.dispose();
    _pulsoAnim.dispose();
    _limpiarPresenciaFirestore();
    super.dispose();
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================
  bool _esHoraNoche() { final h = DateTime.now().hour; return h >= 21 || h < 6; }

  void _toggleModoNoche() {
    setState(() { _modoManual = true; _modoNoche = !_modoNoche; });
    _mapboxMap?.loadStyleURI(_mapStyle);
    _buildings3dCreated = false;
    Future.delayed(const Duration(milliseconds: 800), () {
      _addBuildings3D(); _configurarAtmosfera(); _dibujarTerritoriosEnMapa();
    });
  }

  String get _mapStyle =>
      _modoNoche ? mapbox.MapboxStyles.DARK : _kEstiloPersonalizado;

  String get _ritmoStr {
    if (_velocidadActualKmh < 0.5 || !isTracking || isPaused) return '--:--';
    final mpk = 60.0 / _velocidadActualKmh;
    final min = mpk.floor();
    final seg = ((mpk - min) * 60).round();
    return "$min'${seg.toString().padLeft(2, '0')}\"";
  }

  double _calcularBearing(LatLng a, LatLng b) {
    final lat1 = a.latitude  * math.pi / 180;
    final lat2 = b.latitude  * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  String _colorToHex(Color c) =>
      '#${c.red.toRadixString(16).padLeft(2, '0')}'
      '${c.green.toRadixString(16).padLeft(2, '0')}'
      '${c.blue.toRadixString(16).padLeft(2, '0')}';

  String _encodeJson(dynamic obj) {
    if (obj is Map)    return '{${obj.entries.map((e) => '"${e.key}":${_encodeJson(e.value)}').join(',')}}';
    if (obj is List)   return '[${obj.map(_encodeJson).join(',')}]';
    if (obj is String) return '"$obj"';
    if (obj is bool)   return obj.toString();
    return obj.toString();
  }

  // ==========================================================================
  // CARGA INICIAL
  // ==========================================================================
  Future<void> _cargarDatosIniciales() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players').doc(user.uid).get();
      if (doc.exists) {
        _miNickname = doc.data()?['nickname'] ?? 'Alguien';
        final colorInt = (doc.data()?['territorio_color'] as num?)?.toInt();
        if (colorInt != null && mounted)
          setState(() => _colorTerritorio = Color(colorInt));
        final boost  = doc.data()?['boost_xp_activo'] as bool? ?? false;
        final expira = doc.data()?['boost_xp_expira'] as Timestamp?;
        if (boost && expira != null && expira.toDate().isAfter(DateTime.now()))
          if (mounted) setState(() => _boostXpActivo = true);
      }
      final lista = await TerritoryService.cargarTodosLosTerritorios();
      if (mounted) {
        setState(() { _territorios = lista; _territoriosCargados = true; });
        _dibujarTerritoriosEnMapa();
      }
    } catch (e) { debugPrint('Error datos iniciales: $e'); }
  }

  Future<void> _determinePosition() async {
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.always || p == LocationPermission.whileInUse) {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) setState(() => _currentPosition = pos);
    }
  }

  // ==========================================================================
  // MAPBOX — sin tocar lógica ni mapa
  // ==========================================================================
  void _onMapCreated(mapbox.MapboxMap map) async {
    _mapboxMap = map;
    await map.style.setProjection(
        mapbox.StyleProjection(name: mapbox.StyleProjectionName.globe));
    await map.gestures.updateSettings(
        mapbox.GesturesSettings(rotateEnabled: true, pitchEnabled: false));
    _annotationManager = await map.annotations.createPointAnnotationManager();
    await _moverCamara(
      lat: _currentPosition?.latitude  ?? 40.4167,
      lng: _currentPosition?.longitude ?? -3.70325,
      zoom: _kZoomGlobo, bearing: 0, pitch: _kPitchNormal, animated: false,
    );
    await Future.delayed(const Duration(milliseconds: 500));
    await _addBuildings3D();
    await _configurarAtmosfera();
    await _dibujarTerritoriosEnMapa();
  }

  Future<void> _moverCamara({
    required double lat, required double lng,
    double? zoom, double? bearing, double? pitch,
    bool animated = true, int duracion = 600, bool forzar = false,
  }) async {
    if (_mapboxMap == null) return;
    if (!forzar && animated) {
      final ahora  = DateTime.now();
      final msDiff = ahora.difference(_ultimoMovCamara).inMilliseconds;
      if (msDiff < _kMinMsCamara) return;
      _ultimoMovCamara = ahora;
    }
    final cam = mapbox.CameraOptions(
      center: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
      zoom: zoom, bearing: bearing, pitch: pitch,
    );
    if (animated) {
      await _mapboxMap!.flyTo(cam, mapbox.MapAnimationOptions(duration: duracion));
    } else {
      await _mapboxMap!.setCamera(cam);
    }
  }

  Future<void> _configurarAtmosfera() async {
    if (_mapboxMap == null) return;
    try {
      final layers = await _mapboxMap!.style.getStyleLayers();
      if (!layers.any((l) => l?.id == 'sky-layer'))
        await _mapboxMap!.style.addLayer(mapbox.SkyLayer(id: 'sky-layer'));
      if (_modoNoche) {
        await _mapboxMap!.style.setStyleLayerProperty('sky-layer', 'sky-type', 'atmosphere');
        await _mapboxMap!.style.setStyleLayerProperty('sky-layer', 'sky-atmosphere-color', 'rgba(2,2,15,1)');
        await _mapboxMap!.style.setStyleLayerProperty('sky-layer', 'sky-atmosphere-halo-color', 'rgba(5,5,30,0.8)');
        await _mapboxMap!.style.setStyleLayerProperty('sky-layer', 'sky-atmosphere-sun-intensity', 0.0);
        await _mapboxMap!.style.setStyleLayerProperty('sky-layer', 'sky-opacity', 1.0);
      } else {
        await _mapboxMap!.style.setStyleLayerProperty('sky-layer', 'sky-type', 'atmosphere');
        await _mapboxMap!.style.setStyleLayerProperty('sky-layer', 'sky-atmosphere-color', 'rgba(135,206,250,1)');
        await _mapboxMap!.style.setStyleLayerProperty('sky-layer', 'sky-atmosphere-halo-color', 'rgba(200,230,255,0.9)');
        await _mapboxMap!.style.setStyleLayerProperty('sky-layer', 'sky-atmosphere-sun-intensity', 15.0);
        await _mapboxMap!.style.setStyleLayerProperty('sky-layer', 'sky-opacity', 1.0);
      }
    } catch (e) { debugPrint('Error atmosfera: $e'); }
  }

  Future<void> _addBuildings3D() async {
    if (_mapboxMap == null || _buildings3dCreated) return;
    try {
      try { await _mapboxMap!.style.removeStyleLayer(_buildingsLayerId); } catch (_) {}
      await _mapboxMap!.style.addLayer(mapbox.FillExtrusionLayer(
          id: _buildingsLayerId, sourceId: 'composite', sourceLayer: 'building'));
      await _mapboxMap!.style.setStyleLayerProperty(_buildingsLayerId, 'filter', ['==', ['get', 'extrude'], 'true']);
      await _mapboxMap!.style.setStyleLayerProperty(_buildingsLayerId, 'fill-extrusion-base',
          ['interpolate', ['linear'], ['zoom'], 15, 0, 15.05, ['get', 'min_height']]);
      await _mapboxMap!.style.setStyleLayerProperty(_buildingsLayerId, 'fill-extrusion-height',
          ['interpolate', ['linear'], ['zoom'], 15, 0, 15.05, ['get', 'height']]);
      await _mapboxMap!.style.setStyleLayerProperty(_buildingsLayerId, 'fill-extrusion-color', '#C8B89A');
      await _mapboxMap!.style.setStyleLayerProperty(_buildingsLayerId, 'fill-extrusion-opacity', 0.75);
      await _mapboxMap!.style.setStyleLayerProperty(_buildingsLayerId, 'fill-extrusion-ambient-occlusion-intensity', 0.3);
      await _mapboxMap!.style.setStyleLayerProperty(_buildingsLayerId, 'fill-extrusion-ambient-occlusion-radius', 3.0);
      _buildings3dCreated = true;
    } catch (e) { debugPrint('Error edificios 3D: $e'); }
  }

  Future<void> _dibujarTerritoriosEnMapa() async {
    if (_mapboxMap == null || _territorios.isEmpty) return;
    try {
      await _mapboxMap!.style.removeStyleLayer('territorios-fill');
      await _mapboxMap!.style.removeStyleLayer('territorios-border');
      await _mapboxMap!.style.removeStyleSource('territorios-source');
    } catch (_) {}
    final features = _territorios.map((t) {
      final coords = t.puntos.map((p) => [p.longitude, p.latitude]).toList();
      coords.add(coords.first);
      return _encodeJson({
        'type': 'Feature',
        'properties': {'color': _colorToHex(t.color), 'opacity': t.esMio ? 0.35 : 0.25},
        'geometry': {'type': 'Polygon', 'coordinates': [coords]},
      });
    }).join(',');
    try {
      final geojson = '{"type":"FeatureCollection","features":[$features]}';
      await _mapboxMap!.style.addSource(mapbox.GeoJsonSource(id: 'territorios-source', data: geojson));
      await _mapboxMap!.style.addLayer(mapbox.FillLayer(id: 'territorios-fill', sourceId: 'territorios-source'));
      await _mapboxMap!.style.setStyleLayerProperty('territorios-fill', 'fill-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty('territorios-fill', 'fill-opacity', ['get', 'opacity']);
      await _mapboxMap!.style.addLayer(mapbox.LineLayer(id: 'territorios-border', sourceId: 'territorios-source'));
      await _mapboxMap!.style.setStyleLayerProperty('territorios-border', 'line-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty('territorios-border', 'line-width', 2.0);
      await _mapboxMap!.style.setStyleLayerProperty('territorios-border', 'line-opacity', 0.8);
    } catch (e) { debugPrint('Error territorios: $e'); }
  }

  Future<void> _actualizarRutaEnMapa() async {
    if (_mapboxMap == null || routePoints.length < 2) return;
    final coords  = routePoints.map((p) => [p.longitude, p.latitude]).toList();
    final geojson = _encodeJson({'type': 'Feature', 'geometry': {'type': 'LineString', 'coordinates': coords}});
    try {
      if (!_routeLayerCreated) {
        await _mapboxMap!.style.addSource(mapbox.GeoJsonSource(id: _routeSourceId, data: geojson));
        await _mapboxMap!.style.addLayer(mapbox.LineLayer(id: _routeLayerId, sourceId: _routeSourceId));
        await _mapboxMap!.style.setStyleLayerProperty(_routeLayerId, 'line-color', _colorToHex(_colorTerritorio));
        await _mapboxMap!.style.setStyleLayerProperty(_routeLayerId, 'line-width', 4.5);
        await _mapboxMap!.style.setStyleLayerProperty(_routeLayerId, 'line-opacity', 0.9);
        _routeLayerCreated = true;
      } else {
        final src = await _mapboxMap!.style.getSource(_routeSourceId) as mapbox.GeoJsonSource?;
        await src?.updateGeoJSON(geojson);
      }
    } catch (e) { debugPrint('Error ruta mapa: $e'); }
  }

  // ==========================================================================
  // JUGADORES ACTIVOS
  // ==========================================================================
  void _escucharJugadoresActivos() {
    _jugadoresStream = FirebaseFirestore.instance
        .collection('presencia_activa').snapshots().listen((snap) async {
      if (!mounted) return;
      final user   = FirebaseAuth.instance.currentUser;
      final nuevos = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        if (doc.id == user?.uid) continue;
        final d  = doc.data();
        final ts = d['timestamp'] as Timestamp?;
        if (ts != null && DateTime.now().difference(ts.toDate()).inMinutes < 5)
          nuevos[doc.id] = d;
      }
      setState(() => _jugadoresActivos..clear()..addAll(nuevos));
      _actualizarAvataresMapa(nuevos);
    });
  }

  void _actualizarAvataresMapa(Map<String, Map<String, dynamic>> jugadores) async {
    if (_annotationManager == null) return;
    final activos = jugadores.keys.toSet();
    for (final uid in _anotacionesJugadores.keys.where((k) => !activos.contains(k)).toList())
      _eliminarAvatarJugador(uid);
    for (final entry in jugadores.entries) {
      final uid   = entry.key;
      final data  = entry.value;
      final lat   = (data['lat'] as num?)?.toDouble();
      final lng   = (data['lng'] as num?)?.toDouble();
      final color = Color((data['color'] as num?)?.toInt() ?? _kWater.value);
      if (lat == null || lng == null) continue;
      final bytes = await _getAvatarBytes(color);
      if (_anotacionesJugadores.containsKey(uid)) {
        final ann = _anotacionesJugadores[uid]!;
        await _annotationManager?.update(ann
          ..geometry = mapbox.Point(coordinates: mapbox.Position(lng, lat))
          ..image = bytes);
      } else {
        _crearAvatarJugador(uid, lat, lng, bytes);
      }
    }
  }

  Future<Uint8List> _getAvatarBytes(Color color) async {
    final key = color.value;
    if (_avatarCache.containsKey(key)) return _avatarCache[key]!;
    final bytes = await _generarImagenAvatar(color);
    _avatarCache[key] = bytes;
    return bytes;
  }

  void _crearAvatarJugador(String uid, double lat, double lng, Uint8List bytes) async {
    if (_annotationManager == null) return;
    final ann = await _annotationManager!.create(mapbox.PointAnnotationOptions(
      geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
      image: bytes, iconSize: 1.0,
    ));
    _anotacionesJugadores[uid] = ann;
  }

  void _eliminarAvatarJugador(String uid) async {
    if (_anotacionesJugadores.containsKey(uid)) {
      await _annotationManager?.delete(_anotacionesJugadores[uid]!);
      _anotacionesJugadores.remove(uid);
    }
  }

  Future<Uint8List> _generarImagenAvatar(Color color) async {
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    const sz       = 48.0;
    canvas.drawCircle(Offset(sz / 2, sz / 2), sz / 2,
        Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(Offset(sz / 2, sz / 2), sz / 2 - 6,
        Paint()..color = _kParchment);
    canvas.drawCircle(Offset(sz / 2, sz / 2), sz / 2 - 6,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3);
    final pic      = recorder.endRecording();
    final img      = await pic.toImage(sz.toInt(), sz.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // ==========================================================================
  // PRESENCIA
  // ==========================================================================
  void _iniciarPublicacionPosicion() {
    _timerPublicarPosicion?.cancel();
    _presenciaIntervaloSeg = _kPresenciaMovimientoSeg;
    _timerPublicarPosicion = Timer.periodic(
        Duration(seconds: _presenciaIntervaloSeg), (_) => _publicarPosicion());
  }

  void _ajustarPresenciaPausado() {
    _timerPublicarPosicion?.cancel();
    _presenciaIntervaloSeg = _kPresenciaPausadoSeg;
    _timerPublicarPosicion = Timer.periodic(
        Duration(seconds: _presenciaIntervaloSeg), (_) => _publicarPosicion());
  }

  void _ajustarPresenciaMovimiento() {
    if (_presenciaIntervaloSeg == _kPresenciaMovimientoSeg) return;
    _timerPublicarPosicion?.cancel();
    _presenciaIntervaloSeg = _kPresenciaMovimientoSeg;
    _timerPublicarPosicion = Timer.periodic(
        Duration(seconds: _presenciaIntervaloSeg), (_) => _publicarPosicion());
  }

  Future<void> _publicarPosicion() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentPosition == null || !isTracking) return;
    try {
      await FirebaseFirestore.instance.collection('presencia_activa').doc(user.uid).set({
        'lat': _currentPosition!.latitude, 'lng': _currentPosition!.longitude,
        'color': _colorTerritorio.value, 'nickname': _miNickname,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) { debugPrint('Error presencia: $e'); }
  }

  Future<void> _limpiarPresenciaFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try { await FirebaseFirestore.instance.collection('presencia_activa').doc(user.uid).delete(); }
    catch (_) {}
  }

  // ==========================================================================
  // TRACKING
  // ==========================================================================
  void _iniciarCuentaAtras() {
    setState(() { _mostrandoCuentaAtras = true; _cuentaAtras = 3; });
    _cuentaAtrasAnim.forward(from: 0);
    _timerCuentaAtras = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _cuentaAtras--);
      _cuentaAtrasAnim.forward(from: 0);
      if (_cuentaAtras <= 0) {
        t.cancel();
        setState(() => _mostrandoCuentaAtras = false);
        _comenzarTracking();
      }
    });
  }

  void _comenzarTracking() async {
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied) return;
    }
    setState(() {
      isTracking = true; isPaused = false;
      _distanciaTotal = 0; _velocidadActualKmh = 0; _bearing = 0;
      routePoints.clear(); _puntosDesdeUltimoUpdate = 0;
      _territoriosNotificadosEnSesion.clear();
      _territoriosVisitadosEnSesion.clear();
      _hudMinimizado = true;
    });
    _antiCheat.resetear();
    _sesionInvalidadaPorCheat = false;
    _stopwatch.reset(); _stopwatch.start();
    _timerController.start();
    _iniciarPublicacionPosicion();
    await _mapboxMap?.gestures.updateSettings(
        mapbox.GesturesSettings(rotateEnabled: false, pitchEnabled: false));
    if (_currentPosition != null) {
      await _moverCamara(
        lat: _currentPosition!.latitude, lng: _currentPosition!.longitude,
        zoom: _kZoomCorrer, bearing: _bearing, pitch: _kPitchCorrer,
        duracion: 2800, forzar: true,
      );
    }
    _positionStream = Geolocator.getPositionStream(locationSettings: _kGpsMovimiento)
        .listen((Position pos) async {
      if (!isPaused && mounted) {
        final acResultado = _antiCheat.analizarPunto(pos);
        if (!acResultado.esValido) {
          if (_antiCheat.sesionCancelada && !_sesionInvalidadaPorCheat) {
            _sesionInvalidadaPorCheat = true;
            _positionStream?.cancel(); _timerPublicarPosicion?.cancel();
            _stopwatch.stop(); _timerController.pause();
            await AntiCheatWarningOverlay.mostrar(context,
                motivo: acResultado.detalle ?? 'Actividad sospechosa detectada');
            if (mounted) {
              setState(() { isTracking = false; isPaused = false;
                _hudMinimizado = false; routePoints.clear(); });
              await _limpiarPresenciaFirestore();
            }
          }
          return;
        }
        final newPt = LatLng(pos.latitude, pos.longitude);
        setState(() {
          if (routePoints.isNotEmpty) {
            final dist = Geolocator.distanceBetween(
              routePoints.last.latitude, routePoints.last.longitude,
              newPt.latitude, newPt.longitude);
            _distanciaTotal += dist / 1000;
            _bearing = _calcularBearing(routePoints.last, newPt);
            if (_ultimaPosicionVelocidad != null) {
              final dt = pos.timestamp.difference(_ultimaPosicionVelocidad!.timestamp)
                  .inMilliseconds / 3600000.0;
              if (dt > 0) {
                final vel = (dist / 1000) / dt;
                _velocidadActualKmh = (_velocidadActualKmh * 0.6 + vel * 0.4).clamp(0, 40);
              }
            }
          }
          routePoints.add(newPt); _currentPosition = pos;
          _ultimaPosicionVelocidad = pos; _puntosDesdeUltimoUpdate++;
        });
        _moverCamara(lat: pos.latitude, lng: pos.longitude,
            zoom: _kZoomCorrer, bearing: _bearing, pitch: _kPitchCorrer);
        if (_puntosDesdeUltimoUpdate >= _kActualizarMapaCadaN) {
          _puntosDesdeUltimoUpdate = 0; _actualizarRutaEnMapa();
        }
        _procesarPosicionEnTerritorios(newPt);
        if (!_modoManual) {
          final esNoche = _esHoraNoche();
          if (esNoche != _modoNoche) setState(() => _modoNoche = esNoche);
        }
      }
    }, onError: (e) => debugPrint('GPS error: $e'));
  }

  void togglePause() {
    setState(() {
      isPaused = !isPaused;
      _hudMinimizado = !isPaused;
      if (isPaused) {
        _timerController.pause(); _stopwatch.stop();
        _velocidadActualKmh = 0; _bounceAnim.stop();
        _positionStream?.cancel();
        _positionStream = Geolocator.getPositionStream(locationSettings: _kGpsPausado)
            .listen((pos) { if (mounted) setState(() => _currentPosition = pos); });
        _ajustarPresenciaPausado();
        if (_currentPosition != null) {
          _moverCamara(lat: _currentPosition!.latitude, lng: _currentPosition!.longitude,
              zoom: _kZoomPausado, pitch: _kPitchNormal, bearing: 0, forzar: true);
        }
        _hudAnim.forward();
      } else {
        _timerController.start(); _stopwatch.start();
        _bounceAnim.repeat(reverse: true);
        _positionStream?.cancel();
        _positionStream = Geolocator.getPositionStream(locationSettings: _kGpsMovimiento)
            .listen((Position pos) async {
          if (!isPaused && mounted) {
            final acResultado = _antiCheat.analizarPunto(pos);
            if (!acResultado.esValido) {
              if (_antiCheat.sesionCancelada && !_sesionInvalidadaPorCheat) {
                _sesionInvalidadaPorCheat = true;
                _positionStream?.cancel(); _timerPublicarPosicion?.cancel();
                _stopwatch.stop(); _timerController.pause();
                await AntiCheatWarningOverlay.mostrar(context,
                    motivo: acResultado.detalle ?? 'Actividad sospechosa detectada');
                if (mounted) {
                  setState(() { isTracking = false; isPaused = false;
                    _hudMinimizado = false; routePoints.clear(); });
                  await _limpiarPresenciaFirestore();
                }
              }
              return;
            }
            final newPt = LatLng(pos.latitude, pos.longitude);
            setState(() {
              if (routePoints.isNotEmpty) {
                final dist = Geolocator.distanceBetween(
                  routePoints.last.latitude, routePoints.last.longitude,
                  newPt.latitude, newPt.longitude);
                _distanciaTotal += dist / 1000;
                _bearing = _calcularBearing(routePoints.last, newPt);
              }
              routePoints.add(newPt); _currentPosition = pos;
              _ultimaPosicionVelocidad = pos; _puntosDesdeUltimoUpdate++;
            });
            _moverCamara(lat: pos.latitude, lng: pos.longitude,
                zoom: _kZoomCorrer, bearing: _bearing, pitch: _kPitchCorrer);
            if (_puntosDesdeUltimoUpdate >= _kActualizarMapaCadaN) {
              _puntosDesdeUltimoUpdate = 0; _actualizarRutaEnMapa();
            }
            _procesarPosicionEnTerritorios(newPt);
          }
        });
        _ajustarPresenciaMovimiento();
        if (_currentPosition != null) {
          _moverCamara(lat: _currentPosition!.latitude, lng: _currentPosition!.longitude,
              zoom: _kZoomCorrer, pitch: _kPitchCorrer, bearing: _bearing, forzar: true);
        }
      }
    });
  }

  Future<void> stopTracking() async {
    _stopwatch.stop(); _timerController.pause();
    _positionStream?.cancel(); _timerPublicarPosicion?.cancel();
    await _limpiarPresenciaFirestore();
    final tiempoFinal    = _stopwatch.elapsed;
    final rutaFinal      = List<LatLng>.from(routePoints);
    final distanciaFinal = _distanciaTotal;
    if (mounted) setState(() { isTracking = false; isPaused = false;
      _velocidadActualKmh = 0; _hudMinimizado = false; });
    await _mapboxMap?.gestures.updateSettings(
        mapbox.GesturesSettings(rotateEnabled: true, pitchEnabled: false));
    String? logId;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && distanciaFinal > 0) {
        final monedasBase    = (distanciaFinal * 10).round();
        final monedasFinales = _boostXpActivo ? monedasBase * 2 : monedasBase;
        await FirebaseFirestore.instance.collection('players').doc(user.uid)
            .update({'monedas': FieldValue.increment(monedasFinales)});
        if (_boostXpActivo && mounted) _mostrarSnackBoost(monedasFinales);
        final logRef = await FirebaseFirestore.instance.collection('activity_logs').add({
          'userId': user.uid, 'distancia': distanciaFinal,
          'tiempo_segundos': tiempoFinal.inSeconds, 'boost_activo': _boostXpActivo,
          'timestamp': FieldValue.serverTimestamp(), 'titulo': 'Carrera Libre',
          'fecha_dia': "${DateTime.now().year}-"
              "${DateTime.now().month.toString().padLeft(2, '0')}-"
              "${DateTime.now().day.toString().padLeft(2, '0')}",
        });
        logId = logRef.id;
        if (rutaFinal.isNotEmpty)
          unawaited(StatsService.enriquecerLog(logId: logId, ruta: rutaFinal));
      }
    } catch (e) { debugPrint('Error log: $e'); }
    if (distanciaFinal > 0 && !_sesionInvalidadaPorCheat) {
      final sesionCheck = AntiCheatService.analizarSesionCompleta(
          ruta: rutaFinal, tiempo: tiempoFinal, distanciaKm: distanciaFinal);
      if (!sesionCheck.esValida) {
        _sesionInvalidadaPorCheat = true;
        if (mounted) {
          await AntiCheatWarningOverlay.mostrar(context,
              motivo: sesionCheck.motivo ?? 'Sesión inválida');
          if (mounted) Navigator.of(context).pop();
        }
        return;
      }
    }
    final conquistados = await _procesarConquistas(rutaFinal, tiempoFinal, distanciaFinal);
    final puntosLigaGanados = (distanciaFinal > 0 ? 15 : 0) + (conquistados * 25);
    if (mounted && distanciaFinal > 0) {
      String? nombreRival;
      if (conquistados > 0) {
        final rivalT = _territorios.where((t) => !t.esMio)
            .cast<TerritoryData?>().firstWhere((_) => true, orElse: () => null);
        nombreRival = rivalT?.ownerNickname;
      }
      await ConquistaOverlay.mostrar(context,
          esInvasion: conquistados > 0, nombreTerritorio: nombreRival);
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/resumen', arguments: {
      'distancia': distanciaFinal, 'tiempo': tiempoFinal, 'ruta': rutaFinal,
      'esDesdeCarrera': true, 'territoriosConquistados': conquistados,
      'puntosLigaGanados': puntosLigaGanados,
    });
  }

  // ==========================================================================
  // TERRITORIOS LÓGICA
  // ==========================================================================
  void _procesarPosicionEnTerritorios(LatLng pos) {
    if (_territorios.isEmpty) return;
    final t = TerritoryService.territorioEnPosicion(_territorios, pos);
    if (t == null) return;
    if (t.esMio) {
      if (!_territoriosVisitadosEnSesion.contains(t.docId)) {
        _territoriosVisitadosEnSesion.add(t.docId);
        TerritoryService.actualizarUltimaVisita(t.docId);
        _mostrarSnackRefuerzo();
      }
    } else {
      if (!_territoriosNotificadosEnSesion.contains(t.docId)) {
        _territoriosNotificadosEnSesion.add(t.docId);
        TerritoryService.crearNotificacionInvasion(
            toUserId: t.ownerId, fromNickname: _miNickname, territoryId: t.docId);
        _mostrarSnackInvasion(t.ownerNickname);
      }
    }
  }

  Future<int> _procesarConquistas(
      List<LatLng> ruta, Duration tiempo, double distancia) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || ruta.isEmpty || _territorios.isEmpty) return 0;
    int conquistados = 0;
    for (final t in _territorios.where((t) => !t.esMio)) {
      final paso    = _rutaPasaPorPoligono(ruta, t.puntos);
      final cercano = t.esConquistableSinPasar &&
          _rutaPasaCercaDe(ruta, t.centro, radioMetros: 200);
      if (!paso && !cercano) continue;
      try {
        final ownerDoc = await FirebaseFirestore.instance
            .collection('players').doc(t.ownerId).get();
        if (ownerDoc.exists) {
          final escudo  = ownerDoc.data()?['escudo_activo'] as bool? ?? false;
          final expiraT = ownerDoc.data()?['escudo_expira'] as Timestamp?;
          if (escudo && expiraT != null && expiraT.toDate().isAfter(DateTime.now())) continue;
        }
      } catch (_) {}
      try {
        await FirebaseFirestore.instance.collection('territories').doc(t.docId)
            .update({'userId': user.uid, 'ultima_visita': FieldValue.serverTimestamp()});
        for (final notif in [
          {'toUserId': t.ownerId, 'type': 'territory_lost',
            'message': '😤 ¡$_miNickname te ha robado un territorio!',
            'fromNickname': _miNickname, 'territoryId': t.docId},
          {'toUserId': user.uid, 'type': 'territory_conquered',
            'message': '🏴 ¡Conquistado de ${t.ownerNickname}!',
            'fromNickname': t.ownerNickname, 'territoryId': t.docId,
            'distancia': distancia, 'tiempo_segundos': tiempo.inSeconds},
        ]) {
          await FirebaseFirestore.instance.collection('notifications')
              .add({...notif, 'read': false, 'timestamp': FieldValue.serverTimestamp()});
        }
        await LeagueService.sumarPuntosLiga(user.uid, 25);
        await LeagueService.sumarPuntosLiga(t.ownerId, -10);
        conquistados++;
      } catch (e) { debugPrint('Error conquistando: $e'); }
    }
    return conquistados;
  }

  bool _rutaPasaPorPoligono(List<LatLng> ruta, List<LatLng> pol) =>
      ruta.any((p) => _puntoEnPoligono(p, pol));

  bool _puntoEnPoligono(LatLng punto, List<LatLng> pol) {
    int n = pol.length, inter = 0;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = pol[i].longitude, yi = pol[i].latitude;
      final xj = pol[j].longitude, yj = pol[j].latitude;
      if (((yi > punto.latitude) != (yj > punto.latitude)) &&
          punto.longitude < (xj - xi) * (punto.latitude - yi) / (yj - yi) + xi) inter++;
    }
    return inter % 2 == 1;
  }

  bool _rutaPasaCercaDe(List<LatLng> ruta, LatLng obj, {required double radioMetros}) =>
      ruta.any((p) => Geolocator.distanceBetween(
          p.latitude, p.longitude, obj.latitude, obj.longitude) <= radioMetros);

  // ==========================================================================
  // SNACKS — tono cálido acuarela
  // ==========================================================================
  void _mostrarSnackInvasion(String nick) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      backgroundColor: Colors.transparent, elevation: 0,
      content: _snackWrap(
        gradient: const LinearGradient(colors: [Color(0xFF6B1500), Color(0xFFD4520A)]),
        shadow: _kTerracotta,
        child: Row(children: [
          const Text('⚔️', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text('¡Invadiendo el territorio de $nick!',
              style: const TextStyle(color: Color(0xFFFFE8C0),
                  fontWeight: FontWeight.bold, fontSize: 13))),
        ]),
      ),
    ));
  }

  void _mostrarSnackRefuerzo() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      backgroundColor: Colors.transparent, elevation: 0,
      content: _snackWrap(
        color: _kParchMid,
        border: Border.all(color: _kGold.withValues(alpha: 0.55)),
        child: Row(children: [
          const Text('🛡️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          const Text('¡Territorio reforzado!',
              style: TextStyle(color: _kGoldLight,
                  fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
      ),
    ));
  }

  void _mostrarSnackBoost(int monedas) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      backgroundColor: Colors.transparent, elevation: 0,
      content: _snackWrap(
        gradient: LinearGradient(colors: [_kGoldDim, _kGold]),
        shadow: _kGold,
        child: Row(children: [
          const Text('⚡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Text('¡Boost XP! +$monedas 🪙 (×2)',
              style: const TextStyle(color: _kInk,
                  fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
      ),
    ));
  }

  Widget _snackWrap({Widget? child, Gradient? gradient, Color? color,
    BoxBorder? border, Color shadow = Colors.transparent}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: gradient, color: color,
          borderRadius: BorderRadius.circular(14), border: border,
          boxShadow: [BoxShadow(color: shadow.withValues(alpha: 0.4), blurRadius: 12)],
        ),
        child: child,
      );

  // ==========================================================================
  // BUILD PRINCIPAL
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: _buildMapbox()),
        Positioned(top: 0, left: 0, right: 0, child: _buildHUD()),
        Positioned(top: 200, left: 14, child: _buildChips()),
        Positioned(top: 200, right: 14, child: _buildBotonesMapa()),
        if (isTracking && !isPaused) _buildAvatarOverlay(),
        if (isTracking)
          Align(
            alignment: isPaused
                ? const Alignment(0, -0.1)
                : const Alignment(0, -0.55),
            child: _buildTimerGrande(),
          ),
        if (_mostrandoCuentaAtras) _buildCuentaAtras(),
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBotonera()),
      ]),
    );
  }

  Widget _buildMapbox() => mapbox.MapWidget(
    styleUri: _mapStyle,
    cameraOptions: mapbox.CameraOptions(
      center: mapbox.Point(coordinates: mapbox.Position(
        _currentPosition?.longitude ?? -3.70325,
        _currentPosition?.latitude  ?? 40.4167,
      )),
      zoom: _kZoomGlobo, pitch: _kPitchNormal,
    ),
    onMapCreated: _onMapCreated,
  );

  // ── HUD — pergamino oscuro con borde dorado pulsante ─────────────
  Widget _buildHUD() {
    if (isTracking && _hudMinimizado && !isPaused) return _buildHUDMini();
    return FadeTransition(
      opacity: _hudFade,
      child: AnimatedBuilder(
        animation: _pulsoAnim,
        builder: (_, child) => Container(
          margin: const EdgeInsets.fromLTRB(14, 50, 14, 0),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
          decoration: BoxDecoration(
            color: _kParchment.withValues(alpha: 0.93),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _kGold.withValues(alpha: 0.18 + _pulso.value * 0.22),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _kGold.withValues(alpha: 0.10 + _pulso.value * 0.08),
                blurRadius: 20, spreadRadius: 1,
              ),
              BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 10),
            ],
          ),
          child: child,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _hudStat('KM', _distanciaTotal.toStringAsFixed(2), _kGold),
            _hudDivider(),
            _hudStat('MIN/KM', _ritmoStr, _kWaterLight),
            _hudDivider(),
            _buildStatTimer(),
            if (_boostXpActivo) ...[_hudDivider(), _hudStat('BOOST', '×2', _kGoldLight)],
          ],
        ),
      ),
    );
  }

  Widget _buildHUDMini() => Positioned(
    top: 50, left: 18, right: 18,
    child: GestureDetector(
      onTap: () => setState(() => _hudMinimizado = false),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
        decoration: BoxDecoration(
          color: _kParchment.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _kGoldDim.withValues(alpha: 0.45)),
          boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.10), blurRadius: 10)],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          Text(_distanciaTotal.toStringAsFixed(2),
              style: const TextStyle(color: _kGoldLight,
                  fontWeight: FontWeight.w900, fontSize: 15)),
          Text(' km', style: TextStyle(
              color: _kGold.withValues(alpha: 0.55), fontSize: 11)),
          Container(width: 1, height: 14, color: _kGoldDim.withValues(alpha: 0.4)),
          Text(_ritmoStr, style: const TextStyle(color: _kWaterLight,
              fontWeight: FontWeight.w900, fontSize: 15)),
          Text(' /km', style: TextStyle(
              color: _kWater.withValues(alpha: 0.55), fontSize: 11)),
          const Icon(Icons.expand_more_rounded, color: _kGoldDim, size: 15),
        ]),
      ),
    ),
  );

  Widget _hudStat(String label, String valor, Color color) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1.8)),
        const SizedBox(height: 4),
        Text(valor, style: TextStyle(
            color: Colors.white,
            fontSize: valor.length > 5 ? 16 : 20,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: color.withValues(alpha: 0.55), blurRadius: 10)])),
      ]);

  Widget _hudDivider() => Container(
      width: 1, height: 32,
      color: _kGoldDim.withValues(alpha: 0.35));

  Widget _buildStatTimer() => CustomTimer(
    controller: _timerController,
    builder: (state, remaining) {
      final str = isTracking
          ? "${remaining.hours}:${remaining.minutes}:${remaining.seconds}"
          : '--:--:--';
      return _hudStat('TIEMPO', str, isPaused ? _kGoldDim : _kWaterLight);
    },
  );

  // ── Timer grande — marrón oscuro borde dorado ─────────────────────
  Widget _buildTimerGrande() => IgnorePointer(
    child: CustomTimer(
      controller: _timerController,
      builder: (_, remaining) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: _kParchment.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kGoldDim.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(color: _kGold.withValues(alpha: 0.18), blurRadius: 24),
            BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 8),
          ],
        ),
        child: Text(
          "${remaining.hours}:${remaining.minutes}:${remaining.seconds}",
          style: const TextStyle(
            fontSize: 50, fontWeight: FontWeight.w900,
            color: Colors.white, letterSpacing: 2,
            shadows: [
              Shadow(blurRadius: 22, color: _kGold),
              Shadow(blurRadius: 45, color: Color(0x66D4722A)),
            ],
          ),
        ),
      ),
    ),
  );

  // ── Avatar con sombra cálida ──────────────────────────────────────
  Widget _buildAvatarOverlay() => Positioned(
    bottom: 140, left: 0, right: 0,
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: _bounceAnim,
        builder: (_, __) => Transform.translate(
          offset: Offset(0, _bounceOffset.value),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_velocidadActualKmh > 1)
              SizedBox(width: 100, height: 28,
                  child: CustomPaint(painter: _SpeedLinesPainter(color: _kTerracotta))),
            Image.asset('assets/avatars/explorador.png',
              width: 110, height: 110, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.directions_run_rounded, color: _kGold, size: 80)),
            Container(width: 52, height: 9,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                gradient: RadialGradient(
                    colors: [_kGold.withValues(alpha: 0.28), Colors.transparent]),
              )),
          ]),
        ),
      ),
    ),
  );

  // ── Chips — pergamino con borde del color de cada dato ────────────
  Widget _buildChips() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_territoriosCargados)
        _chip('${_territorios.length} territorios', _kGold, '🗺'),
      if (_jugadoresActivos.isNotEmpty) ...[
        const SizedBox(height: 8),
        _chip('${_jugadoresActivos.length} cerca', _kWater, '🏃'),
      ],
      if (isTracking && _territoriosVisitadosEnSesion.isNotEmpty) ...[
        const SizedBox(height: 8),
        _chip('${_territoriosVisitadosEnSesion.length} reforzados', _kVerde, '🛡'),
      ],
      if (isTracking && _territoriosNotificadosEnSesion.isNotEmpty) ...[
        const SizedBox(height: 8),
        _chip('${_territoriosNotificadosEnSesion.length} invadidos', _kTerracotta, '⚔'),
      ],
    ],
  );

  Widget _chip(String texto, Color color, String emoji) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: _kParchment.withValues(alpha: 0.90),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 8)],
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 11)),
      const SizedBox(width: 5),
      Text(texto, style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    ]),
  );

  // ── Botones mapa — circulares pergamino ───────────────────────────
  Widget _buildBotonesMapa() => Column(children: [
    _botonMapa(_modoNoche ? '🌙' : '☀️', _modoNoche ? _kGoldLight : _kGold, _toggleModoNoche),
    if (isTracking) ...[
      const SizedBox(height: 10),
      _botonMapa('🎯', _kTerracotta, () {
        if (_currentPosition != null) {
          _moverCamara(
            lat: _currentPosition!.latitude, lng: _currentPosition!.longitude,
            zoom: _kZoomCorrer, pitch: _kPitchCorrer, bearing: _bearing, forzar: true,
          );
        }
      }),
    ],
  ]);

  Widget _botonMapa(String emoji, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _kParchment.withValues(alpha: 0.90),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 10),
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4),
            ],
          ),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 19))),
        ),
      );

  // ── Cuenta atrás — pergamino dramático con glow dorado ────────────
  Widget _buildCuentaAtras() => Positioned.fill(
    child: IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center, radius: 0.85,
            colors: [
              _kParchment.withValues(alpha: 0.65),
              Colors.black.withValues(alpha: 0.60),
            ],
          ),
        ),
        child: Center(
          child: ScaleTransition(
            scale: _cuentaAtrasScale,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                _cuentaAtras > 0 ? '$_cuentaAtras' : '⚔️',
                style: const TextStyle(
                  fontSize: 92, fontWeight: FontWeight.w900,
                  color: Colors.white,
                  shadows: [
                    Shadow(blurRadius: 35, color: _kGold),
                    Shadow(blurRadius: 70, color: _kTerracotta),
                    Shadow(blurRadius: 6, color: Colors.black),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                decoration: BoxDecoration(
                  color: _kParchment.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kGoldDim),
                  boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.2), blurRadius: 14)],
                ),
                child: Text(
                  _cuentaAtras > 0 ? 'PREPÁRATE' : '¡A CONQUISTAR!',
                  style: const TextStyle(
                      color: _kGoldLight, fontSize: 13,
                      fontWeight: FontWeight.w800, letterSpacing: 3.5),
                ),
              ),
            ]),
          ),
        ),
      ),
    ),
  );

  // ── Botonera inferior — gradiente pergamino ───────────────────────
  Widget _buildBotonera() => Container(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 38),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter, end: Alignment.topCenter,
        colors: [
          _kParchment.withValues(alpha: 0.97),
          _kParchment.withValues(alpha: 0.72),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ),
    ),
    child: SafeArea(
      top: false,
      child: !isTracking ? _buildBotonEmpezar() : _buildBotonesControl(),
    ),
  );

  Widget _buildBotonEmpezar() => Center(
    child: GestureDetector(
      onTap: _mostrandoCuentaAtras ? null : _iniciarCuentaAtras,
      child: AnimatedBuilder(
        animation: _pulsoAnim,
        builder: (_, child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7A4A00), Color(0xFFD4A84C), Color(0xFFD4722A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _kGoldLight.withValues(alpha: 0.35 + _pulso.value * 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _kGold.withValues(alpha: 0.12 + _pulso.value * 0.28),
                blurRadius: 24, spreadRadius: 2, offset: const Offset(0, 5)),
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8),
            ],
          ),
          child: child,
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('🏴', style: TextStyle(fontSize: 21)),
          SizedBox(width: 12),
          Text('CONQUISTAR', style: TextStyle(
              fontSize: 16, color: _kInk,
              fontWeight: FontWeight.w900, letterSpacing: 2.5)),
        ]),
      ),
    ),
  );

  Widget _buildBotonesControl() => Row(children: [
    // Pausa — circular pergamino
    GestureDetector(
      onTap: togglePause,
      child: Container(
        width: 62, height: 62,
        decoration: BoxDecoration(
          color: _kParchMid, shape: BoxShape.circle,
          border: Border.all(color: _kGoldDim.withValues(alpha: 0.55), width: 1.5),
          boxShadow: [
            BoxShadow(color: _kGold.withValues(alpha: 0.12), blurRadius: 12),
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 5),
          ],
        ),
        child: Center(child: Text(
          isPaused ? '▶️' : '⏸️',
          style: const TextStyle(fontSize: 26))),
      ),
    ),
    const SizedBox(width: 14),
    // Retirada — terracota oscuro
    Expanded(
      child: GestureDetector(
        onTap: stopTracking,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 19),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF5C1200), Color(0xFFB84020)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: _kTerracotta.withValues(alpha: 0.35), width: 1),
            boxShadow: [
              BoxShadow(color: _kTerracotta.withValues(alpha: 0.38),
                  blurRadius: 16, offset: const Offset(0, 4)),
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6),
            ],
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('🏳️', style: TextStyle(fontSize: 20)),
            SizedBox(width: 10),
            Text('RETIRADA', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900,
                color: Color(0xFFFFE0C0), letterSpacing: 2.5)),
          ]),
        ),
      ),
    ),
  ]);
}

// =============================================================================
// PAINTERS
// =============================================================================
class _SpeedLinesPainter extends CustomPainter {
  final Color color;
  const _SpeedLinesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.32)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rnd = math.Random(42);
    for (int i = 0; i < 10; i++) {
      final x   = rnd.nextDouble() * size.width;
      final y   = rnd.nextDouble() * size.height;
      final len = 12.0 + rnd.nextDouble() * 22;
      canvas.drawLine(Offset(x, y), Offset(x - len, y + 3), paint);
    }
  }

  @override
  bool shouldRepaint(_SpeedLinesPainter old) => old.color != color;
}