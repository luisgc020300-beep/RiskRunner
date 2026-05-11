// lib/screens/fullscreen_map_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../services/territory_service.dart';
import '../services/game_state_service.dart';
import '../services/activity_service.dart';
import '../services/route_service.dart';
import '../widgets/custom_navbar.dart';
import '../config/env.dart';

// =============================================================================
// MAPBOX
// =============================================================================
const String _kMapboxToken = Env.mapboxPublicToken;
const String _kMapboxUrl =
    'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12'
    '/tiles/512/{z}/{x}/{y}@2x?access_token=$_kMapboxToken';

const String _kMapboxDarkUrl =
    'https://api.mapbox.com/styles/v1/mapbox/dark-v11'
    '/tiles/512/{z}/{x}/{y}@2x?access_token=$_kMapboxToken';

// =============================================================================
// PALETA
// =============================================================================
const _kBg       = Color(0xFFE8E8ED);
const _kSurface  = Color(0xFFFFFFFF);
const _kSurface2 = Color(0xFFE5E5EA);
const _kBorder   = Color(0xFFC6C6C8);
const _kBorder2  = Color(0xFFD1D1D6);
const _kDim      = Color(0xFFAEAEB2);
const _kSub      = Color(0xFF8E8E93);
const _kText     = Color(0xFF3C3C43);
const _kWhite    = Color(0xFF1C1C1E);
const _kRed      = Color(0xFFE02020);
const _kSafe     = Color(0xFF30D158);
const _kWarn     = Color(0xFFFF9500);
const _kGold     = Color(0xFFFFD60A);
const _kGoldDim  = Color(0xFFAEAEB2);
const _kGoldLight = Color(0xFFFFD60A);
const _kCyan     = Color(0xFF636366);
const _kBlue     = Color.fromARGB(255, 16, 154, 235);


TextStyle _raj(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    GoogleFonts.inter(
        fontSize: size, fontWeight: weight, color: color,
        letterSpacing: spacing, height: height);

TextStyle _cinzel(double size, FontWeight weight, Color color,
    {double spacing = 0}) =>
    GoogleFonts.cinzel(
        fontSize: size, fontWeight: weight, color: color,
        letterSpacing: spacing);



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

  Future<List<_UserGroup>> cargarGruposCercanos(LatLng centro, String myUid) async {
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
    for (final chunk in chunks) {
      try {
        final pd = await _db.collection('players')
            .where(FieldPath.documentId, whereIn: chunk).get();
        for (final p in pd.docs) { playersMap[p.id] = p.data(); }
      } catch (_) {}
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

  Future<List<_TerDet>> cargarDetalles(String ownerId, LatLng centro) async {
    final snap = await _db.collection('territories')
        .where('userId', isEqualTo: ownerId).get();
    final List<_TerDet> dets = [];
    for (final doc in snap.docs) {
      final data = doc.data();
      final rawPts = data['puntos'] as List<dynamic>?;
      List<LatLng> pts = [];
      double dist = 0;
      if (rawPts != null && rawPts.isNotEmpty) {
        pts = _parsePuntos(rawPts);
        final c = _centroide(pts);
        dist = Geolocator.distanceBetween(
            centro.latitude, centro.longitude, c.latitude, c.longitude) / 1000;
      }
      final tsV = data['ultima_visita'] as Timestamp?;
      final dias = tsV == null ? 0 : DateTime.now().difference(tsV.toDate()).inDays;
      dets.add(_TerDet(
        docId: doc.id, dist: dist, diasSinVisitar: dias,
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
        .snapshots()
        .listen((snap) {
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
          ownerColor:      ownerColorInt != null ? Color(ownerColorInt) : null,
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
      territoriosGlobales = List<GlobalTerritory>.from(cached);
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
        final t = GlobalTerritory.fromFirestore(doc);
        if (t != null) fromDb.add(t);
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

  Future<void> cargarCercanos(String myUid) async {
    setLoadingCercanos(true);
    try {
      final result = await _service.cargarGruposCercanos(centro, myUid);
      setGrupos(result);
    } catch (e) {
      setError('No se pudieron cargar los territorios cercanos');
    }
  }

  Future<void> cargarDetalles(String ownerId) async {
    if (_detallesCacheValido(ownerId)) { notifyListeners(); return; }
    try {
      final dets = await _service.cargarDetalles(ownerId, centro);
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

  final MapController                 _mapController = MapController();
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
  double _zoomGlobal = 2.5;

  // ── FIX: zoom y centro inicial compartidos entre ciudad y solitario ────────
  static const double _kInitialZoom = 14.0;

  static const LatLng _kGlobalCenter = LatLng(20.0, 0.0);

  // ── FIX: Estado del botón centrar (toggle: mi posición ↔ vista inicial) ───
  bool _fabCentradoEnUsuario = false;

  // Toggle mapa claro/oscuro
  bool _mapaOscuro = false;

  // ── Modo solitario — barrios OSM ──────────────────────────────────────────
  List<_BarrioData> _barriosCercanos  = [];
  bool _barriosCargados               = false;
  bool _cargandoBarrios               = false;
  String? _errorBarrios;
  // Future que completa cuando _resolverCentro() termina de obtener el GPS real.
  // _activarModoSolitario() lo espera para no consultar Overpass con coords por defecto.
  Future<void>? _centroListo;

  // ── Filtro de mapa + actividad ────────────────────────────────────────────
  _FiltroMapa _filtroActivo = _FiltroMapa.todos;
  Future<List<ActivityEntry>>? _feedFuture;
  final Map<String, List<Map<String, dynamic>>> _historialCache = {};

  // ── Modo Rutas ────────────────────────────────────────────────────────────
  List<RouteData> _misRutas        = [];
  bool            _cargandoRutas   = false;
  RouteData?      _rutaSeleccionada;

  @override
  void initState() {
    super.initState();
    _state = _MapState();
    _state.addListener(_onErrorCheck);
    _state.addListener(_recalcularPorcentajesBarrios);

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

    _initData();
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
    final misTers = _state.territorios.where((t) => t.esMio).toList();
    bool changed = false;
    for (final barrio in _barriosCercanos) {
      double areaCubierta = 0.0;
      for (final ter in misTers) {
        if (_puntoEnPoligonoSol(ter.centro, barrio.puntos)) {
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
  }

  @override
  void dispose() {
    _state.removeListener(_onErrorCheck);
    _state.removeListener(_recalcularPorcentajesBarrios);
    _state.dispose();
    _pulseCtrl.dispose();
    _selCtrl.dispose();
    _sheetEntryCtrl.dispose();
    _toggleCtrl.dispose();
    _globalEntryCtrl.dispose();
    _presenciaStream?.cancel();
    _desafioStreamRetador?.cancel();
    _desafioStreamRetado?.cancel();
    _sheetCtrl.dispose();
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

  Future<void> _initData() async {
    _centroListo = _resolverCentro();
    await _centroListo;
    // Listeners arrancan en cuanto tenemos el centro — no esperan a los territorios
    _escucharJugadores();
    _escucharDesafio();
    await _cargarTerritorios();
    await _rellenarConFantasmas();
    if (!mounted) return;
    _sheetEntryCtrl.forward();
  }

  Future<void> _resolverCentro() async {
    if (widget.centroInicial != null) {
      _state.setCentro(widget.centroInicial!);
      return;
    }
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));
        _state.setCentro(LatLng(pos.latitude, pos.longitude));
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
    _state.setLoadingTerritorios(true);
    try {
      // Pre-leer el modo guardado evita la race condition entre _initData()
      // (que corre sin await) y _activarModoSolitario() (postFrameCallback):
      // sin esto, _initData cargaría competitivo aunque el modo sea solitario.
      final savedMode = GameStateService.instance.currentMode;
      final modo = (_state.modoSolitario || savedMode == 'solitario') ? 'solitario' : 'competitivo';

      // Usar cache compartido si sigue siendo válido
      final cached = modo == 'solitario'
          ? GameStateService.instance.getSolitarioTerritories()
          : GameStateService.instance.getCompetitiveTerritories();
      if (cached != null) {
        _state.setTerritorios(List<TerritoryData>.from(cached));
        return;
      }

      final lista = await TerritoryService.cargarTodosLosTerritorios(
          centro: _state.centro, modo: modo);
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
    final centro = _state.centro;
    if (centro.latitude == 0 && centro.longitude == 0) return;
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
    _presenciaStream = FirebaseFirestore.instance
        .collection('presencia_activa')
        .where('lat', isGreaterThan: latMin)
        .where('lat', isLessThan: latMax)
        .snapshots()
        .listen((snap) {
      final nuevos = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        if (doc.id == _uid) continue;
        final d = doc.data();
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
      _mapController.move(_kGlobalCenter, 2.5);
      setState(() => _zoomGlobal = 2.5);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sheetCtrl.isAttached) {
          _sheetCtrl.animateTo(0.35,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut);
        }
      });
    } else {
      _toggleCtrl.reverse();
      // FIX: volver al zoom y centro inicial igual al de ciudad
      _mapController.move(_state.centro, _kInitialZoom);
    }
  }

  void _onTerritoryTap(TerritoryData t) {
    HapticFeedback.lightImpact();
    _state.seleccionarTerritorio(t);
    _selCtrl.forward(from: 0);
    _mapController.move(t.centro, 15);
  }

  void _onGlobalTerritoryTap(GlobalTerritory t) {
    HapticFeedback.lightImpact();
    _state.seleccionarTerritoryGlobal(t);
    _selCtrl.forward(from: 0);
    _mapController.move(t.center, 5);
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

        Positioned.fill(child: _buildMapa()),

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
                key: ValueKey(isGlobal),
                controller: _sheetCtrl,
                initialChildSize: 0.4,
                minChildSize: 0.08,
                maxChildSize: 0.75,
                snap: true,
                snapSizes: isGlobal
                    ? const [0.08, 0.35, 0.75]
                    : const [0.08, 0.13, 0.4, 0.75],
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
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 2),
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
                      AnimatedBuilder(
                        animation: _toggleCtrl,
                        builder: (_, __) => Text(
                          _toggleAnim.value > 0.5
                              ? 'MAPA GLOBAL'
                              : 'MAPA DE CIUDAD',
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

            if (!_state.modoGlobal && (det > 0 || pel > 0)) ...[
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: _kBg.withValues(alpha: 0.82),
            border: Border.all(color: _kBorder2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [

            // ── MI CIUDAD ─────────────────────────────────────────────────
            Expanded(child: GestureDetector(
              onTap: isCiudad ? null : () async {
                if (isGlobal) _toggleModo();           // global → ciudad
                if (isSolitario) {
                  _state.setModoSolitario(false);
                  await _cargarTerritorios();
                }
                // FIX: volver al zoom inicial de ciudad
                _mapController.move(_state.centro, _kInitialZoom);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isCiudad
                      ? _kRed.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(7)),
                  border: isCiudad
                      ? Border.all(color: _kRed.withValues(alpha: 0.4))
                      : null,
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.location_on_rounded,
                      color: isCiudad ? _kBlue : _kSub, size: 13),
                  const SizedBox(width: 5),
                  Text('COMPETITIVO',
                      style: _raj(9, FontWeight.w900,
                          isCiudad ? _kWhite : _kSub, spacing: 1.0)),
                ]),
              ),
            )),

            Container(width: 1, height: 30, color: _kBorder2),

            // ── SOLITARIO ─────────────────────────────────────────────────
            Expanded(child: GestureDetector(
              onTap: isSolitario ? null : () async {
                if (isGlobal) _toggleModo();           // global → ciudad primero
                await _activarModoSolitario();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isSolitario
                      ? _kSafe.withValues(alpha: 0.12)
                      : Colors.transparent,
                  border: isSolitario
                      ? Border.all(color: _kSafe.withValues(alpha: 0.4))
                      : null,
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.explore_rounded,
                      size: 12, color: isSolitario ? _kSafe : _kSub),
                  const SizedBox(width: 5),
                  Text('SOLITARIO',
                      style: _raj(9, FontWeight.w900,
                          isSolitario ? _kSafe : _kSub, spacing: 1.0)),
                ]),
              ),
            )),

            Container(width: 1, height: 30, color: _kBorder2),

            // ── GUERRA GLOBAL ─────────────────────────────────────────────
            Expanded(child: GestureDetector(
              onTap: isGlobal ? null : () {
                if (isSolitario) _state.setModoSolitario(false);
                if (isRutas)    _state.setModoRutas(false);
                _toggleModo();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isGlobal
                      ? _kGold.withValues(alpha: 0.12)
                      : Colors.transparent,
                  border: isGlobal
                      ? Border.all(color: _kGold.withValues(alpha: 0.4))
                      : null,
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.public_rounded,
                      size: 12, color: isGlobal ? _kGoldLight : _kSub),
                  const SizedBox(width: 5),
                  Text('GLOBAL',
                      style: _raj(9, FontWeight.w900,
                          isGlobal ? _kGoldLight : _kSub, spacing: 1.0)),
                  if (isGlobal && _state.territoriosMios > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: _kGold.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text('${_state.territoriosMios}/5',
                          style: _raj(8, FontWeight.w900, _kGold)),
                    ),
                  ],
                ]),
              ),
            )),

            Container(width: 1, height: 30, color: _kBorder2),

            // ── RUTAS ─────────────────────────────────────────────────────
            Expanded(child: GestureDetector(
              onTap: isRutas ? null : () async {
                if (isGlobal)    _toggleModo();
                if (isSolitario) _state.setModoSolitario(false);
                await _activarModoRutas();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isRutas
                      ? const Color(0xFF6A4A9B).withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(7)),
                  border: isRutas
                      ? Border.all(color: const Color(0xFF6A4A9B).withValues(alpha: 0.5))
                      : null,
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.route_rounded,
                      size: 12,
                      color: isRutas ? const Color(0xFF9B72CF) : _kSub),
                  const SizedBox(width: 5),
                  Text('RUTAS',
                      style: _raj(9, FontWeight.w900,
                          isRutas ? const Color(0xFF9B72CF) : _kSub,
                          spacing: 1.0)),
                ]),
              ),
            )),

          ]),
        ),
      ),
    );
  }

  // ==========================================================================
  // MODO SOLITARIO — barrios OSM
  // ==========================================================================
  Future<void> _activarModoSolitario() async {
    await _centroListo; // garantiza GPS real antes de consultar Overpass
    _state.setModoSolitario(true);
    _mapController.move(_state.centro, _kInitialZoom);
    await _cargarTerritorios();
    _recalcularPorcentajesBarrios(); // recalcular con barrios ya en caché
    // Resetear si la carga anterior no encontró resultados
    if (_barriosCargados && _barriosCercanos.isEmpty) {
      setState(() { _barriosCargados = false; });
    }
    if (!_barriosCargados && !_cargandoBarrios) {
      await _cargarBarriosSolitario(_state.centro);
      _recalcularPorcentajesBarrios(); // recalcular tras cargar barrios por primera vez
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
      const delta = 0.045; // ~5 km

      final bbox = '${lat - delta},${lng - delta},${lat + delta},${lng + delta}';
      final url = Uri.parse(
        'https://overpass-api.de/api/interpreter?data='
        '[out:json][timeout:25];'
        '('
        '  way["place"~"suburb|neighbourhood|quarter|city_block"]($bbox);'
        '  relation["place"~"suburb|neighbourhood|quarter"]($bbox);'
        '  relation["boundary"="administrative"]["admin_level"~"^(9|10|11)\$"]($bbox);'
        '  way["boundary"="administrative"]["admin_level"~"^(9|10|11)\$"]($bbox);'
        ');'
        'out geom;',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 12));
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
          for (final member in members) {
            final m = member as Map<String, dynamic>;
            if (m['role'] == 'outer' && m['geometry'] != null) {
              final geom = m['geometry'] as List<dynamic>;
              puntos = geom.map((g) {
                final gm = g as Map<String, dynamic>;
                return LatLng((gm['lat'] as num).toDouble(),
                              (gm['lon'] as num).toDouble());
              }).toList();
              break;
            }
          }
        }

        if (puntos.length < 4) continue;
        final area = TerritoryService.calcularAreaM2(puntos);
        if (area < 10000) continue;   // muy pequeño (< 0.01 km²)
        if (area > 8000000) continue; // demasiado grande (> 8 km²) = municipio/provincia

        // Calcular % cubierto con territorios propios
        final misTers = _state.territorios.where((t) => t.esMio).toList();
        double areaCubierta = 0.0;
        for (final ter in misTers) {
          if (_puntoEnPoligonoSol(ter.centro, puntos)) {
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

      if (!mounted) return;
      setState(() {
        _barriosCercanos = barrios;
        _barriosCargados = true;
        _cargandoBarrios = false;
      });
    } catch (e) {
      final msg = e.toString().contains('TimeoutException')
          ? 'Tiempo agotado · Reintenta'
          : 'Sin conexión · Reintenta';
      if (mounted) setState(() {
        _cargandoBarrios = false;
        _errorBarrios = msg;
      });
    }
  }

  // ==========================================================================
  // MODO RUTAS
  // ==========================================================================
  Future<void> _activarModoRutas() async {
    _state.setModoRutas(true);
    await _cargarMisRutas();
  }

  Future<void> _cargarMisRutas() async {
    if (_cargandoRutas) return;
    if (mounted) setState(() => _cargandoRutas = true);
    try {
      final rutas = await RouteService.cargarMisRutas();
      if (!mounted) return;
      setState(() {
        _misRutas      = rutas;
        _cargandoRutas = false;
      });
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

  // FIX: el mapa solitario ahora usa el mismo MapController y mismo zoom inicial
  Widget _buildMapaSolitario() {
    return ListenableBuilder(
      listenable: _state,
      builder: (_, __) {
        final territorios = _filteredTerritorios(_state.territorios);
        return Stack(children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _state.centro,
              initialZoom: _kInitialZoom,   // FIX: mismo zoom que ciudad
              minZoom: 3, maxZoom: 19,
              cameraConstraint: CameraConstraint.containCenter(
                bounds: LatLngBounds(
                  const LatLng(-85.0, -180.0),
                  const LatLng(85.0, 180.0),
                ),
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: _mapaOscuro ? _kMapboxDarkUrl : _kMapboxUrl,
                userAgentPackageName: 'com.runner_risk.app',
                tileDimension: 256,
                keepBuffer: 4,
                panBuffer: 2,
                maxNativeZoom: 19,
              ),

              // Polígonos de barrios OSM
              if (_barriosCercanos.isNotEmpty)
                PolygonLayer(
                  polygons: _barriosCercanos.map((b) {
                    final pct = b.porcentajeCubierto;
                    final Color color = pct >= 1.0
                        ? _kSafe
                        : pct > 0 ? _kWarn : _kDim;
                    return Polygon(
                      points: b.puntos,
                      color: color.withValues(alpha: pct > 0 ? 0.16 : 0.06),
                      borderColor: _mapaOscuro
                          ? Colors.white.withValues(alpha: 0.80)
                          : const Color(0xFF1A1A1A).withValues(alpha: 0.70),
                      borderStrokeWidth: 2.5,
                    );
                  }).toList(),
                ),

              // Zonas objetivo solitario (todas, no conquistadas aún)
              if (_state.modoSolitario && territorios.any((t) => !t.esMio))
                PolygonLayer(
                  polygons: territorios.where((t) => !t.esMio).map((t) => Polygon(
                    points: t.puntos,
                    color: Colors.white.withValues(alpha: 0.04),
                    borderColor: Colors.white.withValues(alpha: 0.35),
                    borderStrokeWidth: 1.5,
                  )).toList(),
                ),

              // Halo táctico mínimo — propios
              if (territorios.any((t) => t.esMio))
                PolygonLayer(
                  polygons: territorios.where((t) => t.esMio).map((t) {
                    final decay = _decayFactor(t);
                    return Polygon(
                      points: t.puntos,
                      color: Colors.transparent,
                      borderColor: t.color.withValues(alpha: 0.08 * decay),
                      borderStrokeWidth: 6.0,
                    );
                  }).toList(),
                ),

              // Territorios propios encima
              if (territorios.isNotEmpty)
                PolygonLayer(
                  polygons: territorios.where((t) => t.esMio).map((t) {
                    final decay = _decayFactor(t);
                    final frio  = t.ultimaVisita != null &&
                        DateTime.now().difference(t.ultimaVisita!).inDays >= 7;
                    return Polygon(
                      points: t.puntos,
                      color: frio
                          ? Colors.grey.withValues(alpha: 0.14)
                          : t.color.withValues(alpha: 0.30 * decay),
                      borderColor: frio
                          ? Colors.grey.withValues(alpha: 0.60)
                          : t.color.withValues(alpha: (0.90 * decay).clamp(0.0, 1.0)),
                      borderStrokeWidth: 2.8,
                    );
                  }).toList(),
                ),

              // Marcadores de alerta en territorios fríos (7+ días sin visitar)
              if (territorios.any((t) => t.esMio && t.ultimaVisita != null &&
                  DateTime.now().difference(t.ultimaVisita!).inDays >= 7))
                MarkerLayer(
                  markers: territorios.where((t) => t.esMio &&
                      t.ultimaVisita != null &&
                      DateTime.now().difference(t.ultimaVisita!).inDays >= 7)
                    .map((t) => Marker(
                      point: t.centro,
                      width: 22, height: 22,
                      child: Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.4),
                            blurRadius: 6)],
                        ),
                        child: const Icon(Icons.warning_amber_rounded,
                            color: Colors.white, size: 13),
                      ),
                    )).toList(),
                ),

              // Marcador de posición del usuario
              MarkerLayer(markers: [
                Marker(
                  point: _state.centro, width: 22, height: 22,
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: _kRed, width: 2),
                      boxShadow: [BoxShadow(
                          color: _kRed.withValues(alpha: 0.50),
                          blurRadius: 8, spreadRadius: 1)],
                    ),
                  ),
                ),
              ]),

              // Etiquetas de barrios
              if (_barriosCercanos.isNotEmpty)
                MarkerLayer(
                  markers: _barriosCercanos.map((b) {
                    final pct = b.porcentajeCubierto;
                    final Color color = pct >= 1.0
                        ? _kSafe : pct > 0 ? _kWarn : _kDim;
                    return Marker(
                      point: b.centro,
                      width: 120, height: 40,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(b.nombre,
                            textAlign: TextAlign.center,
                            style: _raj(9, FontWeight.w700, color, spacing: 0.5),
                          ),
                          if (pct > 0)
                            Text('${(pct * 100).toInt()}%',
                              style: _raj(8, FontWeight.w600, color)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),

          // Indicador de carga de barrios
          if (_cargandoBarrios)
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
                    Text('Cargando barrios…',
                        style: _raj(10, FontWeight.w600, _kSub)),
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
  }

  // ==========================================================================
  // MAPA
  // ==========================================================================
  Widget _buildMapa() {
    final tieneRuta = widget.ruta.length > 1 && widget.mostrarRuta;
    return ListenableBuilder(
      listenable: _state,
      builder: (_, __) {
        if (_state.modoGlobal)    return _buildMapaGlobal();
        if (_state.modoSolitario) return _buildMapaSolitario();
        if (_state.modoRutas)     return _buildMapaRutas();
        return _buildMapaCiudad(tieneRuta);
      },
    );
  }

  Widget _buildMapaCiudad(bool tieneRuta) {
    final territorios  = _filteredTerritorios(_state.territorios);
    final seleccionado = _state.territorioSeleccionado;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _state.centro,
        initialZoom: _kInitialZoom,   // FIX: zoom inicial compartido
        minZoom: 3, maxZoom: 19,
        cameraConstraint: CameraConstraint.containCenter(
          bounds: LatLngBounds(
            const LatLng(-85.0, -180.0),
            const LatLng(85.0, 180.0),
          ),
        ),
        onTap: (_, __) { if (seleccionado != null) _cerrarSeleccion(); },
        onMapReady: () {
          if (tieneRuta) {
            try {
              _mapController.fitCamera(CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(widget.ruta),
                  padding: const EdgeInsets.all(60)));
            } catch (_) {}
          }
        },
      ),
      children: [
        TileLayer(
            urlTemplate: _mapaOscuro ? _kMapboxDarkUrl : _kMapboxUrl,
            userAgentPackageName: 'com.runner_risk.app',
            tileDimension: 256,
            keepBuffer: 4,
            panBuffer: 2,
            maxNativeZoom: 19),

        // Halo táctico mínimo — solo territorios propios
        if (territorios.any((t) => t.esMio))
          PolygonLayer(
            polygons: territorios.where((t) => t.esMio).map((t) => Polygon(
              points: t.puntos,
              color: Colors.transparent,
              borderColor: t.color.withValues(alpha: 0.08),
              borderStrokeWidth: 6.0,
            )).toList(),
          ),

        // Halo rojo — territorios rivales en estado crítico
        if (territorios.any((t) => !t.esMio && t.estadoHp == EstadoHp.critico))
          PolygonLayer(
            polygons: territorios
                .where((t) => !t.esMio && t.estadoHp == EstadoHp.critico)
                .map((t) => Polygon(
                  points: t.puntos,
                  color: Colors.transparent,
                  borderColor: const Color(0xFFCC2222).withValues(alpha: 0.22),
                  borderStrokeWidth: 7.0,
                )).toList(),
          ),

        if (territorios.isNotEmpty)
          GestureDetector(
            onTapUp: (details) {
              final tapLatLng =
                  _mapController.camera.offsetToCrs(details.localPosition);
              TerritoryData? encontrado;
              for (final t in territorios) {
                if (_pointInPolygon(tapLatLng, t.puntos)) {
                  encontrado = t;
                  break;
                }
              }
              if (encontrado == null) {
                double minDist = double.infinity;
                for (final t in territorios) {
                  final d = Geolocator.distanceBetween(
                      tapLatLng.latitude, tapLatLng.longitude,
                      t.centro.latitude, t.centro.longitude);
                  if (d < minDist && d < 200) {
                    minDist = d;
                    encontrado = t;
                  }
                }
              }
              if (encontrado != null) _onTerritoryTap(encontrado);
            },
            child: PolygonLayer(
              polygons: territorios.map((t) {
                final bool sel = seleccionado?.docId == t.docId;
                final double bWidth = sel
                    ? 3.0
                    : t.esMio
                        ? 2.8
                        : switch (t.estadoHp) {
                            EstadoHp.saludable => 1.6,
                            EstadoHp.danado    => 2.0,
                            EstadoHp.critico   => 2.4,
                          };
                return Polygon(
                  points: t.puntos,
                  color: sel
                      ? t.color.withValues(alpha: 0.40)
                      : t.color.withValues(alpha: t.opacidadRelleno),
                  borderColor: sel
                      ? t.color
                      : t.color.withValues(alpha: t.opacidadBorde),
                  borderStrokeWidth: bWidth,
                );
              }).toList(),
            ),
          ),

        if (tieneRuta)
          PolylineLayer(polylines: [
            Polyline(points: widget.ruta, strokeWidth: 4, color: _kRed),
          ]),

        MarkerLayer(markers: [
          Marker(
            point: _state.centro, width: 40, height: 40,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kRed.withValues(alpha: 0.12),
                border: Border.all(color: _kRed.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Center(
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: _kRed, width: 2.5),
                    boxShadow: [BoxShadow(
                        color: _kRed.withValues(alpha: 0.55),
                        blurRadius: 10, spreadRadius: 1)],
                  ),
                ),
              ),
            ),
          ),
        ]),

        if (territorios.isNotEmpty)
          MarkerLayer(
            markers: territorios.map((t) => Marker(
              point: t.centro, width: 72, height: 22,
              child: GestureDetector(
                onTap: () => _onTerritoryTap(t),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: seleccionado?.docId == t.docId
                          ? t.color
                          : t.color.withValues(alpha: 0.5),
                      width: seleccionado?.docId == t.docId ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    t.esMio ? '[ YO ]' : t.ownerNickname,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.color, fontSize: 8,
                      fontWeight: FontWeight.w800, letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            )).toList(),
          ),

        if (_state.jugadoresEnVivo.isNotEmpty)
          MarkerLayer(
            markers: _state.jugadoresEnVivo.entries.map((e) {
              final d = e.value;
              final lat = (d['lat'] as num?)?.toDouble();
              final lng = (d['lng'] as num?)?.toDouble();
              final color = d['color'] != null
                  ? Color(d['color'] as int)
                  : _kRed;
              final nick = d['nickname'] as String? ?? '';
              if (lat == null || lng == null) return null;
              return Marker(
                point: LatLng(lat, lng), width: 56, height: 60,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      border: Border.all(color: color.withValues(alpha: 0.7)),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      nick.length > 6
                          ? '${nick.substring(0, 6)}..'
                          : nick,
                      style: TextStyle(
                          color: color,
                          fontSize: 8,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                  Container(
                      width: 1.5,
                      height: 6,
                      color: color.withValues(alpha: 0.6)),
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Container(
                      width: 10 + 4 * _pulse.value,
                      height: 10 + 4 * _pulse.value,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5 * _pulse.value),
                            blurRadius: 12, spreadRadius: 3)
                        ],
                      ),
                    ),
                  ),
                ]),
              );
            }).whereType<Marker>().toList(),
          ),
      ],
    );
  }

  // ==========================================================================
  // MAPA RUTAS
  // ==========================================================================
  Widget _buildMapaRutas() {
    final selId = _rutaSeleccionada?.id;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _state.centro,
        initialZoom:   _kInitialZoom,
        minZoom: 3, maxZoom: 19,
        onTap: (_, __) => setState(() => _rutaSeleccionada = null),
      ),
      children: [
        TileLayer(
          urlTemplate:          _mapaOscuro ? _kMapboxDarkUrl : _kMapboxUrl,
          userAgentPackageName: 'com.runner_risk.app',
          tileDimension: 256,
          keepBuffer: 4,
          panBuffer:  2,
          maxNativeZoom: 19,
        ),
        if (_misRutas.isNotEmpty)
          PolylineLayer(
            polylines: _misRutas.map((r) {
              final selected = r.id == selId;
              return Polyline(
                points:       r.coords,
                color:        r.color.withValues(alpha: selected ? 1.0 : 0.65),
                strokeWidth:  selected ? 5.0 : 3.0,
              );
            }).toList(),
          ),
        // Marcador de inicio de cada ruta
        MarkerLayer(
          markers: _misRutas
              .where((r) => r.coords.isNotEmpty)
              .map((r) => Marker(
                    point:  r.coords.first,
                    width:  28,
                    height: 28,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _rutaSeleccionada = r);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color:  r.color,
                          shape:  BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                        ),
                        child: const Icon(Icons.route_rounded, color: Colors.white, size: 13),
                      ),
                    ),
                  ))
              .toList(),
        ),

        // Posición del usuario
        MarkerLayer(markers: [
          Marker(
            point: _state.centro, width: 40, height: 40,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kRed.withValues(alpha: 0.12),
                border: Border.all(color: _kRed.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Center(
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: _kRed, width: 2.5),
                    boxShadow: [BoxShadow(
                        color: _kRed.withValues(alpha: 0.55),
                        blurRadius: 10, spreadRadius: 1)],
                  ),
                ),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  // ==========================================================================
  // MAPA GLOBAL
  // ==========================================================================
  Widget _buildMapaGlobal() {
    final sel = _state.territorioGlobalSeleccionado;
    return FadeTransition(
      opacity: _globalEntryAnim,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _kGlobalCenter,
          initialZoom: 2.5,
          minZoom: 1.5, maxZoom: 8,
          onTap: (_, __) { if (sel != null) _cerrarSeleccion(); },
          onPositionChanged: (position, hasGesture) {
            final newZoom = position.zoom;
            if ((newZoom - _zoomGlobal).abs() > 0.3) {
              setState(() => _zoomGlobal = newZoom);
            }
          },
        ),
        children: [
          TileLayer(
              urlTemplate: _kMapboxDarkUrl,
              userAgentPackageName: 'com.runner_risk.app',
              tileDimension: 256,
              keepBuffer: 4,
              panBuffer: 2,
              maxNativeZoom: 8),

          // Atmospheric deep-space overlay — tinta navy sobre dark-v11
          const ColorFiltered(
            colorFilter: ColorFilter.mode(Color(0x44000B28), BlendMode.srcOver),
            child: SizedBox.expand(),
          ),

          if (_state.loadingGlobal)
            const ColorFiltered(
              colorFilter:
                  ColorFilter.mode(Colors.black45, BlendMode.srcOver),
              child: SizedBox.expand(),
            ),

          if (!_state.loadingGlobal &&
              _state.territoriosGlobales.isNotEmpty) ...[

            // Capa de glow exterior — bloom neon sobre los bordes
            PolygonLayer(
              polygons: _state.territoriosGlobales.map((t) {
                final isMine = t.isMine;
                final baseColor = isMine
                    ? _kGold
                    : t.isOwned
                        ? t.displayColor
                        : _dificultadColor(t.difficultyLevel);
                return Polygon(
                  points: t.points,
                  color: Colors.transparent,
                  borderColor: baseColor.withValues(
                      alpha: isMine ? 0.30 : (t.isOwned ? 0.18 : 0.10)),
                  borderStrokeWidth: isMine ? 12.0 : (t.isOwned ? 8.0 : 5.0),
                );
              }).toList(),
            ),

            GestureDetector(
              onTapUp: (details) {
                final tapLatLng = _mapController.camera
                    .offsetToCrs(details.localPosition);
                GlobalTerritory? encontrado;
                for (final t in _state.territoriosGlobales) {
                  if (_pointInPolygon(tapLatLng, t.points)) {
                    encontrado = t;
                    break;
                  }
                }
                if (encontrado != null) _onGlobalTerritoryTap(encontrado);
              },
              child: PolygonLayer(
                polygons: _state.territoriosGlobales.map((t) {
                  final isSel  = sel?.id == t.id;
                  final isMine = t.isMine;
                  final baseColor = isMine
                      ? _kGold
                      : t.isOwned
                          ? t.displayColor
                          : _dificultadColor(t.difficultyLevel);

                  return Polygon(
                    points: t.points,
                    color: isSel
                        ? baseColor.withValues(alpha: 0.65)
                        : baseColor.withValues(alpha: isMine
                            ? 0.55
                            : (t.isOwned ? 0.38 : 0.28)),
                    borderColor: isSel
                        ? baseColor
                        : baseColor.withValues(alpha: isMine
                            ? 1.0
                            : (t.isOwned ? 0.92 : 0.75)),
                    borderStrokeWidth: isSel
                        ? 4.0
                        : isMine
                            ? 3.0
                            : (t.tier == TerritoryTier.legendario
                                ? 2.5
                                : 2.0),
                  );
                }).toList(),
              ),
            ),

            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => MarkerLayer(
                markers: _state.territoriosGlobales.map((t) {
                  final isSel  = sel?.id == t.id;
                  final isMine = t.isMine;
                  final Color baseColor = isMine
                      ? _kGold
                      : t.isOwned
                          ? (t.ownerColor ?? t.tierColor)
                          : _kDim;
                  final bool isLegend = t.tier == TerritoryTier.legendario;

                  final double glowR = isMine
                      ? 9.0 + 5.0 * _pulse.value
                      : (t.isOwned ? 5.0 : 0.0);
                  final double glowA = isMine
                      ? 0.30 + 0.18 * _pulse.value
                      : (t.isOwned ? 0.18 : 0.0);

                  // ── Modo lejano (zoom < 4) — anillo compacto ───────────
                  if (_zoomGlobal < 4.0) {
                    final double sz    = isSel ? 24.0 : (isLegend ? 22.0 : 19.0);
                    final double dotSz = isMine ? 7.0 : (t.isOwned ? 5.0 : 3.0);
                    return Marker(
                      point: t.center,
                      width: sz + glowR * 2 + 4,
                      height: sz + glowR * 2 + 4,
                      child: GestureDetector(
                        onTap: () => _onGlobalTerritoryTap(t),
                        child: Stack(alignment: Alignment.center, children: [
                          if (isMine || t.isOwned)
                            Container(
                              width: sz + glowR * 2,
                              height: sz + glowR * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(
                                  color: baseColor.withValues(alpha: glowA),
                                  blurRadius: glowR * 2,
                                )],
                              ),
                            ),
                          Container(
                            width: sz,
                            height: sz,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF08080B).withValues(alpha: 0.92),
                              border: Border.all(
                                color: isSel
                                    ? baseColor
                                    : baseColor.withValues(alpha:
                                        isMine ? 0.92 : (t.isOwned ? 0.80 : 0.55)),
                                width: isSel ? 2.0 : (isMine ? 1.8 : 1.2),
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: dotSz, height: dotSz,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: baseColor.withValues(
                                      alpha: t.isOwned ? 1.0 : 0.60),
                                ),
                              ),
                            ),
                          ),
                          if (isMine)
                            Positioned(
                              top: 1, right: 1,
                              child: Container(
                                width: 7, height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _kGold,
                                  boxShadow: [BoxShadow(
                                    color: _kGold.withValues(alpha: 0.70),
                                    blurRadius: 4,
                                  )],
                                ),
                              ),
                            ),
                        ]),
                      ),
                    );
                  }

                  // ── Modo cercano (zoom >= 4) — anillo + etiqueta mínima ─
                  final double sz    = isSel ? (isLegend ? 30.0 : 26.0) : (isLegend ? 26.0 : 22.0);
                  final double dotSz = isMine ? 9.0 : (t.isOwned ? 6.0 : 3.0);
                  final double fs    = isLegend ? 8.0 : 7.0;

                  return Marker(
                    point: t.center,
                    width: isLegend ? 108.0 : 96.0,
                    height: isLegend ? 88.0 : 74.0,
                    child: GestureDetector(
                      onTap: () => _onGlobalTerritoryTap(t),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(alignment: Alignment.center, children: [
                            if (isMine || t.isOwned || isLegend)
                              Container(
                                width: sz + glowR * 2,
                                height: sz + glowR * 2,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(
                                    color: baseColor.withValues(alpha: glowA),
                                    blurRadius: glowR * 2,
                                  )],
                                ),
                              ),
                            Container(
                              width: sz,
                              height: sz,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF08080B).withValues(alpha: 0.92),
                                border: Border.all(
                                  color: isSel
                                      ? baseColor
                                      : baseColor.withValues(alpha:
                                          isMine ? 0.92 : (t.isOwned ? 0.80 : 0.55)),
                                  width: isSel ? 2.0 : (isMine ? 1.8 : (isLegend ? 1.5 : 1.2)),
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  width: dotSz, height: dotSz,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: baseColor.withValues(
                                        alpha: t.isOwned ? 1.0 : 0.60),
                                  ),
                                ),
                              ),
                            ),
                            if (isMine)
                              Positioned(
                                top: 1, right: 1,
                                child: Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _kGold,
                                    boxShadow: [BoxShadow(
                                      color: _kGold.withValues(alpha: 0.70),
                                      blurRadius: 4,
                                    )],
                                  ),
                                ),
                              ),
                          ]),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF08080B).withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: isMine
                                    ? _kGold.withValues(alpha: 0.55)
                                    : t.isOwned
                                        ? baseColor.withValues(alpha: 0.38)
                                        : Colors.white.withValues(alpha: 0.08),
                                width: 0.8,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  t.epicName.length > 13
                                      ? '${t.epicName.substring(0, 12)}…'
                                      : t.epicName,
                                  style: GoogleFonts.rajdhani(
                                    color: isMine
                                        ? _kGoldLight
                                        : (t.isOwned ? Colors.white : _kSub),
                                    fontSize: fs,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  isMine
                                      ? 'TÚ'
                                      : t.isOwned
                                          ? (t.ownerNickname ?? '?')
                                          : 'LIBRE',
                                  style: GoogleFonts.rajdhani(
                                    color: isMine
                                        ? _kGold
                                        : t.isOwned
                                            ? baseColor.withValues(alpha: 0.85)
                                            : _kDim,
                                    fontSize: 6.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_zoomGlobal >= 5.0) ...[
                                  const SizedBox(height: 1),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${t.difficultyLevel}/10  ',
                                        style: TextStyle(
                                          color: _dificultadColor(t.difficultyLevel),
                                          fontSize: fs - 2,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '${t.kmRequired.toStringAsFixed(1)}km',
                                        style: TextStyle(
                                          color: _kSub,
                                          fontSize: fs - 2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          if (_state.loadingGlobal)
            MarkerLayer(markers: [
              Marker(
                point: _kGlobalCenter, width: 80, height: 80,
                child: const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: _kGold)),
              ),
            ]),
        ],
      ),
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
        _mapController.move(_kGlobalCenter, 2.5);
        setState(() => _zoomGlobal = 2.5);
        return;
      }

      if (_fabCentradoEnUsuario) {
        // Segunda pulsación: zoom out a vista ciudad
        _mapController.move(_state.centro, 12.0);
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
            _mapController.move(
                LatLng(pos.latitude, pos.longitude), 15.0);
            setState(() => _fabCentradoEnUsuario = true);
          }
        } catch (_) {
          // Sin permiso: simplemente centra en el centro conocido
          _mapController.move(_state.centro, 15.0);
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
                          _mapController.move(t.centro, 16);
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
            modeColor: _kSub,
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
          if (_state.desafioActivo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _buildBannerDesafio(_state.desafioActivo!),
            ),
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
    final barriosOrdenados = List<_BarrioData>.from(_barriosCercanos)
      ..sort((a, b) => b.porcentajeCubierto.compareTo(a.porcentajeCubierto));
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
              modeColor: _kSub,
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
            else if (barriosOrdenados.isNotEmpty) ...[
              _shSectionTitle('Zonas cercanas'),
              ...barriosOrdenados.map(_shBarrioCell),
            ] else if (_barriosCargados)
              _shEmptyState(Icons.explore_rounded, 'Sin zonas cercanas',
                  'Intenta desplazarte a una zona urbana')
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
            modeColor: _kSub,
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
          _mapController.move(r.coords.first, 14.5);
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
        _mapController.move(b.centro, 13.5);
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
        _state.cargarCercanos(_uid ?? '');
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
                  await _state.cargarDetalles(g.ownerId);
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
    Color c = _kSafe;
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
            await _state.cargarDetalles(det.ownerId);
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

  Widget _buildBannerDesafio(Map<String, dynamic> data) {
    final bool soyR = data['retadorId'] == _uid;
    final String rival = soyR
        ? (data['retadoNick'] ?? 'Rival')
        : (data['retadorNick'] ?? 'Rival');
    final int misPts = soyR
        ? (data['puntosRetador'] as num? ?? 0).toInt()
        : (data['puntosRetado'] as num? ?? 0).toInt();
    final int rivalPts = soyR
        ? (data['puntosRetado'] as num? ?? 0).toInt()
        : (data['puntosRetador'] as num? ?? 0).toInt();
    final int apuesta = (data['apuesta'] as num? ?? 0).toInt();
    final Timestamp? finTs = data['fin'] as Timestamp?;
    final bool ganando = misPts > rivalPts; // empate → gana el retado (defensor)

    String tiempo = '';
    if (finTs != null) {
      final diff = finTs.toDate().difference(DateTime.now());
      tiempo = diff.isNegative
          ? 'FINALIZADO'
          : diff.inHours > 0
              ? '${diff.inHours}h ${diff.inMinutes.remainder(60)}m'
              : '${diff.inMinutes}m';
    }
    final int total = misPts + rivalPts;
    final double pct = total > 0 ? misPts / total : 0.5;

    return Container(
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.04),
        border: Border.all(color: _kBorder2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 3,
          decoration: const BoxDecoration(
            color: _kRed,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              bottomLeft: Radius.circular(4),
            ),
          ),
        ),
        Expanded(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 14, 8),
              child: Row(children: [
                const Icon(Icons.sports_rounded, size: 14, color: _kRed),
                const SizedBox(width: 8),
                Text('DESAFÍO ACTIVO',
                    style:
                        _raj(9, FontWeight.w900, _kRed, spacing: 2)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      border: Border.all(color: _kBorder2),
                      borderRadius: BorderRadius.circular(3)),
                  child: Text(tiempo,
                      style:
                          _raj(9, FontWeight.w700, _kText, spacing: 1))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 14, 0),
              child: Row(children: [
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('TÚ',
                      style: _raj(7, FontWeight.w700, _kSub,
                          spacing: 2)),
                  Text('$misPts',
                      style: _raj(22, FontWeight.w900,
                          ganando ? _kWhite : _kSub, height: 1)),
                ])),
                Column(children: [
                  Text('VS',
                      style: _raj(10, FontWeight.w900, _kDim,
                          spacing: 2)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.monetization_on_rounded,
                        size: 10, color: _kGoldDim),
                    const SizedBox(width: 2),
                    Text('$apuesta',
                        style: _raj(9, FontWeight.w700, _kText)),
                  ]),
                ]),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                  Text(rival.toString().toUpperCase(),
                      style: _raj(7, FontWeight.w700, _kSub,
                          spacing: 2)),
                  Text('$rivalPts',
                      style: _raj(22, FontWeight.w900,
                          !ganando ? _kWhite : _kSub, height: 1)),
                ])),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 8, 14, 12),
              child: Stack(children: [
                Container(height: 3, color: _kBorder2),
                FractionallySizedBox(
                    widthFactor: pct.clamp(0.0, 1.0),
                    child: Container(height: 3, color: _kRed)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

// =============================================================================
// DIÁLOGO RENOMBRAR
// =============================================================================
class _DialogoRenombrar extends StatefulWidget {
  final String nombreActual;
  final Future<void> Function(String) onGuardar;
  const _DialogoRenombrar(
      {required this.nombreActual, required this.onGuardar});

  @override
  State<_DialogoRenombrar> createState() => _DialogoRenombrarState();
}

class _DialogoRenombrarState extends State<_DialogoRenombrar> {
  late final TextEditingController _ctrl;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.nombreActual);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _guardar() async {
    final nombre = _ctrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'El nombre no puede estar vacío');
      return;
    }
    if (nombre.length > 30) {
      setState(() => _error = 'Máximo 30 caracteres');
      return;
    }
    setState(() { _guardando = true; _error = null; });
    try {
      await widget.onGuardar(nombre);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kSurface,
          border: Border.all(color: _kGold.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: _kGold.withValues(alpha: 0.08), blurRadius: 30),
            const BoxShadow(color: Colors.black87, blurRadius: 20),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
                color: _kGold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _kGold.withValues(alpha: 0.4))),
            child: const Icon(Icons.edit_rounded,
                color: _kGold, size: 22)),
          const SizedBox(height: 16),
          Text('NOMBRE DEL TERRITORIO',
              style: _raj(15, FontWeight.w900, _kWhite, spacing: 1.5)),
          const SizedBox(height: 6),
          Text(
            'Este nombre será visible para todos en el mapa.',
            textAlign: TextAlign.center,
            style: _raj(11, FontWeight.w500, _kSub, height: 1.5)),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: _kBg,
              border: Border.all(
                  color: _error != null
                      ? _kRed.withValues(alpha: 0.6)
                      : _kGold.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(6)),
            child: TextField(
              controller: _ctrl, maxLength: 30, autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: _raj(14, FontWeight.w700, _kWhite),
              cursorColor: _kGold,
              decoration: InputDecoration(
                hintText: 'Ej: La Cuesta del Infierno',
                hintStyle: _raj(13, FontWeight.w500, _kDim),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: InputBorder.none,
                counterStyle: _raj(10, FontWeight.w500, _kSub)),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _guardar(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: _kRed, size: 12),
                const SizedBox(width: 4),
                Text(_error!, style: _raj(10, FontWeight.w600, _kRed)),
              ]),
            ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(color: _kBorder,
                    borderRadius: BorderRadius.circular(6)),
                child: Center(child: Text('CANCELAR',
                    style: _raj(12, FontWeight.w800, _kText,
                        spacing: 1)))),
            )),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: _guardando ? null : _guardar,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                    color: _kGold.withValues(alpha: 0.15),
                    border:
                        Border.all(color: _kGold.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(6)),
                child: Center(child: _guardando
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: _kGold))
                    : Text('GUARDAR',
                        style: _raj(12, FontWeight.w900, _kGold,
                            spacing: 1)))),
            )),
          ]),
        ]),
      ),
    );
  }
}

// =============================================================================
// DIÁLOGOS CONQUISTA
// =============================================================================
class _DialogoConfirmarConquista extends StatelessWidget {
  final String ownerNick;
  final int diasSinVisitar;
  const _DialogoConfirmarConquista(
      {required this.ownerNick, required this.diasSinVisitar});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kSurface,
          border: Border.all(color: _kRed.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: _kRed.withValues(alpha: 0.1), blurRadius: 30),
            const BoxShadow(color: Colors.black87, blurRadius: 20),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _kRed.withValues(alpha: 0.4))),
            child: const Icon(Icons.sports_kabaddi_rounded,
                color: _kRed, size: 24)),
          const SizedBox(height: 16),
          Text('¿CONQUISTAR?',
              style: _raj(18, FontWeight.w900, _kWhite, spacing: 2)),
          const SizedBox(height: 8),
          Text(
            'Territorio de ${ownerNick.toUpperCase()}\n'
            '$diasSinVisitar días sin visitar',
            textAlign: TextAlign.center,
            style: _raj(12, FontWeight.w600, _kSub, height: 1.5)),
          const SizedBox(height: 6),
          Text(
            'Debes estar físicamente a menos\nde 200 m del territorio.',
            textAlign: TextAlign.center,
            style: _raj(11, FontWeight.w500, _kDim, height: 1.5)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(color: _kBorder,
                    borderRadius: BorderRadius.circular(6)),
                child: Center(child: Text('CANCELAR',
                    style: _raj(12, FontWeight.w800, _kText,
                        spacing: 1)))),
            )),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: () => Navigator.of(context).pop(true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                    color: _kRed.withValues(alpha: 0.15),
                    border: Border.all(color: _kRed.withValues(alpha: 0.6)),
                    borderRadius: BorderRadius.circular(6)),
                child: Center(child: Text('CONQUISTAR',
                    style: _raj(12, FontWeight.w900, _kRed,
                        spacing: 1)))),
            )),
          ]),
        ]),
      ),
    );
  }
}

class _DialogoConquistando extends StatelessWidget {
  const _DialogoConquistando();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _kSurface,
          border: Border.all(color: _kBorder2),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Colors.black87, blurRadius: 20),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
            width: 36, height: 36,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: _kRed)),
          const SizedBox(height: 16),
          Text('CONQUISTANDO...',
              style: _raj(14, FontWeight.w900, _kWhite, spacing: 2)),
          const SizedBox(height: 6),
          Text('Verificando posición y condiciones',
              style: _raj(10, FontWeight.w500, _kSub)),
        ]),
      ),
    );
  }
}