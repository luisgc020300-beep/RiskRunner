import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:custom_timer/custom_timer.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../services/territory_service.dart';
import 'fullscreen_map_screen.dart';
import '../services/anticheat_service.dart';
import '../services/stats_service.dart';
import '../services/subscription_service.dart';
import '../widgets/conquista_overlay.dart';
import '../widgets/anticheat_warning_overlay.dart';
import '../widgets/narrador_overlay.dart';
import '../services/narrador_service.dart';
import '../services/desafios_service.dart';

// =============================================================================
// PALETA
// =============================================================================
// Colores fijos (no cambian con el tema)
const _kGold       = Color(0xFFFFD60A);
const _kGoldLight  = Color(0xFFFFD60A);
const _kWater      = Color(0xFF5BA3A0);
const _kWaterLight = Color(0xFF8ECFCC);
const _kVerde      = Color(0xFF8FAF4A);

// Paleta adaptativa dark / light
class _LP {
  final Color ink, parchment, parchMid, cosmicBg, cosmicMid, goldDim, terracotta, globalRed;
  const _LP._({
    required this.ink,        required this.parchment,
    required this.parchMid,   required this.cosmicBg,
    required this.cosmicMid,  required this.goldDim,
    required this.terracotta, required this.globalRed,
  });
  static const light = _LP._(
    ink:        Color(0xFF1C1C1E),
    parchment:  Color(0xFFFFFFFF),
    parchMid:   Color(0xFFE5E5EA),
    cosmicBg:   Color(0xFFE8E8ED),
    cosmicMid:  Color(0xFFFFFFFF),
    goldDim:    Color(0xFFAEAEB2),
    terracotta: Color(0xFF636366),
    globalRed:  Color(0xFF636366),
  );
  static const dark = _LP._(
    ink:        Color(0xFFEEEEEE),
    parchment:  Color(0xFF1C1C1E),
    parchMid:   Color(0xFF2C2C2E),
    cosmicBg:   Color(0xFF090807),
    cosmicMid:  Color(0xFF1C1C1E),
    goldDim:    Color(0xFF636366),
    terracotta: Color(0xFF8E8E93),
    globalRed:  Color(0xFF8E8E93),
  );
  static _LP of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? dark : light;
}

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

// Cache limitado a 50 entradas para evitar memory leak en sesiones largas
final Map<int, Uint8List> _avatarCache = {};
const int _kAvatarCacheMax = 50;

// =============================================================================
// MODELO BARRIO
// =============================================================================
class _BarrioData {
  final String       nombre;
  final List<LatLng> puntos;
  final double       areaM2;
  double             porcentajeCubierto;

  _BarrioData({
    required this.nombre,
    required this.puntos,
    required this.areaM2,
    this.porcentajeCubierto = 0.0,
  });

  LatLng get centro {
    final lat = puntos.map((p) => p.latitude).reduce((a, b) => a + b)  / puntos.length;
    final lng = puntos.map((p) => p.longitude).reduce((a, b) => a + b) / puntos.length;
    return LatLng(lat, lng);
  }
}

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

  _LP get _p => _LP.of(context);

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
  // Anotaciones de corona para territorios con Rey
  final Map<String, mapbox.PointAnnotation> _anotacionesReyes = {};
  Uint8List? _coronaBytes;

  // ── GPS
  List<TerritoryData> _territoriosRivalesCercanos = [];
  TerritoryData? _territorioActualBajoPie;
  List<LatLng> routePoints           = [];
  bool isTracking                    = false;
  bool isPaused                      = false;
  double _distanciaTotal             = 0.0;
  double _velocidadActualKmh         = 0.0;
  double _bearing                    = 0.0;
  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;
  Position? _ultimaPosicionVelocidad;

  // ── Barrios OSM (modo solitario)
  List<_BarrioData> _barriosCercanos   = [];
  _BarrioData?      _barrioActual;
  bool              _cargandoBarrios   = false;
  bool              _barriosCargados   = false;
  static const String _barrioSourceId     = 'barrios-source';
  static const String _barrioFillLayerId  = 'barrios-fill';
  static const String _barrioLineLayerId  = 'barrios-line';
  static const String _barrioLabelLayerId = 'barrios-label';
  bool _barriosLayerCreated            = false;

  int _puntosDesdeUltimoUpdate       = 0;
  static const int _kActualizarMapaCadaN = 3;
  DateTime _ultimoMovCamara = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kMinMsCamara = 800;

  // ── Modo de juego
  bool _modoSolitario = false;

  // ── Jugador
  Color  _colorTerritorio      = const Color(0xFF636366);
  List<TerritoryData> _territorios     = [];
  bool   _territoriosCargados  = false;
  bool   _fantasmasCargando    = false;
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
  static const String _routeSourceId       = 'route-source';
  static const String _routeLayerId        = 'route-layer';
  static const String _buildingsLayerId    = 'buildings-3d';
  static const String _fillLayerId         = 'territorios-fill';
  static const String _fillInnerLayerId    = 'territorios-fill-inner';
  static const String _borderLayerId       = 'territorios-border';
  static const String _borderPulseLayerId  = 'territorios-border-pulse';
  static const String _sourceId            = 'territorios-source';
  static const String _centrosSourceId     = 'territorios-centros-source';
  static const String _centrosLayerId      = 'territorios-centros-layer';
  static const String _kTileUrl =
      'https://api.mapbox.com/styles/v1/luiisgoomezz1/cmmdzh1aj00f501r68crag5gv'
      '/tiles/256/{z}/{x}/{y}@2x?access_token='
      'pk.eyJ1IjoibHVpaXNnb29tZXp6MSIsImEiOiJjbW1mNDVoajkwNGNyMnBzNTBiaXNrMm5pIn0.gzN772_GMDx55owCXwsozA';

  bool _routeLayerCreated       = false;
  bool _buildings3dCreated      = false;
  bool _territoriosLayersCreated = false;
  bool _centrosLayerCreated     = false;

  // Web fallback (flutter_map)
  MapController? _webMapCtrl;

  Timer? _pulsoTimer;
  double _pulsoOpacity = 0.9;
  bool   _pulsoUp      = false;

  // ── Narrador
  final NarradorService _narrador = NarradorService();
  MensajeNarrador? _mensajeNarrador;
  double _distanciaUltimoAnalisisRitmo  = 0;
  int    _minutosResistenciaNotificados = 0;
  Timer? _timerResistencia;

  // ── Reto activo desde Home
  Map<String, dynamic>? _retoActivo;
  bool _retoCompletado = false;

  // ── GUERRA GLOBAL — estado del objetivo de conquista
  Map<String, dynamic>? _objetivoGlobal;
  bool _globalConquistado   = false;
  bool _globalConquistando  = false;
  bool _globalKmAlcanzados  = false;
  double? _nuevaClausula;
  StreamSubscription<DocumentSnapshot>? _globalTerritoryStream;
  String? _globalTerritoryLastOwner;
  // FIX: guard contra doble tap en stopTracking
  bool _stopping = false;

  // ==========================================================================
  // INIT / DISPOSE
  // ==========================================================================
  @override
  void initState() {
    super.initState();
    _modoNoche = _esHoraNoche();

    StatsService.mapboxToken =
        'pk.eyJ1IjoibHVpaXNnb29tZXp6MSIsImEiOiJjbW1mNDVoajkwNGNyMnBzNTBiaXNrMm5pIn0.gzN772_GMDx55owCXwsozA';

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
        vsync: this, duration: const Duration(seconds: 90))
      ..repeat()
      ..addListener(_rotarGlobo);

    _determinePosition();
    _cargarDatosIniciales();
    _escucharJugadoresActivos();

    _narrador.onMensaje = (msg) {
      if (mounted) setState(() => _mensajeNarrador = msg);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args == null) return;

      if (args['retoActivo'] != null) {
        final reto = args['retoActivo'] as Map<String, dynamic>;
        setState(() => _retoActivo = reto);
        final titulo         = reto['titulo'] as String? ?? 'Reto';
        final objetivoMetros =
            (reto['objetivo_valor'] as num?)?.toDouble() ?? 0;
        _narrador.configurarReto(titulo, objetivoMetros);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _narrador.anunciarReto(titulo);
        });
      }

      if (args['objetivoGlobal'] != null) {
        final objetivo = args['objetivoGlobal'] as Map<String, dynamic>;
        setState(() {
          _objetivoGlobal     = objetivo;
          _globalConquistado  = false;
          _globalConquistando = false;
          _modoSolitario      = false;
        });
        final nombre = objetivo['territorioNombre'] as String? ?? 'Territorio';
        final kmReq  = (objetivo['kmRequeridos'] as num?)?.toDouble() ?? 0;
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _narrador.anunciarReto(
                '⚔️ Objetivo: conquistar $nombre — ${kmReq.toStringAsFixed(1)} km');
          }
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
    _globalTerritoryStream?.cancel();
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
  void _rotarGlobo() {
    if (isTracking) return;
    if (kIsWeb) return; // flutter_map no soporta bearing continuo
    if (_mapboxMap == null) return;
    final bearing = _globoAnim.value * 360.0;
    _mapboxMap!.setCamera(mapbox.CameraOptions(bearing: bearing));
  }

  bool _esHoraNoche() {
    final h = DateTime.now().hour;
    return h >= 21 || h < 6;
  }

  void _toggleModoNoche() {
    setState(() { _modoManual = true; _modoNoche = !_modoNoche; });
    if (_estiloMapa == 'normal') {
      _mapboxMap?.loadStyleURI(_mapStyle);
    }
    _buildings3dCreated       = false;
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
      // Intentar posición rápida para el query global; si no hay, el service
      // carga solo los territorios propios como fallback.
      LatLng? centro;
      if (_currentPosition != null) {
        centro = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      } else {
        try {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) centro = LatLng(last.latitude, last.longitude);
        } catch (_) {}
      }

      final lista = await TerritoryService.cargarTodosLosTerritorios(
          centro: centro, modo: _modoSolitario ? 'solitario' : 'competitivo');
      if (mounted) {
        setState(() { _territorios = lista; _territoriosCargados = true; });
        _dibujarTerritoriosEnMapa();
        _aplicarTerritoriosFantasma();
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
      if (mounted) {
        final anteriorCentro = _currentPosition;
        setState(() => _currentPosition = pos);

        // Si la posición difiere >500 m de la usada al cargar, recargar territorios
        final debeCargarse = anteriorCentro == null ||
            Geolocator.distanceBetween(anteriorCentro.latitude,
                anteriorCentro.longitude, pos.latitude, pos.longitude) > 500;

        if (debeCargarse && _territoriosCargados) {
          TerritoryService.invalidarCache();
          final centro = LatLng(pos.latitude, pos.longitude);
          final lista  = await TerritoryService.cargarTodosLosTerritorios(
              centro: centro, modo: _modoSolitario ? 'solitario' : 'competitivo');
          if (mounted) {
            setState(() => _territorios = lista);
            _dibujarTerritoriosEnMapa();
          }
        }
        _aplicarTerritoriosFantasma();
      }
    }
  }

  // ==========================================================================
  // BARRIOS OSM — modo solitario
  // ==========================================================================
  Future<void> _cargarBarriosOSM(LatLng pos) async {
    if (_cargandoBarrios || _barriosCargados) return;
    _cargandoBarrios = true;

    try {
      final lat   = pos.latitude;
      final lng   = pos.longitude;
      const delta = 0.12; // ~13 km — suficiente para capturar municipios cercanos

      final url = Uri.parse(
        'https://overpass-api.de/api/interpreter?data='
        '[out:json][timeout:25];'
        '('
        '  relation["boundary"="administrative"]["admin_level"="8"]'
        '    (${lat - delta},${lng - delta},${lat + delta},${lng + delta});'
        ');'
        'out geom;',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;

      final jsonData  = jsonDecode(response.body) as Map<String, dynamic>;
      final elements  = (jsonData['elements'] as List<dynamic>? ?? []);
      final List<_BarrioData> barrios = [];

      for (final el in elements) {
        final tags   = el['tags'] as Map<String, dynamic>? ?? {};
        final nombre = (tags['name'] as String?)?.trim() ?? '';
        if (nombre.isEmpty) continue;

        List<LatLng> puntos = [];

        if (el['type'] == 'way') {
          final geometry = el['geometry'] as List<dynamic>? ?? [];
          puntos = geometry.map((g) {
            final m = g as Map<String, dynamic>;
            return LatLng(
              (m['lat'] as num).toDouble(),
              (m['lon'] as num).toDouble(),
            );
          }).toList();
        } else if (el['type'] == 'relation') {
          final members = el['members'] as List<dynamic>? ?? [];
          for (final member in members) {
            final m = member as Map<String, dynamic>;
            if (m['role'] == 'outer' && m['geometry'] != null) {
              final geom = m['geometry'] as List<dynamic>;
              puntos = geom.map((g) {
                final gm = g as Map<String, dynamic>;
                return LatLng(
                  (gm['lat'] as num).toDouble(),
                  (gm['lon'] as num).toDouble(),
                );
              }).toList();
              break;
            }
          }
        }

        if (puntos.length < 4) continue;
        final area = TerritoryService.calcularAreaM2(puntos);
        if (area < 10000) continue;

        barrios.add(_BarrioData(nombre: nombre, puntos: puntos, areaM2: area));
      }

      if (!mounted) return;

      // Calcular porcentaje inicial
      final misTerritorios = _territorios.where((t) => t.esMio).toList();
      for (final barrio in barrios) {
        barrio.porcentajeCubierto =
            _calcularPorcentajeBarrio(barrio, misTerritorios);
      }

      // Ordenar por distancia
      barrios.sort((a, b) {
        final dA = Geolocator.distanceBetween(
            lat, lng, a.centro.latitude, a.centro.longitude);
        final dB = Geolocator.distanceBetween(
            lat, lng, b.centro.latitude, b.centro.longitude);
        return dA.compareTo(dB);
      });

      setState(() {
        _barriosCercanos = barrios;
        _barrioActual    = barrios.isNotEmpty ? barrios.first : null;
        _barriosCargados = true;
      });

      await _dibujarBarriosEnMapa();

    } catch (e) {
      debugPrint('Error cargando barrios OSM: $e');
    } finally {
      _cargandoBarrios = false;
    }
  }

  double _calcularPorcentajeBarrio(
      _BarrioData barrio, List<TerritoryData> misTerritorios) {
    if (barrio.areaM2 <= 0) return 0.0;
    double areaCubierta = 0.0;
    for (final ter in misTerritorios) {
      // Si el centro del territorio está dentro del barrio, sumamos su área
      if (_puntoEnPoligono(ter.centro, barrio.puntos)) {
        areaCubierta += TerritoryService.calcularAreaM2(ter.puntos);
      }
    }
    return (areaCubierta / barrio.areaM2).clamp(0.0, 1.0);
  }

  Future<void> _dibujarBarriosEnMapa() async {
    if (_mapboxMap == null || _barriosCercanos.isEmpty) return;
    if (!_modoSolitario) return;

    final features = _barriosCercanos.map((b) {
      final coords = b.puntos.map((p) => [p.longitude, p.latitude]).toList();
      if (coords.first[0] != coords.last[0] ||
          coords.first[1] != coords.last[1]) {
        coords.add(coords.first);
      }
      final pct = b.porcentajeCubierto;
      final String color = pct >= 1.0
          ? '#30D158'   // verde — zona completa
          : pct > 0
              ? '#FF9500' // naranja — en progreso
              : '#8E8E93'; // gris   — sin explorar
      final String label = pct >= 1.0
          ? '${b.nombre} ✓'
          : pct > 0
              ? '${b.nombre} ${(pct * 100).toInt()}%'
              : b.nombre;

      return _encodeJson({
        'type': 'Feature',
        'properties': {
          'nombre':     b.nombre,
          'label':      label,
          'color':      color,
          'porcentaje': (pct * 100).toInt(),
        },
        'geometry': {'type': 'Polygon', 'coordinates': [coords]},
      });
    }).join(',');

    final geojson = '{"type":"FeatureCollection","features":[$features]}';

    try {
      if (_barriosLayerCreated) {
        final src = await _mapboxMap!.style
            .getSource(_barrioSourceId) as mapbox.GeoJsonSource?;
        await src?.updateGeoJSON(geojson);
        return;
      }

      for (final id in [_barrioLabelLayerId, _barrioLineLayerId, _barrioFillLayerId]) {
        try { await _mapboxMap!.style.removeStyleLayer(id); } catch (_) {}
      }
      try { await _mapboxMap!.style.removeStyleSource(_barrioSourceId); } catch (_) {}

      await _mapboxMap!.style.addSource(
          mapbox.GeoJsonSource(id: _barrioSourceId, data: geojson));

      // Relleno semitransparente
      await _mapboxMap!.style.addLayer(
          mapbox.FillLayer(id: _barrioFillLayerId, sourceId: _barrioSourceId));
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioFillLayerId, 'fill-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioFillLayerId, 'fill-opacity', 0.12);

      // Borde — sólido y visible
      await _mapboxMap!.style.addLayer(
          mapbox.LineLayer(id: _barrioLineLayerId, sourceId: _barrioSourceId));
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLineLayerId, 'line-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLineLayerId, 'line-width', 2.0);
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLineLayerId, 'line-opacity', 0.75);

      // Etiqueta: nombre + porcentaje
      await _mapboxMap!.style.addLayer(
          mapbox.SymbolLayer(id: _barrioLabelLayerId, sourceId: _barrioSourceId));
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLabelLayerId, 'text-field', ['get', 'label']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLabelLayerId, 'text-size', 11.0);
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLabelLayerId, 'text-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLabelLayerId, 'text-halo-color', 'rgba(0,0,0,0.8)');
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLabelLayerId, 'text-halo-width', 1.5);
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLabelLayerId, 'text-font', ['DIN Pro Medium', 'Arial Unicode MS Regular']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLabelLayerId, 'text-anchor', 'center');
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLabelLayerId, 'text-max-width', 8.0);
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLabelLayerId, 'symbol-placement', 'point');

      _barriosLayerCreated = true;
    } catch (e) {
      debugPrint('Error dibujando barrios: $e');
    }
  }

  Future<void> _limpiarCapasBarrios() async {
    if (!_barriosLayerCreated || _mapboxMap == null) return;
    for (final id in [_barrioLabelLayerId, _barrioLineLayerId, _barrioFillLayerId]) {
      try { await _mapboxMap!.style.removeStyleLayer(id); } catch (_) {}
    }
    try { await _mapboxMap!.style.removeStyleSource(_barrioSourceId); } catch (_) {}
    _barriosLayerCreated = false;
  }

  Future<void> _verificarBarriosCompletados() async {
    if (!_modoSolitario || _barriosCercanos.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final misTerritorios = _territorios.where((t) => t.esMio).toList();

    for (final barrio in _barriosCercanos) {
      final pctAntes = barrio.porcentajeCubierto;
      final pctAhora = _calcularPorcentajeBarrio(barrio, misTerritorios);
      barrio.porcentajeCubierto = pctAhora;

      if (pctAhora >= 1.0 && pctAntes < 1.0) {
        final bonusMonedas = _calcularBonusBarrio(barrio);
        try {
          await FirebaseFirestore.instance
              .collection('players')
              .doc(user.uid)
              .update({'monedas': FieldValue.increment(bonusMonedas)});

          await FirebaseFirestore.instance
              .collection('notifications')
              .add({
            'toUserId':     user.uid,
            'type':         'barrio_completado',
            'message':      '🏆 ¡Has conquistado el barrio de ${barrio.nombre}! +$bonusMonedas 🪙',
            'read':         false,
            'timestamp':    FieldValue.serverTimestamp(),
            'barrioNombre': barrio.nombre,
            'bonusMonedas': bonusMonedas,
          });
        } catch (e) {
          debugPrint('Error dando bonus barrio: $e');
        }

        if (mounted) _mostrarNotificacionBarrioCompletado(barrio, bonusMonedas);
      }
    }

    await _dibujarBarriosEnMapa();
  }

  int _calcularBonusBarrio(_BarrioData barrio) {
    if (barrio.areaM2 > 2000000) return 1000;
    if (barrio.areaM2 > 50000)   return 600;
    return 300;
  }

  // ==========================================================================
  // MAPBOX
  // ==========================================================================
  void _onMapCreated(mapbox.MapboxMap map) async {
    _mapboxMap = map;
    await map.style.setProjection(
        mapbox.StyleProjection(name: mapbox.StyleProjectionName.globe));
    await map.gestures.updateSettings(mapbox.GesturesSettings(
      rotateEnabled: true,
      pitchEnabled: false,
      scrollEnabled: true,
      pinchToZoomEnabled: true,
      doubleTapToZoomInEnabled: true,
    ));
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
    if (kIsWeb) {
      final ctrl = _webMapCtrl;
      if (ctrl == null) return;
      ctrl.move(LatLng(lat, lng), zoom ?? ctrl.camera.zoom);
      return;
    }
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
      try { await _mapboxMap!.style.removeStyleLayer(_buildingsLayerId); } catch (_) {}
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

  // ── Territorios fantasma ─────────────────────────────────────────────────
  // El query global ya incluye los fantasmas de Firestore en _territorios.
  // Este método solo comprueba si hay que CREAR más (mapa escaso) y, si los
  // crea, invalida el caché y recarga para que aparezcan.
  Future<void> _aplicarTerritoriosFantasma() async {
    if (_modoSolitario) {
      final sinF = _territorios.where((t) => !t.esFantasma).toList();
      if (sinF.length != _territorios.length) {
        if (mounted) setState(() => _territorios = sinF);
        _dibujarTerritoriosEnMapa();
      }
      return;
    }
    if (_currentPosition == null || !_territoriosCargados) return;
    if (_fantasmasCargando) return;

    _fantasmasCargando = true;
    try {
      final centro = LatLng(
          _currentPosition!.latitude, _currentPosition!.longitude);

      const double radioVisible = 0.022; // ~2.4 km
      const int    kUmbral      = 18;

      // Contar territorios reales (no bot) ya cargados cerca
      final realesCercanos = _territorios.where((t) =>
        !t.esFantasma &&
        (t.centro.latitude  - centro.latitude).abs()  < radioVisible &&
        (t.centro.longitude - centro.longitude).abs() < radioVisible,
      ).length;

      // Contar fantasmas ya presentes en _territorios
      final fantasmasCercanos = _territorios.where((t) =>
        t.esFantasma &&
        (t.centro.latitude  - centro.latitude).abs()  < radioVisible &&
        (t.centro.longitude - centro.longitude).abs() < radioVisible,
      ).length;

      final faltan = kUmbral - realesCercanos - fantasmasCercanos;
      if (faltan <= 0) return; // ya hay suficientes

      // Crear los que faltan y recargar el mapa
      await TerritoryService.crearTerritoriosFantasmaEnZona(
        centro:          centro,
        todosExistentes: _territorios,
        max:             faltan,
      );
      // crearTerritoriosFantasmaEnZona ya invalida el caché
      final lista = await TerritoryService.cargarTodosLosTerritorios(
          centro: centro, modo: 'competitivo');
      if (mounted) {
        setState(() => _territorios = lista);
        _dibujarTerritoriosEnMapa();
      }
    } catch (e) {
      debugPrint('Error gestionando fantasmas: $e');
    } finally {
      _fantasmasCargando = false;
    }
  }

  Future<void> _dibujarTerritoriosEnMapa() async {
    if (_mapboxMap == null || _territorios.isEmpty) return;

    final features = _territorios.map((t) {
      final coords = t.puntos.map((p) => [p.longitude, p.latitude]).toList();
      coords.add(coords.first);

      // Los fantasmas son rivales normales visualmente (HP, color, opacidad iguales)
      final colorHex    = _colorToHex(t.esMio ? t.color : t.colorEstadoHp);
      final borderWidth = t.esMio
          ? 2.8
          : switch (t.estadoHp) {
              EstadoHp.saludable => 1.4,
              EstadoHp.danado    => 1.8,
              EstadoHp.critico   => 2.2,
            };
      final innerOpacity = t.esMio ? t.opacidadRelleno * 0.55 : 0.0;

      return _encodeJson({
        'type': 'Feature',
        'properties': {
          'color':         colorHex,
          'fillOpacity':   t.opacidadRelleno,
          'innerOpacity':  innerOpacity,
          'borderOpacity': t.opacidadBorde,
          'borderWidth':   borderWidth,
          'esMio':         t.esMio,
          'estadoHp':      t.estadoHp.name,
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
        _actualizarCoronesMapa();
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
      _actualizarCoronesMapa();

      // Marcadores en el globo (visibles a zoom bajo, desaparecen al correr)
      if (!_centrosLayerCreated) {
        final misTerr = _territorios.where((t) => t.esMio).toList();
        if (misTerr.isNotEmpty) {
          final feats = misTerr.map((t) {
            final c = t.centro;
            return '{"type":"Feature","properties":{},"geometry":{'
                '"type":"Point","coordinates":[${c.longitude},${c.latitude}]}}';
          }).join(',');
          final gj = '{"type":"FeatureCollection","features":[$feats]}';
          await _mapboxMap!.style.addSource(
              mapbox.GeoJsonSource(id: _centrosSourceId, data: gj));
          await _mapboxMap!.style.addLayer(
              mapbox.CircleLayer(id: _centrosLayerId, sourceId: _centrosSourceId));
          await _mapboxMap!.style.setStyleLayerProperty(
              _centrosLayerId, 'circle-color', '#FFD60A');
          await _mapboxMap!.style.setStyleLayerProperty(
              _centrosLayerId, 'circle-radius',
              ['interpolate', ['linear'], ['zoom'], 1, 2.5, 5, 5.0, 9, 0.0]);
          await _mapboxMap!.style.setStyleLayerProperty(
              _centrosLayerId, 'circle-opacity',
              ['interpolate', ['linear'], ['zoom'], 4, 0.9, 8, 0.0]);
          await _mapboxMap!.style.setStyleLayerProperty(
              _centrosLayerId, 'circle-blur', 0.3);
          _centrosLayerCreated = true;
        }
      } else {
        final misTerr = _territorios.where((t) => t.esMio).toList();
        final feats = misTerr.map((t) {
          final c = t.centro;
          return '{"type":"Feature","properties":{},"geometry":{'
              '"type":"Point","coordinates":[${c.longitude},${c.latitude}]}}';
        }).join(',');
        final gj = '{"type":"FeatureCollection","features":[$feats]}';
        final src = await _mapboxMap!.style
            .getSource(_centrosSourceId) as mapbox.GeoJsonSource?;
        await src?.updateGeoJSON(gj);
      }

      _pulsoTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
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
    final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(minutes: 5)));
    _jugadoresStream = FirebaseFirestore.instance
        .collection('presencia_activa')
        .where('timestamp', isGreaterThan: cutoff)
        .snapshots()
        .listen((snap) async {
      if (!mounted) return;
      final user   = FirebaseAuth.instance.currentUser;
      final myLat  = _currentPosition?.latitude;
      final myLng  = _currentPosition?.longitude;
      final nuevos = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        if (doc.id == user?.uid) continue;
        final d  = doc.data();
        // Filtro dinámico: descartar jugadores inactivos hace >5 min
        final ts = d['timestamp'] as Timestamp?;
        if (ts == null ||
            DateTime.now().difference(ts.toDate()).inMinutes >= 5) { continue; }
        final lat = (d['lat'] as num?)?.toDouble();
        final lng = (d['lng'] as num?)?.toDouble();
        // Filtro geográfico client-side: solo jugadores a <5 km
        if (myLat != null && myLng != null && lat != null && lng != null) {
          final dist = Geolocator.distanceBetween(myLat, myLng, lat, lng);
          if (dist > 5000) continue;
        }
        nuevos[doc.id] = d;
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
    for (final uid in _anotacionesJugadores.keys
        .where((k) => !activos.contains(k))
        .toList()) {
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
    if (_avatarCache.length >= _kAvatarCacheMax) _avatarCache.remove(_avatarCache.keys.first);
    _avatarCache[key] = bytes;
    return bytes;
  }

  void _crearAvatarJugador(
      String uid, double lat, double lng, Uint8List bytes) async {
    if (_annotationManager == null) return;
    final ann = await _annotationManager!.create(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
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

  // ==========================================================================
  // CORONAS DE REYES EN EL MAPA
  // ==========================================================================
  Future<void> _actualizarCoronesMapa() async {
    if (_annotationManager == null || _modoSolitario) return;

    final bytes = _coronaBytes ??= await _generarImagenCorona();

    final conRey = _territorios
        .where((t) => t.tieneRey && !t.esFantasma)
        .toList();
    final idsConRey = conRey.map((t) => t.docId).toSet();

    // Eliminar coronas de territorios que ya no tienen Rey
    for (final docId in _anotacionesReyes.keys
        .where((k) => !idsConRey.contains(k))
        .toList()) {
      await _annotationManager?.delete(_anotacionesReyes[docId]!);
      _anotacionesReyes.remove(docId);
    }

    // Crear / actualizar coronas
    for (final t in conRey) {
      final pos = mapbox.Point(
        coordinates: mapbox.Position(
            t.centro.longitude, t.centro.latitude),
      );
      if (_anotacionesReyes.containsKey(t.docId)) {
        final ann = _anotacionesReyes[t.docId]!;
        await _annotationManager?.update(ann..geometry = pos);
      } else {
        final ann = await _annotationManager!.create(
          mapbox.PointAnnotationOptions(
            geometry: pos,
            image:    bytes,
            iconSize: 0.9,
          ),
        );
        _anotacionesReyes[t.docId] = ann;
      }
    }
  }

  Future<Uint8List> _generarImagenCorona() async {
    const sz = 48.0;
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);

    // Fondo circular semitransparente
    canvas.drawCircle(
      const Offset(sz / 2, sz / 2),
      sz / 2,
      Paint()..color = const Color(0xCC1A1000),
    );
    // Borde dorado
    canvas.drawCircle(
      const Offset(sz / 2, sz / 2),
      sz / 2 - 2,
      Paint()
        ..color       = const Color(0xFFD4A84C)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Emoji 👑 centrado
    final tp = TextPainter(
      text: const TextSpan(
        text: '👑',
        style: TextStyle(fontSize: 24, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset((sz - tp.width) / 2, (sz - tp.height) / 2 - 1));

    final pic      = recorder.endRecording();
    final img      = await pic.toImage(sz.toInt(), sz.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _generarImagenAvatar(Color color) async {
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    const sz       = 48.0;
    canvas.drawCircle(Offset(sz / 2, sz / 2), sz / 2,
        Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(
        Offset(sz / 2, sz / 2), sz / 2 - 6, Paint()..color = _p.parchment);
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
      // En empate gana el retado (defensor), igual que en Risk clásico
      if (puntosRetador > puntosRetado) {
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
        {
          'toUserId': ganadorId, 'type': 'desafio_ganado',
          'message': '🏆 ¡Ganaste el desafío contra $perdedorNick! +${apuesta * 2} 🪙'
        },
        {
          'toUserId': perdedorId, 'type': 'desafio_perdido',
          'message': '💀 Perdiste el desafío contra $ganadorNick. $ganadorNick se lleva ${apuesta * 2} 🪙'
        },
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
  // GUERRA GLOBAL
  // ==========================================================================
  double get _progresoGlobal {
    if (_objetivoGlobal == null) return 0;
    final kmReq = (_objetivoGlobal!['kmRequeridos'] as num?)?.toDouble() ?? 0;
    if (kmReq <= 0) return 0;
    return (_distanciaTotal / kmReq).clamp(0.0, 1.0);
  }

  double get _kmRestantesGlobal {
    if (_objetivoGlobal == null) return 0;
    final kmReq = (_objetivoGlobal!['kmRequeridos'] as num?)?.toDouble() ?? 0;
    return (kmReq - _distanciaTotal).clamp(0.0, kmReq);
  }

  Future<void> _conquistarTerritorioGlobal(
  String activityLogId, {
  required double kmCorridosEnSesion,
}) async {
  if (_globalConquistando) return;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final territorioId = _objetivoGlobal?['territorioId'] as String?;
  if (territorioId == null) return;

  setState(() => _globalConquistando = true);

  try {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('conquistarTerritorioGlobal');
    final result = await callable.call({
      'territorioId':        territorioId,
      'activityLogId':       activityLogId,
      'ownerColor':          _colorTerritorio.value,
      'kmCorridosEnSesion':  kmCorridosEnSesion,   // ← añadido
    });
      if (!mounted) return;
      final data = result.data as Map<String, dynamic>;
      if (data['ok'] == true) {
        final nuevaClausula = (data['nuevaClausula'] as num?)?.toDouble();
        setState(() {
          _globalConquistado = true;
          _nuevaClausula = nuevaClausula;
        });
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 150),
            () => HapticFeedback.heavyImpact());
        Future.delayed(const Duration(milliseconds: 300),
            () => HapticFeedback.heavyImpact());
        _narrador.eventoConquista(
            _objetivoGlobal?['territorioNombre'] as String? ?? '');
        _mostrarNotificacionConquistaGlobal();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) _mostrarError(e.message ?? 'Error al conquistar.');
    } catch (e) {
      debugPrint('Error conquista global: $e');
      if (mounted) _mostrarError('Error inesperado. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _globalConquistando = false);
    }
  }

  void _mostrarNotificacionConquistaGlobal() {
    if (!mounted) return;
    final nombre     = _objetivoGlobal?['territorioNombre'] as String? ?? 'Territorio';
    final recompensa = (_objetivoGlobal?['recompensa'] as num?)?.toInt() ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3A2800), Color(0xFFD4A84C)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          border: Border.all(color: _kGold, width: 1.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.55), blurRadius: 28)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('⚔️', style: TextStyle(fontSize: 38)),
          const SizedBox(height: 8),
          Text('¡TERRITORIO CONQUISTADO!', textAlign: TextAlign.center,
              style: GoogleFonts.cinzel(color: _kGoldLight, fontSize: 16,
                  fontWeight: FontWeight.w900, letterSpacing: 2.5)),
          const SizedBox(height: 4),
          Text(nombre, textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.30),
              border: Border.all(color: _p.goldDim.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('+$recompensa 🪙 el lunes si sigues siendo dueño  ·  +50 pts de liga',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: _kGoldLight.withValues(alpha: 0.9),
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    ));
  }

  void _mostrarError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: _snackWrap(
        color:  _p.parchMid,
        border: Border.all(color: _p.globalRed.withValues(alpha: 0.5)),
        child: Row(children: [
          Icon(CupertinoIcons.exclamationmark_triangle, color: _p.globalRed, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg,
              style: GoogleFonts.inter(color: _kGoldLight,
                  fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      ),
    ));
  }

  // ==========================================================================
  // TRACKING
  // ==========================================================================
  StreamSubscription<Position> _crearStreamGPS() {
    return Geolocator.getPositionStream(
        locationSettings: _kGpsMovimiento).listen(
      (Position pos) async {
        if (isPaused || !mounted) return;

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

        final newPt = LatLng(pos.latitude, pos.longitude);
        setState(() {
          if (routePoints.isNotEmpty) {
            final dist = Geolocator.distanceBetween(
              routePoints.last.latitude, routePoints.last.longitude,
              newPt.latitude, newPt.longitude,
            );
            _distanciaTotal += dist / 1000;
            _bearing = _calcularBearing(routePoints.last, newPt);
            if (_ultimaPosicionVelocidad != null) {
              final dt = pos.timestamp
                      .difference(_ultimaPosicionVelocidad!.timestamp)
                      .inMilliseconds / 3600000.0;
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

        _moverCamara(lat: pos.latitude, lng: pos.longitude,
            zoom: _kZoomCorrer, bearing: _bearing, pitch: _kPitchCorrer);
        if (_puntosDesdeUltimoUpdate >= _kActualizarMapaCadaN) {
          _puntosDesdeUltimoUpdate = 0;
          _actualizarRutaEnMapa();
        }

        if (_retoActivo != null && !_retoCompletado) {
          final objetivoMetros =
              (_retoActivo!['objetivo_valor'] as num?)?.toDouble() ?? 0;
          final distanciaMetros = _distanciaTotal * 1000;
          if (objetivoMetros > 0) {
            _narrador.eventoMitadReto(distanciaMetros);
            _narrador.eventoFinalReto(distanciaMetros);
            if (distanciaMetros >= objetivoMetros) {
              setState(() => _retoCompletado = true);
              final titulo = _retoActivo!['titulo'] as String? ?? 'Reto';
              _narrador.anunciarRetoCompletado(titulo);
              _mostrarNotificacionRetoCompletado();
            }
          }
        }

        if (_objetivoGlobal != null && !_globalKmAlcanzados && !_globalConquistando) {
  final kmReq = (_objetivoGlobal!['kmRequeridos'] as num?)?.toDouble() ?? 0;
  if (kmReq > 0 && _distanciaTotal >= kmReq) {
    setState(() => _globalKmAlcanzados = true);
    final nombreTer =
        _objetivoGlobal!['territorioNombre'] as String? ?? 'Territorio';
    _narrador.anunciarReto(
        '⚔️ ¡$nombreTer alcanzado! Finaliza la carrera para reclamar.');
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 150), HapticFeedback.heavyImpact);
    Future.delayed(const Duration(milliseconds: 300), HapticFeedback.heavyImpact);
  }
}

        if (!_modoSolitario) _procesarPosicionEnTerritorios(newPt);

        final kmActual = _distanciaTotal.floor();
        if (kmActual > 0) _narrador.eventoKilometro(kmActual);
        if (_distanciaTotal - _distanciaUltimoAnalisisRitmo >= 0.5) {
          _distanciaUltimoAnalisisRitmo = _distanciaTotal;
          _narrador.analizarRitmo(_velocidadActualKmh);
        }

        if (!_modoSolitario) {
          final double radioRadar = SubscriptionService.radioRadar;
          for (final entry in _jugadoresActivos.entries) {
            final lat2 = (entry.value['lat'] as num?)?.toDouble();
            final lng2 = (entry.value['lng'] as num?)?.toDouble();
            if (lat2 == null || lng2 == null) continue;
            final dist = Geolocator.distanceBetween(
                pos.latitude, pos.longitude, lat2, lng2);
            if (dist < radioRadar) {
              _narrador.eventoRivalCerca(entry.value['nickname'] as String?, dist);
              break;
            }
          }
        }

        if (!_modoManual) {
          final esNoche = _esHoraNoche();
          if (esNoche != _modoNoche) setState(() => _modoNoche = esNoche);
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
    }
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() => _mostrandoCuentaAtras = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Necesitas activar la ubicación para correr.\nVe a Ajustes del teléfono → Permisos → Ubicación.',
              style: TextStyle(fontSize: 13)),
          backgroundColor: const Color(0xFFCC2222),
          duration: const Duration(seconds: 5),
          action: p == LocationPermission.deniedForever
              ? SnackBarAction(
                  label: 'AJUSTES',
                  textColor: Colors.white,
                  onPressed: () => Geolocator.openAppSettings(),
                )
              : null,
        ),
      );
      return;
    }
    setState(() {
      _globalKmAlcanzados = false;
      isTracking               = true;
      isPaused                 = false;
      _distanciaTotal          = 0;
      _velocidadActualKmh      = 0;
      _bearing                 = 0;
      routePoints.clear();
      _puntosDesdeUltimoUpdate = 0;
      _territoriosNotificadosEnSesion.clear();
      _territoriosVisitadosEnSesion.clear();
      _hudMinimizado           = true;
      _retoCompletado          = false;
    });
    _antiCheat.resetear();
    _sesionInvalidadaPorCheat = false;
    _stopping = false;
    _stopwatch.reset();
    _stopwatch.start();
    _timerController.start();
    // Transición globo → calle
    if (!kIsWeb && _mapboxMap != null && _currentPosition != null) {
      _mapboxMap!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(
              _currentPosition!.longitude, _currentPosition!.latitude)),
          zoom: _kZoomCorrer,
          pitch: _kPitchCorrer,
        ),
        mapbox.MapAnimationOptions(duration: 2500),
      );
    } else if (kIsWeb && _webMapCtrl != null && _currentPosition != null) {
      _webMapCtrl!.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        _kZoomCorrer,
      );
    }
    _iniciarPublicacionPosicion();
    _narrador.iniciar();
    _minutosResistenciaNotificados = 0;
    _distanciaUltimoAnalisisRitmo  = 0;

    _timerResistencia?.cancel();
    _timerResistencia = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!isTracking || isPaused || !mounted) return;
      final mins = _stopwatch.elapsed.inMinutes;
      if (mins >= 20 && mins % 10 == 0 && mins != _minutosResistenciaNotificados) {
        _minutosResistenciaNotificados = mins;
        _narrador.eventoResistencia(mins);
      }
    });

    await _mapboxMap?.gestures.updateSettings(
        mapbox.GesturesSettings(rotateEnabled: false, pitchEnabled: false));
    if (_currentPosition != null) {
      await _moverCamara(
        lat: _currentPosition!.latitude, lng: _currentPosition!.longitude,
        zoom: _kZoomCorrer, bearing: _bearing, pitch: _kPitchCorrer,
        duracion: 2800, forzar: true,
      );
    }

    // ── Cargar barrios OSM si estamos en modo solitario
    if (_modoSolitario && _currentPosition != null) {
      _cargarBarriosOSM(LatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      ));
    }

    _positionStream = _crearStreamGPS();

    // ── Listener en tiempo real del territorio global objetivo
    if (_objetivoGlobal != null) {
      final tId = _objetivoGlobal!['territorioId'] as String?;
      if (tId != null) {
        _globalTerritoryLastOwner =
            _objetivoGlobal!['ownerUid'] as String?;
        _globalTerritoryStream = FirebaseFirestore.instance
            .collection('global_territories')
            .doc(tId)
            .snapshots()
            .listen((snap) {
          if (!mounted || !isTracking) return;
          if (!snap.exists) return;
          final data    = snap.data()!;
          final newOwner = data['ownerUid'] as String?;
          final uid      = FirebaseAuth.instance.currentUser?.uid;
          // Si cambió de dueño y no somos nosotros quienes lo tomamos
          if (newOwner != null &&
              newOwner != _globalTerritoryLastOwner &&
              newOwner != uid &&
              !_globalConquistado) {
            _globalTerritoryLastOwner = newOwner;
            final nick = data['ownerNickname'] as String? ?? 'otro jugador';
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                duration: const Duration(seconds: 5),
                backgroundColor: Colors.transparent,
                elevation: 0,
                content: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0000),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: const Color(0xFFCC2222).withValues(alpha: 0.7)),
                  ),
                  child: Row(children: [
                    const Text('⚔️', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '¡$nick acaba de conquistar este territorio!',
                        style: GoogleFonts.inter(
                          color: const Color(0xFFFF5252),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ]),
                ),
              ));
            }
          } else if (newOwner != null) {
            _globalTerritoryLastOwner = newOwner;
          }
        });
      }
    }
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
        _moverCamara(lat: _currentPosition!.latitude,
            lng: _currentPosition!.longitude,
            zoom: _kZoomPausado, pitch: _kPitchNormal, bearing: 0, forzar: true);
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
        _moverCamara(lat: _currentPosition!.latitude,
            lng: _currentPosition!.longitude,
            zoom: _kZoomCorrer, pitch: _kPitchCorrer, bearing: _bearing, forzar: true);
      }
    }
  }

  Future<void> stopTracking() async {
    if (_stopping) return;
    _stopping = true;

    _stopwatch.stop();
    _timerController.pause();
    _positionStream?.cancel();
    _timerPublicarPosicion?.cancel();
    _pulsoTimer?.cancel();
    await _limpiarPresenciaFirestore();

    // Limpiar capas de barrios si era solitario
    if (_modoSolitario) {
      await _limpiarCapasBarrios();
    }

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
    // Volver al globo terráqueo al terminar la sesión
    await _moverCamara(
      lat: _currentPosition?.latitude  ?? 40.4167,
      lng: _currentPosition?.longitude ?? -3.70325,
      zoom: _kZoomGlobo, bearing: 0, pitch: _kPitchNormal,
      animated: true, duracion: 1200,
    );

    // ── Guardar log de actividad
    String? logId;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && distanciaFinal > 0) {
        final monedasBase    = (distanciaFinal * 10).round();
        final bool esPremium = SubscriptionService.currentStatus.isPremium;
        final int multiplicador = (_boostXpActivo ? 2 : 1) * (esPremium ? 2 : 1);
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
          'velocidad_media': tiempoFinal.inSeconds > 0
              ? distanciaFinal / (tiempoFinal.inSeconds / 3600)
              : 0.0,
          'boost_activo':    _boostXpActivo,
          'latFinal':        _currentPosition?.latitude,
          'lngFinal':        _currentPosition?.longitude,
          'timestamp':       FieldValue.serverTimestamp(),
          'ownerColor':      _colorTerritorio.value,
          'titulo': _modoSolitario
              ? 'Exploración Solitaria'
              : _objetivoGlobal != null
                  ? 'Guerra Global · ${_objetivoGlobal!['territorioNombre']}'
                  : 'Carrera Libre',
          'modo': _modoSolitario
              ? 'solitario'
              : _objetivoGlobal != null ? 'guerra_global' : 'competitivo',
          'fecha_dia':
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          if (_objetivoGlobal != null) ...{
            'objetivo_global_id':           _objetivoGlobal!['territorioId'],
            'objetivo_global_conquistado':  _globalConquistado,
          },
        });
        logId = logRef.id;

        if (_objetivoGlobal != null && _globalKmAlcanzados && logId != null) {
          await _conquistarTerritorioGlobal(logId, kmCorridosEnSesion: distanciaFinal);
        }

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
        ruta: rutaFinal, tiempo: tiempoFinal, distanciaKm: distanciaFinal,
      );
      if (!sesionCheck.esValida) {
        _sesionInvalidadaPorCheat = true;
        if (mounted) {
          await AntiCheatWarningOverlay.mostrar(
              context, motivo: sesionCheck.motivo ?? 'Sesión inválida');
          if (mounted) Navigator.of(context).pop();
        }
        _stopping = false;
        return;
      }
    }

    // ── Conquistas locales
    int conquistados = 0;

    if (_modoSolitario) {
      final creado = await TerritoryService.crearTerritorioSolitario(
        ruta:            rutaFinal,
        colorTerritorio: _colorTerritorio,
        nickname:        _miNickname,
      );
      if (creado) {
        conquistados = 1;
        // Recargar territorios e incluir el nuevo en el cálculo de barrios
        final nuevosTerritorios =
            await TerritoryService.cargarTodosLosTerritorios(modo: 'solitario');
        if (mounted) setState(() => _territorios = nuevosTerritorios);
        await _verificarBarriosCompletados();
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
                color: _p.parchMid,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _p.goldDim),
              ),
              child: Row(children: [
                const Text('🗺️', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Área insuficiente para crear territorio.\n'
                    '¡Explora más calles y rodea una zona más amplia!',
                    style: GoogleFonts.inter(color: _kGoldLight,
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ));
        }
      }
      // Limpiar estado de barrios
      if (mounted) {
        setState(() {
          _barriosCercanos = [];
          _barrioActual    = null;
          _barriosCargados = false;
        });
      }
    } else if (_objetivoGlobal == null && distanciaFinal >= 0.3) {
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
        await ConquistaOverlay.mostrar(context,
            esInvasion: conquistados > 0, nombreTerritorio: nombreRival);
      }
    }

    if (!mounted) { _stopping = false; return; }

    // En guerra global los puntos de liga se entregan el lunes (CF liquidarGuerraGlobal),
    // no en el momento de la conquista. Solo se computan para los otros modos.
    final puntosLigaGanados = _modoSolitario
        ? 0
        : _objetivoGlobal != null
            ? 0
            : (distanciaFinal > 0 ? 15 : 0) + (conquistados * 25);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null && distanciaFinal > 0) {
      DesafiosService.acumularPuntos(
        uid:                     user.uid,
        distanciaKm:             distanciaFinal,
        territoriosConquistados: conquistados,
      );
      DesafiosService.verificarExpirados(user.uid);
    }

    _stopping = false;

    Navigator.pushReplacementNamed(context, '/resumen', arguments: {
      'distancia':               distanciaFinal,
      'tiempo':                  tiempoFinal,
      'ruta':                    rutaFinal,
      'esDesdeCarrera':          true,
      'territoriosConquistados': conquistados,
      'puntosLigaGanados':       puntosLigaGanados,
      'retoCompletado':          _retoCompletado ? _retoActivo : null,
      'objetivoGlobal':          _objetivoGlobal,
      'globalConquistado':       _globalConquistado,
      'nuevaClausula':           _nuevaClausula,
    });
  }

  // ==========================================================================
  // TERRITORIOS LÓGICA LOCAL
  // ==========================================================================
  void _procesarPosicionEnTerritorios(LatLng pos) {
    if (_territorios.isEmpty) return;

    final t = TerritoryService.territorioEnPosicion(_territorios, pos);

    final cercanos = _territorios.where((ter) {
      if (ter.esMio) return false;
      final dist = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        ter.centro.latitude, ter.centro.longitude,
      );
      return dist < 400;
    }).toList()
      ..sort((a, b) {
        final dA = Geolocator.distanceBetween(pos.latitude, pos.longitude,
            a.centro.latitude, a.centro.longitude);
        final dB = Geolocator.distanceBetween(pos.latitude, pos.longitude,
            b.centro.latitude, b.centro.longitude);
        return dA.compareTo(dB);
      });

    if (mounted) {
      setState(() {
        _territoriosRivalesCercanos = cercanos.take(3).toList();
        _territorioActualBajoPie    = (t != null && !t.esMio) ? t : null;
      });
    }

    if (t == null) return;

    if (t.esMio) {
      if (!_territoriosVisitadosEnSesion.contains(t.docId)) {
        _territoriosVisitadosEnSesion.add(t.docId);
        TerritoryService.actualizarUltimaVisita(t.docId);
        _narrador.eventoTerritorioPropio();
        _mostrarSnackRefuerzo(t);
      }
    } else {
      if (!_territoriosNotificadosEnSesion.contains(t.docId)) {
        _territoriosNotificadosEnSesion.add(t.docId);
        // Los fantasmas no tienen dueño real → no enviar notificación Firestore
        if (!t.esFantasma) {
          TerritoryService.crearNotificacionInvasion(
            toUserId: t.ownerId, fromNickname: _miNickname, territoryId: t.docId,
          );
        }
        _narrador.eventoTerritorioRival(t.ownerNickname);
        _mostrarSnackTerritorioRival(t);
      }
    }
  }

  Future<int> _procesarConquistas(
      List<LatLng> ruta, Duration tiempo, double distancia) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || ruta.isEmpty || _territorios.isEmpty) return 0;

    final rutaParaCloud = ruta
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList();

    final double velocidadMedia = _velocidadActualKmh > 0
        ? _velocidadActualKmh
        : (distancia > 0 && tiempo.inSeconds > 0
            ? distancia / (tiempo.inSeconds / 3600)
            : 5.0);

    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('atacarTerritorio',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));

    final territoriosObjetivo = _territorios.where((t) {
      if (t.esMio) return false;
      final paso    = _rutaPasaPorPoligono(ruta, t.puntos);
      final cercano = t.esConquistableSinPasar &&
          _rutaPasaCercaDe(ruta, t.centro, radioMetros: 50);
      return paso || cercano;
    }).toList();

    if (territoriosObjetivo.isEmpty) return 0;

    final resultados = await Future.wait(
      territoriosObjetivo.map((t) async {
        try {
          final result = await callable.call({
            'territorioDefensorId':      t.docId,
            'rutaAtacante':              rutaParaCloud,
            'velocidadMediaAtacanteKmh': velocidadMedia,
          });
          final data   = result.data as Map<String, dynamic>;
          final accion = data['accion'] as String?;
          if (data['ok'] == true) {
            if (accion == 'conquista_total' || accion == 'robo_parcial') {
              _narrador.eventoConquista(t.ownerNickname);
              final nuevos = await TerritoryService.cargarTodosLosTerritorios(
                  modo: _modoSolitario ? 'solitario' : 'competitivo');
                if (mounted) {
                  setState(() => _territorios = nuevos);
                  _territoriosLayersCreated = false;
                  await _dibujarTerritoriosEnMapa();
                }
              return 1;
            } else if (accion == 'daño') {
              final hpDespues     = data['hpDespues'] as int? ?? 0;
              final bajoDeEstado  = data['bajoDeEstado'] as bool? ?? false;
              final estadoDespues = data['estadoDespues'] as String? ?? '';
              if (mounted) {
                final mensaje = bajoDeEstado
                    ? '⚠️ Territorio debilitado a estado ${estadoDespues.toUpperCase()}'
                    : '⚔️ Daño causado. HP rival: $hpDespues%';
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  duration: const Duration(seconds: 3),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  content: _snackWrap(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF6B1500), Color(0xFFD4520A)]),
                    shadow: _p.terracotta,
                    child: Row(children: [
                      const Text('⚔️', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(mensaje,
                          style: const TextStyle(color: Color(0xFFFFE8C0),
                              fontWeight: FontWeight.bold, fontSize: 13))),
                    ]),
                  ),
                ));
              }
            }
          }
          return 0;
        } on FirebaseFunctionsException catch (e) {
          debugPrint('Error atacarTerritorio [${t.docId}]: ${e.message}');
          return 0;
        } catch (e) {
          debugPrint('Error atacarTerritorio: $e');
          return 0;
        }
      }),
      eagerError: false,
    );

    return resultados.fold<int>(0, (sum, val) => sum + val);
  }

  bool _rutaPasaPorPoligono(List<LatLng> ruta, List<LatLng> pol) =>
      ruta.any((p) => _puntoEnPoligono(p, pol));

  bool _puntoEnPoligono(LatLng punto, List<LatLng> pol) {
    int n = pol.length, inter = 0;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = pol[i].longitude, yi = pol[i].latitude;
      final xj = pol[j].longitude, yj = pol[j].latitude;
      if (((yi > punto.latitude) != (yj > punto.latitude)) &&
          punto.longitude < (xj - xi) * (punto.latitude - yi) / (yj - yi) + xi) {
        inter++;
      }
    }
    return inter % 2 == 1;
  }

  bool _rutaPasaCercaDe(List<LatLng> ruta, LatLng obj,
          {required double radioMetros}) =>
      ruta.any((p) => Geolocator.distanceBetween(
              p.latitude, p.longitude, obj.latitude, obj.longitude) <=
          radioMetros);

  // ==========================================================================
  // SNACKS Y NOTIFICACIONES
  // ==========================================================================
  void _mostrarNotificacionRetoCompletado() {
    if (!mounted || _retoActivo == null) return;
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 150), () => HapticFeedback.heavyImpact());
    Future.delayed(const Duration(milliseconds: 300), () => HapticFeedback.heavyImpact());
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
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          border: Border.all(color: _kGold, width: 1.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.55), blurRadius: 28)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🏆', style: TextStyle(fontSize: 38)),
          const SizedBox(height: 8),
          Text('¡RETO COMPLETADO!', textAlign: TextAlign.center,
              style: GoogleFonts.cinzel(color: _kGoldLight, fontSize: 17,
                  fontWeight: FontWeight.w900, letterSpacing: 3)),
          const SizedBox(height: 4),
          Text(titulo, textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.30),
              border: Border.all(color: _p.goldDim.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Puedes seguir corriendo o finalizar la carrera',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: _kGoldLight.withValues(alpha: 0.85),
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    ));
  }

  // Corrección 1 — snack territorio rival con HP y estado
  void _mostrarSnackTerritorioRival(TerritoryData t) {
    if (!mounted) return;
    final String estadoLabel;
    final Color  estadoColor;
    final String emoji;
    final String consejo;
    switch (t.estadoHp) {
      case EstadoHp.saludable:
        estadoLabel = 'FUERTE'; estadoColor = _kVerde;
        emoji = '🟢'; consejo = 'Necesitas >7 km/h para dañarlo';
      case EstadoHp.danado:
        estadoLabel = 'MEDIO'; estadoColor = _kGold;
        emoji = '🟡'; consejo = 'Necesitas >5 km/h';
      case EstadoHp.critico:
        estadoLabel = '¡LEVE!'; estadoColor = _p.globalRed;
        emoji = '🔴'; consejo = '¡Cualquier paso lo conquista!';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _p.parchment.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: estadoColor.withValues(alpha: 0.7), width: 1.5),
          boxShadow: [
            BoxShadow(color: estadoColor.withValues(alpha: 0.25), blurRadius: 16),
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8),
          ],
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color:  estadoColor.withValues(alpha: 0.15),
              shape:  BoxShape.circle,
              border: Border.all(color: estadoColor.withValues(alpha: 0.5)),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Text('⚔️ ', style: TextStyle(fontSize: 12)),
                  Expanded(child: Text(t.ownerNickname,
                      style: GoogleFonts.inter(color: _kGoldLight,
                          fontSize: 13, fontWeight: FontWeight.w900),
                      overflow: TextOverflow.ellipsis)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: estadoColor.withValues(alpha: 0.15),
                      border: Border.all(color: estadoColor.withValues(alpha: 0.6)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(estadoLabel,
                        style: GoogleFonts.inter(color: estadoColor,
                            fontSize: 10, fontWeight: FontWeight.w900,
                            letterSpacing: 1.2)),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(consejo,
                    style: GoogleFonts.inter(
                        color: _kGoldLight.withValues(alpha: 0.75),
                        fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Stack(children: [
                  Container(height: 3,
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2))),
                  FractionallySizedBox(
                    widthFactor: (t.hpActual / 100.0).clamp(0.0, 1.0),
                    child: Container(height: 3,
                        decoration: BoxDecoration(color: estadoColor,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [BoxShadow(
                                color: estadoColor.withValues(alpha: 0.6),
                                blurRadius: 4)])),
                  ),
                ]),
              ],
            ),
          ),
        ]),
      ),
    ));
  }

  // Corrección 1 — radar de territorios próximos
  Widget _buildRadarTerritoriosProximos() {
    if (_modoSolitario || !isTracking || isPaused) return const SizedBox.shrink();
    if (_territoriosRivalesCercanos.isEmpty && _territorioActualBajoPie == null) {
      return const SizedBox.shrink();
    }
    final todos = [
      if (_territorioActualBajoPie != null) _territorioActualBajoPie!,
      ..._territoriosRivalesCercanos
          .where((t) => t.docId != _territorioActualBajoPie?.docId),
    ].take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: todos.map((t) {
        final bool bajoPie = t.docId == _territorioActualBajoPie?.docId;
        final Color estadoColor;
        final String estadoEmoji;
        final String estadoLabel;
        switch (t.estadoHp) {
          case EstadoHp.saludable:
            estadoColor = _kVerde; estadoEmoji = '🟢'; estadoLabel = 'FUERTE';
          case EstadoHp.danado:
            estadoColor = _kGold; estadoEmoji = '🟡'; estadoLabel = 'MEDIO';
          case EstadoHp.critico:
            estadoColor = _p.globalRed; estadoEmoji = '🔴'; estadoLabel = 'LEVE';
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bajoPie
                ? estadoColor.withValues(alpha: 0.18)
                : _p.parchment.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: estadoColor.withValues(alpha: bajoPie ? 0.9 : 0.45),
                width: bajoPie ? 1.5 : 1.0),
            boxShadow: bajoPie
                ? [BoxShadow(color: estadoColor.withValues(alpha: 0.3), blurRadius: 12)]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(estadoEmoji, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 6),
            Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, children: [
              Text(bajoPie ? '¡PISANDO!' : 'CERCA',
                  style: GoogleFonts.inter(
                      color: bajoPie ? estadoColor : _p.goldDim,
                      fontSize: 8, fontWeight: FontWeight.w900,
                      letterSpacing: 1.5)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (t.tieneRey) ...[
                  const Text('👑', style: TextStyle(fontSize: 9)),
                  const SizedBox(width: 3),
                ],
                if (t.escudoVigente) ...[
                  const Text('🛡️', style: TextStyle(fontSize: 9)),
                  const SizedBox(width: 3),
                ],
                Text(t.ownerNickname.length > 10
                    ? '${t.ownerNickname.substring(0, 9)}…'
                    : t.ownerNickname,
                    style: GoogleFonts.inter(
                        color: bajoPie
                            ? _kGoldLight
                            : _kGoldLight.withValues(alpha: 0.7),
                        fontSize: 11, fontWeight: FontWeight.w800)),
              ]),
            ]),
            const SizedBox(width: 8),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: estadoColor.withValues(alpha: 0.15),
                  border: Border.all(color: estadoColor.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(estadoLabel,
                    style: GoogleFonts.inter(color: estadoColor,
                        fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
              ),
              if (t.escudoVigente && t.escudoExpira != null) ...[
                const SizedBox(height: 2),
                Text(
                  'escudo ${_horasRestantes(t.escudoExpira!)}h',
                  style: GoogleFonts.inter(
                      color: Colors.lightBlueAccent,
                      fontSize: 7, fontWeight: FontWeight.w700),
                ),
              ],
            ]),
          ]),
        );
      }).toList(),
    );
  }

  // Corrección 2 — chip barrio actual (modo solitario)
  Widget _buildChipBarrioActual() {
    if (!_modoSolitario || !isTracking || _barrioActual == null) {
      return const SizedBox.shrink();
    }
    final barrio = _barrioActual!;
    final pct    = barrio.porcentajeCubierto;
    final pctInt = (pct * 100).toInt();
    final Color color;
    final String emoji;
    if (pct >= 1.0)      { color = _kVerde;     emoji = '🏆'; }
    else if (pct >= 0.5) { color = _kGold;       emoji = '🗺️'; }
    else if (pct > 0)    { color = _p.terracotta; emoji = '📍'; }
    else                 { color = _p.goldDim;    emoji = '🗺️'; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _p.parchment.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.20), blurRadius: 12)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          Text(barrio.nombre,
              style: GoogleFonts.inter(color: _kGoldLight,
                  fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          SizedBox(
            width: 110,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value:           pct,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor:      AlwaysStoppedAnimation(color),
                minHeight:       4,
              ),
            ),
          ),
        ]),
        const SizedBox(width: 8),
        Text('$pctInt%',
            style: GoogleFonts.orbitron(color: color,
                fontSize: 12, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  // Corrección 2 — notificación barrio completado al 100%
  void _mostrarNotificacionBarrioCompletado(_BarrioData barrio, int bonusMonedas) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 150), () => HapticFeedback.heavyImpact());
    Future.delayed(const Duration(milliseconds: 300), () => HapticFeedback.heavyImpact());
    Future.delayed(const Duration(milliseconds: 450), () => HapticFeedback.heavyImpact());

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 10),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A3A1A), Color(0xFF4CAF50)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          border: Border.all(color: _kVerde, width: 1.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: _kVerde.withValues(alpha: 0.55), blurRadius: 28)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🏆', style: TextStyle(fontSize: 42)),
          const SizedBox(height: 8),
          Text('¡BARRIO CONQUISTADO!', textAlign: TextAlign.center,
              style: GoogleFonts.cinzel(color: _kGoldLight, fontSize: 16,
                  fontWeight: FontWeight.w900, letterSpacing: 2.5)),
          const SizedBox(height: 4),
          Text(barrio.nombre.toUpperCase(), textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: Colors.white,
                  fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Has conquistado el 100% de este barrio',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.30),
              border: Border.all(color: _kVerde.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('🪙', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('+$bonusMonedas BONUS',
                  style: GoogleFonts.orbitron(color: _kGoldLight,
                      fontSize: 16, fontWeight: FontWeight.w900,
                      letterSpacing: 1.5)),
            ]),
          ),
        ]),
      ),
    ));
  }

  int _horasRestantes(DateTime expira) =>
      expira.difference(DateTime.now()).inHours.clamp(0, 999);

  void _mostrarSnackRefuerzo(TerritoryData territorio) {
    if (!mounted) return;
    final String mensaje;
    final String emoji;
    switch (territorio.estadoHp) {
      case EstadoHp.critico:
        mensaje = '¡Territorio estabilizado a estado Medio!'; emoji = '🔧';
      case EstadoHp.danado:
        mensaje = '¡Territorio reforzado a estado Fuerte!'; emoji = '🛡️';
      case EstadoHp.saludable:
        mensaje = '¡Territorio en perfecto estado!'; emoji = '⚔️';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: territorio.escudoVigente ? 2 : 5),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: _snackWrap(
        color:  _p.parchMid,
        border: Border.all(color: _kGold.withValues(alpha: 0.55)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Text(mensaje,
                style: const TextStyle(color: _kGoldLight,
                    fontWeight: FontWeight.bold, fontSize: 13))),
            if (territorio.escudoVigente && territorio.escudoExpira != null) ...[
              const Text('🛡️', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text('${_horasRestantes(territorio.escudoExpira!)}h',
                  style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ]),
          if (!territorio.escudoVigente) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Text('🛡️', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Text('Proteger con escudo:',
                  style: GoogleFonts.inter(
                      color: _p.goldDim, fontSize: 10, fontWeight: FontWeight.w700)),
              const Spacer(),
              ...TerritoryService.kPreciosEscudo.entries.map((e) =>
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () async {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      await _activarEscudo(territorio.docId, e.key, e.value);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: _p.goldDim.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _kGold.withValues(alpha: 0.5)),
                      ),
                      child: Text('${e.key}h · ${e.value}🪙',
                          style: GoogleFonts.inter(
                              color: _kGold,
                              fontSize: 9,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ]),
      ),
    ));
  }

  Future<void> _activarEscudo(
      String territorioId, int horas, int precio) async {
    if (!mounted) return;
    try {
      await TerritoryService.activarEscudo(
          territorioId: territorioId, horas: horas);
      if (!mounted) return;
      // Recargar para reflejar el escudo en el modelo
      final nuevos = await TerritoryService.cargarTodosLosTerritorios(
          modo: _modoSolitario ? 'solitario' : 'competitivo');
      if (!mounted) return;
      setState(() => _territorios = nuevos);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: _snackWrap(
          color: const Color(0xFF0D1A2A),
          border: Border.all(
              color: Colors.lightBlueAccent.withValues(alpha: 0.6)),
          child: Row(children: [
            const Text('🛡️', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Text('¡Escudo activado $horas horas por $precio 🪙!',
                style: const TextStyle(
                    color: Colors.lightBlueAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ]),
        ),
      ));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _mostrarError(e.message ?? 'Error al activar el escudo.');
    }
  }

  Widget _snackWrap({
    Widget? child, Gradient? gradient, Color? color,
    BoxBorder? border, Color shadow = Colors.transparent,
  }) =>
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
        if (!isTracking && !_mostrandoCuentaAtras)
          Positioned.fill(child: IgnorePointer(child: _buildGloboOverlay())),
        Positioned(top: 0, left: 0, right: 0, child: _buildHUD()),
        Positioned(top: 200, left: 14, child: _buildChips()),
        Positioned(
          top: 200, right: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBotonesMapa(),
              const SizedBox(height: 12),
              _buildRadarTerritoriosProximos(),
            ],
          ),
        ),
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
          Positioned(bottom: 130, left: 0, right: 0,
              child: NarradorOverlay(mensaje: _mensajeNarrador)),
        // Corrección 2 — chip barrio (solo modo solitario)
        if (isTracking && _modoSolitario && _barrioActual != null)
          Positioned(top: 160, left: 0, right: 0,
              child: Center(child: _buildChipBarrioActual())),
        if (isTracking && _retoActivo != null && !_retoCompletado)
          Positioned(
            top: (_modoSolitario && _barrioActual != null) ? 210 : 160,
            left: 0, right: 0,
            child: Center(child: _buildChipRetoActivo()),
          ),
        if (_objetivoGlobal != null && !_globalConquistado)
  Positioned(
    // si está corriendo, debajo del chip de barrio/reto; si no, centrado arriba
    top: isTracking
        ? (_retoActivo != null ? 260 : 160)
        : 120,
    left: 0, right: 0,
    child: Center(child: _buildChipObjetivoGlobal()),
  ),
        if (_globalConquistando)
          Positioned.fill(child: _buildConquistadoOverlay()),
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBotonera()),
      ]),
    );
  }

  // ==========================================================================
  // GUERRA GLOBAL — widgets
  // ==========================================================================
  Widget _buildChipObjetivoGlobal() {
  final nombre      = _objetivoGlobal?['territorioNombre'] as String? ?? 'Territorio';
  final progreso    = _progresoGlobal;

  // Estado 3: confirmado por Cloud Function
  if (_globalConquistado) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _kVerde.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kVerde.withValues(alpha: 0.7)),
        boxShadow: [BoxShadow(color: _kVerde.withValues(alpha: 0.35), blurRadius: 16)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('✅', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Text('¡$nombre CONQUISTADO!',
            style: GoogleFonts.cinzel(color: _kVerde, fontSize: 11,
                fontWeight: FontWeight.w900, letterSpacing: 1.5)),
      ]),
    );
  }

  // Estado 2: km alcanzados, esperando que el usuario finalice
  if (_globalKmAlcanzados) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _kGold.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kGold.withValues(alpha: 0.8)),
        boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.40), blurRadius: 18)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('🏁', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          Text('¡META ALCANZADA!',
              style: GoogleFonts.cinzel(color: _kGoldLight, fontSize: 11,
                  fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          Text('Finaliza la carrera para reclamar',
              style: GoogleFonts.inter(color: _kGold, fontSize: 9,
                  fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  // Estado 1: en progreso (comportamiento original)
  final kmRestantes = _kmRestantesGlobal;
  final restanteStr = kmRestantes >= 1
      ? '${kmRestantes.toStringAsFixed(2)} km'
      : '${(kmRestantes * 1000).toInt()} m';

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: _p.ink.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _p.globalRed.withValues(alpha: 0.6)),
      boxShadow: [BoxShadow(color: _p.globalRed.withValues(alpha: 0.25), blurRadius: 14)],
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Text('⚔️', style: TextStyle(fontSize: 13)),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [
        Text(nombre, style: GoogleFonts.inter(color: _kGoldLight,
            fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progreso,
              backgroundColor: _p.globalRed.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(_p.globalRed),
              minHeight: 4,
            ),
          ),
        ),
      ]),
      const SizedBox(width: 8),
      Text(restanteStr,
          style: GoogleFonts.orbitron(color: _kGoldLight,
              fontSize: 10, fontWeight: FontWeight.w900)),
    ]),
  );
}

  Widget _buildConquistadoOverlay() => Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            decoration: BoxDecoration(
              color: _p.ink,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kGold.withValues(alpha: 0.5)),
              boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.2), blurRadius: 30)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 36, height: 36,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _kGold)),
              const SizedBox(height: 16),
              Text('CONQUISTANDO...',
                  style: GoogleFonts.cinzel(color: _kGoldLight, fontSize: 14,
                      fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 6),
              Text(_objetivoGlobal?['territorioNombre'] as String? ?? '',
                  style: GoogleFonts.inter(color: _kGold, fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  // ==========================================================================
  // CHIP RETO ACTIVO
  // ==========================================================================
  Widget _buildChipRetoActivo() {
    final objetivoMetros  = (_retoActivo!['objetivo_valor'] as num?)?.toDouble() ?? 0;
    final distanciaMetros = _distanciaTotal * 1000;
    final progreso = objetivoMetros > 0
        ? (distanciaMetros / objetivoMetros).clamp(0.0, 1.0)
        : 0.0;
    final restanteM   = (objetivoMetros - distanciaMetros).clamp(0.0, objetivoMetros);
    final restanteStr = restanteM >= 1000
        ? '${(restanteM / 1000).toStringAsFixed(2)} km'
        : '${restanteM.toInt()} m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _p.parchment.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kGold.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.20), blurRadius: 12)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('⚡', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          Text(_retoActivo!['titulo'] as String? ?? 'Reto activo',
              style: GoogleFonts.inter(color: _kGoldLight,
                  fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progreso,
                backgroundColor: _p.goldDim.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation(_kGold),
                minHeight: 4,
              ),
            ),
          ),
        ]),
        const SizedBox(width: 8),
        Text(restanteStr,
            style: GoogleFonts.orbitron(color: _kGoldLight,
                fontSize: 10, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  // ==========================================================================
  // GLOBO 3D
  // ==========================================================================
  // GLOBO UI — overlay transparente sobre el MapboxMap globe real
  // ==========================================================================
  Widget _buildGloboOverlay() {
    return Stack(children: [
      // Viñeta espacial en los bordes (sin tapar el globo central)
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center, radius: 0.82,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
              ),
            ),
          ),
        ),
      ),
      // Título
      Positioned(
        top: 58, left: 0, right: 0,
        child: IgnorePointer(
          child: Column(children: [
            Text('CAMPO DE BATALLA EN VIVO', textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700,
                    letterSpacing: 4, color: Colors.white.withValues(alpha: 0.55))),
            const SizedBox(height: 5),
            Text('RISK RUNNER', textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900,
                    letterSpacing: 3, color: Colors.white,
                    shadows: [
                      Shadow(blurRadius: 24, color: Colors.black.withValues(alpha: 0.9)),
                      Shadow(blurRadius: 8,  color: Colors.black),
                    ])),
          ]),
        ),
      ),
      // Chips de info — esquina superior izquierda
      Positioned(
        top: 148, left: 14,
        child: IgnorePointer(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_modoSolitario) ...[
              _globoChip(CupertinoIcons.map_pin, '${_territorios.where((t) => t.esMio).length} mis zonas', _kGold),
              const SizedBox(height: 6),
              if (_barriosCercanos.isNotEmpty) ...[
                _globoChip(
                  CupertinoIcons.map,
                  '${_barriosCercanos.where((b) => b.porcentajeCubierto >= 1.0).length}/${_barriosCercanos.length} barrios',
                  const Color(0xFF30D158),
                ),
                const SizedBox(height: 6),
                if (_barrioActual != null)
                  _globoChip(
                    CupertinoIcons.compass,
                    '${_barrioActual!.nombre} · ${(_barrioActual!.porcentajeCubierto * 100).toInt()}%',
                    _barrioActual!.porcentajeCubierto >= 1.0
                        ? const Color(0xFF30D158)
                        : _barrioActual!.porcentajeCubierto > 0
                            ? const Color(0xFFFF9500)
                            : Colors.white70,
                  ),
              ] else
                _globoChip(CupertinoIcons.compass, 'Explora y conquista', Colors.white70),
            ] else if (_objetivoGlobal != null) ...[
              _globoChip(CupertinoIcons.flag,
                  _objetivoGlobal!['territorioNombre'] as String? ?? 'Territorio',
                  _p.globalRed),
              const SizedBox(height: 6),
              _globoChip(CupertinoIcons.person,
                  '${(_objetivoGlobal!['kmRequeridos'] as num?)?.toStringAsFixed(1) ?? "?"} km requeridos',
                  Colors.white70),
              const SizedBox(height: 6),
              _globoChip(CupertinoIcons.circle,
                  '+${(_objetivoGlobal!['recompensa'] as num?)?.toInt() ?? 0} el lunes',
                  _kGold),
            ] else ...[
              _globoChip(CupertinoIcons.shield,
                  '${_territoriosNotificadosEnSesion.isNotEmpty ? _territoriosNotificadosEnSesion.length : "—"} invasiones',
                  _p.terracotta),
              const SizedBox(height: 6),
              _globoChip(CupertinoIcons.person_2, '${_jugadoresActivos.length} activos ahora', _kWaterLight),
              const SizedBox(height: 6),
              _globoChip(CupertinoIcons.map, '${_territorios.length} territorios', Colors.white70),
            ],
            if (_retoActivo != null) ...[
              const SizedBox(height: 6),
              _globoChip(CupertinoIcons.bolt, _retoActivo!['titulo'] as String? ?? 'Reto activo', _kGold),
            ],
          ]),
        ),
      ),
      // Stats en la parte inferior
      Positioned(
        bottom: 265, left: 0, right: 0,
        child: IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _objetivoGlobal != null
                  ? [
                      _globoStat(_distanciaTotal.toStringAsFixed(2), 'KM HECHOS', _kGold),
                      _globoStat(
                        (_objetivoGlobal!['kmRequeridos'] as num?)?.toStringAsFixed(1) ?? '?',
                        'KM META', _kWaterLight,
                      ),
                      _globoStat('${(_progresoGlobal * 100).toInt()}%', 'PROGRESO', _kGoldLight),
                      _globoStat(_globalConquistado ? 'OK' : '···', 'ESTADO',
                          _globalConquistado ? _kVerde : _p.terracotta),
                    ]
                  : _modoSolitario && _barriosCercanos.isNotEmpty
                      ? [
                          _globoStat(
                            '${_barriosCercanos.where((b) => b.porcentajeCubierto >= 1.0).length}',
                            'COMPLETAS', const Color(0xFF30D158),
                          ),
                          _globoStat(
                            '${_barriosCercanos.length}',
                            'ZONAS', _kGoldLight,
                          ),
                          _globoStat(
                            '${_territorios.where((t) => t.esMio).length}',
                            'MIS TERR.', _kGold,
                          ),
                          _globoStat(
                            _barriosCercanos.isEmpty ? '0%'
                              : '${(_barriosCercanos.map((b) => b.porcentajeCubierto).reduce((a, b) => a + b) / _barriosCercanos.length * 100).toInt()}%',
                            'MEDIA', _kWaterLight,
                          ),
                        ]
                      : [
                          _globoStat('${_territorios.where((t) => t.esMio).length}', 'MIS ZONAS', _kGold),
                          _globoStat('${_jugadoresActivos.length}', 'ACTIVOS', _kWaterLight),
                          _globoStat('${_territorios.length}', 'TOTAL', _kGoldLight),
                          _globoStat('${_territoriosNotificadosEnSesion.length}', 'EN GUERRA', _p.terracotta),
                        ],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _globoChip(IconData icon, String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 6),
          Text(texto, style: GoogleFonts.inter(
              fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
        ]),
      );

  Widget _globoStat(String valor, String label, Color color) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(valor, style: GoogleFonts.orbitron(
            fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.inter(fontSize: 7,
            fontWeight: FontWeight.w700, letterSpacing: 1.8,
            color: _kGold.withValues(alpha: 0.4))),
      ]);

  Widget _buildMapbox() {
    if (kIsWeb) return _buildWebMap();
    return mapbox.MapWidget(
      styleUri: _mapStyle,
      cameraOptions: mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(
            _currentPosition?.longitude ?? -3.70325,
            _currentPosition?.latitude  ?? 40.4167)),
        zoom: _kZoomGlobo, pitch: _kPitchNormal,
      ),
      onMapCreated: _onMapCreated,
    );
  }

  Widget _buildWebMap() {
    _webMapCtrl ??= MapController();
    return FlutterMap(
      mapController: _webMapCtrl!,
      options: MapOptions(
        initialCenter: LatLng(
          _currentPosition?.latitude  ?? 40.4167,
          _currentPosition?.longitude ?? -3.70325,
        ),
        initialZoom: isTracking ? _kZoomCorrer : 3.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(urlTemplate: _kTileUrl,
            userAgentPackageName: 'com.runner_risk.app'),
        if (_territorios.isNotEmpty) PolygonLayer(
          polygons: _territorios.map((t) {
            final col = t.esMio ? t.color : t.colorEstadoHp;
            return Polygon(
              points: t.puntos,
              color: col.withValues(alpha: 0.22),
              borderColor: col,
              borderStrokeWidth: t.esMio ? 2.5 : 1.5,
            );
          }).toList(),
        ),
        if (isTracking && routePoints.isNotEmpty) PolylineLayer(
          polylines: [Polyline(points: routePoints,
              color: _colorTerritorio, strokeWidth: 4.5)],
        ),
        if (isTracking && _currentPosition != null) MarkerLayer(
          markers: [
            Marker(
              point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
              width: 28, height: 28,
              child: Container(
                decoration: BoxDecoration(
                  color: _kGold, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.5), blurRadius: 8)],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

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
            color: _p.parchment.withValues(alpha: 0.93),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: (_objetivoGlobal != null ? _p.globalRed : _kGold)
                    .withValues(alpha: 0.18 + _pulso.value * 0.22),
                width: 1.5),
            boxShadow: [
              BoxShadow(color: (_objetivoGlobal != null ? _p.globalRed : _kGold)
                  .withValues(alpha: 0.10 + _pulso.value * 0.08),
                  blurRadius: 20, spreadRadius: 1),
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
            if (_objetivoGlobal != null) ...[
              _hudDivider(),
              _hudStat('META', '${(_progresoGlobal * 100).toInt()}%',
                  _globalConquistado ? _kVerde : _p.globalRed),
            ] else if (_modoSolitario) ...[
              _hudDivider(),
              _hudStat('MODO', 'SOLO', _kVerde),
            ],
            if (_boostXpActivo) ...[
              _hudDivider(),
              _hudStat('BOOST', '×2', _kGoldLight),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHUDMini() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 50, 18, 0),
        child: GestureDetector(
          onTap: () => setState(() => _hudMinimizado = false),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
            decoration: BoxDecoration(
              color: _p.parchment.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: _p.goldDim.withValues(alpha: 0.45)),
              boxShadow: [BoxShadow(color: _kGold.withValues(alpha: 0.10), blurRadius: 10)],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text(_distanciaTotal.toStringAsFixed(2),
                    style: GoogleFonts.orbitron(color: _kGoldLight,
                        fontWeight: FontWeight.w900, fontSize: 14)),
                Text(' km', style: TextStyle(color: _kGold.withValues(alpha: 0.55), fontSize: 11)),
                Container(width: 1, height: 14, color: _p.goldDim.withValues(alpha: 0.4)),
                Text(_ritmoStr,
                    style: GoogleFonts.orbitron(color: _kWaterLight,
                        fontWeight: FontWeight.w900, fontSize: 14)),
                Text(' /km', style: TextStyle(color: _kWater.withValues(alpha: 0.55), fontSize: 11)),
                if (_objetivoGlobal != null) ...[
                  Container(width: 1, height: 14, color: _p.goldDim.withValues(alpha: 0.4)),
                  Text('${(_progresoGlobal * 100).toInt()}%',
                      style: GoogleFonts.orbitron(
                          color: _globalConquistado ? _kVerde : _p.globalRed,
                          fontWeight: FontWeight.w900, fontSize: 14)),
                ] else if (_modoSolitario) ...[
                  Container(width: 1, height: 14, color: _p.goldDim.withValues(alpha: 0.4)),
                  Text('SOLO', style: GoogleFonts.inter(color: _kVerde,
                      fontWeight: FontWeight.w900, fontSize: 11)),
                ],
                Icon(CupertinoIcons.chevron_down, color: _p.goldDim, size: 15),
              ],
            ),
          ),
        ),
      );

  Widget _hudStat(String label, String valor, Color color) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: GoogleFonts.inter(color: color.withValues(alpha: 0.7),
            fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1.8)),
        const SizedBox(height: 4),
        Text(valor, style: GoogleFonts.orbitron(color: Colors.white,
            fontSize: valor.length > 5 ? 14 : 18, fontWeight: FontWeight.w900,
            shadows: [Shadow(color: color.withValues(alpha: 0.55), blurRadius: 10)])),
      ]);

  Widget _hudDivider() =>
      Container(width: 1, height: 32, color: _p.goldDim.withValues(alpha: 0.35));

  Widget _buildStatTimer() => CustomTimer(
        controller: _timerController,
        builder: (state, remaining) {
          final str = isTracking
              ? '${remaining.hours}:${remaining.minutes.toString().padLeft(2,'0')}:${remaining.seconds.toString().padLeft(2,'0')}'
              : '--:--:--';
          return _hudStat('TIEMPO', str, isPaused ? _p.goldDim : _kWaterLight);
        },
      );

  Widget _buildTimerGrande() => IgnorePointer(
        child: CustomTimer(
          controller: _timerController,
          builder: (_, remaining) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: _p.parchment.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _p.goldDim.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(color: _kGold.withValues(alpha: 0.18), blurRadius: 24),
                BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 8),
              ],
            ),
            child: Text(
              '${remaining.hours}:${remaining.minutes.toString().padLeft(2,'0')}:${remaining.seconds.toString().padLeft(2,'0')}',
              style: GoogleFonts.orbitron(fontSize: 46, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: 2,
                  shadows: const [
                    Shadow(blurRadius: 22, color: _kGold),
                    Shadow(blurRadius: 45, color: Color(0x66D4722A)),
                  ]),
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
                  SizedBox(width: 100, height: 28,
                      child: CustomPaint(
                          painter: _SpeedLinesPainter(color: _p.terracotta))),
                Image.asset('assets/avatars/explorador.png',
                    width: 110, height: 110, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        Icon(CupertinoIcons.person, color: _kGold, size: 80)),
                Container(
                  width: 52, height: 9,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    gradient: RadialGradient(colors: [
                      _kGold.withValues(alpha: 0.28), Colors.transparent
                    ]),
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
        _chip('${_territoriosNotificadosEnSesion.length} invadidos', _p.terracotta, '⚔'),
      ],
      if (_globalConquistado) ...[
        const SizedBox(height: 8),
        _chip('¡Conquistado!', _kVerde, '⚔️'),
      ],
    ]);
  }

  Widget _chip(String texto, Color color, String emoji) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: _p.parchment.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 5),
          Text(texto, style: GoogleFonts.inter(color: color,
              fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _buildBotonesMapa() => Column(children: [
        _botonMapa(_modoNoche ? '🌙' : '☀️',
            _modoNoche ? _kGoldLight : _kGold, _toggleModoNoche),
        if (isTracking) ...[
          const SizedBox(height: 10),
          _botonMapa('🎯', _p.terracotta, () {
            if (_currentPosition != null) {
              _moverCamara(lat: _currentPosition!.latitude,
                  lng: _currentPosition!.longitude,
                  zoom: _kZoomCorrer, pitch: _kPitchCorrer,
                  bearing: _bearing, forzar: true);
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
            color: _p.parchment.withValues(alpha: 0.90),
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
                  _p.parchment.withValues(alpha: 0.65),
                  Colors.black.withValues(alpha: 0.60),
                ],
              ),
            ),
            child: Center(
              child: ScaleTransition(
                scale: _cuentaAtrasScale,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    _cuentaAtras > 0
                        ? '$_cuentaAtras'
                        : (_modoSolitario ? '🗺️'
                            : _objetivoGlobal != null ? '⚔️' : '⚔️'),
                    style: GoogleFonts.cinzel(fontSize: 96,
                        fontWeight: FontWeight.w900, color: Colors.white,
                        shadows: [
                          const Shadow(blurRadius: 35, color: _kGold),
                          Shadow(blurRadius: 70, color: _p.terracotta),
                          const Shadow(blurRadius: 6, color: Colors.black),
                        ]),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    decoration: BoxDecoration(
                      color: _p.parchment.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _p.goldDim),
                      boxShadow: [BoxShadow(
                          color: _kGold.withValues(alpha: 0.2), blurRadius: 14)],
                    ),
                    child: Text(
                      _cuentaAtras > 0
                          ? 'PREPÁRATE'
                          : (_modoSolitario ? '¡A EXPLORAR!'
                              : _objetivoGlobal != null
                                  ? '¡A CONQUISTAR EL MUNDO!'
                                  : '¡A CONQUISTAR!'),
                      style: GoogleFonts.cinzel(color: _kGoldLight, fontSize: 13,
                          fontWeight: FontWeight.w700, letterSpacing: 3.5),
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
              (!isTracking ? _p.cosmicMid : _p.parchment).withValues(alpha: 0.97),
              (!isTracking ? _p.cosmicMid : _p.parchment).withValues(alpha: 0.72),
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

  /// Abre FullscreenMapScreen en modo selección global.
  /// Cuando el usuario pulsa "INICIAR CONQUISTA" allí, la pantalla hace pop()
  /// con el mapa del objetivo y aquí lo recibimos para arrancar la carrera.
  Future<void> _elegirTerritorioGlobal() async {
    final resultado = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const FullscreenMapScreen(selectionMode: true),
      ),
    );
    if (resultado == null || !mounted) return;
    setState(() {
      _objetivoGlobal     = resultado;
      _modoSolitario      = false;
      _globalConquistado  = false;
      _globalConquistando = false;
    });
    final nombre = resultado['territorioNombre'] as String? ?? 'Territorio';
    final kmReq  = (resultado['kmRequeridos'] as num?)?.toDouble() ?? 0;
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _narrador.anunciarReto(
            '⚔️ Objetivo: conquistar $nombre — ${kmReq.toStringAsFixed(1)} km');
      }
    });
  }

  Widget _buildSelectorModo() {
    if (_objetivoGlobal != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _p.ink.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _p.globalRed.withValues(alpha: 0.5)),
            boxShadow: [BoxShadow(color: _p.globalRed.withValues(alpha: 0.15), blurRadius: 16)],
          ),
          child: Row(children: [
            const Text('⚔️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('GUERRA GLOBAL', style: GoogleFonts.cinzel(color: _kGoldLight,
                  fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 2),
              Text(_objetivoGlobal!['territorioNombre'] as String? ?? 'Territorio',
                  style: GoogleFonts.inter(color: _kGold, fontSize: 11,
                      fontWeight: FontWeight.w700)),
              Text('Corre ${(_objetivoGlobal!['kmRequeridos'] as num?)?.toStringAsFixed(1) ?? "?"} km para conquistar',
                  style: GoogleFonts.inter(color: _p.goldDim, fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('+${(_objetivoGlobal!['recompensa'] as num?)?.toInt() ?? 0}',
                  style: GoogleFonts.orbitron(color: _kGold, fontSize: 16,
                      fontWeight: FontWeight.w900)),
              Text('🪙 el lunes',
                  style: GoogleFonts.inter(color: _p.goldDim, fontSize: 10)),
            ]),
          ]),
        ),
        GestureDetector(
          onTap: _mostrandoCuentaAtras ? null : _iniciarCuentaAtras,
          child: AnimatedBuilder(
            animation: _pulsoAnim,
            builder: (_, child) => Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF5C0000), Color(0xFFCC2222), Color(0xFF8B0000)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                    color: _p.globalRed.withValues(alpha: 0.35 + _pulso.value * 0.2),
                    width: 1.5),
                boxShadow: [
                  BoxShadow(color: _p.globalRed.withValues(alpha: 0.12 + _pulso.value * 0.28),
                      blurRadius: 24, spreadRadius: 2, offset: const Offset(0, 5)),
                  BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8),
                ],
              ),
              child: child,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('⚔️', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 14),
              Text('INICIAR CONQUISTA',
                  style: GoogleFonts.cinzel(fontSize: 16, color: Colors.white,
                      fontWeight: FontWeight.w900, letterSpacing: 2.5)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _objetivoGlobal = null),
          child: Text('cambiar objetivo',
              style: GoogleFonts.inter(
                  color: _p.goldDim, fontSize: 11,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline)),
        ),
      ]);
    }

    final bool isCompetitivo = !_modoSolitario && _objetivoGlobal == null;
    final bool isGlobal      = _objetivoGlobal != null;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(children: [
            _modeSegment(
              label: 'Competitivo',
              active: isCompetitivo,
              activeColor: _kGoldLight,
              onTap: () async {
                setState(() => _modoSolitario = false);
                TerritoryService.invalidarCache();
                final centro = _currentPosition != null
                    ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                    : null;
                final lista = await TerritoryService.cargarTodosLosTerritorios(
                    centro: centro, modo: 'competitivo');
                if (mounted) setState(() => _territorios = lista);
                _aplicarTerritoriosFantasma();
              },
            ),
            _modeSegment(
              label: 'Solitario',
              active: _modoSolitario,
              activeColor: _kVerde,
              onTap: () async {
                setState(() => _modoSolitario = true);
                TerritoryService.invalidarCache();
                final centro = _currentPosition != null
                    ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                    : null;
                final lista = await TerritoryService.cargarTodosLosTerritorios(
                    centro: centro, modo: 'solitario');
                if (mounted) setState(() => _territorios = lista);
                _dibujarTerritoriosEnMapa();
              },
            ),
            _modeSegment(
              label: 'Global',
              active: isGlobal,
              activeColor: const Color(0xFFFF453A),
              onTap: _elegirTerritorioGlobal,
            ),
          ]),
        ),
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
                  width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: (_modoSolitario ? _kVerde : _kGold)
                        .withValues(alpha: 0.12 + _pulso.value * 0.28),
                    blurRadius: 24, spreadRadius: 2, offset: const Offset(0, 5)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8),
              ],
            ),
            child: child,
          ),
          child: Center(
            child: Text(_modoSolitario ? 'EXPLORAR' : 'CONQUISTAR',
                style: GoogleFonts.inter(fontSize: 16,
                    color: _modoSolitario ? Colors.white : _p.ink,
                    fontWeight: FontWeight.w900, letterSpacing: 2.5)),
          ),
        ),
      ),
    ]);
  }

  Widget _modeSegment({
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: active
                  ? activeColor.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: active
                  ? Border.all(
                      color: activeColor.withValues(alpha: 0.35), width: 1)
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight:
                      active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? activeColor : _p.goldDim,
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildSelectorEstiloMapa() {
    final estilos = [
      {'id': 'normal',   'emoji': '🗺️', 'label': 'Normal'},
      {'id': 'satelite', 'emoji': '🛰️', 'label': 'Satélite'},
      {'id': 'militar',  'emoji': '🎖️', 'label': 'Militar'},
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Row(children: [
          const Text('👑', style: TextStyle(fontSize: 10)),
          const SizedBox(width: 5),
          Text('ESTILO DE MAPA', style: GoogleFonts.inter(color: _p.goldDim,
              fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2)),
        ]),
      ),
      Container(
        decoration: BoxDecoration(
          color: _p.parchMid.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _p.goldDim.withValues(alpha: 0.3)),
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
                        ? _p.goldDim.withValues(alpha: 0.45) : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(e['emoji'] as String, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(e['label'] as String,
                        style: GoogleFonts.inter(fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: selected ? _kGoldLight : _p.goldDim,
                            letterSpacing: 0.5)),
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  String _mapUriParaEstilo(String estilo) {
    switch (estilo) {
      case 'satelite': return mapbox.MapboxStyles.SATELLITE_STREETS;
      case 'militar':  return mapbox.MapboxStyles.DARK;
      default: return _modoNoche ? mapbox.MapboxStyles.DARK : _kEstiloPersonalizado;
    }
  }

  Widget _buildBotonesControl() => Row(children: [
        GestureDetector(
          onTap: togglePause,
          child: Container(
            width: 62, height: 62,
            decoration: BoxDecoration(
              color: _p.parchMid, shape: BoxShape.circle,
              border: Border.all(color: _p.goldDim.withValues(alpha: 0.55), width: 1.5),
              boxShadow: [
                BoxShadow(color: _kGold.withValues(alpha: 0.12), blurRadius: 12),
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 5),
              ],
            ),
            child: Center(
                child: Text(isPaused ? '▶️' : '⏸️',
                    style: const TextStyle(fontSize: 26))),
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
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _p.terracotta.withValues(alpha: 0.35), width: 1),
                boxShadow: [
                  BoxShadow(color: _p.terracotta.withValues(alpha: 0.38),
                      blurRadius: 16, offset: const Offset(0, 4)),
                  BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6),
                ],
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_modoSolitario ? '🏁'
                    : _objetivoGlobal != null ? '🏴' : '🏳️',
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Text(
                  _modoSolitario ? 'FINALIZAR'
                      : _objetivoGlobal != null
                          ? (_globalConquistado ? 'MISIÓN CUMPLIDA' : 'RETIRADA')
                          : 'RETIRADA',
                  style: GoogleFonts.cinzel(fontSize: 15, fontWeight: FontWeight.w700,
                      color: const Color(0xFFFFE0C0), letterSpacing: 2.5),
                ),
              ]),
            ),
          ),
        ),
      ]);
}

class _SpeedLinesPainter extends CustomPainter {
  final Color color;
  const _SpeedLinesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color.withValues(alpha: 0.32)
      ..strokeWidth = 1.5
      ..style       = PaintingStyle.stroke;
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