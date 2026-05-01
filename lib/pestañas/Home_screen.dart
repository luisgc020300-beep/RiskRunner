import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:RiskRunner/pesta%C3%B1as/create_post_screen.dart';
import 'package:RiskRunner/pesta%C3%B1as/paywall_screen.dart';
import 'package:RiskRunner/pesta%C3%B1as/settings_screen.dart';
import 'package:RiskRunner/services/league_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/custom_navbar.dart';
import '../services/territory_service.dart';
import '../services/subscription_service.dart';
import '../services/story_service.dart';
import 'coin_shop_screen.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_overlay.dart';
import 'notifications_screen.dart';
import 'perfil_screen.dart';
import 'package:RiskRunner/pesta%C3%B1as/story_viewer_screen.dart';
import '../widgets/conquista_overlay.dart';

// =============================================================================
// MAPBOX
// =============================================================================
const _kMapboxToken = 'pk.eyJ1IjoibHVpaXNnb29tZXp6MSIsImEiOiJjbW1mNDVoajkwNGNyMnBzNTBiaXNrMm5pIn0.gzN772_GMDx55owCXwsozA';
const _kMapboxTileUrl =
    'https://api.mapbox.com/styles/v1/luiisgoomezz1/cmmdzh1aj00f501r68crag5gv/tiles/256/{z}/{x}/{y}@2x?access_token=$_kMapboxToken';

// =============================================================================
// DESIGN TOKENS — Paleta dorada/pergamino
// Rojo SOLO para alertas e invasiones
// =============================================================================
// Paleta dinámica: se actualiza en cada build() según brightness
class _TColors {
  final Color bg0, bg1, bg2, bg3, bg4;
  final Color parch, gold, bronze, terra;
  final Color white, text, sub, dim, muted;
  final Color border, border2;
  final Color safe, warn, red, redD, redGlow;

  const _TColors._({
    required this.bg0, required this.bg1, required this.bg2,
    required this.bg3, required this.bg4,
    required this.parch, required this.gold, required this.bronze, required this.terra,
    required this.white, required this.text, required this.sub,
    required this.dim, required this.muted,
    required this.border, required this.border2,
    required this.safe, required this.warn,
    required this.red, required this.redD, required this.redGlow,
  });

  static const light = _TColors._(
    bg0: Color(0xFFE8E8ED), bg1: Color(0xFFFFFFFF), bg2: Color(0xFFE5E5EA),
    bg3: Color(0xFFE8E8ED), bg4: Color(0xFFFFFFFF),
    parch: Color(0xFF1C1C1E), gold: Color(0xFFFFD60A),
    bronze: Color(0xFF636366), terra: Color(0xFFAEAEB2),
    white: Color(0xFF1C1C1E), text: Color(0xFF3C3C43),
    sub: Color(0xFF636366), dim: Color(0xFF8E8E93), muted: Color(0xFFAEAEB2),
    border: Color(0xFFC6C6C8), border2: Color(0xFFD1D1D6),
    safe: Color(0xFF30D158), warn: Color(0xFFFF9800),
    red: Color(0xFFE02020), redD: Color(0xFFFF6B6B), redGlow: Color(0x22E02020),
  );

  static const dark = _TColors._(
    bg0: Color(0xFF090807), bg1: Color(0xFF1C1C1E), bg2: Color(0xFF2C2C2E),
    bg3: Color(0xFF090807), bg4: Color(0xFF1C1C1E),
    parch: Color(0xFFEAD9AA), gold: Color(0xFFFFD60A),
    bronze: Color(0xFF8E8E93), terra: Color(0xFF636366),
    white: Color(0xFFEEEEEE), text: Color(0xFFD1D1D6),
    sub: Color(0xFF8E8E93), dim: Color(0xFF636366), muted: Color(0xFF48484A),
    border: Color(0xFF38383A), border2: Color(0xFF2C2C2E),
    safe: Color(0xFF30D158), warn: Color(0xFFFF9800),
    red: Color(0xFFE02020), redD: Color(0xFFFF6B6B), redGlow: Color(0x22E02020),
  );

  static _TColors of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark ? dark : light;
}

TextStyle _raj(double size, FontWeight weight, Color color,
    {double spacing = 0, double? height}) =>
    GoogleFonts.inter(
      fontSize: size, fontWeight: weight, color: color,
      letterSpacing: spacing, height: height,
    );

// =============================================================================
// MODELO FEED POST
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
  });

  factory FeedPost.fromFirestore(DocumentSnapshot doc, String myUid) {
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

  // Paleta dinámica — se actualiza al inicio de cada build()
  _TColors _T = _TColors.light;

  // ── Perfil
  Position? _currentPosition;
  String nickname = "Cargando...";
  int monedas = 0;
  int nivel = 1;
  String? fotoBase64;
  bool isLoading = true;

  Color _accentColor = _TColors.light.bronze;

  // ── Amigos / Stories
  List<Map<String, dynamic>> _amigos = [];
  bool _amigosLoaded = false;
  bool _storiesLoaded = false;
  Map<String, List<StoryModel>> _storiesPorAmigo = {};
  List<StoryModel> _misHistorias = [];

  // ── Retos
  List<QueryDocumentSnapshot> _dailyChallenges = [];
  bool _loadingChallenges = true;
  List<Map<String, dynamic>> _completedChallengesCache = [];
  bool _mostrarTodosLosLogros = false;
  Timer? _dailyResetTimer;
  final _timeUntilReset = ValueNotifier<Duration>(Duration.zero);

  // ── Mapa
  bool _loadingTerritorios = true;
  StreamSubscription<QuerySnapshot>? _invasionListener;
  StreamSubscription<QuerySnapshot>? _presenciaListener;

  // ── Territorios cercanos
  final Map<String, List<_TerritoryDetail>> _detallesPorUser = {};

  // ── Notificaciones
  int _notifNoLeidas = 0;
  StreamSubscription<QuerySnapshot>? _notifCountListener;

  // ── Feed
  List<FeedPost> _feedPosts = [];
  bool _loadingFeed = true;
  StreamSubscription<QuerySnapshot>? _feedListener;
  // Cache de avatares actuales por userId (evita mostrar fotos desactualizadas)
  final Map<String, String?> _avatarCache = {};

  // ── Tab activa
  int _tabIndex = 0;
  late PageController _pageController;

  StreamSubscription<User?>? _authListener;

  // ── Animaciones
  late AnimationController _entradaCtrl;
  late AnimationController _loopCtrl;
  late AnimationController _scanCtrl;
  late Animation<double> _fadeA;
  late Animation<double> _fadeB;
  late Animation<Offset> _slideB;
  late Animation<double> _pulse;
  late Animation<double> _scan;

  @override
  void initState() {
    super.initState();

    _pageController = PageController(initialPage: 0);

    _entradaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _loopCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3500))
      ..repeat(reverse: true);
    _scanCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat();

    _fadeA = CurvedAnimation(
        parent: _entradaCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut));
    _fadeB = CurvedAnimation(
        parent: _entradaCtrl,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut));
    _slideB = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _entradaCtrl,
            curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic)));
    _pulse = CurvedAnimation(parent: _loopCtrl, curve: Curves.easeInOut);
    _scan  = CurvedAnimation(parent: _scanCtrl, curve: Curves.linear);

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
    _pageController.dispose();
    _dailyResetTimer?.cancel();
    _timeUntilReset.dispose();
    _entradaCtrl.dispose();
    _loopCtrl.dispose();
    _scanCtrl.dispose();
    _presenciaListener?.cancel();
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
      if (mounted && _loadingFeed) setState(() => _loadingFeed = false);
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
      final posts = snap.docs
          .map((doc) => FeedPost.fromFirestore(doc, uid))
          .toList();
      if (mounted) setState(() {
        _feedPosts = posts;
        _loadingFeed = false;
      });
      // Actualizar cache de avatares para los userIds nuevos
      final idsNuevos = posts.map((p) => p.userId).toSet()
          .difference(_avatarCache.keys.toSet());
      if (idsNuevos.isNotEmpty) _actualizarAvatarCache(idsNuevos);
    }, onError: (e) {
      if (mounted) setState(() => _loadingFeed = false);
    });
  }

  Future<void> _actualizarAvatarCache(Set<String> userIds) async {
    final ids = userIds.toList();
    // Firestore whereIn soporta hasta 30 elementos por query
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, (i + 30).clamp(0, ids.length));
      try {
        final snap = await FirebaseFirestore.instance
            .collection('usuarios')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        if (!mounted) return;
        final fetched = {for (final d in snap.docs) d.id: d.data()['foto_base64'] as String?};
        // Marcar como null los ids que no devolvió Firestore
        final missing = {for (final id in chunk) id: null as String?};
        setState(() => _avatarCache.addAll({...missing, ...fetched}));
      } catch (e) {
        debugPrint('Error cargando avatares batch: $e');
        for (final id in chunk) {
          _avatarCache[id] = null;
        }
      }
    }
  }

  Future<void> _toggleLike(FeedPost post) async {
    if (userId == null) return;
    final ref = FirebaseFirestore.instance.collection('posts').doc(post.id);
    try {
      if (post.likedByMe) {
        await ref.update({'likes': FieldValue.arrayRemove([userId])});
      } else {
        await ref.update({'likes': FieldValue.arrayUnion([userId])});
      }
    } catch (e) {
      debugPrint('Error toggleLike: $e');
      if (mounted) _snackError('No se pudo registrar el like');
    }
  }

  Future<void> _toggleSave(FeedPost post) async {
    if (userId == null) return;
    final ref = FirebaseFirestore.instance.collection('posts').doc(post.id);
    try {
      if (post.savedByMe) {
        await ref.update({'saved': FieldValue.arrayRemove([userId])});
      } else {
        await ref.update({'saved': FieldValue.arrayUnion([userId])});
      }
    } catch (e) {
      debugPrint('Error toggleSave: $e');
      if (mounted) _snackError('No se pudo guardar');
    }
  }

  void _snackError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      backgroundColor: _T.redD.withValues(alpha: 0.95),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Row(children: [
        Icon(Icons.wifi_off_rounded, color: _T.white, size: 16),
        const SizedBox(width: 10),
        Text(msg, style: _raj(12, FontWeight.w600, _T.white)),
      ]),
    ));
  }

  Future<void> _guardarRuta(FeedPost post) async {
    if (userId == null || post.ruta == null) return;
    try {
      final esPremium = SubscriptionService.currentStatus.isPremium;
      if (!esPremium) {
        final snap = await FirebaseFirestore.instance
            .collection('players')
            .doc(userId)
            .collection('saved_routes')
            .count()
            .get();
        final total = snap.count ?? 0;
        if (total >= 5) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.transparent,
              elevation: 0,
              content: GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  PaywallScreen.mostrar(context,
                      featureOrigen: 'Rutas guardadas ilimitadas');
                },
                child: _snackContainer(
                  border: _T.bronze,
                  child: Row(children: [
                    const Text('', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('LÍMITE ALCANZADO (5/5)', style: _raj(11, FontWeight.w800, _T.white, spacing: 1)),
                        const SizedBox(height: 2),
                        Text('Premium → rutas ilimitadas. Toca para activar.', style: _raj(10, FontWeight.w500, _T.sub)),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: _T.bronze),
                  ]),
                ),
              ),
            ),
          );
          return;
        }
      }

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: _snackContainer(
            border: _T.border2,
            child: Row(children: [
              Container(width: 5, height: 5,
                  decoration: BoxDecoration(color: _T.safe, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Text('RUTA GUARDADA', style: _raj(11, FontWeight.w900, _T.white, spacing: 2)),
            ]),
          ),
        ));
      }
    } catch (e) {
      debugPrint('Error guardando ruta: $e');
      if (mounted) _snackError('No se pudo guardar la ruta');
    }
  }

  Widget _snackContainer({required Color border, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _T.bg1,
        border: Border.all(color: border.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 16)],
      ),
      child: child,
    );
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
      await _loadAmigos();
      await _checkDailyReset();
      await _loadCompletedChallenges();
      await _loadRandomDailyChallenges();
      await _cargarTerritorios();
    } catch (e) {
      debugPrint("Error en inicialización: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        _entradaCtrl.forward();
      }
    }
  }

  Future<void> _loadAmigos() async {
    if (userId == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('friendships')
          .where('status', isEqualTo: 'accepted')
          .get();

      final misFriendships = snap.docs.where((doc) =>
          doc['senderId'] == userId || doc['receiverId'] == userId).toList();

      final futures = misFriendships.map((doc) {
        final friendId = doc['senderId'] == userId
            ? doc['receiverId'] as String
            : doc['senderId'] as String;
        return FirebaseFirestore.instance.collection('players').doc(friendId).get();
      }).toList();

      final playerDocs = await Future.wait(futures);
      final amigos = playerDocs
          .where((d) => d.exists)
          .map((d) => {...d.data()!, 'id': d.id})
          .toList();

      final amigoIds = amigos.map((a) => a['id'] as String).toList();
      final storiesPorAmigo = await StoryService.fetchActiveStoriesForUsers(
          amigoIds, defaultColor: _accentColor);
      final misHistorias = await StoryService.fetchMyActiveStories(
          defaultColor: _accentColor);

      if (mounted) {
        setState(() {
          _amigos = amigos;
          _amigosLoaded = true;
          _storiesPorAmigo = storiesPorAmigo;
          _misHistorias = misHistorias;
          _storiesLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _amigosLoaded = true; _storiesLoaded = true; });
      }
    }
  }

  Future<void> _cargarTerritorios() async {
    if (mounted) setState(() => _loadingTerritorios = true);
    try {
      final lista = await TerritoryService.cargarTodosLosTerritorios();
      if (mounted) {
        setState(() { _loadingTerritorios = false; });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingTerritorios = false);
    }
  }

  Widget _dialogStatCard({required IconData icon, required String title,
      required String value, required Color color, bool smallText = false}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.04),
          border: Border.all(color: color.withValues(alpha: 0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Icon(icon, color: color, size: 13),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _raj(8, FontWeight.w700, _T.muted, spacing: 1)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
            child: Text(value, style: _raj(smallText ? 10 : 12, FontWeight.w900, color)),
          ),
        ]),
      ]),
    );
  }

  // ── Invasión — ROJO se mantiene porque son alertas
  void _escucharNotificacionesInvasion() {
    if (userId == null) return;
    _presenciaListener?.cancel();
    _presenciaListener = FirebaseFirestore.instance
        .collection('presencia_activa')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final nuevos = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final ts = d['timestamp'] as Timestamp?;
        if (ts != null && DateTime.now().difference(ts.toDate()).inMinutes < 5) {
          nuevos[doc.id] = d;
        }
      }
      // jugadores en vivo — tracking only, no UI refresh needed
    });

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
          final data = change.doc.data();
          if (data == null) continue;
          _mostrarBannerInvasion(
              data['message'] ?? ' Alguien está invadiendo tu territorio',
              change.doc.id);
        }
      }
    });
  }

  // Banner de invasión — ROJO se mantiene (es una alerta crítica)
  void _mostrarBannerInvasion(String mensaje, String notifId) {
    if (!mounted) return;
    FirebaseFirestore.instance.collection('notifications').doc(notifId).update({'read': true});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: _T.redD.withValues(alpha: 0.97),
            border: Border.all(color: _T.red.withValues(alpha: 0.5)),
            boxShadow: [BoxShadow(color: _T.redGlow, blurRadius: 20)]),
        child: Row(children: [
          const Text('', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(child: Text(mensaje,
              style: _raj(13, FontWeight.w700, _T.white, spacing: 0.5))),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            child: Text('DEFENDER', style: _raj(11, FontWeight.w900, _T.red, spacing: 1.5)),
          ),
        ]),
      ),
    ));
  }

  // ── Datos usuario
  Future<void> _loadUserData() async {
    final userDoc = await FirebaseFirestore.instance.collection('players').doc(userId).get();
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
          .map((d) => d.data())
          .where((d) => d.containsKey('id_reto_completado') && d['id_reto_completado'] != null)
          .toList();
      listaTemporal.sort((a, b) {
        Timestamp? tA = a['timestamp'] as Timestamp?;
        Timestamp? tB = b['timestamp'] as Timestamp?;
        if (tA == null || tB == null) return 0;
        return tB.compareTo(tA);
      });
      if (mounted) setState(() => _completedChallengesCache = listaTemporal);
    } catch (e) {
      debugPrint("Error cargando logros: $e");
    }
  }

  Future<void> _checkDailyReset() async {
    final userDocRef = FirebaseFirestore.instance.collection('players').doc(userId);
    final userDoc = await userDocRef.get();
    if (!userDoc.exists) return;
    final data = userDoc.data()!;
    final lastReset = data['last_daily_reset'] as Timestamp?;
    final now = DateTime.now();
    if (lastReset == null || now.difference(lastReset.toDate()).inSeconds >= 86400) {
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
      if (!mounted) return;
      final remaining = resetTime.difference(DateTime.now());
      _timeUntilReset.value = remaining;
      if (remaining.isNegative || remaining.inSeconds == 0) {
        _dailyResetTimer?.cancel();
        _handleDailyReset();
      }
    });
  }

  Future<void> _handleDailyReset() async {
    if (mounted) setState(() {
      _completedChallengesCache.clear();
      _dailyChallenges.clear();
      isLoading = true;
    });
    await _initializeData();
  }

  Future<void> _loadRandomDailyChallenges() async {
    if (mounted) setState(() => _loadingChallenges = true);
    try {
      final esPremium = SubscriptionService.currentStatus.isPremium;

      final challengesSnap = await FirebaseFirestore.instance
          .collection('daily_challenges')
          .where('rango_requerido', isLessThanOrEqualTo: nivel)
          .get();

      final completedIds = _completedChallengesCache
          .map((c) => c['id_reto_completado']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final disponibles = challengesSnap.docs
          .where((doc) {
            final d = doc.data();
            final esPrem = d['es_premium'] as bool? ?? false;
            return !completedIds.contains(doc.id) && !esPrem;
          })
          .toList()..shuffle();

      final retosNormales = disponibles.take(3).toList();
      List<QueryDocumentSnapshot> retosPremium = [];

      if (esPremium) {
        final premiumSnap = await FirebaseFirestore.instance
            .collection('daily_challenges')
            .where('es_premium', isEqualTo: true)
            .get();
        retosPremium = premiumSnap.docs
            .where((doc) => !completedIds.contains(doc.id))
            .toList()..shuffle();
        retosPremium = retosPremium.take(2).toList();
      }

      if (mounted) {
        setState(() {
          _dailyChallenges = [...retosPremium, ...retosNormales];
          _loadingChallenges = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando retos: $e');
      if (mounted) setState(() => _loadingChallenges = false);
    }
  }

  Future<void> _mostrarTooltipRetosIntro() async {
    final state = await OnboardingService.cargarEstado();
    if (!mounted) return;
    await mostrarTooltipOnboarding(
      context: context,
      tooltipId: 'retos_intro',
      state: state,
    );
  }

  void _confirmarInicioReto({
    required String id,
    required String titulo,
    required String desc,
    required int premio,
    required int objetivoMetros,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _T.bg1,
            border: Border.all(color: _T.bronze.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(color: _T.bronze.withValues(alpha: 0.08), blurRadius: 32),
              const BoxShadow(color: Colors.black54, blurRadius: 12),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: _T.bronze.withValues(alpha: 0.08),
                border: Border.all(color: _T.bronze.withValues(alpha: 0.30)),
              ),
              child: const Center(child: Text('', style: TextStyle(fontSize: 26))),
            ),
            const SizedBox(height: 16),
            Text('INICIAR MISIÓN',
                style: _raj(9, FontWeight.w900, _T.bronze, spacing: 3)),
            const SizedBox(height: 8),
            Text(
              '¿Vas a iniciar el reto de\n"$titulo"?\n¿Estás seguro?',
              textAlign: TextAlign.center,
              style: _raj(15, FontWeight.w700, _T.white, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: _raj(12, FontWeight.w500, _T.sub, height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _T.bg0,
                border: Border.all(color: _T.border2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('DISTANCIA', style: _raj(8, FontWeight.w700, _T.muted, spacing: 1.5)),
                    const SizedBox(height: 4),
                    Text(
                      objetivoMetros >= 1000
                          ? '${(objetivoMetros / 1000).toStringAsFixed(1)} km'
                          : '${objetivoMetros} m',
                      style: _raj(18, FontWeight.w900, _T.white, height: 1),
                    ),
                  ]),
                  Container(width: 1, height: 32, color: _T.border2),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('RECOMPENSA', style: _raj(8, FontWeight.w700, _T.muted, spacing: 1.5)),
                    const SizedBox(height: 4),
                    Text('+$premio PTS',
                        style: _raj(18, FontWeight.w900, _T.gold, height: 1)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: _T.border2),
                    ),
                    child: Text(
                      'NO',
                      textAlign: TextAlign.center,
                      style: _raj(13, FontWeight.w700, _T.muted, spacing: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/correr',
                      ModalRoute.withName('/home'),
                      arguments: {
                        'retoActivo': {
                          'id':             id,
                          'titulo':         titulo,
                          'desc':           desc,
                          'premio':         premio,
                          'objetivo_valor': objetivoMetros,
                        },
                      },
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _T.bronze.withValues(alpha: 0.10),
                      border: Border.all(color: _T.bronze.withValues(alpha: 0.55)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Text(
                          'INICIAR',
                          textAlign: TextAlign.center,
                          style: _raj(13, FontWeight.w900, _T.bronze, spacing: 2.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<String?> _puedeRobarTerritorio({
    required String ownerIdObjetivo,
    required String territorioDocId,
  }) async {
    if (nivel < 2) {
      return 'Necesitas al menos nivel 2 para conquistar territorios.\nActualmente eres nivel $nivel.';
    }
    try {
      final terDoc = await FirebaseFirestore.instance.collection('territories').doc(territorioDocId).get();
      if (terDoc.exists) {
        final data = terDoc.data()!;
        final tsVisita = data['ultima_visita'] as Timestamp?;
        if (tsVisita != null) {
          final diasSinVisitar = DateTime.now().difference(tsVisita.toDate()).inDays;
          if (diasSinVisitar < 5) {
            return 'Este territorio está protegido.\nEl dueño lo visitó hace $diasSinVisitar día${diasSinVisitar == 1 ? '' : 's'}. Necesitas 5+ días sin visitar.';
          }
        } else {
          return 'Este territorio está activo y protegido.\nVuelve cuando lleve 5+ días sin ser visitado.';
        }
      }
    } catch (e) { // intentional
    }
    try {
      final misTerritoriosSnap = await FirebaseFirestore.instance
          .collection('territories').where('userId', isEqualTo: userId).get();
      final territoriosDefensorSnap = await FirebaseFirestore.instance
          .collection('territories').where('userId', isEqualTo: ownerIdObjetivo).get();
      final misCantidad = misTerritoriosSnap.docs.length;
      final defensorCantidad = territoriosDefensorSnap.docs.length;
      if (defensorCantidad > 0 && misCantidad >= defensorCantidad * 3) {
        return 'Ya tienes demasiados territorios comparado con este jugador.\nNo puedes seguir conquistando hasta que el rival crezca.';
      }
    } catch (e) { // intentional
    }
    try {
      final ownerDoc = await FirebaseFirestore.instance.collection('players').doc(ownerIdObjetivo).get();
      if (ownerDoc.exists) {
        final escudoActivo = ownerDoc.data()?['escudo_activo'] as bool? ?? false;
        final escudoExpiraTs = ownerDoc.data()?['escudo_expira'] as Timestamp?;
        if (escudoActivo && escudoExpiraTs != null && escudoExpiraTs.toDate().isAfter(DateTime.now())) {
          final duracion = escudoExpiraTs.toDate().difference(DateTime.now());
          final horas = duracion.inHours;
          final minutos = duracion.inMinutes.remainder(60);
          final tiempoRestante = horas > 0 ? '${horas}h ${minutos}m' : '${minutos}m';
          return ' Este territorio tiene un escudo activo.\nNo puede ser conquistado durante $tiempoRestante más.';
        }
      }
    } catch (e) { // intentional
    }
    return null;
  }

  void _navegarAlPerfil(FeedPost post) {
    if (post.userId == userId) {
      Navigator.pushNamedAndRemoveUntil(context, '/perfil', ModalRoute.withName('/home'));
    } else {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => PerfilScreen(targetUserId: post.userId)));
    }
  }

  Future<void> _recargarHistorias() async {
    try {
      final misHistorias = await StoryService.fetchMyActiveStories(
          defaultColor: _accentColor);
      final amigoIds = _amigos.map((a) => a['id'] as String).toList();
      final storiesPorAmigo = await StoryService.fetchActiveStoriesForUsers(
          amigoIds, defaultColor: _accentColor);
      if (mounted) {
        setState(() {
          _misHistorias = misHistorias;
          _storiesPorAmigo = storiesPorAmigo;
        });
      }
    } catch (e) {
      debugPrint('Error recargando historias: $e');
    }
  }

  void _openStoryViewer({
    required bool isMe,
    required Map<String, dynamic> item,
    required String? foto,
    required String label,
  }) {
    if (isMe) {
      if (_misHistorias.isEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const CreatePostScreen(),
          ),
        ).then((_) {
          if (mounted) _recargarHistorias();
        });
        return;
      }
      Navigator.push(context, PageRouteBuilder(
        pageBuilder: (_, __, ___) => StoryViewerScreen(
          groups: [UserStoriesGroup(
            userId: userId!, nickname: nickname, avatarBase64: fotoBase64,
            color: _T.bronze, stories: _misHistorias)],
          initialGroupIndex: 0,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      )).then((_) {
        if (mounted) _recargarHistorias();
      });
      return;
    }

    final friendId = item['id'] as String;
    final friendStories = _storiesPorAmigo[friendId];
    if (friendStories == null || friendStories.isEmpty) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => PerfilScreen(targetUserId: friendId)));
      return;
    }

    final List<UserStoriesGroup> groups = [];
    int initialIdx = 0;
    for (final amigo in _amigos) {
      final aId = amigo['id'] as String;
      final aStories = _storiesPorAmigo[aId];
      if (aStories == null || aStories.isEmpty) continue;
      if (aId == friendId) initialIdx = groups.length;
      groups.add(UserStoriesGroup(
        userId: aId, nickname: amigo['nickname'] as String? ?? '?',
        avatarBase64: amigo['foto_base64'] as String?,
        color: _T.bronze, stories: aStories));
    }
    if (groups.isEmpty) return;

    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, __, ___) => StoryViewerScreen(groups: groups, initialGroupIndex: initialIdx),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  void _mostrarResumenCarrera(FeedPost post) {
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
      final latC = ruta.map((p) => p.latitude).reduce((a, b) => a + b) / ruta.length;
      final lngC = ruta.map((p) => p.longitude).reduce((a, b) => a + b) / ruta.length;
      centro = LatLng(latC, lngC);
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.90),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
        child: Container(
          decoration: BoxDecoration(
            color: _T.bg1,
            border: Border.all(color: _T.border2),
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 36)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
              child: Row(children: [
                GestureDetector(
                  onTap: () { Navigator.pop(ctx); _navegarAlPerfil(post); },
                  child: _buildAvatar(post, radius: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(post.userNickname.toUpperCase(),
                      style: _raj(13, FontWeight.w900, _T.white, spacing: 1.5)),
                  if (post.titulo != null)
                    Text(post.titulo!, style: _raj(12, FontWeight.w500, _T.sub)),
                  Text(_timeAgo(post.fecha), style: _raj(11, FontWeight.w500, _T.muted)),
                ])),
                IconButton(onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close_rounded, color: _T.sub, size: 20)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
                decoration: BoxDecoration(
                  color: _T.bg0,
                  border: Border.all(color: _T.border2),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  if (post.distanciaKm != null)
                    _popupStat(value: post.distanciaKm!.toStringAsFixed(2),
                        unit: 'KM', big: true),
                  if (tiempoStr != null)
                    _popupStat(value: tiempoStr, unit: 'TIEMPO'),
                  if (post.velocidadMedia != null)
                    _popupStat(value: post.velocidadMedia!.toStringAsFixed(1), unit: 'KM/H'),
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
                      initialCenter: centro, initialZoom: 14,
                      interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                    ),
                    children: [
                      TileLayer(urlTemplate: _kMapboxTileUrl,
                          userAgentPackageName: 'com.runner_risk.app',
                          tileDimension: 256,
                          additionalOptions: const {'accessToken': _kMapboxToken}),
                      PolylineLayer(polylines: [
                        Polyline(points: ruta, color: _T.bronze, strokeWidth: 3.5)]),
                      MarkerLayer(markers: [
                        Marker(point: ruta.first, width: 18, height: 18,
                            child: Container(decoration: BoxDecoration(
                                color: _T.safe, shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2)))),
                        Marker(point: ruta.last, width: 18, height: 18,
                            child: Container(decoration: BoxDecoration(
                                color: _T.bronze, shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2)))),
                      ]),
                    ],
                  ),
                ),
              ),
            if (post.descripcion != null && post.descripcion!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _T.bg0, border: Border.all(color: _T.border)),
                  child: Text(post.descripcion!,
                      style: _raj(13, FontWeight.w500, _T.sub, height: 1.5)),
                ),
              ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Widget _popupStat({required String value, required String unit, bool big = false}) {
    return Expanded(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: GoogleFonts.inter(
            fontSize: big ? 36 : 26, fontWeight: FontWeight.w700,
            color: _T.white, height: 1,
            letterSpacing: -0.5)),
        const SizedBox(height: 3),
        Text(unit, style: _raj(9, FontWeight.w700, _T.muted, spacing: 2)),
      ]),
    );
  }

  // =============================================================================
  // BUILD
  // =============================================================================
  @override
  Widget build(BuildContext context) {
    _T = _TColors.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: isLoading
          ? _buildLoadingState()
          : Column(children: [
              FadeTransition(opacity: _fadeA, child: _buildStoriesHeader()),
              FadeTransition(opacity: _fadeA, child: _buildTabBar()),
              Expanded(
                child: SlideTransition(
                  position: _slideB,
                  child: FadeTransition(
                    opacity: _fadeB,
                    child: PageView(
                      controller: _pageController,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (index) {
                        setState(() => _tabIndex = index);
                        if (index == 1) _mostrarTooltipRetosIntro();
                      },
                      children: [
                        _buildFeedTab(),
                        _buildRetosTab(),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 0),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge([_loopCtrl, _scanCtrl]),
        builder: (_, __) => Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 48, height: 48,
            child: CustomPaint(painter: _LoaderPainter(
                accent: _T.bronze,
                progress: _scan.value,
                pulse: _pulse.value)),
          ),
          const SizedBox(height: 18),
          Text('CARGANDO', style: _raj(10, FontWeight.w700, _T.muted, spacing: 4)),
        ]),
      ),
    );
  }

  // =============================================================================
  // APP BAR
  // =============================================================================
  PreferredSizeWidget _buildAppBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : const Color(0xF0F2F2F7),
      elevation: 0,
      titleSpacing: 16,
      surfaceTintColor: Colors.transparent,
      title: Row(children: [
        RichText(
          text: TextSpan(
            style: GoogleFonts.inter(
              fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            children: [
              const TextSpan(
                text: 'RISK',
                style: TextStyle(color: Color(0xFFE02020)),
              ),
              TextSpan(
                text: 'RUNNER',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : const Color(0xFF1C1C1E),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ]),
      actions: [
        GestureDetector(
          onTap: () => CoinShopScreen.mostrar(context),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _T.gold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _T.gold.withValues(alpha: 0.30)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text('$monedas',
                style: TextStyle(
                  color: _T.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                )),
            ]),
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Stack(children: [
              Icon(Icons.notifications_outlined, color: _T.dim, size: 22),
              if (_notifNoLeidas > 0)
                Positioned(right: 0, top: 0,
                  child: Container(
                    width: 7, height: 7,
                    // Notificación — rojo se mantiene (es una alerta)
                    decoration: BoxDecoration(color: _T.red, shape: BoxShape.circle),
                  ),
                ),
            ]),
          ),
        ),
        GestureDetector(
          onTap: () => SettingsScreen.mostrar(context),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Icon(Icons.settings_outlined, color: _T.dim, size: 20),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // =============================================================================
  // STORIES HEADER
  // =============================================================================
  Widget _buildStoriesHeader() {
    final List<Map<String, dynamic>> items = [
      {'isMe': true, 'label': nickname},
      ..._amigos,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _T.bg1,
        border: Border(bottom: BorderSide(color: _T.border2)),
      ),
      child: SizedBox(
        height: 104,
        child: _amigosLoaded
            ? ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final item = items[i];
                  final bool isMe = item['isMe'] == true;
                  final String label = isMe ? 'Tú' : (item['nickname'] as String? ?? '?');
                  final String? foto = isMe ? fotoBase64 : (item['foto_base64'] as String?);
                  final bool hasStories = isMe
                      ? _misHistorias.isNotEmpty
                      : (_storiesPorAmigo[item['id']]?.isNotEmpty ?? false);
                  final bool allViewed = !isMe && hasStories &&
                      (_storiesPorAmigo[item['id']]?.every((s) => s.isViewedByMe) ?? false);

                  Color ringColor;
                  double ringWidth;
                  if (hasStories && !allViewed) {
                    ringColor = _T.bronze; ringWidth = 2.0;
                  } else if (hasStories && allViewed) {
                    ringColor = _T.muted; ringWidth = 1.5;
                  } else {
                    ringColor = isMe ? _T.bronze.withValues(alpha: 0.5) : _T.border2;
                    ringWidth = isMe ? 1.5 : 1.0;
                  }

                  return GestureDetector(
                    onTap: () => _openStoryViewer(
                        isMe: isMe, item: item, foto: foto, label: label),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) {
                          return Stack(children: [
                            Container(
                              width: 72, height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: (hasStories && !allViewed && isMe)
                                      ? ringColor.withValues(alpha: 0.5 + 0.5 * _pulse.value)
                                      : ringColor,
                                  width: ringWidth,
                                ),
                              ),
                              padding: const EdgeInsets.all(3),
                              child: child,
                            ),
                            if (hasStories && !allViewed)
                              Positioned(right: 2, bottom: 2,
                                child: Container(
                                  width: 13, height: 13,
                                  decoration: BoxDecoration(
                                      color: _T.bronze, shape: BoxShape.circle,
                                      border: Border.all(color: _T.bg1, width: 1.5)),
                                )),
                          ]);
                        },
                        child: ClipOval(
                          child: Container(
                            color: _T.bg2,
                            child: foto != null
                                ? Image.memory(base64Decode(foto), key: ValueKey(foto.hashCode), fit: BoxFit.cover, gaplessPlayback: true)
                                : isMe
                                    ? Stack(alignment: Alignment.center, children: [
                                        Icon(Icons.person, color: _T.dim, size: 30),
                                        Positioned(bottom: 4, right: 4, child: Container(
                                          width: 18, height: 18,
                                          decoration: BoxDecoration(
                                              color: _T.bronze, shape: BoxShape.circle,
                                              border: Border.all(color: _T.bg1, width: 1.5)),
                                          child: const Icon(Icons.add, color: Colors.white, size: 11),
                                        )),
                                      ])
                                    : Center(child: Text(label[0].toUpperCase(),
                                        style: _raj(22, FontWeight.w900, _T.white))),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        isMe
                            ? (_misHistorias.isNotEmpty ? 'Mi historia' : 'Tú')
                            : (label.length > 7 ? '${label.substring(0, 6)}…' : label),
                        style: _raj(9, hasStories && !allViewed ? FontWeight.w700 : FontWeight.w500,
                            hasStories && !allViewed ? _T.white : _T.sub),
                      ),
                      if (!isMe)
                        Text('NIV.${(item['nivel'] as num? ?? 1).toInt()}',
                            style: _raj(7, FontWeight.w600, _T.muted, spacing: 0.5)),
                    ]),
                  );
                },
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 5,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, __) => Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 72, height: 72,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                          color: _T.bg2, border: Border.all(color: _T.border2))),
                  const SizedBox(height: 5),
                  Container(width: 36, height: 7, color: _T.bg3),
                ]),
              ),
      ),
    );
  }

  // =============================================================================
  // TAB BAR
  // =============================================================================
  Widget _buildTabBar() {
    final tabs = [
      {'id': 'feed',  'label': 'FEED',  'icon': Icons.dynamic_feed_outlined, 'page': 0},
      {'id': 'retos', 'label': 'RETOS', 'icon': Icons.bolt_outlined,          'page': 1},
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      height: 42,
      decoration: BoxDecoration(
        color: _T.bg1,
        border: Border.all(color: _T.border2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: tabs.map((tab) {
          final pageIdx  = tab['page'] as int;
          final isCorrer = pageIdx == -1;
          final isActive = !isCorrer && _tabIndex == pageIdx;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (isCorrer) {
                  Navigator.pushNamed(context, '/correr');
                  return;
                }
                setState(() => _tabIndex = pageIdx);
                _pageController.animateToPage(
                  pageIdx,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                );
                if (tab['id'] == 'retos') _mostrarTooltipRetosIntro();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isActive ? _T.bg2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: isActive ? Border.all(color: _T.border2) : null,
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(tab['icon'] as IconData,
                      size: 12,
                      color: isCorrer ? _T.bronze : isActive ? _T.bronze : _T.dim),
                  const SizedBox(width: 5),
                  Stack(children: [
                    Text(
                      tab['label'] as String,
                      style: _raj(9,
                          isActive || isCorrer ? FontWeight.w900 : FontWeight.w600,
                          isCorrer ? _T.bronze : isActive ? _T.white : _T.dim,
                          spacing: 1.5),
                    ),
                    if (tab['id'] == 'retos' && _dailyChallenges.isNotEmpty)
                      Positioned(
                        right: -8, top: -2,
                        child: Container(
                          width: 12, height: 12,
                          // Badge de retos — bronce, no rojo
                          decoration: BoxDecoration(
                              color: _T.bronze, shape: BoxShape.circle),
                          child: Center(child: Text('${_dailyChallenges.length}',
                              style: _raj(7, FontWeight.w900, _T.bg0))),
                        ),
                      ),
                  ]),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // =============================================================================
  // TAB: FEED
  // =============================================================================
  Widget _buildFeedTab() {
    if (_loadingFeed) {
      return Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([_loopCtrl, _scanCtrl]),
          builder: (_, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 40, height: 40,
                child: CustomPaint(painter: _LoaderPainter(
                    accent: _T.bronze, progress: _scan.value, pulse: _pulse.value))),
            const SizedBox(height: 16),
            Text('CARGANDO FEED', style: _raj(10, FontWeight.w700, _T.muted, spacing: 3)),
          ]),
        ),
      );
    }
    if (_feedPosts.isEmpty) return _buildFeedEmptyState();
    return RefreshIndicator(
      onRefresh: () async {
        _feedListener?.cancel();
        _escucharFeed();
      },
      color: _T.bronze, backgroundColor: _T.bg2, strokeWidth: 1.5,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 12, bottom: 120),
        itemCount: _feedPosts.length,
        itemBuilder: (context, index) => _buildPostCard(_feedPosts[index]),
      ),
    );
  }

  Widget _buildFeedEmptyState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
              color: _T.bg1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _T.border2)),
          child: Icon(Icons.directions_run_rounded, color: _T.muted, size: 30),
        ),
        const SizedBox(height: 20),
        Text('SIN ACTIVIDAD', style: _raj(14, FontWeight.w900, _T.white, spacing: 4)),
        const SizedBox(height: 8),
        Text('Sé el primero en compartir\ntu carrera con la comunidad',
            textAlign: TextAlign.center,
            style: _raj(13, FontWeight.w500, _T.sub, height: 1.5)),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/correr'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
            decoration: BoxDecoration(
                color: _T.bronze.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _T.bronze.withValues(alpha: 0.5))),
            child: Text('INICIAR CARRERA',
                style: _raj(12, FontWeight.w900, _T.bronze, spacing: 2.5)),
          ),
        ),
      ]),
    );
  }

  // =============================================================================
  // POST CARD
  // =============================================================================
  Widget _buildPostCard(FeedPost post) {
    final isRun = post.tipo == 'run' || post.tipo == 'territorio';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Header
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Row(children: [
          GestureDetector(
            onTap: () => _navegarAlPerfil(post),
            child: _buildAvatar(post, radius: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _navegarAlPerfil(post),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(post.userNickname,
                    style: _raj(14, FontWeight.w700, _T.white)),
                const SizedBox(height: 1),
                Text(_timeAgo(post.fecha),
                    style: _raj(11, FontWeight.w400, _T.dim)),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _T.bg2,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_iconForTipo(post.tipo), color: _T.sub, size: 11),
              const SizedBox(width: 4),
              Text(_labelForTipo(post.tipo),
                  style: _raj(9, FontWeight.w600, _T.sub, spacing: 0.3)),
            ]),
          ),
          const SizedBox(width: 8),
          Icon(Icons.more_horiz, color: _T.dim, size: 20),
        ]),
      ),
      // ── Título + descripción
      if (post.titulo != null || post.descripcion != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (post.titulo != null)
              Text(post.titulo!, style: _raj(15, FontWeight.w700, _T.white, height: 1.3)),
            if (post.descripcion != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(post.descripcion!,
                    style: _raj(13, FontWeight.w400, _T.sub, height: 1.5)),
              ),
          ]),
        ),
      // ── Stats carrera
      if (isRun && (post.distanciaKm != null || post.velocidadMedia != null || post.tiempo != null))
        _buildRunStatsBar(post),
      // ── Media / mapa
      if (post.mediaBase64 != null)
        _buildMediaImage(post)
      else if (isRun && post.ruta != null && post.ruta!.isNotEmpty)
        _buildRouteMap(post),
      // ── Acciones
      _buildPostActions(post),
      Divider(height: 1, thickness: 0.5, color: _T.border),
    ]);
  }

  Widget _buildAvatar(FeedPost post, {double radius = 20}) {
    final foto = _avatarCache.containsKey(post.userId)
        ? _avatarCache[post.userId]
        : post.userAvatarBase64;
    return Container(
      width: radius * 2 + 2, height: radius * 2 + 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _T.border, width: 1),
      ),
      child: ClipOval(
        child: foto != null
            ? Image.memory(
                base64Decode(foto),
                key: ValueKey(foto.hashCode),
                fit: BoxFit.cover,
                width: radius * 2,
                height: radius * 2,
                gaplessPlayback: true,
              )
            : Container(
                color: _T.bg2,
                child: Center(child: Text(
                    post.userNickname.isNotEmpty ? post.userNickname[0].toUpperCase() : 'R',
                    style: _raj(radius * 0.85, FontWeight.w900, _T.white))),
              ),
      ),
    );
  }

  Widget _buildRunStatsBar(FeedPost post) {
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
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _T.bg2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        if (post.distanciaKm != null)
          _statItem(value: post.distanciaKm!.toStringAsFixed(2), unit: 'KM', big: true),
        if (post.distanciaKm != null && tiempoStr != null) _statDivider(),
        if (tiempoStr != null)
          _statItem(value: tiempoStr, unit: 'TIEMPO'),
        if (tiempoStr != null && post.velocidadMedia != null) _statDivider(),
        if (post.velocidadMedia != null)
          _statItem(value: post.velocidadMedia!.toStringAsFixed(1), unit: 'KM/H'),
      ]),
    );
  }

  Widget _statItem({required String value, required String unit, bool big = false}) {
    return Expanded(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: GoogleFonts.inter(
            fontSize: big ? 32 : 22, fontWeight: FontWeight.w700,
            color: _T.white, height: 1, letterSpacing: -0.5)),
        const SizedBox(height: 3),
        Text(unit, style: _raj(8, FontWeight.w700, _T.muted, spacing: 2)),
      ]),
    );
  }

  Widget _statDivider() => Container(
    width: 1, height: 32,
    color: _T.border2,
  );

  Widget _buildMediaImage(FeedPost post) {
    return Container(
      height: 300,
      margin: const EdgeInsets.only(bottom: 4),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(),
      child: Image.memory(base64Decode(post.mediaBase64!),
          width: double.infinity, fit: BoxFit.cover),
    );
  }

  Widget _buildRouteMap(FeedPost post) {
    final ruta = post.ruta!;
    final latC = ruta.map((p) => p.latitude).reduce((a, b) => a + b) / ruta.length;
    final lngC = ruta.map((p) => p.longitude).reduce((a, b) => a + b) / ruta.length;
    return Container(
      height: 200,
      margin: const EdgeInsets.only(bottom: 4),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(),
      child: Stack(children: [
        FlutterMap(
          options: MapOptions(
              initialCenter: LatLng(latC, lngC), initialZoom: 14,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
          children: [
            TileLayer(urlTemplate: _kMapboxTileUrl,
                userAgentPackageName: 'com.runner_risk.app',
                tileDimension: 256,
                additionalOptions: const {'accessToken': _kMapboxToken}),
            PolylineLayer(polylines: [
              Polyline(points: ruta, color: _T.bronze, strokeWidth: 3)
            ]),
            MarkerLayer(markers: [
              Marker(point: ruta.first, width: 12, height: 12,
                  child: Container(decoration: BoxDecoration(
                      color: _T.safe, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2)))),
              Marker(point: ruta.last, width: 12, height: 12,
                  child: Container(decoration: BoxDecoration(
                      color: _T.bronze, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2)))),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  color: _T.bg0.withValues(alpha: 0.88),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bar_chart_rounded, color: _T.sub, size: 10),
                    const SizedBox(width: 4),
                    Text('VER STATS',
                        style: _raj(9, FontWeight.w900, _T.sub, spacing: 1)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildPostActions(FeedPost post) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 10, 10),
      child: Row(children: [
        _actionBtn(
          icon: post.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          label: post.likes > 0 ? '${post.likes}' : null,
          color: post.likedByMe ? _T.white : _T.sub,
          onTap: () => _toggleLike(post),
        ),
        _actionBtn(
          icon: Icons.chat_bubble_outline_rounded,
          label: post.comentarios > 0 ? '${post.comentarios}' : null,
          color: _T.sub,
          onTap: () => _mostrarComentariosSheet(post),
        ),
        _actionBtn(icon: Icons.share_outlined, color: _T.sub, onTap: () {}),
        const Spacer(),
        if (post.ruta != null && post.ruta!.isNotEmpty)
          _actionBtn(icon: Icons.route_outlined, color: _T.sub, onTap: () => _guardarRuta(post)),
        _actionBtn(
          icon: post.savedByMe ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          color: post.savedByMe ? _T.white : _T.sub,
          onTap: () => _toggleSave(post),
        ),
      ]),
    );
  }

  Widget _actionBtn({required IconData icon, String? label, required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 22),
          if (label != null) ...[
            const SizedBox(width: 5),
            Text(label, style: _raj(13, FontWeight.w600, color)),
          ],
        ]),
      ),
    );
  }

  void _mostrarComentariosSheet(FeedPost post) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _T.bg1,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.65, minChildSize: 0.4, maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Column(children: [
          Container(margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 32, height: 3, color: _T.muted),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Text('COMENTARIOS', style: _raj(11, FontWeight.w900, _T.white, spacing: 2.5)),
              const Spacer(),
              GestureDetector(onTap: () => Navigator.pop(ctx),
                  child: Icon(Icons.close_rounded, color: _T.sub, size: 20)),
            ]),
          ),
          Divider(color: _T.border2, height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('posts').doc(post.id)
                  .collection('comments').orderBy('timestamp').snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: _T.bronze, strokeWidth: 1.5));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(child: Text('Sin comentarios todavía',
                      style: _raj(13, FontWeight.w500, _T.muted)));
                }
                return ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) => _buildCommentRow(docs[i].data() as Map<String, dynamic>),
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
          width: 32, height: 32,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: _T.bg2,
              border: Border.all(color: _T.border2)),
          child: Center(child: Text(
              (cd['nickname'] as String? ?? 'R')[0].toUpperCase(),
              style: _raj(13, FontWeight.w900, _T.white))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cd['nickname'] ?? 'Runner', style: _raj(12, FontWeight.w700, _T.white)),
          const SizedBox(height: 2),
          Text(cd['texto'] ?? '', style: _raj(13, FontWeight.w500, _T.sub)),
        ])),
      ]),
    );
  }

  Widget _buildCommentInput(FeedPost post) {
    return _CommentInput(
      fotoBase64: fotoBase64,
      onSend: (texto) async {
        if (userId == null) return;
        await FirebaseFirestore.instance.collection('posts').doc(post.id)
            .collection('comments').add({
          'userId': userId, 'nickname': nickname,
          'texto': texto, 'timestamp': FieldValue.serverTimestamp(),
        });
        await FirebaseFirestore.instance.collection('posts').doc(post.id)
            .update({'comentariosCount': FieldValue.increment(1)});
      },
    );
  }

  // =============================================================================
  // TAB: RETOS
  // =============================================================================
  Widget _buildRetosTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionHeader('LOGROS DE HOY', Icons.emoji_events_outlined,
            _completedChallengesCache.length > 3
                ? (_mostrarTodosLosLogros
                    ? 'VER MENOS' : 'VER TODOS (${_completedChallengesCache.length})')
                : '',
            () => setState(() => _mostrarTodosLosLogros = !_mostrarTodosLosLogros)),
        const SizedBox(height: 14),
        _buildCompletedChallengesList(),
        const SizedBox(height: 28),
        _buildSectionHeader('MISIONES DEL DÍA', Icons.bolt_outlined, '', null),
        const SizedBox(height: 8),
        _buildDailyResetTimer(),
        const SizedBox(height: 14),
        _buildDailyChallengesList(),
      ]),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, String action, VoidCallback? onAction) {
    return Row(children: [
      Container(width: 2, height: 14, color: _T.bronze),
      const SizedBox(width: 9),
      Icon(icon, color: _T.dim, size: 11),
      const SizedBox(width: 7),
      Text(title, style: _raj(10, FontWeight.w700, _T.dim, spacing: 2.5)),
      const Spacer(),
      if (action.isNotEmpty)
        GestureDetector(
          onTap: onAction,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: _T.bg2, border: Border.all(color: _T.border2)),
            child: Text(action,
                style: _raj(9, FontWeight.w800, _T.sub, spacing: 1.2)),
          ),
        ),
    ]);
  }

  Widget _buildDailyResetTimer() {
    return ValueListenableBuilder<Duration>(
      valueListenable: _timeUntilReset,
      builder: (_, remaining, __) {
        final h = remaining.inHours.toString().padLeft(2, '0');
        final m = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
        final s = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: _T.bg1, border: Border.all(color: _T.border2)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.timer_outlined, color: _T.muted, size: 12),
            const SizedBox(width: 6),
            Text('RESET EN $h:$m:$s',
                style: _raj(11, FontWeight.w700, _T.text, spacing: 1.5)),
          ]),
        );
      },
    );
  }

  Widget _buildCompletedChallengesList() {
    if (_completedChallengesCache.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _T.bg1, border: Border.all(color: _T.border2)),
        child: Row(children: [
          Icon(Icons.hourglass_empty_rounded, color: _T.muted, size: 14),
          const SizedBox(width: 10),
          Text('Ningún reto completado hoy todavía',
              style: _raj(13, FontWeight.w500, _T.muted)),
        ]),
      );
    }
    final lista = _mostrarTodosLosLogros
        ? _completedChallengesCache : _completedChallengesCache.take(3).toList();
    return Column(children: lista.map((data) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: _T.bg1,
          border: Border(
              left: BorderSide(color: _T.safe, width: 2),
              top: BorderSide(color: _T.border2),
              right: BorderSide(color: _T.border2),
              bottom: BorderSide(color: _T.border2))),
      child: Row(children: [
        Icon(Icons.check_circle_outline_rounded, color: _T.safe, size: 17),
        const SizedBox(width: 12),
        Expanded(child: Text(data['titulo'] ?? 'Reto completado',
            style: _raj(13, FontWeight.w600, _T.white))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: _T.bg2, border: Border.all(color: _T.border2)),
          child: Text('+${data['recompensa']}',
              style: _raj(12, FontWeight.w900, _T.gold)),
        ),
      ]),
    )).toList());
  }

  Widget _buildDailyChallengesList() {
    if (_loadingChallenges) {
      return Center(child: CircularProgressIndicator(color: _T.bronze, strokeWidth: 1.5));
    }
    if (_dailyChallenges.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _T.bg1,
            border: Border(
                left: BorderSide(color: _T.safe, width: 2),
                top: BorderSide(color: _T.border2),
                right: BorderSide(color: _T.border2),
                bottom: BorderSide(color: _T.border2))),
        child: Row(children: [
          Icon(Icons.check_circle_outline_rounded, color: _T.safe, size: 14),
          const SizedBox(width: 10),
          Text('¡Todos los desafíos completados!',
              style: _raj(13, FontWeight.w600, _T.safe)),
        ]),
      );
    }
    return Column(children: _dailyChallenges.map((doc) {
      final data       = doc.data() as Map<String, dynamic>;
      final esPremium  = data['es_premium'] as bool? ?? false;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _confirmarInicioReto(
            id:             doc.id,
            titulo:         data['titulo'] as String? ?? 'Misión',
            desc:           data['descripcion'] as String? ?? '',
            premio:         (data['recompensas_monedas'] as num?)?.toInt() ?? 0,
            objetivoMetros: (data['objetivo_valor'] as num?)?.toInt() ?? 0,
          ),
          splashColor: _T.bronze.withValues(alpha: 0.08),
          highlightColor: _T.bronze.withValues(alpha: 0.04),
          child: _buildMissionCard(
              data['titulo'] ?? 'Misión',
              data['descripcion'] ?? '',
              '${data['recompensas_monedas'] ?? 0}',
              esPremium: esPremium),
        ),
      );
    }).toList());
  }

  Widget _buildMissionCard(String title, String desc, String reward,
      {bool esPremium = false}) {
    const goldColor = Color(0xFFDECA46);
    final borderColor = esPremium ? goldColor : _T.bronze;
    final iconBg      = esPremium
        ? goldColor.withValues(alpha: 0.08)
        : _T.bronze.withValues(alpha: 0.07);
    final iconBorder  = esPremium
        ? goldColor.withValues(alpha: 0.3)
        : _T.bronze.withValues(alpha: 0.20);
    final icon = esPremium ? Icons.workspace_premium_rounded : Icons.bolt_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: esPremium ? goldColor.withValues(alpha: 0.04) : _T.bg1,
        border: Border(
          left: BorderSide(color: borderColor, width: 2),
          top: BorderSide(color: _T.border2),
          right: BorderSide(color: _T.border2),
          bottom: BorderSide(color: _T.border2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              border: Border.all(color: iconBorder),
            ),
            child: Icon(icon, color: borderColor, size: 17),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (esPremium) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: goldColor.withValues(alpha: 0.12),
                    border: Border.all(color: goldColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(' PREMIUM',
                      style: _raj(7, FontWeight.w900, goldColor, spacing: 0.8)),
                ),
              ],
              Expanded(child: Text(title,
                  style: _raj(13, FontWeight.w800, _T.white),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 4),
            Text(desc, style: _raj(11, FontWeight.w500, _T.sub, height: 1.3)),
          ])),
          const SizedBox(width: 10),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('+$reward', style: GoogleFonts.inter(
                fontSize: 22, fontWeight: FontWeight.w700,
                color: esPremium ? goldColor : _T.gold, height: 1)),
            Text('PTS', style: _raj(8, FontWeight.w800, _T.muted, spacing: 2)),
          ]),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: _T.muted, size: 15),
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
      case 'video': return Icons.play_circle_outline_rounded;
      case 'foto': return Icons.image_outlined;
      case 'territorio': return Icons.flag_rounded;
      default: return Icons.directions_run_rounded;
    }
  }

  String _labelForTipo(String tipo) {
    switch (tipo) {
      case 'video': return 'VIDEO';
      case 'foto': return 'FOTO';
      case 'territorio': return 'ZONA';
      default: return 'CARRERA';
    }
  }
}

// =============================================================================
// PAINTER
// =============================================================================
class _LoaderPainter extends CustomPainter {
  final Color accent;
  final double progress, pulse;
  _LoaderPainter({required this.accent, required this.progress, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(c, 7.0 * i * 1.1,
          Paint()
            ..color = accent.withValues(alpha: 0.03 + 0.015 * pulse * (4 - i))
            ..strokeWidth = 0.6
            ..style = PaintingStyle.stroke);
    }
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: 18),
        progress * 2 * math.pi, 1.2, false,
        Paint()
          ..color = accent
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_LoaderPainter o) =>
      o.progress != progress || o.pulse != pulse;
}

// =============================================================================
// MODELOS AUXILIARES
// =============================================================================
class _UserTerritoryGroup {
  final String ownerId;
  final String nickname;
  final int nivel;
  final bool esMio;
  final List<_TerritoryDetail> territorios;

  _UserTerritoryGroup({
    required this.ownerId, required this.nickname, required this.nivel,
    required this.esMio, required this.territorios});
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
    required this.docId, required this.distanciaAlCentroKm,
    this.diasSinVisitar, this.fechaCreacion, this.distanciaRecorrida,
    this.velocidadMedia, this.tiempoActividad, this.puntos = const []});
}

// =============================================================================
// COMMENT INPUT — StatefulWidget para ciclo de vida correcto del controller
// =============================================================================
class _CommentInput extends StatefulWidget {
  final String? fotoBase64;
  final Future<void> Function(String texto) onSend;

  const _CommentInput({required this.fotoBase64, required this.onSend});

  @override
  State<_CommentInput> createState() => _CommentInputState();
}

class _CommentInputState extends State<_CommentInput> {
  final TextEditingController _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(texto);
      _ctrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final _T = _TColors.of(context);
    return Container(
      padding: EdgeInsets.only(
          left: 14, right: 14, top: 10,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14),
      decoration: BoxDecoration(
          color: _T.bg2, border: Border(top: BorderSide(color: _T.border2))),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(shape: BoxShape.circle,
              border: Border.all(color: _T.bronze.withValues(alpha: 0.5))),
          child: ClipOval(
            child: widget.fotoBase64 != null
                ? Image.memory(base64Decode(widget.fotoBase64!), fit: BoxFit.cover)
                : Icon(Icons.person, color: _T.bronze, size: 16),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _ctrl,
            style: _raj(13, FontWeight.w500, _T.white),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _handleSend(),
            decoration: InputDecoration(
              hintText: 'Añadir comentario...',
              hintStyle: _raj(13, FontWeight.w400, _T.muted),
              filled: true, fillColor: _T.bg1,
              border: OutlineInputBorder(borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: _T.border2)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: _T.border2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _handleSend,
          child: Container(
            width: 36, height: 36,
            color: _sending ? _T.muted : _T.bronze,
            child: _sending
                ? const Center(child: SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5)))
                : const Icon(Icons.send_rounded, color: Colors.white, size: 16),
          ),
        ),
      ]),
    );
  }
}