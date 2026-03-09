import 'dart:async';
import 'dart:convert';
import 'package:RunnerRisk/Pestañas/Social_screen.dart';
import 'package:RunnerRisk/services/league_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../Widgets/custom_navbar.dart';
import '../services/territory_service.dart';
import 'fullscreen_map_screen.dart';
import 'notifications_screen.dart';
import 'perfil_screen.dart';
import '../widgets/conquista_overlay.dart';

// =============================================================================
// MAPBOX
// =============================================================================
const _kMapboxToken =
    'pk.eyJ1IjoibHVpaXNnb29tZXp6MSIsImEiOiJjbW1keTI1bjkwN25qMm9zNzFlOXZkeG9wIn0.l186BxbIhi6-vAXtBjIzsw';
const _kMapboxTileUrl =
    'https://api.mapbox.com/styles/v1/luiisgoomezz1/cmmdzh1aj00f501r68crag5gv/tiles/256/{z}/{x}/{y}@2x?access_token=$_kMapboxToken';

// =============================================================================
// DESIGN TOKENS — PARCH DARK
// =============================================================================
class _RR {
  // Fondos
  static const bg0 = Color(0xFF090807); // --void
  static const bg1 = Color(0xFF100D08); // --surf
  static const bg2 = Color(0xFF161209); // --surf2
  static const bg3 = Color(0xFF1C1610); // un tono más claro

  // Pergamino / dorado
  static const parch  = Color(0xFFEAD9AA); // --parch
  static const parchm = Color(0xFFCAAA6C); // --parchm  ← color de acento dorado
  static const parchd = Color(0xFF8C7242); // --parchd
  static const bronze = Color(0xFFCC7C3A); // --bronze
  static const ivory  = Color(0xFFF3EDE1); // --ivory

  // Rojo dinámico (se sobreescribe desde perfil)
  static const red    = Color(0xFFE62E2E); // --red  (fallback)
  static const redb   = Color(0xFFBF2626); // --redb
  static const redd   = Color(0xFF5C0E0E); // --redd

  // Otros acentos
  static const cyan   = Color(0xFF9EB2C6); // --silver (frío, secundario)
  static const gold   = Color(0xFFDECA46); // --gold
  static const safe   = Color(0xFF6AAF6A); // verde apagado
  static const warn   = Color(0xFFDECA46); // dorado

  // Textos
  static const t1 = Color(0xFFF3EDE1); // ivory
  static const t2 = Color(0xFFCAAA6C); // parchm
  static const t3 = Color(0xFF8C7242); // parchd

  // Bordes
  static const border    = Color(0x1FCAAA6C); // rgba(202,170,108,0.12)
  static const borderHot = Color(0x3FCAAA6C); // rgba(202,170,108,0.25)

  // Danger (rojo) — getter estático para compat. con código existente
  static const danger = red;
  static const fire   = bronze;
  static const fireGlow = parch;
}

// =============================================================================
// MODELO FEED POST  (sin cambios)
// =============================================================================
class FeedPost {
  final String id;
  final String userId;
  final String userNickname;
  final String? userAvatarBase64;
  final int userNivel;
  final String tipo;
  final String? titulo;
  final String? descripcion;
  final String? mediaBase64;
  final double? distanciaKm;
  final Duration? tiempo;
  final double? velocidadMedia;
  final List<LatLng>? ruta;
  final int likes;
  final int comentarios;
  final bool likedByMe;
  final bool savedByMe;
  final DateTime fecha;
  final Color userColor;

  FeedPost({
    required this.id,
    required this.userId,
    required this.userNickname,
    this.userAvatarBase64,
    required this.userNivel,
    required this.tipo,
    this.titulo,
    this.descripcion,
    this.mediaBase64,
    this.distanciaKm,
    this.tiempo,
    this.velocidadMedia,
    this.ruta,
    required this.likes,
    required this.comentarios,
    required this.likedByMe,
    required this.savedByMe,
    required this.fecha,
    required this.userColor,
  });

  factory FeedPost.fromFirestore(
      DocumentSnapshot doc, String myUid, Color userColor) {
    final d = doc.data() as Map<String, dynamic>;
    final ts = d['timestamp'] as Timestamp?;
    final rawRuta = d['ruta'] as List<dynamic>?;
    List<LatLng>? ruta;
    if (rawRuta != null) {
      ruta = rawRuta.map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng(
            (m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
      }).toList();
    }
    final likesList = (d['likes'] as List<dynamic>?) ?? [];
    final savedList = (d['saved'] as List<dynamic>?) ?? [];
    return FeedPost(
      id: doc.id,
      userId: d['userId'] ?? '',
      userNickname: d['userNickname'] ?? 'Runner',
      userAvatarBase64: d['userAvatarBase64'] as String?,
      userNivel: d['userNivel'] ?? 1,
      tipo: d['tipo'] ?? 'run',
      titulo: d['titulo'] as String?,
      descripcion: d['descripcion'] as String?,
      mediaBase64: d['mediaBase64'] as String?,
      distanciaKm: (d['distanciaKm'] as num?)?.toDouble(),
      tiempo: d['tiempoSegundos'] != null
          ? Duration(seconds: (d['tiempoSegundos'] as num).toInt())
          : null,
      velocidadMedia: (d['velocidadMedia'] as num?)?.toDouble(),
      ruta: ruta,
      likes: likesList.length,
      comentarios: d['comentariosCount'] ?? 0,
      likedByMe: likesList.contains(myUid),
      savedByMe: savedList.contains(myUid),
      fecha: ts?.toDate() ?? DateTime.now(),
      userColor: userColor,
    );
  }
}

// =============================================================================
// HOME SCREEN
// =============================================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  // ── Perfil
  Position? _currentPosition;
  String nickname = "Cargando...";
  int monedas = 0;
  int nivel = 1;
  String? fotoBase64;
  bool isLoading = true;

  // ── Color dinámico (configurado desde perfil)
  Color _accentColor = _RR.red;

  // ── Retos / logros
  List<QueryDocumentSnapshot> _dailyChallenges = [];
  bool _loadingChallenges = true;
  List<Map<String, dynamic>> _completedChallengesCache = [];
  bool _mostrarTodosLosLogros = false;
  Timer? _dailyResetTimer;
  Duration _timeUntilReset = Duration.zero;

  // ── Mapa
  List<TerritoryData> _territorios = [];
  bool _loadingTerritorios = true;
  final MapController _homeMapController = MapController();
  StreamSubscription<QuerySnapshot>? _invasionListener;

  // ── Territorios cercanos
  List<_UserTerritoryGroup> _gruposTerritoriosCercanos = [];
  bool _loadingCercanos = false;
  bool _panelCercanosExpandido = false;
  String? _userExpandido;
  final Map<String, List<_TerritoryDetail>> _detallesPorUser = {};

  // ── Notificaciones
  int _notifNoLeidas = 0;
  StreamSubscription<QuerySnapshot>? _notifCountListener;

  // ── Feed
  List<FeedPost> _feedPosts = [];
  bool _loadingFeed = true;
  StreamSubscription<QuerySnapshot>? _feedListener;
  final List<Color> _paletaColores = [
    _RR.bronze,
    _RR.parch,
    const Color(0xFFCC9966),
    const Color(0xFF9EB2C6),
    const Color(0xFFDECA46),
    const Color(0xFFB88040),
  ];

  // ── Tab activa
  String _tabActiva = 'feed';

  StreamSubscription<User?>? _authListener;

  // ── Animaciones
  late AnimationController _headerAnimController;
  late AnimationController _contentAnimController;
  late AnimationController _pulseController;
  late Animation<double> _headerFade;
  late Animation<double> _contentFade;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _headerAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _contentAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _headerFade =
        CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOut);
    _contentFade =
        CurvedAnimation(parent: _contentAnimController, curve: Curves.easeIn);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _getUserLocation();

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _initializeData();
      _escucharNotificacionesInvasion();
      _escucharConteoNotificaciones();
      _escucharFeed();
    } else {
      _authListener = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null && mounted) {
          _initializeData();
          _escucharNotificacionesInvasion();
          _escucharConteoNotificaciones();
          _escucharFeed();
          _authListener?.cancel();
          _authListener = null;
        }
      });
    }
  }

  @override
  void dispose() {
    _dailyResetTimer?.cancel();
    _headerAnimController.dispose();
    _contentAnimController.dispose();
    _pulseController.dispose();
    _invasionListener?.cancel();
    _notifCountListener?.cancel();
    _feedListener?.cancel();
    _authListener?.cancel();
    super.dispose();
  }

  // ── Notificaciones
  void _escucharConteoNotificaciones() {
    if (userId == null) return;
    _notifCountListener?.cancel();
    _notifCountListener = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _notifNoLeidas = snap.docs.length);
    });
  }

  // ── Feed
  void _escucharFeed() {
    if (userId == null) return;
    if (mounted) setState(() => _loadingFeed = true);
    _feedListener?.cancel();

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _loadingFeed) {
        debugPrint("⚠️ Feed timeout: forzando loadingFeed=false");
        setState(() => _loadingFeed = false);
      }
    });

    _feedListener = FirebaseFirestore.instance
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(30)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final uid = userId;
      if (uid == null) return;
      debugPrint("✅ Feed recibido: ${snap.docs.length} posts");
      final posts = snap.docs.asMap().entries.map((entry) {
        final color = _paletaColores[entry.key % _paletaColores.length];
        return FeedPost.fromFirestore(entry.value, uid, color);
      }).toList();
      setState(() {
        _feedPosts = posts;
        _loadingFeed = false;
      });
    }, onError: (e) {
      debugPrint("❌ Error feed: $e");
      if (mounted) setState(() => _loadingFeed = false);
    });
  }

  Future<void> _toggleLike(FeedPost post) async {
    if (userId == null) return;
    final ref = FirebaseFirestore.instance.collection('posts').doc(post.id);
    if (post.likedByMe) {
      await ref.update({'likes': FieldValue.arrayRemove([userId])});
    } else {
      await ref.update({'likes': FieldValue.arrayUnion([userId])});
    }
  }

  Future<void> _toggleSave(FeedPost post) async {
    if (userId == null) return;
    final ref = FirebaseFirestore.instance.collection('posts').doc(post.id);
    if (post.savedByMe) {
      await ref.update({'saved': FieldValue.arrayRemove([userId])});
    } else {
      await ref.update({'saved': FieldValue.arrayUnion([userId])});
    }
  }

  Future<void> _guardarRuta(FeedPost post) async {
    if (userId == null || post.ruta == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('players')
          .doc(userId)
          .collection('saved_routes')
          .add({
        'postId': post.id,
        'fromNickname': post.userNickname,
        'titulo': post.titulo ?? 'Ruta guardada',
        'distanciaKm': post.distanciaKm,
        'ruta': post.ruta!
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.transparent,
            elevation: 0,
            content: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _RR.bg2,
                border: Border.all(color: _RR.parchd.withOpacity(0.5)),
                boxShadow: [
                  BoxShadow(
                      color: _RR.parchm.withOpacity(0.15),
                      blurRadius: 16,
                      spreadRadius: 2)
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: _RR.safe, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  const Text('RUTA GUARDADA',
                      style: TextStyle(
                          color: _RR.parch,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 2)),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error guardando ruta: $e");
    }
  }

  // ── Ubicación
  Future<void> _getUserLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition();
        if (mounted) setState(() => _currentPosition = position);
      }
    } catch (e) {
      debugPrint("Error ubicación: $e");
    }
  }

  // ── Init
  Future<void> _initializeData() async {
    if (userId == null) return;
    if (mounted) setState(() => isLoading = true);
    try {
      await _loadUserData();
      await _checkDailyReset();
      await _loadCompletedChallenges();
      await _loadRandomDailyChallenges();
      await _cargarTerritorios();
    } catch (e) {
      debugPrint("Error en inicialización: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        _headerAnimController.forward();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _contentAnimController.forward();
        });
      }
    }
  }

  Future<void> _cargarTerritorios() async {
    if (mounted) setState(() => _loadingTerritorios = true);
    try {
      final lista = await TerritoryService.cargarTodosLosTerritorios();
      if (mounted) {
        setState(() {
          _territorios = lista;
          _loadingTerritorios = false;
        });
      }
    } catch (e) {
      debugPrint("Error cargando territorios: $e");
      if (mounted) setState(() => _loadingTerritorios = false);
    }
  }

  Future<void> _cargarTerritoriosCercanos() async {
    if (mounted) setState(() => _loadingCercanos = true);
    final bool usarFiltroDistancia = !kIsWeb && _currentPosition != null;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('territories').get();
      final Map<String, _UserTerritoryGroup> grupos = {};
      final myUid = userId!;

      for (final doc in snap.docs) {
        final data = doc.data();
        final rawPuntos = data['puntos'] as List<dynamic>?;
        if (rawPuntos == null || rawPuntos.isEmpty) continue;

        final List<LatLng> puntos = rawPuntos.map((p) {
          final map = p as Map<String, dynamic>;
          return LatLng(
            (map['lat'] as num).toDouble(),
            (map['lng'] as num).toDouble(),
          );
        }).toList();

        final double latC =
            puntos.map((p) => p.latitude).reduce((a, b) => a + b) /
                puntos.length;
        final double lngC =
            puntos.map((p) => p.longitude).reduce((a, b) => a + b) /
                puntos.length;

        double distMetros = 0;
        if (_currentPosition != null) {
          distMetros = Geolocator.distanceBetween(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              latC,
              lngC);
        }
        if (usarFiltroDistancia && distMetros > 5000) continue;

        final String ownerId = data['userId'] as String? ?? '';
        if (ownerId.isEmpty) continue;

        if (!grupos.containsKey(ownerId)) {
          String ownerNick = ownerId == myUid ? nickname : ownerId;
          int ownerNivel = 1;
          Color ownerColor = ownerId == myUid ? _accentColor : _RR.cyan;
          try {
            final playerDoc = await FirebaseFirestore.instance
                .collection('players')
                .doc(ownerId)
                .get();
            if (playerDoc.exists) {
              final pd = playerDoc.data()!;
              ownerNick = pd['nickname'] ?? ownerNick;
              ownerNivel = pd['nivel'] ?? 1;
              final colorInt = (pd['territorio_color'] as num?)?.toInt();
              if (colorInt != null) ownerColor = Color(colorInt);
            }
          } catch (_) {}
          grupos[ownerId] = _UserTerritoryGroup(
            ownerId: ownerId,
            nickname: ownerNick,
            nivel: ownerNivel,
            color: ownerColor,
            esMio: ownerId == myUid,
            territorios: [],
          );
        }

        grupos[ownerId]!.territorios.add(_TerritoryDetail(
            docId: doc.id,
            distanciaAlCentroKm: distMetros / 1000,
            puntos: puntos));
      }

      final lista = grupos.values.toList()
        ..sort((a, b) {
          if (a.esMio) return -1;
          if (b.esMio) return 1;
          return a.nickname.compareTo(b.nickname);
        });

      if (mounted) {
        setState(() {
          _gruposTerritoriosCercanos = lista;
          _loadingCercanos = false;
          _panelCercanosExpandido = true;
        });
      }
    } catch (e) {
      debugPrint("Error cargando cercanos: $e");
      if (mounted) setState(() => _loadingCercanos = false);
    }
  }

  Future<void> _cargarDetallesUsuario(String ownerId) async {
    if (_detallesPorUser.containsKey(ownerId)) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('territories')
          .where('userId', isEqualTo: ownerId)
          .get();

      final List<_TerritoryDetail> detalles = [];
      double? distanciaRecorrida;
      double? velocidadMedia;
      Duration? tiempoActividad;
      DateTime? fechaLog;

      try {
        final logSnap = await FirebaseFirestore.instance
            .collection('activity_logs')
            .where('userId', isEqualTo: ownerId)
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();
        if (logSnap.docs.isNotEmpty) {
          final logData = logSnap.docs.first.data();
          distanciaRecorrida = (logData['distancia'] as num?)?.toDouble();
          final int? tiempoSeg =
              (logData['tiempo_segundos'] as num?)?.toInt();
          if (tiempoSeg != null)
            tiempoActividad = Duration(seconds: tiempoSeg);
          if (distanciaRecorrida != null &&
              tiempoSeg != null &&
              tiempoSeg > 0) {
            velocidadMedia = distanciaRecorrida / (tiempoSeg / 3600);
          }
          final ts = logData['timestamp'] as Timestamp?;
          if (ts != null) fechaLog = ts.toDate();
        }
      } catch (_) {}

      for (final doc in snap.docs) {
        final data = doc.data();
        DateTime? ultimaVisita;
        final tsVisita = data['ultima_visita'] as Timestamp?;
        if (tsVisita != null) ultimaVisita = tsVisita.toDate();
        final int diasSinVisitar = ultimaVisita == null
            ? 0
            : DateTime.now().difference(ultimaVisita).inDays;
        final rawPuntos = data['puntos'] as List<dynamic>?;
        List<LatLng> puntos = [];
        double distanciaAlCentro = 0;
        if (rawPuntos != null && rawPuntos.isNotEmpty) {
          puntos = rawPuntos.map((p) {
            final map = p as Map<String, dynamic>;
            return LatLng((map['lat'] as num).toDouble(),
                (map['lng'] as num).toDouble());
          }).toList();
          if (_currentPosition != null) {
            final double latC =
                puntos.map((p) => p.latitude).reduce((a, b) => a + b) /
                    puntos.length;
            final double lngC =
                puntos.map((p) => p.longitude).reduce((a, b) => a + b) /
                    puntos.length;
            distanciaAlCentro = Geolocator.distanceBetween(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                    latC,
                    lngC) /
                1000;
          }
        }
        detalles.add(_TerritoryDetail(
          docId: doc.id,
          distanciaAlCentroKm: distanciaAlCentro,
          diasSinVisitar: diasSinVisitar,
          fechaCreacion: ultimaVisita ?? fechaLog,
          distanciaRecorrida: distanciaRecorrida,
          velocidadMedia: velocidadMedia,
          tiempoActividad: tiempoActividad,
          puntos: puntos,
        ));
      }

      if (mounted) setState(() => _detallesPorUser[ownerId] = detalles);
    } catch (e) {
      debugPrint("Error cargando detalles de $ownerId: $e");
    }
  }

  void _mostrarDialogTerritorio(
      _TerritoryDetail det, Color color, String ownerNickname) {
    final LatLng centro = det.puntos.isNotEmpty
        ? LatLng(
            det.puntos.map((p) => p.latitude).reduce((a, b) => a + b) /
                det.puntos.length,
            det.puntos.map((p) => p.longitude).reduce((a, b) => a + b) /
                det.puntos.length)
        : const LatLng(37.1350, -3.6330);

    String estadoDeterioro = 'ACTIVO';
    Color colorEstado = _RR.safe;
    if (det.diasSinVisitar != null && det.diasSinVisitar! >= 10) {
      estadoDeterioro = 'CRÍTICO';
      colorEstado = _accentColor;
    } else if (det.diasSinVisitar != null && det.diasSinVisitar! >= 5) {
      estadoDeterioro = 'DESGASTE';
      colorEstado = _RR.warn;
    }

    String? tiempoFormateado;
    if (det.tiempoActividad != null) {
      final h = det.tiempoActividad!.inHours;
      final m = det.tiempoActividad!.inMinutes.remainder(60);
      final s = det.tiempoActividad!.inSeconds.remainder(60);
      tiempoFormateado = h > 0
          ? '${h}h ${m.toString().padLeft(2, '0')}m'
          : '${m}m ${s.toString().padLeft(2, '0')}s';
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.88),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
          child: Container(
            decoration: BoxDecoration(
              color: _RR.bg1,
              border: Border.all(color: color.withOpacity(0.35)),
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(0.15),
                    blurRadius: 32,
                    spreadRadius: 2)
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header con línea gradiente inferior
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: color.withOpacity(0.2), width: 1)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.10),
                          border: Border.all(
                              color: color.withOpacity(0.4), width: 1),
                        ),
                        child: Text('ZONA',
                            style: TextStyle(
                                color: color,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(ownerNickname.toUpperCase(),
                              style: const TextStyle(
                                  color: _RR.ivory,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 1.5))),
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded,
                              color: _RR.parchd, size: 20)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: SizedBox(
                    height: 180,
                    child: det.puntos.isEmpty
                        ? Container(
                            color: _RR.bg0,
                            child: Center(
                                child: Text('SIN DATOS',
                                    style: TextStyle(
                                        color: _RR.parchd,
                                        fontSize: 11,
                                        letterSpacing: 2))))
                        : FlutterMap(
                            options: MapOptions(
                                initialCenter: centro,
                                initialZoom: 15,
                                interactionOptions:
                                    const InteractionOptions(
                                        flags: InteractiveFlag.none)),
                            children: [
                              TileLayer(
                                urlTemplate: _kMapboxTileUrl,
                                userAgentPackageName:
                                    'com.runner_risk.app',
                                tileSize: 256,
                                additionalOptions: const {
                                  'accessToken': _kMapboxToken
                                },
                              ),
                              PolygonLayer(polygons: [
                                Polygon(
                                    points: det.puntos,
                                    color: color.withOpacity(0.3),
                                    borderColor: color,
                                    borderStrokeWidth: 2.5)
                              ]),
                            ],
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.3,
                    children: [
                      _dialogStatCard(
                          icon: Icons.shield_outlined,
                          title: 'ESTADO',
                          value: estadoDeterioro,
                          color: colorEstado),
                      _dialogStatCard(
                          icon: Icons.calendar_today_outlined,
                          title: 'SIN VISITAR',
                          value: det.diasSinVisitar != null
                              ? '${det.diasSinVisitar}d'
                              : '--',
                          color: _RR.parchd),
                      _dialogStatCard(
                          icon: Icons.flag_outlined,
                          title: 'CONQUISTADO',
                          value: det.fechaCreacion != null
                              ? _formatFecha(det.fechaCreacion!)
                              : '--',
                          color: _RR.parchd,
                          smallText: true),
                      _dialogStatCard(
                          icon: Icons.straighten_outlined,
                          title: 'DISTANCIA',
                          value: det.distanciaRecorrida != null
                              ? '${det.distanciaRecorrida!.toStringAsFixed(2)}km'
                              : '--',
                          color: _RR.parchm),
                      _dialogStatCard(
                          icon: Icons.speed_outlined,
                          title: 'VEL. MEDIA',
                          value: det.velocidadMedia != null
                              ? '${det.velocidadMedia!.toStringAsFixed(1)}'
                              : '--',
                          color: _RR.bronze),
                      _dialogStatCard(
                          icon: Icons.timer_outlined,
                          title: 'TIEMPO',
                          value: tiempoFormateado ?? '--',
                          color: _RR.parch),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                        color: _RR.bg0,
                        border: Border.all(color: _RR.border)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.my_location_outlined,
                            color: _RR.parchd, size: 13),
                        const SizedBox(width: 6),
                        Text(
                            'A ${det.distanciaAlCentroKm.toStringAsFixed(2)} km de tu posición',
                            style: const TextStyle(
                                color: _RR.t2,
                                fontSize: 12,
                                letterSpacing: 0.3)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dialogStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    bool smallText = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          border: Border.all(color: color.withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    color: _RR.parchd,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: smallText ? 10 : 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5)),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Invasión
  void _escucharNotificacionesInvasion() {
    if (userId == null) return;
    _invasionListener?.cancel();
    _invasionListener = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .where('type', isEqualTo: 'territory_invasion')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      for (var change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          _mostrarBannerInvasion(
              data['message'] ?? '⚔️ Alguien está invadiendo tu territorio',
              change.doc.id);
        }
      }
    });
  }

  void _mostrarBannerInvasion(String mensaje, String notifId) {
    if (!mounted) return;
    FirebaseFirestore.instance
        .collection('notifications')
        .doc(notifId)
        .update({'read': true});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: _RR.redd.withOpacity(0.95),
            border: Border.all(color: _accentColor.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                  color: _accentColor.withOpacity(0.35), blurRadius: 16)
            ]),
        child: Row(children: [
          const Text('⚔️', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(mensaje,
                  style: const TextStyle(
                      color: _RR.ivory,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.5))),
          TextButton(
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              child: Text('DEFENDER',
                  style: TextStyle(
                      color: _accentColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 1.5))),
        ]),
      ),
    ));
  }

  // ── Datos usuario
  Future<void> _loadUserData() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('players')
        .doc(userId)
        .get();
    if (userDoc.exists && mounted) {
      final data = userDoc.data()!;
      final colorInt = (data['territorio_color'] as num?)?.toInt();
      setState(() {
        nickname = data['nickname'] ?? "Corredor";
        monedas = data['monedas'] ?? 0;
        nivel = data['nivel'] ?? 1;
        fotoBase64 = data['foto_base64'] as String?;
        if (colorInt != null) _accentColor = Color(colorInt);
      });
    }
  }

  Future<void> _loadCompletedChallenges() async {
    if (userId == null) return;
    final ahora = DateTime.now();
    final String fechaHoy =
        "${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}";
    try {
      final logsSnap = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('userId', isEqualTo: userId)
          .where('fecha_dia', isEqualTo: fechaHoy)
          .get();
      List<Map<String, dynamic>> listaTemporal = logsSnap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .where((d) =>
              d.containsKey('id_reto_completado') &&
              d['id_reto_completado'] != null)
          .toList();
      listaTemporal.sort((a, b) {
        Timestamp? tA = a['timestamp'] as Timestamp?;
        Timestamp? tB = b['timestamp'] as Timestamp?;
        if (tA == null || tB == null) return 0;
        return tB.compareTo(tA);
      });
      if (mounted)
        setState(() => _completedChallengesCache = listaTemporal);
    } catch (e) {
      debugPrint("Error cargando logros: $e");
    }
  }

  Future<void> _checkDailyReset() async {
    final userDocRef =
        FirebaseFirestore.instance.collection('players').doc(userId);
    final userDoc = await userDocRef.get();
    if (!userDoc.exists) return;
    final data = userDoc.data()!;
    final lastReset = data['last_daily_reset'] as Timestamp?;
    final now = DateTime.now();
    if (lastReset == null ||
        now.difference(lastReset.toDate()).inSeconds >= 86400) {
      await userDocRef.update({'last_daily_reset': Timestamp.now()});
      _setupDailyTimer(lastResetTime: now);
    } else {
      _setupDailyTimer(lastResetTime: lastReset.toDate());
    }
  }

  void _setupDailyTimer({required DateTime lastResetTime}) {
    final resetTime = lastResetTime.add(const Duration(hours: 24));
    _dailyResetTimer?.cancel();
    _dailyResetTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        final now = DateTime.now();
        setState(() => _timeUntilReset = resetTime.difference(now));
        if (_timeUntilReset.isNegative || _timeUntilReset.inSeconds == 0) {
          _dailyResetTimer?.cancel();
          _handleDailyReset();
        }
      }
    });
  }

  Future<void> _handleDailyReset() async {
    if (mounted)
      setState(() {
        _completedChallengesCache.clear();
        _dailyChallenges.clear();
        isLoading = true;
      });
    await _initializeData();
  }

  Future<void> _loadRandomDailyChallenges() async {
    if (mounted) setState(() => _loadingChallenges = true);
    try {
      final challengesSnap = await FirebaseFirestore.instance
          .collection('daily_challenges')
          .where('rango_requerido', isLessThanOrEqualTo: nivel)
          .get();
      final completedIds = _completedChallengesCache
          .map((c) => c['id_reto_completado']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final disponibles = challengesSnap.docs
          .where((doc) => !completedIds.contains(doc.id))
          .toList()
        ..shuffle();
      if (mounted) {
        setState(() {
          _dailyChallenges = disponibles.take(3).toList();
          _loadingChallenges = false;
        });
      }
    } catch (e) {
      debugPrint("Error desafíos: $e");
      if (mounted) setState(() => _loadingChallenges = false);
    }
  }

  Future<void> _finalizarActividad(
      String id, String titulo, int premio) async {
    if (userId == null) return;
    final ahora = DateTime.now();
    final String fechaId =
        "${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}";
    setState(() {
      _completedChallengesCache.insert(0, {
        'titulo': titulo,
        'recompensa': premio,
        'id_reto_completado': id,
        'fecha_dia': fechaId,
        'timestamp': Timestamp.now(),
      });
      _dailyChallenges.removeWhere((doc) => doc.id == id);
      monedas += premio;
    });
    try {
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': userId,
        'id_reto_completado': id,
        'titulo': titulo,
        'recompensa': premio,
        'timestamp': FieldValue.serverTimestamp(),
        'fecha_dia': fechaId,
      });
      await FirebaseFirestore.instance
          .collection('players')
          .doc(userId)
          .update({'monedas': monedas, 'nivel': (monedas ~/ 30) + 1});
    } catch (e) {
      debugPrint("Error al guardar: $e");
    }
  }

  Future<String?> _puedeRobarTerritorio({
    required String ownerIdObjetivo,
    required String territorioDocId,
  }) async {
    if (nivel < 2) {
      return 'Necesitas al menos nivel 2 para conquistar territorios.\nActualmente eres nivel $nivel.';
    }

    try {
      final terDoc = await FirebaseFirestore.instance
          .collection('territories')
          .doc(territorioDocId)
          .get();
      if (terDoc.exists) {
        final data = terDoc.data()!;
        final tsVisita = data['ultima_visita'] as Timestamp?;
        if (tsVisita != null) {
          final diasSinVisitar =
              DateTime.now().difference(tsVisita.toDate()).inDays;
          if (diasSinVisitar < 5) {
            return 'Este territorio está protegido.\nEl dueño lo visitó hace $diasSinVisitar día${diasSinVisitar == 1 ? '' : 's'}. Necesitas 5+ días sin visitar.';
          }
        } else {
          return 'Este territorio está activo y protegido.\nVuelve cuando lleve 5+ días sin ser visitado.';
        }
      }
    } catch (e) {
      debugPrint('Error comprobando territorio: $e');
    }

    try {
      final misTerritoriosSnap = await FirebaseFirestore.instance
          .collection('territories')
          .where('userId', isEqualTo: userId)
          .get();
      final territoriosDefensorSnap = await FirebaseFirestore.instance
          .collection('territories')
          .where('userId', isEqualTo: ownerIdObjetivo)
          .get();

      final misCantidad = misTerritoriosSnap.docs.length;
      final defensorCantidad = territoriosDefensorSnap.docs.length;

      if (defensorCantidad > 0 && misCantidad >= defensorCantidad * 3) {
        return 'Ya tienes demasiados territorios comparado con este jugador.\nNo puedes seguir conquistando hasta que el rival crezca.';
      }
    } catch (e) {
      debugPrint('Error comprobando balance de territorios: $e');
    }

    try {
      final ownerDoc = await FirebaseFirestore.instance
          .collection('players')
          .doc(ownerIdObjetivo)
          .get();

      if (ownerDoc.exists) {
        final escudoActivo =
            ownerDoc.data()?['escudo_activo'] as bool? ?? false;
        final escudoExpiraTs =
            ownerDoc.data()?['escudo_expira'] as Timestamp?;

        if (escudoActivo &&
            escudoExpiraTs != null &&
            escudoExpiraTs.toDate().isAfter(DateTime.now())) {
          final duracion =
              escudoExpiraTs.toDate().difference(DateTime.now());
          final horas = duracion.inHours;
          final minutos = duracion.inMinutes.remainder(60);
          final tiempoRestante =
              horas > 0 ? '${horas}h ${minutos}m' : '${minutos}m';
          return '🛡️ Este territorio tiene un escudo activo.\nNo puede ser conquistado durante $tiempoRestante más.';
        }
      }
    } catch (e) {
      debugPrint('Error comprobando escudo: $e');
    }

    return null;
  }

  Future<void> _testSimularConquista() async {
    if (userId == null) return;
    final friendshipsSnap = await FirebaseFirestore.instance
        .collection('friendships')
        .where('status', isEqualTo: 'accepted')
        .get();
    final List<String> amigoIds = [];
    for (var doc in friendshipsSnap.docs) {
      final data = doc.data();
      if (data['senderId'] == userId)
        amigoIds.add(data['receiverId'] as String);
      else if (data['receiverId'] == userId)
        amigoIds.add(data['senderId'] as String);
    }
    if (amigoIds.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No tienes amigos con territorios para conquistar'),
            backgroundColor: Colors.redAccent));
      return;
    }
    QueryDocumentSnapshot? territorioObjetivo;
    String? ownerIdObjetivo;
    String ownerNicknameObjetivo = 'rival';
    for (final amigoId in amigoIds) {
      final snap = await FirebaseFirestore.instance
          .collection('territories')
          .where('userId', isEqualTo: amigoId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        territorioObjetivo = snap.docs.first;
        ownerIdObjetivo = amigoId;
        try {
          final p = await FirebaseFirestore.instance
              .collection('players')
              .doc(amigoId)
              .get();
          if (p.exists)
            ownerNicknameObjetivo = p.data()?['nickname'] ?? 'rival';
        } catch (_) {}
        break;
      }
    }
    if (territorioObjetivo == null || ownerIdObjetivo == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tus amigos no tienen territorios aún'),
            backgroundColor: Colors.redAccent));
      return;
    }

    final motivoBloqueo = await _puedeRobarTerritorio(
      ownerIdObjetivo: ownerIdObjetivo,
      territorioDocId: territorioObjetivo.id,
    );

    if (motivoBloqueo != null) {
      if (mounted) {
        showDialog(
          context: context,
          barrierColor: Colors.black.withOpacity(0.88),
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 32),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _RR.bg1,
                border: Border.all(color: _accentColor.withOpacity(0.4)),
                boxShadow: [
                  BoxShadow(
                      color: _accentColor.withOpacity(0.12),
                      blurRadius: 24)
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🛡️', style: TextStyle(fontSize: 36)),
                  const SizedBox(height: 14),
                  const Text('CONQUISTA BLOQUEADA',
                      style: TextStyle(
                          color: _RR.ivory,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5)),
                  const SizedBox(height: 12),
                  Text(motivoBloqueo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _RR.t2, fontSize: 13, height: 1.6)),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: _RR.redd.withOpacity(0.15),
                        border: Border.all(
                            color: _accentColor.withOpacity(0.5)),
                      ),
                      child: Text('ENTENDIDO',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: _accentColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 2.5)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return;
    }

    final dataTerritorio =
        territorioObjetivo.data() as Map<String, dynamic>;
    final rawPuntos = dataTerritorio['puntos'] as List<dynamic>?;
    if (rawPuntos == null || rawPuntos.isEmpty) return;
    final List<LatLng> puntos = rawPuntos.map((p) {
      final map = p as Map<String, dynamic>;
      return LatLng(
          (map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
    }).toList();
    final double latCenter =
        puntos.map((p) => p.latitude).reduce((a, b) => a + b) / puntos.length;
    final double lngCenter =
        puntos.map((p) => p.longitude).reduce((a, b) => a + b) /
            puntos.length;

    await FirebaseFirestore.instance
        .collection('territories')
        .doc(territorioObjetivo.id)
        .update({'userId': userId});

    await FirebaseFirestore.instance.collection('notifications').add({
      'toUserId': ownerIdObjetivo,
      'type': 'territory_lost',
      'message':
          '😤 ¡$nickname te ha robado un territorio! Sal a recuperarlo.',
      'fromNickname': nickname,
      'territoryId': territorioObjetivo.id,
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('notifications').add({
      'toUserId': userId,
      'type': 'territory_conquered',
      'message':
          '🏴 ¡Has conquistado un territorio de $ownerNicknameObjetivo!',
      'fromNickname': ownerNicknameObjetivo,
      'territoryId': territorioObjetivo.id,
      'distancia': 2.5,
      'tiempo_segundos': 18 * 60,
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await LeagueService.sumarPuntosLiga(userId!, 25);
    await LeagueService.sumarPuntosLiga(ownerIdObjetivo, -10);

    if (!mounted) return;
    await ConquistaOverlay.mostrar(context,
        esInvasion: true, nombreTerritorio: ownerNicknameObjetivo);

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/resumen', arguments: {
      'distancia': 2.5,
      'tiempo': const Duration(minutes: 18),
      'ruta': [
        LatLng(latCenter - 0.002, lngCenter - 0.002),
        LatLng(latCenter, lngCenter),
        LatLng(latCenter + 0.002, lngCenter + 0.002)
      ],
      'esDesdeCarrera': true,
      'territoriosConquistados': 1,
    });
  }

  Future<void> _testSimularCarrera() async {
    if (!mounted) return;
    await ConquistaOverlay.mostrar(context);
    if (!mounted) return;
    final double offset =
        (DateTime.now().millisecondsSinceEpoch % 100) / 10000.0;
    Navigator.pushReplacementNamed(context, '/resumen', arguments: {
      'distancia': 3.7 + offset,
      'tiempo': const Duration(minutes: 25),
      'ruta': [
        LatLng(37.1358 + offset, -3.6340),
        LatLng(37.1368 + offset, -3.6315),
        LatLng(37.1350 + offset, -3.6305),
        LatLng(37.1335 + offset, -3.6325),
        LatLng(37.1340 + offset, -3.6348),
        LatLng(37.1358 + offset, -3.6340),
      ],
      'esDesdeCarrera': true,
    });
  }

  void _navegarAlPerfil(FeedPost post) {
    if (post.userId == userId) {
      Navigator.pushNamedAndRemoveUntil(
          context, '/perfil', ModalRoute.withName('/home'));
    } else {
      Navigator.push(context,
          MaterialPageRoute(
              builder: (_) => PerfilScreen(targetUserId: post.userId)));
    }
  }

  void _mostrarResumenCarrera(FeedPost post) {
    final color = post.userColor;
    String? tiempoStr;
    if (post.tiempo != null) {
      final h = post.tiempo!.inHours;
      final m = post.tiempo!.inMinutes.remainder(60);
      final s = post.tiempo!.inSeconds.remainder(60);
      tiempoStr = h > 0
          ? '${h}h ${m.toString().padLeft(2, '0')}m'
          : '${m}m ${s.toString().padLeft(2, '0')}s';
    }

    final ruta = post.ruta;
    LatLng? centro;
    if (ruta != null && ruta.isNotEmpty) {
      final latC =
          ruta.map((p) => p.latitude).reduce((a, b) => a + b) / ruta.length;
      final lngC =
          ruta.map((p) => p.longitude).reduce((a, b) => a + b) / ruta.length;
      centro = LatLng(latC, lngC);
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.90),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
        child: Container(
          decoration: BoxDecoration(
            color: _RR.bg1,
            border: Border.all(color: color.withOpacity(0.35)),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.15),
                  blurRadius: 36,
                  spreadRadius: 2)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
                child: Row(children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _navegarAlPerfil(post);
                    },
                    child: _buildAvatar(post, color, radius: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(post.userNickname.toUpperCase(),
                              style: const TextStyle(
                                  color: _RR.ivory,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 1.5)),
                          if (post.titulo != null)
                            Text(post.titulo!,
                                style: TextStyle(
                                    color: color.withOpacity(0.8),
                                    fontSize: 12)),
                          Text(_timeAgo(post.fecha),
                              style: const TextStyle(
                                  color: _RR.parchd, fontSize: 11)),
                        ]),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded,
                        color: _RR.parchd, size: 20),
                  ),
                ]),
              ),
              // Stats
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 16, horizontal: 8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.06),
                    border: Border.all(color: color.withOpacity(0.2)),
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (post.distanciaKm != null)
                          _popupStat(
                              value: post.distanciaKm!.toStringAsFixed(2),
                              unit: 'KM',
                              color: color,
                              big: true),
                        if (tiempoStr != null)
                          _popupStat(
                              value: tiempoStr,
                              unit: 'TIEMPO',
                              color: _RR.parchm),
                        if (post.velocidadMedia != null)
                          _popupStat(
                              value: post.velocidadMedia!.toStringAsFixed(1),
                              unit: 'KM/H',
                              color: _RR.bronze),
                      ]),
                ),
              ),
              const SizedBox(height: 12),
              if (centro != null && ruta != null && ruta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 200,
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: centro,
                        initialZoom: 14,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.pinchZoom |
                              InteractiveFlag.drag,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: _kMapboxTileUrl,
                          userAgentPackageName: 'com.runner_risk.app',
                          tileSize: 256,
                          additionalOptions: const {
                            'accessToken': _kMapboxToken
                          },
                        ),
                        PolylineLayer(polylines: [
                          Polyline(
                              points: ruta,
                              color: color,
                              strokeWidth: 4),
                        ]),
                        MarkerLayer(markers: [
                          Marker(
                            point: ruta.first,
                            width: 14,
                            height: 14,
                            child: Container(
                                decoration: BoxDecoration(
                                    color: _RR.safe,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2.5))),
                          ),
                          Marker(
                            point: ruta.last,
                            width: 14,
                            height: 14,
                            child: Container(
                                decoration: BoxDecoration(
                                    color: _accentColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2.5))),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              if (post.descripcion != null && post.descripcion!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _RR.bg0,
                      border: Border.all(color: _RR.border),
                    ),
                    child: Text(post.descripcion!,
                        style:
                            const TextStyle(color: _RR.t2, fontSize: 13)),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _popupStat(
      {required String value,
      required String unit,
      required Color color,
      bool big = false}) {
    return Expanded(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: big ? 28 : 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                shadows: [
                  Shadow(
                      color: color.withOpacity(0.4), blurRadius: 8)
                ])),
        const SizedBox(height: 2),
        Text(unit,
            style: const TextStyle(
                color: _RR.parchd,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 2)),
      ]),
    );
  }

  // =============================================================================
  // BUILD
  // =============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _RR.bg0,
      extendBodyBehindAppBar: false,
      appBar: _buildAppBar(),
      body: isLoading
          ? _buildLoadingState()
          : Column(children: [
              FadeTransition(
                  opacity: _headerFade, child: _buildStoriesHeader()),
              FadeTransition(
                  opacity: _contentFade, child: _buildTabBar()),
              Expanded(
                child: FadeTransition(
                    opacity: _contentFade, child: _buildTabContent()),
              ),
            ]),
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 0),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            border: Border.all(color: _RR.parchd.withOpacity(0.4), width: 1.5),
          ),
          child: CircularProgressIndicator(
              color: _accentColor, strokeWidth: 1.5),
        ),
        const SizedBox(height: 18),
        const Text('INICIANDO',
            style: TextStyle(
                color: _RR.parchd,
                fontSize: 10,
                letterSpacing: 4,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // =============================================================================
  // APP BAR — Parch Dark
  // =============================================================================
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _RR.bg0,
      elevation: 0,
      titleSpacing: 16,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Color(0x3FCAAA6C),
                Colors.transparent
              ],
            ),
          ),
        ),
      ),
      title: Row(children: [
        // Avatar con borde dorado y punto de estado
        Stack(children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: _accentColor.withOpacity(0.25),
                    blurRadius: 10,
                    spreadRadius: 1)
              ],
            ),
            child: CircleAvatar(
              radius: 19,
              backgroundColor: _RR.bg2,
              child: ClipOval(
                child: fotoBase64 != null
                    ? Image.memory(base64Decode(fotoBase64!),
                        fit: BoxFit.cover, width: 38, height: 38)
                    : const Icon(Icons.person,
                        color: _RR.parchd, size: 18),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _RR.safe,
                shape: BoxShape.circle,
                border: Border.all(color: _RR.bg0, width: 1.5),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(nickname.toUpperCase(),
                style: const TextStyle(
                    color: _RR.parch,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                    height: 1)),
            const SizedBox(height: 4),
            Row(children: [
              // Badge nivel — estilo pergamino
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: _RR.parchd.withOpacity(0.12),
                    border: Border.all(
                        color: _RR.parchd.withOpacity(0.5), width: 1)),
                child: Text('NIV.$nivel',
                    style: const TextStyle(
                        color: _RR.parchm,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
              ),
              const SizedBox(width: 8),
              // Monedas
              Row(children: [
                const Text('⬡', style: TextStyle(fontSize: 10, color: _RR.parchm)),
                const SizedBox(width: 3),
                Text('$monedas',
                    style: const TextStyle(
                        color: _RR.parchm,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ]),
            ]),
          ],
        ),
      ]),
      actions: [
        // Notificaciones
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => const NotificationsScreen())),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Stack(children: [
              const Icon(Icons.notifications_outlined,
                  color: _RR.parchd, size: 22),
              if (_notifNoLeidas > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _accentColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: _accentColor.withOpacity(0.5),
                            blurRadius: 4)
                      ],
                    ),
                  ),
                ),
            ]),
          ),
        ),
        // Refresh
        GestureDetector(
          onTap: _initializeData,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: const Icon(Icons.refresh_rounded,
                color: _RR.parchd, size: 20),
          ),
        ),
        _buildUserMenu(),
        const SizedBox(width: 8),
      ],
    );
  }

  // =============================================================================
  // STORIES HEADER — Parch Dark (círculos con borde dorado/rojo)
  // =============================================================================
  Widget _buildStoriesHeader() {
    final stories = [
      {'label': 'Tú', 'isMe': true, 'hasStory': false},
      {'label': 'Carlos', 'isMe': false, 'hasStory': true},
      {'label': 'María', 'isMe': false, 'hasStory': true},
      {'label': 'RunnerX', 'isMe': false, 'hasStory': true},
      {'label': 'Javi', 'isMe': false, 'hasStory': true},
      {'label': 'Ana', 'isMe': false, 'hasStory': false},
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      // Línea ornamental inferior
      decoration: const BoxDecoration(
        color: _RR.bg0,
        border: Border(
          bottom: BorderSide(color: Color(0x1FCAAA6C), width: 1),
        ),
      ),
      child: SizedBox(
        height: 82,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: stories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final s = stories[i];
            final isMe = s['isMe'] as bool;
            final hasStory = s['hasStory'] as bool;
            // "en vivo" = Carlos (index 1)
            final isLive = i == 1;

            return GestureDetector(
              onTap: () {},
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (context, child) {
                      final borderColor = isLive
                          ? _accentColor.withOpacity(_pulseAnim.value)
                          : hasStory
                              ? _RR.parchm.withOpacity(0.7)
                              : _RR.border;
                      return Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: borderColor,
                              width: isMe || isLive ? 2 : 1.5),
                          boxShadow: (hasStory || isLive)
                              ? [
                                  BoxShadow(
                                      color: (isLive
                                              ? _accentColor
                                              : _RR.parchm)
                                          .withOpacity(
                                              0.18 * _pulseAnim.value),
                                      blurRadius: 8)
                                ]
                              : null,
                        ),
                        padding: const EdgeInsets.all(2.5),
                        child: child,
                      );
                    },
                    child: Container(
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: _RR.bg2),
                      child: isMe && fotoBase64 != null
                          ? ClipOval(
                              child: Image.memory(
                                  base64Decode(fotoBase64!),
                                  fit: BoxFit.cover))
                          : isMe
                              ? Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    const Icon(Icons.person,
                                        color: _RR.parchd, size: 24),
                                    Positioned(
                                      bottom: 5,
                                      right: 5,
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                            color: _accentColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: _RR.bg0, width: 1.5)),
                                        child: const Icon(Icons.add,
                                            color: Colors.white,
                                            size: 9),
                                      ),
                                    ),
                                  ],
                                )
                              : Center(
                                  child: Text(
                                    (s['label'] as String)[0].toUpperCase(),
                                    style: TextStyle(
                                        color: isLive
                                            ? _accentColor
                                            : _RR.parch,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 19),
                                  ),
                                ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    s['label'] as String,
                    style: TextStyle(
                        color: isMe
                            ? _RR.parchm
                            : isLive
                                ? _accentColor
                                : _RR.parchd,
                        fontSize: 9,
                        fontWeight: isMe ? FontWeight.w800 : FontWeight.w500,
                        letterSpacing: 0.5),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // =============================================================================
  // TAB BAR — Parch Dark (estilo pestañas rectangulares)
  // =============================================================================
  Widget _buildTabBar() {
    final tabs = [
      {'id': 'feed', 'label': 'FEED', 'icon': Icons.dynamic_feed_rounded},
      {'id': 'mapa', 'label': 'MAPA', 'icon': Icons.map_rounded},
      {'id': 'retos', 'label': 'RETOS', 'icon': Icons.bolt_rounded},
      {'id': 'grabar', 'label': '● CORRER', 'icon': Icons.fiber_manual_record},
    ];

    return Container(
      decoration: const BoxDecoration(
        color: _RR.bg1,
        border: Border(
          bottom: BorderSide(color: Color(0x1FCAAA6C), width: 1),
        ),
      ),
      child: Row(
        children: tabs.map((tab) {
          final isActive = _tabActiva == tab['id'];
          final isGrabar = tab['id'] == 'grabar';

          return Expanded(
            child: GestureDetector(
              onTap: () {
                final id = tab['id'] as String;
                if (id == 'grabar') {
                  CustomBottomNavbar.abrirCrearPost(context);
                } else {
                  setState(() => _tabActiva = id);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive && !isGrabar
                      ? _RR.parchd.withOpacity(0.08)
                      : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: isActive && !isGrabar
                          ? _accentColor
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tab['label'] as String,
                          style: TextStyle(
                              color: isGrabar
                                  ? _accentColor
                                  : isActive
                                      ? _RR.parch
                                      : _RR.parchd,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5),
                        ),
                        if (tab['id'] == 'retos' &&
                            _dailyChallenges.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(left: 5),
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? _RR.parchd.withOpacity(0.3)
                                  : _accentColor,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                  '${_dailyChallenges.length}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabActiva) {
      case 'feed':
        return _buildFeedTab();
      case 'mapa':
        return _buildMapaTab();
      case 'retos':
        return _buildRetosTab();
      default:
        return _buildFeedTab();
    }
  }

  // =============================================================================
  // TAB: FEED
  // =============================================================================
  Widget _buildFeedTab() {
    debugPrint("🔥 Feed state: loading=$_loadingFeed, posts=${_feedPosts.length}, userId=$userId");

    if (_loadingFeed) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: _RR.parchd.withOpacity(0.25), width: 1),
            ),
            child: CircularProgressIndicator(
                color: _accentColor, strokeWidth: 1.5),
          ),
          const SizedBox(height: 16),
          const Text('CARGANDO FEED',
              style: TextStyle(
                  color: _RR.parchd,
                  fontSize: 10,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700)),
        ]),
      );
    }
    if (_feedPosts.isEmpty) return _buildFeedEmptyState();
    return RefreshIndicator(
      onRefresh: () async => _escucharFeed(),
      color: _accentColor,
      backgroundColor: _RR.bg2,
      strokeWidth: 1.5,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 120),
        itemCount: _feedPosts.length,
        itemBuilder: (context, index) =>
            _buildPostCard(_feedPosts[index], index),
      ),
    );
  }

  Widget _buildFeedEmptyState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.05),
              border: Border.all(
                  color: _accentColor.withOpacity(0.25), width: 1.5)),
          child: Icon(Icons.directions_run_rounded,
              color: _accentColor, size: 36),
        ),
        const SizedBox(height: 18),
        const Text('SIN ACTIVIDAD',
            style: TextStyle(
                color: _RR.parch,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 4)),
        const SizedBox(height: 8),
        const Text(
            'Sé el primero en compartir\ntu carrera con la comunidad',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _RR.parchd, fontSize: 13, height: 1.5)),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: _testSimularCarrera,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
            decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.12),
                border: Border.all(
                    color: _accentColor.withOpacity(0.5), width: 1)),
            child: Text('INICIAR CARRERA',
                style: TextStyle(
                    color: _accentColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 2.5)),
          ),
        ),
      ]),
    );
  }

  // =============================================================================
  // POST CARD — Parch Dark
  // =============================================================================
  Widget _buildPostCard(FeedPost post, int index) {
    final color = post.userColor;
    final isRun = post.tipo == 'run' || post.tipo == 'territorio';

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          decoration: BoxDecoration(
            color: _RR.bg1,
            border: Border.all(color: _RR.border, width: 1),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 3)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Cabecera
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
              child: Row(children: [
                GestureDetector(
                  onTap: () => _navegarAlPerfil(post),
                  child: _buildAvatar(post, color, radius: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _navegarAlPerfil(post),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(post.userNickname.toUpperCase(),
                                style: const TextStyle(
                                    color: _RR.ivory,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    letterSpacing: 1.5)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                  color: _RR.parchd.withOpacity(0.1),
                                  border: Border.all(
                                      color: _RR.parchd.withOpacity(0.3),
                                      width: 1)),
                              child: Text('NIV.${post.userNivel}',
                                  style: const TextStyle(
                                      color: _RR.parchm,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5)),
                            ),
                          ]),
                          const SizedBox(height: 2),
                          Text(_timeAgo(post.fecha),
                              style: const TextStyle(
                                  color: _RR.parchd, fontSize: 11)),
                        ]),
                  ),
                ),
                // Badge tipo
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: _RR.parchd.withOpacity(0.08),
                      border: Border.all(
                          color: _RR.parchd.withOpacity(0.25), width: 1)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_iconForTipo(post.tipo), color: _RR.parchm, size: 11),
                    const SizedBox(width: 4),
                    Text(_labelForTipo(post.tipo),
                        style: const TextStyle(
                            color: _RR.parchm,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1)),
                  ]),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {},
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.more_horiz, color: _RR.parchd, size: 18),
                  ),
                ),
              ]),
            ),
            // ── Título / descripción
            if (post.titulo != null || post.descripcion != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (post.titulo != null)
                        Text(post.titulo!,
                            style: const TextStyle(
                                color: _RR.ivory,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                height: 1.3,
                                letterSpacing: 0.5)),
                      if (post.descripcion != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(post.descripcion!,
                              style: const TextStyle(
                                  color: _RR.t2,
                                  fontSize: 13,
                                  height: 1.4)),
                        ),
                    ]),
              ),
            // ── Stats de carrera
            if (isRun &&
                (post.distanciaKm != null ||
                    post.velocidadMedia != null ||
                    post.tiempo != null))
              _buildRunStatsBar(post, color),
            // ── Media o mapa
            if (post.mediaBase64 != null)
              _buildMediaImage(post)
            else if (isRun && post.ruta != null && post.ruta!.isNotEmpty)
              _buildRouteMap(post, color)
            else
              const SizedBox(height: 4),
            // ── Acciones
            _buildPostActions(post, color),
          ]),
        ),
        // Barra lateral de acento (color del post)
        Positioned(
          left: 12,
          top: 0,
          bottom: 0,
          child: Container(
            width: 3,
            color: color.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(FeedPost post, Color color, {double radius = 18}) {
    return Container(
      width: radius * 2 + 4,
      height: radius * 2 + 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.55), width: 1.5),
      ),
      child: ClipOval(
        child: post.userAvatarBase64 != null
            ? Image.memory(base64Decode(post.userAvatarBase64!),
                fit: BoxFit.cover,
                width: radius * 2,
                height: radius * 2)
            : Container(
                color: color.withOpacity(0.08),
                child: Center(
                  child: Text(
                      post.userNickname.isNotEmpty
                          ? post.userNickname[0].toUpperCase()
                          : 'R',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontSize: radius * 0.9)),
                ),
              ),
      ),
    );
  }

  Widget _buildRunStatsBar(FeedPost post, Color color) {
    String? tiempoStr;
    if (post.tiempo != null) {
      final h = post.tiempo!.inHours;
      final m = post.tiempo!.inMinutes.remainder(60);
      final s = post.tiempo!.inSeconds.remainder(60);
      tiempoStr = h > 0
          ? '${h}h ${m.toString().padLeft(2, '0')}m'
          : '${m}m ${s.toString().padLeft(2, '0')}s';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      decoration: BoxDecoration(
        color: _RR.bg0,
        border: Border.all(color: _RR.borderHot),
      ),
      child: Row(children: [
        if (post.distanciaKm != null)
          _statItem(
              value: post.distanciaKm!.toStringAsFixed(2),
              unit: 'KM',
              color: color,
              big: true),
        if (post.distanciaKm != null && tiempoStr != null) _statDivider(),
        if (tiempoStr != null)
          _statItem(value: tiempoStr, unit: 'TIEMPO', color: _RR.parchm),
        if (tiempoStr != null && post.velocidadMedia != null) _statDivider(),
        if (post.velocidadMedia != null)
          _statItem(
              value: post.velocidadMedia!.toStringAsFixed(1),
              unit: 'KM/H',
              color: _RR.bronze),
      ]),
    );
  }

  Widget _statItem(
      {required String value,
      required String unit,
      required Color color,
      bool big = false}) {
    return Expanded(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: big ? 26 : 21,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                shadows: [
                  Shadow(color: color.withOpacity(0.3), blurRadius: 6)
                ])),
        const SizedBox(height: 2),
        Text(unit,
            style: const TextStyle(
                color: _RR.parchd,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 2)),
      ]),
    );
  }

  Widget _statDivider() =>
      Container(width: 1, height: 32, color: _RR.border);

  Widget _buildMediaImage(FeedPost post) {
    return Container(
      height: 280,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _RR.bg0,
      ),
      child:
          Image.memory(base64Decode(post.mediaBase64!), fit: BoxFit.cover),
    );
  }

  Widget _buildRouteMap(FeedPost post, Color color) {
    final ruta = post.ruta!;
    final latC =
        ruta.map((p) => p.latitude).reduce((a, b) => a + b) / ruta.length;
    final lngC =
        ruta.map((p) => p.longitude).reduce((a, b) => a + b) / ruta.length;
    return Container(
      height: 200,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Stack(children: [
        FlutterMap(
          options: MapOptions(
              initialCenter: LatLng(latC, lngC),
              initialZoom: 14,
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none)),
          children: [
            TileLayer(
              urlTemplate: _kMapboxTileUrl,
              userAgentPackageName: 'com.runner_risk.app',
              tileSize: 256,
              additionalOptions: const {'accessToken': _kMapboxToken},
            ),
            PolylineLayer(polylines: [
              Polyline(
                  points: ruta,
                  color: color,
                  strokeWidth: 3,
                  gradientColors: [color.withOpacity(0.5), color])
            ]),
            MarkerLayer(markers: [
              Marker(
                  point: ruta.first,
                  width: 12,
                  height: 12,
                  child: Container(
                      decoration: BoxDecoration(
                          color: _RR.safe,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white, width: 2)))),
              Marker(
                  point: ruta.last,
                  width: 12,
                  height: 12,
                  child: Container(
                      decoration: BoxDecoration(
                          color: _accentColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white, width: 2)))),
            ]),
          ],
        ),
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _mostrarResumenCarrera(post),
            child: Container(
              color: Colors.transparent,
              child: Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: _RR.bg0.withOpacity(0.85),
                    border: Border.all(
                        color: _RR.parchd.withOpacity(0.4), width: 1),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.bar_chart_rounded,
                        color: _RR.parchm, size: 11),
                    const SizedBox(width: 4),
                    const Text('VER STATS',
                        style: TextStyle(
                            color: _RR.parchm,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Acciones del post
  Widget _buildPostActions(FeedPost post, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x0FCAAA6C), width: 1)),
      ),
      child: Row(children: [
        _actionBtn(
          icon: post.likedByMe
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          label: post.likes > 0 ? '${post.likes}' : null,
          color: post.likedByMe ? _accentColor : _RR.parchd,
          active: post.likedByMe,
          activeColor: _accentColor,
          onTap: () => _toggleLike(post),
        ),
        const SizedBox(width: 4),
        _actionBtn(
          icon: Icons.chat_bubble_outline_rounded,
          label: post.comentarios > 0 ? '${post.comentarios}' : null,
          color: _RR.parchd,
          onTap: () => _mostrarComentariosSheet(post),
        ),
        const SizedBox(width: 4),
        _actionBtn(
          icon: Icons.share_outlined,
          color: _RR.parchd,
          onTap: () {},
        ),
        const Spacer(),
        if (post.ruta != null && post.ruta!.isNotEmpty)
          _actionBtn(
            icon: Icons.route_outlined,
            color: _RR.parchm,
            onTap: () => _guardarRuta(post),
          ),
        const SizedBox(width: 4),
        _actionBtn(
          icon: post.savedByMe
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          color: post.savedByMe ? _RR.parchm : _RR.parchd,
          active: post.savedByMe,
          activeColor: _RR.parchm,
          onTap: () => _toggleSave(post),
        ),
      ]),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    String? label,
    required Color color,
    bool active = false,
    Color activeColor = _RR.bronze,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: active
            ? BoxDecoration(
                color: activeColor.withOpacity(0.08),
              )
            : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 20),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ]),
      ),
    );
  }

  void _mostrarComentariosSheet(FeedPost post) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _RR.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(0))),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Column(children: [
          // Handle
          Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 32,
              height: 3,
              color: _RR.border),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              const Text('COMENTARIOS',
                  style: TextStyle(
                      color: _RR.parch,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.5)),
              const Spacer(),
              GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const Icon(Icons.close_rounded,
                      color: _RR.parchd, size: 20)),
            ]),
          ),
          const Divider(color: Color(0x1FCAAA6C), height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .doc(post.id)
                  .collection('comments')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: CircularProgressIndicator(
                          color: _accentColor, strokeWidth: 1.5));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                      child: Text('Sin comentarios todavía',
                          style: TextStyle(
                              color: _RR.parchd, fontSize: 13)));
                }
                return ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) => _buildCommentRow(
                      docs[i].data() as Map<String, dynamic>),
                );
              },
            ),
          ),
          _buildCommentInput(post),
        ]),
      ),
    );
  }

  Widget _buildCommentRow(Map<String, dynamic> cd) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _RR.parchd.withOpacity(0.08),
              border: Border.all(
                  color: _RR.parchd.withOpacity(0.3), width: 1)),
          child: Center(
            child: Text(
                (cd['nickname'] as String? ?? 'R')[0].toUpperCase(),
                style: const TextStyle(
                    color: _RR.parchm,
                    fontWeight: FontWeight.w900,
                    fontSize: 13)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cd['nickname'] ?? 'Runner',
                    style: const TextStyle(
                        color: _RR.parch,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(cd['texto'] ?? '',
                    style:
                        const TextStyle(color: _RR.t2, fontSize: 13)),
              ]),
        ),
      ]),
    );
  }

  Widget _buildCommentInput(FeedPost post) {
    final ctrl = TextEditingController();
    return Container(
      padding: EdgeInsets.only(
          left: 14,
          right: 14,
          top: 10,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14),
      decoration: const BoxDecoration(
          color: _RR.bg2,
          border: Border(
              top: BorderSide(color: Color(0x1FCAAA6C), width: 1))),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _RR.parchd.withOpacity(0.4))),
          child: ClipOval(
            child: fotoBase64 != null
                ? Image.memory(base64Decode(fotoBase64!),
                    fit: BoxFit.cover)
                : Icon(Icons.person, color: _accentColor, size: 16),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: ctrl,
            style: const TextStyle(color: _RR.ivory, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Añadir comentario...',
              hintStyle: const TextStyle(color: _RR.parchd, fontSize: 13),
              filled: true,
              fillColor: _RR.bg1,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: const BorderSide(
                      color: Color(0x1FCAAA6C), width: 1)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: const BorderSide(
                      color: Color(0x1FCAAA6C), width: 1)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () async {
            final texto = ctrl.text.trim();
            if (texto.isEmpty || userId == null) return;
            await FirebaseFirestore.instance
                .collection('posts')
                .doc(post.id)
                .collection('comments')
                .add({
              'userId': userId,
              'nickname': nickname,
              'texto': texto,
              'timestamp': FieldValue.serverTimestamp(),
            });
            await FirebaseFirestore.instance
                .collection('posts')
                .doc(post.id)
                .update({'comentariosCount': FieldValue.increment(1)});
            ctrl.clear();
          },
          child: Container(
            width: 36,
            height: 36,
            color: _accentColor,
            child: const Icon(Icons.send_rounded,
                color: Colors.white, size: 16),
          ),
        ),
      ]),
    );
  }

  // =============================================================================
  // TAB: MAPA
  // =============================================================================
  Widget _buildMapaTab() {
    return RefreshIndicator(
      onRefresh: _initializeData,
      color: _accentColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildTestButton(),
          const SizedBox(height: 8),
          _buildTestConquistaButton(),
          const SizedBox(height: 24),
          _buildSectionHeader(
              'ESTADO DE GUERRA',
              Icons.map_rounded,
              'VER TODO',
              () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => FullscreenMapScreen(
                          territorios: _territorios,
                          colorTerritorio: _accentColor,
                          centroInicial: _currentPosition != null
                              ? LatLng(_currentPosition!.latitude,
                                  _currentPosition!.longitude)
                              : const LatLng(37.1350, -3.6330))))),
          const SizedBox(height: 14),
          _buildMapaEnVivo(),
        ]),
      ),
    );
  }

  // =============================================================================
  // TAB: RETOS
  // =============================================================================
  Widget _buildRetosTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionHeader(
            'LOGROS DE HOY',
            Icons.emoji_events_outlined,
            _completedChallengesCache.length > 3
                ? (_mostrarTodosLosLogros
                    ? 'VER MENOS'
                    : 'VER TODOS (${_completedChallengesCache.length})')
                : '',
            () => setState(
                () => _mostrarTodosLosLogros = !_mostrarTodosLosLogros)),
        const SizedBox(height: 14),
        _buildCompletedChallengesList(),
        const SizedBox(height: 28),
        _buildSectionHeader(
            'MISIONES DEL DÍA', Icons.bolt_outlined, '', null),
        const SizedBox(height: 8),
        _buildDailyResetTimer(),
        const SizedBox(height: 14),
        _buildDailyChallengesList(),
      ]),
    );
  }

  // =============================================================================
  // MAPA EN VIVO
  // =============================================================================
  Widget _buildMapaEnVivo() {
    final LatLng centro = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(37.1350, -3.6330);

    final miosTotales = _territorios.where((t) => t.esMio).length;
    final deteriorados =
        _territorios.where((t) => t.esMio && t.estaDeterirado).length;
    final enPeligro =
        _territorios.where((t) => t.esMio && t.esConquistableSinPasar).length;

    return Column(children: [
      GestureDetector(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => FullscreenMapScreen(
                    territorios: _territorios,
                    colorTerritorio: _accentColor,
                    centroInicial: centro))),
        child: Container(
          height: 220,
          decoration: BoxDecoration(
              border: Border.all(color: _RR.border)),
          clipBehavior: Clip.antiAlias,
          child: _loadingTerritorios
              ? Container(
                  color: _RR.bg1,
                  child: Center(
                      child: CircularProgressIndicator(
                          color: _accentColor, strokeWidth: 1.5)))
              : Stack(children: [
                  FlutterMap(
                    mapController: _homeMapController,
                    options: MapOptions(
                        initialCenter: centro,
                        initialZoom: 14,
                        interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none)),
                    children: [
                      TileLayer(
                        urlTemplate: _kMapboxTileUrl,
                        userAgentPackageName: 'com.runner_risk.app',
                        tileSize: 256,
                        additionalOptions: const {
                          'accessToken': _kMapboxToken
                        },
                      ),
                      if (_territorios.isNotEmpty)
                        PolygonLayer(
                            polygons: _territorios
                                .map((t) => Polygon(
                                    points: t.puntos,
                                    color: t.color
                                        .withOpacity(t.opacidadRelleno),
                                    borderColor: t.color
                                        .withOpacity(t.opacidadBorde),
                                    borderStrokeWidth:
                                        t.estaDeterirado ? 1.5 : 2))
                                .toList()),
                      if (_currentPosition != null)
                        MarkerLayer(markers: [
                          Marker(
                            point: LatLng(_currentPosition!.latitude,
                                _currentPosition!.longitude),
                            width: 14,
                            height: 14,
                            child: Container(
                                decoration: BoxDecoration(
                                    color: _RR.parch,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                          color:
                                              _RR.parch.withOpacity(0.4),
                                          blurRadius: 6)
                                    ])),
                          ),
                        ]),
                    ],
                  ),
                  // Icono fullscreen
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      color: _RR.bg0.withOpacity(0.7),
                      child: const Icon(Icons.fullscreen,
                          color: _RR.parchm, size: 15),
                    ),
                  ),
                  // Label coordenadas
                  Positioned(
                    bottom: 8,
                    left: 10,
                    child: Text(
                      'GRANADA · 37.18°N',
                      style: const TextStyle(
                          color: _RR.parchd,
                          fontSize: 8,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        _buildTerritoryStatChip(
            '$miosTotales', 'ZONAS', Icons.flag_rounded, _RR.parchm),
        const SizedBox(width: 8),
        if (deteriorados > 0)
          _buildTerritoryStatChip('$deteriorados', 'DESGASTE',
              Icons.warning_amber_rounded, _RR.warn),
        if (deteriorados > 0 && enPeligro > 0) const SizedBox(width: 8),
        if (enPeligro > 0)
          _buildTerritoryStatChip('$enPeligro', 'CRÍTICO',
              Icons.dangerous_rounded, _accentColor),
      ]),
      const SizedBox(height: 10),
      _buildBotonTerritoriosCercanos(),
      if (_panelCercanosExpandido) _buildPanelCercanos(),
      if (deteriorados > 0 || enPeligro > 0)
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.05),
              border:
                  Border.all(color: _accentColor.withOpacity(0.3))),
          child: Row(children: [
            Icon(Icons.shield_outlined, color: _accentColor, size: 14),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
              enPeligro > 0
                  ? '⚔ Tienes $enPeligro ${enPeligro == 1 ? 'territorio' : 'territorios'} que cualquiera puede conquistar.'
                  : '⚠ $deteriorados ${deteriorados == 1 ? 'territorio debilitado' : 'territorios debilitados'}. Visítalos antes de perderlos.',
              style: TextStyle(
                  color: _accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3),
            )),
          ]),
        ),
    ]);
  }

  Widget _buildBotonTerritoriosCercanos() {
    return GestureDetector(
      onTap: () {
        if (_panelCercanosExpandido) {
          setState(() {
            _panelCercanosExpandido = false;
            _userExpandido = null;
          });
        } else {
          _cargarTerritoriosCercanos();
        }
      },
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
            color: _RR.bg1,
            border: Border.all(color: _RR.border)),
        child: Row(children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                  color: _RR.safe.withOpacity(
                      0.5 + 0.5 * _pulseAnim.value),
                  shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          _loadingCercanos
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: _accentColor, strokeWidth: 1.5))
              : Text(
                  _panelCercanosExpandido
                      ? 'TERRITORIOS EN ZONA (5KM) ▲'
                      : 'TERRITORIOS EN ZONA (5KM) ▼',
                  style: const TextStyle(
                      color: _RR.parchd,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5)),
          const Spacer(),
          const Icon(Icons.people_alt_outlined,
              color: _RR.parchd, size: 13),
        ]),
      ),
    );
  }

  Widget _buildPanelCercanos() {
    if (_gruposTerritoriosCercanos.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _RR.bg1,
            border: Border.all(color: _RR.border)),
        child: const Text('No hay territorios en 5 km',
            style: TextStyle(color: _RR.parchd, fontSize: 12)));
    }
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
          color: _RR.bg1,
          border: Border.all(color: _RR.border)),
      child: Column(
        children:
            _gruposTerritoriosCercanos.asMap().entries.map((entry) {
          final index = entry.key;
          final grupo = entry.value;
          final isExpanded = _userExpandido == grupo.ownerId;
          final detalles = _detallesPorUser[grupo.ownerId];
          final isLast =
              index == _gruposTerritoriosCercanos.length - 1;
          return Column(children: [
            InkWell(
              onTap: () async {
                if (isExpanded) {
                  setState(() => _userExpandido = null);
                } else {
                  setState(() => _userExpandido = grupo.ownerId);
                  await _cargarDetallesUsuario(grupo.ownerId);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Row(children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: grupo.color,
                          shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          grupo.esMio
                              ? '${grupo.nickname.toUpperCase()} (TÚ)'
                              : grupo.nickname.toUpperCase(),
                          style: TextStyle(
                              color:
                                  grupo.esMio ? _RR.parch : _RR.ivory,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 1.5))),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: grupo.color.withOpacity(0.08),
                        border: Border.all(
                            color: grupo.color.withOpacity(0.3))),
                    child: Text('NIV.${grupo.nivel}',
                        style: TextStyle(
                            color: grupo.color,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5)),
                  ),
                  const SizedBox(width: 8),
                  Text('${grupo.territorios.length} 🏴',
                      style:
                          const TextStyle(color: _RR.parchd, fontSize: 11)),
                  const SizedBox(width: 6),
                  Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: _RR.parchd,
                      size: 18),
                ]),
              ),
            ),
            if (isExpanded)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _RR.bg0,
                    border: Border.all(
                        color: grupo.color.withOpacity(0.15))),
                child: detalles == null
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                                color: _accentColor, strokeWidth: 1.5)))
                    : detalles.isEmpty
                        ? const Text('Sin territorios',
                            style:
                                TextStyle(color: _RR.parchd, fontSize: 12))
                        : Column(
                            children: detalles
                                .asMap()
                                .entries
                                .map((e) => _buildTerritoryDetailCard(
                                    e.key,
                                    e.value,
                                    grupo.color,
                                    grupo.esMio ? 'YO' : grupo.nickname))
                                .toList()),
              ),
            if (!isLast)
              const Divider(
                  color: Color(0x1FCAAA6C), height: 1),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildTerritoryDetailCard(int index, _TerritoryDetail det,
      Color color, String ownerNickname) {
    String estadoDeterioro = 'ACTIVO';
    Color colorEstado = _RR.safe;
    if (det.diasSinVisitar != null && det.diasSinVisitar! >= 10) {
      estadoDeterioro = 'CRÍTICO';
      colorEstado = _accentColor;
    } else if (det.diasSinVisitar != null && det.diasSinVisitar! >= 5) {
      estadoDeterioro = 'DESGASTE';
      colorEstado = _RR.warn;
    }
    return GestureDetector(
      onTap: () => _mostrarDialogTerritorio(det, color, ownerNickname),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: color.withOpacity(0.04),
            border: Border.all(color: color.withOpacity(0.15))),
        child: Row(children: [
          Icon(Icons.crop_square_rounded, color: color, size: 12),
          const SizedBox(width: 8),
          Text('ZONA #${index + 1}',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.5)),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            color: colorEstado.withOpacity(0.08),
            child: Text(estadoDeterioro,
                style: TextStyle(
                    color: colorEstado,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
          ),
          const Spacer(),
          Text('${det.distanciaAlCentroKm.toStringAsFixed(1)}km',
              style: const TextStyle(color: _RR.parchd, fontSize: 10)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded,
              color: color.withOpacity(0.5), size: 13),
        ]),
      ),
    );
  }

  String _formatFecha(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

  String _timeAgo(DateTime fecha) {
    final diff = DateTime.now().difference(fecha);
    if (diff.inSeconds < 60) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    return _formatFecha(fecha);
  }

  IconData _iconForTipo(String tipo) {
    switch (tipo) {
      case 'video':
        return Icons.play_circle_outline_rounded;
      case 'foto':
        return Icons.image_outlined;
      case 'territorio':
        return Icons.flag_rounded;
      default:
        return Icons.directions_run_rounded;
    }
  }

  String _labelForTipo(String tipo) {
    switch (tipo) {
      case 'video':
        return 'VIDEO';
      case 'foto':
        return 'FOTO';
      case 'territorio':
        return 'ZONA';
      default:
        return 'CARRERA';
    }
  }

  Widget _buildTerritoryStatChip(
      String valor, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          border: Border.all(color: color.withOpacity(0.25))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 6),
        Text('$valor $label',
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
      ]),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, String action,
      VoidCallback? onAction) {
    return Row(children: [
      // Ornamento lateral dorado
      Container(
        width: 3,
        height: 14,
        color: _RR.parchm,
      ),
      const SizedBox(width: 10),
      Icon(icon, color: _RR.parchm, size: 13),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(
              color: _RR.parch,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5)),
      const Spacer(),
      if (action.isNotEmpty)
        GestureDetector(
          onTap: onAction,
          child: Text(action,
              style: TextStyle(
                  color: _accentColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
        ),
    ]);
  }

  Widget _buildDailyResetTimer() {
    final h = _timeUntilReset.inHours.toString().padLeft(2, '0');
    final m = _timeUntilReset.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final s = _timeUntilReset.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: _RR.bg1,
          border: Border.all(color: _RR.gold.withOpacity(0.2))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.timer_outlined, color: _RR.parchd, size: 12),
        const SizedBox(width: 6),
        Text('RESET EN $h:$m:$s',
            style: const TextStyle(
                color: _RR.gold,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
  }

  Widget _buildCompletedChallengesList() {
    if (_completedChallengesCache.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _RR.bg1,
            border: Border.all(color: _RR.border)),
        child: const Row(children: [
          Icon(Icons.hourglass_empty_rounded, color: _RR.parchd, size: 14),
          SizedBox(width: 10),
          Text('Ningún reto completado hoy todavía',
              style: TextStyle(color: _RR.parchd, fontSize: 13)),
        ]),
      );
    }
    final lista = _mostrarTodosLosLogros
        ? _completedChallengesCache
        : _completedChallengesCache.take(3).toList();
    return Column(
        children: lista
            .map((data) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                      color: _RR.bg1,
                      border: Border.all(
                          color: _RR.gold.withOpacity(0.2))),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: _RR.gold.withOpacity(0.08),
                      child: const Icon(Icons.emoji_events_rounded,
                          color: _RR.gold, size: 15),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(
                            data['titulo'] ?? 'Reto completado',
                            style: const TextStyle(
                                color: _RR.ivory, fontSize: 13))),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: _RR.parchd.withOpacity(0.1),
                          border: Border.all(
                              color: _RR.parchd.withOpacity(0.3))),
                      child: Text('+${data['recompensa']}',
                          style: const TextStyle(
                              color: _RR.parchm,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 0.5)),
                    ),
                  ]),
                ))
            .toList());
  }

  Widget _buildDailyChallengesList() {
    if (_loadingChallenges)
      return Center(
          child: CircularProgressIndicator(
              color: _accentColor, strokeWidth: 1.5));
    if (_dailyChallenges.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _RR.bg1,
            border: Border.all(color: _RR.safe.withOpacity(0.2))),
        child: const Row(children: [
          Icon(Icons.check_circle_outline_rounded,
              color: _RR.safe, size: 14),
          SizedBox(width: 10),
          Text('¡Todos los desafíos completados!',
              style: TextStyle(color: _RR.safe, fontSize: 13)),
        ]),
      );
    }
    return Column(children: _dailyChallenges.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return GestureDetector(
        onTap: () => _finalizarActividad(
            doc.id, data['titulo'], data['recompensas_monedas']),
        child: _buildMissionCard(data['titulo'], data['descripcion'],
            '${data['recompensas_monedas']}'),
      );
    }).toList());
  }

  Widget _buildMissionCard(String title, String desc, String reward) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: _RR.bg1,
          border: Border.all(color: _RR.border)),
      child: Stack(
        children: [
          // Barra lateral
          Positioned(
            left: 0, top: 0, bottom: 0,
            child: Container(width: 3, color: _RR.bronze.withOpacity(0.6)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                color: _RR.bronze.withOpacity(0.08),
                child: const Icon(Icons.bolt_rounded,
                    color: _RR.bronze, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: _RR.ivory,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.3)),
                  const SizedBox(height: 3),
                  Text(desc,
                      style:
                          const TextStyle(color: _RR.parchd, fontSize: 12)),
                ],
              )),
              const SizedBox(width: 10),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('+$reward',
                    style: const TextStyle(
                        color: _RR.bronze,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: 0.3)),
                const SizedBox(height: 1),
                const Text('PTS',
                    style: TextStyle(
                        color: _RR.parchd,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5)),
              ]),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: _RR.parchd, size: 16),
            ]),
          ),
        ],
      ),
    );
  }

  // =============================================================================
  // TEST BUTTONS
  // =============================================================================
  Widget _buildTestButton() {
    return GestureDetector(
      onTap: _testSimularCarrera,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
        decoration: BoxDecoration(
            color: _RR.parchd.withOpacity(0.06),
            border: Border.all(color: _RR.parchd.withOpacity(0.3))),
        child: Row(children: [
          const Text('🧪', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('TEST — Simular carrera y territorio',
                style: TextStyle(
                    color: _RR.parchm,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.5)),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: _RR.parchd, size: 16),
        ]),
      ),
    );
  }

  Widget _buildTestConquistaButton() {
    return GestureDetector(
      onTap: _testSimularConquista,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
        decoration: BoxDecoration(
            color: _accentColor.withOpacity(0.05),
            border: Border.all(color: _accentColor.withOpacity(0.3))),
        child: Row(children: [
          const Text('⚔️', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 12),
          Expanded(
            child: Text('TEST — Conquistar territorio de amigo',
                style: TextStyle(
                    color: _accentColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.5)),
          ),
          Icon(Icons.chevron_right_rounded,
              color: _accentColor, size: 16),
        ]),
      ),
    );
  }

  Widget _buildUserMenu() => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: _RR.parchd, size: 20),
        color: _RR.bg1,
        shape: const RoundedRectangleBorder(
            side: BorderSide(color: Color(0x1FCAAA6C))),
        onSelected: (value) async {
          if (value == 'logout') {
            try {
              await FirebaseAuth.instance.signOut();
              if (mounted)
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/login', (route) => false);
            } catch (e) {
              debugPrint("Error al cerrar sesión: $e");
            }
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
              value: 'logout',
              child: Row(children: [
                Icon(Icons.logout, color: _accentColor, size: 17),
                const SizedBox(width: 10),
                const Text('Cerrar sesión',
                    style: TextStyle(color: _RR.parchd, fontSize: 13)),
              ])),
        ],
      );
}

// =============================================================================
// MODELOS AUXILIARES  (sin cambios)
// =============================================================================
class _UserTerritoryGroup {
  final String ownerId;
  final String nickname;
  final int nivel;
  final Color color;
  final bool esMio;
  final List<_TerritoryDetail> territorios;

  _UserTerritoryGroup({
    required this.ownerId,
    required this.nickname,
    required this.nivel,
    required this.color,
    required this.esMio,
    required this.territorios,
  });
}

class _TerritoryDetail {
  final String docId;
  final double distanciaAlCentroKm;
  final int? diasSinVisitar;
  final DateTime? fechaCreacion;
  final double? distanciaRecorrida;
  final double? velocidadMedia;
  final Duration? tiempoActividad;
  final List<LatLng> puntos;

  _TerritoryDetail({
    required this.docId,
    required this.distanciaAlCentroKm,
    this.diasSinVisitar,
    this.fechaCreacion,
    this.distanciaRecorrida,
    this.velocidadMedia,
    this.tiempoActividad,
    this.puntos = const [],
  });
}