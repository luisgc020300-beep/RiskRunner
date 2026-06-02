// lib/screens/fullscreen_map_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shimmer/shimmer.dart';

import '../services/territory_service.dart';
import '../services/game_state_service.dart';
import '../services/activity_service.dart';
import '../services/route_service.dart';
import '../widgets/custom_navbar.dart';
import '../shell/app_shell.dart';
import '../config/env.dart';
import '../widgets/map/map_theme.dart';
import '../widgets/map/map_dialogs.dart';
import '../widgets/map/map_starfield.dart';

// =============================================================================
// MAPBOX
// =============================================================================
const String _kMapboxToken = Env.mapboxPublicToken;
const String _kMapboxUrl =
    'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12'
    '/tiles/256/{z}/{x}/{y}@2x?access_token=$_kMapboxToken';


// =============================================================================
// PALETA — aliases privados sobre las constantes públicas de map_theme.dart
// =============================================================================
const _kBg        = kMapBg;
const _kSurface   = kMapSurface;
const _kSurface2  = kMapSurface2;
const _kBorder    = kMapBorder;
const _kBorder2   = kMapBorder2;
const _kDim       = kMapDim;
const _kSub       = kMapSub;
const _kText      = kMapText;
const _kWhite     = kMapWhite;
const _kRed       = kMapRed;
const _kSafe      = kMapSafe;
const _kWarn      = kMapWarn;
const _kGold      = kMapGold;
const _kGoldDim   = kMapGoldDim;
const _kGoldLight = kMapGold;
const _kCyan      = kMapCyan;
const _kBlue      = kMapBlue;

TextStyle _raj(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    mapRaj(size, weight, color, spacing: spacing, height: height);

TextStyle _cinzel(double size, FontWeight weight, Color color,
    {double spacing = 0}) =>
    mapCinzel(size, weight, color, spacing: spacing);

// aliases para los call sites existentes
typedef _DialogoRenombrar            = MapDialogoRenombrar;
typedef _DialogoConfirmarConquista   = MapDialogoConfirmarConquista;
typedef _DialogoConquistando         = MapDialogoConquistando;
typedef _StarfieldPainter            = MapStarfieldPainter;
typedef _Star                        = MapStar;



// =============================================================================
// MODELO BARRIO (modo solitario)
// =============================================================================
class _ShStat {
  final String value, label;
  const _ShStat(this.value, this.label);
}

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
    final lat = puntos.map((p) => p.latitude).reduce((a, b) => a + b) / puntos.length;
    final lng = puntos.map((p) => p.longitude).reduce((a, b) => a + b) / puntos.length;
    return LatLng(lat, lng);
  }
}


// =============================================================================
// MODELOS MI CIUDAD
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
  final String ownerId;
  final String? nombreTerritorio;
  _TerDet({required this.docId, required this.dist,
      this.diasSinVisitar, this.puntos = const [],
      this.ownerId = '', this.nombreTerritorio});
}

// =============================================================================
// SERVICIO DE DATOS
// =============================================================================
class _MapDataService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const double _kRadGrados = 0.045;

  Future<List<_UserGroup>> cargarGruposCercanos(LatLng centro, String myUid, {String modo = 'competitivo'}) async {
    final latMin = centro.latitude  - _kRadGrados;
    final latMax = centro.latitude  + _kRadGrados;
    QuerySnapshot snap;
    try {
      snap = await _db.collection('territories')
          .where('centroLat', isGreaterThan: latMin)
          .where('centroLat', isLessThan:    latMax)
          .get();
    } catch (e) {
      snap = await _db.collection('territories').get();
    }
    final Map<String, List<_TerDet>> tersPorOwner = {};
    for (final doc in snap.docs) {
      final data = (doc.data() ?? {}) as Map<String, dynamic>;
      final rawPts = data['puntos'] as List<dynamic>?;
      if (rawPts == null || rawPts.isEmpty) continue;
      // Filter by mode: solitario territories are private; competitive shows null+competitivo
      final docModo = data['modo'] as String?;
      if (modo == 'solitario') {
        if (docModo != 'solitario') continue;
        final docOwner = data['userId'] as String? ?? '';
        if (docOwner != myUid) continue;
      } else {
        if (docModo == 'solitario') continue;
      }
      final pts = _parsePuntos(rawPts);
      final c = _centroide(pts);
      final dist = Geolocator.distanceBetween(
          centro.latitude, centro.longitude, c.latitude, c.longitude);
      if (dist > 5000) continue;
      final ownerId = data['userId'] as String? ?? '';
      if (ownerId.isEmpty) continue;
      tersPorOwner.putIfAbsent(ownerId, () => []).add(
          _TerDet(docId: doc.id, dist: dist / 1000, puntos: pts, ownerId: ownerId));
    }
    if (tersPorOwner.isEmpty) return [];
    final ownerIds = tersPorOwner.keys.toList();
    final chunks = _chunked(ownerIds, 30);
    final Map<String, Map<String, dynamic>> playersMap = {};
    final results = await Future.wait(
      chunks.map((chunk) async {
        try {
          return await _db.collection('players')
              .where(FieldPath.documentId, whereIn: chunk).get();
        } catch (_) {
          return null;
        }
      }),
    );
    for (final snap in results) {
      if (snap == null) continue;
      for (final p in snap.docs) { playersMap[p.id] = p.data(); }
    }
    final Map<String, _UserGroup> grupos = {};
    for (final ownerId in tersPorOwner.keys) {
      final pData = playersMap[ownerId];
      final nick = ownerId == myUid ? 'YO' : (pData?['nickname'] as String? ?? ownerId);
      final nivel = (pData?['nivel'] as num? ?? 1).toInt();
      grupos[ownerId] = _UserGroup(
        ownerId: ownerId, nickname: nick, nivel: nivel,
        esMio: ownerId == myUid, territorios: tersPorOwner[ownerId]!,
      );
    }
    return grupos.values.toList()
      ..sort((a, b) {
        if (a.esMio) return -1;
        if (b.esMio) return 1;
        return a.nickname.compareTo(b.nickname);
      });
  }

  Future<List<_TerDet>> cargarDetalles(String ownerId, LatLng centro, {String modo = 'competitivo'}) async {
    final snap = await _db.collection('territories')
        .where('userId', isEqualTo: ownerId).get();
    final List<_TerDet> dets = [];
    for (final doc in snap.docs) {
      final data = doc.data();
      final docModo = data['modo'] as String?;
      if (modo == 'solitario') {
        if (docModo != 'solitario') continue;
      } else {
        if (docModo == 'solitario') continue;
      }
      final rawPts = data['puntos'] as List<dynamic>?;
      if (rawPts == null || rawPts.isEmpty) continue;
      final pts = _parsePuntos(rawPts);
      final c = _centroide(pts);
      final distM = Geolocator.distanceBetween(
          centro.latitude, centro.longitude, c.latitude, c.longitude);
      if (distM > 5000) continue;
      final tsV = data['ultima_visita'] as Timestamp?;
      final dias = tsV == null ? 0 : DateTime.now().difference(tsV.toDate()).inDays;
      dets.add(_TerDet(
        docId: doc.id, dist: distM / 1000, diasSinVisitar: dias,
        puntos: pts, ownerId: ownerId,
        nombreTerritorio: data['nombre_territorio'] as String?,
      ));
    }
    return dets;
  }

  static List<LatLng> _parsePuntos(List<dynamic> raw) => raw.map((p) {
    final m = p as Map<String, dynamic>;
    return LatLng((m['lat'] as num).toDouble(), (m['lon'] != null
        ? (m['lon'] as num).toDouble()
        : (m['lng'] as num).toDouble()));
  }).toList();

  static LatLng _centroide(List<LatLng> pts) => LatLng(
    pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length,
    pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length,
  );

  static List<List<T>> _chunked<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(list.sublist(i, math.min(i + size, list.length)));
    }
    return chunks;
  }
}

// =============================================================================
// CHANGENOTIFIER
// =============================================================================
class _MapState extends ChangeNotifier {
  final _MapDataService _service = _MapDataService();

  List<TerritoryData> territorios             = [];
  bool loadingTerritorios                     = true;
  Map<String, Map<String, dynamic>> jugadoresEnVivo = {};
  Map<String, dynamic>? desafioActivo;
  List<_UserGroup> grupos                     = [];
  bool loadingCercanos                        = false;
  bool cercanosVisible                        = false;
  String? userExpandido;
  TerritoryData? territorioSeleccionado;
  LatLng centro = const LatLng(40.4167, -3.70325);
  String? errorMessage;

  bool modoGlobal                             = false;
  bool modoSolitario                          = false;
  bool modoRutas                              = false;
  List<GlobalTerritory> territoriosGlobales   = [];
  bool loadingGlobal                          = false;
  GlobalTerritory? territorioGlobalSeleccionado;
  int territoriosMios                         = 0;
  static const int maxTerritoriosPorJugador   = 5;
  Color colorJugador                          = const Color(0xFFCC2222);

  int diasRestantesSemana  = 0;
  int totalJugadoresGlobal = 0;

  StreamSubscription? _globalStream;

  static final Map<String, List<_TerDet>> _detallesCache = {};
  static final Map<String, DateTime> _detallesTimestamp = {};
  static const Duration _detallesTTL = Duration(minutes: 2);

  static bool _detallesCacheValido(String ownerId) {
    final ts = _detallesTimestamp[ownerId];
    if (ts == null || !_detallesCache.containsKey(ownerId)) return false;
    return DateTime.now().difference(ts) < _detallesTTL;
  }

  List<_TerDet>? detallesDe(String ownerId) => _detallesCache[ownerId];

  static void invalidarDetallesCache() {
    _detallesCache.clear();
    _detallesTimestamp.clear();
  }

  void setCentro(LatLng c) { centro = c; notifyListeners(); }
  void setLoadingTerritorios(bool v) { loadingTerritorios = v; notifyListeners(); }
  void seleccionarTerritorio(TerritoryData? t) { territorioSeleccionado = t; notifyListeners(); }
  void seleccionarTerritoryGlobal(GlobalTerritory? t) { territorioGlobalSeleccionado = t; notifyListeners(); }
  void setLoadingCercanos(bool v) { loadingCercanos = v; notifyListeners(); }
  void setUserExpandido(String? id) { userExpandido = id; notifyListeners(); }
  void clearError() { errorMessage = null; }

  void setModoSolitario(bool v) {
    GameStateService.instance.currentMode = v ? 'solitario' : 'competitivo';
    modoSolitario = v;
    territorios   = [];
    if (v) {
      modoGlobal = false;
      modoRutas  = false;
      _globalStream?.cancel();
    }
    territorioSeleccionado = null;
    notifyListeners();
  }

  void setModoRutas(bool v) {
    modoRutas     = v;
    modoSolitario = false;
    modoGlobal    = false;
    territorios   = [];
    if (v) {
      _globalStream?.cancel();
      GameStateService.instance.currentMode = 'ruta';
    } else {
      GameStateService.instance.currentMode = 'competitivo';
    }
    territorioSeleccionado = null;
    notifyListeners();
  }

  void toggleModoGlobal() {
    modoGlobal = !modoGlobal;
    if (modoGlobal) { modoSolitario = false; modoRutas = false; }
    GameStateService.instance.currentMode = modoGlobal ? 'global' : 'competitivo';
    territorioSeleccionado = null;
    territorioGlobalSeleccionado = null;
    if (modoGlobal) {
      if (territoriosGlobales.isEmpty) _cargarTerritoriosGlobales();
      _escucharTerritoriosGlobales();
    } else {
      _globalStream?.cancel();
    }
    notifyListeners();
  }

  // ── Stream en tiempo real de global_territories ──────────────────────────
  void _escucharTerritoriosGlobales() {
    _globalStream?.cancel();
    _globalStream = FirebaseFirestore.instance
        .collection('global_territories')
        .where('activo', isEqualTo: true)
        .limit(500)
        .snapshots()
        .listen((snap) {
      if (!modoGlobal) return;
      if (territoriosGlobales.isEmpty) return;

      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

      final Map<String, Map<String, dynamic>> ownershipMap = {
        for (final doc in snap.docs) doc.id: doc.data(),
      };

      territoriosGlobales = territoriosGlobales.map((t) {
        final data = ownershipMap[t.id];
        if (data == null) {
          return t.copyWith(clearOwner: true);
        }

        final ownerUid      = data['ownerUid']      as String?;
        final ownerNickname = data['ownerNickname']  as String?;
        final ownerColorInt = data['ownerColor']     as int?;
        final difficulty    = (data['difficultyLevel'] as num?)?.toInt();
        final count         = (data['conquestCount']   as num?)?.toInt();
        // ── clausulaKm: si no existe en Firestore, usa baseKm como fallback ─
        final clausula      = (data['clausulaKm'] as num?)?.toDouble() ?? t.baseKm;

        if (ownerUid == null) {
          return t.copyWith(
            clearOwner:      true,
            difficultyLevel: difficulty,
            conquestCount:   count,
            clausulaKm:      clausula,
          );
        }

        return t.copyWith(
          ownerUid:        ownerUid,
          ownerNickname:   ownerNickname,
          ownerColor:      ownerUid == uid ? colorJugador : (ownerColorInt != null ? Color(ownerColorInt) : null),
          difficultyLevel: difficulty,
          conquestCount:   count,
          clausulaKm:      clausula,
        );
      }).toList();

      territoriosMios = territoriosGlobales.where((t) => t.ownerUid == uid).length;
      GameStateService.instance.setGlobalTerritories(territoriosGlobales);
      notifyListeners();
    });
  }

  Future<void> _cargarTerritoriosGlobales() async {
    // Usar cache compartido si sigue siendo válido
    final cached = GameStateService.instance.getGlobalTerritories();
    if (cached != null) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      territoriosGlobales = cached.map((t) =>
          (t.ownerUid != null && t.ownerUid == uid)
              ? t.copyWith(ownerColor: colorJugador)
              : t).toList();
      territoriosMios     = territoriosGlobales.where((t) => t.ownerUid == uid).length;
      loadingGlobal = false;
      notifyListeners();
      return;
    }

    loadingGlobal = true;
    notifyListeners();

    try {
      final snap = await FirebaseFirestore.instance
          .collection('global_territories')
          .where('activo', isEqualTo: true)
          .get();

      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final List<GlobalTerritory> fromDb = [];
      for (final doc in snap.docs) {
        var t = GlobalTerritory.fromFirestore(doc);
        if (t == null) continue;
        if (t.ownerUid != null && t.ownerUid == uid) {
          t = t.copyWith(ownerColor: colorJugador);
        }
        fromDb.add(t);
      }

      if (fromDb.isNotEmpty) {
        territoriosGlobales = fromDb;
        territoriosMios     = fromDb.where((t) => t.ownerUid == uid).length;
        GameStateService.instance.setGlobalTerritories(fromDb);
      } else {
        territoriosGlobales = buildSampleGlobalTerritories();
        territoriosMios     = 0;
      }
    } catch (e) {
      debugPrint('Error cargando territorios globales: $e');
      territoriosGlobales = buildSampleGlobalTerritories();
      territoriosMios     = 0;
    }

    final now = DateTime.now();
    final nextMonday = now.add(Duration(
        days: (8 - now.weekday) % 7 == 0 ? 7 : (8 - now.weekday) % 7));
    diasRestantesSemana = nextMonday.difference(now).inDays;

    try {
      final cutoff = Timestamp.fromDate(now.subtract(const Duration(days: 7)));
      final logsSnap = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('timestamp', isGreaterThan: cutoff)
          .limit(500)
          .get();
      final uids = logsSnap.docs
          .map((d) => d.data()['userId'] as String?)
          .whereType<String>()
          .toSet();
      totalJugadoresGlobal = uids.length;
    } catch (_) {
      totalJugadoresGlobal = 0;
    }

    loadingGlobal = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _globalStream?.cancel();
    super.dispose();
  }

  void setTerritorios(List<TerritoryData> lista) {
    territorios = lista;
    loadingTerritorios = false;
    errorMessage = null;
    notifyListeners();
  }

  void setError(String msg) {
    errorMessage = msg;
    loadingTerritorios = false;
    loadingCercanos = false;
    notifyListeners();
  }

  void setJugadores(Map<String, Map<String, dynamic>> j) {
    jugadoresEnVivo = j;
    notifyListeners();
  }

  void setDesafio(Map<String, dynamic>? d) {
    desafioActivo = d;
    notifyListeners();
  }

  void setGrupos(List<_UserGroup> g) {
    grupos = g;
    loadingCercanos = false;
    cercanosVisible = true;
    errorMessage = null;
    notifyListeners();
  }

  void toggleCercanos() {
    cercanosVisible = !cercanosVisible;
    if (!cercanosVisible) userExpandido = null;
    notifyListeners();
  }

  void _setDetalles(String ownerId, List<_TerDet> dets) {
    _detallesCache[ownerId] = dets;
    _detallesTimestamp[ownerId] = DateTime.now();
    notifyListeners();
  }

  Future<void> cargarCercanos(String myUid, {String modo = 'competitivo'}) async {
    setLoadingCercanos(true);
    try {
      final result = await _service.cargarGruposCercanos(centro, myUid, modo: modo);
      setGrupos(result);
    } catch (e) {
      setError('No se pudieron cargar los territorios cercanos');
    }
  }

  Future<void> cargarDetalles(String ownerId, {String modo = 'competitivo'}) async {
    if (_detallesCacheValido(ownerId)) { notifyListeners(); return; }
    try {
      final dets = await _service.cargarDetalles(ownerId, centro, modo: modo);
      _setDetalles(ownerId, dets);
    } catch (e) {
      setError('No se pudieron cargar los detalles');
    }
  }
}

// =============================================================================
// PANTALLA PRINCIPAL
// =============================================================================
enum _FiltroMapa { todos, mios, enGuerra }

class FullscreenMapScreen extends StatefulWidget {
  final List<TerritoryData> territorios;
  final Color colorTerritorio;
  final LatLng? centroInicial;
  final List<LatLng> ruta;
  final bool mostrarRuta;
  /// Cuando es true, la pantalla se abre en modo selección de territorio global.
  /// El botón "INICIAR CONQUISTA" devuelve los datos del territorio vía
  /// Navigator.pop en lugar de navegar a /correr.
  final bool selectionMode;

  const FullscreenMapScreen({
    super.key,
    this.territorios     = const [],
    this.colorTerritorio = const Color(0xFFCC2222),
    this.centroInicial,
    this.ruta            = const [],
    this.mostrarRuta     = false,
    this.selectionMode   = false,
  });

  @override
  State<FullscreenMapScreen> createState() => _FullscreenMapScreenState();
}

class _FullscreenMapScreenState extends State<FullscreenMapScreen>
    with TickerProviderStateMixin {

  // flutter_map MapController eliminado — todos los mapas usan Mapbox
  final DraggableScrollableController _sheetCtrl     = DraggableScrollableController();
  late final _MapState                _state;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  bool   get _isDark   => Theme.of(context).brightness == Brightness.dark;
  Color  get _shBg     => _isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
  Color  get _shSurf   => _isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
  Color  get _shBorder => _isDark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8);
  Color  get _shText   => _isDark ? const Color(0xFFEEEEEE) : const Color(0xFF1C1C1E);

  StreamSubscription? _presenciaStream;
  StreamSubscription? _desafioStreamRetador;
  StreamSubscription? _desafioStreamRetado;
  StreamSubscription<List<TerritoryData>>? _competitiveStreamSub;
  StreamSubscription<List<TerritoryData>>? _solitarioStreamSub;

  // Últimos datos de cada query — se mezclan en _mergeDesafio()
  Map<String, dynamic>? _desafioComoRetador;
  Map<String, dynamic>? _desafioComoRetado;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;
  late AnimationController _selCtrl;
  late Animation<double>   _selAnim;
  late AnimationController _sheetEntryCtrl;
  late Animation<double>   _sheetEntryAnim;
  late AnimationController _toggleCtrl;
  late Animation<double>   _toggleAnim;
  late AnimationController _globalEntryCtrl;
  late Animation<double>   _globalEntryAnim;

  bool _refreshing = false;

  // ── Recarga automática al desplazar el mapa ───────────────────────────────
  Timer?  _cameraDebounce;

  // ── Solitario — scroll reload ─────────────────────────────────────────────
  Timer?  _solCamDebounce;
  LatLng? _solLastCenter;

  // ── Campo de estrellas para el mapa global oscuro ─────────────────────────
  late final List<_Star> _starfield;

  // zoom amplio por defecto al entrar — FAB lleva a la zona del usuario
  static const double _kInitialZoom = 5.0;
  static const double _kLocateZoom  = 15.0;

  static const LatLng _kGlobalCenter = LatLng(20.0, 0.0);

  // ── FIX: Estado del botón centrar (toggle: mi posición ↔ vista inicial) ───
  bool _fabCentradoEnUsuario = false;

  // Toggle mapa claro/oscuro
  bool _mapaOscuro = false;

  // Caché de widgets de mapa — se crea una vez por modo y se reutiliza para
  // evitar recrear el MapWidget (y su contexto Metal/GL nativo) en cada build().
  Widget? _cachedMapaCiudad;
  Widget? _cachedMapaSolitario;
  Widget? _cachedMapaRutas;
  Widget? _cachedMapaGlobal;

  // ── Modo solitario — barrios OSM ──────────────────────────────────────────
  List<_BarrioData> _barriosCercanos  = [];
  bool _barriosCargados               = false;
  bool _cargandoBarrios               = false;
  String? _errorBarrios;
  LatLng? _barriosCentro; // centro donde se cargaron los barrios actuales
  final TextEditingController _barriosSearchCtrl = TextEditingController();
  String _barriosBusqueda = '';
  // Future que completa cuando _resolverCentro() termina de obtener el GPS real.
  // _activarModoSolitario() lo espera para no consultar Overpass con coords por defecto.
  Future<void>? _centroListo;
  bool _gpsResuelto         = false;
  bool _recargandoSilencioso = false;

  // ── Filtro de mapa + actividad ────────────────────────────────────────────
  _FiltroMapa _filtroActivo = _FiltroMapa.todos;
  Future<List<ActivityEntry>>? _feedFuture;
  final Map<String, List<Map<String, dynamic>>> _historialCache = {};

  // ── Modo Ciudad — Mapbox ─────────────────────────────────────────────────
  mapbox.MapboxMap?              _mapboxCiudadMap;
  bool                           _ciudadStyleLoaded    = false;
  bool                           _ciudadLayersCreated  = false;
  bool                           _ciudadLayersCreating = false;
  mapbox.PointAnnotationManager? _ciudadAnnManager;
  final Map<String, mapbox.PointAnnotation> _ciudadJugMarkers = {};
  LatLng?                        _ciudadLastCenter;
  Timer?                         _ciudadCamDebounce;
  Timer?                         _streamTerritoriDebounce;
  Timer?                         _barrioPctDebounce;

  // ── Modo Solitario — Mapbox ──────────────────────────────────────────────
  mapbox.MapboxMap?              _mapboxSolMap;
  bool                           _solStyleLoaded    = false;
  bool                           _solLayersCreated  = false;
  bool                           _solLayersCreating = false;

  // ── Modo Rutas — Mapbox ──────────────────────────────────────────────────
  mapbox.MapboxMap?              _mapboxRutasMap;
  bool                           _rutasStyleLoaded   = false;
  bool                           _rutasLayersCreated = false;

  // ── Modo Global — Mapbox ─────────────────────────────────────────────────
  mapbox.MapboxMap?              _mapboxGlobalMap;
  bool                           _globalMbxStyleLoaded    = false;
  bool                           _globalMbxLayersCreated  = false;
  bool                           _globalMbxLayersCreating = false;

  // ── Modo Rutas ────────────────────────────────────────────────────────────
  List<RouteData> _misRutas        = [];
  bool            _cargandoRutas   = false;
  RouteData?      _rutaSeleccionada;

  @override
  void initState() {
    super.initState();
    _state = _MapState();
    _state.colorJugador = widget.colorTerritorio;
    _state.addListener(_onErrorCheck);
    _state.addListener(_recalcularPorcentajesBarrios);
    _state.addListener(_onStateChangedForCiudad);
    _state.addListener(_onStateChangedForSolitario);
    _state.addListener(_onStateChangedForGlobal);

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _selCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _selAnim = CurvedAnimation(parent: _selCtrl, curve: Curves.easeOutCubic);

    _sheetEntryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _sheetEntryAnim = CurvedAnimation(
        parent: _sheetEntryCtrl, curve: Curves.easeOutCubic);

    _toggleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _toggleAnim = CurvedAnimation(parent: _toggleCtrl, curve: Curves.easeInOut);

    _globalEntryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _globalEntryAnim = CurvedAnimation(
        parent: _globalEntryCtrl, curve: Curves.easeOutCubic);

    _starfield = _StarfieldPainter.generate();
    _initData();
    // scroll reload via onScrollListener en cada MapWidget Mapbox
    _feedFuture = ActivityService.obtenerFeedReciente();

    if (widget.selectionMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_state.modoGlobal) _toggleModo();
      });
    } else {
      final savedMode = GameStateService.instance.currentMode;
      if (savedMode == 'global') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_state.modoGlobal) _toggleModo();
        });
      } else if (savedMode == 'solitario') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_state.modoSolitario) _activarModoSolitario();
        });
      } else if (savedMode == 'ruta') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_state.modoRutas) _activarModoRutas();
        });
      }
    }
  }

  void _onErrorCheck() {
    if (!mounted) return;
    if (_state.errorMessage != null) {
      _mostrarError(_state.errorMessage!);
      _state.clearError();
    }
  }

  void _recalcularPorcentajesBarrios() {
    if (!_state.modoSolitario || _barriosCercanos.isEmpty) return;
    _barrioPctDebounce?.cancel();
    _barrioPctDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final misTers = _state.territorios.where((t) => t.esMio).toList();
      bool changed = false;
      for (final barrio in _barriosCercanos) {
        double areaCubierta = 0.0;
        for (final ter in misTers) {
          if (_territorioEnBarrio(ter, barrio.puntos)) {
            areaCubierta += TerritoryService.calcularAreaM2(ter.puntos);
          }
        }
        final newPct = (areaCubierta / barrio.areaM2).clamp(0.0, 1.0);
        if ((newPct - barrio.porcentajeCubierto).abs() > 0.001) {
          barrio.porcentajeCubierto = newPct;
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _state.removeListener(_onErrorCheck);
    _state.removeListener(_recalcularPorcentajesBarrios);
    _state.removeListener(_onStateChangedForCiudad);
    _state.removeListener(_onStateChangedForSolitario);
    _state.removeListener(_onStateChangedForGlobal);
    _ciudadCamDebounce?.cancel();
    _streamTerritoriDebounce?.cancel();
    _barrioPctDebounce?.cancel();
    _mapboxCiudadMap  = null;
    _ciudadAnnManager = null;
    _mapboxSolMap     = null;
    _mapboxRutasMap   = null;
    _mapboxGlobalMap  = null;
    _state.dispose();
    _pulseCtrl.dispose();
    _selCtrl.dispose();
    _sheetEntryCtrl.dispose();
    _toggleCtrl.dispose();
    _globalEntryCtrl.dispose();
    _presenciaStream?.cancel();
    _desafioStreamRetador?.cancel();
    _desafioStreamRetado?.cancel();
    _competitiveStreamSub?.cancel();
    _solitarioStreamSub?.cancel();
    TerritoryService.stopRealtimeListener();
    _cameraDebounce?.cancel();
    _solCamDebounce?.cancel();
    _sheetCtrl.dispose();
    _barriosSearchCtrl.dispose();
    super.dispose();
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: _kWarn, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(mensaje, style: _raj(12, FontWeight.w600, _kWhite))),
      ]),
      backgroundColor: _kSurface,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: _kWarn, width: 1),
      ),
      duration: const Duration(seconds: 3),
    ));
  }

  void _mostrarExito(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: _kSafe, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(mensaje, style: _raj(12, FontWeight.w600, _kWhite))),
      ]),
      backgroundColor: _kSurface,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: _kSafe, width: 1),
      ),
      duration: const Duration(seconds: 3),
    ));
  }

  void _suscribirStreamTerritorios() {
    _competitiveStreamSub = TerritoryService.competitiveStream.listen((list) {
      if (!mounted) return;
      GameStateService.instance.setCompetitiveTerritories(list);
      if (_state.modoSolitario || _state.modoRutas || _state.modoGlobal) return;
      // Debounce: evita redraws múltiples cuando Firestore emite ráfagas
      // (p.ej. creación de territorios fantasma uno a uno)
      _streamTerritoriDebounce?.cancel();
      _streamTerritoriDebounce = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        if (_state.modoSolitario || _state.modoRutas || _state.modoGlobal) return;
        _state.setTerritorios(list);
      });
    });
    _solitarioStreamSub = TerritoryService.solitarioStream.listen((list) {
      if (!mounted) return;
      // Siempre actualizar caché para que el retorno a solitario sea inmediato
      GameStateService.instance.setSolitarioTerritories(list);
      if (!_state.modoSolitario) return;
      _state.setTerritorios(list);
    });
  }

  Future<void> _initData() async {
    _centroListo = _resolverCentro();
    // Cargar color del jugador en paralelo con el GPS
    final colorFuture = _cargarColorJugador();
    await _centroListo;
    await colorFuture;
    // Arrancar listener en tiempo real y suscribirse a los streams
    TerritoryService.startRealtimeListener(centro: _state.centro);
    _suscribirStreamTerritorios();
    // Listeners arrancan en cuanto tenemos el centro — no esperan a los territorios
    _escucharJugadores();
    _escucharDesafio();
    await _cargarTerritorios();
    await _rellenarConFantasmas();
    if (!mounted) return;
    _sheetEntryCtrl.forward();
  }

  Future<void> _cargarColorJugador() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players').doc(uid).get();
      final colorInt = (doc.data()?['territorio_color'] as num?)?.toInt();
      if (colorInt != null) _state.colorJugador = Color(colorInt);
    } catch (_) {}
  }

  Future<void> _resolverCentro() async {
    if (widget.centroInicial != null) {
      _state.setCentro(widget.centroInicial!);
      _gpsResuelto = true;
      return;
    }
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        try {
          final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));
          _state.setCentro(LatLng(pos.latitude, pos.longitude));
          _gpsResuelto = true;
          return;
        } catch (_) {}
        // Fallback: última posición conocida si getCurrentPosition falla
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          _state.setCentro(LatLng(last.latitude, last.longitude));
          _gpsResuelto = true;
        }
      }
    } catch (e) {
      debugPrint('FullscreenMap resolverCentro error: $e');
    }
  }

  Future<void> _cargarTerritorios() async {
    if (widget.territorios.isNotEmpty) {
      _state.setTerritorios(widget.territorios);
      return;
    }
    // Pre-leer el modo guardado evita la race condition entre _initData()
    // (que corre sin await) y _activarModoSolitario() (postFrameCallback).
    final savedMode = GameStateService.instance.currentMode;
    final modo = (_state.modoSolitario || savedMode == 'solitario') ? 'solitario' : 'competitivo';

    // 1. Caché válida → mostrar al instante
    final cached = modo == 'solitario'
        ? GameStateService.instance.getSolitarioTerritories()
        : GameStateService.instance.getCompetitiveTerritories();
    if (cached != null) {
      _state.setTerritorios(List<TerritoryData>.from(cached));
      return;
    }

    // 2. Caché expirada pero con datos → mostrar inmediatamente y refrescar en background
    final stale = modo == 'solitario'
        ? GameStateService.instance.getStaleSolitarioTerritories()
        : GameStateService.instance.getStaleCompetitiveTerritories();
    if (stale != null) {
      _state.setTerritorios(List<TerritoryData>.from(stale));
      _recargarSilencioso(modo);
      return;
    }

    // 3. Sin datos — mostrar spinner y esperar Firestore
    _state.setLoadingTerritorios(true);
    try {
      final lista = await TerritoryService.cargarTodosLosTerritorios(
          centro: _state.centro, modo: modo);
      if (!mounted) return;
      // Si el modo cambió mientras esperábamos, guardamos en caché pero no
      // actualizamos la UI (ya habrá otra carga en curso para el modo actual).
      final modoActual = _state.modoSolitario ? 'solitario' : 'competitivo';
      if (modoActual != modo) {
        if (modo == 'solitario') {
          GameStateService.instance.setSolitarioTerritories(lista);
        } else {
          GameStateService.instance.setCompetitiveTerritories(lista);
        }
        if (mounted) _state.setLoadingTerritorios(false);
        return;
      }
      _state.setTerritorios(lista);
      if (modo == 'solitario') {
        GameStateService.instance.setSolitarioTerritories(lista);
      } else {
        GameStateService.instance.setCompetitiveTerritories(lista);
      }
    } catch (e) {
      debugPrint('FullscreenMap cargarTerritorios error: $e');
      _state.setError('No se pudieron cargar los territorios');
    }
  }

  Future<void> _recargarSilencioso(String modo) async {
    if (_recargandoSilencioso) return;
    _recargandoSilencioso = true;
    try {
      final lista = await TerritoryService.cargarTodosLosTerritorios(
          centro: _state.centro, modo: modo);
      if (!mounted) return;
      final modoActual = _state.modoSolitario ? 'solitario' : 'competitivo';
      if (modoActual != modo) return;
      _state.setTerritorios(lista);
      if (modo == 'solitario') {
        GameStateService.instance.setSolitarioTerritories(lista);
      } else {
        GameStateService.instance.setCompetitiveTerritories(lista);
      }
    } catch (e) {
      debugPrint('FullscreenMap recargarSilencioso: $e');
    } finally {
      _recargandoSilencioso = false;
    }
  }

  Future<void> _refrescarTerritorios() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    TerritoryService.invalidarCache();
    GameStateService.instance.invalidateTerritories();
    _MapState.invalidarDetallesCache();
    await _cargarTerritorios();
    await _rellenarConFantasmas();
    if (mounted) setState(() => _refreshing = false);
  }




  Future<void> _rellenarConFantasmas() async {
    if (_state.modoSolitario) return;
    if (widget.territorios.isNotEmpty) return;
    if (!_gpsResuelto) return;
    final centro = _state.centro;
    final actuales = List<TerritoryData>.from(_state.territorios);
    await TerritoryService.crearTerritoriosFantasmaEnZona(
      centro: centro,
      todosExistentes: actuales,
    );
    // Load ghosts directly and merge — avoids Firestore eventual-consistency race
    final fantasmas = await TerritoryService.cargarTerritoriosFantasmaCercanos(
      centro: centro,
    );
    if (!mounted) return;
    final sinFantasmas = actuales.where((t) => !t.esFantasma).toList();
    _state.setTerritorios([...sinFantasmas, ...fantasmas]);
  }

  void _escucharJugadores() {
    const double radioGrados = 0.09;
    final latMin = _state.centro.latitude  - radioGrados;
    final latMax = _state.centro.latitude  + radioGrados;
    final lngMin = _state.centro.longitude - radioGrados;
    final lngMax = _state.centro.longitude + radioGrados;
    _presenciaStream = FirebaseFirestore.instance
        .collection('presencia_activa')
        .where('lat', isGreaterThan: latMin)
        .where('lat', isLessThan: latMax)
        .limit(100)
        .snapshots()
        .listen((snap) {
      final nuevos = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        if (doc.id == _uid) continue;
        final d = doc.data();
        final lng = (d['lng'] as num?)?.toDouble();
        if (lng == null || lng < lngMin || lng > lngMax) continue;
        final ts = d['timestamp'] as Timestamp?;
        if (ts != null && DateTime.now().difference(ts.toDate()).inMinutes < 5) {
          nuevos[doc.id] = d;
        }
      }
      _state.setJugadores(nuevos);
    });
  }

  void _escucharDesafio() {
    final uid = _uid;
    if (uid == null) return;

    final db = FirebaseFirestore.instance;

    // Query 1: el usuario es el retador
    _desafioStreamRetador = db
        .collection('desafios')
        .where('retadorId', isEqualTo: uid)
        .where('estado', isEqualTo: 'activo')
        .limit(1)
        .snapshots()
        .listen((snap) {
      _desafioComoRetador = snap.docs.isEmpty ? null : snap.docs.first.data();
      _mergeDesafio();
    });

    // Query 2: el usuario es el retado
    _desafioStreamRetado = db
        .collection('desafios')
        .where('retadoId', isEqualTo: uid)
        .where('estado', isEqualTo: 'activo')
        .limit(1)
        .snapshots()
        .listen((snap) {
      _desafioComoRetado = snap.docs.isEmpty ? null : snap.docs.first.data();
      _mergeDesafio();
    });
  }

  // Prioriza el rol de retador; si no hay, usa el de retado.
  void _mergeDesafio() {
    _state.setDesafio(_desafioComoRetador ?? _desafioComoRetado);
  }

  void _toggleModo() {
    HapticFeedback.mediumImpact();
    _state.toggleModoGlobal();
    if (_state.modoGlobal) {
      _toggleCtrl.forward();
      _globalEntryCtrl.forward(from: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_sheetCtrl.isAttached) {
          _sheetCtrl.animateTo(0.35,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut);
        }
        _moverCamara(_kGlobalCenter, 2.5);
      });
    } else {
      _toggleCtrl.reverse();
      _moverCamara(_state.centro, 13.0);
    }
  }

  void _onTerritoryTap(TerritoryData t) {
    HapticFeedback.lightImpact();
    _state.seleccionarTerritorio(t);
    _selCtrl.forward(from: 0);
    _moverCamara(t.centro, 15);
  }

  void _onGlobalTerritoryTap(GlobalTerritory t) {
    HapticFeedback.lightImpact();
    _state.seleccionarTerritoryGlobal(t);
    _selCtrl.forward(from: 0);
    _moverCamara(t.center, 5);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sheetCtrl.isAttached) {
        _sheetCtrl.animateTo(0.08,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut);
      }
    });
  }

  void _cerrarSeleccion() {
    _selCtrl.reverse();
    Future.delayed(const Duration(milliseconds: 280), () {
      _state.seleccionarTerritorio(null);
      _state.seleccionarTerritoryGlobal(null);
    });
  }

  void _toggleSheet() {
    HapticFeedback.selectionClick();
    if (_sheetEntryCtrl.value > 0.5) {
      if (_sheetCtrl.isAttached) {
        _sheetCtrl.animateTo(0.0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInCubic);
      }
      _sheetEntryCtrl.reverse();
    } else {
      _sheetEntryCtrl.forward();
      Future.delayed(const Duration(milliseconds: 160), () {
        if (_sheetCtrl.isAttached) {
          _sheetCtrl.animateTo(0.4,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic);
        }
      });
    }
  }

  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersections = 0;
    final int n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final double xi = polygon[i].longitude, yi = polygon[i].latitude;
      final double xj = polygon[j].longitude, yj = polygon[j].latitude;
      final bool cruza = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
      if (cruza) intersections++;
    }
    return intersections % 2 == 1;
  }

  Future<void> _intentarConquistarGlobal(GlobalTerritory t) async {
    final uid = _uid;
    if (uid == null) return;

    if (_state.territoriosMios >= _MapState.maxTerritoriosPorJugador && !t.isMine) {
      _mostrarDialogoLimiteAlcanzado();
      return;
    }

    if (t.isMine) {
      _mostrarError('Ya eres el dueño de este territorio');
      return;
    }

    if (!mounted) return;
    _mostrarDialogoConquistaGlobal(t);
  }

  void _mostrarDialogoLimiteAlcanzado() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border.all(color: _kBorder2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 3,
                decoration: BoxDecoration(color: _kBorder2,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: _kWarn.withValues(alpha: 0.1), shape: BoxShape.circle,
                border: Border.all(color: _kWarn.withValues(alpha: 0.4))),
              child: const Icon(Icons.lock_rounded, color: _kWarn, size: 26)),
            const SizedBox(height: 16),
            Text('LÍMITE ALCANZADO',
                style: _cinzel(16, FontWeight.w900, _kWarn, spacing: 2)),
            const SizedBox(height: 8),
            Text(
              'Ya controlas ${_MapState.maxTerritoriosPorJugador} territorios, '
              'el máximo permitido.\n\nDefiende los que tienes o pierde alguno '
              'para poder conquistar uno nuevo.',
              textAlign: TextAlign.center,
              style: _raj(12, FontWeight.w500, _kSub, height: 1.6),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _kWarn.withValues(alpha: 0.1),
                  border: Border.all(color: _kWarn.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Text('ENTENDIDO',
                    style: _raj(13, FontWeight.w900, _kWarn, spacing: 2))),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  /// Diálogo de conquista — muestra clausulaKm real (via t.kmRequired)
  void _mostrarDialogoConquistaGlobal(GlobalTerritory t) {
    // kmRequired ya devuelve clausulaKm directamente
    final kmReq = t.kmRequired;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border.all(color: t.tierColor.withValues(alpha: 0.4)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 16),
            width: 36, height: 3,
            decoration: BoxDecoration(color: _kBorder2,
                borderRadius: BorderRadius.circular(2))),

          Container(
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.tierColor.withValues(alpha: 0.08), Colors.transparent],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              border: Border.all(color: t.tierColor.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Text(t.icon, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 14),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.tierColor.withValues(alpha: 0.12),
                    border: Border.all(color: t.tierColor.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(t.tierLabel,
                      style: _raj(8, FontWeight.w900, t.tierColor, spacing: 1.5)),
                ),
                const SizedBox(height: 6),
                Text(t.epicName,
                    style: _cinzel(13, FontWeight.w700, _kWhite, spacing: 0.5)),
                const SizedBox(height: 2),
                Text(t.inspiration, style: _raj(10, FontWeight.w500, _kSub)),
              ])),
            ]),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(children: [
              _globalStatCard('DIFICULTAD', '${t.difficultyLevel}/10',
                  _dificultadColor(t.difficultyLevel),
                  Icons.whatshot_rounded),
              const SizedBox(width: 10),
              // ── clausulaKm real ──────────────────────────────────────────
              _globalStatCard(
                'KM NECESARIOS',
                '${kmReq.toStringAsFixed(1)} km',
                _kCyan,
                Icons.directions_run_rounded,
                sub: t.conquestCount > 0 ? '×1.15 por conquista' : null,
              ),
              const SizedBox(width: 10),
              _globalStatCard('RECOMPENSA', '+${t.rewardActual}',
                  _kGold, Icons.monetization_on_rounded),
            ]),
          ),

          const SizedBox(height: 12),

          if (t.isOwned && !t.isMine)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: _kRed.withValues(alpha: 0.04),
                  border: Border.all(color: _kBorder2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(children: [
                  Container(
                    width: 3, height: 38,
                    decoration: const BoxDecoration(
                      color: _kRed,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(4),
                        bottomLeft: Radius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.shield_rounded, color: _kRed, size: 14),
                  const SizedBox(width: 8),
                  Text('Controlado por ',
                      style: _raj(11, FontWeight.w500, _kSub)),
                  Text(t.ownerNickname!.toUpperCase(),
                      style: _raj(11, FontWeight.w900, _kWhite)),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Text('INVADIR',
                        style: _raj(10, FontWeight.w900, _kRed)),
                  ),
                ]),
              ),
            ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kSurface2,
                border: Border.all(color: _kBorder2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded,
                    color: _kGold, size: 16),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Sal a correr ${kmReq.toStringAsFixed(1)} km en cualquier '
                  'dirección desde tu ciudad. Al finalizar la carrera el '
                  'territorio será tuyo automáticamente.',
                  style: _raj(11, FontWeight.w500, _kText, height: 1.5),
                )),
              ]),
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: GestureDetector(
              onTap: () {
                final objetivo = {
                  'territorioId':    t.id,
                  'territorioNombre': t.epicName,
                  'kmRequeridos':    t.kmRequired,
                  'recompensa':      t.rewardActual,
                  'ownerUid':        t.ownerUid,      // ← bug fix: incluir ownerUid
                };
                Navigator.of(context).pop(); // cierra el bottom sheet
                if (widget.selectionMode) {
                  // Devolver el territorio seleccionado a quien llamó (LiveActivity)
                  Navigator.of(context).pop(objetivo);
                } else {
                  Navigator.pushNamed(context, '/correr',
                      arguments: {'objetivoGlobal': objetivo});
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      t.tierColor.withValues(alpha: 0.3),
                      t.tierColor.withValues(alpha: 0.15)
                    ],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: t.tierColor.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(color: t.tierColor.withValues(alpha: 0.2),
                        blurRadius: 20),
                  ],
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(t.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Text(
                    'CONQUISTAR · ${kmReq.toStringAsFixed(1)} KM',
                    style: _cinzel(14, FontWeight.w900, t.tierColor,
                        spacing: 1.5),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Color _dificultadColor(int level) {
    if (level <= 3) return _kSafe;
    if (level <= 6) return _kWarn;
    return _kRed;
  }

  /// Stat card con subtexto opcional
  Widget _globalStatCard(
    String label,
    String value,
    Color color,
    IconData icon, {
    String? sub,
  }) =>
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 6),
          Text(value,
              style: _raj(13, FontWeight.w900, color),
              textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(label,
              style: _raj(7, FontWeight.w700, _kSub, spacing: 0.5),
              textAlign: TextAlign.center),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub,
                style: _raj(6, FontWeight.w600, color.withValues(alpha: 0.55)),
                textAlign: TextAlign.center),
          ],
        ]),
      ));

  Future<void> _ejecutarConquista(_TerDet det, String ownerNick) async {
    Position? pos;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        pos = await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.high));
      }
    } catch (_) {}

    if (pos == null) {
      _mostrarError('No se pudo obtener tu ubicación.');
      return;
    }
    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoConfirmarConquista(
          ownerNick: ownerNick,
          diasSinVisitar: det.diasSinVisitar ?? 0),
    );
    if (confirmar != true) return;
    if (!mounted) return;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _DialogoConquistando());
    try {
      await TerritoryService.conquistarTerritorio(
        docId: det.docId, duenoAnteriorId: det.ownerId,
        latUsuario: pos.latitude, lngUsuario: pos.longitude,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _mostrarExito('¡Territorio conquistado!');
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop();
      await _refrescarTerritorios();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _mostrarError(e.message ?? 'No puedes conquistar este territorio');
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _mostrarError('Error inesperado. Inténtalo de nuevo.');
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

        Positioned.fill(
          child: ListenableBuilder(
            listenable: _state,
            builder: (_, __) => _buildMapa(),
          ),
        ),

        Positioned(
          top: 0, left: 0, right: 0,
          child: ListenableBuilder(
            listenable: _state,
            builder: (_, __) {
              final mios = _state.territorios.where((t) => t.esMio).length;
              final det  = _state.territorios
                  .where((t) => t.esMio && t.estaDeterirado).length;
              final pel  = _state.territorios
                  .where((t) => t.esMio && t.esConquistableSinPasar).length;
              return _buildFloatingBar(mios, det, pel);
            },
          ),
        ),

        SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(0, 1), end: Offset.zero)
              .animate(_sheetEntryAnim),
          child: ListenableBuilder(
            listenable: _state,
            builder: (_, __) {
              final isGlobal = _state.modoGlobal;
              return DraggableScrollableSheet(
                key: ValueKey('${_state.modoGlobal}_${_state.modoSolitario}_${_state.modoRutas}'),
                controller: _sheetCtrl,
                initialChildSize: 0.13,
                minChildSize: 0.08,
                maxChildSize: 0.70,
                snap: true,
                snapSizes: const [0.08, 0.13, 0.70],
                builder: (ctx, scrollCtrl) {
                  final mios = _state.territorios
                      .where((t) => t.esMio).length;
                  final det  = _state.territorios
                      .where((t) => t.esMio && t.estaDeterirado).length;
                  final pel  = _state.territorios
                      .where((t) => t.esMio && t.esConquistableSinPasar)
                      .length;
                  return isGlobal
                      ? _buildSheetGlobal(scrollCtrl)
                      : _state.modoSolitario
                          ? _buildSheetSolitario(scrollCtrl)
                          : _state.modoRutas
                              ? _buildSheetRutas(scrollCtrl)
                              : _buildSheet(scrollCtrl, mios, det, pel);
                },
              );
            },
          ),
        ),

        ListenableBuilder(
          listenable: _state,
          builder: (_, __) {
            final screenH = MediaQuery.of(context).size.height;
            if (_state.modoGlobal) {
              if (_state.territorioGlobalSeleccionado == null) {
                return const SizedBox.shrink();
              }
              return Positioned(
                bottom: screenH * 0.14 + 12, left: 16, right: 16,
                child: _buildGlobalTerritoryCard(
                    _state.territorioGlobalSeleccionado!),
              );
            } else {
              if (_state.territorioSeleccionado == null) {
                return const SizedBox.shrink();
              }
              return Positioned(
                bottom: screenH * 0.14 + 12, left: 16, right: 16,
                child: _buildTerritoryCard(_state.territorioSeleccionado!),
              );
            }
          },
        ),

        // "SIN TERRITORIOS" se muestra en el sheet, no como overlay sobre el mapa

        ListenableBuilder(
          listenable: _state,
          builder: (_, __) {
            final screenH = MediaQuery.of(context).size.height;
            final hasCard = _state.modoGlobal
                ? _state.territorioGlobalSeleccionado != null
                : _state.territorioSeleccionado != null;
            return Positioned(
              right: 16,
              bottom: screenH * 0.14 + (hasCard ? 160 : 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildToggleMapa(),
                  const SizedBox(height: 8),
                  _buildFab(),
                ],
              ),
            );
          },
        ),
      ]),
      bottomNavigationBar: AppShell.isActive(context) ? null : const CustomBottomNavbar(currentIndex: 2),
    );
  }

  // ==========================================================================
  // FLOATING BAR
  // ==========================================================================
  Widget _buildFloatingBar(int mios, int det, int pel) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(children: [
          Row(children: [
            GestureDetector(
              onTap: _toggleSheet,
              child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                    color: _kBg.withValues(alpha: 0.72),
                    border: Border.all(color: _kBorder2),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 20)
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedBuilder(
                      animation: _toggleCtrl,
                      builder: (_, __) => Container(
                        width: 2, height: 18,
                        color: Color.lerp(
                            _kRed, _kGold, _toggleAnim.value),
                        margin: const EdgeInsets.only(right: 10),
                      ),
                    ),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      ListenableBuilder(
                        listenable: Listenable.merge([_toggleCtrl, _state]),
                        builder: (_, __) => Text(
                          _state.modoGlobal
                              ? 'MAPA GLOBAL'
                              : _state.modoSolitario
                              ? 'MAPA SOLITARIO'
                              : _state.modoRutas
                              ? 'MAPA RUTAS'
                              : 'MAPA COMPETITIVO',
                          style: _raj(13, FontWeight.w900, _kWhite,
                              spacing: 2),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) => Row(children: [
                          Container(
                            width: 5, height: 5,
                            decoration: BoxDecoration(
                              color: (_state.modoGlobal
                                      ? _kGold
                                      : _kSafe)
                                  .withValues(alpha: 0.4 + 0.6 * _pulse.value),
                              shape: BoxShape.circle,
                            ),
                            margin: const EdgeInsets.only(right: 5),
                          ),
                          Text(
                            _state.modoGlobal
                                ? '${_state.totalJugadoresGlobal} GUERREROS · '
                                  '${_state.territoriosGlobales.length} TERRITORIOS'
                                : _state.modoRutas
                                ? '${_misRutas.length} ${_misRutas.length == 1 ? 'RUTA' : 'RUTAS'}'
                                : '${_state.jugadoresEnVivo.length} EN VIVO · '
                                  '${_state.territorios.length} ZONAS',
                            style: _raj(8, FontWeight.w700, _kSub,
                                spacing: 1.5),
                          ),
                        ]),
                      ),
                    ]),
                  ]),
                ),
              ),
            ),
            ), // GestureDetector

            const Spacer(),

            if (!_state.modoGlobal && !_state.modoSolitario && !_state.modoRutas && (det > 0 || pel > 0)) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _kBg.withValues(alpha: 0.72),
                      border: Border.all(
                          color: (pel > 0 ? _kRed : _kWarn)
                              .withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (pel > 0) ...[
                        const Icon(Icons.dangerous_rounded,
                            color: _kRed, size: 12),
                        const SizedBox(width: 4),
                        Text('$pel',
                            style: _raj(11, FontWeight.w900, _kRed)),
                        const SizedBox(width: 8),
                      ],
                      if (det > 0) ...[
                        const Icon(Icons.warning_amber_rounded,
                            color: _kWarn, size: 12),
                        const SizedBox(width: 4),
                        Text('$det',
                            style: _raj(11, FontWeight.w900, _kWarn)),
                      ],
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],

            if (_state.modoGlobal &&
                _state.diasRestantesSemana > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _kBg.withValues(alpha: 0.72),
                      border: Border.all(
                          color: _kGold.withValues(alpha: 0.35)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.timer_rounded,
                          color: _kGold, size: 12),
                      const SizedBox(width: 5),
                      Text('${_state.diasRestantesSemana}d',
                          style: _raj(11, FontWeight.w900, _kGold)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],

            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _refrescarTerritorios();
                  },
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: _kBg.withValues(alpha: 0.72),
                      border: Border.all(color: _kBorder2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: _refreshing
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: _kText))
                        : const Icon(Icons.refresh_rounded,
                            color: _kText, size: 16),
                  ),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 10),
          _buildModeToggle(),
        ]),
      ),
    );
  }

  Widget _buildModeToggle() {
    final isCiudad    = !_state.modoGlobal && !_state.modoSolitario && !_state.modoRutas;
    final isSolitario = _state.modoSolitario;
    final isGlobal    = _state.modoGlobal;
    final isRutas     = _state.modoRutas;

    Widget pill({
      required String label,
      required IconData icon,
      required bool isActive,
      required Color color,
      required VoidCallback? onTap,
      Widget? extra,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.18) : _kBg.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? color.withValues(alpha: 0.6) : _kBorder2,
              width: 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 11, color: isActive ? color : _kSub),
            const SizedBox(width: 4),
            Text(label, style: _raj(9, FontWeight.w900,
                isActive ? color : _kSub, spacing: 0.8)),
            if (extra != null) ...[const SizedBox(width: 4), extra],
          ]),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _kBg.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(24),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              pill(
                label: 'COMPETITIVO',
                icon: Icons.location_on_rounded,
                isActive: isCiudad,
                color: _kBlue,
                onTap: isCiudad ? null : () async {
                  _state.setTerritorios([]);  // vaciar antes de cambiar modo
                  if (isGlobal) _toggleModo();
                  if (isSolitario) _state.setModoSolitario(false);
                  if (isRutas) _state.setModoRutas(false);
                  await WidgetsBinding.instance.endOfFrame;
                  await _cargarTerritorios();
                  _moverCamara(_state.centro, 13.0);
                },
              ),
              const SizedBox(width: 5),
              pill(
                label: 'SOLITARIO',
                icon: Icons.explore_rounded,
                isActive: isSolitario,
                color: _kSafe,
                onTap: isSolitario ? null : () async {
                  if (isGlobal) _toggleModo();
                  await _activarModoSolitario();
                },
              ),
              const SizedBox(width: 5),
              pill(
                label: 'RUTAS',
                icon: Icons.route_rounded,
                isActive: isRutas,
                color: const Color(0xFF9B72CF),
                onTap: isRutas ? null : () async {
                  if (isGlobal) _toggleModo();
                  if (isSolitario) _state.setModoSolitario(false);
                  await _activarModoRutas();
                },
              ),
              const SizedBox(width: 5),
              pill(
                label: 'GLOBAL',
                icon: Icons.public_rounded,
                isActive: isGlobal,
                color: _kGoldLight,
                onTap: isGlobal ? null : () {
                  if (isSolitario) _state.setModoSolitario(false);
                  if (isRutas) _state.setModoRutas(false);
                  _toggleModo();
                },
                extra: isGlobal && _state.territoriosMios > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: _kGold.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('${_state.territoriosMios}/5',
                            style: _raj(8, FontWeight.w900, _kGold)),
                      )
                    : null,
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // MODO SOLITARIO — barrios OSM
  // ==========================================================================
  Future<void> _activarModoSolitario() async {
    await _centroListo; // garantiza GPS real antes de consultar Overpass
    _state.setTerritorios([]);  // vaciar antes de cambiar modo → sin flash de datos del modo anterior
    _state.setModoSolitario(true);
    await WidgetsBinding.instance.endOfFrame;
    _moverCamara(_state.centro, _kInitialZoom);
    await _cargarTerritorios();
    _recalcularPorcentajesBarrios(); // recalcular con barrios ya en caché
    // Resetear si la carga anterior no encontró resultados
    if (_barriosCargados && _barriosCercanos.isEmpty) {
      setState(() { _barriosCargados = false; });
    }
    if (!_barriosCargados && !_cargandoBarrios) {
      await _cargarBarriosSolitario(_state.centro);
      _recalcularPorcentajesBarrios();
      _dibujarBarriosSolitario();
    }
  }

  Future<void> _cargarBarriosSolitario(LatLng pos) async {
    if (_cargandoBarrios) return;
    if (_barriosCargados && _barriosCercanos.isNotEmpty) return;
    _cargandoBarrios = true;
    _errorBarrios = null;
    if (mounted) setState(() {});  // muestra spinner de carga

    try {
      final lat   = pos.latitude;
      final lng   = pos.longitude;
      const delta = 0.12; // ~13 km — cubre toda el área metropolitana

      // Overpass bbox format: sur,oeste,norte,este
      final bbox = '${lat - delta},${lng - delta},${lat + delta},${lng + delta}';
      final query = '[out:json][timeout:40];'
          '('
          // Municipios (admin_level=8 en España) — los pueblos que componen la ciudad
          '  relation["boundary"="administrative"]["admin_level"="8"]($bbox);'
          // Distritos y barrios administrativos
          '  relation["boundary"="administrative"]["admin_level"~"^(9|10)\$"]($bbox);'
          // Barrios por etiqueta place
          '  relation["place"~"suburb|neighbourhood|quarter"]($bbox);'
          '  way["place"~"suburb|neighbourhood|quarter"]($bbox);'
          ');'
          'out geom;';
      final response = await http.post(
        Uri.https('overpass-api.de', '/api/interpreter'),
        body: {'data': query},
        headers: {
          'User-Agent': 'RiskRunner/1.0 (contact@riskrunner.app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        if (mounted) setState(() {
          _cargandoBarrios = false;
          _errorBarrios = 'Error ${response.statusCode} · OpenStreetMap';
        });
        return;
      }

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = (jsonData['elements'] as List<dynamic>? ?? []);
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
            return LatLng((m['lat'] as num).toDouble(),
                          (m['lon'] as num).toDouble());
          }).toList();
        } else if (el['type'] == 'relation') {
          final members = el['members'] as List<dynamic>? ?? [];
          final segs = <List<LatLng>>[];
          for (final member in members) {
            final m = member as Map<String, dynamic>;
            if (m['role'] == 'outer' && m['geometry'] != null) {
              final geom = m['geometry'] as List<dynamic>;
              final seg = geom.map((g) {
                final gm = g as Map<String, dynamic>;
                return LatLng((gm['lat'] as num).toDouble(),
                              (gm['lon'] as num).toDouble());
              }).toList();
              if (seg.length >= 2) segs.add(seg);
            }
          }
          puntos = _encadenarSegmentos(segs);
        }

        if (puntos.length < 4) continue;
        final area = TerritoryService.calcularAreaM2(puntos);
        if (area < 10000) continue;       // < 0.01 km² — artefacto
        if (area > 300000000) continue;   // > 300 km² — provincia/región

        // Calcular % cubierto con territorios propios
        final misTers = _state.territorios.where((t) => t.esMio).toList();
        double areaCubierta = 0.0;
        for (final ter in misTers) {
          if (_territorioEnBarrio(ter, puntos)) {
            areaCubierta += TerritoryService.calcularAreaM2(ter.puntos);
          }
        }
        final pct = (areaCubierta / area).clamp(0.0, 1.0);
        barrios.add(_BarrioData(nombre: nombre, puntos: puntos, areaM2: area,
            porcentajeCubierto: pct));
      }

      // Ordenar por distancia al centro
      barrios.sort((a, b) {
        final dA = Geolocator.distanceBetween(
            lat, lng, a.centro.latitude, a.centro.longitude);
        final dB = Geolocator.distanceBetween(
            lat, lng, b.centro.latitude, b.centro.longitude);
        return dA.compareTo(dB);
      });

      if (!mounted) {
        _cargandoBarrios = false;
        return;
      }
      setState(() {
        _barriosCercanos = barrios;
        _barriosCargados = true;
        _cargandoBarrios = false;
        _barriosCentro   = pos;
      });
    } catch (e) {
      final msg = e.toString().contains('TimeoutException')
          ? 'Tiempo agotado · Reintenta'
          : 'Sin conexión · Reintenta';
      if (mounted) {
        setState(() {
          _cargandoBarrios = false;
          _errorBarrios = msg;
        });
      } else {
        _cargandoBarrios = false;
      }
    }
  }

  // Encadena los segmentos outer de una relación OSM en un anillo continuo.
  // Conecta cada segmento al que comparte vértice (directo o invertido).
  List<LatLng> _encadenarSegmentos(List<List<LatLng>> segs) {
    if (segs.isEmpty) return [];
    if (segs.length == 1) return segs[0];

    final result  = List<LatLng>.from(segs[0]);
    final pending = segs.sublist(1).toList();

    while (pending.isNotEmpty) {
      final end = result.last;
      bool matched = false;
      for (int i = 0; i < pending.length; i++) {
        final s = pending[i];
        if (_cerca(s.first, end)) {
          result.addAll(s.skip(1));
          pending.removeAt(i);
          matched = true;
          break;
        }
        if (_cerca(s.last, end)) {
          result.addAll(s.reversed.skip(1));
          pending.removeAt(i);
          matched = true;
          break;
        }
      }
      if (!matched) {
        for (final s in pending) result.addAll(s);
        break;
      }
    }
    return result;
  }

  static bool _cerca(LatLng a, LatLng b) =>
      (a.latitude  - b.latitude).abs()  < 0.00005 &&
      (a.longitude - b.longitude).abs() < 0.00005;

  // ==========================================================================
  // MODO RUTAS
  // ==========================================================================
  Future<void> _activarModoRutas() async {
    _state.setModoRutas(true);
    await WidgetsBinding.instance.endOfFrame;
    _moverCamara(_state.centro, _kInitialZoom);
    await _cargarMisRutas();
  }

  Future<void> _cargarMisRutas() async {
    if (_cargandoRutas) return;
    // Si ya tenemos datos sólo redibujar (el mapa puede ser una nueva instancia)
    if (_misRutas.isNotEmpty) {
      await _dibujarRutas();
      return;
    }
    if (mounted) setState(() => _cargandoRutas = true);
    try {
      final rutas = await RouteService.cargarMisRutas();
      if (!mounted) return;
      setState(() {
        _misRutas      = rutas;
        _cargandoRutas = false;
      });
      await _dibujarRutas();
    } catch (e) {
      debugPrint('FullscreenMap rutas error: $e');
      if (mounted) setState(() => _cargandoRutas = false);
    }
  }

  /// Ray-casting para saber si un punto está dentro de un polígono.
  bool _puntoEnPoligonoSol(LatLng punto, List<LatLng> polygon) {
    int cruces = 0;
    final n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].longitude; final yi = polygon[i].latitude;
      final xj = polygon[j].longitude; final yj = polygon[j].latitude;
      if (((yi > punto.latitude) != (yj > punto.latitude)) &&
          (punto.longitude < (xj - xi) * (punto.latitude - yi) / (yj - yi) + xi)) {
        cruces++;
      }
    }
    return cruces.isOdd;
  }

  /// Devuelve true si el territorio solapa con el barrio:
  /// comprueba el centroide Y todos los vértices del territorio.
  /// Esto evita perder territorios cuyo centro cae justo fuera del borde del barrio.
  bool _territorioEnBarrio(TerritoryData ter, List<LatLng> barrioPuntos) {
    if (_puntoEnPoligonoSol(ter.centro, barrioPuntos)) return true;
    for (final v in ter.puntos) {
      if (_puntoEnPoligonoSol(v, barrioPuntos)) return true;
    }
    return false;
  }

  // ==========================================================================
  // BUILD MAPA — dispatcher
  // ==========================================================================
  void _invalidarCacheMapa() {
    _cachedMapaCiudad   = null;
    _cachedMapaSolitario = null;
    _cachedMapaRutas    = null;
    _cachedMapaGlobal   = null;
  }

  Widget _buildMapa() {
    final int idx = _state.modoGlobal    ? 3
        : _state.modoSolitario ? 1
        : _state.modoRutas     ? 2
        : 0;
    // Cachear cada widget de mapa para que Flutter reutilice el elemento
    // nativo (Metal/GL) en lugar de recrearlo en cada setState.
    // Se invalida solo al cambiar estilo (claro/oscuro).
    _cachedMapaCiudad    ??= _buildMapaCiudad(widget.mostrarRuta && widget.ruta.isNotEmpty);
    _cachedMapaSolitario ??= _buildMapaSolitario();
    _cachedMapaRutas     ??= _buildMapaRutas();
    _cachedMapaGlobal    ??= _buildMapaGlobal();
    return IndexedStack(
      index: idx,
      children: [
        _cachedMapaCiudad!,
        _cachedMapaSolitario!,
        _cachedMapaRutas!,
        _cachedMapaGlobal!,
      ],
    );
  }

  // ==========================================================================
  // CONSTANTES — layer IDs Mapbox
  // ==========================================================================
  static const String _cidSrc      = 'cid-territories-src';
  static const String _cidGlowLine = 'cid-glow-line';
  static const String _cidFill     = 'cid-fill';
  static const String _cidLine     = 'cid-line';
  static const String _cidLabel    = 'cid-label';
  static const String _cidRoute    = 'cid-route-line';
  static const String _cidRouteSrc = 'cid-route-src';

  static const String _solBarSrc   = 'sol-bar-src';
  static const String _solBarFill  = 'sol-bar-fill';
  static const String _solBarLine  = 'sol-bar-line';
  static const String _solBarLabel = 'sol-bar-label';
  static const String _solTerSrc   = 'sol-ter-src';
  static const String _solTerGlow  = 'sol-ter-glow';
  static const String _solTerFill  = 'sol-ter-fill';
  static const String _solTerLine  = 'sol-ter-line';

  static const String _rutSrc      = 'rut-src';
  static const String _rutLine     = 'rut-line';

  static const String _glbSrc      = 'glb-src';
  static const String _glbGlow     = 'glb-glow';
  static const String _glbFill     = 'glb-fill';
  static const String _glbLine     = 'glb-line';
  static const String _glbLabel    = 'glb-label';

  // ==========================================================================
  // HELPERS — GeoJSON
  // ==========================================================================
  static String _hexColor(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    final a = (c.a * 255).round();
    return 'rgba($r,$g,$b,${(a / 255).toStringAsFixed(3)})';
  }

  static String _toJson(dynamic o) => jsonEncode(o);

  // ==========================================================================
  // MODO CIUDAD — MAPBOX
  // ==========================================================================

  void _onStateChangedForCiudad() {
    if (_state.modoSolitario || _state.modoRutas || _state.modoGlobal) return;
    if (!_ciudadStyleLoaded) return;
    _dibujarTerritoriosCiudad();
    _actualizarJugadoresCiudad();
  }

  void _onCiudadMapCreated(mapbox.MapboxMap map) async {
    _mapboxCiudadMap = map;
    await map.style.setProjection(
        mapbox.StyleProjection(name: mapbox.StyleProjectionName.globe));
    await map.gestures.updateSettings(mapbox.GesturesSettings(
      rotateEnabled: false,
      pitchEnabled: false,
      scrollEnabled: true,
      pinchToZoomEnabled: true,
      doubleTapToZoomInEnabled: true,
      doubleTouchToZoomOutEnabled: true,
    ));
    await map.location.updateSettings(mapbox.LocationComponentSettings(
      enabled: true,
      puckBearingEnabled: false,
      locationPuck: mapbox.LocationPuck(
          locationPuck2D: mapbox.DefaultLocationPuck2D()),
    ));
    _ciudadAnnManager = await map.annotations.createPointAnnotationManager();
  }

  void _onCiudadStyleLoaded(mapbox.StyleLoadedEventData _) async {
    _ciudadStyleLoaded    = true;
    _ciudadLayersCreated  = false;
    _ciudadLayersCreating = false;
    await _setupCiudadTerrain();
    await _dibujarTerritoriosCiudad();
    if (widget.mostrarRuta && widget.ruta.isNotEmpty) {
      await _setupCiudadRuta();
    }
    _actualizarJugadoresCiudad();
    await (_centroListo ?? Future.value());
    if (mounted) {
      _mapboxCiudadMap?.flyTo(
        mapbox.CameraOptions(center: mapbox.Point(coordinates: mapbox.Position(_state.centro.longitude, _state.centro.latitude)), zoom: 13.0),
        mapbox.MapAnimationOptions(duration: 400),
      );
    }
  }

  Future<void> _setupCiudadTerrain() async {
    final map = _mapboxCiudadMap;
    if (map == null) return;
    try {
      await map.style.addSource(mapbox.RasterDemSource(
          id: 'cid-dem', url: 'mapbox://mapbox.mapbox-terrain-dem-v1',
          tileSize: 512, maxzoom: 14.0));
      await map.style.setStyleTerrain(
          '{"source":"cid-dem","exaggeration":1.2}');
      await map.style.addLayer(mapbox.HillshadeLayer(
          id: 'cid-hillshade', sourceId: 'cid-dem',
          hillshadeIlluminationDirection: 335,
          hillshadeExaggeration: 0.35,
          hillshadeShadowColor: 0xFF101828,
          hillshadeHighlightColor: 0xFFFFFFFF));
    } catch (_) {}

    try {
      try { await map.style.removeStyleLayer('cid-buildings'); } catch (_) {}
      await map.style.addLayer(mapbox.FillExtrusionLayer(
          id: 'cid-buildings', sourceId: 'composite', sourceLayer: 'building'));
      await map.style.setStyleLayerProperty(
          'cid-buildings', 'filter', ['==', ['get', 'extrude'], 'true']);
      await map.style.setStyleLayerProperty(
          'cid-buildings', 'fill-extrusion-base',
          ['interpolate', ['linear'], ['zoom'], 15, 0, 15.05, ['get', 'min_height']]);
      await map.style.setStyleLayerProperty(
          'cid-buildings', 'fill-extrusion-height',
          ['interpolate', ['linear'], ['zoom'], 15, 0, 15.05, ['get', 'height']]);
      final night = _mapaOscuro;
      final List<Object> bColors = night
          ? ['interpolate', ['linear'], ['get', 'height'],
              0, '#9C8060', 8, '#B09070', 25, '#C4A878', 60, '#D4B880', 120, '#C09858']
          : ['interpolate', ['linear'], ['get', 'height'],
              0, '#F2EAD6', 8, '#E8D4A8', 25, '#D4B878', 60, '#B89048', 120, '#906830'];
      await map.style.setStyleLayerProperty(
          'cid-buildings', 'fill-extrusion-color', bColors);
      await map.style.setStyleLayerProperty(
          'cid-buildings', 'fill-extrusion-opacity', 0.90);
      await map.style.setStyleLayerProperty(
          'cid-buildings', 'fill-extrusion-ambient-occlusion-intensity', 0.25);
      await map.style.setStyleLayerProperty(
          'cid-buildings', 'fill-extrusion-ambient-occlusion-radius', 3.0);
    } catch (_) {}
  }

  Future<void> _dibujarTerritoriosCiudad() async {
    final map = _mapboxCiudadMap;
    if (map == null || !_ciudadStyleLoaded) return;
    final territorios = _filteredTerritorios(
      _state.territorios.where((t) => t.modo != 'solitario').toList(),
    );
    if (territorios.isEmpty) return;

    final features = territorios.map((t) {
      final decay      = _decayFactor(t);
      final tColor     = t.esMio ? _state.colorJugador : t.color;
      final sel        = _state.territorioSeleccionado?.docId == t.docId;
      final fillAlpha  = sel ? 0.50 : (t.esMio ? 0.30 * decay : 0.20);
      final lineAlpha  = t.esMio ? (0.90 * decay).clamp(0.0, 1.0) : 0.70;
      final glowAlpha  = t.esMio ? 0.10 * decay : 0.06;
      final lineWidth  = sel ? 3.5 : (t.esMio ? 2.5 : 1.8);
      final glowWidth  = sel ? 14.0 : (t.esMio ? 10.0 : 6.0);
      final label      = t.ownerNickname;
      final labelColor = t.esMio ? _kGoldLight : Colors.white;
      final coords     = t.puntos.map((p) => [p.longitude, p.latitude]).toList()
        ..add([t.puntos.first.longitude, t.puntos.first.latitude]);
      return {
        'type': 'Feature',
        'properties': {
          'fillColor':  _hexColor(tColor.withValues(alpha: fillAlpha)),
          'lineColor':  _hexColor(tColor.withValues(alpha: lineAlpha)),
          'glowColor':  _hexColor(tColor.withValues(alpha: glowAlpha)),
          'lineWidth':  lineWidth,
          'glowWidth':  glowWidth,
          'label':      label,
          'labelColor': _hexColor(labelColor),
        },
        'geometry': {'type': 'Polygon', 'coordinates': [coords]},
      };
    }).toList();

    final geojson = _toJson({'type': 'FeatureCollection', 'features': features});

    try {
      if (_ciudadLayersCreated) {
        await (await _mapboxCiudadMap!.style.getSource(_cidSrc)
            as mapbox.GeoJsonSource).updateGeoJSON(geojson);
        return;
      }
      if (_ciudadLayersCreating) return;
      _ciudadLayersCreating = true;

      await map.style.addSource(mapbox.GeoJsonSource(
          id: _cidSrc, data: geojson, tolerance: 0.5));

      await map.style.addLayer(mapbox.LineLayer(
        id: _cidGlowLine, sourceId: _cidSrc,
        lineColorExpression: ['get', 'glowColor'],
        lineWidthExpression: ['get', 'glowWidth'],
        lineBlur: 6.0,
      ));
      await map.style.addLayer(mapbox.FillLayer(
        id: _cidFill, sourceId: _cidSrc,
        fillColorExpression: ['get', 'fillColor'],
      ));
      await map.style.addLayer(mapbox.LineLayer(
        id: _cidLine, sourceId: _cidSrc,
        lineColorExpression: ['get', 'lineColor'],
        lineWidthExpression: ['get', 'lineWidth'],
      ));
      await map.style.addLayer(mapbox.SymbolLayer(
        id: _cidLabel, sourceId: _cidSrc,
        textFieldExpression: ['get', 'label'],
        textColorExpression: ['get', 'labelColor'],
        textSize: 9,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.5,
        textMaxWidth: 8,
        textAnchor: mapbox.TextAnchor.CENTER,
      ));

      _ciudadLayersCreated  = true;
      _ciudadLayersCreating = false;
    } catch (_) {
      _ciudadLayersCreating = false;
    }
  }

  Future<void> _setupCiudadRuta() async {
    final map = _mapboxCiudadMap;
    if (map == null || widget.ruta.isEmpty) return;
    try {
      final coords = widget.ruta.map((p) => [p.longitude, p.latitude]).toList();
      final geojson = _toJson({
        'type': 'Feature',
        'properties': {},
        'geometry': {'type': 'LineString', 'coordinates': coords},
      });
      final srcExists = await map.style.styleSourceExists(_cidRouteSrc);
      if (!srcExists) {
        await map.style.addSource(mapbox.GeoJsonSource(id: _cidRouteSrc, data: geojson));
        await map.style.addLayer(mapbox.LineLayer(
          id: _cidRoute, sourceId: _cidRouteSrc,
          lineColor: _kBlue.toARGB32(),
          lineWidth: 3.5,
          lineOpacity: 0.85,
        ));
      }
    } catch (_) {}
  }

  Future<void> _actualizarJugadoresCiudad() async {
    final mgr = _ciudadAnnManager;
    if (mgr == null) return;
    final jugadores = Map<String, Map<String, dynamic>>.from(_state.jugadoresEnVivo);

    final toAdd    = jugadores.keys.where((id) => !_ciudadJugMarkers.containsKey(id)).toList();
    final toRemove = _ciudadJugMarkers.keys.where((id) => !jugadores.containsKey(id)).toList();

    for (final id in toRemove) {
      final ann = _ciudadJugMarkers.remove(id);
      if (ann != null) await mgr.delete(ann);
    }

    for (final id in toAdd) {
      final d   = jugadores[id]!;
      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      try {
        final img = await _renderCirclePng();
        final ann = await mgr.create(mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
          image: img,
          iconSize: 0.6,
        ));
        _ciudadJugMarkers[id] = ann;
      } catch (_) {}
    }
  }

  Future<Uint8List> _renderCirclePng() async {
    const size = 32.0;
    final recorder = PictureRecorder();
    final canvas   = Canvas(recorder);
    final paint    = Paint()..color = _kBlue;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 2, paint);
    final picture = recorder.endRecording();
    final img     = await picture.toImage(size.toInt(), size.toInt());
    final bytes   = await img.toByteData(format: ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  void _onCiudadTap(mapbox.MapContentGestureContext ctx) {
    final tapLat = ctx.point.coordinates.lat.toDouble();
    final tapLng = ctx.point.coordinates.lng.toDouble();
    final tapLL  = LatLng(tapLat, tapLng);

    TerritoryData? encontrado;
    for (final t in _state.territorios) {
      if (_pointInPolygon(tapLL, t.puntos)) { encontrado = t; break; }
    }
    if (encontrado != null) {
      _onTerritoryTap(encontrado);
    } else if (_state.territorioSeleccionado != null) {
      _cerrarSeleccion();
    }
    _dibujarTerritoriosCiudad();
  }

  void _onCiudadCameraIdle(mapbox.MapContentGestureContext _) {
    _ciudadCamDebounce?.cancel();
    _ciudadCamDebounce = Timer(const Duration(milliseconds: 600), () async {
      final map = _mapboxCiudadMap;
      if (map == null || !mounted) return;
      final cam = await map.getCameraState();
      final newCenter = LatLng(
        cam.center.coordinates.lat.toDouble(),
        cam.center.coordinates.lng.toDouble(),
      );
      if (_ciudadLastCenter != null) {
        final distM = Geolocator.distanceBetween(
          _ciudadLastCenter!.latitude, _ciudadLastCenter!.longitude,
          newCenter.latitude, newCenter.longitude,
        );
        if (distM < 3000) return;
      }
      _ciudadLastCenter = newCenter;
      _state.setCentro(newCenter);
      TerritoryService.invalidarCache();
      TerritoryService.startRealtimeListener(centro: newCenter);
      final lista = await TerritoryService.cargarTodosLosTerritorios(
          centro: newCenter, modo: 'competitivo');
      // El usuario pudo cambiar de modo mientras esperábamos Firestore
      if (!mounted || _state.modoSolitario || _state.modoRutas || _state.modoGlobal) {
        GameStateService.instance.setCompetitiveTerritories(lista);
        return;
      }
      _state.setTerritorios(lista);
      GameStateService.instance.setCompetitiveTerritories(lista);
      await _rellenarConFantasmas();
      _dibujarTerritoriosCiudad();
    });
  }

  Widget _buildMapaCiudad(bool tieneRuta) {
    final styleUri = _mapaOscuro
        ? mapbox.MapboxStyles.DARK
        : 'mapbox://styles/mapbox/outdoors-v12';
    return Stack(children: [
      mapbox.MapWidget(
        key: const ValueKey('mapa_ciudad_mapbox'),
        styleUri: styleUri,
        cameraOptions: mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(
              _state.centro.longitude, _state.centro.latitude)),
          zoom: 13.0,
        ),
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
        },
        onMapCreated:          _onCiudadMapCreated,
        onStyleLoadedListener: _onCiudadStyleLoaded,
        onTapListener:         _onCiudadTap,
        onScrollListener:      _onCiudadCameraIdle,
      ),
      if (_state.loadingTerritorios)
        Positioned(
          top: 90, left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _kSurface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: _kSub),
                ),
                const SizedBox(width: 8),
                Text('Cargando territorios…',
                    style: _raj(10, FontWeight.w600, _kSub)),
              ]),
            ),
          ),
        ),
    ]);
  }

  // ==========================================================================
  // MODO RUTAS — MAPBOX lifecycle
  // ==========================================================================

  void _onRutasMapCreated(mapbox.MapboxMap map) async {
    _mapboxRutasMap = map;
    await map.style.setProjection(
        mapbox.StyleProjection(name: mapbox.StyleProjectionName.globe));
    await map.gestures.updateSettings(mapbox.GesturesSettings(
      rotateEnabled: false,
      pitchEnabled: false,
      scrollEnabled: true,
      pinchToZoomEnabled: true,
      doubleTapToZoomInEnabled: true,
      doubleTouchToZoomOutEnabled: true,
    ));
    await map.location.updateSettings(mapbox.LocationComponentSettings(
      enabled: true,
      puckBearingEnabled: false,
      locationPuck: mapbox.LocationPuck(
          locationPuck2D: mapbox.DefaultLocationPuck2D()),
    ));
  }

  void _onRutasStyleLoaded(mapbox.StyleLoadedEventData _) async {
    _rutasStyleLoaded   = true;
    _rutasLayersCreated = false;
    await _dibujarRutas();
    await (_centroListo ?? Future.value());
    if (mounted) {
      _mapboxRutasMap?.flyTo(
        mapbox.CameraOptions(center: mapbox.Point(coordinates: mapbox.Position(_state.centro.longitude, _state.centro.latitude)), zoom: _kInitialZoom),
        mapbox.MapAnimationOptions(duration: 400),
      );
    }
  }

  Future<void> _dibujarRutas() async {
    final map = _mapboxRutasMap;
    if (map == null || !_rutasStyleLoaded) return;
    final rutas = _misRutas;
    if (rutas.isEmpty) return;

    final selected = _rutaSeleccionada;
    final features = rutas.map((r) {
      final isSel = selected?.id == r.id;
      final color = isSel
          ? Color.lerp(_state.colorJugador, Colors.white, 0.25)!
          : _state.colorJugador;
      final width = isSel ? 5.0 : 3.0;
      final coords = r.coords.map((p) => [p.longitude, p.latitude]).toList();
      return {
        'type': 'Feature',
        'properties': {
          'routeId':   r.id,
          'lineColor': _hexColor(color),
          'lineWidth': width,
        },
        'geometry': {'type': 'LineString', 'coordinates': coords},
      };
    }).toList();

    final geojson = _toJson({'type': 'FeatureCollection', 'features': features});

    try {
      if (_rutasLayersCreated) {
        await (await map.style.getSource(_rutSrc)
            as mapbox.GeoJsonSource).updateGeoJSON(geojson);
        return;
      }

      await map.style.addSource(mapbox.GeoJsonSource(
          id: _rutSrc, data: geojson, tolerance: 0.5));
      await map.style.addLayer(mapbox.LineLayer(
        id: _rutLine, sourceId: _rutSrc,
        lineColorExpression: ['get', 'lineColor'],
        lineWidthExpression: ['get', 'lineWidth'],
        lineCap: mapbox.LineCap.ROUND,
        lineJoin: mapbox.LineJoin.ROUND,
      ));
      _rutasLayersCreated = true;
    } catch (_) {}
  }

  void _onRutasTap(mapbox.MapContentGestureContext ctx) {
    // Tap en modo rutas: buscar la ruta más cercana al punto pulsado
    final tapLat = ctx.point.coordinates.lat.toDouble();
    final tapLng = ctx.point.coordinates.lng.toDouble();
    final tapLL  = LatLng(tapLat, tapLng);
    RouteData? closest;
    double minDist = double.infinity;
    for (final r in _misRutas) {
      for (final p in r.coords) {
        final d = Geolocator.distanceBetween(
            tapLL.latitude, tapLL.longitude, p.latitude, p.longitude);
        if (d < minDist) { minDist = d; closest = r; }
      }
    }
    if (closest != null && minDist < 200) {
      setState(() => _rutaSeleccionada = closest);
      _dibujarRutas();
    }
  }

  // ==========================================================================
  // MODO SOLITARIO — MAPBOX
  // ==========================================================================

  void _onStateChangedForSolitario() {
    if (!_solStyleLoaded || !_state.modoSolitario) return;
    _dibujarBarriosSolitario();
    _dibujarTerritoriosSolitario();
  }

  void _onSolMapCreated(mapbox.MapboxMap map) async {
    _mapboxSolMap = map;
    await map.style.setProjection(
        mapbox.StyleProjection(name: mapbox.StyleProjectionName.globe));
    await map.gestures.updateSettings(mapbox.GesturesSettings(
      rotateEnabled: false,
      pitchEnabled: false,
      scrollEnabled: true,
      pinchToZoomEnabled: true,
      doubleTapToZoomInEnabled: true,
      doubleTouchToZoomOutEnabled: true,
    ));
    await map.location.updateSettings(mapbox.LocationComponentSettings(
      enabled: true,
      puckBearingEnabled: false,
      locationPuck: mapbox.LocationPuck(
          locationPuck2D: mapbox.DefaultLocationPuck2D()),
    ));
  }

  void _onSolStyleLoaded(mapbox.StyleLoadedEventData _) async {
    _solStyleLoaded    = true;
    _solLayersCreated  = false;
    _solLayersCreating = false;
    await _dibujarBarriosSolitario();
    await _dibujarTerritoriosSolitario();
    await (_centroListo ?? Future.value());
    if (mounted) {
      _mapboxSolMap?.flyTo(
        mapbox.CameraOptions(center: mapbox.Point(coordinates: mapbox.Position(_state.centro.longitude, _state.centro.latitude)), zoom: _kInitialZoom),
        mapbox.MapAnimationOptions(duration: 400),
      );
    }
  }

  Future<void> _dibujarBarriosSolitario() async {
    final map = _mapboxSolMap;
    if (map == null || !_solStyleLoaded) return;
    final barrios = _barriosCercanos;
    if (barrios.isEmpty) return;

    final features = barrios.map((b) {
      final pct   = b.porcentajeCubierto.clamp(0.0, 1.0);
      final color = pct > 0 ? _state.colorJugador : _kDim;
      final fillOpacity = pct > 0 ? (0.08 + 0.20 * pct) : 0.06;
      final coords = b.puntos.map((p) => [p.longitude, p.latitude]).toList()
        ..add([b.puntos.first.longitude, b.puntos.first.latitude]);
      return {
        'type': 'Feature',
        'properties': {
          'nombre': b.nombre,
          'pct': pct,
          'pctPct': '${(pct * 100).round()}%',
          'fillColor': _hexColor(color),
          'fillOpacity': fillOpacity,
          'lineColor': _hexColor(_mapaOscuro
              ? Colors.white.withValues(alpha: 0.45)
              : const Color(0xFF888888)),
        },
        'geometry': {'type': 'Polygon', 'coordinates': [coords]},
      };
    }).toList();

    final geojson = _toJson({'type': 'FeatureCollection', 'features': features});

    try {
      if (_solLayersCreated) {
        final src = await map.style.getSource(_solBarSrc) as mapbox.GeoJsonSource;
        await src.updateGeoJSON(geojson);
        return;
      }
      if (_solLayersCreating) return;
      _solLayersCreating = true;

      await map.style.addSource(mapbox.GeoJsonSource(
          id: _solBarSrc, data: geojson, tolerance: 0.5));

      await map.style.addLayer(mapbox.FillLayer(
        id: _solBarFill, sourceId: _solBarSrc,
        fillColorExpression: ['get', 'fillColor'],
        fillOpacityExpression: ['get', 'fillOpacity'],
      ));
      await map.style.addLayer(mapbox.LineLayer(
        id: _solBarLine, sourceId: _solBarSrc,
        lineColorExpression: ['get', 'lineColor'],
        lineWidth: 1.5,
      ));
      await map.style.addLayer(mapbox.SymbolLayer(
        id: _solBarLabel, sourceId: _solBarSrc,
        textFieldExpression: [
          'format',
          ['get', 'nombre'], {},
          '\n', {},
          ['get', 'pctPct'], {'text-color': ['get', 'fillColor']},
        ],
        textSize: 9,
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.5,
        textMaxWidth: 10,
        textAnchor: mapbox.TextAnchor.CENTER,
      ));

      _solLayersCreated  = true;
      _solLayersCreating = false;
    } catch (_) {
      _solLayersCreating = false;
    }
  }

  Future<void> _dibujarTerritoriosSolitario() async {
    final map = _mapboxSolMap;
    if (map == null || !_solStyleLoaded) return;
    final territorios = _filteredTerritorios(_state.territorios);
    final propios = territorios.where((t) => t.esMio && t.modo == 'solitario').toList();

    final features = propios.map((t) {
      final userColor = _state.colorJugador;
      final coords = t.puntos.map((p) => [p.longitude, p.latitude]).toList()
        ..add([t.puntos.first.longitude, t.puntos.first.latitude]);
      return {
        'type': 'Feature',
        'properties': {
          'fillColor':   _hexColor(userColor.withValues(alpha: 0.32)),
          'lineColor':   _hexColor(userColor.withValues(alpha: 0.90)),
          'glowColor':   _hexColor(userColor.withValues(alpha: 0.10)),
        },
        'geometry': {'type': 'Polygon', 'coordinates': [coords]},
      };
    }).toList();

    final geojson = _toJson({'type': 'FeatureCollection', 'features': features});

    try {
      final srcExists = await map.style.styleSourceExists(_solTerSrc);
      if (srcExists) {
        await (await map.style.getSource(_solTerSrc)
            as mapbox.GeoJsonSource).updateGeoJSON(geojson);
        return;
      }

      await map.style.addSource(mapbox.GeoJsonSource(
          id: _solTerSrc, data: geojson));
      await map.style.addLayer(mapbox.LineLayer(
        id: _solTerGlow, sourceId: _solTerSrc,
        lineColorExpression: ['get', 'glowColor'],
        lineWidth: 7.0, lineBlur: 4.0,
      ));
      await map.style.addLayer(mapbox.FillLayer(
        id: _solTerFill, sourceId: _solTerSrc,
        fillColorExpression: ['get', 'fillColor'],
      ));
      await map.style.addLayer(mapbox.LineLayer(
        id: _solTerLine, sourceId: _solTerSrc,
        lineColorExpression: ['get', 'lineColor'],
        lineWidth: 2.8,
      ));
    } catch (_) {}
  }

  void _onSolCameraIdle(mapbox.MapContentGestureContext _) {
    _solCamDebounce?.cancel();
    _solCamDebounce = Timer(const Duration(milliseconds: 700), () async {
      final map = _mapboxSolMap;
      if (map == null || !mounted) return;
      final cam = await map.getCameraState();
      final newCenter = LatLng(
        cam.center.coordinates.lat.toDouble(),
        cam.center.coordinates.lng.toDouble(),
      );
      if (_solLastCenter != null) {
        final distM = Geolocator.distanceBetween(
          _solLastCenter!.latitude, _solLastCenter!.longitude,
          newCenter.latitude, newCenter.longitude,
        );
        if (distM < 3000) return;
      }
      _solLastCenter = newCenter;
      _state.setCentro(newCenter);
      TerritoryService.invalidarCache();
      TerritoryService.startRealtimeListener(centro: newCenter);

      // Si el nuevo centro está >8 km del centro original de los barrios,
      // invalidar para que se recarguen los barrios de la nueva zona.
      if (_barriosCentro != null) {
        final distBarrios = Geolocator.distanceBetween(
          _barriosCentro!.latitude, _barriosCentro!.longitude,
          newCenter.latitude,       newCenter.longitude,
        );
        if (distBarrios > 8000) {
          setState(() {
            _barriosCargados = false;
            _barriosCercanos = [];
            _barriosCentro   = null;
          });
        }
      }

      final lista = await TerritoryService.cargarTodosLosTerritorios(
          centro: newCenter, modo: 'solitario');
      if (!mounted || !_state.modoSolitario) return;
      _state.setTerritorios(lista);
      GameStateService.instance.setSolitarioTerritories(lista);
      _recalcularPorcentajesBarrios();
      _dibujarTerritoriosSolitario();
      // Recargar barrios si fueron invalidados
      if (!_barriosCargados && !_cargandoBarrios) {
        await _cargarBarriosSolitario(newCenter);
        _recalcularPorcentajesBarrios();
        _dibujarBarriosSolitario();
      }
    });
  }

  void _moverCamara(LatLng centro, double zoom) {
    final mapbox.MapboxMap? target;
    if (_state.modoSolitario)        { target = _mapboxSolMap; }
    else if (_state.modoRutas)       { target = _mapboxRutasMap; }
    else if (_state.modoGlobal)      { target = _mapboxGlobalMap; }
    else                             { target = _mapboxCiudadMap; }
    if (target == null) return;

    final opts = mapbox.CameraOptions(
      center: mapbox.Point(
          coordinates: mapbox.Position(centro.longitude, centro.latitude)),
      zoom: zoom,
    );
    target.flyTo(opts, mapbox.MapAnimationOptions(duration: 500));
  }


  Widget _buildMapaSolitario() {
    final styleUri = _mapaOscuro
        ? mapbox.MapboxStyles.DARK
        : 'mapbox://styles/mapbox/outdoors-v12';
    return Stack(children: [
      mapbox.MapWidget(
        key: const ValueKey('mapa_solitario_mapbox'),
        styleUri: styleUri,
        cameraOptions: mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(
              _state.centro.longitude, _state.centro.latitude)),
          zoom: _kInitialZoom,
        ),
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
        },
        onMapCreated:          _onSolMapCreated,
        onStyleLoadedListener: _onSolStyleLoaded,
        onScrollListener:      _onSolCameraIdle,
      ),
      if (_state.loadingTerritorios || _cargandoBarrios)
        Positioned(
          top: 90, left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _kSurface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: _kSub),
                ),
                const SizedBox(width: 8),
                Text(
                  _state.loadingTerritorios
                      ? 'Cargando territorios…'
                      : 'Cargando barrios…',
                  style: _raj(10, FontWeight.w600, _kSub),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }


  // ==========================================================================
  // MAPA RUTAS
  // ==========================================================================
  Widget _buildMapaRutas() {
    final styleUri = _mapaOscuro
        ? mapbox.MapboxStyles.DARK
        : 'mapbox://styles/mapbox/outdoors-v12';
    return Stack(children: [
      mapbox.MapWidget(
        key: const ValueKey('mapa_rutas_mapbox'),
        styleUri: styleUri,
        cameraOptions: mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(
              _state.centro.longitude, _state.centro.latitude)),
          zoom: _kInitialZoom,
        ),
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
        },
        onMapCreated:          _onRutasMapCreated,
        onStyleLoadedListener: _onRutasStyleLoaded,
        onTapListener:         _onRutasTap,
      ),
      if (_cargandoRutas)
        Positioned(
          top: 90, left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _kSurface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: _kSub),
                ),
                const SizedBox(width: 8),
                Text('Cargando rutas…',
                    style: _raj(10, FontWeight.w600, _kSub)),
              ]),
            ),
          ),
        ),
    ]);
  }


  // ==========================================================================
  // MODO GLOBAL — MAPBOX
  // ==========================================================================

  void _onStateChangedForGlobal() {
    if (!_globalMbxStyleLoaded || !_state.modoGlobal) return;
    _dibujarTerritoriosGlobal();
  }

  void _onGlobalMapCreated(mapbox.MapboxMap map) async {
    _mapboxGlobalMap = map;
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
    ));
  }

  void _onGlobalStyleLoaded(mapbox.StyleLoadedEventData _) async {
    _globalMbxStyleLoaded    = true;
    _globalMbxLayersCreated  = false;
    _globalMbxLayersCreating = false;
    await _dibujarTerritoriosGlobal();
    if (mounted) {
      _mapboxGlobalMap?.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
              coordinates: mapbox.Position(
                  _kGlobalCenter.longitude, _kGlobalCenter.latitude)),
          zoom: 2.5,
        ),
        mapbox.MapAnimationOptions(duration: 400),
      );
    }
  }

  Future<void> _dibujarTerritoriosGlobal() async {
    final map = _mapboxGlobalMap;
    if (map == null || !_globalMbxStyleLoaded) return;
    final sel      = _state.territorioGlobalSeleccionado;
    final globales = _state.territoriosGlobales;
    if (globales.isEmpty) return;

    final features = globales.map((t) {
      final isSel     = sel?.id == t.id;
      final isMine    = t.isMine;
      final baseColor = isMine ? _kGold
          : t.isOwned ? t.displayColor : t.tierColor;

      final fillAlpha = isSel ? 0.65
          : isMine ? 0.55 : (t.isOwned ? 0.38 : 0.45);
      final lineAlpha = isMine ? 1.0 : (t.isOwned ? 0.92 : 0.90);
      final lineWidth = isSel ? 4.0 : isMine ? 3.0
          : (t.tier == TerritoryTier.legendario ? 2.5 : 2.0);
      final glowWidth = isMine ? 12.0 : (t.isOwned ? 8.0 : 6.0);
      final glowAlpha = isMine ? 0.30 : (t.isOwned ? 0.18 : 0.22);

      final owner = isMine ? 'TÚ'
          : t.isOwned ? (t.ownerNickname ?? '?') : 'LIBRE';
      final label = '${t.epicName}\n$owner';

      final coords = t.points.map((p) => [p.longitude, p.latitude]).toList()
        ..add([t.points.first.longitude, t.points.first.latitude]);
      return {
        'type': 'Feature',
        'properties': {
          'fillColor': _hexColor(baseColor.withValues(alpha: fillAlpha)),
          'lineColor': _hexColor(baseColor.withValues(alpha: lineAlpha)),
          'glowColor': _hexColor(baseColor.withValues(alpha: glowAlpha)),
          'lineWidth': lineWidth,
          'glowWidth': glowWidth,
          'label':     label,
          'labelColor': _hexColor(isMine ? _kGoldLight
              : t.isOwned ? Colors.white : _kSub),
        },
        'geometry': {'type': 'Polygon', 'coordinates': [coords]},
      };
    }).toList();

    final geojson = _toJson({'type': 'FeatureCollection', 'features': features});

    try {
      if (_globalMbxLayersCreated) {
        await (await map.style.getSource(_glbSrc)
            as mapbox.GeoJsonSource).updateGeoJSON(geojson);
        return;
      }
      if (_globalMbxLayersCreating) return;
      _globalMbxLayersCreating = true;

      await map.style.addSource(mapbox.GeoJsonSource(
          id: _glbSrc, data: geojson, tolerance: 0.5));

      // Glow exterior
      await map.style.addLayer(mapbox.LineLayer(
        id: _glbGlow, sourceId: _glbSrc,
        lineColorExpression: ['get', 'glowColor'],
        lineWidthExpression: ['get', 'glowWidth'],
        lineBlur: 6.0,
      ));
      // Relleno
      await map.style.addLayer(mapbox.FillLayer(
        id: _glbFill, sourceId: _glbSrc,
        fillColorExpression: ['get', 'fillColor'],
      ));
      // Borde
      await map.style.addLayer(mapbox.LineLayer(
        id: _glbLine, sourceId: _glbSrc,
        lineColorExpression: ['get', 'lineColor'],
        lineWidthExpression: ['get', 'lineWidth'],
      ));
      // Etiqueta
      await map.style.addLayer(mapbox.SymbolLayer(
        id: _glbLabel, sourceId: _glbSrc,
        textFieldExpression: ['get', 'label'],
        textColorExpression: ['get', 'labelColor'],
        textSize: 9,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.5,
        textMaxWidth: 10,
        textAnchor: mapbox.TextAnchor.CENTER,
      ));

      _globalMbxLayersCreated  = true;
      _globalMbxLayersCreating = false;
    } catch (_) {
      _globalMbxLayersCreating = false;
    }
  }

  void _onGlobalTapMapbox(mapbox.MapContentGestureContext ctx) {
    final tapLat = ctx.point.coordinates.lat.toDouble();
    final tapLng = ctx.point.coordinates.lng.toDouble();
    final tapLL  = LatLng(tapLat, tapLng);
    GlobalTerritory? encontrado;
    for (final t in _state.territoriosGlobales) {
      if (_pointInPolygon(tapLL, t.points)) { encontrado = t; break; }
    }
    if (encontrado != null) {
      _onGlobalTerritoryTap(encontrado);
    } else if (_state.territorioGlobalSeleccionado != null) {
      _cerrarSeleccion();
    }
    _dibujarTerritoriosGlobal();
  }

  // ==========================================================================
  // MAPA GLOBAL
  // ==========================================================================
  Widget _buildMapaGlobal() {
    final styleUri = _mapaOscuro
        ? mapbox.MapboxStyles.DARK
        : 'mapbox://styles/mapbox/outdoors-v12';
    return FadeTransition(
      opacity: _globalEntryAnim,
      child: Stack(children: [
        mapbox.MapWidget(
          key: const ValueKey('mapa_global_mapbox'),
          styleUri: styleUri,
          cameraOptions: mapbox.CameraOptions(
            center: mapbox.Point(coordinates: mapbox.Position(0, 20)),
            zoom: 2.5,
          ),
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
          },
          onMapCreated:          _onGlobalMapCreated,
          onStyleLoadedListener: _onGlobalStyleLoaded,
          onTapListener:         _onGlobalTapMapbox,
        ),
        // Campo de estrellas en modo oscuro — overlay Flutter puro
        if (_mapaOscuro) ...[
          IgnorePointer(
            child: SizedBox.expand(
              child: CustomPaint(painter: _StarfieldPainter(_starfield)),
            ),
          ),
          const IgnorePointer(
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(Color(0x33000B28), BlendMode.srcOver),
              child: SizedBox.expand(),
            ),
          ),
        ],
        if (_state.loadingGlobal) ...[
          const ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.black45, BlendMode.srcOver),
            child: SizedBox.expand(),
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kGold.withValues(alpha: 0.35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: _kGold),
                ),
                const SizedBox(width: 10),
                Text('Cargando territorios…',
                    style: _raj(11, FontWeight.w600, _kGold)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }


  // ==========================================================================
  // TOGGLE MAPA CLARO / OSCURO
  // ==========================================================================
  Widget _buildToggleMapa() {
    if (_state.modoGlobal) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _invalidarCacheMapa();
        setState(() => _mapaOscuro = !_mapaOscuro);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _kSurface.withValues(alpha: 0.85),
              border: Border.all(
                color: _mapaOscuro
                    ? _kGold.withValues(alpha: 0.55)
                    : _kBorder.withValues(alpha: 0.7),
              ),
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
            ),
            child: Icon(
              _mapaOscuro ? Icons.nightlight_round : Icons.wb_sunny_rounded,
              color: _mapaOscuro ? _kGold : _kSub,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // FAB — FIX: toggle entre mi posición y vista inicial
  // ==========================================================================
  Widget _buildFab() => GestureDetector(
    onTap: () async {
      HapticFeedback.mediumImpact();

      if (_state.modoGlobal) {
        // En modo global siempre centra el mapa global
        _moverCamara(_kGlobalCenter, 2.5);
        return;
      }

      if (_fabCentradoEnUsuario) {
        // Segunda pulsación: volver a vista de barrio (ciudad) o amplia (otros modos)
        final zoomOut = (_state.modoSolitario || _state.modoRutas)
            ? _kInitialZoom
            : 13.0;
        _moverCamara(_state.centro, zoomOut);
        setState(() => _fabCentradoEnUsuario = false);
      } else {
        // Primera pulsación: ir a mi posición actual con zoom cercano
        try {
          final perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse) {
            final pos = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.low));
            if (!mounted) return;
            _moverCamara(LatLng(pos.latitude, pos.longitude), _kLocateZoom);
            setState(() => _fabCentradoEnUsuario = true);
          }
        } catch (_) {
          _moverCamara(_state.centro, _kLocateZoom);
          setState(() => _fabCentradoEnUsuario = true);
        }
      }
    },
    child: AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _kSurface.withValues(alpha: 0.85),
              border: Border.all(
                // FIX: el borde cambia según el estado del toggle
                color: _state.modoGlobal
                    ? _kGold.withValues(alpha: 0.4 + 0.3 * _pulse.value)
                    : _fabCentradoEnUsuario
                        ? _kSafe.withValues(alpha: 0.7)
                        : _kRed.withValues(alpha: 0.4 + 0.3 * _pulse.value),
              ),
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                    color: (_state.modoGlobal
                            ? _kGold
                            : _fabCentradoEnUsuario
                                ? _kSafe
                                : _kRed)
                        .withValues(alpha: 0.15 * _pulse.value),
                    blurRadius: 16),
                const BoxShadow(color: Colors.black54, blurRadius: 12),
              ],
            ),
            // FIX: el icono cambia según el estado del toggle
            child: Icon(
              _state.modoGlobal
                  ? Icons.public_rounded
                  : _fabCentradoEnUsuario
                      ? Icons.explore_rounded   // centrado en usuario → icono brújula
                      : Icons.my_location_rounded,
              color: _state.modoGlobal
                  ? _kGold
                  : _fabCentradoEnUsuario
                      ? _kSafe
                      : _kRed,
              size: 18,
            ),
          ),
        ),
      ),
    ),
  );

  // ==========================================================================
  // CARD TERRITORIO CIUDAD — FIX: muestra stats y vida para todos los territorios
  // ==========================================================================
  Widget _buildTerritoryCard(TerritoryData t) {
    String estadoLabel = 'ACTIVO';
    Color cEstado = _kSafe;
    IconData estadoIcon = Icons.check_circle_rounded;
    if (t.estadoHp == EstadoHp.critico) {
      estadoLabel = 'CRÍTICO';
      cEstado = _kRed;
      estadoIcon = Icons.warning_rounded;
    } else if (t.estadoHp == EstadoHp.danado) {
      estadoLabel = 'DAÑADO';
      cEstado = _kWarn;
      estadoIcon = Icons.error_rounded;
    }

    final double hpFraction = t.hpActual / kHpMax.toDouble();
    // En modo competitivo, los territorios rivales no revelan nombre ni HP
    final bool rivalCompetitivo = !t.esMio && !_state.modoSolitario;

    return ScaleTransition(
      scale: _selAnim,
      child: FadeTransition(
        opacity: _selAnim,
        child: Container(
          decoration: BoxDecoration(
            color: _shBg,
            border: Border.all(color: t.color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                  color: t.color.withValues(alpha: 0.18), blurRadius: 20),
              const BoxShadow(
                  color: Colors.black54, blurRadius: 16),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Cabecera ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                color: t.color.withValues(alpha: 0.10),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8)),
                border: Border(
                    bottom: BorderSide(
                        color: t.color.withValues(alpha: 0.25))),
              ),
              child: Row(children: [
                Container(width: 3, height: 20, color: t.color,
                    margin: const EdgeInsets.only(right: 10)),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      t.esMio
                          ? 'MI TERRITORIO'
                          : rivalCompetitivo
                              ? 'ZONA RIVAL'
                              : t.ownerNickname.toUpperCase(),
                      style: _raj(13, FontWeight.w900, _shText,
                          spacing: 1.5)),
                  Text(
                      t.esMio
                          ? 'ZONA CONTROLADA'
                          : rivalCompetitivo
                              ? 'INFORMACIÓN BLOQUEADA'
                              : 'TERRITORIO RIVAL',
                      style: _raj(8, FontWeight.w700,
                          t.esMio ? t.color : _kSub, spacing: 2)),
                ])),
                GestureDetector(
                  onTap: _cerrarSeleccion,
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                        color: _shBorder,
                        borderRadius: BorderRadius.circular(4)),
                    child: Icon(Icons.close_rounded,
                        color: _shText, size: 14)),
                ),
              ]),
            ),

            // ── Stats row ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(children: [
                rivalCompetitivo
                    ? _cardStat(Icons.lock_outline_rounded, 'OCULTO', _kSub)
                    : _cardStat(estadoIcon, estadoLabel, cEstado),
                _vDiv(),
                _cardStat(Icons.flag_rounded, '${t.puntos.length} PTS', _shText),
                _vDiv(),
                t.esMio
                    ? _cardStat(Icons.shield_rounded, 'DEFENDER', _kGold)
                    : GestureDetector(
                        onTap: () {
                          _cerrarSeleccion();
                          _moverCamara(t.centro, 16);
                        },
                        child: _cardStat(Icons.visibility_rounded, 'OBSERVAR', _kSub),
                      ),
              ]),
            ),

            // ── Barra de vida — oculta en modo competitivo para rivales ──────
            if (!rivalCompetitivo)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: cEstado, shape: BoxShape.circle,
                          boxShadow: [BoxShadow(
                              color: cEstado.withValues(alpha: 0.6),
                              blurRadius: 4)],
                        ),
                        margin: const EdgeInsets.only(right: 6),
                      ),
                      Text(
                        t.estadoHp == EstadoHp.saludable
                            ? 'Territorio saludable'
                            : t.estadoHp == EstadoHp.danado
                                ? 'Territorio debilitado'
                                : 'En estado crítico',
                        style: _raj(9, FontWeight.w700, cEstado,
                            spacing: 0.5),
                      ),
                      const Spacer(),
                      Text(
                        '${t.hpActual}/$kHpMax HP',
                        style: _raj(9, FontWeight.w700, cEstado,
                            spacing: 0.5),
                      ),
                    ]),
                    const SizedBox(height: 5),
                    Stack(children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: _shBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: hpFraction.clamp(0.0, 1.0),
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: cEstado,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [BoxShadow(
                                color: cEstado.withValues(alpha: 0.5),
                                blurRadius: 6)],
                          ),
                        ),
                      ),
                    ]),
                    if (!t.esMio) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(Icons.schedule_rounded, color: _kSub, size: 11),
                        const SizedBox(width: 4),
                        Text(
                          'Sin visitar: ${t.diasSinVisitar} día${t.diasSinVisitar == 1 ? '' : 's'}',
                          style: _raj(9, FontWeight.w600, _kSub),
                        ),
                        if (t.esConquistableSinPasar) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _kRed.withValues(alpha: 0.12),
                              border: Border.all(color: _kRed.withValues(alpha: 0.5)),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('CONQUISTABLE',
                                style: _raj(8, FontWeight.w900, _kRed)),
                          ),
                        ],
                      ]),
                    ],
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, color: _kSub, size: 12),
                  const SizedBox(width: 6),
                  Text('Corre sobre este territorio para revelar su estado',
                    style: _raj(9, FontWeight.w600, _kSub, spacing: 0.3)),
                ]),
              ),

            // ── Stats extra: dominio + velocidad + rey ─────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(children: [
                if (t.fechaDesdeDueno != null)
                  _miniStat(
                    Icons.calendar_today_rounded,
                    '${DateTime.now().difference(t.fechaDesdeDueno!).inDays}d',
                    'DOMINIO',
                  ),
                if (t.fechaDesdeDueno != null) const SizedBox(width: 14),
                _miniStat(
                  Icons.speed_rounded,
                  '${t.velocidadConquistaKmh.toStringAsFixed(1)} km/h',
                  'VELOCIDAD',
                ),
                const Spacer(),
                if (t.tieneRey)
                  _miniStat(
                    Icons.military_tech_rounded,
                    t.reyNickname ?? 'Rey',
                    'REY',
                    color: _kGold,
                  ),
              ]),
            ),

            // ── Historial de conquistas ────────────────────────────────────
            if (!t.esFantasma)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                decoration: BoxDecoration(
                  color: _shSurf,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _buildCardHistorial(t.docId),
              ),

          ]),
        ),
      ),
    );
  }

  // ==========================================================================
  // CARD TERRITORIO GLOBAL — muestra clausulaKm via t.kmRequired
  // ==========================================================================
  Widget _buildGlobalTerritoryCard(GlobalTerritory t) {
    final Color baseColor = t.isMine
        ? _kGold
        : t.isOwned
            ? (t.ownerColor ?? t.tierColor)
            : t.tierColor;

    return ScaleTransition(
      scale: _selAnim,
      child: FadeTransition(
        opacity: _selAnim,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: _kSurface.withValues(alpha: 0.92),
                border: Border.all(color: baseColor.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                      color: baseColor.withValues(alpha: 0.2), blurRadius: 24),
                  const BoxShadow(
                      color: Colors.black87, blurRadius: 16),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        baseColor.withValues(alpha: 0.12),
                        Colors.transparent
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8)),
                    border: Border(
                        bottom: BorderSide(
                            color: baseColor.withValues(alpha: 0.2))),
                  ),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: baseColor.withValues(alpha: 0.40)),
                      ),
                      child: Center(
                          child: Text(t.icon,
                              style: const TextStyle(fontSize: 20))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: baseColor.withValues(alpha: 0.12),
                            border: Border.all(
                                color: baseColor.withValues(alpha: 0.35)),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(t.tierLabel,
                              style: _raj(7, FontWeight.w900, baseColor,
                                  spacing: 1)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _dificultadColor(t.difficultyLevel)
                                .withValues(alpha: 0.1),
                            border: Border.all(
                                color: _dificultadColor(t.difficultyLevel)
                                    .withValues(alpha: 0.35)),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('DIF. ${t.difficultyLevel}/10',
                              style: _raj(7, FontWeight.w900,
                                  _dificultadColor(t.difficultyLevel),
                                  spacing: 0.5)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(t.epicName,
                          style: _cinzel(12, FontWeight.w700, _kWhite)),
                      const SizedBox(height: 1),
                      Text(t.inspiration,
                          style: _raj(9, FontWeight.w500, _kSub)),
                    ])),
                    GestureDetector(
                      onTap: _cerrarSeleccion,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                            color: _kBorder,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Icon(Icons.close_rounded,
                            color: _kText, size: 14)),
                    ),
                  ]),
                ),

                // ── Stats — muestra clausulaKm via t.kmRequired ─────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(children: [
                    _cardStat(
                      Icons.directions_run_rounded,
                      '${t.kmRequired.toStringAsFixed(1)} km',
                      _kCyan,
                    ),
                    _vDiv(),
                    _cardStat(Icons.monetization_on_rounded, '+${t.rewardActual}', _kGold),
                    _vDiv(),
                    t.isMine
                        ? _cardStat(Icons.stars_rounded, 'TUYO', _kGold)
                        : t.isOwned
                            ? _cardStat(Icons.dangerous_rounded, 'INVADIR', _kRed)
                            : _cardStat(Icons.flag_rounded, 'LIBRE', _kSafe),
                  ]),
                ),

                if (t.isOwned && !t.isMine)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.06),
                        border: Border.all(
                            color: baseColor.withValues(alpha: 0.25)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: baseColor, shape: BoxShape.circle,
                            boxShadow: [BoxShadow(
                                color: baseColor.withValues(alpha: 0.5),
                                blurRadius: 4)],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Controlado por ',
                            style: _raj(10, FontWeight.w500, _kSub)),
                        Text(t.ownerNickname!.toUpperCase(),
                            style:
                                _raj(10, FontWeight.w900, baseColor)),
                      ]),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: GestureDetector(
                    onTap: () {
                      _cerrarSeleccion();
                      Future.delayed(
                          const Duration(milliseconds: 300), () {
                        _intentarConquistarGlobal(t);
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: t.isMine
                            ? _kGold.withValues(alpha: 0.08)
                            : baseColor.withValues(alpha: 0.15),
                        border: Border.all(
                            color: t.isMine
                                ? _kGold.withValues(alpha: 0.3)
                                : baseColor.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                          child: Text(
                        t.isMine
                            ? 'TERRITORIO CONTROLADO'
                            : 'CONQUISTAR · ${t.kmRequired.toStringAsFixed(1)} KM',
                        style: _raj(11, FontWeight.w900,
                            t.isMine ? _kGoldDim : baseColor,
                            spacing: 1),
                      )),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardStat(IconData icon, String label, Color color) =>
      Expanded(
        child: Column(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(label,
              style: _raj(9, FontWeight.w800, color, spacing: 0.5),
              textAlign: TextAlign.center),
        ]),
      );

  Widget _vDiv() => Container(
      width: 1, height: 36, color: _shBorder,
      margin: const EdgeInsets.symmetric(horizontal: 4));

  // ==========================================================================
  // SHEET MI CIUDAD
  // ==========================================================================
  // ==========================================================================
  // TERRITORY DECAY
  // ==========================================================================
  double _decayFactor(TerritoryData t) {
    if (t.ultimaVisita == null) return 1.0;
    final days = DateTime.now().difference(t.ultimaVisita!).inDays;
    if (days < 7) return 1.0;
    if (days >= 30) return 0.35;
    return 1.0 - ((days - 7) / 23) * 0.65;
  }

  // ==========================================================================
  // FILTRO DE MAPA
  // ==========================================================================
  List<TerritoryData> _filteredTerritorios(List<TerritoryData> all) {
    switch (_filtroActivo) {
      case _FiltroMapa.mios:     return all.where((t) => t.esMio).toList();
      case _FiltroMapa.enGuerra: return all.where((t) => t.estadoHp == EstadoHp.critico).toList();
      case _FiltroMapa.todos:    return all;
    }
  }

  Widget _buildFiltroChips() {
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _filtroChip('Todos',    _FiltroMapa.todos,    Icons.layers_rounded),
          const SizedBox(width: 6),
          _filtroChip('Míos',     _FiltroMapa.mios,     Icons.shield_rounded),
          const SizedBox(width: 6),
          _filtroChip('En guerra',_FiltroMapa.enGuerra, Icons.whatshot_rounded),
        ],
      ),
    );
  }

  Widget _filtroChip(String label, _FiltroMapa filtro, IconData icon) {
    final activo = _filtroActivo == filtro;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _filtroActivo = filtro);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color:   activo ? _kRed.withValues(alpha: 0.10) : _shSurf,
          border:  Border.all(
              color: activo ? _kRed.withValues(alpha: 0.45) : _shBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11,
              color: activo ? _kRed : _kSub),
          const SizedBox(width: 4),
          Text(label,
              style: _raj(10,
                  activo ? FontWeight.w800 : FontWeight.w600,
                  activo ? _kRed : _kSub,
                  spacing: 0.3)),
        ]),
      ),
    );
  }

  // ==========================================================================
  // FEED DE ACTIVIDAD RECIENTE
  // ==========================================================================
  Widget _buildFeedActividad() {
    return FutureBuilder<List<ActivityEntry>>(
      future: _feedFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: _kSub),
              ),
            ),
          );
        }
        final entries = snap.data ?? [];
        if (entries.isEmpty) return const SizedBox(height: 12);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kSub.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kSub.withValues(alpha: 0.20)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.bolt_rounded, size: 11, color: _kSub),
                    const SizedBox(width: 4),
                    Text('ACTIVIDAD RECIENTE',
                        style: _raj(8, FontWeight.w800, _kSub, spacing: 1.5)),
                  ]),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    await ActivityService.invalidarCache();
                    if (mounted) {
                      setState(() {
                        _feedFuture = ActivityService.obtenerFeedReciente();
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _shSurf,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _shBorder),
                    ),
                    child: const Icon(Icons.refresh_rounded, size: 12, color: _kSub),
                  ),
                ),
              ]),
            ),
            ...entries.map(_buildFeedItem),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildFeedItem(ActivityEntry e) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      decoration: BoxDecoration(
        color: _shSurf,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: e.color, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: e.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: e.color.withValues(alpha: 0.30)),
            ),
            child: Center(child: Icon(
              e.mode == 'solitario'
                  ? Icons.explore_rounded
                  : Icons.shield_rounded,
              size: 14,
              color: e.color,
            )),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: Text('@${e.userNick}',
                    style: _raj(11, FontWeight.w800, _shText),
                    overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                Text('conquistó', style: _raj(10, FontWeight.w400, _kSub)),
              ]),
              const SizedBox(height: 2),
              Text(e.territoryName,
                  style: _raj(11, FontWeight.w700, e.color),
                  overflow: TextOverflow.ellipsis),
              if (e.previousOwnerNick != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text('← @${e.previousOwnerNick}',
                      style: _raj(9, FontWeight.w500, _kDim),
                      overflow: TextOverflow.ellipsis),
                ),
            ],
          )),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: _shBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _shBorder),
            ),
            child: Text(e.timeAgo, style: _raj(9, FontWeight.w500, _kDim)),
          ),
        ]),
      ),
    );
  }

  // ==========================================================================
  // HISTORIAL DE CONQUISTAS (tarjeta de territorio)
  // ==========================================================================
  Widget _buildCardHistorial(String docId) {
    final cached = _historialCache[docId];
    if (cached != null) return _historialContent(cached);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ActivityService.obtenerHistorialTerritorio(docId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.2, color: _kSub)),
            ),
          );
        }
        final entries = snap.data ?? [];
        if (entries.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_historialCache.containsKey(docId)) {
              setState(() => _historialCache[docId] = entries);
            }
          });
        }
        return _historialContent(entries);
      },
    );
  }

  Widget _historialContent(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 5),
          child: Row(children: [
            Container(width: 2, height: 9, color: _kSub,
                margin: const EdgeInsets.only(right: 6)),
            Text('HISTORIAL', style: _raj(8, FontWeight.w800, _kSub, spacing: 1.5)),
          ]),
        ),
        ...entries.take(3).map((e) {
          final nick   = e['ownerNickname'] as String? ?? '?';
          final prev   = e['previousOwner'] as String?;
          final colorV = (e['ownerColor'] as num?)?.toInt();
          final color  = colorV != null ? Color(colorV) : _kSub;
          final ts     = (e['conquista_ts'] as Timestamp?)?.toDate();
          final ago    = ts != null ? _timeAgoStr(ts) : '';
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
            child: Row(children: [
              Container(width: 5, height: 5, margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
              Text('@$nick', style: _raj(9, FontWeight.w700, _shText)),
              if (prev != null)
                Text(' ← @$prev', style: _raj(9, FontWeight.w500, _kSub)),
              const Spacer(),
              Text(ago, style: _raj(9, FontWeight.w500, _kSub)),
            ]),
          );
        }),
        const SizedBox(height: 6),
      ],
    );
  }

  String _timeAgoStr(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours   < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  // ==========================================================================
  // MINI STAT — para tarjeta de territorio
  // ==========================================================================
  Widget _miniStat(IconData icon, String value, String label, {Color? color}) {
    final c = color ?? _kSub;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 9, color: c),
          const SizedBox(width: 3),
          Text(value, style: _raj(9, FontWeight.w800, _shText)),
        ]),
        Text(label, style: _raj(7, FontWeight.w700, c, spacing: 0.8)),
      ],
    );
  }

  Widget _buildSheet(ScrollController scrollCtrl, int mios, int det, int pel) {
    return Container(
      decoration: BoxDecoration(
        color: _shBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: _shBorder, width: 1)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, -2))],
      ),
      child: ListView(
        controller: scrollCtrl,
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        children: [
          _shPill(),
          _shHeader(
            icon: Icons.shield_rounded,
            modeLabel: 'MI CIUDAD',
            modeColor: _kBlue ,
            heroValue: '$mios',
            heroLabel: 'zonas conquistadas',
            trailing: _shStatusBadge(det, pel),
          ),
          _shStatBar([
            _ShStat('${_state.territorios.length}', 'EN MAPA'),
            _ShStat('${_state.jugadoresEnVivo.length}', 'EN VIVO'),
            _ShStat('$det', 'DESGASTE'),
            _ShStat('$pel', 'CRÍTICOS'),
          ]),
          if (pel > 0 || det > 0) _shAlert(det, pel),
          if (_state.loadingTerritorios)
            _shLoading('Buscando zonas', 'Cargando territorios cercanos', _kSub)
          else if (_state.territorios.isEmpty)
            _shEmptyState(Icons.map_outlined, 'Sin territorios',
                'No hay territorios en esta zona.\nSal a correr para descubrir y\nconquistar los más cercanos.')
          else if (mios == 0)
            _shEmptyState(Icons.flag_outlined, 'Zona libre',
                'Hay ${_state.territorios.length} territorios cerca.\nSal a conquistar el primero.')
          else ...[
            _shSectionTitle('Mis territorios'),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildFiltroChips(),
            ),
            _buildBotonCercanos(),
            if (_state.cercanosVisible) _buildPanelCercanos(),
          ],
          _buildFeedActividad(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==========================================================================
  // SHEET MODO SOLITARIO
  // ==========================================================================
  Widget _buildSheetSolitario(ScrollController scrollCtrl) {
    // Solo zonas con ≥1% — las demás se desbloquean al visitar
    final barriosOrdenados = (List<_BarrioData>.from(_barriosCercanos)
      ..sort((a, b) => b.porcentajeCubierto.compareTo(a.porcentajeCubierto)))
        .where((b) => b.porcentajeCubierto >= 0.01).toList();
    // Filtro por búsqueda
    final q = _barriosBusqueda.toLowerCase().trim();
    final barriosFiltrados = q.isEmpty
        ? barriosOrdenados
        : barriosOrdenados.where((b) => b.nombre.toLowerCase().contains(q)).toList();
    final completados = barriosOrdenados.where((b) => b.porcentajeCubierto >= 1.0).length;
    final enProgreso  = barriosOrdenados.where((b) => b.porcentajeCubierto > 0 && b.porcentajeCubierto < 1.0).length;
    final avgPct = barriosOrdenados.isEmpty ? 0
        : (barriosOrdenados.map((b) => b.porcentajeCubierto).reduce((a, b) => a + b)
            / barriosOrdenados.length * 100).toInt();

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        if (n.extent > 0.15 && !_barriosCargados && !_cargandoBarrios) {
          _cargarBarriosSolitario(_state.centro);
        }
        return false;
      },
      child: Container(
        decoration: BoxDecoration(
          color: _shBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(top: BorderSide(color: _shBorder, width: 1)),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, -2))],
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.zero,
          physics: const ClampingScrollPhysics(),
          children: [
            _shPill(),
            _shHeader(
              icon: Icons.explore_rounded,
              modeLabel: 'EXPLORADOR',
              modeColor: _kSafe,
              heroValue: _cargandoBarrios ? '…' : '${barriosOrdenados.length}',
              heroLabel: 'zonas cercanas',
              trailing: (!_cargandoBarrios && !_barriosCargados && barriosOrdenados.isEmpty)
                  ? GestureDetector(
                      onTap: () => _cargarBarriosSolitario(_state.centro),
                      child: _shPillBadge('Cargar', Icons.download_rounded, _kSub),
                    )
                  : null,
            ),
            if (barriosOrdenados.isNotEmpty)
              _shStatBar([
                _ShStat('$completados', 'COMPLETAS'),
                _ShStat('$enProgreso', 'EN CURSO'),
                _ShStat('$avgPct%', 'COBERTURA'),
              ]),
            if (barriosOrdenados.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _barriosSearchCtrl,
                  onChanged: (v) => setState(() => _barriosBusqueda = v),
                  style: _raj(13, FontWeight.w500, _shText),
                  decoration: InputDecoration(
                    hintText: 'Buscar zona…',
                    hintStyle: _raj(13, FontWeight.w400, _kSub),
                    prefixIcon: Icon(Icons.search_rounded, color: _kSub, size: 18),
                    suffixIcon: _barriosBusqueda.isNotEmpty
                        ? GestureDetector(
                            onTap: () => setState(() {
                              _barriosBusqueda = '';
                              _barriosSearchCtrl.clear();
                            }),
                            child: Icon(Icons.close_rounded, color: _kSub, size: 16),
                          )
                        : null,
                    filled: true,
                    fillColor: _shSurf,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _shBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _shBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _kSub),
                    ),
                  ),
                ),
              ),
            if (_cargandoBarrios)
              _shLoading('Cargando zonas', 'Consultando OpenStreetMap', _kSub)
            else if (_errorBarrios != null)
              GestureDetector(
                onTap: () {
                  setState(() { _errorBarrios = null; });
                  _cargarBarriosSolitario(_state.centro);
                },
                child: _shEmptyState(Icons.refresh_rounded, 'No se pudieron cargar',
                    '$_errorBarrios\nToca para reintentar'),
              )
            else if (barriosFiltrados.isNotEmpty) ...[
              _shSectionTitle('Zonas desbloqueadas'),
              ...barriosFiltrados.map(_shBarrioCell),
            ] else if (barriosOrdenados.isNotEmpty)
              _shEmptyState(Icons.search_off_rounded, 'Sin resultados',
                  'No hay zonas que coincidan con "$_barriosBusqueda"')
            else if (_barriosCargados)
              _shEmptyState(Icons.explore_rounded, 'Sin zonas desbloqueadas',
                  'Corre por una zona para desbloquearla aquí')
            else
              _shEmptyState(Icons.explore_rounded, 'Desliza para cargar',
                  'Se consultarán las zonas cercanas'),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // SHEET GUERRA GLOBAL
  // ==========================================================================
  Widget _buildSheetGlobal(ScrollController scrollCtrl) {
    final uid  = _uid ?? '';
    final mios = _state.territoriosGlobales.where((t) => t.ownerUid == uid).toList();
    final libres = _state.territoriosGlobales.where((t) => !t.isOwned).toList();
    final disp = _state.territoriosGlobales.where((t) => t.isOwned && t.ownerUid != uid).toList();
    final max  = _MapState.maxTerritoriosPorJugador;

    return Container(
      decoration: BoxDecoration(
        color: _shBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: _shBorder, width: 1)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, -2))],
      ),
      child: ListView(
        controller: scrollCtrl,
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        children: [
          _shPill(),
          _shHeader(
            icon: Icons.public_rounded,
            modeLabel: 'GUERRA GLOBAL',
            modeColor: _kGold,
            heroValue: '${mios.length}',
            heroSuffix: '/ $max',
            heroLabel: 'dominios',
            trailing: _shPillBadge('${_state.diasRestantesSemana}d', Icons.timer_outlined, _kSub),
            below: _shCapacityBar(mios.length, max, _kSub),
          ),
          _shStatBar([
            _ShStat('${mios.length}', 'MÍOS'),
            _ShStat('${libres.length}', 'LIBRES'),
            _ShStat('${disp.length}', 'EN DISPUTA'),
            _ShStat('${_state.totalJugadoresGlobal}', 'RIVALES'),
          ]),
          if (mios.isNotEmpty) ...[
            _shSectionTitle('Mis dominios'),
            ...mios.map(_globalTerCard),
          ],
          if (libres.isNotEmpty) ...[
            _shSectionTitle('Disponibles'),
            ...libres.map(_globalTerCard),
          ],
          if (disp.isNotEmpty) ...[
            _shSectionTitle('En disputa'),
            ...disp.map(_globalTerCard),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==========================================================================
  // iOS SHEET HELPERS
  // ==========================================================================

  Widget _shPill() => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Center(
      child: Container(
        width: 36, height: 4,
        decoration: BoxDecoration(
          color: _shBorder,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );

  // ==========================================================================
  // SHEET MODO RUTAS
  // ==========================================================================
  Widget _buildSheetRutas(ScrollController scrollCtrl) {
    final totalKm   = _misRutas.fold(0.0, (s, r) => s + r.distanciaKm);
    final totalRutas = _misRutas.length;

    return Container(
      decoration: BoxDecoration(
        color: _shBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: _shBorder, width: 1)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, -2))],
      ),
      child: ListView(
        controller: scrollCtrl,
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        children: [
          _shPill(),
          _shHeader(
            icon:       Icons.route_rounded,
            modeLabel:  'MIS RUTAS',
            modeColor:  const Color(0xFF9B72CF),
            heroValue:  '$totalRutas',
            heroLabel:  totalRutas == 1 ? 'ruta guardada' : 'rutas guardadas',
            trailing: GestureDetector(
              onTap: _cargarMisRutas,
              child: const Icon(Icons.refresh_rounded, color: _kSub, size: 18),
            ),
          ),
          _shStatBar([
            _ShStat(totalKm.toStringAsFixed(1), 'KM TOTAL'),
            _ShStat('$totalRutas', 'RUTAS'),
            if (_misRutas.isNotEmpty) ...[
              _ShStat(
                _misRutas.map((r) => r.distanciaKm).reduce(math.max).toStringAsFixed(1),
                'MEJOR KM',
              ),
            ],
          ]),
          if (_cargandoRutas)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(
                    color: Color(0xFF9B72CF), strokeWidth: 1.5),
              ),
            )
          else if (_misRutas.isEmpty)
            _shEmptyState(
              Icons.route_rounded,
              'Sin rutas',
              'Sal a correr en modo Ruta Libre\npara ver tus recorridos aquí',
            )
          else ...[
            _shSectionTitle('Historial de rutas'),
            ..._misRutas.map((r) => _buildRutaCard(r)),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildRutaCard(RouteData r) {
    final isSelected = _rutaSeleccionada?.id == r.id;
    final fechaStr   = '${r.fecha.day}/${r.fecha.month}/${r.fecha.year}';
    final nombre     = (r.nombre != null && r.nombre!.isNotEmpty)
        ? r.nombre!
        : 'Ruta $fechaStr';

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _rutaSeleccionada = isSelected ? null : r);
        if (!isSelected && r.coords.isNotEmpty) {
          _moverCamara(r.coords.first, 14.5);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6A4A9B).withValues(alpha: 0.12)
              : _shSurf,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF9B72CF).withValues(alpha: 0.5)
                : _shBorder,
          ),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color:  r.color.withValues(alpha: 0.15),
              shape:  BoxShape.circle,
              border: Border.all(color: r.color.withValues(alpha: 0.4)),
            ),
            child: Icon(Icons.route_rounded, color: r.color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre,
                  style: _raj(13, FontWeight.w700, _shText),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(fechaStr, style: _raj(10, FontWeight.w400, _kSub)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${r.distanciaKm.toStringAsFixed(2)} km',
                style: _raj(13, FontWeight.w700, _shText)),
            const SizedBox(height: 2),
            Text(r.ritmoStr,
                style: _raj(10, FontWeight.w400, _kSub)),
          ]),
        ]),
      ),
    );
  }

  Widget _shHeader({
    required IconData icon,
    required String modeLabel,
    required Color modeColor,
    required String heroValue,
    required String heroLabel,
    String? heroSuffix,
    Widget? trailing,
    Widget? below,
  }) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: modeColor.withValues(alpha: 0.20)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 11, color: modeColor),
              const SizedBox(width: 5),
              Text(modeLabel, style: _raj(9, FontWeight.w700, modeColor, spacing: 1)),
            ]),
          ),
          if (trailing != null) ...[const Spacer(), trailing],
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(heroValue, style: _raj(36, FontWeight.w900, _shText, height: 1)),
          if (heroSuffix != null) ...[
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(heroSuffix, style: _raj(16, FontWeight.w600, _kSub)),
            ),
          ],
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(heroLabel, style: _raj(11, FontWeight.w500, _kSub)),
          ),
        ]),
        if (below != null) ...[const SizedBox(height: 10), below],
      ]),
    );

  Widget _shStatBar(List<_ShStat> items) {
    final children = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 8));
      children.add(Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _shSurf,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(items[i].value, style: _raj(17, FontWeight.w800, _shText, height: 1)),
            const SizedBox(height: 3),
            Text(items[i].label, style: _raj(8, FontWeight.w600, _kSub, spacing: 0.3)),
          ]),
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(children: children),
    );
  }

  Widget _shSectionTitle(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(children: [
      Text(label.toUpperCase(), style: _raj(11, FontWeight.w700, _kSub, spacing: 0.5)),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 0.5, color: _shBorder)),
    ]),
  );

  Widget _shPillBadge(String label, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.20)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(label, style: _raj(9, FontWeight.w600, color, spacing: 0.3)),
    ]),
  );

  Widget _shStatusBadge(int det, int pel) {
    if (pel > 0) return _shPillBadge('$pel críticos', Icons.warning_rounded, _kSub);
    if (det > 0) return _shPillBadge('$det desgaste', Icons.shield_outlined, _kSub);
    return _shPillBadge('Todo OK', Icons.check_circle_outline_rounded, _kSub);
  }

  Widget _shAlert(int det, int pel) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
    decoration: BoxDecoration(
      color: _shSurf,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _shBorder),
    ),
    child: Row(children: [
      Container(
        width: 3, height: 30,
        decoration: BoxDecoration(color: _kSub, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 10),
      Icon(Icons.shield_outlined, color: _kSub, size: 14),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          pel > 0
              ? '$pel ${pel == 1 ? 'territorio puede' : 'territorios pueden'} ser conquistados.'
              : '$det ${det == 1 ? 'territorio debilitado' : 'territorios debilitados'}. Visítalos pronto.',
          style: _raj(11, FontWeight.w500, _kDim),
        ),
      ),
    ]),
  );

  Widget _shEmptyState(IconData icon, String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: _shSurf,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: _kSub, size: 22),
      ),
      const SizedBox(height: 12),
      Text(title.toUpperCase(), style: _raj(12, FontWeight.w700, _kSub, spacing: 1)),
      const SizedBox(height: 4),
      Text(subtitle,
          textAlign: TextAlign.center,
          style: _raj(11, FontWeight.w400, _kDim, height: 1.5)),
    ]),
  );

  Widget _shLoading(String title, String subtitle, Color color) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 22, height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
      const SizedBox(height: 12),
      Text(title, style: _raj(12, FontWeight.w600, _kSub)),
      const SizedBox(height: 3),
      Text(subtitle, style: _raj(10, FontWeight.w400, _kDim)),
    ]),
  );

  Widget _shCapacityBar(int current, int max, Color color) {
    final frac = (current / max).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('CAPACIDAD', style: _raj(8, FontWeight.w700, _kSub, spacing: 1)),
        const Spacer(),
        Text('$current / $max', style: _raj(9, FontWeight.w700, _kDim)),
      ]),
      const SizedBox(height: 5),
      Stack(children: [
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: _shBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        FractionallySizedBox(
          widthFactor: frac,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: _kDim,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _shBarrioCell(_BarrioData b) {
    final pct = b.porcentajeCubierto;
    const Color color = _kSub;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _moverCamara(b.centro, 13.5);
        if (_sheetCtrl.isAttached) {
          _sheetCtrl.animateTo(0.13,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic);
        }
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _shSurf,
          border: Border.all(color: _shBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Container(
            width: 3, height: 32,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.nombre,
                style: _raj(12, FontWeight.w600, _shText),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Stack(children: [
              Container(height: 2,
                  decoration: BoxDecoration(color: _shBorder, borderRadius: BorderRadius.circular(2))),
              FractionallySizedBox(
                widthFactor: pct.clamp(0.0, 1.0),
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: _kDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ]),
          ])),
          const SizedBox(width: 12),
          Text(pct >= 1.0 ? '100%' : '${(pct * 100).toInt()}%',
              style: _raj(13, FontWeight.w800, _shText)),
        ]),
      ),
    );
  }


  /// Card de territorio global en la sheet — muestra clausulaKm real
  Widget _globalTerCard(GlobalTerritory t) {
    final Color baseColor = t.isMine
        ? _kGold
        : t.isOwned
            ? (t.ownerColor ?? t.tierColor)
            : t.tierColor;
    final diffColor = _dificultadColor(t.difficultyLevel);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _onGlobalTerritoryTap(t);
        _sheetCtrl.animateTo(0.13,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut);
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _shSurf,
          border: Border.all(
              color: t.isMine
                  ? _kGold.withValues(alpha: 0.40)
                  : t.isOwned
                      ? baseColor.withValues(alpha: 0.30)
                      : _shBorder),
          borderRadius: BorderRadius.circular(10),
          boxShadow: t.isMine
              ? [BoxShadow(color: _kGold.withValues(alpha: 0.10), blurRadius: 16)]
              : t.isOwned
                  ? [BoxShadow(color: baseColor.withValues(alpha: 0.07), blurRadius: 12)]
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color:  baseColor.withValues(alpha: t.isOwned ? 0.12 : 0.06),
              shape:  BoxShape.circle,
              border: Border.all(
                  color: baseColor.withValues(alpha: t.isOwned ? 0.45 : 0.25)),
            ),
            child: Center(
              child: Icon(
                t.tier == TerritoryTier.legendario
                    ? Icons.stars_rounded
                    : t.tier == TerritoryTier.mediano
                        ? Icons.shield_rounded
                        : Icons.flag_rounded,
                color: baseColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: baseColor.withValues(alpha: 0.10),
                  border:
                      Border.all(color: baseColor.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(t.tierLabel,
                    style: _raj(7, FontWeight.w900, baseColor,
                        spacing: 1)),
              ),
              const SizedBox(width: 6),
              if (t.isMine)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: _kGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text('TUYO',
                      style: _raj(7, FontWeight.w900, _kGold)),
                ),
            ]),
            const SizedBox(height: 4),
            Text(t.epicName,
                style: _raj(12, FontWeight.w700, _shText),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(children: [
              if (t.isOwned) ...[
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                      color: baseColor, shape: BoxShape.circle),
                  margin: const EdgeInsets.only(right: 5),
                ),
              ],
              Text(
                t.isOwned && !t.isMine
                    ? t.ownerNickname!
                    : t.isMine
                        ? 'Controlado por ti'
                        : 'Disponible',
                style: _raj(9, FontWeight.w600,
                    t.isMine
                        ? _kGold
                        : (t.isOwned ? baseColor : _kSafe)),
              ),
            ]),
          ])),

          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color:  diffColor.withValues(alpha: 0.10),
                border: Border.all(color: diffColor.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('${t.difficultyLevel}/10',
                  style: _raj(10, FontWeight.w900, diffColor)),
            ),
            const SizedBox(height: 6),
            // ── clausulaKm real via t.kmRequired ────────────────────────
            Text('${t.kmRequired.toStringAsFixed(1)} km',
                style: _raj(11, FontWeight.w700, _kCyan)),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.monetization_on_rounded,
                  size: 10, color: _kGoldDim),
              const SizedBox(width: 3),
              Text('+${t.rewardActual}',
                  style: _raj(10, FontWeight.w600, _kGoldDim)),
            ]),
          ]),
        ]),
      ),
    );
  }


  Widget _buildBotonCercanos() => GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      if (_state.cercanosVisible) {
        _state.toggleCercanos();
      } else {
        _state.cargarCercanos(_uid ?? '', modo: _state.modoSolitario ? 'solitario' : 'competitivo');
      }
    },
    child: Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: _shSurf,
        border: Border.all(
            color: _state.cercanosVisible
                ? _kRed.withValues(alpha: 0.3)
                : _shBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                  color: _kSafe.withValues(alpha: 0.4 + 0.6 * _pulse.value),
                  shape: BoxShape.circle),
            )),
        const SizedBox(width: 10),
        _state.loadingCercanos
            ? Shimmer.fromColors(
                baseColor: _shSurf,
                highlightColor: _shBorder,
                child: Container(
                    width: 160, height: 12,
                    decoration: BoxDecoration(
                        color: _shSurf,
                        borderRadius: BorderRadius.circular(3))))
            : Text(
                _state.cercanosVisible
                    ? 'TERRITORIOS EN ZONA  ▲'
                    : 'TERRITORIOS EN ZONA  ▼',
                style: _raj(10, FontWeight.w700,
                    _state.cercanosVisible ? _shText : _kSub,
                    spacing: 1.5)),
        const Spacer(),
        Text('5 KM',
            style: _raj(9, FontWeight.w800, _kDim, spacing: 1)),
        const SizedBox(width: 8),
        Icon(Icons.radar_rounded,
            color: _state.cercanosVisible ? _kRed : _kDim, size: 14),
      ]),
    ),
  );

  Widget _buildPanelCercanos() {
    if (_state.grupos.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _shSurf,
            border: Border.all(color: _shBorder),
            borderRadius: BorderRadius.circular(6)),
        child: Text('No hay territorios en 5 km',
            style: _raj(12, FontWeight.w500, _kSub)),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
          color: _shSurf,
          border: Border.all(color: _shBorder),
          borderRadius: BorderRadius.circular(6)),
      child: Column(
        children: _state.grupos.asMap().entries.map((entry) {
          final idx = entry.key;
          final g   = entry.value;
          final isExp  = _state.userExpandido == g.ownerId;
          final dets   = _state.detallesDe(g.ownerId);
          final isLast = idx == _state.grupos.length - 1;
          return Column(children: [
            InkWell(
              onTap: () async {
                HapticFeedback.selectionClick();
                if (isExp) {
                  _state.setUserExpandido(null);
                } else {
                  _state.setUserExpandido(g.ownerId);
                  await _state.cargarDetalles(g.ownerId, modo: _state.modoSolitario ? 'solitario' : 'competitivo');
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 13),
                child: Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: g.esMio ? _kRed : _kSub,
                      shape: BoxShape.circle,
                      boxShadow: g.esMio
                          ? [BoxShadow(
                              color: _kRed.withValues(alpha: 0.5),
                              blurRadius: 6)]
                          : null,
                    )),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    g.esMio
                        ? '${g.nickname.toUpperCase()}  (TÚ)'
                        : g.nickname.toUpperCase(),
                    style: _raj(12, FontWeight.w800,
                        g.esMio ? _shText : _kSub, spacing: 1))),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        border: Border.all(color: _shBorder),
                        borderRadius: BorderRadius.circular(3)),
                    child: Text('NIV.${g.nivel}',
                        style: _raj(8, FontWeight.w900,
                            g.esMio ? _kRed : _kSub))),
                  const SizedBox(width: 8),
                  Text('${g.territorios.length}',
                      style: _raj(11, FontWeight.w600, _kDim)),
                  const SizedBox(width: 2),
                  const Icon(Icons.flag_rounded, size: 11, color: _kDim),
                  const SizedBox(width: 6),
                  Icon(
                    isExp
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: _kDim, size: 18),
                ]),
              ),
            ),
            if (isExp)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _shBg,
                    border: Border.all(color: _shBorder),
                    borderRadius: BorderRadius.circular(4)),
                child: dets == null
                    ? _buildShimmerDetalles()
                    : dets.isEmpty
                        ? Text('Sin territorios',
                            style: _raj(12, FontWeight.w500, _kSub))
                        : Column(
                            children: dets.asMap().entries
                                .map((e) => _terCard(
                                      e.key,
                                      e.value,
                                      g.esMio ? 'YO' : g.nickname,
                                    ))
                                .toList()),
              ),
            if (!isLast)
              Container(height: 1, color: _shBorder),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildShimmerDetalles() => Column(
    children: List.generate(
        2,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Shimmer.fromColors(
            baseColor: _shSurf, highlightColor: _shBorder,
            child: Container(
                height: 44,
                decoration: BoxDecoration(
                    color: _shSurf,
                    borderRadius: BorderRadius.circular(4))),
          ),
        )),
  );

  Widget _terCard(int i, _TerDet det, String nick) {
    String est = 'ACTIVO';
    Color c = _state.modoSolitario ? _kSafe : _kBlue;
    if (det.diasSinVisitar != null && det.diasSinVisitar! >= kDiasParaDeterioroFuncional) {
      est = 'CRÍTICO'; c = _kRed;
    } else if (det.diasSinVisitar != null && det.diasSinVisitar! >= kDiasParaDeterioroVisual) {
      est = 'DESGASTE'; c = _kWarn;
    }
    return GestureDetector(
      onTap: () => _mostrarDialogo(det, nick),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: _kSurface,
            border: Border.all(color: c.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(4)),
        child: Row(children: [
          Container(width: 2, height: 14, color: c,
              margin: const EdgeInsets.only(right: 8)),
          Text('ZONA #${i + 1}',
              style: _raj(11, FontWeight.w800, _kText,
                  spacing: 0.5)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 5, vertical: 2),
            color: c.withValues(alpha: 0.08),
            child: Text(est,
                style: _raj(8, FontWeight.w800, c, spacing: 1))),
          const Spacer(),
          Text('${det.dist.toStringAsFixed(1)} km',
              style: _raj(10, FontWeight.w600, _kSub)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded,
              color: _kRed.withValues(alpha: 0.5), size: 13),
        ]),
      ),
    );
  }

  // ==========================================================================
  // DIÁLOGO DETALLE TERRITORIO
  // ==========================================================================
  void _mostrarDialogo(_TerDet det, String ownerNick) {
    final esMio = det.ownerId == (_uid ?? '');
    final conquistable = !esMio &&
        det.diasSinVisitar != null &&
        det.diasSinVisitar! >= kDiasParaDeterioroFuncional;
    final centro = det.puntos.isNotEmpty
        ? LatLng(
            det.puntos.map((p) => p.latitude).reduce((a, b) => a + b) /
                det.puntos.length,
            det.puntos.map((p) => p.longitude).reduce((a, b) => a + b) /
                det.puntos.length)
        : _state.centro;

    String estado = 'activo';
    Color cEstado = _kSafe;
    if (det.diasSinVisitar != null && det.diasSinVisitar! >= kDiasParaDeterioroFuncional) {
      estado = 'crítico'; cEstado = _kRed;
    } else if (det.diasSinVisitar != null && det.diasSinVisitar! >= kDiasParaDeterioroVisual) {
      estado = 'con desgaste'; cEstado = _kWarn;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        TerritoryData? td;
        try {
          td = _state.territorios.firstWhere((x) => x.docId == det.docId);
        } catch (_) {}
        final Color accent = td?.color ?? cEstado;
        final int hp       = td?.hpActual ?? kHpMax;
        final double hpFrac = (hp / kHpMax).clamp(0.0, 1.0);
        final Color hpColor;
        switch (td?.estadoHp ?? EstadoHp.saludable) {
          case EstadoHp.saludable: hpColor = _kSafe; break;
          case EstadoHp.danado:    hpColor = _kWarn; break;
          case EstadoHp.critico:   hpColor = _kRed;  break;
        }

        return Container(
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border(
              top:   BorderSide(color: accent.withValues(alpha: 0.55), width: 2),
              left:  BorderSide(color: _kBorder2),
              right: BorderSide(color: _kBorder2),
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              width: 32, height: 3,
              decoration: BoxDecoration(
                  color: _kBorder, borderRadius: BorderRadius.circular(2))),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 2, height: 36, color: accent,
                  margin: const EdgeInsets.only(right: 10, top: 2)),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ownerNick.toUpperCase(),
                        style: _raj(14, FontWeight.w900, _kWhite, spacing: 1.0)),
                    const SizedBox(height: 2),
                    Text(
                      det.nombreTerritorio != null && det.nombreTerritorio!.isNotEmpty
                          ? det.nombreTerritorio!
                          : 'Sin nombre asignado',
                      style: _raj(11, FontWeight.w500, _kSub)),
                  ],
                )),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: cEstado.withValues(alpha: 0.06),
                    border: Border.all(color: cEstado.withValues(alpha: 0.28)),
                    borderRadius: BorderRadius.circular(3)),
                  child: Text(estado.toUpperCase(),
                      style: _raj(8, FontWeight.w800, cEstado, spacing: 0.8))),
              ]),
            ),

            const Divider(height: 1, thickness: 1, color: _kBorder2),

            // Mini map
            if (det.puntos.isNotEmpty)
              SizedBox(
                height: 140,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: centro,
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom |
                            InteractiveFlag.doubleTapZoom)),
                  children: [
                    TileLayer(
                        urlTemplate: _kMapboxUrl,
                        userAgentPackageName: 'com.runner_risk.app',
                        tileDimension: 256,
                        keepBuffer: 4,
                        panBuffer: 1),
                    PolygonLayer(polygons: [
                      Polygon(
                          points: det.puntos,
                          color: accent.withValues(alpha: 0.15),
                          borderColor: accent,
                          borderStrokeWidth: 2),
                    ]),
                  ],
                ),
              ),

            if (det.puntos.isNotEmpty)
              const Divider(height: 1, thickness: 1, color: _kBorder2),

            // HP bar (enemy territories only)
            if (td != null && !esMio)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(children: [
                  Row(children: [
                    Text(estado.toUpperCase(),
                        style: _raj(9, FontWeight.w700, hpColor, spacing: 0.8)),
                    const Spacer(),
                    Text('$hp / $kHpMax HP',
                        style: _raj(9, FontWeight.w500, _kSub)),
                  ]),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(1.5),
                    child: Stack(children: [
                      Container(height: 3, color: _kBorder2),
                      FractionallySizedBox(
                        widthFactor: hpFrac,
                        child: Container(height: 3, color: hpColor)),
                    ]),
                  ),
                ]),
              ),

            // Stats
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(children: [
                _dStat(
                    'SIN VISITAR',
                    det.diasSinVisitar != null ? '${det.diasSinVisitar}d' : '—',
                    _kText),
                Container(width: 1, height: 32, color: _kBorder2),
                _dStat('DISTANCIA',
                    '${det.dist.toStringAsFixed(1)} km', _kText),
                Container(width: 1, height: 32, color: _kBorder2),
                _dStat('VÉRTICES', '${det.puntos.length}', _kText),
              ]),
            ),

            const Divider(height: 1, thickness: 1, color: _kBorder2),
            const SizedBox(height: 8),

            // Action buttons
            if (conquistable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: GestureDetector(
                  onTap: () => _ejecutarConquista(det, ownerNick),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _kRed.withValues(alpha: 0.06),
                      border: Border.all(color: _kRed.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.sports_kabaddi_rounded,
                              color: _kRed, size: 16),
                          const SizedBox(width: 10),
                          Text('CONQUISTAR TERRITORIO',
                              style: _raj(12, FontWeight.w900, _kRed,
                                  spacing: 1.5)),
                        ]),
                  ),
                ),
              ),
            if (!esMio && !conquistable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 11, horizontal: 14),
                  decoration: BoxDecoration(
                      color: _kSurface2,
                      border: Border.all(color: _kBorder2),
                      borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    const Icon(Icons.lock_outline_rounded,
                        color: _kSub, size: 13),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'Faltan ${kDiasParaDeterioroFuncional - (det.diasSinVisitar ?? 0)} días sin visita para conquistar.',
                      style: _raj(10, FontWeight.w500, _kSub),
                    )),
                  ]),
                ),
              ),
            if (esMio)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    _mostrarDialogoRenombrar(det);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.06),
                      border: Border.all(color: accent.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit_outlined, color: accent, size: 15),
                          const SizedBox(width: 8),
                          Text(
                            det.nombreTerritorio != null &&
                                    det.nombreTerritorio!.isNotEmpty
                                ? 'EDITAR NOMBRE'
                                : 'ASIGNAR NOMBRE',
                            style: _raj(12, FontWeight.w800, accent,
                                spacing: 1.2)),
                        ]),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  Widget _dStat(String l, String v, Color c) =>
      Expanded(child: Column(children: [
        Text(l, style: _raj(8, FontWeight.w700, _kSub, spacing: 1.5)),
        const SizedBox(height: 4),
        Text(v, style: _raj(16, FontWeight.w900, c)),
      ]));

  void _mostrarDialogoRenombrar(_TerDet det) {
    showDialog(
      context: context,
      builder: (_) => _DialogoRenombrar(
        nombreActual: det.nombreTerritorio ?? '',
        onGuardar: (nuevoNombre) async {
          try {
            await TerritoryService.renombrarTerritorio(
                docId: det.docId, nombre: nuevoNombre);
            if (!mounted) return;
            _mostrarExito(
                '✏️ Territorio renombrado como "$nuevoNombre"');
            _MapState.invalidarDetallesCache();
            await _state.cargarDetalles(det.ownerId, modo: _state.modoSolitario ? 'solitario' : 'competitivo');
          } on FirebaseFunctionsException catch (e) {
            if (!mounted) return;
            _mostrarError(e.message ?? 'No se pudo renombrar');
          } catch (_) {
            if (!mounted) return;
            _mostrarError('Error inesperado.');
          }
        },
      ),
    );
  }

}
