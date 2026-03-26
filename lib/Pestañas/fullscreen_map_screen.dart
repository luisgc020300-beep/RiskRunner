import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

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
const _kBg       = Color(0xFF060608);
const _kSurface  = Color(0xFF0D0D10);
const _kSurface2 = Color(0xFF131318);
const _kBorder   = Color(0xFF1C1C24);
const _kBorder2  = Color(0xFF242430);
const _kDim      = Color(0xFF3A3A4A);
const _kSub      = Color(0xFF5A5A70);
const _kText     = Color(0xFFAAAAAC);
const _kWhite    = Color(0xFFF0F0F2);
const _kRed      = Color(0xFFCC2222);
const _kSafe     = Color(0xFF3DBF82);
const _kWarn     = Color(0xFFD4872A);
const _kGold     = Color(0xFFD4A84C);

TextStyle _raj(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    GoogleFonts.rajdhani(
        fontSize: size, fontWeight: weight, color: color,
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
    } catch (e, stack) {
      debugPrint('⚠️ _MapDataService.cargarGruposCercanos: geobounds query falló, '
                 'usando fallback completo.\n$e\n$stack');
      snap = await _db.collection('territories').get();
    }

    final Map<String, List<_TerDet>> tersPorOwner = {};

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
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
    final chunks   = _chunked(ownerIds, 30);
    final Map<String, Map<String, dynamic>> playersMap = {};
    for (final chunk in chunks) {
      try {
        final pd = await _db.collection('players')
            .where(FieldPath.documentId, whereIn: chunk).get();
        for (final p in pd.docs) {
          playersMap[p.id] = p.data();
        }
      } catch (e, stack) {
        debugPrint('⚠️ _MapDataService: error cargando players chunk.\n$e\n$stack');
      }
    }

    final Map<String, _UserGroup> grupos = {};
    for (final ownerId in tersPorOwner.keys) {
      final pData = playersMap[ownerId];
      final nick  = ownerId == myUid
          ? 'YO'
          : (pData?['nickname'] as String? ?? ownerId);
      final nivel = (pData?['nivel'] as num? ?? 1).toInt();
      grupos[ownerId] = _UserGroup(
        ownerId:     ownerId,
        nickname:    nick,
        nivel:       nivel,
        esMio:       ownerId == myUid,
        territorios: tersPorOwner[ownerId]!,
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
      final data = doc.data() as Map<String, dynamic>;
      final rawPts = data['puntos'] as List<dynamic>?;
      List<LatLng> pts = [];
      double dist = 0;
      if (rawPts != null && rawPts.isNotEmpty) {
        pts  = _parsePuntos(rawPts);
        final c = _centroide(pts);
        dist = Geolocator.distanceBetween(
            centro.latitude, centro.longitude,
            c.latitude, c.longitude) / 1000;
      }
      final tsV  = data['ultima_visita'] as Timestamp?;
      final dias = tsV == null
          ? 0
          : DateTime.now().difference(tsV.toDate()).inDays;
      dets.add(_TerDet(
        docId:            doc.id,
        dist:             dist,
        diasSinVisitar:   dias,
        puntos:           pts,
        ownerId:          ownerId,
        nombreTerritorio: data['nombre_territorio'] as String?,
      ));
    }
    return dets;
  }

  static List<LatLng> _parsePuntos(List<dynamic> raw) => raw.map((p) {
    final m = p as Map<String, dynamic>;
    return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
  }).toList();

  static LatLng _centroide(List<LatLng> pts) => LatLng(
    pts.map((p) => p.latitude).reduce((a, b) => a + b)  / pts.length,
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

  List<TerritoryData> territorios                   = [];
  bool loadingTerritorios                           = true;
  Map<String, Map<String, dynamic>> jugadoresEnVivo = {};
  Map<String, dynamic>? desafioActivo;
  List<_UserGroup> grupos                           = [];
  bool loadingCercanos                              = false;
  bool cercanosVisible                              = false;
  String? userExpandido;
  TerritoryData? territorioSeleccionado;
  LatLng centro = const LatLng(40.4167, -3.70325);
  String? errorMessage;

  // ── CACHÉ estático de detalles con TTL 2 minutos ─────────────────────────
  static final Map<String, List<_TerDet>> _detallesCache     = {};
  static final Map<String, DateTime>      _detallesTimestamp = {};
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
    debugPrint('🗑️ _MapState: caché de detalles invalidado');
  }

  void setCentro(LatLng c)                     { centro = c; notifyListeners(); }
  void setLoadingTerritorios(bool v)           { loadingTerritorios = v; notifyListeners(); }
  void seleccionarTerritorio(TerritoryData? t) { territorioSeleccionado = t; notifyListeners(); }
  void setLoadingCercanos(bool v)              { loadingCercanos = v; notifyListeners(); }
  void setUserExpandido(String? id)            { userExpandido = id; notifyListeners(); }
  void clearError()                            { errorMessage = null; }

  void setTerritorios(List<TerritoryData> lista) {
    territorios        = lista;
    loadingTerritorios = false;
    errorMessage       = null;
    notifyListeners();
  }

  void setError(String msg) {
    errorMessage       = msg;
    loadingTerritorios = false;
    loadingCercanos    = false;
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
    grupos          = g;
    loadingCercanos = false;
    cercanosVisible = true;
    errorMessage    = null;
    notifyListeners();
  }

  void toggleCercanos() {
    cercanosVisible = !cercanosVisible;
    if (!cercanosVisible) userExpandido = null;
    notifyListeners();
  }

  void _setDetalles(String ownerId, List<_TerDet> dets) {
    _detallesCache[ownerId]     = dets;
    _detallesTimestamp[ownerId] = DateTime.now();
    notifyListeners();
  }

  Future<void> cargarCercanos(String myUid) async {
    setLoadingCercanos(true);
    try {
      final result = await _service.cargarGruposCercanos(centro, myUid);
      setGrupos(result);
    } catch (e, stack) {
      debugPrint('⚠️ _MapState.cargarCercanos: $e\n$stack');
      setError('No se pudieron cargar los territorios cercanos');
    }
  }

  Future<void> cargarDetalles(String ownerId) async {
    if (_detallesCacheValido(ownerId)) {
      debugPrint('✅ _MapState: detalles caché hit para $ownerId');
      notifyListeners();
      return;
    }
    try {
      final dets = await _service.cargarDetalles(ownerId, centro);
      _setDetalles(ownerId, dets);
    } catch (e, stack) {
      debugPrint('⚠️ _MapState.cargarDetalles: $e\n$stack');
      setError('No se pudieron cargar los detalles del territorio');
    }
  }
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
    this.territorios     = const [],
    this.colorTerritorio = const Color(0xFFCC2222),
    this.centroInicial,
    this.ruta            = const [],
    this.mostrarRuta     = false,
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

  StreamSubscription? _presenciaStream;
  StreamSubscription? _desafioStream;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;
  late AnimationController _selCtrl;
  late Animation<double>   _selAnim;
  late AnimationController _sheetEntryCtrl;
  late Animation<double>   _sheetEntryAnim;

  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _state = _MapState();
    _state.addListener(_onErrorCheck);

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

    _initData();
  }

  void _onErrorCheck() {
    if (!mounted) return;
    if (_state.errorMessage != null) {
      _mostrarError(_state.errorMessage!);
      _state.clearError();
    }
  }

  @override
  void dispose() {
    _state.removeListener(_onErrorCheck);
    _state.dispose();
    _pulseCtrl.dispose();
    _selCtrl.dispose();
    _sheetEntryCtrl.dispose();
    _presenciaStream?.cancel();
    _desafioStream?.cancel();
    _sheetCtrl.dispose();
    super.dispose();
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: _kWarn, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(mensaje,
              style: _raj(12, FontWeight.w600, _kWhite))),
        ]),
        backgroundColor: _kSurface,
        behavior:        SnackBarBehavior.floating,
        margin:  const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: _kWarn, width: 1),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _mostrarExito(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: _kSafe, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(mensaje,
              style: _raj(12, FontWeight.w600, _kWhite))),
        ]),
        backgroundColor: _kSurface,
        behavior:        SnackBarBehavior.floating,
        margin:  const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: _kSafe, width: 1),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _initData() async {
    await _resolverCentro();
    await _cargarTerritorios();
    _escucharJugadores();
    _escucharDesafio();
    _sheetEntryCtrl.forward();
  }

  Future<void> _resolverCentro() async {
    if (widget.centroInicial != null) {
      _state.setCentro(widget.centroInicial!);
      return;
    }
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.low));
        _state.setCentro(LatLng(pos.latitude, pos.longitude));
      }
    } catch (e, stack) {
      debugPrint('⚠️ _resolverCentro: $e\n$stack');
    }
  }

  Future<void> _cargarTerritorios() async {
    if (widget.territorios.isNotEmpty) {
      _state.setTerritorios(widget.territorios);
      return;
    }
    _state.setLoadingTerritorios(true);
    try {
      final lista = await TerritoryService.cargarTodosLosTerritorios(
        centro: _state.centro,
      );
      _state.setTerritorios(lista);
    } catch (e, stack) {
      debugPrint('⚠️ _cargarTerritorios: $e\n$stack');
      _state.setError('No se pudieron cargar los territorios');
    }
  }

  Future<void> _refrescarTerritorios() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    TerritoryService.invalidarCache();
    _MapState.invalidarDetallesCache();
    await _cargarTerritorios();
    if (mounted) setState(() => _refreshing = false);
  }

  void _escucharJugadores() {
    const double radioGrados = 0.09;
    final latMin = _state.centro.latitude  - radioGrados;
    final latMax = _state.centro.latitude  + radioGrados;

    _presenciaStream = FirebaseFirestore.instance
        .collection('presencia_activa')
        .where('lat', isGreaterThan: latMin)
        .where('lat', isLessThan:    latMax)
        .snapshots()
        .listen((snap) {
      final nuevos = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        if (doc.id == _uid) continue;
        final d  = doc.data();
        final ts = d['timestamp'] as Timestamp?;
        if (ts != null &&
            DateTime.now().difference(ts.toDate()).inMinutes < 5) {
          nuevos[doc.id] = d;
        }
      }
      _state.setJugadores(nuevos);
    }, onError: (e, stack) {
      debugPrint('⚠️ _escucharJugadores stream error: $e\n$stack');
    });
  }

  void _escucharDesafio() {
    if (_uid == null) return;
    _desafioStream = FirebaseFirestore.instance
        .collection('desafios')
        .where('estado', isEqualTo: 'activo')
        .snapshots()
        .listen((snap) {
      try {
        final doc = snap.docs.firstWhere((d) {
          final data = d.data();
          return data['retadorId'] == _uid || data['retadoId'] == _uid;
        });
        _state.setDesafio(doc.data());
      } catch (_) {
        _state.setDesafio(null);
      }
    }, onError: (e, stack) {
      debugPrint('⚠️ _escucharDesafio stream error: $e\n$stack');
      _state.setDesafio(null);
    });
  }

  void _onTerritoryTap(TerritoryData t) {
    HapticFeedback.lightImpact();
    _state.seleccionarTerritorio(t);
    _selCtrl.forward(from: 0);
    _mapController.move(t.centro, 15);
  }

  void _cerrarSeleccion() {
    _selCtrl.reverse();
    Future.delayed(const Duration(milliseconds: 280), () {
      _state.seleccionarTerritorio(null);
    });
  }

  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersections = 0;
    final int n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final double xi = polygon[i].longitude;
      final double yi = polygon[i].latitude;
      final double xj = polygon[j].longitude;
      final double yj = polygon[j].latitude;
      final bool cruza =
          ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
      if (cruza) intersections++;
    }
    return intersections % 2 == 1;
  }

  // ==========================================================================
  // CONQUISTA — lógica principal
  // ==========================================================================
  Future<void> _ejecutarConquista(_TerDet det, String ownerNick) async {
    // Obtener posición actual
    Position? pos;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high));
      }
    } catch (e) {
      debugPrint('⚠️ _ejecutarConquista: error obteniendo posición: $e');
    }

    if (pos == null) {
      _mostrarError('No se pudo obtener tu ubicación. Activa el GPS.');
      return;
    }

    // Mostrar diálogo de confirmación
    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoConfirmarConquista(
        ownerNick: ownerNick,
        diasSinVisitar: det.diasSinVisitar ?? 0,
      ),
    );
    if (confirmar != true) return;

    // Ejecutar conquista via Cloud Function
    if (!mounted) return;
    // Mostrar loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DialogoConquistando(),
    );

    try {
      await TerritoryService.conquistarTerritorio(
        docId:          det.docId,
        duenoAnteriorId: det.ownerId,
        latUsuario:     pos.latitude,
        lngUsuario:     pos.longitude,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // cerrar loading

      _mostrarExito('⚔️ ¡Territorio conquistado!');
      HapticFeedback.heavyImpact();

      // Refrescar mapa y cerrar bottom sheet
      Navigator.of(context).pop(); // cerrar _mostrarDialogo
      await _refrescarTerritorios();

    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // cerrar loading
      _mostrarError(e.message ?? 'No puedes conquistar este territorio');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // cerrar loading
      _mostrarError('Error inesperado. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(children: [

        Positioned.fill(child: _buildMapa()),

        Positioned(
          top: 0, left: 0, right: 0,
          child: ListenableBuilder(
            listenable: _state,
            builder: (_, __) {
              final mios         = _state.territorios.where((t) => t.esMio).length;
              final deteriorados = _state.territorios.where((t) => t.esMio && t.estaDeterirado).length;
              final enPeligro    = _state.territorios.where((t) => t.esMio && t.esConquistableSinPasar).length;
              return _buildFloatingBar(mios, deteriorados, enPeligro);
            },
          ),
        ),

        SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1), end: Offset.zero,
          ).animate(_sheetEntryAnim),
          child: DraggableScrollableSheet(
            controller:       _sheetCtrl,
            initialChildSize: 0.13,
            minChildSize:     0.08,
            maxChildSize:     0.75,
            snap:             true,
            snapSizes:        const [0.08, 0.13, 0.4, 0.75],
            builder: (ctx, scrollCtrl) => ListenableBuilder(
              listenable: _state,
              builder: (_, __) {
                final mios         = _state.territorios.where((t) => t.esMio).length;
                final deteriorados = _state.territorios.where((t) => t.esMio && t.estaDeterirado).length;
                final enPeligro    = _state.territorios.where((t) => t.esMio && t.esConquistableSinPasar).length;
                return _buildSheet(scrollCtrl, mios, deteriorados, enPeligro);
              },
            ),
          ),
        ),

        ListenableBuilder(
          listenable: _state,
          builder: (_, __) {
            if (_state.territorioSeleccionado == null) return const SizedBox.shrink();
            final screenH = MediaQuery.of(context).size.height;
            return Positioned(
              bottom: screenH * 0.14 + 12,
              left: 16, right: 16,
              child: _buildTerritoryCard(_state.territorioSeleccionado!),
            );
          },
        ),

        ListenableBuilder(
          listenable: _state,
          builder: (_, __) {
            final screenH = MediaQuery.of(context).size.height;
            return Positioned(
              right: 16,
              bottom: screenH * 0.14 +
                  (_state.territorioSeleccionado != null ? 160 : 12),
              child: _buildFab(),
            );
          },
        ),
      ]),
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 2),
    );
  }

  // ==========================================================================
  // APP BAR FLOTANTE
  // ==========================================================================
  Widget _buildFloatingBar(int mios, int det, int pel) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [

          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: _kBg.withOpacity(0.72),
                  border: Border.all(color: _kBorder2),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 20)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 2, height: 18, color: _kRed,
                      margin: const EdgeInsets.only(right: 10)),
                  Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('MAPA DE GUERRA',
                        style: _raj(13, FontWeight.w900, _kWhite, spacing: 2)),
                    AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) =>
                      Row(children: [
                        Container(
                          width: 5, height: 5,
                          decoration: BoxDecoration(
                            color: _kSafe.withOpacity(0.4 + 0.6 * _pulse.value),
                            shape: BoxShape.circle),
                          margin: const EdgeInsets.only(right: 5)),
                        Text(
                          '${_state.jugadoresEnVivo.length} EN VIVO · '
                          '${_state.territorios.length} ZONAS',
                          style: _raj(8, FontWeight.w700, _kSub, spacing: 1.5)),
                      ])),
                  ]),
                ]),
              ),
            ),
          ),

          const Spacer(),

          if (det > 0 || pel > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kBg.withOpacity(0.72),
                    border: Border.all(
                        color: (pel > 0 ? _kRed : _kWarn).withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 20)],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (pel > 0) ...[
                      const Icon(Icons.dangerous_rounded, color: _kRed, size: 12),
                      const SizedBox(width: 4),
                      Text('$pel', style: _raj(11, FontWeight.w900, _kRed)),
                      const SizedBox(width: 8),
                    ],
                    if (det > 0) ...[
                      const Icon(Icons.warning_amber_rounded, color: _kWarn, size: 12),
                      const SizedBox(width: 4),
                      Text('$det', style: _raj(11, FontWeight.w900, _kWarn)),
                    ],
                  ]),
                ),
              ),
            ),

          const SizedBox(width: 8),

          // ── Botón refresh con feedback visual ─────────────────────────────
          Semantics(
            label: _refreshing ? 'Recargando territorios' : 'Recargar territorios',
            button: true,
            child: ClipRRect(
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
                      color: _kBg.withOpacity(0.72),
                      border: Border.all(color: _kBorder2),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 20)],
                    ),
                    child: _refreshing
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: _kText,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, color: _kText, size: 16),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
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
        final territorios  = _state.territorios;
        final seleccionado = _state.territorioSeleccionado;

        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _state.centro,
            initialZoom:   14,
            minZoom: 3, maxZoom: 19,
            onTap: (_, __) {
              if (seleccionado != null) _cerrarSeleccion();
            },
            onMapReady: () {
              if (tieneRuta) {
                try {
                  _mapController.fitCamera(CameraFit.bounds(
                      bounds:  LatLngBounds.fromPoints(widget.ruta),
                      padding: const EdgeInsets.all(60)));
                } catch (e) {
                  debugPrint('⚠️ fitCamera: $e');
                }
              }
            },
          ),
          children: [

            TileLayer(
              urlTemplate:          _kMapboxUrl,
              userAgentPackageName: 'com.runner_risk.app',
              tileSize:             256,
            ),

            if (territorios.isNotEmpty)
              GestureDetector(
                onTapUp: (details) {
                  if (territorios.isEmpty) return;
                  final tapLatLng = _mapController.camera
                      .offsetToCrs(details.localPosition);

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
                      if (d < minDist && d < 200) { minDist = d; encontrado = t; }
                    }
                  }
                  if (encontrado != null) _onTerritoryTap(encontrado);
                },
                child: PolygonLayer(
                  polygons: territorios.map((t) {
                    final bool sel = seleccionado?.docId == t.docId;
                    return Polygon(
                      points:            t.puntos,
                      color:             sel
                          ? t.color.withOpacity(0.45)
                          : t.color.withOpacity(t.opacidadRelleno),
                      borderColor:       sel
                          ? t.color
                          : t.color.withOpacity(t.opacidadBorde),
                      borderStrokeWidth: sel
                          ? 3.5
                          : (t.estaDeterirado ? 1.5 : 2.5),
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
                point: _state.centro, width: 24, height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color:  Colors.white,
                    shape:  BoxShape.circle,
                    border: Border.all(color: _kRed, width: 2),
                    boxShadow: [
                      BoxShadow(color: _kRed.withOpacity(0.5),
                          blurRadius: 12, spreadRadius: 2),
                      const BoxShadow(color: Colors.white24, blurRadius: 4),
                    ],
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
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: seleccionado?.docId == t.docId
                              ? t.color
                              : t.color.withOpacity(0.5),
                          width: seleccionado?.docId == t.docId ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        t.esMio ? '[ YO ]' : t.ownerNickname,
                        textAlign:  TextAlign.center,
                        overflow:   TextOverflow.ellipsis,
                        style: TextStyle(
                          color:      t.color, fontSize: 8,
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
                  final d    = e.value;
                  final lat  = (d['lat'] as num?)?.toDouble();
                  final lng  = (d['lng'] as num?)?.toDouble();
                  final color = d['color'] != null
                      ? Color(d['color'] as int) : _kRed;
                  final nick = d['nickname'] as String? ?? '';
                  if (lat == null || lng == null) return null;
                  return Marker(
                    point: LatLng(lat, lng), width: 56, height: 60,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color:  color.withOpacity(0.15),
                          border: Border.all(color: color.withOpacity(0.7)),
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: [BoxShadow(
                              color: color.withOpacity(0.3), blurRadius: 8)],
                        ),
                        child: Text(
                          nick.length > 6 ? '${nick.substring(0, 6)}..' : nick,
                          style: TextStyle(color: color, fontSize: 8,
                              fontWeight: FontWeight.w900)),
                      ),
                      Container(width: 1.5, height: 6,
                          color: color.withOpacity(0.6)),
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) => Container(
                          width:  10 + 4 * _pulse.value,
                          height: 10 + 4 * _pulse.value,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.8),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(
                                color:      color.withOpacity(0.5 * _pulse.value),
                                blurRadius: 12, spreadRadius: 3)],
                          ),
                        ),
                      ),
                    ]),
                  );
                }).whereType<Marker>().toList(),
              ),

            if (_state.loadingTerritorios)
              const ColorFiltered(
                colorFilter: ColorFilter.mode(Colors.black45, BlendMode.srcOver),
                child: SizedBox.expand(),
              ),
          ],
        );
      },
    );
  }

  // ==========================================================================
  // FAB
  // ==========================================================================
  Widget _buildFab() => Semantics(
    label: 'Centrar mapa en mi ubicación',
    button: true,
    child: GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _mapController.move(_state.centro, 15);
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
                color:  _kSurface.withOpacity(0.85),
                border: Border.all(
                    color: _kRed.withOpacity(0.4 + 0.3 * _pulse.value)),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                      color:      _kRed.withOpacity(0.15 * _pulse.value),
                      blurRadius: 16),
                  const BoxShadow(color: Colors.black54, blurRadius: 12),
                ],
              ),
              child: const Icon(Icons.my_location_rounded, color: _kRed, size: 18),
            ),
          ),
        ),
      ),
    ),
  );

  // ==========================================================================
  // CARD TERRITORIO SELECCIONADO
  // ==========================================================================
  Widget _buildTerritoryCard(TerritoryData t) {
    String estado      = 'activo';
    Color  cEstado     = _kSafe;
    String estadoEmoji = '✅';
    if (t.esConquistableSinPasar) {
      estado = 'crítico'; cEstado = _kRed; estadoEmoji = '🔴';
    } else if (t.estaDeterirado) {
      estado = 'con desgaste'; cEstado = _kWarn; estadoEmoji = '🟡';
    }

    return Semantics(
      label: '${t.esMio ? "Tu territorio" : "Territorio de ${t.ownerNickname}"}. '
             'Estado: $estado. ${t.puntos.length} puntos.',
      child: ScaleTransition(
        scale: _selAnim,
        child: FadeTransition(
          opacity: _selAnim,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                decoration: BoxDecoration(
                  color:  _kSurface.withOpacity(0.88),
                  border: Border.all(color: t.color.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: t.color.withOpacity(0.15), blurRadius: 20),
                    const BoxShadow(color: Colors.black87, blurRadius: 16),
                  ],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    decoration: BoxDecoration(
                      color: t.color.withOpacity(0.08),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      border: Border(bottom: BorderSide(color: t.color.withOpacity(0.2))),
                    ),
                    child: Row(children: [
                      Container(width: 3, height: 20, color: t.color,
                          margin: const EdgeInsets.only(right: 10)),
                      Column(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                          t.esMio ? 'MI TERRITORIO' : t.ownerNickname.toUpperCase(),
                          style: _raj(13, FontWeight.w900, _kWhite, spacing: 1.5)),
                        Text(
                          t.esMio ? 'ZONA CONTROLADA' : 'TERRITORIO RIVAL',
                          style: _raj(8, FontWeight.w700,
                              t.esMio ? t.color : _kSub, spacing: 2)),
                      ]),
                      const Spacer(),
                      Semantics(
                        label: 'Cerrar detalle de territorio',
                        button: true,
                        child: GestureDetector(
                          onTap: _cerrarSeleccion,
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: _kBorder,
                              borderRadius: BorderRadius.circular(4)),
                            child: const Icon(Icons.close_rounded,
                                color: _kText, size: 14)),
                        ),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Row(children: [
                      _cardStat(estadoEmoji, estado.toUpperCase(), cEstado),
                      _vDiv(),
                      _cardStat('🏴', '${t.puntos.length} PTS', _kText),
                      _vDiv(),
                      if (t.esMio)
                        _cardStat('⚔️', 'DEFENDER', _kGold)
                      else
                        _cardStat('👁', 'OBSERVAR', _kSub),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardStat(String emoji, String label, Color color) => Expanded(
    child: Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 4),
      Text(label,
          style: _raj(9, FontWeight.w800, color, spacing: 0.5),
          textAlign: TextAlign.center),
    ]),
  );

  Widget _vDiv() => Container(
      width: 1, height: 36, color: _kBorder2,
      margin: const EdgeInsets.symmetric(horizontal: 4));

  // ==========================================================================
  // DRAGGABLE SHEET
  // ==========================================================================
  Widget _buildSheet(
      ScrollController scrollCtrl, int mios, int det, int pel) {
    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(
          top:   BorderSide(color: _kBorder2),
          left:  BorderSide(color: _kBorder2),
          right: BorderSide(color: _kBorder2),
        ),
        boxShadow: [BoxShadow(
            color: Colors.black87, blurRadius: 30, offset: Offset(0, -4))],
      ),
      child: ListView(
        controller: scrollCtrl,
        padding:    EdgeInsets.zero,
        physics:    const ClampingScrollPhysics(),
        children: [
          _buildSheetHandle(mios, det, pel),
          if (_state.desafioActivo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildBannerDesafio(_state.desafioActivo!),
            ),
          _buildStatsRow(mios, det, pel),
          if (det > 0 || pel > 0) _buildAlertaBanner(det, pel),
          _buildBotonCercanos(),
          if (_state.cercanosVisible) _buildPanelCercanos(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSheetHandle(int mios, int det, int pel) => Semantics(
    label: 'Tus dominios. '
           'Tienes $mios zonas. '
           '${pel > 0 ? "$pel en estado crítico. " : ""}'
           '${det > 0 ? "$det con desgaste." : ""}',
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(children: [
        Center(child: Container(
          width: 36, height: 3,
          decoration: BoxDecoration(
            color: _kBorder2, borderRadius: BorderRadius.circular(2)),
        )),
        const SizedBox(height: 14),
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TUS DOMINIOS',
                style: _raj(9, FontWeight.w800, _kSub, spacing: 2.5)),
            const SizedBox(height: 2),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$mios',
                  style: _raj(28, FontWeight.w900, _kWhite, height: 1)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('ZONAS',
                    style: _raj(10, FontWeight.w700, _kSub, spacing: 1.5)),
              ),
            ]),
          ]),
          const Spacer(),
          if (pel > 0)
            _quickBadge('$pel CRÍTICO', _kRed, Icons.dangerous_rounded),
          if (pel > 0 && det > 0) const SizedBox(width: 6),
          if (det > 0)
            _quickBadge('$det DESGASTE', _kWarn, Icons.warning_amber_rounded),
          if (pel == 0 && det == 0)
            _quickBadge('TODO OK', _kSafe, Icons.shield_rounded),
        ]),
      ]),
    ),
  );

  Widget _quickBadge(String label, Color color, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color:  color.withOpacity(0.08),
      border: Border.all(color: color.withOpacity(0.3)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 10),
      const SizedBox(width: 4),
      Text(label, style: _raj(9, FontWeight.w800, color, spacing: 0.5)),
    ]),
  );

  Widget _buildStatsRow(int mios, int det, int pel) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Row(children: [
      _sheetStat('${_state.territorios.length}', 'TOTAL',  _kText),
      const SizedBox(width: 8),
      _sheetStat('${_state.jugadoresEnVivo.length}', 'EN VIVO', _kSafe),
      const SizedBox(width: 8),
      _sheetStat('$mios', 'MÍO', widget.colorTerritorio),
    ]),
  );

  Widget _sheetStat(String v, String l, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color:  _kSurface,
        border: Border.all(color: c.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(children: [
        Text(v, style: _raj(20, FontWeight.w900, c, height: 1)),
        const SizedBox(height: 3),
        Text(l, style: _raj(7, FontWeight.w800, c.withOpacity(0.6), spacing: 1.5)),
      ]),
    ),
  );

  Widget _buildAlertaBanner(int det, int pel) => Container(
    margin:  const EdgeInsets.fromLTRB(16, 0, 16, 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: _kRed.withOpacity(0.04),
      border: Border(
        left:   const BorderSide(color: _kRed, width: 2.5),
        top:    BorderSide(color: _kBorder2),
        right:  BorderSide(color: _kBorder2),
        bottom: BorderSide(color: _kBorder2),
      ),
      borderRadius: const BorderRadius.only(
        topRight:    Radius.circular(4),
        bottomRight: Radius.circular(4)),
    ),
    child: Row(children: [
      const Icon(Icons.shield_outlined, color: _kRed, size: 14),
      const SizedBox(width: 10),
      Expanded(child: Text(
        pel > 0
            ? '⚔ $pel ${pel == 1 ? 'territorio puede' : 'territorios pueden'} ser conquistados ahora.'
            : '⚠ $det ${det == 1 ? 'territorio debilitado' : 'territorios debilitados'}. Visítalos pronto.',
        style: _raj(11, FontWeight.w600, _kRed),
      )),
    ]),
  );

  Widget _buildBotonCercanos() => Semantics(
    label: _state.cercanosVisible
        ? 'Ocultar territorios cercanos'
        : 'Ver territorios en un radio de 5 kilómetros',
    button: true,
    child: GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (_state.cercanosVisible) {
          _state.toggleCercanos();
        } else {
          _state.cargarCercanos(_uid ?? '');
        }
      },
      child: Container(
        margin:  const EdgeInsets.fromLTRB(16, 0, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color:  _kSurface,
          border: Border.all(
              color: _state.cercanosVisible
                  ? _kRed.withOpacity(0.3) : _kBorder2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) => Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: _kSafe.withOpacity(0.4 + 0.6 * _pulse.value),
              shape: BoxShape.circle),
          )),
          const SizedBox(width: 10),
          _state.loadingCercanos
              ? Shimmer.fromColors(
                  baseColor:      _kSurface2,
                  highlightColor: _kBorder2,
                  child: Container(
                    width: 160, height: 12,
                    decoration: BoxDecoration(
                      color: _kSurface2,
                      borderRadius: BorderRadius.circular(3))))
              : Text(
                  _state.cercanosVisible
                      ? 'TERRITORIOS EN ZONA  ▲'
                      : 'TERRITORIOS EN ZONA  ▼',
                  style: _raj(10, FontWeight.w700,
                      _state.cercanosVisible ? _kText : _kSub, spacing: 1.5)),
          const Spacer(),
          Text('5 KM', style: _raj(9, FontWeight.w800, _kDim, spacing: 1)),
          const SizedBox(width: 8),
          Icon(Icons.radar_rounded,
              color: _state.cercanosVisible ? _kRed : _kDim, size: 14),
        ]),
      ),
    ),
  );

  Widget _buildPanelCercanos() {
    if (_state.grupos.isEmpty) {
      return Container(
        margin:  const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:  _kSurface,
          border: Border.all(color: _kBorder2),
          borderRadius: BorderRadius.circular(6)),
        child: Text('No hay territorios en 5 km',
            style: _raj(12, FontWeight.w500, _kSub)));
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color:  _kSurface,
        border: Border.all(color: _kBorder2),
        borderRadius: BorderRadius.circular(6)),
      child: Column(
        children: _state.grupos.asMap().entries.map((entry) {
          final idx   = entry.key;
          final g     = entry.value;
          final isExp = _state.userExpandido == g.ownerId;
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(children: [
                  Container(width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: g.esMio ? _kRed : _kSub,
                      shape: BoxShape.circle,
                      boxShadow: g.esMio
                          ? [BoxShadow(color: _kRed.withOpacity(0.5), blurRadius: 6)]
                          : null,
                    )),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    g.esMio
                        ? '${g.nickname.toUpperCase()}  (TÚ)'
                        : g.nickname.toUpperCase(),
                    style: _raj(12, FontWeight.w800,
                        g.esMio ? _kWhite : _kText, spacing: 1))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: _kBorder2),
                      borderRadius: BorderRadius.circular(3)),
                    child: Text('NIV.${g.nivel}',
                        style: _raj(8, FontWeight.w900,
                            g.esMio ? _kRed : _kSub))),
                  const SizedBox(width: 8),
                  Text('${g.territorios.length} 🏴',
                      style: _raj(11, FontWeight.w600, _kDim)),
                  const SizedBox(width: 6),
                  Icon(isExp
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                      color: _kDim, size: 18),
                ]),
              ),
            ),
            if (isExp)
              Container(
                margin:  const EdgeInsets.fromLTRB(14, 0, 14, 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:  _kBg,
                  border: Border.all(color: _kBorder2),
                  borderRadius: BorderRadius.circular(4)),
                child: dets == null
                    ? _buildShimmerDetalles()
                    : dets.isEmpty
                        ? Text('Sin territorios',
                            style: _raj(12, FontWeight.w500, _kSub))
                        : Column(
                            children: dets.asMap().entries.map((e) =>
                              _terCard(e.key, e.value,
                                  g.esMio ? 'YO' : g.nickname)).toList()),
              ),
            if (!isLast) Container(height: 1, color: _kBorder),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildShimmerDetalles() => Column(
    children: List.generate(2, (i) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Shimmer.fromColors(
        baseColor:      _kSurface,
        highlightColor: _kBorder2,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(4)),
        ),
      ),
    )),
  );

  Widget _terCard(int i, _TerDet det, String nick) {
    String est = 'ACTIVO'; Color c = _kSafe;
    if (det.diasSinVisitar != null && det.diasSinVisitar! >= 10) {
      est = 'CRÍTICO'; c = _kRed;
    } else if (det.diasSinVisitar != null && det.diasSinVisitar! >= 5) {
      est = 'DESGASTE'; c = _kWarn;
    }
    return GestureDetector(
      onTap: () => _mostrarDialogo(det, nick),
      child: Container(
        margin:  const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:  _kSurface,
          border: Border.all(color: c.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(4)),
        child: Row(children: [
          Container(width: 2, height: 14, color: c,
              margin: const EdgeInsets.only(right: 8)),
          Text('ZONA #${i + 1}',
              style: _raj(11, FontWeight.w800, _kText, spacing: 0.5)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            color: c.withOpacity(0.08),
            child: Text(est, style: _raj(8, FontWeight.w800, c, spacing: 1))),
          const Spacer(),
          Text('${det.dist.toStringAsFixed(1)} km',
              style: _raj(10, FontWeight.w600, _kSub)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded,
              color: _kRed.withOpacity(0.5), size: 13),
        ]),
      ),
    );
  }

  // ==========================================================================
  // DIÁLOGO DETALLE — con botón CONQUISTAR si aplica
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

    String estado = 'activo'; Color cEstado = _kSafe;
    if (det.diasSinVisitar != null && det.diasSinVisitar! >= 10) {
      estado = 'crítico'; cEstado = _kRed;
    } else if (det.diasSinVisitar != null && det.diasSinVisitar! >= 5) {
      estado = 'con desgaste'; cEstado = _kWarn;
    }

    showModalBottomSheet(
      context:            context,
      backgroundColor:    Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(
            top:   BorderSide(color: _kBorder2),
            left:  BorderSide(color: _kBorder2),
            right: BorderSide(color: _kBorder2),
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 14),
            width: 36, height: 3,
            decoration: BoxDecoration(
                color: _kBorder2, borderRadius: BorderRadius.circular(2))),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Row(children: [
              Container(width: 3, height: 18, color: _kRed,
                  margin: const EdgeInsets.only(right: 10)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(ownerNick.toUpperCase(),
                      style: _raj(15, FontWeight.w900, _kWhite, spacing: 1.5)),
                  if (det.nombreTerritorio != null &&
                      det.nombreTerritorio!.isNotEmpty)
                    Text('"${det.nombreTerritorio}"',
                        style: _raj(11, FontWeight.w600, _kGold, spacing: 0.5)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:  cEstado.withOpacity(0.08),
                  border: Border.all(color: cEstado.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(4)),
                child: Text(estado.toUpperCase(),
                    style: _raj(9, FontWeight.w900, cEstado, spacing: 1))),
            ]),
          ),

          // Mini mapa
          if (det.puntos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(height: 160,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: centro,
                      initialZoom:   15,
                      interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.pinchZoom |
                                 InteractiveFlag.doubleTapZoom)),
                    children: [
                      TileLayer(
                          urlTemplate: _kMapboxUrl,
                          userAgentPackageName: 'com.runner_risk.app',
                          tileSize: 256),
                      PolygonLayer(polygons: [Polygon(
                          points:            det.puntos,
                          color:             _kRed.withOpacity(0.2),
                          borderColor:       _kRed,
                          borderStrokeWidth: 2)]),
                    ],
                  ),
                ),
              ),
            ),

          // Stats
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              _dStat('SIN VISITAR',
                  det.diasSinVisitar != null
                      ? '${det.diasSinVisitar}d' : '--', _kDim),
              Container(width: 1, height: 36, color: _kBorder2),
              _dStat('DISTANCIA', '${det.dist.toStringAsFixed(1)} km', _kText),
              Container(width: 1, height: 36, color: _kBorder2),
              _dStat('PUNTOS', '${det.puntos.length}', _kGold),
            ]),
          ),

          // ── BOTÓN CONQUISTAR ─────────────────────────────────────────────
          if (conquistable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: GestureDetector(
                onTap: () => _ejecutarConquista(det, ownerNick),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _kRed.withOpacity(0.12),
                    border: Border.all(color: _kRed.withOpacity(0.6)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.sports_kabaddi_rounded,
                          color: _kRed, size: 18),
                      const SizedBox(width: 10),
                      Text('CONQUISTAR TERRITORIO',
                          style: _raj(13, FontWeight.w900, _kRed, spacing: 2)),
                    ],
                  ),
                ),
              ),
            ),

          // Nota si no es conquistable pero es rival
          if (!esMio && !conquistable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: _kSurface2,
                  border: Border.all(color: _kBorder2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  const Icon(Icons.lock_outline_rounded, color: _kSub, size: 14),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Necesita ${kDiasParaDeterioroFuncional - (det.diasSinVisitar ?? 0)} días más sin visita para poder conquistarlo.',
                    style: _raj(10, FontWeight.w600, _kSub),
                  )),
                ]),
              ),
            ),

          // ── BOTÓN RENOMBRAR (solo si es mío) ─────────────────────────────
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
                    color: _kGold.withOpacity(0.08),
                    border: Border.all(color: _kGold.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.edit_rounded, color: _kGold, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        det.nombreTerritorio != null &&
                                det.nombreTerritorio!.isNotEmpty
                            ? 'CAMBIAR NOMBRE'
                            : 'PONERLE NOMBRE',
                        style: _raj(12, FontWeight.w900, _kGold, spacing: 1.5)),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _dStat(String l, String v, Color c) =>
      Expanded(child: Column(children: [
    Text(l, style: _raj(8, FontWeight.w700, _kSub, spacing: 1.5)),
    const SizedBox(height: 4),
    Text(v, style: _raj(16, FontWeight.w900, c)),
  ]));

  // ==========================================================================
  // DIÁLOGO RENOMBRAR TERRITORIO
  // ==========================================================================
  void _mostrarDialogoRenombrar(_TerDet det) {
    showDialog(
      context: context,
      builder: (_) => _DialogoRenombrar(
        nombreActual: det.nombreTerritorio ?? '',
        onGuardar: (nuevoNombre) async {
          try {
            await TerritoryService.renombrarTerritorio(
              docId:  det.docId,
              nombre: nuevoNombre,
            );
            if (!mounted) return;
            _mostrarExito('✏️ Territorio renombrado como "$nuevoNombre"');
            _MapState.invalidarDetallesCache();
            // Recargar detalles del owner para reflejar el nuevo nombre
            await _state.cargarDetalles(det.ownerId);
          } on FirebaseFunctionsException catch (e) {
            if (!mounted) return;
            _mostrarError(e.message ?? 'No se pudo renombrar el territorio');
          } catch (e) {
            if (!mounted) return;
            _mostrarError('Error inesperado. Inténtalo de nuevo.');
          }
        },
      ),
    );
  }

  // ==========================================================================
  // BANNER DESAFÍO
  // ==========================================================================
  Widget _buildBannerDesafio(Map<String, dynamic> data) {
    final bool soyR    = data['retadorId'] == _uid;
    final String rival = soyR
        ? (data['retadoNick']  ?? 'Rival')
        : (data['retadorNick'] ?? 'Rival');
    final int misPts   = soyR
        ? (data['puntosRetador'] as num? ?? 0).toInt()
        : (data['puntosRetado']  as num? ?? 0).toInt();
    final int rivalPts = soyR
        ? (data['puntosRetado']  as num? ?? 0).toInt()
        : (data['puntosRetador'] as num? ?? 0).toInt();
    final int apuesta  = (data['apuesta'] as num? ?? 0).toInt();
    final Timestamp? finTs = data['fin'] as Timestamp?;
    final bool ganando = misPts >= rivalPts;

    String tiempo = '';
    if (finTs != null) {
      final diff = finTs.toDate().difference(DateTime.now());
      tiempo = diff.isNegative
          ? 'FINALIZADO'
          : diff.inHours > 0
              ? '${diff.inHours}h ${diff.inMinutes.remainder(60)}m'
              : '${diff.inMinutes}m';
    }
    final int total  = misPts + rivalPts;
    final double pct = total > 0 ? misPts / total : 0.5;

    return Container(
      decoration: BoxDecoration(
        color: _kRed.withOpacity(0.04),
        border: Border(
          left:   const BorderSide(color: _kRed, width: 2.5),
          top:    BorderSide(color: _kBorder2),
          right:  BorderSide(color: _kBorder2),
          bottom: BorderSide(color: _kBorder2),
        ),
        borderRadius: const BorderRadius.only(
          topRight:    Radius.circular(4),
          bottomRight: Radius.circular(4)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Row(children: [
            const Text('⚔️', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            Text('DESAFÍO ACTIVO',
                style: _raj(9, FontWeight.w900, _kRed, spacing: 2)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: _kBorder2),
                borderRadius: BorderRadius.circular(3)),
              child: Text(tiempo,
                  style: _raj(9, FontWeight.w700, _kText, spacing: 1))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          child: Row(children: [
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('TÚ', style: _raj(7, FontWeight.w700, _kSub, spacing: 2)),
              Text('$misPts', style: _raj(22, FontWeight.w900,
                  ganando ? _kWhite : _kSub, height: 1)),
            ])),
            Column(children: [
              Text('VS', style: _raj(10, FontWeight.w900, _kDim, spacing: 2)),
              Text('$apuesta 🪙', style: _raj(9, FontWeight.w700, _kText)),
            ]),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
              Text(rival.toString().toUpperCase(),
                  style: _raj(7, FontWeight.w700, _kSub, spacing: 2)),
              Text('$rivalPts', style: _raj(22, FontWeight.w900,
                  !ganando ? _kWhite : _kSub, height: 1)),
            ])),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Stack(children: [
            Container(height: 3, color: _kBorder2),
            FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(height: 3, color: _kRed)),
          ]),
        ),
      ]),
    );
  }
}

// =============================================================================
// DIÁLOGO RENOMBRAR TERRITORIO
// =============================================================================
class _DialogoRenombrar extends StatefulWidget {
  final String nombreActual;
  final Future<void> Function(String) onGuardar;

  const _DialogoRenombrar({
    required this.nombreActual,
    required this.onGuardar,
  });

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
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

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
      // El error lo muestra el caller con SnackBar
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
          border: Border.all(color: _kGold.withOpacity(0.35)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: _kGold.withOpacity(0.08), blurRadius: 30),
            const BoxShadow(color: Colors.black87, blurRadius: 20),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Icono
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: _kGold.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: _kGold.withOpacity(0.4)),
            ),
            child: const Icon(Icons.edit_rounded, color: _kGold, size: 22),
          ),
          const SizedBox(height: 16),
          Text('NOMBRE DEL TERRITORIO',
              style: _raj(15, FontWeight.w900, _kWhite, spacing: 1.5)),
          const SizedBox(height: 6),
          Text(
            'Este nombre será visible para todos\nen el mapa de guerra.',
            textAlign: TextAlign.center,
            style: _raj(11, FontWeight.w500, _kSub, height: 1.5),
          ),
          const SizedBox(height: 20),

          // Campo de texto
          Container(
            decoration: BoxDecoration(
              color: _kBg,
              border: Border.all(
                color: _error != null
                    ? _kRed.withOpacity(0.6)
                    : _kGold.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: TextField(
              controller:    _ctrl,
              maxLength:     30,
              autofocus:     true,
              textCapitalization: TextCapitalization.sentences,
              style: _raj(14, FontWeight.w700, _kWhite),
              cursorColor: _kGold,
              decoration: InputDecoration(
                hintText:        'Ej: La Cuesta del Infierno',
                hintStyle:       _raj(13, FontWeight.w500, _kDim),
                contentPadding:  const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border:          InputBorder.none,
                counterStyle:    _raj(10, FontWeight.w500, _kSub),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _guardar(),
            ),
          ),

          // Mensaje de error inline
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

          // Botones
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: _kBorder,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text('CANCELAR',
                        style: _raj(12, FontWeight.w800, _kText, spacing: 1)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _guardando ? null : _guardar,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: _kGold.withOpacity(0.15),
                    border: Border.all(color: _kGold.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: _guardando
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: _kGold))
                        : Text('GUARDAR',
                            style: _raj(12, FontWeight.w900, _kGold,
                                spacing: 1)),
                  ),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// =============================================================================
// DIÁLOGO CONFIRMAR CONQUISTA
// =============================================================================
class _DialogoConfirmarConquista extends StatelessWidget {
  final String ownerNick;
  final int diasSinVisitar;

  const _DialogoConfirmarConquista({
    required this.ownerNick,
    required this.diasSinVisitar,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kSurface,
          border: Border.all(color: _kRed.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: _kRed.withOpacity(0.1), blurRadius: 30),
            const BoxShadow(color: Colors.black87, blurRadius: 20),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: _kRed.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: _kRed.withOpacity(0.4)),
            ),
            child: const Icon(Icons.sports_kabaddi_rounded,
                color: _kRed, size: 24),
          ),
          const SizedBox(height: 16),
          Text('¿CONQUISTAR?',
              style: _raj(18, FontWeight.w900, _kWhite, spacing: 2)),
          const SizedBox(height: 8),
          Text(
            'Territorio de ${ownerNick.toUpperCase()}\n'
            '$diasSinVisitar días sin visitar',
            textAlign: TextAlign.center,
            style: _raj(12, FontWeight.w600, _kSub, height: 1.5),
          ),
          const SizedBox(height: 6),
          Text(
            'Debes estar físicamente a menos\nde 200 m del territorio.',
            textAlign: TextAlign.center,
            style: _raj(11, FontWeight.w500, _kDim, height: 1.5),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: _kBorder,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text('CANCELAR',
                        style: _raj(12, FontWeight.w800, _kText, spacing: 1)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: _kRed.withOpacity(0.15),
                    border: Border.all(color: _kRed.withOpacity(0.6)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text('CONQUISTAR',
                        style: _raj(12, FontWeight.w900, _kRed, spacing: 1)),
                  ),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// =============================================================================
// DIÁLOGO LOADING CONQUISTA
// =============================================================================
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
              strokeWidth: 2,
              color: _kRed,
            ),
          ),
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