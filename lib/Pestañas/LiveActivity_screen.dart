import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:custom_timer/custom_timer.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../services/territory_service.dart';
import '../services/league_service.dart';
import '../services/anticheat_service.dart';
import '../services/stats_service.dart';
import '../services/subscription_service.dart';
import '../services/clan_service.dart';
import '../widgets/conquista_overlay.dart';
import '../widgets/anticheat_warning_overlay.dart';
import '../widgets/narrador_overlay.dart';
import '../services/narrador_service.dart';
import '../services/desafios_service.dart';

// =============================================================================
// PALETA
// =============================================================================
const _kInk        = Color(0xFF1E1408);
const _kParchment  = Color(0xFF2A1F0F);
const _kParchMid   = Color(0xFF3D2E18);
const _kGold       = Color(0xFFD4A84C);
const _kGoldLight  = Color(0xFFEDD98A);
const _kGoldDim    = Color(0xFF7A5E28);
const _kTerracotta = Color(0xFFD4722A);
const _kWater      = Color(0xFF5BA3A0);
const _kWaterLight = Color(0xFF8ECFCC);
const _kVerde      = Color(0xFF8FAF4A);
const _kCosmicBg   = Color(0xFF040302);
const _kCosmicMid  = Color(0xFF1A0F08);

// =============================================================================
// CONSTANTES GPS / CÁMARA
// =============================================================================
const double _kPitchCorrer = 50.0;
const double _kPitchNormal = 0.0;
const double _kZoomCorrer  = 18.5;
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

  // ── Timer
  late final CustomTimerController _timerController = CustomTimerController(
    vsync: this,
    begin: const Duration(),
    end: const Duration(hours: 24),
    initialState: CustomTimerState.reset,
    interval: CustomTimerInterval.milliseconds,
  );
  final Stopwatch _stopwatch = Stopwatch();

  // ── Mapbox
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _annotationManager;
  final Map<String, mapbox.PointAnnotation> _anotacionesJugadores = {};

  // ── GPS
  List<LatLng> routePoints           = [];
  bool isTracking                    = false;
  bool isPaused                      = false;
  double _distanciaTotal             = 0.0;
  double _velocidadActualKmh         = 0.0;
  double _bearing                    = 0.0;
  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;
  Position? _ultimaPosicionVelocidad;

  int _puntosDesdeUltimoUpdate       = 0;
  static const int _kActualizarMapaCadaN = 3;
  DateTime _ultimoMovCamara = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kMinMsCamara = 800;

  // ── Modo de juego
  bool _modoSolitario = false;

  // ── Jugador
  Color  _colorTerritorio      = _kTerracotta;
  List<TerritoryData> _territorios = [];
  bool   _territoriosCargados  = false;
  String _miNickname           = 'Alguien';
  String? _miClanId;
  bool   _boostXpActivo        = false;

  final Set<String> _territoriosNotificadosEnSesion = {};
  final Set<String> _territoriosVisitadosEnSesion   = {};

  StreamSubscription? _jugadoresStream;
  final Map<String, Map<String, dynamic>> _jugadoresActivos = {};

  Timer? _timerPublicarPosicion;
  int    _presenciaIntervaloSeg = _kPresenciaMovimientoSeg;

  // ── Anti-cheat
  final AntiCheatService _antiCheat = AntiCheatService();
  bool _sesionInvalidadaPorCheat    = false;

  // ── Modo noche
  late bool _modoNoche;
  bool _modoManual = false;

  // ── Estilo de mapa
  String _estiloMapa = 'normal';

  // ── Animaciones
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

  late AnimationController _globoAnim;

  // ── Capas de mapa
  static const String _routeSourceId      = 'route-source';
  static const String _routeLayerId       = 'route-layer';
  static const String _buildingsLayerId   = 'buildings-3d';
  static const String _fillLayerId        = 'territorios-fill';
  static const String _fillInnerLayerId   = 'territorios-fill-inner';
  static const String _borderLayerId      = 'territorios-border';
  static const String _borderPulseLayerId = 'territorios-border-pulse';
  static const String _sourceId          = 'territorios-source';

  bool _routeLayerCreated  = false;
  bool _buildings3dCreated = false;
  bool _territoriosLayersCreated = false;

  Timer? _pulsoTimer;
  double _pulsoOpacity = 0.9;
  bool   _pulsoUp      = false;

  // ── Narrador
  final NarradorService _narrador = NarradorService();
  MensajeNarrador? _mensajeNarrador;
  double _distanciaUltimoAnalisisRitmo  = 0;
  int    _minutosResistenciaNotificados = 0;
  Timer? _timerResistencia;

  // ── Reto activo desde Home ─────────────────────────────────────────────────
  Map<String, dynamic>? _retoActivo;
  bool _retoCompletado = false;

  // ==========================================================================
  // INIT / DISPOSE
  // ==========================================================================
  @override
  void initState() {
    super.initState();
    _modoNoche = _esHoraNoche();

    StatsService.mapboxToken = 'pk.eyJ1IjoibHVpaXNnb29tZXp6MSIsImEiOiJjbW1mNDVoajkwNGNyMnBzNTBiaXNrMm5pIn0.gzN772_GMDx55owCXwsozA';

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

    _globoAnim = AnimationController(
        vsync: this, duration: const Duration(seconds: 120))
      ..repeat();

    _determinePosition();
    _cargarDatosIniciales();
    _escucharJugadoresActivos();

    _narrador.onMensaje = (msg) {
      if (mounted) setState(() => _mensajeNarrador = msg);
    };

    // ── Leer el reto activo si viene desde el Home
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['retoActivo'] != null) {
        final reto = args['retoActivo'] as Map<String, dynamic>;
        setState(() => _retoActivo = reto);
        // Configurar el narrador con los datos del reto
        final titulo         = reto['titulo'] as String? ?? 'Reto';
        final objetivoMetros = (reto['objetivo_valor'] as num?)?.toDouble() ?? 0;
        _narrador.configurarReto(titulo, objetivoMetros);
        // Anunciar el reto con un pequeño delay para que cargue la pantalla
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _narrador.anunciarReto(titulo);
        });
      }
    });
  }

  @override
  void dispose() {
    _timerController.dispose();
    _timerCuentaAtras?.cancel();
    _positionStream?.cancel();
    _jugadoresStream?.cancel();
    _timerPublicarPosicion?.cancel();
    _pulsoTimer?.cancel();
    _timerResistencia?.cancel();
    _narrador.resetear();
    _cuentaAtrasAnim.dispose();
    _hudAnim.dispose();
    _bounceAnim.dispose();
    _pulsoAnim.dispose();
    _globoAnim.dispose();
    _limpiarPresenciaFirestore();
    super.dispose();
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================
  bool _esHoraNoche() {
    final h = DateTime.now().hour;
    return h >= 21 || h < 6;
  }

  void _toggleModoNoche() {
    setState(() { _modoManual = true; _modoNoche = !_modoNoche; });
    if (_estiloMapa == 'normal') {
      _mapboxMap?.loadStyleURI(_mapStyle);
    }
    _buildings3dCreated = false;
    _territoriosLayersCreated = false;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _addBuildings3D();
      _configurarAtmosfera();
      _dibujarTerritoriosEnMapa();
    });
  }

  String get _mapStyle {
    if (_estiloMapa == 'satelite') return mapbox.MapboxStyles.SATELLITE_STREETS;
    if (_estiloMapa == 'militar')  return mapbox.MapboxStyles.DARK;
    return _modoNoche ? mapbox.MapboxStyles.DARK : _kEstiloPersonalizado;
  }

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
    if (obj is Map)
      return '{${obj.entries.map((e) => '"${e.key}":${_encodeJson(e.value)}').join(',')}}';
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
          .collection('players')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        _miNickname = doc.data()?['nickname'] ?? 'Alguien';
        final colorInt = (doc.data()?['territorio_color'] as num?)?.toInt();
        if (colorInt != null && mounted) {
          setState(() => _colorTerritorio = Color(colorInt));
        }
        final boost  = doc.data()?['boost_xp_activo'] as bool? ?? false;
        final expira = doc.data()?['boost_xp_expira'] as Timestamp?;
        if (boost && expira != null && expira.toDate().isAfter(DateTime.now())) {
          if (mounted) setState(() => _boostXpActivo = true);
        }
        _miClanId = doc.data()?['clanId'] as String?;
      }
      final lista = await TerritoryService.cargarTodosLosTerritorios();
      if (mounted) {
        setState(() { _territorios = lista; _territoriosCargados = true; });
        _dibujarTerritoriosEnMapa();
      }
    } catch (e) {
      debugPrint('Error datos iniciales: $e');
    }
  }

  Future<void> _determinePosition() async {
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.always || p == LocationPermission.whileInUse) {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) setState(() => _currentPosition = pos);
    }
  }

  // ==========================================================================
  // MAPBOX
  // ==========================================================================
  void _onMapCreated(mapbox.MapboxMap map) async {
    _mapboxMap = map;
    await map.style.setProjection(
        mapbox.StyleProjection(name: mapbox.StyleProjectionName.globe));
    await map.gestures.updateSettings(
        mapbox.GesturesSettings(rotateEnabled: true, pitchEnabled: false));
    _annotationManager =
        await map.annotations.createPointAnnotationManager();
    await _moverCamara(
      lat: _currentPosition?.latitude ?? 40.4167,
      lng: _currentPosition?.longitude ?? -3.70325,
      zoom: _kZoomGlobo,
      bearing: 0,
      pitch: _kPitchNormal,
      animated: false,
    );
    await Future.delayed(const Duration(milliseconds: 500));
    await _addBuildings3D();
    await _configurarAtmosfera();
    await _dibujarTerritoriosEnMapa();
  }

  Future<void> _moverCamara({
    required double lat,
    required double lng,
    double? zoom,
    double? bearing,
    double? pitch,
    bool animated = true,
    int duracion = 600,
    bool forzar = false,
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
      zoom: zoom,
      bearing: bearing,
      pitch: pitch,
    );
    if (animated) {
      await _mapboxMap!.flyTo(
          cam, mapbox.MapAnimationOptions(duration: duracion));
    } else {
      await _mapboxMap!.setCamera(cam);
    }
  }

  Future<void> _configurarAtmosfera() async {
    if (_mapboxMap == null) return;
    try {
      final layers = await _mapboxMap!.style.getStyleLayers();
      if (!layers.any((l) => l?.id == 'sky-layer')) {
        await _mapboxMap!.style.addLayer(mapbox.SkyLayer(id: 'sky-layer'));
      }
      if (_modoNoche) {
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-type', 'atmosphere');
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-color', 'rgba(2,2,15,1)');
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-halo-color', 'rgba(5,5,30,0.8)');
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-sun-intensity', 0.0);
        await _mapboxMap!.style
            .setStyleLayerProperty('sky-layer', 'sky-opacity', 1.0);
      } else {
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-type', 'atmosphere');
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-color', 'rgba(135,206,250,1)');
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-halo-color', 'rgba(200,230,255,0.9)');
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-sun-intensity', 15.0);
        await _mapboxMap!.style
            .setStyleLayerProperty('sky-layer', 'sky-opacity', 1.0);
      }
    } catch (e) {
      debugPrint('Error atmosfera: $e');
    }
  }

  Future<void> _addBuildings3D() async {
    if (_mapboxMap == null || _buildings3dCreated) return;
    try {
      try {
        await _mapboxMap!.style.removeStyleLayer(_buildingsLayerId);
      } catch (_) {}
      await _mapboxMap!.style.addLayer(mapbox.FillExtrusionLayer(
          id: _buildingsLayerId,
          sourceId: 'composite',
          sourceLayer: 'building'));
      await _mapboxMap!.style.setStyleLayerProperty(
          _buildingsLayerId, 'filter', ['==', ['get', 'extrude'], 'true']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _buildingsLayerId, 'fill-extrusion-base',
          ['interpolate', ['linear'], ['zoom'], 15, 0, 15.05, ['get', 'min_height']]);
      await _mapboxMap!.style.setStyleLayerProperty(
          _buildingsLayerId, 'fill-extrusion-height',
          ['interpolate', ['linear'], ['zoom'], 15, 0, 15.05, ['get', 'height']]);
      await _mapboxMap!.style.setStyleLayerProperty(
          _buildingsLayerId, 'fill-extrusion-color', '#C8B89A');
      await _mapboxMap!.style.setStyleLayerProperty(
          _buildingsLayerId, 'fill-extrusion-opacity', 0.75);
      await _mapboxMap!.style.setStyleLayerProperty(
          _buildingsLayerId, 'fill-extrusion-ambient-occlusion-intensity', 0.3);
      await _mapboxMap!.style.setStyleLayerProperty(
          _buildingsLayerId, 'fill-extrusion-ambient-occlusion-radius', 3.0);
      _buildings3dCreated = true;
    } catch (e) {
      debugPrint('Error edificios 3D: $e');
    }
  }

  Future<void> _dibujarTerritoriosEnMapa() async {
    if (_mapboxMap == null || _territorios.isEmpty) return;

    final features = _territorios.map((t) {
      final coords = t.puntos.map((p) => [p.longitude, p.latitude]).toList();
      coords.add(coords.first);
      return _encodeJson({
        'type': 'Feature',
        'properties': {
          'color':        _colorToHex(t.color),
          'fillOpacity':  t.esMio ? 0.38 : 0.18,
          'innerOpacity': t.esMio ? 0.20 : 0.0,
          'borderOpacity':t.esMio ? 0.95 : 0.55,
          'borderWidth':  t.esMio ? 2.8  : 1.4,
          'esMio':        t.esMio,
        },
        'geometry': {'type': 'Polygon', 'coordinates': [coords]},
      });
    }).join(',');

    final geojson = '{"type":"FeatureCollection","features":[$features]}';

    try {
      if (_territoriosLayersCreated) {
        final src = await _mapboxMap!.style
            .getSource(_sourceId) as mapbox.GeoJsonSource?;
        await src?.updateGeoJSON(geojson);
        return;
      }

      _pulsoTimer?.cancel();
      for (final id in [
        _borderPulseLayerId, _borderLayerId, _fillInnerLayerId, _fillLayerId
      ]) {
        try { await _mapboxMap!.style.removeStyleLayer(id); } catch (_) {}
      }
      try { await _mapboxMap!.style.removeStyleSource(_sourceId); } catch (_) {}

      await _mapboxMap!.style
          .addSource(mapbox.GeoJsonSource(id: _sourceId, data: geojson));

      await _mapboxMap!.style
          .addLayer(mapbox.FillLayer(id: _fillLayerId, sourceId: _sourceId));
      await _mapboxMap!.style
          .setStyleLayerProperty(_fillLayerId, 'fill-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _fillLayerId, 'fill-opacity', ['get', 'fillOpacity']);
      await _mapboxMap!.style
          .setStyleLayerProperty(_fillLayerId, 'fill-antialias', true);

      await _mapboxMap!.style.addLayer(
          mapbox.FillLayer(id: _fillInnerLayerId, sourceId: _sourceId));
      await _mapboxMap!.style.setStyleLayerProperty(
          _fillInnerLayerId, 'fill-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _fillInnerLayerId, 'fill-opacity', ['get', 'innerOpacity']);
      await _mapboxMap!.style
          .setStyleLayerProperty(_fillInnerLayerId, 'fill-antialias', true);

      await _mapboxMap!.style
          .addLayer(mapbox.LineLayer(id: _borderLayerId, sourceId: _sourceId));
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderLayerId, 'line-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderLayerId, 'line-width', ['get', 'borderWidth']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderLayerId, 'line-opacity', ['get', 'borderOpacity']);
      await _mapboxMap!.style
          .setStyleLayerProperty(_borderLayerId, 'line-join', 'round');
      await _mapboxMap!.style
          .setStyleLayerProperty(_borderLayerId, 'line-cap', 'round');

      await _mapboxMap!.style.addLayer(
          mapbox.LineLayer(id: _borderPulseLayerId, sourceId: _sourceId));
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderPulseLayerId, 'line-color', ['get', 'color']);
      await _mapboxMap!.style
          .setStyleLayerProperty(_borderPulseLayerId, 'line-width', 6.0);
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderPulseLayerId, 'line-opacity',
          ['case', ['==', ['get', 'esMio'], true], _pulsoOpacity, 0.0]);
      await _mapboxMap!.style
          .setStyleLayerProperty(_borderPulseLayerId, 'line-blur', 3.0);
      await _mapboxMap!.style
          .setStyleLayerProperty(_borderPulseLayerId, 'line-join', 'round');

      _territoriosLayersCreated = true;

      _pulsoTimer =
          Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!mounted || _mapboxMap == null) return;
        if (_pulsoUp) {
          _pulsoOpacity += 0.025;
          if (_pulsoOpacity >= 0.60) _pulsoUp = false;
        } else {
          _pulsoOpacity -= 0.025;
          if (_pulsoOpacity <= 0.15) _pulsoUp = true;
        }
        try {
          _mapboxMap!.style.setStyleLayerProperty(
              _borderPulseLayerId, 'line-opacity',
              ['case', ['==', ['get', 'esMio'], true], _pulsoOpacity, 0.0]);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('Error territorios: $e');
    }
  }

  Future<void> _actualizarRutaEnMapa() async {
    if (_mapboxMap == null || routePoints.length < 2) return;
    final coords = routePoints.map((p) => [p.longitude, p.latitude]).toList();
    final geojson = _encodeJson({
      'type': 'Feature',
      'geometry': {'type': 'LineString', 'coordinates': coords}
    });
    try {
      if (!_routeLayerCreated) {
        await _mapboxMap!.style
            .addSource(mapbox.GeoJsonSource(id: _routeSourceId, data: geojson));
        await _mapboxMap!.style.addLayer(
            mapbox.LineLayer(id: _routeLayerId, sourceId: _routeSourceId));
        await _mapboxMap!.style.setStyleLayerProperty(
            _routeLayerId, 'line-color', _colorToHex(_colorTerritorio));
        await _mapboxMap!.style
            .setStyleLayerProperty(_routeLayerId, 'line-width', 4.5);
        await _mapboxMap!.style
            .setStyleLayerProperty(_routeLayerId, 'line-opacity', 0.9);
        _routeLayerCreated = true;
      } else {
        final src = await _mapboxMap!.style
            .getSource(_routeSourceId) as mapbox.GeoJsonSource?;
        await src?.updateGeoJSON(geojson);
      }
    } catch (e) {
      debugPrint('Error ruta mapa: $e');
    }
  }

  // ==========================================================================
  // JUGADORES ACTIVOS
  // ==========================================================================
  void _escucharJugadoresActivos() {
    _jugadoresStream = FirebaseFirestore.instance
        .collection('presencia_activa')
        .snapshots()
        .listen((snap) async {
      if (!mounted) return;
      final user   = FirebaseAuth.instance.currentUser;
      final nuevos = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        if (doc.id == user?.uid) continue;
        final d  = doc.data();
        final ts = d['timestamp'] as Timestamp?;
        if (ts != null &&
            DateTime.now().difference(ts.toDate()).inMinutes < 5) {
          nuevos[doc.id] = d;
        }
      }
      setState(() => _jugadoresActivos
        ..clear()
        ..addAll(nuevos));
      _actualizarAvataresMapa(nuevos);
    });
  }

  void _actualizarAvataresMapa(
      Map<String, Map<String, dynamic>> jugadores) async {
    if (_annotationManager == null) return;
    final activos = jugadores.keys.toSet();
    for (final uid
        in _anotacionesJugadores.keys.where((k) => !activos.contains(k)).toList()) {
      _eliminarAvatarJugador(uid);
    }
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
          ..image    = bytes);
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

  void _crearAvatarJugador(
      String uid, double lat, double lng, Uint8List bytes) async {
    if (_annotationManager == null) return;
    final ann = await _annotationManager!.create(
        mapbox.PointAnnotationOptions(
          geometry:
              mapbox.Point(coordinates: mapbox.Position(lng, lat)),
          image:    bytes,
          iconSize: 1.0,
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
    canvas.drawCircle(
        Offset(sz / 2, sz / 2), sz / 2 - 6, Paint()..color = _kParchment);
    canvas.drawCircle(
        Offset(sz / 2, sz / 2), sz / 2 - 6,
        Paint()
          ..color       = color
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 3);
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
      await FirebaseFirestore.instance
          .collection('presencia_activa')
          .doc(user.uid)
          .set({
        'lat':       _currentPosition!.latitude,
        'lng':       _currentPosition!.longitude,
        'color':     _colorTerritorio.value,
        'nickname':  _miNickname,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error presencia: $e');
    }
  }

  Future<void> _actualizarPuntosDesafio(
      int conquistados, double distanciaKm) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapRetador = await FirebaseFirestore.instance
          .collection('desafios')
          .where('retadorId', isEqualTo: user.uid)
          .where('estado', isEqualTo: 'activo')
          .limit(1)
          .get();
      final snapRetado = await FirebaseFirestore.instance
          .collection('desafios')
          .where('retadoId', isEqualTo: user.uid)
          .where('estado', isEqualTo: 'activo')
          .limit(1)
          .get();
      final doc = snapRetador.docs.isNotEmpty
          ? snapRetador.docs.first
          : snapRetado.docs.isNotEmpty
              ? snapRetado.docs.first
              : null;
      if (doc == null) return;
      final data = doc.data();
      final fin  = (data['fin'] as Timestamp?)?.toDate();
      if (fin != null && DateTime.now().isAfter(fin)) {
        await _finalizarDesafio(doc.id, data);
        return;
      }
      final int puntos = (conquistados * 10) + (distanciaKm * 5).round();
      if (puntos == 0) return;
      final bool soyRetador = data['retadorId'] == user.uid;
      await FirebaseFirestore.instance
          .collection('desafios')
          .doc(doc.id)
          .update({
        soyRetador ? 'puntosRetador' : 'puntosRetado':
            FieldValue.increment(puntos),
      });
    } catch (e) {
      debugPrint('Error actualizando desafío: $e');
    }
  }

  Future<void> _finalizarDesafio(
      String desafioId, Map<String, dynamic> data) async {
    try {
      final puntosRetador = (data['puntosRetador'] as num?)?.toInt() ?? 0;
      final puntosRetado  = (data['puntosRetado'] as num?)?.toInt() ?? 0;
      final apuesta       = (data['apuesta'] as num?)?.toInt() ?? 0;
      final retadorId     = data['retadorId'] as String;
      final retadoId      = data['retadoId'] as String;
      final retadorNick   = data['retadorNick'] as String? ?? 'Rival';
      final retadoNick    = data['retadoNick'] as String? ?? 'Rival';
      final String ganadorId, ganadorNick, perdedorId, perdedorNick;
      if (puntosRetador >= puntosRetado) {
        ganadorId = retadorId; ganadorNick = retadorNick;
        perdedorId = retadoId; perdedorNick = retadoNick;
      } else {
        ganadorId = retadoId; ganadorNick = retadoNick;
        perdedorId = retadorId; perdedorNick = retadorNick;
      }
      await FirebaseFirestore.instance
          .collection('players')
          .doc(ganadorId)
          .update({'monedas': FieldValue.increment(apuesta * 2)});
      await FirebaseFirestore.instance
          .collection('desafios')
          .doc(desafioId)
          .update({'estado': 'finalizado', 'ganadorId': ganadorId});
      for (final n in [
        {'toUserId': ganadorId,  'type': 'desafio_ganado',
         'message': '🏆 ¡Ganaste el desafío contra $perdedorNick! +${apuesta * 2} 🪙'},
        {'toUserId': perdedorId, 'type': 'desafio_perdido',
         'message': '💀 Perdiste el desafío contra $ganadorNick. $ganadorNick se lleva ${apuesta * 2} 🪙'},
      ]) {
        await FirebaseFirestore.instance.collection('notifications').add(
            {...n, 'read': false, 'timestamp': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      debugPrint('Error finalizando desafío: $e');
    }
  }

  Future<void> _limpiarPresenciaFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('presencia_activa')
          .doc(user.uid)
          .delete();
    } catch (_) {}
  }

  // ==========================================================================
  // TRACKING
  // ==========================================================================
  StreamSubscription<Position> _crearStreamGPS() {
    return Geolocator.getPositionStream(
        locationSettings: _kGpsMovimiento).listen(
      (Position pos) async {
        if (isPaused || !mounted) return;

        // ── Anti-cheat
        final acResultado = _antiCheat.analizarPunto(pos);
        if (!acResultado.esValido) {
          if (_antiCheat.sesionCancelada && !_sesionInvalidadaPorCheat) {
            _sesionInvalidadaPorCheat = true;
            _positionStream?.cancel();
            _timerPublicarPosicion?.cancel();
            _stopwatch.stop();
            _timerController.pause();
            await AntiCheatWarningOverlay.mostrar(
              context,
              motivo: acResultado.detalle ?? 'Actividad sospechosa detectada',
            );
            if (mounted) {
              setState(() {
                isTracking     = false;
                isPaused       = false;
                _hudMinimizado = false;
                routePoints.clear();
              });
              await _limpiarPresenciaFirestore();
            }
          }
          return;
        }

        // ── Actualizar estado GPS
        final newPt = LatLng(pos.latitude, pos.longitude);
        setState(() {
          if (routePoints.isNotEmpty) {
            final dist = Geolocator.distanceBetween(
              routePoints.last.latitude,
              routePoints.last.longitude,
              newPt.latitude,
              newPt.longitude,
            );
            _distanciaTotal += dist / 1000;
            _bearing = _calcularBearing(routePoints.last, newPt);

            if (_ultimaPosicionVelocidad != null) {
              final dt = pos.timestamp
                      .difference(_ultimaPosicionVelocidad!.timestamp)
                      .inMilliseconds /
                  3600000.0;
              if (dt > 0) {
                final vel = (dist / 1000) / dt;
                _velocidadActualKmh =
                    (_velocidadActualKmh * 0.6 + vel * 0.4).clamp(0, 40);
              }
            }
          }
          routePoints.add(newPt);
          _currentPosition         = pos;
          _ultimaPosicionVelocidad = pos;
          _puntosDesdeUltimoUpdate++;
        });

        // ── Cámara y mapa
        _moverCamara(
          lat:     pos.latitude,
          lng:     pos.longitude,
          zoom:    _kZoomCorrer,
          bearing: _bearing,
          pitch:   _kPitchCorrer,
        );
        if (_puntosDesdeUltimoUpdate >= _kActualizarMapaCadaN) {
          _puntosDesdeUltimoUpdate = 0;
          _actualizarRutaEnMapa();
        }

        // ── Verificar progreso y completion del reto activo
        if (_retoActivo != null && !_retoCompletado) {
          final objetivoMetros =
              (_retoActivo!['objetivo_valor'] as num?)?.toDouble() ?? 0;
          final distanciaMetros = _distanciaTotal * 1000;
          if (objetivoMetros > 0) {
            // Narrador al 50% del reto
            _narrador.eventoMitadReto(distanciaMetros);
            // Narrador a 200m del final
            _narrador.eventoFinalReto(distanciaMetros);
            // Completado
            if (distanciaMetros >= objetivoMetros) {
              setState(() => _retoCompletado = true);
              final titulo = _retoActivo!['titulo'] as String? ?? 'Reto';
              _narrador.anunciarRetoCompletado(titulo);
              _mostrarNotificacionRetoCompletado();
            }
          }
        }

        // ── Territorios
        if (!_modoSolitario) _procesarPosicionEnTerritorios(newPt);

        // ── Narrador
        final kmActual = _distanciaTotal.floor();
        if (kmActual > 0) _narrador.eventoKilometro(kmActual);
        if (_distanciaTotal - _distanciaUltimoAnalisisRitmo >= 0.5) {
          _distanciaUltimoAnalisisRitmo = _distanciaTotal;
          _narrador.analizarRitmo(_velocidadActualKmh);
        }

        // ── Rival cerca
        if (!_modoSolitario) {
          final double radioRadar = SubscriptionService.radioRadar;
          for (final entry in _jugadoresActivos.entries) {
            final lat2 = (entry.value['lat'] as num?)?.toDouble();
            final lng2 = (entry.value['lng'] as num?)?.toDouble();
            if (lat2 == null || lng2 == null) continue;
            final dist = Geolocator.distanceBetween(
                pos.latitude, pos.longitude, lat2, lng2);
            if (dist < radioRadar) {
              _narrador.eventoRivalCerca(
                  entry.value['nickname'] as String?, dist);
              break;
            }
          }
        }

        // ── Modo noche automático
        if (!_modoManual) {
          final esNoche = _esHoraNoche();
          if (esNoche != _modoNoche) {
            setState(() => _modoNoche = esNoche);
          }
        }
      },
      onError: (e) => debugPrint('GPS error: $e'),
    );
  }

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
      isTracking     = true;
      isPaused       = false;
      _distanciaTotal       = 0;
      _velocidadActualKmh   = 0;
      _bearing              = 0;
      routePoints.clear();
      _puntosDesdeUltimoUpdate = 0;
      _territoriosNotificadosEnSesion.clear();
      _territoriosVisitadosEnSesion.clear();
      _hudMinimizado = true;
      // Reset reto al iniciar nueva sesión
      _retoCompletado = false;
    });
    _antiCheat.resetear();
    _sesionInvalidadaPorCheat = false;
    _stopwatch.reset();
    _stopwatch.start();
    _timerController.start();
    _iniciarPublicacionPosicion();
    _narrador.iniciar();
    _minutosResistenciaNotificados = 0;
    _distanciaUltimoAnalisisRitmo  = 0;

    _timerResistencia?.cancel();
    _timerResistencia =
        Timer.periodic(const Duration(minutes: 1), (_) {
      if (!isTracking || isPaused || !mounted) return;
      final mins = _stopwatch.elapsed.inMinutes;
      if (mins >= 20 &&
          mins % 10 == 0 &&
          mins != _minutosResistenciaNotificados) {
        _minutosResistenciaNotificados = mins;
        _narrador.eventoResistencia(mins);
      }
    });

    await _mapboxMap?.gestures.updateSettings(
        mapbox.GesturesSettings(rotateEnabled: false, pitchEnabled: false));
    if (_currentPosition != null) {
      await _moverCamara(
        lat:     _currentPosition!.latitude,
        lng:     _currentPosition!.longitude,
        zoom:    _kZoomCorrer,
        bearing: _bearing,
        pitch:   _kPitchCorrer,
        duracion: 2800,
        forzar:  true,
      );
    }

    _positionStream = _crearStreamGPS();
  }

  void togglePause() {
    setState(() {
      isPaused       = !isPaused;
      _hudMinimizado = !isPaused;
    });

    if (isPaused) {
      _timerController.pause();
      _stopwatch.stop();
      _velocidadActualKmh = 0;
      _bounceAnim.stop();
      _positionStream?.cancel();

      _positionStream = Geolocator.getPositionStream(
          locationSettings: _kGpsPausado).listen((pos) {
        if (mounted) setState(() => _currentPosition = pos);
      });

      _ajustarPresenciaPausado();
      if (_currentPosition != null) {
        _moverCamara(
          lat:     _currentPosition!.latitude,
          lng:     _currentPosition!.longitude,
          zoom:    _kZoomPausado,
          pitch:   _kPitchNormal,
          bearing: 0,
          forzar:  true,
        );
      }
      _hudAnim.forward();
    } else {
      _timerController.start();
      _stopwatch.start();
      _bounceAnim.repeat(reverse: true);
      _positionStream?.cancel();
      _positionStream = _crearStreamGPS();
      _ajustarPresenciaMovimiento();
      if (_currentPosition != null) {
        _moverCamara(
          lat:     _currentPosition!.latitude,
          lng:     _currentPosition!.longitude,
          zoom:    _kZoomCorrer,
          pitch:   _kPitchCorrer,
          bearing: _bearing,
          forzar:  true,
        );
      }
    }
  }

  Future<void> stopTracking() async {
    _stopwatch.stop();
    _timerController.pause();
    _positionStream?.cancel();
    _timerPublicarPosicion?.cancel();
    _pulsoTimer?.cancel();
    await _limpiarPresenciaFirestore();

    final tiempoFinal    = _stopwatch.elapsed;
    final rutaFinal      = List<LatLng>.from(routePoints);
    final distanciaFinal = _distanciaTotal;

    if (mounted) {
      setState(() {
        isTracking          = false;
        isPaused            = false;
        _velocidadActualKmh = 0;
        _hudMinimizado      = false;
      });
    }
    await _mapboxMap?.gestures.updateSettings(
        mapbox.GesturesSettings(rotateEnabled: true, pitchEnabled: false));

    // ── Guardar log
    String? logId;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && distanciaFinal > 0) {
        final monedasBase    = (distanciaFinal * 10).round();
        final bool esPremium = SubscriptionService.currentStatus.isPremium;
        final int multiplicador =
            (_boostXpActivo ? 2 : 1) * (esPremium ? 2 : 1);
        final double factorModo = multiplicadorMonedas(_modoSolitario);
        final int monedasFinales =
            (monedasBase * multiplicador * factorModo).round();
        await FirebaseFirestore.instance
            .collection('players')
            .doc(user.uid)
            .update({'monedas': FieldValue.increment(monedasFinales)});
        final now = DateTime.now();
        final logRef = await FirebaseFirestore.instance
            .collection('activity_logs')
            .add({
          'userId':          user.uid,
          'distancia':       distanciaFinal,
          'tiempo_segundos': tiempoFinal.inSeconds,
          'boost_activo':    _boostXpActivo,
          'timestamp':       FieldValue.serverTimestamp(),
          'titulo': _modoSolitario ? 'Exploración Solitaria' : 'Carrera Libre',
          'modo': _modoSolitario ? 'solitario' : 'competitivo',
          'fecha_dia':
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        });
        logId = logRef.id;

        if (rutaFinal.isNotEmpty) {
          StatsService.enriquecerLog(logId: logId, ruta: rutaFinal)
              .catchError((e) => debugPrint('Error enriquecerLog: $e'));
        }
      }
    } catch (e) {
      debugPrint('Error log: $e');
    }

    // ── Validación post-sesión anticheat
    if (distanciaFinal > 0 && !_sesionInvalidadaPorCheat) {
      final sesionCheck = AntiCheatService.analizarSesionCompleta(
        ruta:         rutaFinal,
        tiempo:       tiempoFinal,
        distanciaKm:  distanciaFinal,
      );
      if (!sesionCheck.esValida) {
        _sesionInvalidadaPorCheat = true;
        if (mounted) {
          await AntiCheatWarningOverlay.mostrar(
            context,
            motivo: sesionCheck.motivo ?? 'Sesión inválida',
          );
          if (mounted) Navigator.of(context).pop();
        }
        return;
      }
    }

    // ── Conquistas
    int conquistados = 0;

    if (_modoSolitario) {
      final creado = await TerritoryService.crearTerritorioSolitario(
        ruta:            rutaFinal,
        colorTerritorio: _colorTerritorio,
        nickname:        _miNickname,
      );
      if (creado) {
        conquistados = 1;
        if (mounted) await ConquistaOverlay.mostrar(context, esInvasion: false);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.transparent,
            elevation: 0,
            content: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _kParchMid,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kGoldDim),
              ),
              child: Row(children: [
                const Text('🗺️', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Área insuficiente para crear territorio.\n'
                    '¡Explora más calles y rodea una zona más amplia!',
                    style: GoogleFonts.rajdhani(
                        color: _kGoldLight,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ));
        }
      }
    } else {
      conquistados =
          await _procesarConquistas(rutaFinal, tiempoFinal, distanciaFinal);
      await _actualizarPuntosDesafio(conquistados, distanciaFinal);
      if (mounted && distanciaFinal > 0) {
        String? nombreRival;
        if (conquistados > 0) {
          final rivalT = _territorios
              .where((t) => !t.esMio)
              .cast<TerritoryData?>()
              .firstWhere((_) => true, orElse: () => null);
          nombreRival = rivalT?.ownerNickname;
        }
        await ConquistaOverlay.mostrar(
          context,
          esInvasion:       conquistados > 0,
          nombreTerritorio: nombreRival,
        );
      }
    }

    if (!mounted) return;
    final puntosLigaGanados = _modoSolitario
        ? 0
        : (distanciaFinal > 0 ? 15 : 0) + (conquistados * 25);

    // ── Desafíos: acumular puntos y verificar expirados ──────────────────────
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && distanciaFinal > 0) {
      // Acumular puntos en desafíos activos
      DesafiosService.acumularPuntos(
        uid:                    user.uid,
        distanciaKm:            distanciaFinal,
        territoriosConquistados: conquistados,
      );
      // Resolver desafíos que hayan expirado durante la sesión
      DesafiosService.verificarExpirados(user.uid);
    }

    // ── NUEVO: pasar el reto completado al resumen si hubo uno
    Navigator.pushReplacementNamed(context, '/resumen', arguments: {
      'distancia':               distanciaFinal,
      'tiempo':                  tiempoFinal,
      'ruta':                    rutaFinal,
      'esDesdeCarrera':          true,
      'territoriosConquistados': conquistados,
      'puntosLigaGanados':       puntosLigaGanados,
      'retoCompletado':          _retoCompletado ? _retoActivo : null,
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
        _narrador.eventoTerritorioPropio();
        _mostrarSnackRefuerzo();
      }
    } else {
      if (!_territoriosNotificadosEnSesion.contains(t.docId)) {
        _territoriosNotificadosEnSesion.add(t.docId);
        TerritoryService.crearNotificacionInvasion(
          toUserId:    t.ownerId,
          fromNickname: _miNickname,
          territoryId: t.docId,
        );
        _narrador.eventoTerritorioRival(t.ownerNickname);
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
          if (escudo && expiraT != null &&
              expiraT.toDate().isAfter(DateTime.now())) continue;
        }
      } catch (_) {}

      try {
        final conquistado = await FirebaseFirestore.instance
            .runTransaction<bool>((tx) async {
          final terRef = FirebaseFirestore.instance
              .collection('territories').doc(t.docId);
          final terSnap = await tx.get(terRef);
          if (!terSnap.exists) return false;
          final currentOwner = terSnap.data()?['userId'] as String?;
          if (currentOwner != t.ownerId) return false;
          tx.update(terRef, {
            'userId':          user.uid,
            'ultima_visita':   FieldValue.serverTimestamp(),
            'conquistado_por': user.uid,
            'fecha_conquista': FieldValue.serverTimestamp(),
          });
          return true;
        });

        if (!conquistado) continue;

        for (final notif in [
          {
            'toUserId':    t.ownerId,
            'type':        'territory_lost',
            'message':     '😤 ¡$_miNickname te ha robado un territorio!',
            'fromNickname': _miNickname,
            'territoryId': t.docId,
          },
          {
            'toUserId':    user.uid,
            'type':        'territory_conquered',
            'message':     '🏴 ¡Conquistado de ${t.ownerNickname}!',
            'fromNickname': t.ownerNickname,
            'territoryId': t.docId,
            'distancia':   distancia,
            'tiempo_segundos': tiempo.inSeconds,
          },
        ]) {
          await FirebaseFirestore.instance.collection('notifications').add(
              {...notif, 'read': false, 'timestamp': FieldValue.serverTimestamp()});
        }

        await LeagueService.sumarPuntosLiga(user.uid, 25);
        await LeagueService.sumarPuntosLiga(t.ownerId, -10);
        _narrador.eventoConquista(t.ownerNickname);
        conquistados++;

        if (_miClanId != null) {
          try {
            await ClanService.sumarPuntosAlClan(
                clanId: _miClanId!, uid: user.uid, puntos: 25);
            final guerrasSnap = await FirebaseFirestore.instance
                .collection('clan_wars')
                .where('estado', isEqualTo: 'activa')
                .where('clanA.id', isEqualTo: _miClanId)
                .limit(1)
                .get();
            final guerrasSnapB = guerrasSnap.docs.isEmpty
                ? await FirebaseFirestore.instance
                    .collection('clan_wars')
                    .where('estado', isEqualTo: 'activa')
                    .where('clanB.id', isEqualTo: _miClanId)
                    .limit(1)
                    .get()
                : null;
            final warDoc = guerrasSnap.docs.isNotEmpty
                ? guerrasSnap.docs.first
                : guerrasSnapB?.docs.firstOrNull;
            if (warDoc != null) {
              await ClanService.puntoClanEnGuerra(
                  warId: warDoc.id, clanId: _miClanId!);
            }
          } catch (e) {
            debugPrint('Error puntos clan/guerra: $e');
          }
        }
      } catch (e) {
        debugPrint('Error conquistando (transacción): $e');
      }
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
          punto.longitude <
              (xj - xi) * (punto.latitude - yi) / (yj - yi) + xi) {
        inter++;
      }
    }
    return inter % 2 == 1;
  }

  bool _rutaPasaCercaDe(
          List<LatLng> ruta, LatLng obj, {required double radioMetros}) =>
      ruta.any((p) => Geolocator.distanceBetween(
              p.latitude, p.longitude, obj.latitude, obj.longitude) <=
          radioMetros);

  // ==========================================================================
  // SNACKS
  // ==========================================================================

  // ── NUEVO: Notificación de reto completado durante la carrera
  void _mostrarNotificacionRetoCompletado() {
    if (!mounted || _retoActivo == null) return;

    // Vibración triple para destacarlo
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 150),
        () => HapticFeedback.heavyImpact());
    Future.delayed(const Duration(milliseconds: 300),
        () => HapticFeedback.heavyImpact());

    final titulo = _retoActivo!['titulo'] as String? ?? 'Reto';

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 7),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3A2800), Color(0xFFD4A84C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: _kGold, width: 1.5),
          boxShadow: [
            BoxShadow(
                color: _kGold.withValues(alpha: 0.55), blurRadius: 28),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🏆', style: TextStyle(fontSize: 38)),
          const SizedBox(height: 8),
          Text(
            '¡RETO COMPLETADO!',
            textAlign: TextAlign.center,
            style: GoogleFonts.cinzel(
              color: _kGoldLight, fontSize: 17,
              fontWeight: FontWeight.w900, letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: GoogleFonts.rajdhani(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.30),
              border: Border.all(color: _kGoldDim.withValues(alpha: 0.5)),
            ),
            child: Text(
              'Puedes seguir corriendo o finalizar la carrera',
              textAlign: TextAlign.center,
              style: GoogleFonts.rajdhani(
                color: _kGoldLight.withValues(alpha: 0.85),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
      ),
    ));
  }

  void _mostrarSnackInvasion(String nick) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration:        const Duration(seconds: 3),
      backgroundColor: Colors.transparent,
      elevation:       0,
      content: _snackWrap(
        gradient: const LinearGradient(
            colors: [Color(0xFF6B1500), Color(0xFFD4520A)]),
        shadow: _kTerracotta,
        child: Row(children: [
          const Text('⚔️', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '¡Invadiendo el territorio de $nick!',
              style: const TextStyle(
                  color:      Color(0xFFFFE8C0),
                  fontWeight: FontWeight.bold,
                  fontSize:   13),
            ),
          ),
        ]),
      ),
    ));
  }

  void _mostrarSnackRefuerzo() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration:        const Duration(seconds: 2),
      backgroundColor: Colors.transparent,
      elevation:       0,
      content: _snackWrap(
        color:  _kParchMid,
        border: Border.all(color: _kGold.withValues(alpha: 0.55)),
        child:  const Row(children: [
          Text('🛡️', style: TextStyle(fontSize: 18)),
          SizedBox(width: 10),
          Text('¡Territorio reforzado!',
              style: TextStyle(
                  color:      _kGoldLight,
                  fontWeight: FontWeight.bold,
                  fontSize:   13)),
        ]),
      ),
    ));
  }

  void _mostrarSnackBoost(int monedas, {String etiqueta = '×2'}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration:        const Duration(seconds: 3),
      backgroundColor: Colors.transparent,
      elevation:       0,
      content: _snackWrap(
        gradient: LinearGradient(colors: [_kGoldDim, _kGold]),
        shadow:   _kGold,
        child: Row(children: [
          const Text('⚡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Text('¡Bonus! +$monedas 🪙 ($etiqueta)',
              style: const TextStyle(
                  color:      _kInk,
                  fontWeight: FontWeight.bold,
                  fontSize:   13)),
        ]),
      ),
    ));
  }

  Widget _snackWrap({
    Widget?    child,
    Gradient?  gradient,
    Color?     color,
    BoxBorder? border,
    Color      shadow = Colors.transparent,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient:     gradient,
          color:        color,
          borderRadius: BorderRadius.circular(14),
          border:       border,
          boxShadow: [
            BoxShadow(color: shadow.withValues(alpha: 0.4), blurRadius: 12)
          ],
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
        if (!isTracking && !_mostrandoCuentaAtras)
          Positioned.fill(child: _buildGloboOverlay()),
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
        if (isTracking && !isPaused && _mensajeNarrador != null)
          Positioned(
            bottom: 130, left: 0, right: 0,
            child: NarradorOverlay(mensaje: _mensajeNarrador),
          ),
        // ── NUEVO: Chip de reto activo visible mientras corres
        if (isTracking && _retoActivo != null && !_retoCompletado)
          Positioned(
            top: 160, left: 0, right: 0,
            child: Center(child: _buildChipRetoActivo()),
          ),
        Positioned(
            bottom: 0, left: 0, right: 0, child: _buildBotonera()),
      ]),
    );
  }

  // ── Chip pequeño que muestra el progreso del reto activo
  Widget _buildChipRetoActivo() {
    final objetivoMetros =
        (_retoActivo!['objetivo_valor'] as num?)?.toDouble() ?? 0;
    final distanciaMetros = _distanciaTotal * 1000;
    final progreso = objetivoMetros > 0
        ? (distanciaMetros / objetivoMetros).clamp(0.0, 1.0)
        : 0.0;
    final restanteM = (objetivoMetros - distanciaMetros).clamp(0.0, objetivoMetros);
    final restanteStr = restanteM >= 1000
        ? '${(restanteM / 1000).toStringAsFixed(2)} km'
        : '${restanteM.toInt()} m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _kParchment.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kGold.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: _kGold.withValues(alpha: 0.20), blurRadius: 12),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('⚡', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(
            _retoActivo!['titulo'] as String? ?? 'Reto activo',
            style: GoogleFonts.rajdhani(
              color: _kGoldLight, fontSize: 11, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progreso,
                backgroundColor: _kGoldDim.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation(_kGold),
                minHeight: 4,
              ),
            ),
          ),
        ]),
        const SizedBox(width: 8),
        Text(
          restanteStr,
          style: GoogleFonts.orbitron(
            color: _kGoldLight, fontSize: 10, fontWeight: FontWeight.w900),
        ),
      ]),
    );
  }

  // ==========================================================================
  // GLOBO 3D CON SELECTOR DE MODO
  // ==========================================================================
  Widget _buildGloboOverlay() {
    return AnimatedBuilder(
      animation: _globoAnim,
      builder: (_, __) {
        final angle = _globoAnim.value * math.pi * 2;
        return Stack(children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.1),
                radius: 1.2,
                colors: [Color(0xFF1A0F08), _kCosmicBg],
                stops: [0.0, 1.0],
              ),
            ),
          ),
          Positioned.fill(
              child: CustomPaint(
                  painter: _GlobePainter(angle: angle, goldColor: _kGold))),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.72,
                    colors: [
                      Colors.transparent,
                      _kCosmicBg.withValues(alpha: 0.55)
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 60, left: 0, right: 0,
            child: IgnorePointer(
              child: Column(children: [
                Text(
                  'CAMPO DE BATALLA EN VIVO',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.rajdhani(
                    fontSize: 9, fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: _kGold.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'RISK RUNNER',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cinzel(
                    fontSize: 22, fontWeight: FontWeight.w900,
                    letterSpacing: 3, color: _kGold,
                    shadows: [
                      Shadow(blurRadius: 28, color: _kGold.withValues(alpha: 0.35)),
                      Shadow(blurRadius: 60, color: _kTerracotta.withValues(alpha: 0.2)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          Positioned(
            top: 155, left: 12,
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_modoSolitario) ...[
                    _globoChip('🗺', '${_territorios.where((t) => t.esMio).length} mis zonas', _kGold),
                    const SizedBox(height: 7),
                    _globoChip('🌍', 'Explora y conquista', _kGoldLight),
                  ] else ...[
                    _globoChip('⚔️',
                        '${_territoriosNotificadosEnSesion.isNotEmpty ? _territoriosNotificadosEnSesion.length : "—"} invasiones',
                        _kTerracotta),
                    const SizedBox(height: 7),
                    _globoChip('🏃', '${_jugadoresActivos.length} activos ahora', _kWaterLight),
                    const SizedBox(height: 7),
                    _globoChip('🗺', '${_territorios.length} territorios', _kGoldLight),
                  ],
                  // ── NUEVO: mostrar reto activo en el globo si viene uno
                  if (_retoActivo != null) ...[
                    const SizedBox(height: 7),
                    _globoChip(
                      '⚡',
                      _retoActivo!['titulo'] as String? ?? 'Reto activo',
                      _kGold,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 148, left: 0, right: 0,
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _globoStat('${_territorios.where((t) => t.esMio).length}', 'MIS ZONAS', _kGold),
                    _globoStat('${_jugadoresActivos.length}', 'ACTIVOS', _kWaterLight),
                    _globoStat('${_territorios.length}', 'TERRITORIOS', _kGoldLight),
                    _globoStat('${_territoriosNotificadosEnSesion.length}⚔', 'EN GUERRA', _kTerracotta),
                  ],
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _globoChip(String emoji, String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: _kCosmicMid.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kGold.withValues(alpha: 0.22)),
          boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 7),
          Text(texto, style: GoogleFonts.rajdhani(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  Widget _globoStat(String valor, String label, Color color) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(valor, style: GoogleFonts.orbitron(
            fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.rajdhani(
            fontSize: 7, fontWeight: FontWeight.w700,
            letterSpacing: 1.8, color: _kGold.withValues(alpha: 0.4))),
      ]);

  Widget _buildMapbox() => mapbox.MapWidget(
        styleUri: _mapStyle,
        cameraOptions: mapbox.CameraOptions(
          center: mapbox.Point(
              coordinates: mapbox.Position(
                  _currentPosition?.longitude ?? -3.70325,
                  _currentPosition?.latitude  ?? 40.4167)),
          zoom:  _kZoomGlobo,
          pitch: _kPitchNormal,
        ),
        onMapCreated: _onMapCreated,
      );

  Widget _buildHUD() {
    if (!isTracking) return const SizedBox.shrink();
    if (_hudMinimizado && !isPaused) return _buildHUDMini();
    return FadeTransition(
      opacity: _hudFade,
      child: AnimatedBuilder(
        animation: _pulsoAnim,
        builder: (_, child) => Container(
          margin:  const EdgeInsets.fromLTRB(14, 50, 14, 0),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
          decoration: BoxDecoration(
            color: _kParchment.withValues(alpha: 0.93),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: _kGold.withValues(alpha: 0.18 + _pulso.value * 0.22),
                width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: _kGold.withValues(alpha: 0.10 + _pulso.value * 0.08),
                  blurRadius: 20, spreadRadius: 1),
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55), blurRadius: 10),
            ],
          ),
          child: child,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _hudStat('KM', _distanciaTotal.toStringAsFixed(2), _kGold),
          _hudDivider(),
          _hudStat('MIN/KM', _ritmoStr, _kWaterLight),
          _hudDivider(),
          _buildStatTimer(),
          if (_modoSolitario) ...[
            _hudDivider(),
            _hudStat('MODO', 'SOLO', _kVerde),
          ],
          if (_boostXpActivo) ...[
            _hudDivider(),
            _hudStat('BOOST', '×2', _kGoldLight),
          ],
        ]),
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
              boxShadow: [
                BoxShadow(color: _kGold.withValues(alpha: 0.10), blurRadius: 10)
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text(_distanciaTotal.toStringAsFixed(2),
                    style: GoogleFonts.orbitron(
                        color: _kGoldLight, fontWeight: FontWeight.w900, fontSize: 14)),
                Text(' km',
                    style: TextStyle(color: _kGold.withValues(alpha: 0.55), fontSize: 11)),
                Container(width: 1, height: 14, color: _kGoldDim.withValues(alpha: 0.4)),
                Text(_ritmoStr,
                    style: GoogleFonts.orbitron(
                        color: _kWaterLight, fontWeight: FontWeight.w900, fontSize: 14)),
                Text(' /km',
                    style: TextStyle(color: _kWater.withValues(alpha: 0.55), fontSize: 11)),
                if (_modoSolitario) ...[
                  Container(width: 1, height: 14, color: _kGoldDim.withValues(alpha: 0.4)),
                  Text('SOLO', style: GoogleFonts.rajdhani(
                      color: _kVerde, fontWeight: FontWeight.w900, fontSize: 11)),
                ],
                const Icon(Icons.expand_more_rounded, color: _kGoldDim, size: 15),
              ],
            ),
          ),
        ),
      );

  Widget _hudStat(String label, String valor, Color color) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: GoogleFonts.rajdhani(
            color: color.withValues(alpha: 0.7), fontSize: 8,
            fontWeight: FontWeight.w700, letterSpacing: 1.8)),
        const SizedBox(height: 4),
        Text(valor, style: GoogleFonts.orbitron(
            color: Colors.white, fontSize: valor.length > 5 ? 14 : 18,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: color.withValues(alpha: 0.55), blurRadius: 10)])),
      ]);

  Widget _hudDivider() =>
      Container(width: 1, height: 32, color: _kGoldDim.withValues(alpha: 0.35));

  Widget _buildStatTimer() => CustomTimer(
        controller: _timerController,
        builder: (state, remaining) {
          final str = isTracking
              ? '${remaining.hours}:${remaining.minutes}:${remaining.seconds}'
              : '--:--:--';
          return _hudStat('TIEMPO', str, isPaused ? _kGoldDim : _kWaterLight);
        },
      );

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
              '${remaining.hours}:${remaining.minutes}:${remaining.seconds}',
              style: GoogleFonts.orbitron(
                fontSize: 46, fontWeight: FontWeight.w900,
                color: Colors.white, letterSpacing: 2,
                shadows: const [
                  Shadow(blurRadius: 22, color: _kGold),
                  Shadow(blurRadius: 45, color: Color(0x66D4722A)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildAvatarOverlay() => Positioned(
        bottom: 140, left: 0, right: 0,
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _bounceAnim,
            builder: (_, __) => Transform.translate(
              offset: Offset(0, _bounceOffset.value),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_velocidadActualKmh > 1)
                  SizedBox(
                    width: 100, height: 28,
                    child: CustomPaint(
                        painter: _SpeedLinesPainter(color: _kTerracotta)),
                  ),
                Image.asset(
                  'assets/avatars/explorador.png',
                  width: 110, height: 110, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.directions_run_rounded, color: _kGold, size: 80),
                ),
                Container(
                  width: 52, height: 9,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    gradient: RadialGradient(
                        colors: [_kGold.withValues(alpha: 0.28), Colors.transparent]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _buildChips() {
    if (!isTracking) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_territoriosCargados)
        _chip('${_territorios.length} territorios', _kGold, '🗺'),
      if (!_modoSolitario && _jugadoresActivos.isNotEmpty) ...[
        const SizedBox(height: 8),
        _chip('${_jugadoresActivos.length} cerca', _kWater, '🏃'),
      ],
      if (_territoriosVisitadosEnSesion.isNotEmpty) ...[
        const SizedBox(height: 8),
        _chip('${_territoriosVisitadosEnSesion.length} reforzados', _kVerde, '🛡'),
      ],
      if (!_modoSolitario && _territoriosNotificadosEnSesion.isNotEmpty) ...[
        const SizedBox(height: 8),
        _chip('${_territoriosNotificadosEnSesion.length} invadidos', _kTerracotta, '⚔'),
      ],
    ]);
  }

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
          Text(texto, style: GoogleFonts.rajdhani(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _buildBotonesMapa() => Column(children: [
        _botonMapa(_modoNoche ? '🌙' : '☀️',
            _modoNoche ? _kGoldLight : _kGold, _toggleModoNoche),
        if (isTracking) ...[
          const SizedBox(height: 10),
          _botonMapa('🎯', _kTerracotta, () {
            if (_currentPosition != null) {
              _moverCamara(
                lat:     _currentPosition!.latitude,
                lng:     _currentPosition!.longitude,
                zoom:    _kZoomCorrer,
                pitch:   _kPitchCorrer,
                bearing: _bearing,
                forzar:  true,
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
                    _cuentaAtras > 0 ? '$_cuentaAtras'
                        : (_modoSolitario ? '🗺️' : '⚔️'),
                    style: GoogleFonts.cinzel(
                      fontSize: 96, fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: const [
                        Shadow(blurRadius: 35, color: _kGold),
                        Shadow(blurRadius: 70, color: _kTerracotta),
                        Shadow(blurRadius: 6, color: Colors.black),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 6),
                    decoration: BoxDecoration(
                      color: _kParchment.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _kGoldDim),
                      boxShadow: [BoxShadow(
                          color: _kGold.withValues(alpha: 0.2), blurRadius: 14)],
                    ),
                    child: Text(
                      _cuentaAtras > 0 ? 'PREPÁRATE'
                          : (_modoSolitario ? '¡A EXPLORAR!' : '¡A CONQUISTAR!'),
                      style: GoogleFonts.cinzel(
                        color: _kGoldLight, fontSize: 13,
                        fontWeight: FontWeight.w700, letterSpacing: 3.5,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _buildBotonera() => Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 38),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: [
              (!isTracking ? _kCosmicMid : _kParchment).withValues(alpha: 0.97),
              (!isTracking ? _kCosmicMid : _kParchment).withValues(alpha: 0.72),
              Colors.transparent,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          top: false,
          child: !isTracking ? _buildSelectorModo() : _buildBotonesControl(),
        ),
      );

  Widget _buildSelectorModo() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: _kParchMid.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kGoldDim.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _modoSolitario = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_modoSolitario
                      ? _kGoldDim.withValues(alpha: 0.5) : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(13)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('⚔️', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 4),
                  Text('COMPETITIVO', style: GoogleFonts.rajdhani(
                      fontSize: 10, fontWeight: FontWeight.w900,
                      color: !_modoSolitario ? _kGoldLight : _kGoldDim,
                      letterSpacing: 1.5)),
                  Text('Conquista rivales', style: GoogleFonts.rajdhani(
                      fontSize: 8, color: _kGoldDim.withValues(alpha: 0.7))),
                ]),
              ),
            ),
          ),
          Container(width: 1, height: 50, color: _kGoldDim.withValues(alpha: 0.3)),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _modoSolitario = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _modoSolitario
                      ? _kVerde.withValues(alpha: 0.25) : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(13)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🗺️', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 4),
                  Text('SOLITARIO', style: GoogleFonts.rajdhani(
                      fontSize: 10, fontWeight: FontWeight.w900,
                      color: _modoSolitario ? _kVerde : _kGoldDim,
                      letterSpacing: 1.5)),
                  Text('Explora tu ciudad', style: GoogleFonts.rajdhani(
                      fontSize: 8, color: _kGoldDim.withValues(alpha: 0.7))),
                ]),
              ),
            ),
          ),
        ]),
      ),

      if (SubscriptionService.estilosMapaActivos) ...[
        _buildSelectorEstiloMapa(),
        const SizedBox(height: 14),
      ],

      GestureDetector(
        onTap: _mostrandoCuentaAtras ? null : _iniciarCuentaAtras,
        child: AnimatedBuilder(
          animation: _pulsoAnim,
          builder: (_, child) => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 20),
            decoration: BoxDecoration(
              gradient: _modoSolitario
                  ? LinearGradient(colors: [
                      const Color(0xFF1A4A1A),
                      _kVerde.withValues(alpha: 0.8),
                      const Color(0xFF2A6A2A),
                    ], begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : const LinearGradient(colors: [
                      Color(0xFF7A4A00), Color(0xFFD4A84C), Color(0xFFD4722A),
                    ], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: (_modoSolitario ? _kVerde : _kGoldLight)
                    .withValues(alpha: 0.35 + _pulso.value * 0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (_modoSolitario ? _kVerde : _kGold)
                      .withValues(alpha: 0.12 + _pulso.value * 0.28),
                  blurRadius: 24, spreadRadius: 2, offset: const Offset(0, 5),
                ),
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35), blurRadius: 8),
              ],
            ),
            child: child,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_modoSolitario ? '🗺️' : '🏴',
                style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Text(
              _modoSolitario ? 'EXPLORAR' : 'CONQUISTAR',
              style: GoogleFonts.cinzel(
                fontSize: 16,
                color: _modoSolitario ? Colors.white : _kInk,
                fontWeight: FontWeight.w900, letterSpacing: 2.5,
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildSelectorEstiloMapa() {
    final estilos = [
      {'id': 'normal',   'emoji': '🗺️', 'label': 'Normal'},
      {'id': 'satelite', 'emoji': '🛰️', 'label': 'Satélite'},
      {'id': 'militar',  'emoji': '🎖️', 'label': 'Militar'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Row(children: [
            const Text('👑', style: TextStyle(fontSize: 10)),
            const SizedBox(width: 5),
            Text('ESTILO DE MAPA', style: GoogleFonts.rajdhani(
                color: _kGoldDim, fontSize: 9,
                fontWeight: FontWeight.w800, letterSpacing: 2)),
          ]),
        ),
        Container(
          decoration: BoxDecoration(
            color: _kParchMid.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kGoldDim.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: estilos.map((e) {
              final selected = _estiloMapa == e['id'];
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (_estiloMapa == e['id']) return;
                    setState(() => _estiloMapa = e['id'] as String);
                    final uri = _mapUriParaEstilo(e['id'] as String);
                    _mapboxMap?.loadStyleURI(uri);
                    _buildings3dCreated       = false;
                    _territoriosLayersCreated = false;
                    Future.delayed(const Duration(milliseconds: 800), () {
                      if (!mounted) return;
                      _addBuildings3D();
                      _configurarAtmosfera();
                      _dibujarTerritoriosEnMapa();
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? _kGoldDim.withValues(alpha: 0.45) : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(e['emoji'] as String,
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(e['label'] as String,
                          style: GoogleFonts.rajdhani(
                              fontSize: 9, fontWeight: FontWeight.w700,
                              color: selected ? _kGoldLight : _kGoldDim,
                              letterSpacing: 0.5)),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _mapUriParaEstilo(String estilo) {
    switch (estilo) {
      case 'satelite': return mapbox.MapboxStyles.SATELLITE_STREETS;
      case 'militar':  return mapbox.MapboxStyles.DARK;
      default:
        return _modoNoche ? mapbox.MapboxStyles.DARK : _kEstiloPersonalizado;
    }
  }

  Widget _buildBotonesControl() => Row(children: [
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
            child: Center(
              child: Text(isPaused ? '▶️' : '⏸️',
                  style: const TextStyle(fontSize: 26)),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: GestureDetector(
            onTap: stopTracking,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 19),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF5C1200), Color(0xFFB84020)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _kTerracotta.withValues(alpha: 0.35), width: 1),
                boxShadow: [
                  BoxShadow(color: _kTerracotta.withValues(alpha: 0.38),
                      blurRadius: 16, offset: const Offset(0, 4)),
                  BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_modoSolitario ? '🏁' : '🏳️',
                      style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Text(
                    _modoSolitario ? 'FINALIZAR' : 'RETIRADA',
                    style: GoogleFonts.cinzel(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: const Color(0xFFFFE0C0), letterSpacing: 2.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]);
}

// =============================================================================
// GLOBO 3D CUSTOM PAINTER
// =============================================================================
class _GlobePainter extends CustomPainter {
  final double angle;
  final Color  goldColor;
  const _GlobePainter({required this.angle, required this.goldColor});

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height;
    final cx = W / 2, cy = H * 0.50;
    final r  = math.min(W, H) * 0.38;

    const starData = [
      [0.07, 0.10], [0.18, 0.19], [0.91, 0.16], [0.95, 0.36],
      [0.06, 0.43], [0.97, 0.58], [0.05, 0.75], [0.94, 0.90],
      [0.53, 0.96], [0.83, 0.07], [0.28, 0.57], [0.12, 0.88],
      [0.76, 0.31], [0.62, 0.14], [0.38, 0.82],
    ];
    for (int i = 0; i < starData.length; i++) {
      final sx      = starData[i][0] * W;
      final sy      = starData[i][1] * H;
      final twinkle = 0.3 + 0.4 * math.sin(angle * 3 + i * 0.8);
      canvas.drawCircle(Offset(sx, sy), i % 3 == 0 ? 1.5 : 0.9,
          Paint()..color = goldColor.withValues(alpha: twinkle * 0.6));
    }

    canvas.drawCircle(Offset(cx, cy), r * 1.45,
        Paint()..shader = RadialGradient(
          center: Alignment.center, radius: 1.0,
          colors: [goldColor.withValues(alpha: 0.04), Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.45)));
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()..shader = const RadialGradient(
          center: Alignment(-0.45, -0.45), radius: 1.0,
          colors: [Color(0xFF2E2010), Color(0xFF1A1008), Color(0xFF060302)],
          stops: [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(0, 0), radius: r)));
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()
          ..color = goldColor.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke..strokeWidth = 1.2);

    canvas.save();
    final clipCircle = ui.Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r - 1));
    canvas.clipPath(clipCircle);
    final gridPaint = Paint()
      ..color = goldColor.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke..strokeWidth = 0.7;
    for (int i = 0; i < 10; i++) {
      final a  = i / 10 * math.pi * 2 + angle;
      final rx = r * math.max(0.01, math.cos(a).abs());
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: r * 2),
          gridPaint);
    }
    for (int lat = 1; lat < 6; lat++) {
      final yOff = cy + r * math.cos(lat / 5 * math.pi);
      final rr   = r * math.max(0.01, math.sin(lat / 5 * math.pi).abs());
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, yOff), width: rr * 2, height: rr * 0.28),
          gridPaint);
    }
    canvas.restore();

    final continenteDefs = [
      _ContinenteDef(angle * 0.25, [
        Offset(-30, -95), Offset(-10, -70), Offset(-20, -35), Offset(-40, -5),
        Offset(-55, 55), Offset(-60, 105), Offset(-42, 95), Offset(-28, 32),
        Offset(-38, -28), Offset(-15, -60),
      ], goldColor.withValues(alpha: 0.30)),
      _ContinenteDef(angle * 0.22, [
        Offset(-95, -85), Offset(-75, -60), Offset(-88, -12), Offset(-105, 62),
        Offset(-120, 110), Offset(-128, 78), Offset(-110, 8), Offset(-96, -52),
      ], goldColor.withValues(alpha: 0.25)),
      _ContinenteDef(angle * 0.28, [
        Offset(15, -90), Offset(72, -78), Offset(105, -48),
        Offset(98, -12), Offset(52, 12), Offset(22, -22),
      ], goldColor.withValues(alpha: 0.22)),
    ];
    for (final def in continenteDefs) {
      canvas.save();
      final clipC = ui.Path()
        ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r - 1));
      canvas.clipPath(clipC);
      final cosR = math.cos(def.rot), sinR = math.sin(def.rot);
      final contPath = ui.Path();
      final transformed = def.pts.map((p) => Offset(
            cx + p.dx * cosR - p.dy * sinR,
            cy + p.dx * sinR + p.dy * cosR,
          )).toList();
      contPath.moveTo(transformed[0].dx, transformed[0].dy);
      for (int i = 1; i < transformed.length; i++) {
        contPath.lineTo(transformed[i].dx, transformed[i].dy);
      }
      contPath.close();
      canvas.drawPath(contPath,
          Paint()..color = def.color..style = PaintingStyle.fill);
      canvas.restore();
    }

    final dotsList = [
      _DotDef(cx - 28, cy - 58, const Color(0xFFCC2222), 5.0),
      _DotDef(cx + 22, cy - 72, const Color(0xFFD4A84C), 4.0),
      _DotDef(cx - 88, cy + 25, const Color(0xFFCC2222), 3.5),
      _DotDef(cx + 50, cy + 20, const Color(0xFF8ECFCC), 4.0),
      _DotDef(cx - 50, cy + 78, const Color(0xFFEDD98A), 3.0),
    ];
    for (int i = 0; i < dotsList.length; i++) {
      final d     = dotsList[i];
      final pulse = d.r + 3 + math.sin(angle * 4 + i) * 2.5;
      canvas.drawCircle(Offset(d.x, d.y), pulse * 2.5,
          Paint()..color = d.color.withValues(alpha: 0.10));
      canvas.drawCircle(Offset(d.x, d.y), d.r, Paint()..color = d.color);
      canvas.drawCircle(Offset(d.x, d.y), pulse,
          Paint()
            ..color = d.color.withValues(alpha: 0.28)
            ..style = PaintingStyle.stroke..strokeWidth = 1.0);
    }
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()..shader = RadialGradient(
          center: const Alignment(-0.55, -0.55), radius: 0.7,
          colors: [Colors.white.withValues(alpha: 0.05), Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)));
  }

  @override
  bool shouldRepaint(_GlobePainter old) =>
      old.angle != angle || old.goldColor != goldColor;
}

class _ContinenteDef {
  final double       rot;
  final List<Offset> pts;
  final Color        color;
  const _ContinenteDef(this.rot, this.pts, this.color);
}

class _DotDef {
  final double x, y, r;
  final Color  color;
  const _DotDef(this.x, this.y, this.color, this.r);
}

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