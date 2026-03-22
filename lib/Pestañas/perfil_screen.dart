// lib/screens/perfil_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:RiskRunner/Pesta%C3%B1as/Social_screen.dart' as social;
import 'package:RiskRunner/Widgets/rey_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../Widgets/custom_navbar.dart';
import 'historial_guerra_screen.dart';
import 'package:RiskRunner/models/notif_item.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/league_card_widget.dart';
import '../services/league_service.dart';
import '../models/avatar_config.dart';
import '../Widgets/avatar_widget.dart';
import 'avatar_customizer_screen.dart';
import '../services/zona_service.dart';
import '../services/desafios_service.dart';
import '../services/subscription_service.dart';
import '../services/stats_service.dart';
import 'coin_shop_screen.dart';

const _kMapboxToken   = String.fromEnvironment('MAPBOX_TOKEN');
const _kMapboxStyleId = 'luiisgoomezz1/cmmdzh1aj00f501r68crag5gv';
const _kMapboxTileUrl =
    'https://api.mapbox.com/styles/v1/$_kMapboxStyleId/tiles/256/{z}/{x}/{y}@2x?access_token=$_kMapboxToken';

const _kBg       = Color(0xFF030303);
const _kSurface  = Color(0xFF0C0C0C);
const _kSurface2 = Color(0xFF101010);
const _kBorder   = Color(0xFF161616);
const _kBorder2  = Color(0xFF1F1F1F);
const _kMuted    = Color(0xFF333333);
const _kDim      = Color(0xFF4A4A4A);
const _kSubtext  = Color(0xFF666666);
const _kText     = Color(0xFFB0B0B0);
const _kWhite    = Color(0xFFEEEEEE);
const _kAccent   = Color(0xFFCC2222);
const _kGold     = Color(0xFFD4A017);

TextStyle _rajdhani(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height, List<Shadow>? shadows}) {
  return GoogleFonts.rajdhani(
    fontSize: size, fontWeight: weight, color: color,
    letterSpacing: spacing, height: height, shadows: shadows,
  );
}

class PerfilScreen extends StatefulWidget {
  final String? targetUserId;
  const PerfilScreen({super.key, this.targetUserId});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen>
    with TickerProviderStateMixin {

  String? get myUserId     => FirebaseAuth.instance.currentUser?.uid;
  String? get viewedUserId => widget.targetUserId ?? myUserId;
  bool get isOwnProfile    =>
      widget.targetUserId == null || widget.targetUserId == myUserId;

  final TextEditingController _nicknameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String   nickname         = '';
  String   email            = '';
  int      monedas          = 0;
  int      nivel            = 1;
  int      territorios      = 0;
  String?  fotoBase64;
  bool     isLoading        = true;
  bool     isSaving         = false;
  bool     isUploadingPhoto = false;
  bool _initialized = false;

  double   _kmTotales               = 0;
  double   _velocidadMediaHistorica = 0;
  int      _totalCarreras           = 0;
  int      _territoriosConquistados = 0;
  Duration _tiempoTotalActividad    = Duration.zero;

  List<Map<String, dynamic>> _logros            = [];
  List<Map<String, dynamic>> _carrerasRecientes = [];
  int _rachaActual = 0;

  List<Map<String, dynamic>> _historialCompleto     = [];
  List<Map<String, dynamic>> _historialFiltrado     = [];
  bool _cargandoHistorial       = false;
  bool _verTodoHistorial        = false;
  final TextEditingController _historialSearchCtrl  = TextEditingController();
  static const int _historialPagina = 20;
  int _historialPaginaActual = 1;

  List<NotifItem> _perdidos         = [];
  List<NotifItem> _ganados          = [];
  bool            _loadingHistorial = true;
  int             _tabGuerraIndex   = 0;
  int             _tabPrincipal     = 0;

  Color _colorTerritorio = const Color(0xFF8B1A1A);
  bool  _colorPanelExpandido = false;

  static const List<_RiskColor> _coloresDisponibles = [
    _RiskColor(Color(0xFFD63B3B), 'Rojo Imperio'),
    _RiskColor(Color(0xFF3B6BBF), 'Azul Atlántico'),
    _RiskColor(Color(0xFF4FA830), 'Verde Ejército'),
    _RiskColor(Color(0xFFC49430), 'Ocre Sáhara'),
    _RiskColor(Color(0xFF8B35CC), 'Violeta Regio'),
    _RiskColor(Color(0xFF2EAAAA), 'Teal Glaciar'),
    _RiskColor(Color(0xFFA85820), 'Marrón Fortaleza'),
    _RiskColor(Color(0xFF7A8A96), 'Gris Acero'),
    _RiskColor(Color(0xFFC46830), 'Bronce Asedio'),
    _RiskColor(Color(0xFF2A9470), 'Verde Selva'),
    _RiskColor(Color(0xFFB03070), 'Granate Real'),
    _RiskColor(Color(0xFF5050B0), 'Azul Noche'),
  ];

  String  _friendshipStatus  = 'none';
  String? _friendshipDocId;
  bool    _loadingFriendship = false;

  int         _rangoEnLiga = 0;
  int         _puntosLiga  = 0;
  LeagueInfo? _ligaInfo;

  List<Map<String, dynamic>> _territoriosDelUsuario  = [];
  bool _loadingTerritoriosMapa   = false;
  bool _mapaTerritoriosExpandido = true;

  final MapController _liveMapCtrl = MapController();
  LatLng _liveCenter = const LatLng(40.4168, -3.7038);
  List<Map<String, dynamic>> _allTerritories = [];
  List<Map<String, dynamic>> _liveRunners    = [];
  StreamSubscription<QuerySnapshot>? _territoriesStream;
  StreamSubscription<QuerySnapshot>? _runnersStream;

  AvatarConfig _avatarConfig = const AvatarConfig();

  // ── Sistema de Reyes ─────────────────────────────────────
  bool _esAdmin = false;
  List<TituloRey> _titulosActivos  = [];
  List<TituloRey> _todosLosTitulos = [];
  bool _loadingTitulos = false;

  // ── Contadores de desafíos para badge ────────────────────
  int _desafiosActivosCount = 0;

  // ── Estado premium ────────────────────────────────────────────────────────
  bool _isPremium = false;

  // ── Stats premium ─────────────────────────────────────────────────────────
  List<CarreraStats>  _carrerasPremium   = [];
  List<PuntoTendencia> _tendencia8Semanas = [];
  ComparativaSemanal?  _comparativaSemanal;
  Map<int, String>     _nombresZonas     = {};  // índice territorio → nombre
  bool _loadingStatsPremium = false;
  bool _statsPremiumCargadas = false;

  late AnimationController _entradaAnim;
  late AnimationController _loopAnim;
  late AnimationController _scanAnim;
  late Animation<double> _fadeZona1;
  late Animation<double> _fadeZona2;
  late Animation<double> _fadeZona3;
  late Animation<Offset>  _slideZona2;
  late Animation<Offset>  _slideZona3;
  late Animation<double>  _pulse;
  late Animation<double>  _scan;

  String get _operativeId {
    final uid = viewedUserId ?? '';
    return uid.length >= 6 ? uid.substring(0, 6).toUpperCase() : 'UNKNWN';
  }

  @override
  void initState() {
    super.initState();
    _entradaAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _loopAnim    = AnimationController(vsync: this, duration: const Duration(milliseconds: 4000))..repeat(reverse: true);
    _scanAnim    = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();
    _fadeZona1   = CurvedAnimation(parent: _entradaAnim, curve: const Interval(0.0, 0.5, curve: Curves.easeOut));
    _fadeZona2   = CurvedAnimation(parent: _entradaAnim, curve: const Interval(0.25, 0.75, curve: Curves.easeOut));
    _fadeZona3   = CurvedAnimation(parent: _entradaAnim, curve: const Interval(0.5, 1.0, curve: Curves.easeOut));
    _slideZona2  = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: _entradaAnim, curve: const Interval(0.25, 0.85, curve: Curves.easeOutCubic)));
    _slideZona3  = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: _entradaAnim, curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic)));
    _pulse       = CurvedAnimation(parent: _loopAnim, curve: Curves.easeInOut);
    _scan        = CurvedAnimation(parent: _scanAnim, curve: Curves.linear);
    _cargarTodo();
    _escucharConteoDesafios();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized && isOwnProfile) _recargarDatosDinamicos();
    _initialized = true;
  }

  @override
  void dispose() {
    _cancelLiveStreams();
    _liveMapCtrl.dispose();
    _nicknameController.dispose();
    _historialSearchCtrl.dispose();
    _entradaAnim.dispose();
    _loopAnim.dispose();
    _scanAnim.dispose();
    super.dispose();
  }

  // ── Cargar stats premium (lazy — solo cuando se abre el tab STATS) ─────────
  Future<void> _cargarStatsPremium() async {
    if (!_isPremium || _statsPremiumCargadas || _loadingStatsPremium) return;
    if (viewedUserId == null) return;
    setState(() => _loadingStatsPremium = true);
    try {
      // Carreras de las últimas 8 semanas (máx 200 — límite premium)
      final uid = viewedUserId!;
      final snap = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('userId', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(200)
          .get();

      final carreras = <CarreraStats>[];
      for (final doc in snap.docs) {
        final d        = doc.data();
        final distancia = (d['distancia'] as num?)?.toDouble() ?? 0;
        final tiempo    = (d['tiempo_segundos'] as num?)?.toInt() ?? 0;
        if (distancia <= 0 || tiempo <= 0) continue;
        final ts     = (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
        final ritmo  = distancia > 0 && tiempo > 0
            ? (tiempo / 60) / distancia : 0.0;
        final zonas  = [
          ZonaRitmo.competicion, ZonaRitmo.umbral,
          ZonaRitmo.moderado, ZonaRitmo.facil, ZonaRitmo.recuperacion
        ];
        final zona = ritmo < 4.5 ? ZonaRitmo.competicion
            : ritmo < 5.5 ? ZonaRitmo.umbral
            : ritmo < 6.5 ? ZonaRitmo.moderado
            : ritmo < 7.5 ? ZonaRitmo.facil
            : ZonaRitmo.recuperacion;
        carreras.add(CarreraStats(
          id: doc.id, fecha: ts,
          distanciaKm: distancia, tiempoSeg: tiempo,
          ritmoMinKm: ritmo, zona: zona, calles: [], ruta: [],
        ));
      }

      final tendencia    = StatsService.calcularTendencia8Semanas(carreras);
      final comparativa  = StatsService.calcularComparativaSemanal(carreras);

      // Geocoding de territorios — centroide de cada territorio
      final Map<int, String> nombres = {};
      if (_territoriosDelUsuario.isNotEmpty) {
        final centroides = _territoriosDelUsuario.map((t) {
          final pts  = t['puntos'] as List<LatLng>;
          final latC = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
          final lngC = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
          return LatLng(latC, lngC);
        }).toList();
        // Limitar a 20 territorios para no saturar Mapbox
        final limitados = centroides.take(20).toList();
        final resultado  = await StatsService.geocodificarTerritorios(limitados);
        nombres.addAll(resultado);
      }

      if (mounted) setState(() {
        _carrerasPremium    = carreras;
        _tendencia8Semanas  = tendencia;
        _comparativaSemanal = comparativa;
        _nombresZonas       = nombres;
        _loadingStatsPremium   = false;
        _statsPremiumCargadas  = true;
      });
    } catch (e) {
      debugPrint('Error cargando stats premium: $e');
      if (mounted) setState(() => _loadingStatsPremium = false);
    }
  }

  // ── Escuchar conteo de desafíos activos para el badge ────────────────────
  void _escucharConteoDesafios() {
    if (viewedUserId == null) return;
    final uid = viewedUserId!;

    // Combinamos retador + retado
    FirebaseFirestore.instance
        .collection('desafios')
        .where('retadorId', isEqualTo: uid)
        .where('estado', isEqualTo: 'activo')
        .snapshots()
        .listen((s1) {
      FirebaseFirestore.instance
          .collection('desafios')
          .where('retadoId', isEqualTo: uid)
          .where('estado', isEqualTo: 'activo')
          .get()
          .then((s2) {
        if (mounted) {
          setState(() =>
              _desafiosActivosCount = s1.docs.length + s2.docs.length);
        }
      });
    });
  }

  Future<void> _recargarDatosDinamicos() async {
    if (viewedUserId == null) return;
    await Future.wait([
      _cargarEstadisticas(), _cargarLogros(), _cargarCarrerasRecientes(),
      _cargarHistorialGuerra(), _cargarRacha(), _cargarHistorialCompleto(),
      _cargarTitulos(),
    ]);
  }

  Future<void> _cargarTodo() async {
    if (viewedUserId == null) return;
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _cargarPerfil(), _cargarEstadisticas(), _cargarLogros(),
        _cargarCarrerasRecientes(), _cargarRangoEnLiga(), _cargarRacha(),
        _cargarHistorialGuerra(), _cargarHistorialCompleto(),
        _cargarTitulos(),
        if (!isOwnProfile) _cargarEstadoAmistad(),
      ]);
    } catch (e) {
      debugPrint('Error cargando perfil: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        _entradaAnim.forward();
        _initLiveMap();
      }
    }
  }

  Future<void> _cargarTitulos() async {
    if (viewedUserId == null) return;
    if (mounted) setState(() => _loadingTitulos = true);
    try {
      final resultados = await Future.wait([
        ZonaService.getTitulosDeUsuario(viewedUserId!),
        ZonaService.getTitulosActivosDeUsuario(viewedUserId!),
      ]);
      if (mounted) setState(() {
        _todosLosTitulos = resultados[0];
        _titulosActivos  = resultados[1];
        _loadingTitulos  = false;
      });
    } catch (e) {
      debugPrint('Error títulos: $e');
      if (mounted) setState(() => _loadingTitulos = false);
    }
  }

  Future<void> _cargarHistorialCompleto() async {
    if (viewedUserId == null) return;
    if (mounted) setState(() => _cargandoHistorial = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('userId', isEqualTo: viewedUserId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get()
          .timeout(const Duration(seconds: 6));
      final lista = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        lista.add({
          'titulo'    : d['titulo'] ?? 'Carrera completada',
          'recompensa': (d['recompensa'] as num? ?? 0).toInt(),
          'fecha'     : d['fecha_dia'] ?? 'Reciente',
          'timestamp' : d['timestamp'],
          'distancia' : (d['distancia'] as num? ?? 0).toDouble(),
          'tiempo_segundos': (d['tiempo_segundos'] as num? ?? 0).toInt(),
          'velocidad_media': (d['velocidad_media'] as num? ?? 0).toDouble(),
        });
      }
      if (mounted) setState(() {
        _historialCompleto     = lista;
        _historialFiltrado     = lista;
        _historialPaginaActual = 1;
        _cargandoHistorial     = false;
      });
    } catch (e) {
      debugPrint('Error historial completo: $e');
      if (mounted) setState(() => _cargandoHistorial = false);
    }
  }

  void _filtrarHistorial(String q) => setState(() {
    _historialFiltrado = _historialCompleto
        .where((l) => l['titulo'].toString().toLowerCase().contains(q.toLowerCase()))
        .toList();
    _historialPaginaActual = 1;
  });

  Future<void> _cargarPerfil() async {
    final doc = await FirebaseFirestore.instance.collection('players').doc(viewedUserId).get();
    if (!doc.exists || !mounted) return;
    final data           = doc.data()!;
    final territoriosSnap = await FirebaseFirestore.instance.collection('territories').where('userId', isEqualTo: viewedUserId).get();
    final colorInt       = (data['territorio_color'] as num?)?.toInt();
    final pts            = (data['puntos_liga'] as num? ?? 0).toInt();
    final liga           = LeagueHelper.getLeague(pts);
    final avatarMap      = data['avatar_config'] as Map<String, dynamic>?;
    if (avatarMap != null) {
      try { _avatarConfig = AvatarConfig.fromMap(avatarMap); } catch (e) { debugPrint('Error avatar config: $e'); }
    }
    setState(() {
      nickname    = data['nickname'] as String? ?? '';
      email       = isOwnProfile ? (data['email'] as String? ?? FirebaseAuth.instance.currentUser?.email ?? '') : '';
      monedas     = (data['monedas'] as num?)?.toInt() ?? 0;
      nivel       = (data['nivel'] as num?)?.toInt() ?? 1;
      territorios = territoriosSnap.docs.length;
      fotoBase64  = data['foto_base64'] as String?;
      _puntosLiga = pts;
      _ligaInfo   = liga;
      if (isOwnProfile) _nicknameController.text = nickname;
      if (colorInt != null) _colorTerritorio = Color(colorInt);
      if (avatarMap != null) _avatarConfig = AvatarConfig.fromMap(avatarMap);
      if (isOwnProfile) _esAdmin = data['esAdmin'] as bool? ?? false;
      _isPremium = (data['is_premium'] as bool?) ??
          SubscriptionService.currentStatus.isPremium;
    });
  }

  Future<void> _abrirCustomizador() async {
    if (!isOwnProfile) return;
    final nuevaConfig = await Navigator.push<AvatarConfig>(context, MaterialPageRoute(builder: (_) => AvatarCustomizerScreen(initialConfig: _avatarConfig, monedas: monedas)));
    if (nuevaConfig != null && mounted) setState(() => _avatarConfig = nuevaConfig);
  }

  Future<void> _cargarRangoEnLiga() async {
    try {
      final myDoc = await FirebaseFirestore.instance.collection('players').doc(viewedUserId).get();
      if (!myDoc.exists) return;
      final myPts    = (myDoc.data()?['puntos_liga'] as num? ?? 0).toInt();
      final ligaInfo = LeagueHelper.getLeague(myPts);
      final int maxPts = ligaInfo.maxPts ?? 999999;
      final rankQ = await FirebaseFirestore.instance.collection('players').where('puntos_liga', isGreaterThan: myPts).where('puntos_liga', isLessThanOrEqualTo: maxPts).count().get();
      if (mounted) { final int raw = (rankQ.count as num?)?.toInt() ?? 0; setState(() => _rangoEnLiga = raw + 1); }
    } catch (e) { debugPrint('Error rango: $e'); if (mounted) setState(() => _rangoEnLiga = 0); }
  }

  Future<void> _cargarEstadoAmistad() async {
    if (myUserId == null || viewedUserId == null) return;
    try {
      final q1 = await FirebaseFirestore.instance.collection('friendships').where('senderId', isEqualTo: myUserId).where('receiverId', isEqualTo: viewedUserId).limit(1).get();
      if (q1.docs.isNotEmpty) {
        final d = q1.docs.first;
        setState(() { _friendshipDocId = d.id; _friendshipStatus = d['status'] == 'accepted' ? 'accepted' : 'pending_sent'; });
        return;
      }
      final q2 = await FirebaseFirestore.instance.collection('friendships').where('senderId', isEqualTo: viewedUserId).where('receiverId', isEqualTo: myUserId).limit(1).get();
      if (q2.docs.isNotEmpty) {
        final d = q2.docs.first;
        setState(() { _friendshipDocId = d.id; _friendshipStatus = d['status'] == 'accepted' ? 'accepted' : 'pending_received'; });
        return;
      }
      setState(() => _friendshipStatus = 'none');
    } catch (e) { debugPrint('Error amistad: $e'); }
  }

  Future<void> _enviarSolicitudAmistad() async {
    if (myUserId == null || viewedUserId == null) return;
    setState(() => _loadingFriendship = true);
    try {
      final ref = await FirebaseFirestore.instance.collection('friendships').add({'senderId': myUserId, 'receiverId': viewedUserId, 'status': 'pending', 'timestamp': FieldValue.serverTimestamp()});
      await FirebaseFirestore.instance.collection('notifications').add({'toUserId': viewedUserId, 'type': 'friend_request', 'fromUserId': myUserId, 'fromNickname': await _getMyNickname(), 'message': 'Te ha enviado una solicitud de amistad', 'read': false, 'timestamp': FieldValue.serverTimestamp()});
      setState(() { _friendshipStatus = 'pending_sent'; _friendshipDocId = ref.id; });
    } catch (e) { debugPrint('Error solicitud: $e'); }
    finally { if (mounted) setState(() => _loadingFriendship = false); }
  }

  Future<void> _aceptarSolicitud() async {
    if (_friendshipDocId == null) return;
    setState(() => _loadingFriendship = true);
    try {
      await FirebaseFirestore.instance.collection('friendships').doc(_friendshipDocId).update({'status': 'accepted'});
      setState(() => _friendshipStatus = 'accepted');
    } catch (e) { debugPrint('Error aceptando: $e'); }
    finally { if (mounted) setState(() => _loadingFriendship = false); }
  }

  Future<void> _eliminarAmistad() async {
    if (_friendshipDocId == null) return;
    setState(() => _loadingFriendship = true);
    try {
      await FirebaseFirestore.instance.collection('friendships').doc(_friendshipDocId).delete();
      setState(() { _friendshipStatus = 'none'; _friendshipDocId = null; });
    } catch (e) { debugPrint('Error eliminando amistad: $e'); }
    finally { if (mounted) setState(() => _loadingFriendship = false); }
  }

  Future<String> _getMyNickname() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('players').doc(myUserId).get();
      return doc.data()?['nickname'] as String? ?? 'Runner';
    } catch (_) { return 'Runner'; }
  }

  Future<void> _cargarTerritoriosDelUsuario() async {
    if (viewedUserId == null) return;
    setState(() => _loadingTerritoriosMapa = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('territories').where('userId', isEqualTo: viewedUserId).get();
      final List<Map<String, dynamic>> lista = [];
      for (final doc in snap.docs) {
        final data      = doc.data();
        final rawPuntos = data['puntos'] as List<dynamic>?;
        if (rawPuntos == null || rawPuntos.isEmpty) continue;
        final puntos = rawPuntos.map((p) { final m = p as Map<String, dynamic>; return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()); }).toList();
        lista.add({'docId': doc.id, 'puntos': puntos});
      }
      if (mounted) setState(() { _territoriosDelUsuario = lista; _loadingTerritoriosMapa = false; _mapaTerritoriosExpandido = true; _initLiveMap(); });
    } catch (e) { debugPrint('Error territorios: $e'); if (mounted) setState(() => _loadingTerritoriosMapa = false); }
  }

  Future<void> _initLiveMap() async {
    if (_territoriosDelUsuario.isNotEmpty) {
      final pts = _territoriosDelUsuario.first['puntos'] as List<LatLng>;
      if (pts.isNotEmpty) {
        final lat = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
        final lng = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
        if (mounted) setState(() => _liveCenter = LatLng(lat, lng));
      }
    }
    _territoriesStream = FirebaseFirestore.instance.collection('territories').limit(200).snapshots().listen((snap) {
      if (!mounted) return;
      final lista = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final raw  = data['puntos'] as List<dynamic>?;
        if (raw == null || raw.isEmpty) continue;
        final pts = raw.map((p) { final m = p as Map<String, dynamic>; return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()); }).toList();
        final colorVal = (data['color'] as num?)?.toInt();
        lista.add({'puntos': pts, 'userId': data['userId'] ?? '', 'color': colorVal != null ? Color(colorVal) : const Color(0xFF2EAAAA)});
      }
      setState(() => _allTerritories = lista);
    });
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    _runnersStream = FirebaseFirestore.instance.collection('active_runners').where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff)).snapshots().listen((snap) {
      if (!mounted) return;
      final runners = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final lat = (d['lat'] as num?)?.toDouble();
        final lng = (d['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        final trail    = (d['trail'] as List<dynamic>? ?? []).map((p) { final m = p as Map<String, dynamic>; return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()); }).toList();
        final colorVal = (d['color'] as num?)?.toInt();
        runners.add({'uid': doc.id, 'pos': LatLng(lat, lng), 'trail': trail, 'nickname': d['nickname'] ?? '?', 'color': colorVal != null ? Color(colorVal) : const Color(0xFF2EAAAA), 'isMe': doc.id == myUserId});
      }
      setState(() => _liveRunners = runners);
    });
  }

  void _cancelLiveStreams() {
    _territoriesStream?.cancel();
    _runnersStream?.cancel();
  }

  // ═══════════════════════════════════════════════════════════
  //  DESAFÍO — botón retar (perfil ajeno)
  // ═══════════════════════════════════════════════════════════

  Widget _buildBotonRetar() {
    return GestureDetector(
      onTap: _mostrarModalReto,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: _kAccent.withOpacity(0.07),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _kAccent.withOpacity(0.35)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('⚔️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Text('RETAR', style: _rajdhani(12, FontWeight.w900, _kAccent, spacing: 1.5)),
        ]),
      ),
    );
  }

  Future<void> _mostrarModalReto({
    bool esContrapropuesta = false,
    int apuestaInicial = 50,
    int horasIniciales = 24,
    String? desafioId,
  }) async {
    if (myUserId == null) return;
    final myDoc      = await FirebaseFirestore.instance.collection('players').doc(myUserId).get();
    final misMonedas = (myDoc.data()?['monedas'] as num?)?.toInt() ?? 0;
    int apuesta = apuestaInicial;
    int horas   = horasIniciales;
    final horasCtrl = TextEditingController(text: '$horasIniciales');

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 3, color: _kMuted)),
            const SizedBox(height: 24),
            Row(children: [
              Container(width: 2, height: 16, color: _kAccent),
              const SizedBox(width: 10),
              Text(esContrapropuesta ? 'CONTRAPROPONAR' : 'DESAFÍO DIRECTO', style: _rajdhani(13, FontWeight.w900, _kWhite, spacing: 2)),
            ]),
            const SizedBox(height: 6),
            Text(esContrapropuesta ? 'Propón tus condiciones a ${nickname.toUpperCase()}' : 'Reta a ${nickname.toUpperCase()} a quien conquista más', style: _rajdhani(12, FontWeight.w500, _kSubtext)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _kSurface2, border: Border.all(color: _kBorder2)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('APUESTA', style: _rajdhani(9, FontWeight.w700, _kDim, spacing: 2)),
                const SizedBox(height: 12),
                Row(children: [
                  GestureDetector(onTap: () => setModal(() => apuesta = (apuesta - 25).clamp(25, misMonedas)), child: Container(width: 36, height: 36, color: _kMuted, child: const Icon(Icons.remove, color: Colors.white, size: 16))),
                  Expanded(child: Center(child: Text('$apuesta 🪙', style: _rajdhani(28, FontWeight.w900, _kWhite)))),
                  GestureDetector(onTap: () => setModal(() => apuesta = (apuesta + 25).clamp(25, misMonedas)), child: Container(width: 36, height: 36, color: _kMuted, child: const Icon(Icons.add, color: Colors.white, size: 16))),
                ]),
                const SizedBox(height: 8),
                Center(child: Text('Tienes $misMonedas 🪙 disponibles', style: _rajdhani(10, FontWeight.w500, _kSubtext))),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _kSurface2, border: Border.all(color: _kBorder2)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('DURACIÓN (HORAS)', style: _rajdhani(9, FontWeight.w700, _kDim, spacing: 2)),
                const SizedBox(height: 12),
                Row(children: [
                  GestureDetector(onTap: () { setModal(() => horas = (horas - 1).clamp(1, 168)); horasCtrl.text = '$horas'; }, child: Container(width: 36, height: 36, color: _kMuted, child: const Icon(Icons.remove, color: Colors.white, size: 16))),
                  Expanded(child: TextField(controller: horasCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: _rajdhani(22, FontWeight.w900, _kWhite), decoration: InputDecoration(border: InputBorder.none, suffix: Text('h', style: _rajdhani(14, FontWeight.w600, _kSubtext))), onChanged: (v) { final parsed = int.tryParse(v); if (parsed != null) setModal(() => horas = parsed.clamp(1, 168)); })),
                  GestureDetector(onTap: () { setModal(() => horas = (horas + 1).clamp(1, 168)); horasCtrl.text = '$horas'; }, child: Container(width: 36, height: 36, color: _kMuted, child: const Icon(Icons.add, color: Colors.white, size: 16))),
                ]),
                const SizedBox(height: 4),
                Center(child: Text('Mínimo 1h · Máximo 168h (7 días)', style: _rajdhani(9, FontWeight.w500, _kSubtext))),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _kAccent.withOpacity(0.04), border: Border(left: BorderSide(color: _kAccent, width: 2), top: BorderSide(color: _kBorder2), right: BorderSide(color: _kBorder2), bottom: BorderSide(color: _kBorder2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PUNTUACIÓN', style: _rajdhani(9, FontWeight.w700, _kDim, spacing: 2)),
                const SizedBox(height: 6),
                Text('Territorios conquistados × 10', style: _rajdhani(11, FontWeight.w500, _kSubtext)),
                Text('Kilómetros corridos × 5', style: _rajdhani(11, FontWeight.w500, _kSubtext)),
              ]),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () { Navigator.pop(ctx); if (esContrapropuesta && desafioId != null) { _enviarContrapropuesta(desafioId, apuesta, horas); } else { _enviarReto(apuesta, horas); } },
              child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15), color: _kAccent, child: Text(esContrapropuesta ? '🔄  ENVIAR CONTRAPROPUESTA' : '⚔️  ENVIAR DESAFÍO', textAlign: TextAlign.center, style: _rajdhani(13, FontWeight.w900, Colors.white, spacing: 2))),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _enviarReto(int apuesta, int horas) async {
    if (myUserId == null || viewedUserId == null) return;
    try {
      final myDoc      = await FirebaseFirestore.instance.collection('players').doc(myUserId).get();
      final myNick     = myDoc.data()?['nickname'] as String? ?? 'Runner';
      final misMonedas = (myDoc.data()?['monedas'] as num?)?.toInt() ?? 0;
      if (misMonedas < apuesta) { _mostrarSnackbar('No tienes suficientes monedas', error: true); return; }
      await FirebaseFirestore.instance.collection('desafios').add({'retadorId': myUserId, 'retadorNick': myNick, 'retadoId': viewedUserId, 'retadoNick': nickname, 'apuesta': apuesta, 'duracionHoras': horas, 'estado': 'pendiente', 'rondas': 0, 'puntosRetador': 0, 'puntosRetado': 0, 'timestamp': FieldValue.serverTimestamp()});
      await FirebaseFirestore.instance.collection('notifications').add({'toUserId': viewedUserId, 'type': 'desafio_recibido', 'fromUserId': myUserId, 'fromNickname': myNick, 'message': '⚔️ $myNick te reta: ${horas}h · $apuesta 🪙. ¿Aceptas?', 'apuesta': apuesta, 'duracionHoras': horas, 'esContrapropuesta': false, 'read': false, 'timestamp': FieldValue.serverTimestamp()});
      await FirebaseFirestore.instance.collection('players').doc(myUserId).update({'monedas': FieldValue.increment(-apuesta)});
      _mostrarSnackbar('¡Desafío enviado!');
    } catch (e) { _mostrarSnackbar('Error al enviar el desafío', error: true); }
  }

  Future<void> _enviarContrapropuesta(String desafioId, int apuesta, int horas) async {
    if (myUserId == null) return;
    try {
      final myDoc      = await FirebaseFirestore.instance.collection('players').doc(myUserId).get();
      final myNick     = myDoc.data()?['nickname'] as String? ?? 'Runner';
      final misMonedas = (myDoc.data()?['monedas'] as num?)?.toInt() ?? 0;
      if (misMonedas < apuesta) { _mostrarSnackbar('No tienes suficientes monedas', error: true); return; }
      await FirebaseFirestore.instance.collection('desafios').doc(desafioId).update({'estado': 'contrapropuesta', 'rondas': 1, 'propuestaApuesta': apuesta, 'propuestaDuracion': horas, 'contrapropuestaDeId': myUserId});
      final desafioDoc = await FirebaseFirestore.instance.collection('desafios').doc(desafioId).get();
      final data       = desafioDoc.data()!;
      final retadorId  = data['retadorId'] as String;
      final toUserId   = myUserId == retadorId ? data['retadoId'] : retadorId;
      await FirebaseFirestore.instance.collection('notifications').add({'toUserId': toUserId, 'type': 'desafio_recibido', 'fromUserId': myUserId, 'fromNickname': myNick, 'desafioId': desafioId, 'message': '🔄 $myNick contrapropone: ${horas}h · $apuesta 🪙', 'apuesta': apuesta, 'duracionHoras': horas, 'esContrapropuesta': true, 'read': false, 'timestamp': FieldValue.serverTimestamp()});
      _mostrarSnackbar('Contrapropuesta enviada');
    } catch (e) { _mostrarSnackbar('Error al enviar contrapropuesta', error: true); }
  }

  void _abrirChat() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => social.ChatScreen(currentUserId: myUserId!, friendId: widget.targetUserId!, friendNickname: nickname, friendFoto: fotoBase64)));
  }

  Future<void> _cargarRacha() async {
    if (viewedUserId == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('players').doc(viewedUserId).get();
      if (!doc.exists) return;
      final data = doc.data()!;
      final int racha = (data['racha_actual'] as num?)?.toInt() ?? 0;
      final Timestamp? ultimaFechaTs = data['ultima_fecha_actividad'] as Timestamp?;
      int rachaVisible = racha;
      if (ultimaFechaTs != null) {
        final DateTime ultima     = ultimaFechaTs.toDate();
        final DateTime hoySinHora = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
        final DateTime ultimaSinH = DateTime(ultima.year, ultima.month, ultima.day);
        if (hoySinHora.difference(ultimaSinH).inDays > 1) rachaVisible = 0;
      }
      if (mounted) setState(() => _rachaActual = rachaVisible);
    } catch (e) { debugPrint('Error racha: $e'); }
  }

  Future<void> _cargarEstadisticas() async {
    try {
      final logsSnap = await FirebaseFirestore.instance.collection('activity_logs').where('userId', isEqualTo: viewedUserId).get();
      double kmTotal = 0, sumVel = 0;
      int countVel = 0, totalSeg = 0;
      for (final doc in logsSnap.docs) {
        final d    = doc.data();
        final dist = (d['distancia'] as num?)?.toDouble() ?? 0;
        final seg  = (d['tiempo_segundos'] as num?)?.toInt() ?? 0;
        kmTotal += dist; totalSeg += seg;
        if (dist > 0 && seg > 0) { sumVel += dist / (seg / 3600); countVel++; }
      }
      final conqSnap = await FirebaseFirestore.instance.collection('notifications').where('toUserId', isEqualTo: viewedUserId).where('type', isEqualTo: 'territory_conquered').limit(500).get();
      if (mounted) setState(() {
        _kmTotales               = kmTotal;
        _velocidadMediaHistorica = countVel > 0 ? sumVel / countVel : 0;
        _totalCarreras           = logsSnap.docs.length;
        _tiempoTotalActividad    = Duration(seconds: totalSeg);
        _territoriosConquistados = conqSnap.docs.length;
      });
    } catch (e) { debugPrint('Error stats: $e'); }
  }

  Future<void> _cargarLogros() async {
    try {
      final logsSnap = await FirebaseFirestore.instance.collection('activity_logs').where('userId', isEqualTo: viewedUserId).get();
      final List<Map<String, dynamic>> logrosData = [];
      final Set<String> idsVistos = {};
      for (final doc in logsSnap.docs) {
        final d      = doc.data();
        final idReto = d['id_reto_completado']?.toString();
        if (idReto == null || d['titulo'] == null) continue;
        if (idsVistos.contains(idReto)) continue;
        idsVistos.add(idReto);
        logrosData.add({...d, 'docId': doc.id});
      }
      logrosData.sort((a, b) {
        final tA = a['timestamp'] as Timestamp?;
        final tB = b['timestamp'] as Timestamp?;
        if (tA == null && tB == null) return 0;
        if (tA == null) return 1;
        if (tB == null) return -1;
        return tB.compareTo(tA);
      });
      if (mounted) setState(() => _logros = logrosData.take(10).toList());
    } catch (e) { debugPrint('Error logros: $e'); }
  }

  Future<void> _cargarCarrerasRecientes() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('activity_logs').where('userId', isEqualTo: viewedUserId).get();
      final List<Map<String, dynamic>> carreras = [];
      for (final doc in snap.docs) {
        final d    = doc.data();
        final dist = (d['distancia'] as num?)?.toDouble() ?? 0;
        if (dist > 0) carreras.add({...d, 'docId': doc.id});
      }
      carreras.sort((a, b) {
        final tA = a['timestamp'] as Timestamp?;
        final tB = b['timestamp'] as Timestamp?;
        if (tA == null && tB == null) return 0;
        if (tA == null) return 1;
        if (tB == null) return -1;
        return tB.compareTo(tA);
      });
      if (mounted) setState(() => _carrerasRecientes = carreras.take(5).toList());
    } catch (e) { debugPrint('Error carreras: $e'); }
  }

  Future<void> _cargarHistorialGuerra() async {
    if (viewedUserId == null) return;
    setState(() => _loadingHistorial = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('notifications').where('toUserId', isEqualTo: viewedUserId).limit(200).get();
      final List<NotifItem> perdidos = [], ganados = [];
      for (final doc in snap.docs) {
        final item = NotifItem.fromFirestore(doc);
        if (item.tipo == 'territory_lost') perdidos.add(item);
        else if (item.tipo == 'territory_conquered' || item.tipo == 'territory_steal_success') ganados.add(item);
      }
      for (final list in [perdidos, ganados]) { list.sort((a, b) { if (a.timestamp == null || b.timestamp == null) return 0; return b.timestamp!.compareTo(a.timestamp!); }); }
      if (mounted) setState(() { _perdidos = perdidos; _ganados = ganados; _loadingHistorial = false; });
    } catch (e) { debugPrint('Error historial: $e'); if (mounted) setState(() => _loadingHistorial = false); }
  }

  Future<void> _seleccionarFoto() async {
    if (!isOwnProfile) return;
    showModalBottomSheet(
      context: context, backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 3, decoration: BoxDecoration(color: _kMuted, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Text('FOTO DE PERFIL', style: _rajdhani(11, FontWeight.w700, _kDim, spacing: 3)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _BotonFoto(icon: Icons.camera_alt_outlined, label: 'Cámara', accent: _kAccent, onTap: () { Navigator.pop(ctx); _tomarFoto(ImageSource.camera); })),
            const SizedBox(width: 12),
            Expanded(child: _BotonFoto(icon: Icons.photo_library_outlined, label: 'Galería', accent: _kAccent, onTap: () { Navigator.pop(ctx); _tomarFoto(ImageSource.gallery); })),
          ]),
          if (fotoBase64 != null) ...[const SizedBox(height: 12), SizedBox(width: double.infinity, child: TextButton.icon(onPressed: () { Navigator.pop(ctx); _eliminarFoto(); }, icon: const Icon(Icons.delete_outline, color: Colors.redAccent), label: Text('Eliminar foto', style: _rajdhani(13, FontWeight.w600, Colors.redAccent))))],
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _tomarFoto(ImageSource source) async {
    if (!isOwnProfile) return;
    try {
      final XFile? imagen = await _picker.pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 80);
      if (imagen == null) return;
      setState(() => isUploadingPhoto = true);
      Uint8List? bytes;
      if (kIsWeb) { bytes = await imagen.readAsBytes(); }
      else { bytes = await FlutterImageCompress.compressWithFile(imagen.path, minWidth: 256, minHeight: 256, quality: 70, format: CompressFormat.jpeg); }
      if (bytes == null) { setState(() => isUploadingPhoto = false); return; }
      final b64 = base64Encode(bytes);
      await FirebaseFirestore.instance.collection('players').doc(myUserId).update({'foto_base64': b64});
      if (mounted) { setState(() { fotoBase64 = b64; isUploadingPhoto = false; }); _mostrarSnackbar('Foto actualizada'); }
    } catch (e) { if (mounted) { setState(() => isUploadingPhoto = false); _mostrarSnackbar('Error al subir la foto', error: true); } }
  }

  Future<void> _eliminarFoto() async {
    if (!isOwnProfile) return;
    try {
      await FirebaseFirestore.instance.collection('players').doc(myUserId).update({'foto_base64': FieldValue.delete()});
      if (mounted) { setState(() => fotoBase64 = null); _mostrarSnackbar('Foto eliminada'); }
    } catch (_) { _mostrarSnackbar('Error al eliminar la foto', error: true); }
  }

  Future<void> _guardarNickname() async {
    if (!isOwnProfile) return;
    final nn = _nicknameController.text.trim();
    if (nn.isEmpty)  { _mostrarSnackbar('El nickname no puede estar vacío', error: true); return; }
    if (nn == nickname) { _mostrarSnackbar('El nickname no ha cambiado'); return; }
    if (nn.length < 3) { _mostrarSnackbar('Mínimo 3 caracteres', error: true); return; }
    setState(() => isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('players').doc(myUserId).update({'nickname': nn});
      if (mounted) { setState(() { nickname = nn; isSaving = false; }); _mostrarSnackbar('Nickname actualizado'); }
    } catch (_) { if (mounted) { setState(() => isSaving = false); _mostrarSnackbar('Error al guardar', error: true); } }
  }

  Future<void> _guardarColorTerritorio(Color color) async {
    if (!isOwnProfile) return;
    setState(() => _colorTerritorio = color);
    try {
      await FirebaseFirestore.instance.collection('players').doc(myUserId).update({'territorio_color': color.value});
      _mostrarSnackbar('Color de territorio actualizado');
    } catch (_) { _mostrarSnackbar('Error al guardar el color', error: true); }
  }

  void _mostrarSnackbar(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: _rajdhani(13, FontWeight.w700, Colors.black)),
      backgroundColor: error ? Colors.redAccent : _kAccent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ));
  }

  void _mostrarDialogoEditarNickname() {
    if (!isOwnProfile) return;
    _nicknameController.text = nickname;
    showModalBottomSheet(
      context: context, backgroundColor: _kSurface, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 3, decoration: BoxDecoration(color: _kMuted, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 24),
          Text('EDITAR CALLSIGN', style: _rajdhani(11, FontWeight.w700, _kText, spacing: 3)),
          const SizedBox(height: 4),
          Text('Se actualizará en toda la app', style: _rajdhani(12, FontWeight.w400, _kSubtext)),
          const SizedBox(height: 20),
          TextField(
            controller: _nicknameController, autofocus: true, maxLength: 20,
            style: _rajdhani(20, FontWeight.w700, Colors.white, spacing: 1),
            decoration: InputDecoration(hintText: 'Tu callsign...', hintStyle: _rajdhani(20, FontWeight.w400, _kMuted), prefixIcon: const Icon(Icons.terminal_rounded, color: _kDim, size: 18), filled: true, fillColor: _kSurface2, counterStyle: _rajdhani(10, FontWeight.w400, _kSubtext), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kText, width: 1.5))),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { Navigator.pop(ctx); _guardarNickname(); }, style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0), child: Text('CONFIRMAR', style: _rajdhani(13, FontWeight.w700, Colors.black, spacing: 3)))),
        ]),
      ),
    );
  }

  String _formatTiempo(Duration d) {
    final h = d.inHours; final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
  }
  String _formatFechaCorta(dynamic ts) {
    if (ts == null || ts is! Timestamp) return '--';
    final dt = ts.toDate();
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }
  String _nivelTitulo(int n) {
    if (n >= 50) return 'LEYENDA';
    if (n >= 30) return 'ÉLITE';
    if (n >= 20) return 'VETERANO';
    if (n >= 10) return 'EXPLORADOR';
    return 'ROOKIE';
  }
  String _formatearTiempoGuerra(Timestamp? ts) {
    if (ts == null) return '--';
    final dif = DateTime.now().difference(ts.toDate());
    if (dif.inMinutes < 1)  return 'Ahora';
    if (dif.inMinutes < 60) return '${dif.inMinutes}m';
    if (dif.inHours < 24)   return '${dif.inHours}h';
    if (dif.inDays == 1)    return 'Ayer';
    if (dif.inDays < 7)     return '${dif.inDays}d';
    final dt = ts.toDate();
    return '${dt.day}/${dt.month}';
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: isLoading ? _buildLoader() : _buildContent(),
      bottomNavigationBar: isOwnProfile ? const CustomBottomNavbar(currentIndex: 4) : null,
    );
  }

  AppBar _buildAppBar() => AppBar(
    backgroundColor: Colors.transparent, elevation: 0,
    leading: !isOwnProfile ? IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 18), onPressed: () => Navigator.pop(context)) : null,
    actions: isOwnProfile ? [
      IconButton(icon: const Icon(Icons.refresh_rounded, color: _kDim, size: 20), onPressed: _cargarTodo),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: _kDim, size: 20),
        color: _kSurface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: _kBorder2)),
        onSelected: (v) async {
          switch (v) {
            case 'avatar': _abrirCustomizador(); break;
            case 'guerra': Navigator.push(context, MaterialPageRoute(builder: (_) => const HistorialGuerraScreen())); break;
            case 'liga':
              _mostrarSnackbar('Inicializando ligas...');
              await LeagueService.migrarJugadoresSinLiga();
              await _cargarTodo();
              _mostrarSnackbar('Ligas inicializadas');
              break;
            case 'temporada': _mostrarDialogoCerrarTemporada(); break;
            case 'logout':
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
              break;
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'avatar', child: _popupItem(Icons.palette_rounded, 'Personalizar avatar', _kText)),
          PopupMenuItem(value: 'guerra', child: _popupItem(Icons.history_rounded, 'Historial de guerra', Colors.redAccent)),
          PopupMenuItem(value: 'liga', child: _popupItem(Icons.sync_rounded, 'Inicializar puntos de liga', Colors.tealAccent)),
          if (_esAdmin)
            PopupMenuItem(value: 'temporada', child: _popupItem(Icons.emoji_events_rounded, 'Cerrar temporada', _kGold)),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'logout', child: _popupItem(Icons.logout_rounded, 'Cerrar sesión', Colors.redAccent)),
        ],
      ),
      const SizedBox(width: 4),
    ] : [],
  );

  void _mostrarDialogoCerrarTemporada() async {
    final temporada = await ZonaService.getTemporadaActiva();
    if (!mounted) return;
    if (temporada == null) { _mostrarSnackbar('No hay temporada activa', error: true); return; }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _kBorder2)),
        title: Row(children: [
          const Text('👑', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Text('Cerrar ${temporada.label}', style: _rajdhani(16, FontWeight.w700, _kWhite)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Se calculará el rey de cada barrio y se entregarán las recompensas.', style: _rajdhani(13, FontWeight.w400, _kSubtext)),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _kGold.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(6), border: Border.all(color: _kGold.withValues(alpha: 0.20))), child: Text('Recompensa por zona: ${temporada.monedasBase} 🪙 + corona desbloqueada', style: _rajdhani(11, FontWeight.w500, _kGold))),
          const SizedBox(height: 8),
          Text('Esta acción no se puede deshacer.', style: _rajdhani(11, FontWeight.w500, Colors.redAccent.withValues(alpha: 0.8))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: _rajdhani(12, FontWeight.w600, _kDim))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _mostrarSnackbar('Calculando reyes...');
              try {
                final n = await ZonaService.cerrarTemporada(temporada.id);
                _mostrarSnackbar('✅ $n títulos otorgados. Temporada cerrada.');
                await _cargarTitulos();
              } catch (e) { _mostrarSnackbar('Error: $e', error: true); }
            },
            child: Text('CERRAR TEMPORADA', style: _rajdhani(12, FontWeight.w700, _kGold)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoader() {
    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge([_loopAnim, _scanAnim]),
        builder: (_, __) => Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 48, height: 48, child: CustomPaint(painter: _LoaderPainter(accent: _kAccent, progress: _scan.value, pulse: _pulse.value))),
          const SizedBox(height: 20),
          Text('CARGANDO EXPEDIENTE', style: _rajdhani(10, FontWeight.w700, _kDim, spacing: 4)),
        ]),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FadeTransition(opacity: _fadeZona1, child: _buildZonaIdentidad()),
        if (!isOwnProfile)
          FadeTransition(
            opacity: _fadeZona2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(children: [
                _buildFriendshipButton(),
                const SizedBox(height: 10),
                _buildBotonRetar(),
                const SizedBox(height: 10),
                _socialBtn('Enviar mensaje', Icons.chat_bubble_outline_rounded, _kText, _abrirChat),
              ]),
            ),
          ),
        SlideTransition(
          position: _slideZona2,
          child: FadeTransition(
            opacity: _fadeZona2,
            child: Column(children: [
              const SizedBox(height: 28),
              _buildTabBar(),
              const SizedBox(height: 24),
              _buildTabContent(),
            ]),
          ),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  TAB BAR — con 4 tabs incluyendo DUELOS
  // ═══════════════════════════════════════════════════════════
  Widget _buildTabBar() {
    final tabs = [
      (Icons.bar_chart_rounded,    'STATS',     false),
      (Icons.shield_outlined,      'HISTORIAL', false),
      (Icons.map_outlined,         'ZONA',      false),
      (Icons.sports_mma_rounded,   'DUELOS',    _desafiosActivosCount > 0),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder2),
        ),
        child: Row(
          children: tabs.asMap().entries.map((e) {
            final i      = e.key;
            final icon   = e.value.$1;
            final label  = e.value.$2;
            final badge  = e.value.$3;
            final active = _tabPrincipal == i;

            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tabPrincipal = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: active ? _kSurface2 : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: active ? Border.all(color: _kBorder2) : null,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(icon, size: 12,
                              color: active ? _kAccent : _kDim),
                          const SizedBox(width: 4),
                          Text(label,
                              style: _rajdhani(9,
                                  active ? FontWeight.w700 : FontWeight.w500,
                                  active ? _kWhite : _kDim,
                                  spacing: 1)),
                        ]),
                      ),
                      // Badge de duelos activos
                      if (badge)
                        Positioned(
                          top: -2, right: 2,
                          child: Container(
                            width: 7, height: 7,
                            decoration: const BoxDecoration(
                                color: _kAccent, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabPrincipal) {
      case 0:
        // Cargar stats premium la primera vez que se abre el tab
        if (_isPremium && !_statsPremiumCargadas && !_loadingStatsPremium) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _cargarStatsPremium();
          });
        }
        return _buildTabStats();
      case 1: return _buildTabHistorial();
      case 2: return _buildTabZona();
      case 3: return _buildTabDuelos();
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildTabStats() {
    return FadeTransition(
      opacity: _fadeZona2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Column(children: [
          _buildKmSangre(), const SizedBox(height: 16),
          _buildTriadaStats(), const SizedBox(height: 16),
          _buildRachaGauge(), const SizedBox(height: 16),
          PalmaresPanel(titulos: _todosLosTitulos, titulosActivos: _titulosActivos),
          const SizedBox(height: 20),

          // ── Panel de estadísticas avanzadas (Premium) ────────────────────
          if (_isPremium)
            _buildPanelStatsPremium()
          else
            _buildBannerStatsPremium(),

          const SizedBox(height: 100),
        ]),
      ),
    );
  }

  Widget _buildTabHistorial() {
    return FadeTransition(
      opacity: _fadeZona3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Column(children: [
          _buildGuerraPanel(), const SizedBox(height: 20),
          _buildMisionesRecientes(), const SizedBox(height: 20),
          _buildHistorialCompleto(), const SizedBox(height: 20),
          _buildLogrosPanel(), const SizedBox(height: 100),
        ]),
      ),
    );
  }

  Widget _buildTabZona() {
    // Auto-cargar territorios la primera vez que se abre el tab
    if (_territoriosDelUsuario.isEmpty && !_loadingTerritoriosMapa) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cargarTerritoriosDelUsuario();
      });
    }
    return FadeTransition(
      opacity: _fadeZona3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Column(children: [
          _buildMapaPanel(),
          if (isOwnProfile) ...[const SizedBox(height: 28), _buildColorPanel()],
          const SizedBox(height: 100),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  TAB DUELOS — nuevo
  // ═══════════════════════════════════════════════════════════
  Widget _buildTabDuelos() {
    final uid = viewedUserId;
    if (uid == null) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _fadeZona3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: StreamBuilder<List<DesafioInfo>>(
          stream: DesafiosService.streamActivos(uid),
          builder: (ctx, snapActivos) {
            return StreamBuilder<List<DesafioInfo>>(
              stream: DesafiosService.streamHistorial(uid),
              builder: (ctx, snapHistorial) {
                final activos   = snapActivos.data ?? [];
                final historial = snapHistorial.data ?? [];

                final ganados  = historial.where((d) => d.ganadorId == uid).length;
                final perdidos = historial.length - ganados;
                final winPct   = historial.isEmpty ? 0.0 : ganados / historial.length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Resumen estadístico ──────────────────────────────────
                    if (historial.isNotEmpty) ...[
                      _buildDuelosResumen(ganados, perdidos, winPct),
                      const SizedBox(height: 20),
                    ],

                    // ── Duelos activos ───────────────────────────────────────
                    _panelLabel('DUELOS EN CURSO', Icons.sports_mma_rounded),
                    const SizedBox(height: 12),

                    if (!snapActivos.hasData)
                      _dueloLoader()
                    else if (activos.isEmpty)
                      _dueloEmpty(isOwnProfile
                          ? 'Sin duelos activos\nReta a alguien desde su perfil'
                          : 'Sin duelos activos')
                    else
                      ...activos.map((d) => _buildDueloCard(d, uid)),

                    const SizedBox(height: 28),

                    // ── Historial ────────────────────────────────────────────
                    if (historial.isNotEmpty) ...[
                      _panelLabel('HISTORIAL DE DUELOS', Icons.history_rounded),
                      const SizedBox(height: 12),
                      ...historial.take(5).map((d) => _buildDueloHistorialCard(d, uid)),
                      if (historial.length > 5)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: GestureDetector(
                            onTap: () => Navigator.pushNamed(
                                context, '/desafios',
                                arguments: {'desafioId': null}),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text('Ver todos los duelos', style: _rajdhani(11, FontWeight.w600, _kText)),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right_rounded, color: _kDim, size: 14),
                            ]),
                          ),
                        ),
                    ],

                    const SizedBox(height: 100),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ── Resumen estadístico de duelos ────────────────────────────────────────
  Widget _buildDuelosResumen(int ganados, int perdidos, double winPct) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder2),
      ),
      child: Row(children: [
        Expanded(child: _dueloStat('$ganados', 'VICTORIAS', _kGold)),
        Container(width: 1, height: 44, color: _kBorder2, margin: const EdgeInsets.symmetric(horizontal: 8)),
        Expanded(child: _dueloStat('$perdidos', 'DERROTAS', _kAccent)),
        Container(width: 1, height: 44, color: _kBorder2, margin: const EdgeInsets.symmetric(horizontal: 8)),
        Expanded(child: _dueloStat(
            '${(winPct * 100).toStringAsFixed(0)}%', 'WIN RATE', _kText)),
      ]),
    );
  }

  Widget _dueloStat(String val, String label, Color color) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(val, style: GoogleFonts.rajdhani(
            fontSize: 28, fontWeight: FontWeight.w900,
            color: color, height: 1)),
        Text(label, style: _rajdhani(8, FontWeight.w700, _kSubtext, spacing: 1.5)),
      ]);

  // ── Card de duelo activo en el perfil ────────────────────────────────────
  Widget _buildDueloCard(DesafioInfo info, String uid) {
    final misPuntos   = info.puntosDeUsuario(uid);
    final rivalPuntos = info.puntosDeRival(uid);
    final rivalNick   = info.nickRival(uid);
    final voy         = misPuntos >= rivalPuntos;
    final total       = misPuntos + rivalPuntos;
    final miPct       = total > 0 ? misPuntos / total : 0.5;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/desafios',
          arguments: {'desafioId': info.id}),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: voy
                  ? _kGold.withOpacity(0.25)
                  : _kAccent.withOpacity(0.20)),
          boxShadow: [
            BoxShadow(
                color: (voy ? _kGold : _kAccent).withOpacity(0.06),
                blurRadius: 16),
          ],
        ),
        child: Column(children: [

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(children: [
              Container(width: 2, height: 14,
                  color: voy ? _kGold : _kAccent),
              const SizedBox(width: 10),
              const Text('⚔️', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text('DUELO ACTIVO',
                  style: _rajdhani(9, FontWeight.w900,
                      voy ? _kGold : _kAccent, spacing: 2)),
              const Spacer(),
              // Tiempo restante
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kBorder2.withOpacity(0.5),
                  border: Border.all(color: _kBorder2),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.timer_outlined, color: _kSubtext, size: 10),
                  const SizedBox(width: 4),
                  Text(info.tiempoRestante,
                      style: _rajdhani(10, FontWeight.w700, _kText)),
                ]),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: _kDim, size: 14),
            ]),
          ),

          // Marcador
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(children: [
              // Yo
              Expanded(child: Column(children: [
                Text('TÚ', style: _rajdhani(8, FontWeight.w700, _kSubtext, spacing: 2)),
                const SizedBox(height: 4),
                _AnimatedCounter(
                  value: misPuntos.toDouble(),
                  style: GoogleFonts.rajdhani(
                      fontSize: 40, fontWeight: FontWeight.w900,
                      color: voy ? _kWhite : _kSubtext, height: 1,
                      shadows: voy
                          ? [Shadow(color: _kGold.withOpacity(0.4), blurRadius: 12)]
                          : []),
                  duration: const Duration(milliseconds: 900),
                ),
                Text('PTS', style: _rajdhani(8, FontWeight.w700,
                    voy ? _kGold : _kDim, spacing: 2)),
              ])),

              // VS + apuesta
              Column(children: [
                Text('VS', style: _rajdhani(11, FontWeight.w900, _kMuted, spacing: 3)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kGold.withOpacity(0.06),
                    border: Border.all(color: _kGold.withOpacity(0.25)),
                  ),
                  child: Text('${info.apuesta} 🪙',
                      style: _rajdhani(10, FontWeight.w900, _kGold)),
                ),
              ]),

              // Rival
              Expanded(child: Column(children: [
                Text(rivalNick.toUpperCase(),
                    style: _rajdhani(8, FontWeight.w700, _kSubtext, spacing: 1),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                _AnimatedCounter(
                  value: rivalPuntos.toDouble(),
                  style: GoogleFonts.rajdhani(
                      fontSize: 40, fontWeight: FontWeight.w900,
                      color: !voy ? _kWhite : _kSubtext, height: 1,
                      shadows: !voy
                          ? [Shadow(color: _kAccent.withOpacity(0.4), blurRadius: 12)]
                          : []),
                  duration: const Duration(milliseconds: 900),
                ),
                Text('PTS', style: _rajdhani(8, FontWeight.w700,
                    !voy ? _kAccent : _kDim, spacing: 2)),
              ])),
            ]),
          ),

          // Barra progreso
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 5,
                  child: Row(children: [
                    Flexible(
                      flex: (miPct * 100).round().clamp(1, 99),
                      child: Container(
                          color: voy ? _kGold : _kAccent),
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      flex: ((1 - miPct) * 100).round().clamp(1, 99),
                      child: Container(color: _kMuted),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (voy ? _kGold : _kAccent).withOpacity(0.08),
                    border: Border.all(
                        color: (voy ? _kGold : _kAccent).withOpacity(0.3)),
                  ),
                  child: Text(voy ? '⬆ Ganando' : '⬇ Perdiendo',
                      style: _rajdhani(9, FontWeight.w800,
                          voy ? _kGold : _kAccent)),
                ),
                const Spacer(),
                Text('Premio: ${info.apuesta * 2} 🪙',
                    style: _rajdhani(9, FontWeight.w600, _kSubtext)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Card historial de duelos en el perfil ────────────────────────────────
  Widget _buildDueloHistorialCard(DesafioInfo info, String uid) {
    final gane       = info.ganadorId == uid;
    final rival      = info.nickRival(uid);
    final misPuntos  = info.puntosDeUsuario(uid);
    final rivalPts   = info.puntosDeRival(uid);
    final color      = gane ? _kGold : _kAccent;
    final premio     = gane ? '+${info.apuesta * 2}' : '-${info.apuesta}';

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/desafios',
          arguments: {'desafioId': info.id}),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: color.withOpacity(0.6), width: 2),
            top: BorderSide(color: _kBorder2),
            right: BorderSide(color: _kBorder2),
            bottom: BorderSide(color: _kBorder2),
          ),
        ),
        child: Row(children: [
          Text(gane ? '🏆' : '💀', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              gane
                  ? 'Victoria vs ${rival.toUpperCase()}'
                  : 'Derrota vs ${rival.toUpperCase()}',
              style: _rajdhani(13, FontWeight.w800, _kWhite),
            ),
            const SizedBox(height: 3),
            Text('$misPuntos pts vs $rivalPts pts',
                style: _rajdhani(10, FontWeight.w500, _kSubtext)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.07),
              border: Border.all(color: color.withOpacity(0.28)),
            ),
            child: Text('$premio 🪙',
                style: _rajdhani(12, FontWeight.w900, color)),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: _kDim, size: 14),
        ]),
      ),
    );
  }

  // ── Helpers del tab Duelos ───────────────────────────────────────────────
  Widget _panelLabel(String label, IconData icon) => Row(children: [
    Container(width: 2, height: 13, decoration: BoxDecoration(
        color: _kBorder2, borderRadius: BorderRadius.circular(1))),
    const SizedBox(width: 9),
    Icon(icon, color: _kDim, size: 11),
    const SizedBox(width: 6),
    Text(label, style: _rajdhani(10, FontWeight.w700, _kDim, spacing: 2.5)),
  ]);

  Widget _dueloLoader() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: Center(child: SizedBox(width: 16, height: 16,
        child: CircularProgressIndicator(color: _kAccent, strokeWidth: 1.5))),
  );

  Widget _dueloEmpty(String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.sports_mma_rounded, color: _kMuted, size: 36),
      const SizedBox(height: 12),
      Text(msg, textAlign: TextAlign.center,
          style: _rajdhani(12, FontWeight.w500, _kSubtext, height: 1.5)),
    ])),
  );

  // ═══════════════════════════════════════════════════════════
  //  resto de widgets (sin cambios)
  // ═══════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════
  //  PANEL ESTADÍSTICAS AVANZADAS — PREMIUM
  // ═══════════════════════════════════════════════════════════

  Widget _buildPanelStatsPremium() {
    if (_loadingStatsPremium) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kGold.withOpacity(0.2)),
        ),
        child: Column(children: [
          const SizedBox(height: 8),
          SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(
                  color: _kGold, strokeWidth: 1.5)),
          const SizedBox(height: 12),
          Text('Cargando análisis avanzado...',
              style: _rajdhani(11, FontWeight.w600, _kSubtext)),
          const SizedBox(height: 8),
        ]),
      );
    }

    return Column(children: [
      // ── Header premium ─────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(
            top: BorderSide(color: _kGold.withOpacity(0.3)),
            left: BorderSide(color: _kGold.withOpacity(0.3)),
            right: BorderSide(color: _kGold.withOpacity(0.3)),
            bottom: BorderSide(color: _kBorder2),
          ),
        ),
        child: Row(children: [
          Container(width: 2, height: 13,
              color: _kGold, margin: const EdgeInsets.only(right: 8)),
          Text('👑', style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 6),
          Text('ANÁLISIS AVANZADO',
              style: _rajdhani(10, FontWeight.w900, _kGold, spacing: 2)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _kGold.withOpacity(0.08),
              border: Border.all(color: _kGold.withOpacity(0.25)),
            ),
            child: Text('PREMIUM',
                style: _rajdhani(7, FontWeight.w900, _kGold, spacing: 1)),
          ),
        ]),
      ),

      // ── Comparativa semanal ────────────────────────────────────────────────
      if (_comparativaSemanal != null)
        _buildComparativaSemanalWidget(_comparativaSemanal!),

      // ── Tendencia 8 semanas ────────────────────────────────────────────────
      _buildTendencia8SemanasWidget(),

      // ── Territorios conquistados con nombre ────────────────────────────────
      _buildTerritoriosConNombre(),
    ]);
  }

  Widget _buildComparativaSemanalWidget(ComparativaSemanal comp) {
    final mejora = comp.mejorKm;
    final color  = mejora ? _kGold : _kAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border(
          left: BorderSide(color: _kBorder2),
          right: BorderSide(color: _kBorder2),
          bottom: BorderSide(color: _kBorder2),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ESTA SEMANA VS ANTERIOR',
            style: _rajdhani(9, FontWeight.w700, _kSubtext, spacing: 2)),
        const SizedBox(height: 14),
        Row(children: [
          // Km esta semana
          Expanded(child: Column(children: [
            _AnimatedCounter(
              value: comp.kmEstaSemana,
              decimals: 1,
              style: GoogleFonts.rajdhani(
                  fontSize: 32, fontWeight: FontWeight.w900,
                  color: _kWhite, height: 1),
              duration: const Duration(milliseconds: 1000),
            ),
            Text('KM ESTA SEM.',
                style: _rajdhani(8, FontWeight.w700, _kSubtext, spacing: 1.5)),
          ])),

          // Delta
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(mejora ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                  color: color, size: 18),
              const SizedBox(height: 2),
              Text(comp.deltaKmStr,
                  style: _rajdhani(11, FontWeight.w900, color)),
            ]),
          ),

          // Km semana anterior
          Expanded(child: Column(children: [
            Text(comp.kmSemanaAnterior.toStringAsFixed(1),
                style: GoogleFonts.rajdhani(
                    fontSize: 32, fontWeight: FontWeight.w900,
                    color: _kSubtext, height: 1),
                textAlign: TextAlign.right),
            Text('SEM. ANTERIOR',
                style: _rajdhani(8, FontWeight.w700, _kSubtext, spacing: 1.5),
                textAlign: TextAlign.right),
          ])),
        ]),
        const SizedBox(height: 12),
        // Próximo hito
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _kBg,
            border: Border.all(color: _kBorder2),
          ),
          child: Row(children: [
            const Text('🎯', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            Expanded(child: Text(comp.proximoHito,
                style: _rajdhani(11, FontWeight.w600, _kText))),
          ]),
        ),
      ]),
    );
  }

  Widget _buildTendencia8SemanasWidget() {
    final tieneDatos = _tendencia8Semanas.any((p) => p.distanciaTotal > 0);
    const goldColor  = Color(0xFFD4A017);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border(
          left: BorderSide(color: _kBorder2),
          right: BorderSide(color: _kBorder2),
          bottom: BorderSide(color: _kBorder2),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TENDENCIA 8 SEMANAS',
            style: _rajdhani(9, FontWeight.w700, _kSubtext, spacing: 2)),
        const SizedBox(height: 14),
        if (!tieneDatos)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(child: Text(
                'Necesitas más carreras para ver la tendencia',
                style: _rajdhani(11, FontWeight.w500, _kSubtext))),
          )
        else
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _tendencia8Semanas.asMap().entries.map((e) {
                final idx  = e.key;
                final pt   = e.value;
                final maxDist = _tendencia8Semanas
                    .map((p) => p.distanciaTotal)
                    .reduce((a, b) => a > b ? a : b);
                final pct = maxDist > 0 ? pt.distanciaTotal / maxDist : 0.0;
                final esReciente = idx >= _tendencia8Semanas.length - 2;

                return Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (pt.distanciaTotal > 0)
                        Text('${pt.distanciaTotal.toStringAsFixed(0)}',
                            style: _rajdhani(7, FontWeight.w700,
                                esReciente ? goldColor : _kSubtext)),
                      const SizedBox(height: 2),
                      AnimatedContainer(
                        duration: Duration(milliseconds: 400 + idx * 60),
                        curve: Curves.easeOutCubic,
                        height: (pct * 72).clamp(4, 72),
                        decoration: BoxDecoration(
                          color: pt.distanciaTotal > 0
                              ? (esReciente
                                  ? goldColor
                                  : goldColor.withOpacity(0.35))
                              : _kBorder2,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(_semanaCorta(pt.semana),
                          style: _rajdhani(6, FontWeight.w600, _kSubtext)),
                    ],
                  ),
                ));
              }).toList(),
            ),
          ),
      ]),
    );
  }

  Widget _buildTerritoriosConNombre() {
    final tieneDatos = _territoriosDelUsuario.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border(
          left: BorderSide(color: _kBorder2),
          right: BorderSide(color: _kBorder2),
          bottom: BorderSide(color: _kBorder2),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('ZONAS CONQUISTADAS',
              style: _rajdhani(9, FontWeight.w700, _kSubtext, spacing: 2)),
          const Spacer(),
          Text('${_territoriosDelUsuario.length} zonas',
              style: _rajdhani(9, FontWeight.w600, _kDim)),
        ]),
        const SizedBox(height: 12),
        if (!tieneDatos)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Sin territorios conquistados aún',
                style: _rajdhani(11, FontWeight.w500, _kSubtext)),
          )
        else if (_nombresZonas.isEmpty && !_loadingStatsPremium)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Cargando nombres de zonas...',
                style: _rajdhani(11, FontWeight.w500, _kSubtext)),
          )
        else
          Column(children: _territoriosDelUsuario
              .take(20)
              .toList()
              .asMap()
              .entries
              .map((e) {
            final idx    = e.key;
            final nombre = _nombresZonas[idx] ?? 'Zona ${idx + 1}';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _kBg,
                border: Border(
                  left: BorderSide(
                      color: _colorTerritorio.withOpacity(0.6), width: 2),
                  top: BorderSide(color: _kBorder2),
                  right: BorderSide(color: _kBorder2),
                  bottom: BorderSide(color: _kBorder2),
                ),
              ),
              child: Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: _colorTerritorio,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(nombre,
                    style: _rajdhani(12, FontWeight.w700, _kText),
                    overflow: TextOverflow.ellipsis)),
                Text('${idx + 1}',
                    style: _rajdhani(9, FontWeight.w600, _kSubtext)),
              ]),
            );
          }).toList()),
        if (_territoriosDelUsuario.length > 20) ...[
          const SizedBox(height: 4),
          Center(child: Text(
              '+${_territoriosDelUsuario.length - 20} zonas más',
              style: _rajdhani(10, FontWeight.w600, _kSubtext))),
        ],
      ]),
    );
  }

  /// Banner para usuarios free invitando a premium
  Widget _buildBannerStatsPremium() {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/paywall'),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kGold.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
                color: _kGold.withOpacity(0.06), blurRadius: 16),
          ],
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _kGold.withOpacity(0.08),
              border: Border.all(color: _kGold.withOpacity(0.25)),
            ),
            child: const Center(
                child: Text('👑', style: TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Análisis avanzado',
                style: _rajdhani(14, FontWeight.w800, _kWhite)),
            const SizedBox(height: 3),
            Text(
              'Tendencia 8 semanas, comparativa semanal y zonas conquistadas con nombre',
              style: _rajdhani(11, FontWeight.w500, _kSubtext, height: 1.4),
            ),
          ])),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: _kGold,
            child: Text('VER',
                style: _rajdhani(10, FontWeight.w900,
                    const Color(0xFF030303), spacing: 1)),
          ),
        ]),
      ),
    );
  }

  String _semanaCorta(DateTime d) {
    const meses = ['E','F','M','A','M','J','J','A','S','O','N','D'];
    return '${d.day}${meses[d.month - 1]}';
  }

  Widget _buildHistorialCompleto() {
    final total     = _historialFiltrado.length;
    final mostrados = _verTodoHistorial || _historialSearchCtrl.text.isNotEmpty
        ? _historialFiltrado
        : _historialFiltrado.take(_historialPagina * _historialPaginaActual).toList();
    return _Panel(
      accent: _kAccent, label: 'TODAS LAS MISIONES', icon: Icons.history_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('$total misión${total == 1 ? '' : 'es'} registrada${total == 1 ? '' : 's'}', style: _rajdhani(11, FontWeight.w500, _kSubtext))),
          if (_historialCompleto.length > 5)
            GestureDetector(
              onTap: () => setState(() {
                _verTodoHistorial = !_verTodoHistorial;
                if (!_verTodoHistorial) { _historialSearchCtrl.clear(); _historialFiltrado = _historialCompleto; _historialPaginaActual = 1; }
              }),
              child: Text(_verTodoHistorial ? 'MENOS' : 'TODO', style: _rajdhani(9, FontWeight.w900, _kText, spacing: 2)),
            ),
        ]),
        if (_verTodoHistorial) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _historialSearchCtrl, onChanged: _filtrarHistorial,
            style: _rajdhani(13, FontWeight.w500, _kWhite),
            decoration: InputDecoration(hintText: 'Buscar misión...', hintStyle: _rajdhani(13, FontWeight.w400, _kDim), prefixIcon: const Icon(Icons.search_rounded, color: _kDim, size: 16), filled: true, fillColor: _kBg, contentPadding: EdgeInsets.zero, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder2)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder2)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kText, width: 1.5))),
          ),
        ],
        const SizedBox(height: 12),
        if (_cargandoHistorial)
          Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: _kAccent, strokeWidth: 1.5))))
        else if (mostrados.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Sin misiones registradas', style: _rajdhani(12, FontWeight.w500, _kDim)))
        else
          Column(children: [
            ...mostrados.asMap().entries.map((e) {
              final idx  = e.key; final d = e.value;
              final dist = (d['distancia'] as double? ?? 0);
              final seg  = (d['tiempo_segundos'] as int? ?? 0);
              final vel  = (d['velocidad_media'] as double? ?? 0);
              final fecha = _formatFechaCorta(d['timestamp']);
              final isFirst = idx == 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: isFirst ? _kAccent : _kBorder2, width: isFirst ? 2 : 1))),
                child: IntrinsicHeight(
                  child: Row(children: [
                    Container(width: 36, alignment: Alignment.center, child: Text('${idx + 1}'.padLeft(2, '0'), style: _rajdhani(10, FontWeight.w700, isFirst ? _kText : _kDim))),
                    Container(width: 1, color: _kBorder2),
                    Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d['titulo'] ?? 'Carrera completada', style: _rajdhani(13, FontWeight.w700, isFirst ? _kWhite : _kText), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Row(children: [
                            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: _kBorder2.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4), border: Border.all(color: _kBorder2)), child: Text('${dist.toStringAsFixed(2)} km', style: _rajdhani(10, FontWeight.w800, _kWhite))),
                            if (seg > 0) ...[const SizedBox(width: 6), Text(_formatTiempo(Duration(seconds: seg)), style: _rajdhani(9, FontWeight.w500, _kDim))],
                            if (vel > 0) ...[const SizedBox(width: 6), Text('${vel.toStringAsFixed(1)} km/h', style: _rajdhani(9, FontWeight.w500, _kDim))],
                          ]),
                        ])),
                        Text(fecha, style: _rajdhani(9, FontWeight.w600, _kSubtext)),
                      ]),
                    )),
                  ]),
                ),
              );
            }),
            if (!_verTodoHistorial && _historialFiltrado.length > _historialPagina * _historialPaginaActual)
              GestureDetector(
                onTap: () => setState(() => _historialPaginaActual++),
                child: Padding(padding: const EdgeInsets.only(top: 4), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Ver más misiones', style: _rajdhani(11, FontWeight.w600, _kText)),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: _kDim, size: 14),
                ])),
              ),
          ]),
      ]),
    );
  }

  Widget _buildZonaIdentidad() {
    final h = MediaQuery.of(context).size.height;
    return SizedBox(
      height: h * 0.52,
      child: Stack(fit: StackFit.expand, children: [
        ClipRect(
          child: FlutterMap(
            mapController: _liveMapCtrl,
            options: MapOptions(initialCenter: _liveCenter, initialZoom: 14.5, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
            children: [
              TileLayer(urlTemplate: _kMapboxTileUrl, tileProvider: NetworkTileProvider(), userAgentPackageName: 'com.runnerrisk.app'),
              PolygonLayer(polygons: _allTerritories.map((t) {
                final pts = t['puntos'] as List<LatLng>; final color = t['color'] as Color; final isMe = (t['userId'] as String) == viewedUserId;
                return Polygon(points: pts, color: color.withValues(alpha: isMe ? 0.28 : 0.12), borderColor: color.withValues(alpha: isMe ? 0.75 : 0.30), borderStrokeWidth: isMe ? 1.6 : 0.7);
              }).toList()),
              PolylineLayer(polylines: _liveRunners.map((r) {
                final trail = r['trail'] as List<LatLng>; final color = r['color'] as Color; final isMe = r['isMe'] as bool;
                return Polyline(points: [r['pos'] as LatLng, ...trail], color: color.withValues(alpha: isMe ? 0.9 : 0.55), strokeWidth: isMe ? 3.0 : 1.8, gradientColors: [color.withValues(alpha: isMe ? 0.9 : 0.55), color.withValues(alpha: 0.0)]);
              }).toList()),
              MarkerLayer(markers: _liveRunners.map((r) {
                final pos = r['pos'] as LatLng; final color = r['color'] as Color; final isMe = r['isMe'] as bool;
                return Marker(point: pos, width: isMe ? 14 : 9, height: isMe ? 14 : 9, child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color.withValues(alpha: isMe ? 0.6 : 0.4), blurRadius: isMe ? 8 : 4, spreadRadius: isMe ? 2 : 1)])));
              }).toList()),
            ],
          ),
        ),
        Container(decoration: BoxDecoration(gradient: RadialGradient(center: Alignment.center, radius: 1.2, colors: [Colors.black.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.60)]))),
        AnimatedBuilder(animation: Listenable.merge([_loopAnim, _scanAnim]), builder: (_, __) => CustomPaint(painter: _DossierBgPainter(accent: _kAccent, pulse: _pulse.value, scan: _scan.value))),
        Align(alignment: Alignment.bottomCenter, child: Container(height: h * 0.22, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, _kBg])))),
        Positioned(top: 58, left: 20, child: _buildOperativeId()),
        Positioned(top: 58, right: 20, child: _buildLigaBadge()),
        Positioned(bottom: 0, left: 0, right: 0,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _buildAvatar(),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: isOwnProfile ? _mostrarDialogoEditarNickname : null,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(nickname.toUpperCase(), style: GoogleFonts.rajdhani(fontSize: 36, fontWeight: FontWeight.w700, color: _kWhite, letterSpacing: 4, height: 1)),
                if (isOwnProfile) ...[const SizedBox(width: 10), const Icon(Icons.edit_outlined, color: _kDim, size: 13)],
              ]),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _tagPill(_nivelTitulo(nivel), _kText, filled: true),
              const SizedBox(width: 8),
              _tagPill('NIV. $nivel', _kText),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: isOwnProfile
                    ? () => CoinShopScreen.mostrar(context)
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('🪙', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    Text('$monedas', style: TextStyle(
                      color: Colors.amber.withValues(alpha: 0.85),
                      fontSize: 12, fontWeight: FontWeight.w800,
                    )),
                    if (isOwnProfile) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.add_circle_outline_rounded,
                          color: Colors.amber.withValues(alpha: 0.6), size: 12),
                    ],
                  ]),
                ),
              ),
              // ── Badge Premium ──────────────────────────────────────────────
              if (_isPremium) ...[
                const SizedBox(width: 8),
                _buildPremiumBadge(),
              ],
            ]),
            const SizedBox(height: 8),
            if (_titulosActivos.isNotEmpty) ...[
              ReyBannerActivo(titulosActivos: _titulosActivos),
              const SizedBox(height: 8),
            ],
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('players').doc(viewedUserId).snapshots(),
              builder: (ctx, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final data      = snap.data!.data() as Map<String, dynamic>?;
                final clanNombre = data?['clanNombre'] as String?;
                final clanTag    = data?['clanTag'] as String?;
                final clanRol    = data?['clanRol'] as String?;
                if (clanNombre == null) {
                  return GestureDetector(
                    onTap: isOwnProfile ? () => Navigator.pushNamed(context, '/clan') : null,
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.transparent, border: Border.all(color: _kMuted), borderRadius: BorderRadius.circular(4)), child: Text('SIN CLAN', style: _rajdhani(9, FontWeight.w700, _kDim, spacing: 1.5))));
                }
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _kAccent.withValues(alpha: 0.08), border: Border.all(color: _kAccent.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(4)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('[$clanTag]', style: _rajdhani(9, FontWeight.w900, _kAccent, spacing: 1)),
                    const SizedBox(width: 6),
                    Text(clanNombre.toUpperCase(), style: _rajdhani(9, FontWeight.w700, _kText, spacing: 1)),
                    if (clanRol == 'lider') ...[const SizedBox(width: 5), const Text('👑', style: TextStyle(fontSize: 9))],
                  ]));
              },
            ),
            if (isOwnProfile && email.isNotEmpty) ...[const SizedBox(height: 8), Text(email, style: _rajdhani(10, FontWeight.w400, _kSubtext))],
            const SizedBox(height: 28),
          ]),
        ),
      ]),
    );
  }

  Widget _buildOperativeId() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: _kBg.withValues(alpha: 0.80), borderRadius: BorderRadius.circular(4), border: Border.all(color: _kBorder2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('OPERATIVE ID', style: _rajdhani(7, FontWeight.w700, _kDim, spacing: 2)),
        Text(_operativeId, style: _rajdhani(16, FontWeight.w700, _kText, spacing: 2)),
        Row(children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: _rachaActual > 0 ? const Color(0xFF39FF14) : _kMuted, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(_rachaActual > 0 ? 'ACTIVO' : 'INACTIVO', style: _rajdhani(8, FontWeight.w700, _rachaActual > 0 ? const Color(0xFF39FF14).withValues(alpha: 0.8) : _kMuted, spacing: 1.5)),
        ]),
      ]),
    );
  }

  Widget _buildLigaBadge() {
    final liga = _ligaInfo;
    if (liga == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: _kBg.withValues(alpha: 0.80), borderRadius: BorderRadius.circular(4), border: Border.all(color: _kBorder2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text('LIGA', style: _rajdhani(7, FontWeight.w700, _kDim, spacing: 2)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(liga.emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(liga.name.toUpperCase(), style: _rajdhani(14, FontWeight.w700, liga.color, spacing: 1)),
        ]),
        if (_rangoEnLiga > 0) Text('#$_rangoEnLiga EN LIGA', style: _rajdhani(8, FontWeight.w700, liga.color.withValues(alpha: 0.7), spacing: 1)),
      ]),
    );
  }

  Widget _buildAvatar() {
    return AnimatedBuilder(
      animation: _loopAnim,
      builder: (_, __) => Stack(alignment: Alignment.center, children: [
        Container(width: 96, height: 96, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _kBorder2, width: 1))),
        GestureDetector(
          onTap: isOwnProfile ? _seleccionarFoto : null,
          child: Container(
            width: 80, height: 80,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _kSurface2, border: Border.all(color: _kAccent, width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.0), blurRadius: 0), BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 0, spreadRadius: 2)]),
            child: isUploadingPhoto
                ? Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: _kAccent, strokeWidth: 1.5)))
                : ClipOval(child: fotoBase64 != null ? Image.memory(base64Decode(fotoBase64!), fit: BoxFit.cover, width: 80, height: 80) : AvatarWidget(config: _avatarConfig, size: 80, fallbackLabel: nickname)),
          ),
        ),
        Positioned(
          bottom: 4, right: 4,
          child: GestureDetector(
            onTap: _abrirCustomizador,
            child: Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: _titulosActivos.isNotEmpty ? _kGold : _kAccent,
                shape: BoxShape.circle,
                border: Border.all(color: _kBg, width: 2),
              ),
              child: Center(
                child: Text(
                  _titulosActivos.isNotEmpty ? '👑' : '',
                  style: const TextStyle(fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
        if (_titulosActivos.isEmpty && isOwnProfile)
          Positioned(bottom: 4, right: 4, child: GestureDetector(onTap: _abrirCustomizador, child: Container(width: 24, height: 24, decoration: BoxDecoration(color: _kAccent, shape: BoxShape.circle, border: Border.all(color: _kBg, width: 2)), child: const Icon(Icons.palette_rounded, color: Colors.black, size: 11)))),
      ]),
    );
  }

  // ── Badge Premium dorado animado ─────────────────────────────────────────
  Widget _buildPremiumBadge() {
    return AnimatedBuilder(
      animation: _loopAnim,
      builder: (_, __) {
        final glow = _pulse.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFD4A017).withOpacity(0.15),
                const Color(0xFFFFD700).withOpacity(0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: Color.lerp(
                const Color(0xFFD4A017),
                const Color(0xFFFFD700),
                glow,
              )!.withOpacity(0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD4A017).withOpacity(glow * 0.25),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('👑', style: TextStyle(fontSize: 9)),
            const SizedBox(width: 4),
            Text('PREMIUM',
                style: _rajdhani(9, FontWeight.w900,
                    const Color(0xFFD4A017), spacing: 1.0)),
          ]),
        );
      },
    );
  }

  Widget _tagPill(String text, Color color, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: filled ? color : color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(3), border: filled ? null : Border.all(color: color.withValues(alpha: 0.20))),
      child: Text(text, style: _rajdhani(10, FontWeight.w700, filled ? Colors.black : color, spacing: 0.5)),
    );
  }

  Widget _buildKmSangre() {
    final progreso = (_kmTotales % 100) / 100;
    final hito     = ((_kmTotales ~/ 100) + 1) * 100;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: _kAccent, width: 1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('DISTANCIA TOTAL', style: _rajdhani(9, FontWeight.w700, _kDim, spacing: 2.5)),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: _AnimatedCounter(
            value: _kmTotales,
            decimals: 1,
            duration: const Duration(milliseconds: 1400),
            style: GoogleFonts.rajdhani(fontSize: 72, fontWeight: FontWeight.w700, color: _kWhite, height: 0.9),
          )),
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _velocidadMediaHistorica > 0
                ? _AnimatedCounter(
                    value: _velocidadMediaHistorica,
                    decimals: 1,
                    style: _rajdhani(16, FontWeight.w700, _kWhite, height: 1),
                    duration: const Duration(milliseconds: 900),
                  )
                : Text('--', style: _rajdhani(16, FontWeight.w700, _kWhite, height: 1)),
              Text('KM/H', style: _rajdhani(8, FontWeight.w600, _kDim, spacing: 1.5)),
            ]),
            const SizedBox(height: 8),
            _miniKpi(_formatTiempo(_tiempoTotalActividad), 'TIEMPO'),
            const SizedBox(height: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _AnimatedCounter(
                value: _totalCarreras.toDouble(),
                style: _rajdhani(16, FontWeight.w700, _kWhite, height: 1),
                duration: const Duration(milliseconds: 1000),
              ),
              Text('MISIONES', style: _rajdhani(8, FontWeight.w600, _kDim, spacing: 1.5)),
            ]),
          ]),
        ]),
        const SizedBox(height: 2),
        Text('KM', style: _rajdhani(13, FontWeight.w700, _kMuted, spacing: 4)),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('HITO $hito KM', style: _rajdhani(9, FontWeight.w600, _kDim, spacing: 1.5)),
          Text('${(progreso * 100).toStringAsFixed(0)}%', style: _rajdhani(9, FontWeight.w700, _kSubtext)),
        ]),
        const SizedBox(height: 5),
        _glowBar(progreso),
      ]),
    );
  }

  Widget _miniKpi(String val, String label) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(val, style: _rajdhani(16, FontWeight.w700, _kWhite, height: 1)),
      Text(label, style: _rajdhani(8, FontWeight.w600, _kDim, spacing: 1.5)),
    ]);
  }

  Widget _buildTriadaStats() {
    final ligaColor = _ligaInfo?.color ?? _kAccent;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 5, child: _buildStatGrande('$territorios', 'ZONAS\nACTIVAS', Icons.crop_square_rounded, _colorTerritorio)),
      const SizedBox(width: 8),
      Expanded(flex: 4, child: Column(children: [
        _buildStatPequena('$_territoriosConquistados', 'CONQUISTAS', Icons.military_tech_rounded, Colors.amber),
        const SizedBox(height: 8),
        _buildStatPequena(_rangoEnLiga > 0 ? '#$_rangoEnLiga' : '—', 'RANKING LIGA', Icons.leaderboard_rounded, ligaColor),
      ])),
    ]);
  }

  Widget _buildStatGrande(String val, String label, IconData icon, Color accentColor) {
    final numVal = double.tryParse(val.replaceAll('#', '').replaceAll(RegExp(r'[^0-9.]'), ''));
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: accentColor.withValues(alpha: 0.12))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: accentColor.withValues(alpha: 0.40), size: 14),
        const SizedBox(height: 12),
        numVal != null && !val.startsWith('#')
          ? _AnimatedCounter(
              value: numVal,
              style: GoogleFonts.rajdhani(fontSize: 52, fontWeight: FontWeight.w700, color: _kWhite, height: 1),
              duration: const Duration(milliseconds: 1100),
            )
          : Text(val, style: GoogleFonts.rajdhani(fontSize: 52, fontWeight: FontWeight.w700, color: _kWhite, height: 1)),
        const SizedBox(height: 4),
        Text(label, style: _rajdhani(9, FontWeight.w600, accentColor.withValues(alpha: 0.60), spacing: 1.5, height: 1.4)),
      ]),
    );
  }

  Widget _buildStatPequena(String val, String label, IconData icon, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _kBorder)),
      child: Row(children: [
        Icon(icon, color: accentColor.withValues(alpha: 0.50), size: 13),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(val, style: _rajdhani(22, FontWeight.w700, _kWhite, height: 1)),
          Text(label, style: _rajdhani(8, FontWeight.w600, _kDim, spacing: 1, height: 1.3)),
        ])),
      ]),
    );
  }

  Widget _buildRachaGauge() {
    final bool activa = _rachaActual > 0;
    final hitos       = [3, 7, 14, 30];
    final int hito    = _rachaActual == 0 ? 3 : hitos.firstWhere((h) => _rachaActual < h, orElse: () => 30);
    final double prog = (_rachaActual / hito).clamp(0.0, 1.0);
    String msg;
    if (!activa)                msg = 'Sin actividad reciente';
    else if (_rachaActual == 1) msg = 'Buen comienzo. No pares.';
    else if (_rachaActual < 7)  msg = '${7 - _rachaActual} días para una semana';
    else if (_rachaActual < 30) msg = 'Más de una semana consecutiva';
    else                        msg = 'Un mes sin parar. Leyenda.';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _kBorder)),
      child: Row(children: [
        SizedBox(width: 76, height: 76, child: AnimatedBuilder(animation: _loopAnim, builder: (_, __) => CustomPaint(painter: _RachaGaugePainter(progress: prog, accent: activa ? _kAccent : _kMuted, pulse: _pulse.value, activa: activa), child: Center(child: Text(activa ? '🔥' : '💤', style: const TextStyle(fontSize: 26)))))),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('RACHA OPERATIVA', style: _rajdhani(9, FontWeight.w700, activa ? _kText : _kDim, spacing: 2)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _AnimatedCounter(
              value: _rachaActual.toDouble(),
              style: GoogleFonts.rajdhani(fontSize: 40, fontWeight: FontWeight.w700, color: _kWhite, height: 1),
              duration: const Duration(milliseconds: 1000),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(_rachaActual == 1 ? 'DÍA' : 'DÍAS',
                  style: _rajdhani(14, FontWeight.w600, _kDim, spacing: 1)),
            ),
          ]),
          const SizedBox(height: 3),
          Text(msg, style: _rajdhani(11, FontWeight.w500, _kSubtext)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('META', style: _rajdhani(8, FontWeight.w700, _kDim, spacing: 2)),
          Text('$hito', style: _rajdhani(28, FontWeight.w700, _kText, height: 1)),
          Text('días', style: _rajdhani(9, FontWeight.w500, _kDim)),
        ]),
      ]),
    );
  }

  Widget _buildGuerraPanel() {
    final total  = _ganados.length + _perdidos.length;
    final winPct = total > 0 ? _ganados.length / total : 0.0;
    final List<NotifItem> lista = _tabGuerraIndex == 0 ? _perdidos : _ganados;
    final Color colTab = _tabGuerraIndex == 0 ? Colors.redAccent : _kAccent;
    String rivalTop = '--';
    if (lista.isNotEmpty) {
      final Map<String, int> freq = {};
      for (final item in lista) { final n = item.fromNickname ?? '?'; freq[n] = (freq[n] ?? 0) + 1; }
      rivalTop = freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }
    return Container(
      decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _kBorder)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
          child: Row(children: [
            Expanded(child: GestureDetector(onTap: () => setState(() => _tabGuerraIndex = 1), child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: Colors.transparent, borderRadius: const BorderRadius.only(topLeft: Radius.circular(12)), border: Border(bottom: BorderSide(color: _tabGuerraIndex == 1 ? _kAccent : _kBorder, width: 2))), child: Column(children: [Text('${_ganados.length}', style: GoogleFonts.rajdhani(fontSize: 44, fontWeight: FontWeight.w700, height: 1, color: _tabGuerraIndex == 1 ? _kWhite : _kMuted)), Text('VICTORIAS', style: _rajdhani(9, FontWeight.w700, _tabGuerraIndex == 1 ? _kText : _kDim, spacing: 2))])))),
            Container(width: 1, height: 80, color: _kBorder2),
            Expanded(child: GestureDetector(onTap: () => setState(() => _tabGuerraIndex = 0), child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: Colors.transparent, borderRadius: const BorderRadius.only(topRight: Radius.circular(12)), border: Border(bottom: BorderSide(color: _tabGuerraIndex == 0 ? Colors.redAccent : _kBorder2, width: 2))), child: Column(children: [Text('${_perdidos.length}', style: GoogleFonts.rajdhani(fontSize: 44, fontWeight: FontWeight.w700, height: 1, color: _tabGuerraIndex == 0 ? _kWhite : _kMuted)), Text('DERROTAS', style: _rajdhani(9, FontWeight.w700, _tabGuerraIndex == 0 ? Colors.redAccent.withValues(alpha: 0.8) : _kDim, spacing: 2))])))),
          ]),
        ),
        Stack(children: [Container(height: 2, color: _kBorder2), FractionallySizedBox(widthFactor: winPct, child: Container(height: 2, color: _kAccent))]),
        if (total > 0)
          Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 0), child: Row(children: [
            _guerraKpi('${(winPct * 100).toStringAsFixed(0)}%', 'WIN RATE', _kText), _guerraDivider(),
            _guerraKpi('$total', 'TOTAL', _kText), _guerraDivider(),
            _guerraKpi(rivalTop, _tabGuerraIndex == 0 ? 'RIVAL TOP' : 'VÍCTIMA TOP', _kText),
          ])),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: _loadingHistorial
              ? Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: _kAccent, strokeWidth: 1.5)))
              : lista.isEmpty
                  ? Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_tabGuerraIndex == 0 ? 'Sin territorios perdidos' : 'Sin conquistas', style: _rajdhani(12, FontWeight.w500, _kDim), textAlign: TextAlign.center))
                  : Column(children: [
                      ...lista.take(3).map((item) => _guerraRow(item, colTab)),
                      if (lista.length > 3 && isOwnProfile)
                        GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistorialGuerraScreen())), child: Padding(padding: const EdgeInsets.only(top: 4), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text('Ver ${lista.length - 3} más', style: _rajdhani(11, FontWeight.w600, _kText)), const SizedBox(width: 4), Icon(Icons.chevron_right_rounded, color: _kDim, size: 12)]))),
                    ]),
        ),
      ]),
    );
  }

  Widget _guerraKpi(String val, String label, Color color) {
    return Expanded(child: Column(children: [Text(val, style: _rajdhani(14, FontWeight.w700, color, height: 1), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis), const SizedBox(height: 2), Text(label, style: _rajdhani(8, FontWeight.w600, _kDim, spacing: 1.5), textAlign: TextAlign.center)]));
  }
  Widget _guerraDivider() => Container(width: 1, height: 28, color: _kBorder2, margin: const EdgeInsets.symmetric(horizontal: 8));
  Widget _guerraRow(NotifItem item, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: _kSurface2, borderRadius: BorderRadius.circular(6), border: Border(left: BorderSide(color: color.withValues(alpha: 0.35), width: 2))),
      child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.mensaje, style: _rajdhani(12, FontWeight.w600, _kText), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Row(children: [
          if (item.fromNickname != null) ...[Text(item.fromNickname!, style: _rajdhani(9, FontWeight.w700, color.withValues(alpha: 0.85))), Container(width: 1, height: 8, color: _kBorder2, margin: const EdgeInsets.symmetric(horizontal: 6))],
          Text(_formatearTiempoGuerra(item.timestamp), style: _rajdhani(9, FontWeight.w500, _kDim)),
        ]),
      ]))]),
    );
  }

  Widget _buildMisionesRecientes() {
    return _Panel(
      accent: _kAccent, label: 'ÚLTIMAS MISIONES', icon: Icons.directions_run_rounded,
      child: _carrerasRecientes.isEmpty ? _emptyRow('Sin misiones registradas')
          : Column(children: _carrerasRecientes.asMap().entries.map((e) {
              final i = e.key; final d = e.value;
              final dist = (d['distancia'] as num?)?.toDouble() ?? 0;
              final seg  = (d['tiempo_segundos'] as num?)?.toInt() ?? 0;
              final vel  = (d['velocidad_media'] as num?)?.toDouble() ?? (dist > 0 && seg > 0 ? dist / (seg / 3600) : 0.0);
              final fecha = _formatFechaCorta(d['timestamp']);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: _kSurface2, borderRadius: BorderRadius.circular(6), border: Border(left: BorderSide(color: i == 0 ? _kBorder2 : _kBorder, width: 1))),
                child: Row(children: [
                  Text('${i + 1}', style: _rajdhani(11, FontWeight.w700, _kDim, spacing: 0)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${dist.toStringAsFixed(2)} km', style: _rajdhani(16, FontWeight.w700, _kWhite, height: 1)),
                    Text('${_formatTiempo(Duration(seconds: seg))}  ·  ${vel.toStringAsFixed(1)} km/h', style: _rajdhani(10, FontWeight.w500, _kDim)),
                  ])),
                  Text(fecha, style: _rajdhani(10, FontWeight.w600, _kMuted)),
                ]),
              );
            }).toList()),
    );
  }

  Widget _buildLogrosPanel() {
    return _Panel(
      accent: _kAccent, label: 'LOGROS', icon: Icons.emoji_events_outlined,
      child: _logros.isEmpty ? _emptyRow('Sin logros todavía')
          : Column(children: _logros.asMap().entries.map((e) {
              final i = e.key; final logro = e.value;
              final titulo     = logro['titulo'] as String? ?? 'Logro';
              final recompensa = (logro['recompensa'] as num? ?? 0).toInt();
              final medalColors = [Colors.amber, const Color(0xFFC0C0C0), const Color(0xFFCD7F32)];
              final color = i < 3 ? medalColors[i] : _kText;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: _kSurface2, borderRadius: BorderRadius.circular(7), border: Border(left: BorderSide(color: color.withValues(alpha: 0.5), width: 2))),
                child: IntrinsicHeight(child: Row(children: [
                  Container(width: 36, alignment: Alignment.center, child: Text(i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}', style: TextStyle(fontSize: i < 3 ? 14 : 10, color: color, fontWeight: FontWeight.w900))),
                  Container(width: 1, color: _kBorder),
                  Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(titulo, style: _rajdhani(13, FontWeight.w700, _kWhite), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (recompensa > 0) ...[const SizedBox(height: 3), Text('+$recompensa monedas', style: _rajdhani(10, FontWeight.w600, color.withValues(alpha: 0.75)))],
                  ]))),
                  if (recompensa > 0) Padding(padding: const EdgeInsets.only(right: 12), child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(5), border: Border.all(color: color.withValues(alpha: 0.18))), child: Text('+$recompensa', style: _rajdhani(11, FontWeight.w900, color)))),
                ])),
              );
            }).toList()),
    );
  }

  Widget _buildMapaPanel() {
    List<Polygon> poligonos = [];
    LatLng centro = const LatLng(37.1350, -3.6330);
    if (_territoriosDelUsuario.isNotEmpty) {
      double latSum = 0, lngSum = 0, total = 0;
      for (final t in _territoriosDelUsuario) {
        final puntos = t['puntos'] as List<LatLng>;
        for (final p in puntos) { latSum += p.latitude; lngSum += p.longitude; total++; }
        poligonos.add(Polygon(points: puntos, color: _colorTerritorio.withValues(alpha: 0.30), borderColor: _colorTerritorio, borderStrokeWidth: 2));
      }
      if (total > 0) centro = LatLng(latSum / total, lngSum / total);
    }
    return _Panel(
      accent: _kAccent, label: isOwnProfile ? 'MIS TERRITORIOS' : 'SUS TERRITORIOS', icon: Icons.map_outlined,
      child: Column(children: [
        GestureDetector(
          onTap: () { if (!_mapaTerritoriosExpandido && _territoriosDelUsuario.isEmpty) { _cargarTerritoriosDelUsuario(); } else { setState(() => _mapaTerritoriosExpandido = !_mapaTerritoriosExpandido); } },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(color: _kSurface2, borderRadius: BorderRadius.circular(6), border: Border.all(color: _kBorder)),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: _colorTerritorio, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              _loadingTerritoriosMapa ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: _kAccent, strokeWidth: 1.5)) : Text(_mapaTerritoriosExpandido ? 'Ocultar mapa' : 'Ver en el mapa', style: _rajdhani(12, FontWeight.w500, _kDim)),
              const Spacer(),
              Icon(_mapaTerritoriosExpandido ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: _kDim, size: 18),
            ]),
          ),
        ),
        if (_mapaTerritoriosExpandido) ...[
          const SizedBox(height: 8),
          if (_territoriosDelUsuario.isEmpty && !_loadingTerritoriosMapa)
            _emptyRow('Sin territorios aún')
          else if (_territoriosDelUsuario.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 240,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: _kBorder)),
                child: Stack(children: [
                  FlutterMap(
                    options: MapOptions(initialCenter: centro, initialZoom: 14, interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag)),
                    children: [
                      TileLayer(urlTemplate: _kMapboxTileUrl, userAgentPackageName: 'com.runner_risk.app', tileSize: 256, additionalOptions: const {'accessToken': _kMapboxToken}),
                      PolygonLayer(polygons: poligonos),
                      MarkerLayer(markers: _territoriosDelUsuario.map((t) {
                        final pts  = t['puntos'] as List<LatLng>;
                        final latC = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
                        final lngC = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
                        return Marker(point: LatLng(latC, lngC), width: 70, height: 20, child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(3), border: Border.all(color: _colorTerritorio, width: 1)), child: Text(nickname, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: _rajdhani(8, FontWeight.w700, _colorTerritorio, spacing: 0.5))));
                      }).toList()),
                    ],
                  ),
                  Positioned(top: 8, right: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(4)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.flag_rounded, color: Colors.black, size: 9), const SizedBox(width: 3), Text('${_territoriosDelUsuario.length}', style: _rajdhani(10, FontWeight.w700, Colors.black))]))),
                ]),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _buildColorPanel() {
    final _RiskColor? colorActual = _coloresDisponibles.where((c) => c.color.value == _colorTerritorio.value).firstOrNull;
    final String nombreActual = colorActual?.nombre ?? 'Personalizado';
    return _Panel(
      accent: _kAccent, label: 'COLOR DE TERRITORIO', icon: Icons.palette_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Identifica tus zonas en el mapa y cómo te ven otros jugadores.', style: _rajdhani(11, FontWeight.w400, _kSubtext)),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => setState(() => _colorPanelExpandido = !_colorPanelExpandido),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: _colorTerritorio, borderRadius: BorderRadius.circular(8))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('COLOR ACTUAL', style: _rajdhani(8, FontWeight.w700, _kDim, spacing: 2)), const SizedBox(height: 2), Text(nombreActual, style: _rajdhani(14, FontWeight.w700, _colorTerritorio))])),
            AnimatedRotation(turns: _colorPanelExpandido ? 0.5 : 0, duration: const Duration(milliseconds: 250), child: Container(width: 28, height: 28, decoration: BoxDecoration(color: _kSurface2, borderRadius: BorderRadius.circular(6), border: Border.all(color: _kBorder2)), child: const Icon(Icons.keyboard_arrow_down_rounded, color: _kDim, size: 18))),
          ]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic,
          child: _colorPanelExpandido
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 16),
                  Container(height: 1, color: _kBorder, margin: const EdgeInsets.only(bottom: 14)),
                  Wrap(spacing: 10, runSpacing: 14, children: _coloresDisponibles.map((rc) {
                    final bool sel = _colorTerritorio.value == rc.color.value;
                    return GestureDetector(
                      onTap: () { _guardarColorTerritorio(rc.color); setState(() => _colorPanelExpandido = false); },
                      child: SizedBox(width: 56, child: Column(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedContainer(duration: const Duration(milliseconds: 200), width: sel ? 44 : 38, height: sel ? 44 : 38, decoration: BoxDecoration(color: rc.color, borderRadius: BorderRadius.circular(9), border: Border.all(color: sel ? Colors.white : _kBorder, width: sel ? 2 : 1), boxShadow: sel ? [BoxShadow(color: rc.color.withValues(alpha: 0.5), blurRadius: 8)] : []), child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 16) : null),
                        const SizedBox(height: 5),
                        Text(rc.nombre.split(' ').last, style: _rajdhani(8, sel ? FontWeight.w700 : FontWeight.w500, sel ? _colorTerritorio : _kDim), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ])),
                    );
                  }).toList()),
                ])
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Widget _popupItem(IconData icon, String label, Color color) {
    return Row(children: [
      Container(width: 26, height: 26, decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.12))), child: Icon(icon, color: color, size: 13)),
      const SizedBox(width: 12),
      Text(label, style: _rajdhani(13, FontWeight.w600, _kText)),
    ]);
  }

  Widget _buildFriendshipButton() {
    if (_loadingFriendship) return Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: _kAccent, strokeWidth: 1.5)));
    switch (_friendshipStatus) {
      case 'accepted':
        return _socialBtn('Amigos', Icons.people_rounded, Colors.greenAccent, () => _confirmarEliminarAmistad(), outlined: true);
      case 'pending_sent':
        return _socialBtn('Solicitud enviada', Icons.hourglass_top_rounded, _kMuted, () => _confirmarEliminarAmistad(), outlined: true);
      case 'pending_received':
        return Row(children: [
          Expanded(child: _socialBtn('Aceptar', Icons.check_rounded, Colors.greenAccent, _aceptarSolicitud)),
          const SizedBox(width: 8),
          Expanded(child: _socialBtn('Rechazar', Icons.close_rounded, Colors.redAccent, _eliminarAmistad, outlined: true)),
        ]);
      default:
        return _socialBtn('Añadir operativo', Icons.person_add_outlined, _kText, _enviarSolicitudAmistad);
    }
  }

  Widget _socialBtn(String label, IconData icon, Color color, VoidCallback onTap, {bool outlined = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(color: outlined ? Colors.transparent : color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: outlined ? 0.30 : 0.18))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color, size: 15), const SizedBox(width: 8), Text(label, style: _rajdhani(12, FontWeight.w700, color, spacing: 0.5))]),
      ),
    );
  }

  void _confirmarEliminarAmistad() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: _kSurface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _kBorder2)),
      title: Text('Eliminar amistad', style: _rajdhani(16, FontWeight.w700, _kWhite)),
      content: Text(_friendshipStatus == 'pending_sent' ? 'Se cancelará la solicitud enviada.' : 'Dejarás de ser aliado con $nickname.', style: _rajdhani(13, FontWeight.w500, _kSubtext)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: _rajdhani(12, FontWeight.w600, _kDim))),
        TextButton(onPressed: () { Navigator.pop(ctx); _eliminarAmistad(); }, child: Text('Eliminar', style: _rajdhani(12, FontWeight.w700, Colors.redAccent))),
      ],
    ));
  }

  Widget _glowBar(double val, {double height = 3, Color? color}) {
    return Stack(children: [
      Container(height: height, decoration: BoxDecoration(color: _kBorder2, borderRadius: BorderRadius.circular(2))),
      FractionallySizedBox(widthFactor: val.clamp(0.0, 1.0), child: Container(height: height, decoration: BoxDecoration(color: color ?? _kAccent, borderRadius: BorderRadius.circular(2)))),
    ]);
  }

  Widget _emptyRow(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(text, style: _rajdhani(12, FontWeight.w500, _kDim)));
}

// ═══════════════════════════════════════════════════════════
//  WIDGETS AUXILIARES
// ═══════════════════════════════════════════════════════════

/// Widget que anima un número desde 0 hasta [value].
/// Se reinicia cada vez que [value] cambia.
class _AnimatedCounter extends StatefulWidget {
  final double value;
  final int decimals;
  final TextStyle style;
  final Duration duration;

  const _AnimatedCounter({
    required this.value,
    required this.style,
    this.decimals = 0,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<_AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<_AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _prevValue = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween<double>(begin: 0, end: widget.value).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    if (widget.value > 0) _ctrl.forward();
  }

  @override
  void didUpdateWidget(_AnimatedCounter old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _anim = Tween<double>(begin: _prevValue, end: widget.value).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _ctrl.forward(from: 0);
    }
    _prevValue = widget.value;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) {
      final val = _anim.value;
      final text = widget.decimals > 0
          ? val.toStringAsFixed(widget.decimals)
          : val.toInt().toString();
      return Text(text, style: widget.style);
    },
  );
}

class _Panel extends StatelessWidget {
  final Color accent; final String label; final IconData icon; final Widget child;
  const _Panel({required this.accent, required this.label, required this.icon, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF0C0C0C), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF161616))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: accent.withValues(alpha: 0.08)))), child: Row(children: [
          Container(width: 2, height: 13, decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(1))),
          const SizedBox(width: 9),
          Icon(icon, color: const Color(0xFF3A3A3A), size: 11),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.rajdhani(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF4A4A4A), letterSpacing: 2.5)),
        ])),
        Padding(padding: const EdgeInsets.all(18), child: child),
      ]),
    );
  }
}

class _DossierBgPainter extends CustomPainter {
  final Color accent; final double pulse, scan;
  _DossierBgPainter({required this.accent, required this.pulse, required this.scan});
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5, cy = size.height * 0.38;
    for (int i = 1; i <= 5; i++) { canvas.drawCircle(Offset(cx, cy), i * 36.0, Paint()..color = accent.withValues(alpha: 0.012)..strokeWidth = 0.6..style = PaintingStyle.stroke); }
    canvas.drawLine(Offset(cx - 180, cy), Offset(cx + 180, cy), Paint()..color = accent.withValues(alpha: 0.022)..strokeWidth = 0.4);
    canvas.drawLine(Offset(cx, cy - 180), Offset(cx, cy + 180), Paint()..color = accent.withValues(alpha: 0.022)..strokeWidth = 0.4);
    final sweepAngle = scan * 2 * math.pi;
    final sweepRect  = Rect.fromCircle(center: Offset(cx, cy), radius: 180);
    canvas.drawArc(sweepRect, sweepAngle - 0.7, 0.7, true, Paint()..shader = RadialGradient(colors: [accent.withValues(alpha: 0.05), Colors.transparent]).createShader(sweepRect)..style = PaintingStyle.fill);
    canvas.drawLine(Offset(cx, cy), Offset(cx + 178 * math.cos(sweepAngle), cy + 178 * math.sin(sweepAngle)), Paint()..color = accent.withValues(alpha: 0.09)..strokeWidth = 0.8);
    canvas.drawCircle(Offset(cx, cy), 2.5, Paint()..color = accent.withValues(alpha: 0.28));
    canvas.drawLine(Offset(0, size.height * 0.62), Offset(size.width, size.height * 0.62), Paint()..color = accent.withValues(alpha: 0.04)..strokeWidth = 0.8);
    for (int i = 0; i < 6; i++) {
      final y = 60.0 + i * 24;
      canvas.drawLine(Offset(0, y), Offset(i % 2 == 0 ? 12 : 6, y), Paint()..color = accent.withValues(alpha: 0.07)..strokeWidth = 0.8);
      canvas.drawLine(Offset(size.width, y), Offset(size.width - (i % 2 == 0 ? 12 : 6), y), Paint()..color = accent.withValues(alpha: 0.07)..strokeWidth = 0.8);
    }
  }
  @override
  bool shouldRepaint(_DossierBgPainter o) => o.pulse != pulse || o.scan != scan || o.accent != accent;
}

class _RachaGaugePainter extends CustomPainter {
  final double progress, pulse; final Color accent; final bool activa;
  _RachaGaugePainter({required this.progress, required this.pulse, required this.accent, required this.activa});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final startAngle = -math.pi * 0.75;
    final sweepTotal = math.pi * 1.5;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), startAngle, sweepTotal, false, Paint()..color = const Color(0xFF1A1A1A)..strokeWidth = 5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    if (progress > 0) canvas.drawArc(Rect.fromCircle(center: c, radius: r), startAngle, sweepTotal * progress, false, Paint()..color = accent..strokeWidth = 5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    final dotPaint = Paint()..color = accent.withValues(alpha: 0.25)..style = PaintingStyle.fill;
    for (final angle in [startAngle, startAngle + sweepTotal]) { canvas.drawCircle(Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle)), 1.5, dotPaint); }
  }
  @override
  bool shouldRepaint(_RachaGaugePainter o) => o.progress != progress || o.pulse != pulse || o.accent != accent;
}

class _LoaderPainter extends CustomPainter {
  final Color accent; final double progress, pulse;
  _LoaderPainter({required this.accent, required this.progress, required this.pulse});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    for (int i = 1; i <= 3; i++) { canvas.drawCircle(c, 7.0 * i * 1.1, Paint()..color = accent.withValues(alpha: 0.03 + 0.015 * pulse * (4 - i))..strokeWidth = 0.6..style = PaintingStyle.stroke); }
    canvas.drawArc(Rect.fromCircle(center: c, radius: 18), progress * 2 * math.pi, 1.2, false, Paint()..color = accent..strokeWidth = 1.8..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(_LoaderPainter o) => o.progress != progress || o.pulse != pulse;
}

class _RiskColor {
  final Color color; final String nombre;
  const _RiskColor(this.color, this.nombre);
}

class _BotonFoto extends StatelessWidget {
  final IconData icon; final String label; final Color accent; final VoidCallback onTap;
  const _BotonFoto({required this.icon, required this.label, required this.accent, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(color: const Color(0xFF0D0D0D), borderRadius: BorderRadius.circular(8), border: Border.all(color: accent.withValues(alpha: 0.18))),
      child: Column(children: [Icon(icon, color: accent, size: 22), const SizedBox(height: 8), Text(label, style: GoogleFonts.rajdhani(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF666666)))]),
    ));
  }
}