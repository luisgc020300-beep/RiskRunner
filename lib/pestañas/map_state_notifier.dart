// lib/pestañas/map_state_notifier.dart
// ChangeNotifier de estado del mapa — extraído de fullscreen_map_screen.dart
part of 'fullscreen_map_screen.dart';

// =============================================================================
// _MapState — estado compartido de FullscreenMap (modo, territorios, UI)
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
        if (data == null) return t.copyWith(clearOwner: true);

        final ownerUid      = data['ownerUid']      as String?;
        final ownerNickname = data['ownerNickname']  as String?;
        final ownerColorInt = data['ownerColor']     as int?;
        final difficulty    = (data['difficultyLevel'] as num?)?.toInt();
        final count         = (data['conquestCount']   as num?)?.toInt();
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
      final fromDb0 = await TerritoryService.cargarGlobalesActivos();
      final uid     = FirebaseAuth.instance.currentUser?.uid ?? '';
      final fromDb  = fromDb0.map((t) =>
          (t.ownerUid != null && t.ownerUid == uid)
              ? t.copyWith(ownerColor: colorJugador)
              : t).toList();

      if (fromDb.isNotEmpty) {
        territoriosGlobales = fromDb;
        territoriosMios     = fromDb.where((t) => t.ownerUid == uid).length;
        GameStateService.instance.setGlobalTerritories(fromDb);
      } else {
        territoriosGlobales = buildSampleGlobalTerritories();
        territoriosMios     = 0;
      }
    } catch (e, st) {
      debugPrint('Error cargando territorios globales: $e');
      FirebaseCrashlytics.instance.recordError(e, st, reason: 'cargarTerritoriosGlobales');
      territoriosGlobales = buildSampleGlobalTerritories();
      territoriosMios     = 0;
    }

    final now        = DateTime.now();
    final nextMonday = now.add(Duration(
        days: (8 - now.weekday) % 7 == 0 ? 7 : (8 - now.weekday) % 7));
    diasRestantesSemana = nextMonday.difference(now).inDays;

    try {
      final cutoff   = Timestamp.fromDate(now.subtract(const Duration(days: 7)));
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
