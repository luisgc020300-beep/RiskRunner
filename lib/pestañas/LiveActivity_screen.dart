import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show Factory, kIsWeb;
import 'package:flutter/gestures.dart' show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:custom_timer/custom_timer.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../services/territory_service.dart';
import '../services/game_state_service.dart';
import '../services/route_service.dart';
import '../widgets/custom_navbar.dart';
import '../services/anticheat_service.dart';
import '../services/stats_service.dart';
import '../services/local_notif_service.dart';
import '../services/league_service.dart';
import '../services/subscription_service.dart';
import '../widgets/conquista_overlay.dart';
import '../widgets/anticheat_warning_overlay.dart';
import '../widgets/narrador_overlay.dart';
import '../services/narrador_service.dart';
import '../services/desafios_service.dart';
import '../services/presence_service.dart';
import '../services/health_service.dart';
import 'package:shimmer/shimmer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/ranking_service.dart';
import '../services/onboarding_service.dart';
import '../services/activity_service.dart';
import '../config/env.dart';
import '../widgets/live_activity/live_starfield.dart';
import '../models/avatar_config.dart';
import '../widgets/avatar_painter.dart';
import '../controllers/territory_notifier.dart';
import '../theme/app_colors.dart';
import '../services/run_session_notifier.dart';
import '../services/tracking_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

part 'live_selector_modo.dart';
part 'live_globe_overlay.dart';
part 'live_session_controls.dart';
part 'live_territory_ui.dart';

// =============================================================================
// PALETA
// =============================================================================
const _kGold       = Color(0xFFFFD60A);
const _kGoldLight  = Color(0xFFFFD60A);
const _kWater      = Color(0xFF5BA3A0);
const _kWaterLight = Color(0xFF8ECFCC);
const _kVerde      = Color(0xFF8FAF4A);


// Fondo universo azul oscuro
const _kUniverseBg = Color(0xFF020B18);

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
    cosmicBg:   _kUniverseBg,       // azul universo
    cosmicMid:  Color(0xFF0A1628),  // azul oscuro medio
    goldDim:    Color(0xFF636366),
    terracotta: Color(0xFF8E8E93),
    globalRed:  Color(0xFF8E8E93),
  );
  static _LP of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? dark : light;
}

// aliases para los call sites existentes
typedef _StarfieldWidget   = LiveStarfieldWidget;

// =============================================================================
// CONSTANTES GPS / CÁMARA
// =============================================================================
const double _kPitchCorrer  = 55.0;
const double _kPitchNormal  = 0.0;
const double _kPitchPausado = 65.0;
const double _kZoomCorrer   = 18.5;
const double _kZoomPausado  = 15.5;
const double _kZoomGlobo   = 5;

const String _kEstiloPersonalizado = 'mapbox://styles/mapbox/outdoors-v12';


const _kPresenciaMovimientoSeg = 15;
const _kPresenciaPausadoSeg    = 45;

final Map<int, Uint8List> _avatarCache = {};
const int _kAvatarCacheMax = 50;

// =============================================================================
// MODELO BARRIO
// =============================================================================
class _BarrioData {
  final String       nombre;
  final List<LatLng> puntos;
  final double       areaM2;
  double             porcentajeCubierto = 0.0;

  _BarrioData({
    required this.nombre,
    required this.puntos,
    required this.areaM2,
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
  // Ruta guardada de otro jugador que el usuario quiere correr guiado
  final RouteData? rutaGuiada;
  const LiveActivityScreen({super.key, this.onFinish, this.rutaGuiada});

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
    interval: CustomTimerInterval.seconds,
  );
  final Stopwatch _stopwatch = Stopwatch();

  // ── Mapbox
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _annotationManager;
  final Map<String, mapbox.PointAnnotation> _anotacionesJugadores = {};
  final Map<String, mapbox.PointAnnotation> _anotacionesReyes = {};
  Uint8List? _coronaBytes;

  // ── Avatar animado en el puck de posición
  AvatarConfig _avatarConfig = const AvatarConfig();
  List<Uint8List> _puckFrames = [];
  int   _puckFrameIdx  = 0;
  Timer? _puckAnimTimer;
  bool  _puckBuilding       = false;
  bool  _puckRebuildPending = false;
  bool  _puckUpdating       = false;
  Uint8List? _emptyPng;

  // ── GPS
  List<TerritoryData> _territoriosRivalesCercanos = [];
  TerritoryData? _territorioActualBajoPie;
  List<LatLng> routePoints           = [];
  late final RunSessionNotifier _session = RunSessionNotifier();
  Timer? _timerSesion;
  double _bearing                    = 0.0;
  // Bearing re-lock: user rotated the map manually; GPS heading resumes after _kRelockMs
  bool  _userRotatedMap        = false;
  Timer? _relockTimer;
  bool  _movingProgrammatically = false;
  Timer? _progMoveTimer;
  static const int _kRelockMs = 5000;
  late final _tracking = TrackingService(session: _session, antiCheat: _antiCheat);
  StreamSubscription<TrackingEvent>? _trackingEventsSub;
  Position? _currentPosition;
  ScaffoldFeatureController? _gpsSnackBar;

  // ── Barrios OSM (modo solitario)
  List<_BarrioData> _barriosCercanos   = [];
  _BarrioData?      _barrioActual;
  static const String _barrioSourceId     = 'barrios-source';
  static const String _barrioFillLayerId  = 'barrios-fill';
  static const String _barrioLineLayerId  = 'barrios-line';
  static const String _barrioLabelLayerId = 'barrios-label';
  bool _barriosLayerCreated            = false;
  bool _barriosCargando                = false;

  int _puntosDesdeUltimoUpdate       = 0;
  static const int _kActualizarMapaCadaN = 3;
  DateTime _ultimoMovCamara = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kMinMsCamara = 800;

  // ── Modo de juego
  late final _modeCtrl = TerritoryNotifier();
  bool get _modoSolitario => _modeCtrl.modoSolitario;
  set _modoSolitario(bool v) => _modeCtrl.modoSolitario = v;
  bool get _modoRuta => _modeCtrl.modoRuta;
  set _modoRuta(bool v) => _modeCtrl.modoRuta = v;

  // ── Ruta guiada (cargada desde RutasExploradorScreen)
  RouteData? _rutaGuiada;
  bool   _ghostLayerCreated    = false;
  static const _kGhostSourceId = 'ghost-route-source';
  static const _kGhostLayerId  = 'ghost-route-layer';
  int    _checkpointActual     = 0;
  bool   _narratorRutaIniciado = false;
  Timer? _timerCheckRuta;

  // ── Jugador
  Color  get _colorTerritorio      => _modeCtrl.colorTerritorio;
  List<TerritoryData> get _territorios => _modeCtrl.territorios;
  set _territorios(List<TerritoryData> v) => _modeCtrl.territorios = v;
  bool get _territoriosCargados => _modeCtrl.territoriosCargados;
  set _territoriosCargados(bool v) => _modeCtrl.territoriosCargados = v;
  bool   _fantasmasCargando    = false;
  String _miNickname           = 'Alguien';
  bool   _boostXpActivo        = false;

  final Set<String>            _territoriosNotificadosEnSesion = {};
  final Set<String>            _territoriosVisitadosEnSesion   = {};
  final Map<String, DateTime>  _ultimaNotifRival               = {};

  StreamSubscription? _jugadoresStream;
  StreamSubscription<List<TerritoryData>>? _competitiveStreamSub;
  StreamSubscription<List<TerritoryData>>? _solitarioStreamSub;
  final Map<String, Map<String, dynamic>> _jugadoresActivos = {};
  bool  get _mapaDesactualizado => _modeCtrl.mapaDesactualizado;
  Timer? _streamReconectarTimer;

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
  static const String _borderOuterGlowId  = 'territorios-border-outer-glow';
  static const String _sourceId            = 'territorios-source';
  static const String _centrosSourceId     = 'territorios-centros-source';
  static const String _centrosLayerId      = 'territorios-centros-layer';
  static const String _globalesSourceId    = 'globales-centros-src';
  static const String _globalesLayerId     = 'globales-centros-layer';
  static const String _globalesSelSourceId = 'globales-sel-src';
  static const String _globalesSelLayerId  = 'globales-sel-layer';
  static const String _puntosGloboSrcId      = 'puntosGlobo-src';
  static const String _puntosGloboLayerId    = 'puntosGlobo-layer';
  static const String _puntosGloboGlowLayerId = 'puntosGlobo-glow-layer';
  static const String _rutasPreviewSrcId    = 'rutas-preview-src';
  static const String _rutasPreviewLayerId  = 'rutas-preview-layer';
  static const String _kTileUrl =
      'https://api.mapbox.com/styles/v1/${Env.mapboxStyleId}'
      '/tiles/256/{z}/{x}/{y}@2x?access_token=${Env.mapboxPublicToken}';

  bool _routeLayerCreated        = false;
  bool _buildings3dCreated       = false;
  bool _territoriosLayersCreated = false;
  bool _previewLayerCreated      = false;
  bool get _zonaValida               => _modeCtrl.zonaValida;

  static const String _previewSourceId     = 'territory-preview-src';
  static const String _previewLayerId      = 'territory-preview-layer';
  static const String _previewBorderLayerId = 'territory-preview-border';
  bool _centrosLayerCreated      = false;
  bool _styleLoaded              = false;
  int  _dibujadosGen             = 0;
  bool _rutasPreviewLayerCreated = false;
  List<RouteData> _rutasPreview  = [];

  // Web fallback (flutter_map)
  MapController? _webMapCtrl;

  Timer? _pulsoTimer;
  Timer? _dibujandoDebounce;
  TerritoryData? _territorioInfo;
  Timer? _infoTimer;
  double _pulsoOpacity = 0.9;
  Timer? _iluminacionTimer;
  bool   _pulsoUp      = false;

  // ── Narrador
  final NarradorService _narrador = NarradorService();
  double _distanciaUltimoAnalisisRitmo  = 0;
  int    _minutosResistenciaNotificados = 0;
  Timer? _timerResistencia;

  // ── Reto activo desde Home
  Map<String, dynamic>? _retoActivo;
  bool get _retoCompletado => _modeCtrl.retoCompletado;

  // ── GUERRA GLOBAL
  Map<String, dynamic>? get _objetivoGlobal => _modeCtrl.objetivoGlobal;
  set _objetivoGlobal(Map<String, dynamic>? v) => _modeCtrl.objetivoGlobal = v;
  bool get _globalConquistado   => _modeCtrl.globalConquistado;
  bool get _globalConquistando  => _modeCtrl.globalConquistando;
  bool get _globalKmAlcanzados  => _modeCtrl.globalKmAlcanzados;
  double? get _nuevaClausula   => _modeCtrl.nuevaClausula;
  StreamSubscription<DocumentSnapshot>? _globalTerritoryStream;
  StreamSubscription<RemoteMessage>?    _fcmSub;
  String? _globalTerritoryLastOwner;
  bool _stopping = false;

  // ── PUNTOS DE TERRITORIOS EN EL GLOBO
  List<Map<String, dynamic>> _puntosGlobo       = [];
  bool _puntosGloboCargados                     = false;
  bool _puntosGloboLayerCreated                 = false;
  bool _actualizandoGloboLayer                  = false;
  bool _dibujandoTerritorios                    = false;


  // ── SELECCIÓN GLOBAL EN GLOBO
  bool get _seleccionandoGlobal => _modeCtrl.seleccionandoGlobal;
  set _seleccionandoGlobal(bool v) => _modeCtrl.seleccionandoGlobal = v;
  bool _mostrarSituacion     = false;
  List<GlobalTerritory> _terrGlobales = [];
  bool   _cargandoGlobales      = false;
  String _modoAnteriorGlobal    = 'competitivo';
  bool   _globalesLayerCreated  = false;
  bool   _globalesSelLayerCreated = false;
  Timer? _globalesPulseTimer;
  Timer? _timerRefreshGlobo;
  double _globalesPulseT        = 0.0;
  bool   _globalesPulseUpdating = false;
  GlobalTerritory? _terrPreviseleccionado;

  // ==========================================================================
  // INIT / DISPOSE
  // ==========================================================================
  @override
  void initState() {
    super.initState();
    _modoNoche = _esHoraNoche();

    StatsService.mapboxToken = Env.mapboxPublicToken;

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

    // Ruta guiada pasada desde RutasExploradorScreen
    if (widget.rutaGuiada != null) {
      _rutaGuiada    = widget.rutaGuiada;
      _modoRuta      = true;
      _modoSolitario = false;
      GameStateService.instance.currentMode = 'ruta';
    }

    _determinePosition();
    final savedMode = GameStateService.instance.currentMode;
    if (savedMode == 'ruta') { _modoRuta = true; _modoSolitario = false; }
    else if (savedMode == 'solitario') { _modoSolitario = true; }
    _cargarDatosIniciales();
    _escucharJugadoresActivos();
    _suscribirStreamTerritorios();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkPendingSession();
    });

    _narrador.onMensaje = (msg) {
      _session.setNarratorMessage(msg);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args == null) return;

      if (args['retoActivo'] != null) {
        final reto = args['retoActivo'] as Map<String, dynamic>;
        setState(() {
          _retoActivo    = reto;
          _modoRuta      = true;
          _modoSolitario = false;
          _territorios   = [];
        });
        GameStateService.instance.currentMode = 'ruta';
        final titulo         = reto['titulo'] as String? ?? 'Reto';
        final objetivoMetros =
            (reto['objetivo_valor'] as num?)?.toDouble() ?? 0;
        _narrador.configurarReto(titulo, objetivoMetros);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _narrador.anunciarReto(titulo);
        });
      }

      if (args['forzarModoRuta'] == true) {
        setState(() {
          _modoRuta      = true;
          _modoSolitario = false;
          _objetivoGlobal = null;
        });
        GameStateService.instance.currentMode = 'ruta';
        if (_territorios.isNotEmpty) setState(() => _territorios = []);
      }

      if (args['objetivoGlobal'] != null) {
        final objetivo = args['objetivoGlobal'] as Map<String, dynamic>;
        _modeCtrl.setObjetivoGlobal(objetivo);
        _modeCtrl.resetConquistaGlobal();
        setState(() { _modoSolitario = false; });
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

  // ── Session persistence ────────────────────────────────────────────────────

  Future<void> _checkPendingSession() async {
    final session = await GameStateService.instance.restoreSession();
    if (session == null || !mounted) return;

    final rawPoints = session['points'] as List<dynamic>? ?? [];
    if (rawPoints.isEmpty) return;

    final pts = rawPoints.map((p) {
      final m = p as Map<String, dynamic>;
      return LatLng(
        (m['lat'] as num).toDouble(),
        (m['lng'] as num).toDouble(),
      );
    }).toList();

    final bool? restore = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Carrera en progreso'),
        content: const Text(
            'Tienes una carrera anterior sin terminar. ¿Quieres continuar?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Descartar'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (restore == true) {
      final mode        = session['mode'] as String? ?? 'competitivo';
      final distanciaKm = (session['distanciaKm'] as num?)?.toDouble() ?? 0;
      setState(() {
        routePoints.addAll(pts);
        _modoSolitario  = mode == 'solitario';
        _modoRuta       = mode == 'ruta';
      });
      _session.resumeSession(distanciaKm);
      GameStateService.instance.currentMode = mode;
    } else {
      await GameStateService.instance.clearSession();
    }
  }

  void _iniciarTimerSesion() {
    _timerSesion?.cancel();
    _timerSesion = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_session.isTracking || _session.isPaused || _sesionInvalidadaPorCheat) return;
      final pts = routePoints
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList();
      GameStateService.instance.saveSession(
        mode:           GameStateService.instance.currentMode,
        points:         pts,
        distanciaKm:    _session.distanciaTotal,
        elapsedSeconds: _stopwatch.elapsed.inSeconds,
      );
    });
  }

  @override
  void dispose() {
    _timerSesion?.cancel();
    _puckAnimTimer?.cancel();
    _timerController.dispose();
    _timerCuentaAtras?.cancel();
    _trackingEventsSub?.cancel();
    _tracking.dispose();
    _jugadoresStream?.cancel();
    _competitiveStreamSub?.cancel();
    _solitarioStreamSub?.cancel();
    _streamReconectarTimer?.cancel();
    TerritoryService.stopRealtimeListener();
    _globalTerritoryStream?.cancel();
    _timerPublicarPosicion?.cancel();
    _timerCheckRuta?.cancel();
    _pulsoTimer?.cancel();
    _dibujandoDebounce?.cancel();
    _infoTimer?.cancel();
    _timerResistencia?.cancel();
    _iluminacionTimer?.cancel();
    _globalesPulseTimer?.cancel();
    _timerRefreshGlobo?.cancel();
    _relockTimer?.cancel();
    _progMoveTimer?.cancel();
    _fcmSub?.cancel();
    _anotacionesJugadores.clear();
    _narrador.resetear();
    _session.dispose();
    _modeCtrl.dispose();
    _cuentaAtrasAnim.dispose();
    _hudAnim.dispose();
    _bounceAnim.dispose();
    _pulsoAnim.dispose();
    _globoAnim.dispose();
    _limpiarPresenciaFirestore();
    WakelockPlus.disable();
    super.dispose();
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================
  void _rotarGlobo() {
    if (_session.isTracking) return;
    if (kIsWeb) return;
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
      _buildings3dCreated       = false;
      _territoriosLayersCreated = false;
      _centrosLayerCreated      = false;
      _globalesLayerCreated      = false;
      _globalesSelLayerCreated   = false;
      _globalesPulseTimer?.cancel();
      _globalesPulseTimer        = null;
      _puntosGloboLayerCreated   = false;
      _actualizandoGloboLayer   = false;
      _dibujandoTerritorios     = false;
      _routeLayerCreated        = false;
      _ghostLayerCreated        = false;
      _rutasPreviewLayerCreated = false;
      _styleLoaded              = false;
      _mapboxMap?.loadStyleURI(_mapStyle);
    }
  }

  String get _mapStyle {
    if (_estiloMapa == 'satelite') return mapbox.MapboxStyles.SATELLITE_STREETS;
    if (_estiloMapa == 'militar')  return mapbox.MapboxStyles.DARK;
    return _modoNoche ? mapbox.MapboxStyles.DARK : _kEstiloPersonalizado;
  }

  String get _ritmoStr => _session.ritmoStr;

  String _colorToHex(Color c) =>
      '#${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}'
      '${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}'
      '${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}';

  Future<void> _buildAvatarPuckFrames() async {
    if (_puckBuilding) {
      _puckRebuildPending = true;
      return;
    }
    _puckRebuildPending = false;
    _puckBuilding = true;
    _puckAnimTimer?.cancel();

    // Generate a 1×1 transparent PNG once, used to explicitly disable
    // the Mapbox SDK's default bearing/shadow images (which are green).
    if (_emptyPng == null) {
      final rec = ui.PictureRecorder();
      Canvas(rec);
      final pic = rec.endRecording();
      final img = await pic.toImage(1, 1);
      final bd  = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bd != null) _emptyPng = bd.buffer.asUint8List();
    }

    const int kN     = 12;
    const double kSz = 128.0;
    final capturedConfig = _avatarConfig;
    final frames = <Uint8List>[];

    for (int i = 0; i < kN; i++) {
      final rec = ui.PictureRecorder();
      AvatarPainter(config: capturedConfig, runPhase: i / kN)
          .paint(Canvas(rec), const Size(kSz, kSz));
      final pic = rec.endRecording();
      final img = await pic.toImage(kSz.toInt(), kSz.toInt());
      final bd  = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bd != null) frames.add(bd.buffer.asUint8List());
      if (!mounted) { _puckBuilding = false; return; }
    }

    _puckBuilding = false;
    if (frames.isEmpty || !mounted || _mapboxMap == null) return;

    _puckFrames   = frames;
    _puckFrameIdx = 0;
    await _applyPuckFrame(frames[0]);

    // If avatar config changed while we were building, rebuild with latest config.
    if (_puckRebuildPending) {
      _buildAvatarPuckFrames();
      return;
    }

    _puckAnimTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || !_session.isTracking || _session.isPaused) return;
      _puckFrameIdx = (_puckFrameIdx + 1) % _puckFrames.length;
      _applyPuckFrame(_puckFrames[_puckFrameIdx]);
    });
  }

  Future<void> _applyPuckFrame(Uint8List bytes) async {
    if (_mapboxMap == null || _puckUpdating) return;
    _puckUpdating = true;
    try {
      await _mapboxMap!.location.updateSettings(mapbox.LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: false,
        locationPuck: mapbox.LocationPuck(
          locationPuck2D: mapbox.DefaultLocationPuck2D(
            topImage: bytes,
            bearingImage: _emptyPng,
            shadowImage: _emptyPng,
          ),
        ),
      ));
    } catch (_) {}
    _puckUpdating = false;
  }

  String _encodeJson(dynamic obj) {
    if (obj is Map) {
      return '{${obj.entries.map((e) => '"${e.key}":${_encodeJson(e.value)}').join(',')}}';
    }
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
      final data = await ActivityService.cargarConfigJugador(user.uid);
      if (data != null) {
        _miNickname = data['nickname'] ?? 'Alguien';
        final colorInt = (data['territorio_color'] as num?)?.toInt();
        if (colorInt != null && mounted) {
          _modeCtrl.setColorTerritorio(Color(colorInt));
        }
        final boost  = data['boost_xp_activo'] as bool? ?? false;
        final expira = data['boost_xp_expira'] as Timestamp?;
        if (boost && expira != null && expira.toDate().isAfter(DateTime.now())) {
          if (mounted) setState(() => _boostXpActivo = true);
        }
        final av = data['avatar_config'] as Map<String, dynamic>?;
        if (av != null) {
          try { _avatarConfig = AvatarConfig.fromMap(av); } catch (_) {}
          if (_mapboxMap != null && mounted) _buildAvatarPuckFrames();
        }
        // Tutorial de primer uso
        final onb = await OnboardingService.cargarEstado();
        if (mounted && !onb.tooltipsVistos.contains('modos_tutorial')) {
          Future.delayed(const Duration(milliseconds: 900), _mostrarTutorialModos);
        }
      }
      LatLng? centro;
      if (_currentPosition != null) {
        centro = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      } else {
        try {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) centro = LatLng(last.latitude, last.longitude);
        } catch (_) {}
      }
      // Arrancar listener en tiempo real en cuanto tenemos posición
      if (centro != null) TerritoryService.startRealtimeListener(centro: centro);

      if (!_modoRuta) {
        final modo = _modoSolitario ? 'solitario' : 'competitivo';
        // 1. Caché válida → mostrar al instante
        final cached = _modoSolitario
            ? GameStateService.instance.getSolitarioTerritories()
            : GameStateService.instance.getCompetitiveTerritories();
        if (cached != null && mounted) {
          setState(() { _territorios = List<TerritoryData>.from(cached); _territoriosCargados = true; });
          _dibujarTerritoriosEnMapa();
          _aplicarTerritoriosFantasma();
        } else {
          // 2. Caché expirada → mostrar stale mientras refrescamos en background
          final stale = _modoSolitario
              ? GameStateService.instance.getStaleSolitarioTerritories()
              : GameStateService.instance.getStaleCompetitiveTerritories();
          if (stale != null && mounted) {
            setState(() { _territorios = List<TerritoryData>.from(stale); _territoriosCargados = true; });
            _dibujarTerritoriosEnMapa();
            _aplicarTerritoriosFantasma();
          }
          // 3. Sin centro GPS aún → intentar obtenerlo antes de la carga Firestore
          if (centro == null) {
            try {
              final pos = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
              ).timeout(const Duration(seconds: 6));
              centro = LatLng(pos.latitude, pos.longitude);
              if (mounted) setState(() => _currentPosition = pos);
            } catch (_) {}
          }
          final lista = await TerritoryService.cargarTodosLosTerritorios(
              centro: centro, modo: modo);
          if (mounted && !_modoRuta) {
            setState(() { _territorios = lista; _territoriosCargados = true; });
            if (_modoSolitario) {
              GameStateService.instance.setSolitarioTerritories(lista);
            } else {
              GameStateService.instance.setCompetitiveTerritories(lista);
            }
            _dibujarTerritoriosEnMapa();
            _aplicarTerritoriosFantasma();
          }
        }
      }
    } catch (e, st) {
      debugPrint('Error datos iniciales: $e');
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'initData');
    }

    // Precargar territorios globales desde cache para que el botón Global sea instantáneo.
    // Se ejecuta después de la carga principal para no bloquear el arranque.
    final cachedGlobal = GameStateService.instance.getGlobalTerritories();
    if (cachedGlobal != null && mounted && _terrGlobales.isEmpty) {
      setState(() { _terrGlobales = List<GlobalTerritory>.from(cachedGlobal); });
    }
  }

  // ==========================================================================
  // TUTORIAL MODOS (primer uso)
  // ==========================================================================
  Future<void> _mostrarTutorialModos() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _buildTutorialSheet(),
    );
    OnboardingService.marcarTooltipVisto('modos_tutorial');
  }

  Widget _buildTutorialSheet() {
    const modos = [
      (
        icon: Icons.people_rounded,
        color: Color(0xFF0A84FF),
        titulo: 'Competitivo',
        desc: 'Corre y conquista zonas. Compite con otros corredores de tu ciudad.',
      ),
      (
        icon: Icons.explore_rounded,
        color: Color(0xFF30D158),
        titulo: 'Solitario',
        desc: 'Explora barrios. Cubre el máximo porcentaje de cada zona tú solo.',
      ),
      (
        icon: Icons.route_rounded,
        color: Color(0xFF6A4A9B),
        titulo: 'Ruta',
        desc: 'Elige una ruta guardada o crea la tuya. Corre siguiendo el trazado y bate tu mejor marca.',
      ),
      (
        icon: Icons.public_rounded,
        color: Color(0xFFFF453A),
        titulo: 'Global',
        desc: 'Guerras mundiales semanales. Elige un territorio en el globo y corre para conquistarlo.',
      ),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 18),
        Text('¿Cómo funciona?', style: GoogleFonts.inter(
          color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Elige tu modo cada vez que salgas a correr',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 20),
        ...modos.map((m) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: m.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: m.color.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: m.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(m.icon, color: m.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.titulo, style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(m.desc, style: GoogleFonts.inter(
                  color: Colors.white60, fontSize: 11, height: 1.4)),
            ])),
          ]),
        )),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('¡Entendido!', textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  // ==========================================================================
  // ACTIVITY FEED — escribe conquistas para el feed global
  // ==========================================================================
  Future<void> _escribirActivityFeed({
    required String territoryName,
    required String territoryId,
    required String mode,
    String? previousOwnerNick,
    int fromColorValue = 0xFFCC2222,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await ActivityService.publicarConquistaFeed(
      uid:               uid,
      nickname:          _miNickname,
      territoryId:       territoryId,
      territoryName:     territoryName,
      mode:              mode,
      previousOwnerNick: previousOwnerNick,
      fromColorValue:    fromColorValue,
    );
    await ActivityService.escribirHistorialConquista(
      territoryId:       territoryId,
      ownerNickname:     _miNickname,
      ownerColorValue:   fromColorValue,
      previousOwnerNick: previousOwnerNick,
    );
  }

  Future<void> _determinePosition() async {
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          p == LocationPermission.deniedForever
              ? 'Ubicación bloqueada. Ve a Ajustes → Permisos → Ubicación para activarla.'
              : 'RiskRunner necesita acceso a tu ubicación para funcionar.',
          style: const TextStyle(fontSize: 13),
        ),
        backgroundColor: AppColors.red,
        duration: const Duration(seconds: 6),
        action: p == LocationPermission.deniedForever
            ? SnackBarAction(
                label: 'AJUSTES',
                textColor: Colors.white,
                onPressed: () => Geolocator.openAppSettings(),
              )
            : null,
      ));
      return;
    }
    if (p == LocationPermission.always || p == LocationPermission.whileInUse) {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) {
        final anteriorCentro = _currentPosition;
        setState(() => _currentPosition = pos);

        final debeCargarse = anteriorCentro == null ||
            Geolocator.distanceBetween(anteriorCentro.latitude,
                anteriorCentro.longitude, pos.latitude, pos.longitude) > 500;

        if (debeCargarse && (anteriorCentro == null || _territoriosCargados) && !_modoRuta) {
          TerritoryService.invalidarCache();
          GameStateService.instance.invalidateTerritories();
          final centro = LatLng(pos.latitude, pos.longitude);
          final lista  = await TerritoryService.cargarTodosLosTerritorios(
              centro: centro, modo: _modoSolitario ? 'solitario' : 'competitivo');
          if (mounted) {
            setState(() => _territorios = lista);
            if (_modoSolitario) {
              GameStateService.instance.setSolitarioTerritories(lista);
            } else {
              GameStateService.instance.setCompetitiveTerritories(lista);
            }
            _dibujarTerritoriosEnMapa();
          }
        }
        _aplicarTerritoriosFantasma();
      }
    }
  }

  // ==========================================================================
  // BARRIOS OSM — modo solitario

  double _calcularPorcentajeBarrio(
      _BarrioData barrio, List<TerritoryData> misTerritorios) {
    if (barrio.areaM2 <= 0) return 0.0;
    double areaCubierta = 0.0;
    for (final ter in misTerritorios) {
      if (_puntoEnPoligono(ter.centro, barrio.puntos)) {
        areaCubierta += TerritoryService.calcularAreaM2(ter.puntos);
      }
    }
    return (areaCubierta / barrio.areaM2).clamp(0.0, 1.0);
  }

  Future<void> _dibujarBarriosEnMapa() async {
    if (_mapboxMap == null || _barriosCercanos.isEmpty) return;
    if (_barriosCargando && !_barriosLayerCreated) return;
    _barriosCargando = true;
    if (!_modoSolitario) return;

    final features = _barriosCercanos.map((b) {
      final coords = b.puntos.map((p) => [p.longitude, p.latitude]).toList();
      if (coords.first[0] != coords.last[0] ||
          coords.first[1] != coords.last[1]) {
        coords.add(coords.first);
      }
      final pct = b.porcentajeCubierto;
      final String color = pct >= 1.0
          ? '#30D158'
          : pct > 0
              ? '#FF9500'
              : '#8E8E93';
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

      await _mapboxMap!.style.addLayer(
          mapbox.FillLayer(id: _barrioFillLayerId, sourceId: _barrioSourceId));
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioFillLayerId, 'fill-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioFillLayerId, 'fill-opacity', 0.12);

      await _mapboxMap!.style.addLayer(
          mapbox.LineLayer(id: _barrioLineLayerId, sourceId: _barrioSourceId));
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLineLayerId, 'line-color', '#FFFFFF');
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLineLayerId, 'line-width', 3.0);
      await _mapboxMap!.style.setStyleLayerProperty(
          _barrioLineLayerId, 'line-opacity', 0.88);

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
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'dibujar_barrios');
    } finally {
      _barriosCargando = false;
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
          await ActivityService.acreditarMonedas(user.uid, bonusMonedas);
          await ActivityService.enviarNotificacion({
            'toUserId':     user.uid,
            'type':         'barrio_completado',
            'message':      'Has conquistado el barrio de ${barrio.nombre}! +$bonusMonedas monedas',
            'barrioNombre': barrio.nombre,
            'bonusMonedas': bonusMonedas,
          });
          if (mounted) _mostrarNotificacionBarrioCompletado(barrio, bonusMonedas);
        } catch (e, st) {
          FirebaseCrashlytics.instance.recordError(e, st, reason: 'acreditar_bonus_barrio');
          debugPrint('Error bonus barrio ${barrio.nombre}: $e');
        }
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
    // El annotation manager se va a recrear — limpiar referencias huérfanas
    _anotacionesJugadores.clear();
    _anotacionesReyes.clear();
    await map.style.setProjection(
        mapbox.StyleProjection(name: mapbox.StyleProjectionName.globe));
    await map.gestures.updateSettings(mapbox.GesturesSettings(
      rotateEnabled: true,
      pitchEnabled: false,
      scrollEnabled: true,
      pinchToZoomEnabled: true,
      doubleTapToZoomInEnabled: true,
      doubleTouchToZoomOutEnabled: true,
      simultaneousRotateAndPinchToZoomEnabled: true,
      scrollDecelerationEnabled: true,
      rotateDecelerationEnabled: true,
      quickZoomEnabled: false,
    ));
    _annotationManager =
        await map.annotations.createPointAnnotationManager();
    _buildAvatarPuckFrames();
    await _moverCamara(
      lat: _currentPosition?.latitude ?? 40.4167,
      lng: _currentPosition?.longitude ?? -3.70325,
      zoom: _kZoomGlobo,
      bearing: 0,
      pitch: _kPitchNormal,
      animated: false,
    );
    _iluminacionTimer?.cancel();
    _iluminacionTimer = Timer.periodic(const Duration(minutes: 20), (_) {
      if (!mounted) return;
      _configurarAtmosfera();
      _mejorarAgua();
    });
  }

  void _onStyleLoaded(mapbox.StyleLoadedEventData _) async {
    _styleLoaded = true;
    if (!mounted) return;
    // Territorios, atmósfera y edificios arrancan todos en paralelo.
    // Los edificios tienen su propia lógica de reintento sin bloquear el resto.
    await Future.wait([
      _configurarAtmosfera(),
      _mejorarAgua(),
      _dibujarTerritoriosEnMapa(),
      if (_objetivoGlobal != null) _cargarYMostrarPuntosGlobo(),
      if (_objetivoGlobal != null) Future.sync(() {
        _timerRefreshGlobo?.cancel();
        _timerRefreshGlobo = Timer.periodic(const Duration(minutes: 5), (_) {
          if (!mounted) return;
          _puntosGloboCargados = false;
          _cargarYMostrarPuntosGlobo();
        });
        _fcmSub?.cancel();
        _fcmSub = FirebaseMessaging.onMessage.listen((msg) {
          if (!mounted) return;
          if (msg.data['type'] == 'territory_refresh') {
            _puntosGloboCargados = false;
            _cargarYMostrarPuntosGlobo();
          }
        });
      }),
      if (_rutaGuiada != null) _dibujarGhostRuta(),
      if (_modoRuta) _cargarYDibujarRutasPreview(),
      if (routePoints.length >= 2) _actualizarRutaEnMapa(),
      _cargarBuildings3DConRetry(),
    ]);
  }

  Future<void> _cargarBuildings3DConRetry() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    await _addBuildings3D();
    if (!_buildings3dCreated) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) await _addBuildings3D();
    }
    if (!_buildings3dCreated) {
      await Future.delayed(const Duration(milliseconds: 2000));
      if (mounted) await _addBuildings3D();
    }
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
    _movingProgrammatically = true;
    _progMoveTimer?.cancel();
    if (animated) {
      // Keep flag true until 100 ms after the animation ends
      _progMoveTimer = Timer(Duration(milliseconds: duracion + 100), () {
        _movingProgrammatically = false;
      });
      await _mapboxMap!.flyTo(
          cam, mapbox.MapAnimationOptions(duration: duracion));
    } else {
      await _mapboxMap!.setCamera(cam);
      _movingProgrammatically = false;
    }
  }


  void _onCameraChanged(mapbox.CameraChangedEventData _) {
    if (!mounted || _movingProgrammatically || !_session.isTracking || _session.isPaused) return;
    if (!_userRotatedMap) setState(() => _userRotatedMap = true);
    _relockTimer?.cancel();
    _relockTimer = Timer(const Duration(milliseconds: _kRelockMs), () {
      if (mounted) setState(() => _userRotatedMap = false);
    });
  }

  Future<void> _configurarAtmosfera() async {
    if (_mapboxMap == null) return;
    try {
      // Iluminación fija según modo claro/oscuro — sin depender de la hora real.
      const double azFijo   = 180.0; // sur
      const double elevFijo = 45.0;  // mediodía
      const double polarFijo = 45.0;
      final night = _modoNoche;

      final layers = await _mapboxMap!.style.getStyleLayers();
      if (!layers.any((l) => l?.id == 'sky-layer')) {
        await _mapboxMap!.style.addLayer(mapbox.SkyLayer(id: 'sky-layer'));
      }

      if (night) {
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-type', 'atmosphere');
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-color', 'rgba(2,8,22,1)');
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-halo-color', 'rgba(5,12,40,0.9)');
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-sun-intensity', 0.0);
      } else {
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-type', 'atmosphere');
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-color', 'rgba(120,195,255,1)');
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-halo-color', 'rgba(195,228,255,0.9)');
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-sun', [azFijo, polarFijo]);
        await _mapboxMap!.style.setStyleLayerProperty(
            'sky-layer', 'sky-atmosphere-sun-intensity', 22.0);
      }
      await _mapboxMap!.style.setStyleLayerProperty(
          'sky-layer', 'sky-opacity', 1.0);

      await _aplicarIluminacion(azFijo, elevFijo, night, false);
    } catch (e) {
      debugPrint('_configurarAtmosfera: $e');
    }
  }


  Future<void> _aplicarIluminacion(
      double az, double elev, bool night, bool golden) async {
    try {
      final int colorArgb;
      final double intensity;
      if (night) {
        colorArgb = 0xFF2A345F; intensity = 0.12;
      } else if (golden) {
        colorArgb = 0xFFFFC341; intensity = 0.75;
      } else if (elev < 40) {
        colorArgb = 0xFFFFEEC3; intensity = 0.62;
      } else {
        colorArgb = 0xFFFFFFF2; intensity = 0.50;
      }
      final polar = (90.0 - elev).clamp(0.0, 180.0);
      await _mapboxMap!.style.setLight(mapbox.FlatLight(
        id:        'sun',
        anchor:    mapbox.Anchor.MAP,
        color:     colorArgb,
        intensity: intensity,
        position:  [1.5, az, polar],
      ));
    } catch (e) {
      debugPrint('Light: $e');
    }
  }

  Future<void> _mejorarAgua() async {
    const ids = ['water', 'water-shadow', 'waterway'];
    if (_modoNoche) {
      for (final id in ids) {
        try {
          await _mapboxMap!.style
              .setStyleLayerProperty(id, 'fill-color', '#030D1C');
          await _mapboxMap!.style
              .setStyleLayerProperty(id, 'fill-opacity', 0.97);
        } catch (_) {}
      }
    } else {
      for (final id in ids) {
        try {
          await _mapboxMap!.style
              .setStyleLayerProperty(id, 'fill-color', '#1A6DAE');
          await _mapboxMap!.style
              .setStyleLayerProperty(id, 'fill-opacity', 0.90);
        } catch (_) {}
      }
    }
  }

  Future<void> _addBuildings3D() async {
    if (_mapboxMap == null || _buildings3dCreated) return;
    try {
      try {
        await _mapboxMap!.style.addSource(mapbox.RasterDemSource(
          id: 'mapbox-dem',
          url: 'mapbox://mapbox.terrain-dem-v1',
          tileSize: 512,
          maxzoom: 14.0,
        ));
      } catch (_) {}

      try {
        await _mapboxMap!.style.setStyleTerrain(
          '{"source":"mapbox-dem","exaggeration":1.8}');
      } catch (e) {
        debugPrint('Terrain: $e');
      }

      try { await _mapboxMap!.style.removeStyleLayer('hillshade-risk'); } catch (_) {}
      try {
        await _mapboxMap!.style.addLayer(
          mapbox.HillshadeLayer(id: 'hillshade-risk', sourceId: 'mapbox-dem'));
        await _mapboxMap!.style.setStyleLayerProperty(
            'hillshade-risk', 'hillshade-exaggeration', 0.45);
        await _mapboxMap!.style.setStyleLayerProperty(
            'hillshade-risk', 'hillshade-highlight-color', '#F5E8C8');
        await _mapboxMap!.style.setStyleLayerProperty(
            'hillshade-risk', 'hillshade-shadow-color', '#7A5230');
        await _mapboxMap!.style.setStyleLayerProperty(
            'hillshade-risk', 'hillshade-accent-color', '#C4965A');
        await _mapboxMap!.style.setStyleLayerProperty(
            'hillshade-risk', 'hillshade-illumination-anchor', 'viewport');
      } catch (e) {
        debugPrint('Hillshade: $e');
      }

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
      // Colores fijos según modo claro/oscuro — sin depender de la hora real.
      final night = _modoNoche;
      final List<Object> bColors;
      if (night) {
        bColors = ['interpolate', ['linear'], ['get', 'height'],
          0,   '#9C8060', 8,   '#B09070',
          25,  '#C4A878', 60,  '#D4B880', 120, '#C09858'];
      } else {
        bColors = ['interpolate', ['linear'], ['get', 'height'],
          0,   '#F2EAD6', 8,   '#E8D4A8',
          25,  '#D4B878', 60,  '#B89048', 120, '#906830'];
      }
      await _mapboxMap!.style.setStyleLayerProperty(
          _buildingsLayerId, 'fill-extrusion-color', bColors);
      await _mapboxMap!.style.setStyleLayerProperty(
          _buildingsLayerId, 'fill-extrusion-opacity', 0.95);
      await _mapboxMap!.style.setStyleLayerProperty(
          _buildingsLayerId, 'fill-extrusion-ambient-occlusion-intensity', 0.25);
      await _mapboxMap!.style.setStyleLayerProperty(
          _buildingsLayerId, 'fill-extrusion-ambient-occlusion-radius', 3.0);
      _buildings3dCreated = true;
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'edificios_3d');
    }
  }

  // ── Territorios fantasma
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

      const double radioVisible = 0.022;
      const int    kUmbral      = 18;

      final realesCercanos = _territorios.where((t) =>
        !t.esFantasma &&
        (t.centro.latitude  - centro.latitude).abs()  < radioVisible &&
        (t.centro.longitude - centro.longitude).abs() < radioVisible,
      ).length;

      final fantasmasCercanos = _territorios.where((t) =>
        t.esFantasma &&
        (t.centro.latitude  - centro.latitude).abs()  < radioVisible &&
        (t.centro.longitude - centro.longitude).abs() < radioVisible,
      ).length;

      final faltan = kUmbral - realesCercanos - fantasmasCercanos;
      if (faltan <= 0) return;

      await TerritoryService.crearTerritoriosFantasmaEnZona(
        centro:          centro,
        todosExistentes: _territorios,
        max:             faltan,
      );
      final lista = await TerritoryService.cargarTodosLosTerritorios(
          centro: centro, modo: 'competitivo');
      if (mounted && !_modoRuta) {
        setState(() => _territorios = lista);
        GameStateService.instance.setCompetitiveTerritories(lista);
        _dibujarTerritoriosEnMapa();
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'fantasmas');
    } finally {
      _fantasmasCargando = false;
    }
  }

  String _buildCentrosGeoJson() {
    final feats = _territorios.map((t) {
      final c        = t.centro;
      final colorHex = _colorToHex(t.color);
      return '{"type":"Feature","properties":{"color":"$colorHex"},'
          '"geometry":{"type":"Point","coordinates":[${c.longitude},${c.latitude}]}}';
    }).join(',');
    return '{"type":"FeatureCollection","features":[$feats]}';
  }

  Future<void> _crearCentrosLayer() async {
    if (_centrosLayerCreated || _territorios.isEmpty || _mapboxMap == null) return;
    try { await _mapboxMap!.style.removeStyleLayer(_centrosLayerId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleSource(_centrosSourceId); } catch (_) {}
    final gj = _buildCentrosGeoJson();
    await _mapboxMap!.style.addSource(
        mapbox.GeoJsonSource(id: _centrosSourceId, data: gj));
    await _mapboxMap!.style.addLayer(
        mapbox.CircleLayer(id: _centrosLayerId, sourceId: _centrosSourceId));
    await _mapboxMap!.style.setStyleLayerProperty(
        _centrosLayerId, 'circle-color', ['get', 'color']);
    await _mapboxMap!.style.setStyleLayerProperty(
        _centrosLayerId, 'circle-radius',
        ['interpolate', ['linear'], ['zoom'],
          1, 4.0, 5, 7.0, 10, 5.5, 18, 4.5]);
    await _mapboxMap!.style.setStyleLayerProperty(
        _centrosLayerId, 'circle-opacity', 0.92);
    await _mapboxMap!.style.setStyleLayerProperty(
        _centrosLayerId, 'circle-stroke-width', 1.8);
    await _mapboxMap!.style.setStyleLayerProperty(
        _centrosLayerId, 'circle-stroke-color', '#0a0a0a');
    await _mapboxMap!.style.setStyleLayerProperty(
        _centrosLayerId, 'circle-stroke-opacity', 0.70);
    await _mapboxMap!.style.setStyleLayerProperty(
        _centrosLayerId, 'circle-blur', 0.0);
    _centrosLayerCreated = true;
  }

  // ==========================================================================
  // PUNTOS DE TERRITORIOS EN EL GLOBO (propios + otros jugadores)
  // ==========================================================================
  Future<void> _cargarYMostrarPuntosGlobo() async {
    if (!_puntosGloboCargados) {
      try {
        final puntos = await TerritoryService.cargarPuntosGlobo(
            modo: _modoSolitario ? 'solitario' : 'competitivo');
        if (!mounted) return;
        _puntosGlobo = puntos;
        _puntosGloboCargados = true;
      } catch (e) {
        debugPrint('puntosGlobo fetch error: $e');
        // Reintento único tras 2 s
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        try {
          final puntos = await TerritoryService.cargarPuntosGlobo(
              modo: _modoSolitario ? 'solitario' : 'competitivo');
          if (!mounted) return;
          _puntosGlobo = puntos;
          _puntosGloboCargados = true;
        } catch (_) {
          return;
        }
      }
    }
    await _actualizarPuntosGloboLayer();
  }

  Future<void> _actualizarPuntosGloboLayer() async {
    if (_mapboxMap == null || _puntosGlobo.isEmpty) return;
    if (_actualizandoGloboLayer) return; // evitar llamadas concurrentes
    _actualizandoGloboLayer = true;
    try {
      final feats = _puntosGlobo.map((p) {
        final raw   = p['color'] as int;
        final hex   = '#${raw.toRadixString(16).padLeft(8, '0').substring(2)}';
        final esMio = p['esMio'] as bool;
        return '{"type":"Feature",'
            '"properties":{"color":"$hex","esMio":${esMio ? 'true' : 'false'}},'
            '"geometry":{"type":"Point","coordinates":[${p['lng']},${p['lat']}]}}';
      }).join(',');
      final gj = '{"type":"FeatureCollection","features":[$feats]}';

      if (!_puntosGloboLayerCreated) {
        try { await _mapboxMap!.style.removeStyleLayer(_puntosGloboGlowLayerId); } catch (_) {}
        try { await _mapboxMap!.style.removeStyleLayer(_puntosGloboLayerId); } catch (_) {}
        try { await _mapboxMap!.style.removeStyleSource(_puntosGloboSrcId); } catch (_) {}

        await _mapboxMap!.style.addSource(
            mapbox.GeoJsonSource(id: _puntosGloboSrcId, data: gj));

        // Capa de glow — halo difuso detrás de los puntos propios
        await _mapboxMap!.style.addLayer(
            mapbox.CircleLayer(
              id: _puntosGloboGlowLayerId,
              sourceId: _puntosGloboSrcId,
              maxZoom: 9.5,
            ));
        await _mapboxMap!.style.setStyleLayerProperty(
            _puntosGloboGlowLayerId, 'circle-color', ['get', 'color']);
        await _mapboxMap!.style.setStyleLayerProperty(
            _puntosGloboGlowLayerId, 'circle-radius', [
          'case', ['==', ['get', 'esMio'], true],
          ['interpolate', ['linear'], ['zoom'], 1, 9.0, 4, 13.0, 8, 11.0],
          0.0,
        ]);
        await _mapboxMap!.style.setStyleLayerProperty(
            _puntosGloboGlowLayerId, 'circle-blur', 1.6);
        await _mapboxMap!.style.setStyleLayerProperty(
            _puntosGloboGlowLayerId, 'circle-opacity', [
          'interpolate', ['linear'], ['zoom'],
          8.0, ['case', ['==', ['get', 'esMio'], true], 0.45, 0.0],
          9.5, 0.0,
        ]);

        // maxZoom: 9.5 — Mapbox oculta los puntos automáticamente al hacer zoom in
        await _mapboxMap!.style.addLayer(
            mapbox.CircleLayer(
              id: _puntosGloboLayerId,
              sourceId: _puntosGloboSrcId,
              maxZoom: 9.5,
            ));

        await _mapboxMap!.style.setStyleLayerProperty(
            _puntosGloboLayerId, 'circle-color', ['get', 'color']);

        // Radios pequeños y precisos — estética táctica/militar
        await _mapboxMap!.style.setStyleLayerProperty(
            _puntosGloboLayerId, 'circle-radius', [
          'case', ['==', ['get', 'esMio'], true],
          ['interpolate', ['linear'], ['zoom'], 1, 3.5, 4, 5.5, 8, 5.0],
          ['interpolate', ['linear'], ['zoom'], 1, 1.8, 4, 2.8, 8, 2.5],
        ]);

        // Opacidad: propios sólidos, ajenos muy tenues
        await _mapboxMap!.style.setStyleLayerProperty(
            _puntosGloboLayerId, 'circle-opacity', [
          'interpolate', ['linear'], ['zoom'],
          8.0, ['case', ['==', ['get', 'esMio'], true], 0.92, 0.38],
          9.5, 0.0,
        ]);

        // Contorno oscuro fino solo en propios (sin blanco brillante)
        await _mapboxMap!.style.setStyleLayerProperty(
            _puntosGloboLayerId, 'circle-stroke-width',
            ['case', ['==', ['get', 'esMio'], true], 1.0, 0.0]);
        await _mapboxMap!.style.setStyleLayerProperty(
            _puntosGloboLayerId, 'circle-stroke-color', '#0a0a0a');
        await _mapboxMap!.style.setStyleLayerProperty(
            _puntosGloboLayerId, 'circle-stroke-opacity',
            ['interpolate', ['linear'], ['zoom'], 8.0, 0.7, 9.5, 0.0]);
        await _mapboxMap!.style.setStyleLayerProperty(
            _puntosGloboLayerId, 'circle-blur',
            ['case', ['==', ['get', 'esMio'], true], 0.0, 0.20]);

        _puntosGloboLayerCreated = true;
      } else {
        final src = await _mapboxMap!.style
            .getSource(_puntosGloboSrcId) as mapbox.GeoJsonSource?;
        await src?.updateGeoJSON(gj);
      }
    } catch (e) {
      debugPrint('puntosGlobo layer: $e');
      _puntosGloboLayerCreated = false; // fuerza recreación en próximo intento
    } finally {
      _actualizandoGloboLayer = false;
    }
  }

  void _onMapTap(mapbox.MapContentGestureContext ctx) async {
    if (_mapboxMap == null) return;
    final cam = await _mapboxMap!.getCameraState();
    final tapLat = ctx.point.coordinates.lat.toDouble();
    final tapLng = ctx.point.coordinates.lng.toDouble();

    if (cam.zoom > 8) {
      // Modo running: mostrar info del territorio más cercano al tap
      if (!_session.isTracking || _territorios.isEmpty) return;
      _mostrarInfoTerritorioCercano(tapLat, tapLng);
      return;
    }

    // Modo globo: volar al territorio más cercano
    if (_puntosGlobo.isEmpty) return;
    Map<String, dynamic>? nearest;
    double minDist = double.infinity;
    for (final p in _puntosGlobo) {
      final dLat = (p['lat'] as double) - tapLat;
      final dLng = (p['lng'] as double) - tapLng;
      final d    = dLat * dLat + dLng * dLng;
      if (d < minDist) { minDist = d; nearest = p; }
    }
    // Umbral ~300 km (≈2.7° al cuadrado ≈ 7.3)
    if (nearest == null || minDist > 8.0) return;

    HapticFeedback.selectionClick();
    await _moverCamara(
      lat:      nearest['lat'] as double,
      lng:      nearest['lng'] as double,
      zoom:     14.0,
      pitch:    _kPitchNormal,
      bearing:  0,
      animated: true,
      duracion: 1400,
    );
  }

  void _mostrarInfoTerritorioCercano(double tapLat, double tapLng) {
    TerritoryData? nearest;
    double minDist = double.infinity;
    for (final t in _territorios) {
      final dLat = t.centro.latitude  - tapLat;
      final dLng = t.centro.longitude - tapLng;
      final d    = dLat * dLat + dLng * dLng;
      if (d < minDist) { minDist = d; nearest = t; }
    }
    // Umbral ~500m (~0.0045° al cuadrado ≈ 0.00002)
    if (nearest == null || minDist > 0.00002) return;
    if (!mounted) return;
    HapticFeedback.selectionClick();
    _infoTimer?.cancel();
    setState(() => _territorioInfo = nearest);
    _infoTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _territorioInfo = null);
    });
  }

  Widget _buildTerritoryInfoOverlay() {
    final t = _territorioInfo;
    if (t == null) return const SizedBox.shrink();

    final Color hpColor = t.estadoHp == EstadoHp.critico
        ? const Color(0xFFE02020)
        : t.estadoHp == EstadoHp.danado
            ? const Color(0xFFFF9800)
            : const Color(0xFF30D158);

    final String hpLabel = t.estadoHp == EstadoHp.critico
        ? 'CRÍTICO — fácil de atacar'
        : t.estadoHp == EstadoHp.danado
            ? 'DAÑADO — resistencia media'
            : 'SALUDABLE — difícil de atacar';

    return Positioned(
      bottom: 170,
      left: 14,
      right: 14,
      child: GestureDetector(
        onTap: () { _infoTimer?.cancel(); setState(() => _territorioInfo = null); },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0F).withValues(alpha: 0.95),
            border: Border.all(color: t.color.withValues(alpha: 0.55), width: 1.5),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: t.color.withValues(alpha: 0.22), blurRadius: 20),
              const BoxShadow(color: Colors.black54, blurRadius: 12),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(width: 3, height: 16, color: t.color,
                    margin: const EdgeInsets.only(right: 8)),
                Expanded(
                  child: Text(
                    t.esMio ? 'TU TERRITORIO' : t.ownerNickname.toUpperCase(),
                    style: GoogleFonts.rajdhani(
                        color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w800, letterSpacing: 1.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () { _infoTimer?.cancel(); setState(() => _territorioInfo = null); },
                  child: const Icon(Icons.close_rounded, color: Colors.white38, size: 15),
                ),
              ]),
              if (!_modoSolitario) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Container(
                    width: 6, height: 6, margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: hpColor, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: hpColor.withValues(alpha: 0.6), blurRadius: 4)],
                    ),
                  ),
                  Expanded(child: Text(hpLabel,
                      style: GoogleFonts.rajdhani(color: hpColor, fontSize: 10,
                          fontWeight: FontWeight.w700, letterSpacing: 0.8))),
                  Text('${t.hpActual}/$kHpMax HP',
                      style: GoogleFonts.rajdhani(color: hpColor, fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (t.hpActual / kHpMax).clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(hpColor),
                    minHeight: 3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


  /// Elimina TODAS las capas de territorio incondicionalmente.
  /// No depende de _territoriosLayersCreated — cubre el caso donde el flag
  /// está desincronizado con el estado real del mapa.
  Future<void> _limpiarCapasTerritoriosForzado() async {
    _dibujandoDebounce?.cancel();
    _dibujadosGen++;
    _territoriosLayersCreated = false;
    _centrosLayerCreated = false;
    _pulsoTimer?.cancel();
    if (_mapboxMap == null) return;
    for (final id in [
      _centrosLayerId,
      _borderOuterGlowId, _borderPulseLayerId, _borderLayerId, _fillInnerLayerId, _fillLayerId,
    ]) {
      try { await _mapboxMap!.style.removeStyleLayer(id); } catch (_) {}
    }
    try { await _mapboxMap!.style.removeStyleSource(_centrosSourceId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleSource(_sourceId); } catch (_) {}
  }

  Future<void> _dibujarTerritoriosEnMapa() async {
    if (_mapboxMap == null || !_styleLoaded) return;

    final gen = _dibujadosGen;

    if (_territorios.isEmpty) {
      _dibujandoTerritorios = false;
      if (_territoriosLayersCreated) {
        _territoriosLayersCreated = false;
        _centrosLayerCreated = false;
        _pulsoTimer?.cancel();
        try { await _mapboxMap!.style.removeStyleLayer(_centrosLayerId); } catch (_) {}
        try { await _mapboxMap!.style.removeStyleSource(_centrosSourceId); } catch (_) {}
        for (final id in [
          _borderOuterGlowId, _borderPulseLayerId, _borderLayerId, _fillInnerLayerId, _fillLayerId
        ]) {
          try { await _mapboxMap!.style.removeStyleLayer(id); } catch (_) {}
        }
        try { await _mapboxMap!.style.removeStyleSource(_sourceId); } catch (_) {}
      }
      return;
    }

    // Evitar dibujos concurrentes — el anterior ya está actualizando las capas
    if (_dibujandoTerritorios) return;
    _dibujandoTerritorios = true;

    final features = _territorios.map((t) {
      final coords = t.puntos.map((p) => [p.longitude, p.latitude]).toList();
      coords.add(coords.first);

      final colorHex    = _colorToHex(t.color);
      final borderWidth = t.esMio
          ? 3.2
          : switch (t.estadoHp) {
              EstadoHp.saludable => 1.6,
              EstadoHp.danado    => 2.0,
              EstadoHp.critico   => 2.4,
            };
      final fillOpacity  = (_modoSolitario && t.esMio) ? 0.85 : t.opacidadRelleno;
      final innerOpacity = t.esMio ? fillOpacity * 0.28 : 0.0;

      return _encodeJson({
        'type': 'Feature',
        'properties': {
          'color':         colorHex,
          'fillOpacity':   fillOpacity,
          'innerOpacity':  innerOpacity,
          'borderOpacity': t.opacidadBorde,
          'borderWidth':   borderWidth,
          'esMio':         t.esMio,
          'esFantasma':    t.esFantasma,
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
        if (_centrosLayerCreated) {
          final cSrc = await _mapboxMap!.style
              .getSource(_centrosSourceId) as mapbox.GeoJsonSource?;
          await cSrc?.updateGeoJSON(_buildCentrosGeoJson());
        } else {
          await _crearCentrosLayer();
        }
        return;
      }

      _pulsoTimer?.cancel();
      for (final id in [
        _borderOuterGlowId, _borderPulseLayerId, _borderLayerId, _fillInnerLayerId, _fillLayerId
      ]) {
        try { await _mapboxMap!.style.removeStyleLayer(id); } catch (_) {}
      }
      try { await _mapboxMap!.style.removeStyleSource(_sourceId); } catch (_) {}

      // Check AFTER the awaited removes — if the mode changed (gen incremented)
      // while those were in flight, abort before adding any territory layers.
      if (gen != _dibujadosGen) return;

      await _mapboxMap!.style
          .addSource(mapbox.GeoJsonSource(id: _sourceId, data: geojson));

      await _mapboxMap!.style
          .addLayer(mapbox.FillLayer(id: _fillLayerId, sourceId: _sourceId, minZoom: 7.0));
      await _mapboxMap!.style
          .setStyleLayerProperty(_fillLayerId, 'fill-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _fillLayerId, 'fill-opacity', [
        'case', ['==', ['get', 'esFantasma'], true],
        ['interpolate', ['linear'], ['zoom'], 9, 0, 12, ['get', 'fillOpacity']],
        ['*', ['get', 'fillOpacity'], ['interpolate', ['linear'], ['zoom'], 7.5, 0.0, 9.5, 1.0]],
      ]);
      await _mapboxMap!.style
          .setStyleLayerProperty(_fillLayerId, 'fill-antialias', true);

      await _mapboxMap!.style.addLayer(
          mapbox.FillLayer(id: _fillInnerLayerId, sourceId: _sourceId, minZoom: 7.0));
      await _mapboxMap!.style.setStyleLayerProperty(
          _fillInnerLayerId, 'fill-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _fillInnerLayerId, 'fill-opacity', [
        'case', ['==', ['get', 'esFantasma'], true],
        ['interpolate', ['linear'], ['zoom'], 9, 0, 12, ['get', 'innerOpacity']],
        ['*', ['get', 'innerOpacity'], ['interpolate', ['linear'], ['zoom'], 7.5, 0.0, 9.5, 1.0]],
      ]);
      await _mapboxMap!.style
          .setStyleLayerProperty(_fillInnerLayerId, 'fill-antialias', true);

      await _mapboxMap!.style
          .addLayer(mapbox.LineLayer(id: _borderLayerId, sourceId: _sourceId, minZoom: 7.0));
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderLayerId, 'line-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderLayerId, 'line-width', ['get', 'borderWidth']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderLayerId, 'line-opacity', [
        'case', ['==', ['get', 'esFantasma'], true],
        ['interpolate', ['linear'], ['zoom'], 9, 0, 12, ['get', 'borderOpacity']],
        ['*', ['get', 'borderOpacity'], ['interpolate', ['linear'], ['zoom'], 7.5, 0.0, 9.0, 1.0]],
      ]);
      await _mapboxMap!.style
          .setStyleLayerProperty(_borderLayerId, 'line-join', 'miter');
      await _mapboxMap!.style
          .setStyleLayerProperty(_borderLayerId, 'line-cap', 'square');

      // Halo exterior — propiedad propia + alerta roja en rivales críticos
      await _mapboxMap!.style.addLayer(
          mapbox.LineLayer(id: _borderOuterGlowId, sourceId: _sourceId, minZoom: 7.0));
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderOuterGlowId, 'line-color', [
        'case',
        ['==', ['get', 'estadoHp'], 'critico'], '#CC2222',
        ['get', 'color'],
      ]);
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderOuterGlowId, 'line-width', [
        'case',
        ['==', ['get', 'estadoHp'], 'critico'], 7.0,
        ['==', ['get', 'esMio'], true], 5.0,
        4.0,
      ]);
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderOuterGlowId, 'line-opacity', [
        'case',
        ['==', ['get', 'esMio'], true], 0.05,
        ['all', ['==', ['get', 'esMio'], false], ['==', ['get', 'estadoHp'], 'critico']], 0.12,
        0.0,
      ]);
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderOuterGlowId, 'line-blur', [
        'case',
        ['==', ['get', 'estadoHp'], 'critico'], 5.0,
        3.0,
      ]);
      await _mapboxMap!.style
          .setStyleLayerProperty(_borderOuterGlowId, 'line-join', 'miter');

      // Pulso táctico — muy contenido
      await _mapboxMap!.style.addLayer(
          mapbox.LineLayer(id: _borderPulseLayerId, sourceId: _sourceId, minZoom: 7.0));
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderPulseLayerId, 'line-color', ['get', 'color']);
      await _mapboxMap!.style
          .setStyleLayerProperty(_borderPulseLayerId, 'line-width', 2.0);
      await _mapboxMap!.style.setStyleLayerProperty(
          _borderPulseLayerId, 'line-opacity',
          ['case', ['==', ['get', 'esMio'], true], _pulsoOpacity, 0.0]);
      await _mapboxMap!.style
          .setStyleLayerProperty(_borderPulseLayerId, 'line-blur', 1.5);
      await _mapboxMap!.style
          .setStyleLayerProperty(_borderPulseLayerId, 'line-join', 'miter');

      // Second gen check: if mode changed WHILE we were adding layers, undo
      // everything we just created before the next draw sees _territoriosLayersCreated.
      if (gen != _dibujadosGen) {
        for (final id in [
          _borderOuterGlowId, _borderPulseLayerId, _borderLayerId, _fillInnerLayerId, _fillLayerId
        ]) {
          try { await _mapboxMap!.style.removeStyleLayer(id); } catch (_) {}
        }
        try { await _mapboxMap!.style.removeStyleSource(_sourceId); } catch (_) {}
        return;
      }
      _territoriosLayersCreated = true;
      _actualizarCoronesMapa();

      if (_centrosLayerCreated) {
        final src = await _mapboxMap!.style
            .getSource(_centrosSourceId) as mapbox.GeoJsonSource?;
        await src?.updateGeoJSON(_buildCentrosGeoJson());
      } else {
        await _crearCentrosLayer();
      }

      _pulsoTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
        if (!mounted || _mapboxMap == null) return;
        if (_pulsoUp) {
          _pulsoOpacity += 0.03;
          if (_pulsoOpacity >= 0.13) _pulsoUp = false;
        } else {
          _pulsoOpacity -= 0.03;
          if (_pulsoOpacity <= 0.04) _pulsoUp = true;
        }
        try {
          _mapboxMap!.style.setStyleLayerProperty(
              _borderPulseLayerId, 'line-opacity',
              ['case', ['==', ['get', 'esMio'], true], _pulsoOpacity, 0.0]);
        } catch (_) {}
      });
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'dibujar_territorios');
    } finally {
      _dibujandoTerritorios = false;
      // Race condition guard: if territories were cleared while this draw was
      // in progress (e.g. user switched to ruta mode before layers were created),
      // _territoriosLayersCreated was false so the empty-check branch skipped
      // cleanup. Trigger it now that the draw has finished and layers exist.
      if (_territorios.isEmpty && _territoriosLayersCreated) {
        _dibujarTerritoriosEnMapa();
      }
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
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'ruta_mapa');
    }
  }

  // ==========================================================================
  // PREVIEW DE TERRITORIO EN TIEMPO REAL
  // ==========================================================================
  Future<void> _actualizarPreviewTerritorio() async {
    if (!mounted || !_session.isTracking || _session.isPaused || _modoRuta || _mapboxMap == null || !_styleLoaded) return;
    if (routePoints.length < 3) return;

    final area   = TerritoryService.calcularAreaM2(routePoints);
    final valida = area >= kAreaMinimaM2;
    _modeCtrl.setZonaValida(valida);

    final coords  = routePoints.map((p) => [p.longitude, p.latitude]).toList();
    coords.add(coords.first);
    final colorHex = _colorToHex(_colorTerritorio);
    final geojson  =
        '{"type":"FeatureCollection","features":[{"type":"Feature",'
        '"properties":{"color":"$colorHex"},'
        '"geometry":{"type":"Polygon","coordinates":[${_encodeJson(coords)}]}}]}';

    try {
      if (_previewLayerCreated) {
        final src = await _mapboxMap!.style
            .getSource(_previewSourceId) as mapbox.GeoJsonSource?;
        await src?.updateGeoJSON(geojson);
        return;
      }
      for (final id in [_previewBorderLayerId, _previewLayerId]) {
        try { await _mapboxMap!.style.removeStyleLayer(id); } catch (_) {}
      }
      try { await _mapboxMap!.style.removeStyleSource(_previewSourceId); } catch (_) {}

      await _mapboxMap!.style.addSource(
          mapbox.GeoJsonSource(id: _previewSourceId, data: geojson));

      await _mapboxMap!.style.addLayer(
          mapbox.FillLayer(id: _previewLayerId, sourceId: _previewSourceId));
      await _mapboxMap!.style.setStyleLayerProperty(
          _previewLayerId, 'fill-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _previewLayerId, 'fill-opacity', 0.18);

      await _mapboxMap!.style.addLayer(
          mapbox.LineLayer(id: _previewBorderLayerId, sourceId: _previewSourceId));
      await _mapboxMap!.style.setStyleLayerProperty(
          _previewBorderLayerId, 'line-color', ['get', 'color']);
      await _mapboxMap!.style.setStyleLayerProperty(
          _previewBorderLayerId, 'line-width', 2.0);
      await _mapboxMap!.style.setStyleLayerProperty(
          _previewBorderLayerId, 'line-opacity', 0.7);
      await _mapboxMap!.style.setStyleLayerProperty(
          _previewBorderLayerId, 'line-dasharray', [4.0, 2.5]);

      _previewLayerCreated = true;
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'preview_territorio');
    }
  }

  Future<void> _limpiarPreviewTerritorio() async {
    if (!_previewLayerCreated || _mapboxMap == null) return;
    for (final id in [_previewBorderLayerId, _previewLayerId]) {
      try { await _mapboxMap!.style.removeStyleLayer(id); } catch (_) {}
    }
    try { await _mapboxMap!.style.removeStyleSource(_previewSourceId); } catch (_) {}
    _previewLayerCreated = false;
    if (mounted) _modeCtrl.setZonaValida(false);
  }

  // ==========================================================================
  // RUTA GUIADA
  // ==========================================================================

  // Dibuja la polilínea fantasma de la ruta guiada sobre el mapa Mapbox.
  Future<void> _dibujarGhostRuta() async {
    final ruta = _rutaGuiada;
    if (_mapboxMap == null || ruta == null || ruta.coords.length < 2) return;
    final coords = ruta.coords.map((p) => [p.longitude, p.latitude]).toList();
    final geojson = _encodeJson({
      'type': 'Feature',
      'geometry': {'type': 'LineString', 'coordinates': coords},
    });
    try {
      if (!_ghostLayerCreated) {
        await _mapboxMap!.style.addSource(
            mapbox.GeoJsonSource(id: _kGhostSourceId, data: geojson));
        await _mapboxMap!.style.addLayer(
            mapbox.LineLayer(id: _kGhostLayerId, sourceId: _kGhostSourceId));
        await _mapboxMap!.style.setStyleLayerProperty(
            _kGhostLayerId, 'line-color', '#FFFFFF');
        await _mapboxMap!.style.setStyleLayerProperty(
            _kGhostLayerId, 'line-width', 3.0);
        await _mapboxMap!.style.setStyleLayerProperty(
            _kGhostLayerId, 'line-opacity', 0.35);
        _ghostLayerCreated = true;
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'ghost_layer');
    }
  }

  Future<void> _cargarYDibujarRutasPreview() async {
    if (_mapboxMap == null || !_styleLoaded) return;
    try {
      final rutas = await RouteService.cargarMisRutas();
      if (!mounted) return;
      setState(() => _rutasPreview = rutas);
      final geojson = rutas.isEmpty
          ? '{"type":"FeatureCollection","features":[]}'
          : '{"type":"FeatureCollection","features":[${rutas.map((r) {
              final coords = r.coords
                  .map((p) => '[${p.longitude},${p.latitude}]')
                  .join(',');
              return '{"type":"Feature","properties":{"color":"${_colorToHex(r.color)}"},'
                  '"geometry":{"type":"LineString","coordinates":[$coords]}}';
            }).join(',')}]}';
      if (_rutasPreviewLayerCreated) {
        final src = await _mapboxMap!.style
            .getSource(_rutasPreviewSrcId) as mapbox.GeoJsonSource?;
        await src?.updateGeoJSON(geojson);
      } else {
        try { await _mapboxMap!.style.removeStyleLayer(_rutasPreviewLayerId); } catch (_) {}
        try { await _mapboxMap!.style.removeStyleSource(_rutasPreviewSrcId); } catch (_) {}
        await _mapboxMap!.style
            .addSource(mapbox.GeoJsonSource(id: _rutasPreviewSrcId, data: geojson));
        await _mapboxMap!.style
            .addLayer(mapbox.LineLayer(id: _rutasPreviewLayerId, sourceId: _rutasPreviewSrcId));
        await _mapboxMap!.style
            .setStyleLayerProperty(_rutasPreviewLayerId, 'line-color', ['get', 'color']);
        await _mapboxMap!.style
            .setStyleLayerProperty(_rutasPreviewLayerId, 'line-width', 3.5);
        await _mapboxMap!.style
            .setStyleLayerProperty(_rutasPreviewLayerId, 'line-opacity', 0.85);
        _rutasPreviewLayerCreated = true;
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'rutas_preview');
    }
  }

  Future<void> _limpiarRutasPreview() async {
    if (!_rutasPreviewLayerCreated || _mapboxMap == null) return;
    _rutasPreviewLayerCreated = false;
    try { await _mapboxMap!.style.removeStyleLayer(_rutasPreviewLayerId); } catch (_) {}
    try { await _mapboxMap!.style.removeStyleSource(_rutasPreviewSrcId); } catch (_) {}
    if (mounted) setState(() => _rutasPreview = []);
  }

  // Evalúa checkpoint y desvío en cada actualización de posición.
  void _actualizarProgresoRutaGuiada(LatLng pos) {
    final ruta = _rutaGuiada;
    if (ruta == null || ruta.coords.isEmpty) return;

    // Narración de inicio (una sola vez al arrancar)
    if (!_narratorRutaIniciado && _session.isTracking) {
      _narratorRutaIniciado = true;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _narrador.eventoInicioRutaGuiada(
              ruta.nombre ?? 'Ruta sin nombre', ruta.runsCount);
          if (ruta.esLegendaria) {
            Future.delayed(const Duration(seconds: 8), () {
              if (mounted) _narrador.eventoRutaLegendaria(ruta.runsCount);
            });
          }
        }
      });
    }

    // Distancia mínima al trazado
    double minDist = double.infinity;
    int    nearestIdx = 0;
    for (var i = 0; i < ruta.coords.length; i++) {
      final d = Geolocator.distanceBetween(
          pos.latitude, pos.longitude,
          ruta.coords[i].latitude, ruta.coords[i].longitude);
      if (d < minDist) { minDist = d; nearestIdx = i; }
    }

    // Desvío > 150 m
    final nuevaFuera = minDist > 150;
    if (nuevaFuera && !_session.fueraDeRuta) {
      _session.updateRuta(fuera: true);
      _narrador.eventoDesvio();
    } else if (!nuevaFuera && _session.fueraDeRuta) {
      _session.updateRuta(fuera: false);
      _narrador.eventoVueltaRuta();
    }

    // Checkpoints cada 20% del recorrido (4 checkpoints: 20 40 60 80 %)
    const totalCheckpoints = 4;
    final pctIdx = nearestIdx / ruta.coords.length;
    final cpActual = (pctIdx * totalCheckpoints).floor();
    if (cpActual > _checkpointActual && cpActual <= totalCheckpoints) {
      _checkpointActual = cpActual;
      _narrador.eventoCheckpoint(_checkpointActual, totalCheckpoints);
    }

    // Actualizar porcentaje visible en HUD
    final nuevoPct = pctIdx.clamp(0.0, 1.0);
    if ((nuevoPct - _session.porcentajeRuta).abs() >= 0.005) {
      _session.updateRuta(porcentaje: nuevoPct);
    }

    // Detección de ruta completada (último 5% del trazado)
    if (!_session.rutaCompletada && pctIdx >= 0.95) {
      _session.updateRuta(completada: true);
      _narrador.eventoRutaCompletada(ruta.nombre ?? 'Ruta');
    }
  }

  // ==========================================================================
  // ── Streams de territorios en tiempo real ─────────────────────────────────
  void _suscribirStreamTerritorios() {
    _competitiveStreamSub = TerritoryService.competitiveStream.listen((list) {
      if (!mounted) return;
      _modeCtrl.setMapaDesactualizado(false);
      GameStateService.instance.setCompetitiveTerritories(list);
      if (!_territoriosCargados || _modoSolitario || _modoRuta) return;
      setState(() => _territorios = list);
      _dibujandoDebounce?.cancel();
      _dibujandoDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _dibujarTerritoriosEnMapa();
      });
    }, onError: (e) {
      debugPrint('Stream competitivo caído: $e');
      if (mounted) _modeCtrl.setMapaDesactualizado(true);
      _programarReconexion();
    });
    _solitarioStreamSub = TerritoryService.solitarioStream.listen((list) {
      if (!mounted) return;
      _modeCtrl.setMapaDesactualizado(false);
      GameStateService.instance.setSolitarioTerritories(list);
      if (!_territoriosCargados || !_modoSolitario) return;
      setState(() => _territorios = list);
      _dibujandoDebounce?.cancel();
      _dibujandoDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _dibujarTerritoriosEnMapa();
      });
    }, onError: (e) {
      debugPrint('Stream solitario caído: $e');
      if (mounted) _modeCtrl.setMapaDesactualizado(true);
      _programarReconexion();
    });
  }

  void _programarReconexion() {
    _streamReconectarTimer?.cancel();
    _streamReconectarTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      _competitiveStreamSub?.cancel();
      _solitarioStreamSub?.cancel();
      _suscribirStreamTerritorios();
    });
  }

  // JUGADORES ACTIVOS
  // ==========================================================================
  void _escucharJugadoresActivos() {
    final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(minutes: 5)));
    _jugadoresStream = PresenceService.stream(cutoff).listen((snap) async {
      if (!mounted) return;
      final user   = FirebaseAuth.instance.currentUser;
      final myLat  = _currentPosition?.latitude;
      final myLng  = _currentPosition?.longitude;
      final nuevos = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        if (doc.id == user?.uid) continue;
        final d  = doc.data();
        final ts = d['timestamp'] as Timestamp?;
        if (ts == null ||
            DateTime.now().difference(ts.toDate()).inMinutes >= 5) { continue; }
        final lat = (d['lat'] as num?)?.toDouble();
        final lng = (d['lng'] as num?)?.toDouble();
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
      final color = Color((data['color'] as num?)?.toInt() ?? _kWater.toARGB32());
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
    final key = color.toARGB32();
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

    for (final docId in _anotacionesReyes.keys
        .where((k) => !idsConRey.contains(k))
        .toList()) {
      await _annotationManager?.delete(_anotacionesReyes[docId]!);
      _anotacionesReyes.remove(docId);
    }

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

    canvas.drawCircle(
      const Offset(sz / 2, sz / 2),
      sz / 2,
      Paint()..color = const Color(0xCC1A1000),
    );
    canvas.drawCircle(
      const Offset(sz / 2, sz / 2),
      sz / 2 - 2,
      Paint()
        ..color       = const Color(0xFFD4A84C)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

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
    canvas.drawCircle(const Offset(sz / 2, sz / 2), sz / 2,
        Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(
        const Offset(sz / 2, sz / 2), sz / 2 - 6, Paint()..color = _p.parchment);
    canvas.drawCircle(
        const Offset(sz / 2, sz / 2), sz / 2 - 6,
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
    if (user == null || _currentPosition == null || !_session.isTracking) return;
    await PresenceService.publicar(
      uid:        user.uid,
      lat:        _currentPosition!.latitude,
      lng:        _currentPosition!.longitude,
      colorValue: _colorTerritorio.toARGB32(),
      nickname:   _miNickname,
    );
  }

  Future<void> _limpiarPresenciaFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await PresenceService.eliminar(user.uid);
  }

  // ==========================================================================
  // GUERRA GLOBAL
  // ==========================================================================
  double get _progresoGlobal {
    if (_objetivoGlobal == null) return 0;
    final kmReq = (_objetivoGlobal!['kmRequeridos'] as num?)?.toDouble() ?? 0;
    if (kmReq <= 0) return 0;
    return (_session.distanciaTotal / kmReq).clamp(0.0, 1.0);
  }

  double get _kmRestantesGlobal {
    if (_objetivoGlobal == null) return 0;
    final kmReq = (_objetivoGlobal!['kmRequeridos'] as num?)?.toDouble() ?? 0;
    return (kmReq - _session.distanciaTotal).clamp(0.0, kmReq);
  }

  Future<void> _conquistarTerritorioGlobal(String activityLogId) async {
  if (_globalConquistando) return;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final territorioId = _objetivoGlobal?['territorioId'] as String?;
  if (territorioId == null) return;
  if (!mounted) return;

  _modeCtrl.setGlobalConquistando(true);

  try {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('conquistarTerritorioGlobal');
    final result = await callable.call({
      'territorioId':  territorioId,
      'activityLogId': activityLogId,
      'ownerColor':    _colorTerritorio.toARGB32(),
    });
      if (!mounted) return;
      final data = result.data as Map<String, dynamic>;
      if (data['ok'] == true) {
        final nuevaClausula = (data['nuevaClausula'] as num?)?.toDouble();
        _modeCtrl.setConquistaGlobalExito(nuevaCl: nuevaClausula);
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 150),
            () => HapticFeedback.heavyImpact());
        Future.delayed(const Duration(milliseconds: 300),
            () => HapticFeedback.heavyImpact());
        _narrador.eventoConquista(
            _objetivoGlobal?['territorioNombre'] as String? ?? '');
        _mostrarNotificacionConquistaGlobal();
        _escribirActivityFeed(
          territoryName: _objetivoGlobal?['territorioNombre'] as String? ?? 'Territorio',
          territoryId:   _objetivoGlobal?['territorioId']    as String? ?? '',
          mode:          'global',
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) _mostrarError(e.message ?? 'Error al conquistar.');
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'conquista_global');
      debugPrint('Error conquista global: $e');
      if (mounted) _mostrarError('Error inesperado. Inténtalo de nuevo.');
    } finally {
      if (mounted) _modeCtrl.setGlobalConquistando(false);
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
          const Icon(Icons.flag_rounded, color: _kGoldLight, size: 38),
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
            child: Text('+$recompensa pts el lunes si sigues siendo dueño  ·  +50 pts de liga',
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
  void _onTrackingEvent(TrackingEvent event) async {
    if (!mounted) return;

    if (event is GpsPointEvent) {
      _gpsSnackBar?.close();
      _gpsSnackBar = null;

      _bearing = event.bearing;
      setState(() {
        routePoints.add(event.punto);
        _currentPosition = event.position;
        _puntosDesdeUltimoUpdate++;
      });

      _moverCamara(
          lat: event.position.latitude, lng: event.position.longitude,
          zoom: _kZoomCorrer,
          bearing: _userRotatedMap ? null : _bearing,
          pitch: _kPitchCorrer);
      if (_puntosDesdeUltimoUpdate >= _kActualizarMapaCadaN) {
        _puntosDesdeUltimoUpdate = 0;
        _actualizarRutaEnMapa();
        if (!_modoRuta) _actualizarPreviewTerritorio();
      }

      if (_retoActivo != null && !_retoCompletado) {
        final objetivoMetros =
            (_retoActivo!['objetivo_valor'] as num?)?.toDouble() ?? 0;
        final distanciaMetros = _session.distanciaTotal * 1000;
        if (objetivoMetros > 0) {
          _narrador.eventoMitadReto(distanciaMetros);
          _narrador.eventoFinalReto(distanciaMetros);
          if (distanciaMetros >= objetivoMetros) {
            _modeCtrl.setRetoCompletado();
            final titulo = _retoActivo!['titulo'] as String? ?? 'Reto';
            _narrador.anunciarRetoCompletado(titulo);
            _mostrarNotificacionRetoCompletado();
          }
        }
      }

      if (_objetivoGlobal != null && !_globalKmAlcanzados && !_globalConquistando) {
        final kmReq = (_objetivoGlobal!['kmRequeridos'] as num?)?.toDouble() ?? 0;
        if (kmReq > 0 && _session.distanciaTotal >= kmReq) {
          _modeCtrl.setGlobalKmAlcanzados();
          final nombreTer =
              _objetivoGlobal!['territorioNombre'] as String? ?? 'Territorio';
          _narrador.anunciarReto(
              '⚔️ ¡$nombreTer alcanzado! Finaliza la carrera para reclamar.');
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 150),
              () { if (mounted) HapticFeedback.heavyImpact(); });
          Future.delayed(const Duration(milliseconds: 300),
              () { if (mounted) HapticFeedback.heavyImpact(); });
        }
      }

      if (!_modoSolitario) _procesarPosicionEnTerritorios(event.punto);

      if (_rutaGuiada != null && _rutaGuiada!.coords.isNotEmpty) {
        _actualizarProgresoRutaGuiada(event.punto);
      }

      final kmActual = _session.distanciaTotal.floor();
      if (kmActual > 0) _narrador.eventoKilometro(kmActual);

      if (kmActual > _session.kmUltimoSplit) {
        final t = _stopwatch.elapsed.inSeconds.toDouble();
        final dt = t - _session.tiempoUltimoSplitSeg;
        if (dt > 0) _session.addSplit(dt / 60.0);
        _session.tiempoUltimoSplitSeg = t;
        _session.kmUltimoSplit = kmActual;
      }

      if (_session.distanciaTotal - _distanciaUltimoAnalisisRitmo >= 0.5) {
        _distanciaUltimoAnalisisRitmo = _session.distanciaTotal;
        _narrador.analizarRitmo(_session.velocidadKmh);
      }

      if (!_modoSolitario) {
        final double radioRadar = SubscriptionService.radioRadar;
        for (final entry in _jugadoresActivos.entries) {
          final lat2 = (entry.value['lat'] as num?)?.toDouble();
          final lng2 = (entry.value['lng'] as num?)?.toDouble();
          if (lat2 == null || lng2 == null) continue;
          final dist = Geolocator.distanceBetween(
              event.position.latitude, event.position.longitude, lat2, lng2);
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

    } else if (event is AntiCheatCancelEvent) {
      if (_sesionInvalidadaPorCheat) return;
      _sesionInvalidadaPorCheat = true;
      _timerSesion?.cancel();
      GameStateService.instance.clearSession();
      _tracking.stop();
      _timerPublicarPosicion?.cancel();
      _stopwatch.stop();
      _timerController.pause();
      await AntiCheatWarningOverlay.mostrar(context, motivo: event.motivo);
      if (mounted) {
        WakelockPlus.disable();
        _session.stopSession();
        setState(() {
          _hudMinimizado = false;
          routePoints.clear();
        });
        await _limpiarPresenciaFirestore();
      }

    } else if (event is GpsErrorEvent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Señal GPS perdida. Busca un espacio abierto.'),
        backgroundColor: Color(0xFFFF453A),
        duration: Duration(seconds: 4),
      ));
    }
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

  void _confirmarYComenzar() {
    HapticFeedback.lightImpact();

    final titulo = _modoRuta
        ? 'Iniciar carrera'
        : _modoSolitario
            ? 'Iniciar exploración'
            : 'Iniciar conquista';

    final subtitulo = _modoRuta
        ? 'Se registrará tu recorrido completo.'
        : _modoSolitario
            ? 'Modo solitario — explora los barrios de tu ciudad.'
            : 'Modo competitivo — conquista territorio para tu ciudad.';

    final iconData = _modoRuta
        ? Icons.route_rounded
        : _modoSolitario
            ? Icons.explore_rounded
            : Icons.flag_rounded;

    final actionLabel = _modoRuta
        ? 'Correr'
        : _modoSolitario
            ? 'Explorar'
            : 'Conquistar';

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF3A3A3C), width: 0.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCC2222).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(iconData, color: const Color(0xFFCC2222), size: 26),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 13,
                        height: 1.45,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ]),
                ),
                Container(height: 0.5, color: const Color(0xFF3A3A3C)),
                IntrinsicHeight(
                  child: Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(16)),
                          ),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    Container(width: 0.5, color: const Color(0xFF3A3A3C)),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _iniciarCuentaAtras();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.only(
                                bottomRight: Radius.circular(16)),
                          ),
                          child: Text(
                            actionLabel,
                            style: const TextStyle(
                              color: Color(0xFFCC2222),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    _session.startSession();
    _modeCtrl.resetParaSesion();
    setState(() {
      _bearing                 = 0;
      _userRotatedMap          = false;
      routePoints.clear();
      _puntosDesdeUltimoUpdate = 0;
      _territoriosNotificadosEnSesion.clear();
      _territoriosVisitadosEnSesion.clear();
      _ultimaNotifRival.clear();
      _hudMinimizado           = true;
    });
    _limpiarPreviewTerritorio();
    _antiCheat.resetear();
    _sesionInvalidadaPorCheat = false;
    _stopping = false;
    // El usuario está corriendo — cancelar aviso de racha
    LocalNotifService.cancelarRecordatorioRacha();
    _stopwatch.reset();
    _stopwatch.start();

    if (_currentPosition == null && mounted) {
      _gpsSnackBar = ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 15),
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3A3A3C)),
          ),
          child: const Row(children: [
            SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: Color(0xFF636366)),
            ),
            SizedBox(width: 12),
            Text('Buscando señal GPS...', style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            )),
          ]),
        ),
      ));
    }
    WakelockPlus.enable();
    _iniciarTimerSesion();
    _timerController.start();
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
      if (!_session.isTracking || _session.isPaused || !mounted) return;
      final mins = _stopwatch.elapsed.inMinutes;
      if (mins >= 20 && mins % 10 == 0 && mins != _minutosResistenciaNotificados) {
        _minutosResistenciaNotificados = mins;
        _narrador.eventoResistencia(mins);
      }
    });

    await _mapboxMap?.gestures.updateSettings(
        mapbox.GesturesSettings(rotateEnabled: true, pitchEnabled: false));
    if (_currentPosition != null) {
      await _moverCamara(
        lat: _currentPosition!.latitude, lng: _currentPosition!.longitude,
        zoom: _kZoomCorrer, bearing: _bearing, pitch: _kPitchCorrer,
        duracion: 4000, forzar: true,
      );
    }


    _trackingEventsSub = _tracking.events.listen(_onTrackingEvent);
    _tracking.start();

    if (_objetivoGlobal != null) {
      final tId = _objetivoGlobal!['territorioId'] as String?;
      if (tId != null) {
        _globalTerritoryLastOwner =
            _objetivoGlobal!['ownerUid'] as String?;
        _globalTerritoryStream?.cancel();
        _globalTerritoryStream = TerritoryService.streamGlobalTerritory(tId)
            .listen((snap) {
          if (!mounted || !_session.isTracking) return;
          if (!snap.exists) return;
          final data    = snap.data()!;
          final newOwner = data['ownerUid'] as String?;
          final uid      = FirebaseAuth.instance.currentUser?.uid;
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
                    const Icon(Icons.flash_on_rounded, color: Color(0xFFFF5252), size: 20),
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
    final nowPaused = !_session.isPaused;
    _session.setPaused(nowPaused);
    setState(() { _hudMinimizado = !nowPaused; });
    if (nowPaused) {
      _timerController.pause();
      _stopwatch.stop();
      _bounceAnim.stop();
      _tracking.pause();
      _ajustarPresenciaPausado();
      if (_currentPosition != null) {
        _moverCamara(lat: _currentPosition!.latitude,
            lng: _currentPosition!.longitude,
            zoom: _kZoomPausado, pitch: _kPitchPausado, bearing: _bearing,
            duracion: 1000, forzar: true);
      }
      _hudAnim.forward();
    } else {
      _userRotatedMap = false;
      _relockTimer?.cancel();
      _timerController.start();
      _stopwatch.start();
      WakelockPlus.enable();
      _bounceAnim.repeat(reverse: true);
      _tracking.resume();
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
    _userRotatedMap = false;
    _relockTimer?.cancel();
    _timerSesion?.cancel();
    GameStateService.instance.clearSession();

    _stopwatch.stop();
    _timerController.pause();
    _tracking.stop();
    _timerPublicarPosicion?.cancel();
    _pulsoTimer?.cancel();
    await _limpiarPresenciaFirestore();
    await _limpiarPreviewTerritorio();

    if (_modoSolitario) {
      await _limpiarCapasBarrios();
    }

    final tiempoFinal    = _stopwatch.elapsed;
    final rutaFinal      = List<LatLng>.from(routePoints);
    final distanciaFinal = _session.distanciaTotal;

    if (distanciaFinal < 0.2) {
      _stopping = false;
      WakelockPlus.disable();
      if (!mounted) return;
      _session.stopSession();
      setState(() { _hudMinimizado = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
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
            const Icon(Icons.straighten_rounded, color: _kGoldLight, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(
              'Distancia mínima no alcanzada.\nCorre al menos 200 m para guardar la sesión.',
              style: GoogleFonts.inter(color: _kGoldLight,
                  fontSize: 13, fontWeight: FontWeight.w600),
            )),
          ]),
        ),
      ));
      // Solo popear si hay una ruta a la que volver; si estamos embebidos en
      // el IndexedStack no hay nada que popear y la pantalla ya muestra idle.
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }

    if (mounted) {
      _session.stopSession();
      setState(() { _hudMinimizado = false; });
    }
    await _mapboxMap?.gestures.updateSettings(
        mapbox.GesturesSettings(rotateEnabled: true, pitchEnabled: false));
    await _moverCamara(
      lat: _currentPosition?.latitude  ?? 40.4167,
      lng: _currentPosition?.longitude ?? -3.70325,
      zoom: _kZoomGlobo, bearing: 0, pitch: _kPitchNormal,
      animated: true, duracion: 1200,
    );

    // Verificar conectividad — Firestore hace cola offline, pero el usuario debe saberlo
    final connectivity = await Connectivity().checkConnectivity();
    final bool sinRed  = connectivity.isEmpty ||
        (connectivity.length == 1 && connectivity.first == ConnectivityResult.none);

    String? logId;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && distanciaFinal > 0) {
        if (!_modoRuta) {
          final monedasBase    = (distanciaFinal * 10).round();
          final bool esPremium = SubscriptionService.currentStatus.isPremium;
          final int multiplicador = (_boostXpActivo ? 2 : 1) * (esPremium ? 2 : 1);
          final double factorModo = multiplicadorMonedas(_modoSolitario);
          final int monedasFinales =
              (monedasBase * multiplicador * factorModo).round();
          await ActivityService.acreditarMonedas(user.uid, monedasFinales);
        }

        final now = DateTime.now();
        logId = await ActivityService.registrarSesion({
          'userId':          user.uid,
          'distancia':       distanciaFinal,
          'tiempo_segundos': tiempoFinal.inSeconds,
          'velocidad_media': StatsService.velocidadKmh(distanciaFinal, tiempoFinal.inSeconds),
          'boost_activo':    _boostXpActivo,
          'latFinal':        _currentPosition?.latitude,
          'lngFinal':        _currentPosition?.longitude,
          'ownerColor':      _colorTerritorio.toARGB32(),
          'titulo': _modoRuta
              ? 'Ruta Libre'
              : _modoSolitario
                  ? 'Exploración Solitaria'
                  : _objetivoGlobal != null
                      ? 'Guerra Global · ${_objetivoGlobal!['territorioNombre']}'
                      : 'Carrera Competitiva',
          'modo': _modoRuta
              ? 'ruta'
              : _modoSolitario
                  ? 'solitario'
                  : _objetivoGlobal != null ? 'guerra_global' : 'competitivo',
          'fecha_dia':
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          'ruta': rutaFinal.isNotEmpty
              ? rutaFinal.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList()
              : [],
          'velocidad_maxima':  _session.velocidadMaxKmh,
          'elevacion_ganada':  _session.elevacionGanada,
          'elevacion_perdida': _session.elevacionPerdida,
          'splits_por_km':     _session.splits,
          if (_objetivoGlobal != null) ...{
            'objetivo_global_id':           _objetivoGlobal!['territorioId'],
            'objetivo_global_conquistado':  _globalConquistado,
          },
        });

        StatsService.actualizarPRs(
          uid:             user.uid,
          distanciaKm:     distanciaFinal,
          ritmoMinKm:      StatsService.ritmoMinKm(distanciaFinal, tiempoFinal.inSeconds),
          velocidadMaxKmh: _session.velocidadMaxKmh,
          elevacionGanada: _session.elevacionGanada,
        ).catchError((e) => debugPrint('actualizarPRs: $e'));

        ActivityService.programarNotificacionesPostCarrera(user.uid, distanciaFinal);

        if (logId != null) {
          if (_objetivoGlobal != null && _globalKmAlcanzados) {
            await _conquistarTerritorioGlobal(logId);
          }
          if (rutaFinal.isNotEmpty) {
            StatsService.enriquecerLog(logId: logId, ruta: rutaFinal)
                .catchError((e) => debugPrint('Error enriquecerLog: $e'));
          }
        }
      }
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'guardar_log_sesion');
      debugPrint('Error log: $e');
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Error al guardar el registro'),
            content: Text(e.toString()),
            actions: [CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            )],
          ),
        );
      }
    }

    if (distanciaFinal > 0 && !_sesionInvalidadaPorCheat) {
      final sesionCheck = AntiCheatService.analizarSesionCompleta(
        ruta: rutaFinal, tiempo: tiempoFinal, distanciaKm: distanciaFinal,
      );
      if (!sesionCheck.esValida) {
        _sesionInvalidadaPorCheat = true;
        if (mounted) {
          await AntiCheatWarningOverlay.mostrar(
              context, motivo: sesionCheck.motivo ?? 'Sesión inválida');
          if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
        }
        _stopping = false;
        return;
      }
    }

    int conquistados = 0;

    if (_modoRuta) {
      await _guardarRutaLibre(rutaFinal, tiempoFinal, distanciaFinal);
      return;
    }

    if (_modoSolitario) {
      final territorioId = await TerritoryService.crearTerritorioSolitario(
        ruta:            rutaFinal,
        colorTerritorio: _colorTerritorio,
        nickname:        _miNickname,
      );
      if (territorioId != null) {
        conquistados = 1;
        if (logId != null) ActivityService.vincularLogTerritorio(logId, territorioId);
        final nuevosTerritorios =
            await TerritoryService.cargarTodosLosTerritorios(modo: 'solitario');
        GameStateService.instance.setSolitarioTerritories(nuevosTerritorios);
        if (mounted) setState(() => _territorios = nuevosTerritorios);
        await _verificarBarriosCompletados();
        if (mounted) {
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 150), () { if (mounted) HapticFeedback.heavyImpact(); });
          Future.delayed(const Duration(milliseconds: 300), () { if (mounted) HapticFeedback.heavyImpact(); });
          await ConquistaOverlay.mostrar(context, esInvasion: false);
        }
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
                Icon(Icons.map_rounded, color: _p.goldDim, size: 20),
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
      if (mounted) {
        setState(() {
          _barriosCercanos = [];
          _barrioActual    = null;
        });
      }
    } else if (_objetivoGlobal == null && distanciaFinal >= 0.3) {
      final double velMedia = _session.velocidadKmh > 0
          ? _session.velocidadKmh
          : (distanciaFinal > 0 && tiempoFinal.inSeconds > 0
              ? distanciaFinal / (tiempoFinal.inSeconds / 3600)
              : 5.0);

      // Crear territorio propio desde el convex hull de la ruta
      final territorioId = await TerritoryService.crearTerritorioCompetitivo(
        ruta:               rutaFinal,
        colorTerritorio:    _colorTerritorio,
        nickname:           _miNickname,
        velocidadMediaKmh:  velMedia,
      );
      if (territorioId != null) {
        conquistados = 1;
        if (logId != null) ActivityService.vincularLogTerritorio(logId, territorioId);
        final nuevos = await TerritoryService.cargarTodosLosTerritorios(
            centro: _currentPosition != null
                ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                : null,
            modo: 'competitivo');
        GameStateService.instance.setCompetitiveTerritories(nuevos);
        if (mounted) setState(() => _territorios = nuevos);
      } else {
        // Área insuficiente — intentar conquistas sobre territorios existentes
        conquistados =
            await _procesarConquistas(rutaFinal, tiempoFinal, distanciaFinal);
      }

      DesafiosService.acumularPuntos(
        uid:                     FirebaseAuth.instance.currentUser?.uid ?? '',
        distanciaKm:             distanciaFinal,
        territoriosConquistados: conquistados,
      );
      if (mounted && distanciaFinal > 0) {
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 150), () { if (mounted) HapticFeedback.heavyImpact(); });
        Future.delayed(const Duration(milliseconds: 300), () { if (mounted) HapticFeedback.heavyImpact(); });
        await ConquistaOverlay.mostrar(context, esInvasion: false);
      }
    }

    if (!mounted) { _stopping = false; return; }

    final puntosLigaGanados = _modoSolitario
        ? 0
        : _objetivoGlobal != null
            ? 0
            : (distanciaFinal > 0 ? 15 : 0) + (conquistados * 25);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DesafiosService.verificarExpirados(user.uid);
      if (puntosLigaGanados > 0) {
        LeagueService.sumarPuntosLiga(user.uid, puntosLigaGanados)
            .catchError((e) { debugPrint('LeagueService competitivo: $e'); return null; });
      }
      // Puntos ranking semanal para modo Global (5 pts/km + 50 bonus si conquista)
      if (_objetivoGlobal != null && distanciaFinal > 0) {
        final pts = (distanciaFinal * 5).round() + (_globalConquistado ? 50 : 0);
        if (pts > 0) {
          RankingService.sumarPuntosGlobal(user.uid, pts)
              .catchError((e) { debugPrint('RankingService global: $e'); return null; });
        }
      }
    }

    await HealthService.registrarCarrera(
      inicio: DateTime.now().subtract(tiempoFinal),
      fin:    DateTime.now(),
      distanciaKm: distanciaFinal,
    );

    _stopping = false;
    if (!mounted) return;

    if (sinRed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Sin conexión — tu carrera se guardará automáticamente cuando vuelvas a tener red.',
          style: TextStyle(fontSize: 13),
        ),
        backgroundColor: AppColors.red,
        duration: Duration(seconds: 5),
      ));
    }

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
      'splitsPorKm':             List<double>.from(_session.splits),
      'velocidadMaxima':         _session.velocidadMaxKmh,
      'elevacionGanada':         _session.elevacionGanada,
      'elevacionPerdida':        _session.elevacionPerdida,
      'modoInicial':             _modoSolitario ? 'solitario'
                                     : _objetivoGlobal != null ? 'global'
                                     : 'competitivo',
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
      if (!_territoriosVisitadosEnSesion.contains(t.docId) &&
          _session.distanciaTotal * 1000 >= 200) {
        _territoriosVisitadosEnSesion.add(t.docId);
        TerritoryService.actualizarUltimaVisita(t.docId);
        _narrador.eventoTerritorioPropio();
        _mostrarSnackRefuerzo(t);
      }
    } else {
      if (!_territoriosNotificadosEnSesion.contains(t.docId)) {
        _territoriosNotificadosEnSesion.add(t.docId);
        final ahora   = DateTime.now();
        final ultima  = _ultimaNotifRival[t.docId];
        final debounce = ultima == null || ahora.difference(ultima).inMinutes >= 30;
        if (!t.esFantasma && debounce) {
          _ultimaNotifRival[t.docId] = ahora;
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

    final double velocidadMedia = _session.velocidadKmh > 0
        ? _session.velocidadKmh
        : (distancia > 0 && tiempo.inSeconds > 0
            ? distancia / (tiempo.inSeconds / 3600)
            : 5.0);

    final territoriosObjetivo = _territorios.where((t) {
      if (t.esMio) return false;
      final paso    = _rutaPasaPorPoligono(ruta, t.puntos);
      final cercano = t.esConquistableSinPasar &&
          _rutaPasaCercaDe(ruta, t.centro, radioMetros: 50);
      return paso || cercano;
    }).toList();

    if (territoriosObjetivo.isEmpty) return 0;

    bool huboError = false;

    final resultados = await Future.wait(
      territoriosObjetivo.map((t) async {
        try {
          final ataque = await TerritoryService.atacarTerritorio(
            territorioDefensorId: t.docId,
            rutaAtacante:         ruta,
            velocidadMediaKmh:    velocidadMedia,
          );

          if (ataque.conquistoAlgo) {
            _narrador.eventoConquista(t.ownerNickname);
            if (ataque.accion == 'conquista_total') {
              _escribirActivityFeed(
                territoryName:     t.nombreTerritorio ?? t.ownerNickname,
                territoryId:       t.docId,
                mode:              _modoSolitario ? 'solitario' : 'competitivo',
                previousOwnerNick: t.ownerNickname,
                fromColorValue:    t.color.toARGB32(),
              );
            }
            _puntosGloboCargados = false;
            final nuevos = await TerritoryService.cargarTodosLosTerritorios(
                centro: _currentPosition != null
                    ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                    : null,
                modo: _modoSolitario ? 'solitario' : 'competitivo');
            if (_modoSolitario) {
              GameStateService.instance.setSolitarioTerritories(nuevos);
            } else {
              GameStateService.instance.setCompetitiveTerritories(nuevos);
            }
            if (mounted) {
              setState(() => _territorios = nuevos);
              await _dibujarTerritoriosEnMapa();
            }
            return 1;
          } else if (ataque.accion == 'daño' && ataque.ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.transparent,
              elevation: 0,
              content: _snackWrap(
                gradient: const LinearGradient(
                    colors: [Color(0xFF6B1500), Color(0xFFD4520A)]),
                shadow: _p.terracotta,
                child: Row(children: [
                  const Icon(Icons.flash_on_rounded,
                      color: Color(0xFFFFE8C0), size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    'Daño causado. HP rival: ${ataque.hpDespues}%',
                    style: const TextStyle(color: Color(0xFFFFE8C0),
                        fontWeight: FontWeight.bold, fontSize: 13),
                  )),
                ]),
              ),
            ));
          }
          return 0;
        } catch (e, st) {
          FirebaseCrashlytics.instance.recordError(e, st, reason: 'atacar_territorio');
          huboError = true;
          return 0;
        }
      }),
      eagerError: false,
    );

    final total = resultados.fold<int>(0, (acc, val) => acc + val);

    if (huboError && total == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: _snackWrap(
          gradient: const LinearGradient(
              colors: [Color(0xFF1C1C1E), Color(0xFF2C2C2E)]),
          shadow: Colors.black54,
          child: const Row(children: [
            Icon(Icons.wifi_off_rounded, color: Color(0xFF636366), size: 18),
            SizedBox(width: 10),
            Expanded(child: Text(
              'No se pudo procesar la conquista — comprueba tu conexión',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            )),
          ]),
        ),
      ));
    }

    return total;
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
    Future.delayed(const Duration(milliseconds: 150), () { if (mounted) HapticFeedback.heavyImpact(); });
    Future.delayed(const Duration(milliseconds: 300), () { if (mounted) HapticFeedback.heavyImpact(); });
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

  void _mostrarSnackTerritorioRival(TerritoryData t) {
    if (!mounted) return;
    final String estadoLabel;
    final Color  estadoColor;
    final String consejo;
    switch (t.estadoHp) {
      case EstadoHp.saludable:
        estadoLabel = 'FUERTE'; estadoColor = _kVerde;
        consejo = 'Necesitas >7 km/h para dañarlo';
      case EstadoHp.danado:
        estadoLabel = 'MEDIO'; estadoColor = _kGold;
        consejo = 'Necesitas >5 km/h';
      case EstadoHp.critico:
        estadoLabel = '¡LEVE!'; estadoColor = _p.globalRed;
        consejo = '¡Cualquier paso lo conquista!';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.of(context).padding.bottom + 110),
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
            child: Center(child: Icon(Icons.circle_rounded, color: estadoColor, size: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Icon(Icons.flash_on_rounded, color: _kGoldLight, size: 12),
                  const SizedBox(width: 3),
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

  // ==========================================================================
  // BUILD PRINCIPAL
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    final bool mostrarGlobo = !_session.isTracking && !_mostrandoCuentaAtras;
    return Scaffold(
      // Fondo azul universo — especialmente visible en modo oscuro
      backgroundColor: _modoNoche ? _kUniverseBg : Colors.black,
      body: Stack(children: [

        // ── 1. FONDO AZUL UNIVERSO (siempre abajo del todo) ────────────────
        if (mostrarGlobo)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: _modoNoche
                      ? [
                          const Color(0xFF102C50), // azul marino visible centro
                          const Color(0xFF071830), // azul profundo borde
                        ]
                      : [
                          const Color(0xFF1A2A3A),
                          const Color(0xFF0A1420),
                        ],
                ),
              ),
            ),
          ),

        // ── 2a. ESTRELLAS DARK — detrás del globo (el área exterior de Mapbox es transparente) ──
        if (mostrarGlobo && Theme.of(context).brightness == Brightness.dark)
          Positioned.fill(
            child: IgnorePointer(
              child: _StarfieldWidget(
                nightMode: true,
                globeAnim: _globoAnim,
              ),
            ),
          ),

        // ── 2. MAPA MAPBOX ──────────────────────────────────────────────────
        Positioned.fill(child: _buildMapbox()),

        // ── 3. ESTRELLAS — encima del mapa, visibles en ambos modos ────────
        if (mostrarGlobo)
          Positioned.fill(
            child: IgnorePointer(
              child: _StarfieldWidget(
                nightMode: _modoNoche,
                globeAnim: _globoAnim,
              ),
            ),
          ),

        // ── 4. OVERLAY DEL GLOBO (viñeta + títulos + stats, sin IgnorePointer global) ──
        if (mostrarGlobo)
          Positioned.fill(child: _buildGloboOverlay()),

        // ── 4b. Chips interactivos (fuera de IgnorePointer para permitir taps) ───
        if (mostrarGlobo)
          Positioned(
            top: 148, left: 14,
            child: _buildChipsGlobo(),
          ),

        // ── 5. HUD y controles ──────────────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: ListenableBuilder(
            listenable: _session,
            builder: (_, __) => _buildHUD(),
          ),
        ),
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
        // Avatar se muestra en el puck de Mapbox (posición GPS real)
        if (_session.isTracking)
          AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: _session.isPaused
                ? const Alignment(0, -0.1)
                : (_hudMinimizado
                    ? const Alignment(0, -0.78)
                    : const Alignment(0, -0.50)),
            child: _buildTimerGrande(),
          ),
        if (_mapaDesactualizado)
          Positioned(
            bottom: _session.isTracking ? 180 : 100, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.wifi_off_rounded, color: Colors.white, size: 13),
                  SizedBox(width: 6),
                  Text('MAPA DESACTUALIZADO', style: TextStyle(
                    color: Colors.white, fontSize: 10,
                    fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                ]),
              ),
            ),
          ),
        if (_mostrandoCuentaAtras) _buildCuentaAtras(),
        if (_session.isTracking && !_session.isPaused && _session.mensajeNarrador != null)
          Positioned(bottom: 175, left: 0, right: 0,
              child: NarradorOverlay(mensaje: _session.mensajeNarrador)),
        if (_session.isTracking && _modoSolitario && _barrioActual != null)
          Positioned(top: 160, left: 0, right: 0,
              child: Center(child: _buildChipBarrioActual())),
        if (_session.isTracking && _retoActivo != null && !_retoCompletado)
          Positioned(
            top: (_modoSolitario && _barrioActual != null) ? 210 : 160,
            left: 0, right: 0,
            child: Center(child: _buildChipRetoActivo()),
          ),
        if (_objetivoGlobal != null && !_globalConquistado && _session.isTracking)
          Positioned(
            top: (_retoActivo != null || (_modoSolitario && _barrioActual != null)) ? 248 : 248,
            left: 14,
            child: _buildChipObjetivoGlobal(),
          ),
        if (_globalConquistando)
          Positioned.fill(child: _buildConquistadoOverlay()),
        if (_territorioInfo != null) _buildTerritoryInfoOverlay(),
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBotonera()),
      ]),
    );
  }

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
      // Cede los gestos al MapWidget antes de que Flutter los intercepte
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
      },
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: _onStyleLoaded,
      onCameraChangeListener: _onCameraChanged,
      onTapListener: _onMapTap,
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
        initialZoom: _session.isTracking ? _kZoomCorrer : 3.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(urlTemplate: _kTileUrl,
            userAgentPackageName: 'com.runner_risk.app'),
        if (_territorios.isNotEmpty) PolygonLayer(
          polygons: _territorios.map((t) {
            final col = t.color;
            return Polygon(
              points: t.puntos,
              color: col.withValues(alpha: 0.22),
              borderColor: col,
              borderStrokeWidth: t.esMio ? 2.5 : 1.5,
            );
          }).toList(),
        ),
        if (_session.isTracking && routePoints.isNotEmpty) PolylineLayer(
          polylines: [Polyline(points: routePoints,
              color: _colorTerritorio, strokeWidth: 4.5)],
        ),
        if (_session.isTracking && _currentPosition != null) MarkerLayer(
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
}

