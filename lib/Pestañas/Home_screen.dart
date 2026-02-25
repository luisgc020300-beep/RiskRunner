import 'dart:async';
import 'dart:convert';
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
import 'notifications_screen.dart'; // ← NUEVO

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  Position? _currentPosition;
  String nickname = "Cargando...";
  int monedas = 0;
  int nivel = 1;
  String? fotoBase64;
  bool isLoading = true;

  List<QueryDocumentSnapshot> _dailyChallenges = [];
  bool _loadingChallenges = true;
  List<Map<String, dynamic>> _completedChallengesCache = [];

  bool _mostrarTodosLosLogros = false;
  Timer? _dailyResetTimer;
  Duration _timeUntilReset = Duration.zero;

  // ── Mapa en vivo ──────────────────────────────────────────────────────────
  List<TerritoryData> _territorios = [];
  bool _loadingTerritorios = true;
  final MapController _homeMapController = MapController();
  StreamSubscription<QuerySnapshot>? _invasionListener;

  // ── Territorios cercanos ──────────────────────────────────────────────────
  List<_UserTerritoryGroup> _gruposTerritoriosCercanos = [];
  bool _loadingCercanos = false;
  bool _panelCercanosExpandido = false;
  String? _userExpandido;
  final Map<String, List<_TerritoryDetail>> _detallesPorUser = {};

  // ── Notificaciones no leídas (para badge campana) ─────────────────────────
  int _notifNoLeidas = 0;
  StreamSubscription<QuerySnapshot>? _notifCountListener;

  // Animaciones
  late AnimationController _headerAnimController;
  late AnimationController _contentAnimController;
  late Animation<double> _headerFade;
  late Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();

    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _contentAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _headerFade = CurvedAnimation(
        parent: _headerAnimController, curve: Curves.easeOut);
    _contentFade = CurvedAnimation(
        parent: _contentAnimController, curve: Curves.easeIn);

    _getUserLocation();
    _initializeData();
    _escucharNotificacionesInvasion();
    _escucharConteoNotificaciones(); // ← NUEVO
  }

  @override
  void dispose() {
    _dailyResetTimer?.cancel();
    _headerAnimController.dispose();
    _contentAnimController.dispose();
    _invasionListener?.cancel();
    _notifCountListener?.cancel(); // ← NUEVO
    super.dispose();
  }

  // ── NUEVO: Escuchar conteo de notificaciones no leídas para el badge ──────
  void _escucharConteoNotificaciones() {
    if (userId == null) return;

    _notifCountListener = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() => _notifNoLeidas = snap.docs.length);
      }
    });
  }

  // ── UBICACIÓN ─────────────────────────────────────────────────────────────
  Future<void> _getUserLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        Position position = await Geolocator.getCurrentPosition();
        if (mounted) setState(() => _currentPosition = position);
      }
    } catch (e) {
      debugPrint("Error ubicación: $e");
    }
  }

  // ── INICIALIZACIÓN ────────────────────────────────────────────────────────
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
        Future.delayed(const Duration(milliseconds: 350), () {
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
            lngC,
          );
        }

        if (usarFiltroDistancia && distMetros > 5000) continue;

        final String ownerId = data['userId'] as String? ?? '';
        if (ownerId.isEmpty) continue;

        if (!grupos.containsKey(ownerId)) {
          String ownerNick = ownerId == myUid ? nickname : ownerId;
          int ownerNivel = 1;
          Color ownerColor = ownerId == myUid ? Colors.orange : Colors.blue;

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
              puntos: puntos,
            ));
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
          if (tiempoSeg != null) {
            tiempoActividad = Duration(seconds: tiempoSeg);
          }
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
            return LatLng(
              (map['lat'] as num).toDouble(),
              (map['lng'] as num).toDouble(),
            );
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
                  lngC,
                ) /
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

      if (mounted) {
        setState(() => _detallesPorUser[ownerId] = detalles);
      }
    } catch (e) {
      debugPrint("Error cargando detalles de $ownerId: $e");
    }
  }

  // ── Dialog de detalle de un territorio ───────────────────────────────────
  void _mostrarDialogTerritorio(
      _TerritoryDetail det, Color color, String ownerNickname) {
    final LatLng centro = det.puntos.isNotEmpty
        ? LatLng(
            det.puntos.map((p) => p.latitude).reduce((a, b) => a + b) /
                det.puntos.length,
            det.puntos.map((p) => p.longitude).reduce((a, b) => a + b) /
                det.puntos.length,
          )
        : const LatLng(37.1350, -3.6330);

    String estadoDeterioro = 'Activo';
    Color colorEstado = Colors.greenAccent;
    if (det.diasSinVisitar != null && det.diasSinVisitar! >= 10) {
      estadoDeterioro = 'En peligro';
      colorEstado = Colors.redAccent;
    } else if (det.diasSinVisitar != null && det.diasSinVisitar! >= 5) {
      estadoDeterioro = 'Deteriorado';
      colorEstado = Colors.amber;
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
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: color.withValues(alpha: 0.5),
                                blurRadius: 6),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ownerNickname,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white38, size: 20),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 180,
                      child: det.puntos.isEmpty
                          ? Container(
                              color: const Color(0xFF0F0F0F),
                              child: const Center(
                                child: Text('Sin ubicación',
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 12)),
                              ),
                            )
                          : FlutterMap(
                              options: MapOptions(
                                initialCenter: centro,
                                initialZoom: 15,
                                interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.none,
                                ),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.runner_risk.app',
                                ),
                                PolygonLayer(
                                  polygons: [
                                    Polygon(
                                      points: det.puntos,
                                      color: color.withValues(alpha: 0.35),
                                      borderColor: color,
                                      borderStrokeWidth: 2.5,
                                    ),
                                  ],
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: centro,
                                      width: 80,
                                      height: 22,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.7),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: color, width: 1),
                                        ),
                                        child: Text(
                                          ownerNickname,
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
                          title: 'Estado',
                          value: estadoDeterioro,
                          color: colorEstado),
                      _dialogStatCard(
                          icon: Icons.calendar_today_outlined,
                          title: 'Sin visitar',
                          value: det.diasSinVisitar != null
                              ? '${det.diasSinVisitar}d'
                              : '--',
                          color: Colors.white70),
                      _dialogStatCard(
                          icon: Icons.flag_outlined,
                          title: 'Conquistado',
                          value: det.fechaCreacion != null
                              ? _formatFecha(det.fechaCreacion!)
                              : '--',
                          color: Colors.white70,
                          smallText: true),
                      _dialogStatCard(
                          icon: Icons.straighten_outlined,
                          title: 'Distancia',
                          value: det.distanciaRecorrida != null
                              ? '${det.distanciaRecorrida!.toStringAsFixed(2)} km'
                              : '--',
                          color: Colors.lightBlueAccent),
                      _dialogStatCard(
                          icon: Icons.speed_outlined,
                          title: 'Vel. media',
                          value: det.velocidadMedia != null
                              ? '${det.velocidadMedia!.toStringAsFixed(1)} km/h'
                              : '--',
                          color: Colors.purpleAccent),
                      _dialogStatCard(
                          icon: Icons.timer_outlined,
                          title: 'Tiempo',
                          value: tiempoFormateado ?? '--',
                          color: Colors.orangeAccent),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.my_location_outlined,
                            color: Colors.white38, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'A ${det.distanciaAlCentroKm.toStringAsFixed(2)} km de tu posición',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
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
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: smallText ? 10 : 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Escuchar banner de invasión en tiempo real ────────────────────────────
  void _escucharNotificacionesInvasion() {
    if (userId == null) return;

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
            change.doc.id,
          );
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFCC0000), Color(0xFFFF4500)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.red.withValues(alpha: 0.5), blurRadius: 12),
            ],
          ),
          child: Row(
            children: [
              const Text('⚔️', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(mensaje,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
              TextButton(
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentSnackBar(),
                child: const Text('DEFENDER',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Lógica original ───────────────────────────────────────────────────────
  Future<void> _loadUserData() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('players')
        .doc(userId)
        .get();
    if (userDoc.exists && mounted) {
      final data = userDoc.data()!;
      setState(() {
        nickname = data['nickname'] ?? "Corredor";
        monedas = data['monedas'] ?? 0;
        nivel = data['nivel'] ?? 1;
        fotoBase64 = data['foto_base64'] as String?;
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

      if (mounted) setState(() => _completedChallengesCache = listaTemporal);
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
    if (mounted) {
      setState(() {
        _completedChallengesCache.clear();
        _dailyChallenges.clear();
        isLoading = true;
      });
    }
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
          .toList();

      disponibles.shuffle();

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
          .update({
        'monedas': monedas,
        'nivel': (monedas ~/ 30) + 1,
      });
    } catch (e) {
      debugPrint("Error al guardar: $e");
    }
  }

 // ── Sustituye el método _testSimularConquista en home_screen.dart ─────────────
// Busca "Future<void> _testSimularConquista()" y reemplaza todo el método por este:

  Future<void> _testSimularConquista() async {
    if (userId == null) return;

    final friendshipsSnap = await FirebaseFirestore.instance
        .collection('friendships')
        .where('status', isEqualTo: 'accepted')
        .get();

    final List<String> amigoIds = [];
    for (var doc in friendshipsSnap.docs) {
      final data = doc.data();
      if (data['senderId'] == userId) {
        amigoIds.add(data['receiverId'] as String);
      } else if (data['receiverId'] == userId) {
        amigoIds.add(data['senderId'] as String);
      }
    }

    if (amigoIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No tienes amigos con territorios para conquistar'),
          backgroundColor: Colors.redAccent,
        ));
      }
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
        // Buscar nickname del amigo
        try {
          final p = await FirebaseFirestore.instance
              .collection('players')
              .doc(amigoId)
              .get();
          if (p.exists) {
            ownerNicknameObjetivo = p.data()?['nickname'] ?? 'rival';
          }
        } catch (_) {}
        break;
      }
    }

    if (territorioObjetivo == null || ownerIdObjetivo == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tus amigos no tienen territorios aún'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }

    final dataTerritorio = territorioObjetivo.data() as Map<String, dynamic>;
    final rawPuntos = dataTerritorio['puntos'] as List<dynamic>?;
    if (rawPuntos == null || rawPuntos.isEmpty) return;

    final List<LatLng> puntos = rawPuntos.map((p) {
      final map = p as Map<String, dynamic>;
      return LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
    }).toList();

    final double latCenter =
        puntos.map((p) => p.latitude).reduce((a, b) => a + b) / puntos.length;
    final double lngCenter =
        puntos.map((p) => p.longitude).reduce((a, b) => a + b) / puntos.length;

    await FirebaseFirestore.instance
        .collection('territories')
        .doc(territorioObjetivo.id)
        .update({'userId': userId});

    // ── Notificación al dueño (territory_lost) CON territoryId ───────────
    await FirebaseFirestore.instance.collection('notifications').add({
      'toUserId': ownerIdObjetivo,
      'type': 'territory_lost',
      'message': '😤 ¡$nickname te ha robado un territorio! Sal a recuperarlo.',
      'fromNickname': nickname,
      'territoryId': territorioObjetivo.id, // ← NUEVO
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // ── Notificación al conquistador (territory_conquered) ────────────────
    await FirebaseFirestore.instance.collection('notifications').add({
      'toUserId': userId,
      'type': 'territory_conquered',
      'message': '🏴 ¡Has conquistado un territorio de $ownerNicknameObjetivo!',
      'fromNickname': ownerNicknameObjetivo,
      'territoryId': territorioObjetivo.id, // ← NUEVO
      'distancia': 2.5,
      'tiempo_segundos': 18 * 60,
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/resumen', arguments: {
        'distancia': 2.5,
        'tiempo': const Duration(minutes: 18),
        'ruta': [
          LatLng(latCenter - 0.002, lngCenter - 0.002),
          LatLng(latCenter, lngCenter),
          LatLng(latCenter + 0.002, lngCenter + 0.002),
        ],
        'esDesdeCarrera': true,
        'territoriosConquistados': 1,
      });
    }
  }

  void _testSimularCarrera() {
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

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // ── NUEVO: campana con badge de notificaciones ─────────────────
          IconButton(
            icon: Badge(
              isLabelVisible: _notifNoLeidas > 0,
              backgroundColor: Colors.redAccent,
              label: _notifNoLeidas > 9
                  ? const Text('9+', style: TextStyle(fontSize: 9))
                  : Text(
                      _notifNoLeidas.toString(),
                      style: const TextStyle(fontSize: 9),
                    ),
              child: const Icon(Icons.notifications_outlined,
                  color: Colors.orange),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const NotificationsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orange),
            onPressed: _initializeData,
          ),
          _buildUserMenu(),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orange))
          : RefreshIndicator(
              onRefresh: _initializeData,
              color: Colors.orange,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FadeTransition(
                      opacity: _headerFade,
                      child: _buildMapHeader(screenHeight),
                    ),
                    FadeTransition(
                      opacity: _contentFade,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 24),
                            _buildStatsRow(),
                            const SizedBox(height: 28),
                            _buildTestButton(),
                            const SizedBox(height: 8),
                            _buildTestConquistaButton(),
                            const SizedBox(height: 32),
                            _buildSectionHeader(
                              "ESTADO DE LA GUERRA",
                              Icons.map_rounded,
                              "Ver todo",
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullscreenMapScreen(
                                    territorios: _territorios,
                                    colorTerritorio: Colors.orange,
                                    centroInicial: _currentPosition != null
                                        ? LatLng(_currentPosition!.latitude,
                                            _currentPosition!.longitude)
                                        : const LatLng(37.1350, -3.6330),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildMapaEnVivo(),
                            const SizedBox(height: 32),
                            _buildSectionHeader(
                              "LOGROS DE HOY",
                              Icons.emoji_events_outlined,
                              _completedChallengesCache.length > 3
                                  ? (_mostrarTodosLosLogros
                                      ? "Ver menos"
                                      : "Ver todos (${_completedChallengesCache.length})")
                                  : "",
                              () => setState(() => _mostrarTodosLosLogros =
                                  !_mostrarTodosLosLogros),
                            ),
                            const SizedBox(height: 12),
                            _buildCompletedChallengesList(),
                            const SizedBox(height: 32),
                            _buildSectionHeader(
                                "MISIONES DEL DÍA", Icons.bolt_outlined, "",
                                null),
                            const SizedBox(height: 6),
                            _buildDailyResetTimer(),
                            const SizedBox(height: 12),
                            _buildDailyChallengesList(),
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: const CustomBottomNavbar(currentIndex: 0),
    );
  }

  // ── MAPA EN VIVO ──────────────────────────────────────────────────────────
  Widget _buildMapaEnVivo() {
    final LatLng centro = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(37.1350, -3.6330);

    final miosTotales = _territorios.where((t) => t.esMio).length;
    final deteriorados =
        _territorios.where((t) => t.esMio && t.estaDeterirado).length;
    final enPeligro =
        _territorios.where((t) => t.esMio && t.esConquistableSinPasar).length;

    return Column(
      children: [
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullscreenMapScreen(
                territorios: _territorios,
                colorTerritorio: Colors.orange,
                centroInicial: centro,
              ),
            ),
          ),
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _loadingTerritorios
                  ? Container(
                      color: const Color(0xFF0F0F0F),
                      child: const Center(
                        child: CircularProgressIndicator(
                            color: Colors.orange, strokeWidth: 2),
                      ),
                    )
                  : Stack(
                      children: [
                        FlutterMap(
                          mapController: _homeMapController,
                          options: MapOptions(
                            initialCenter: centro,
                            initialZoom: 14,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.runner_risk.app',
                            ),
                            if (_territorios.isNotEmpty)
                              PolygonLayer(
                                polygons: _territorios.map((t) {
                                  return Polygon(
                                    points: t.puntos,
                                    color: t.color.withValues(
                                        alpha: t.opacidadRelleno),
                                    borderColor: t.color
                                        .withValues(alpha: t.opacidadBorde),
                                    borderStrokeWidth:
                                        t.estaDeterirado ? 1.5 : 2.5,
                                  );
                                }).toList(),
                              ),
                            if (_territorios.isNotEmpty)
                              MarkerLayer(
                                markers: _territorios.map((t) {
                                  return Marker(
                                    point: t.centro,
                                    width: 80,
                                    height: 22,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.65),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                            color: t.color, width: 1),
                                      ),
                                      child: Text(
                                        t.esMio ? 'YO' : t.ownerNickname,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: t.color,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            if (_currentPosition != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(
                                        _currentPosition!.latitude,
                                        _currentPosition!.longitude),
                                    width: 16,
                                    height: 16,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.blue
                                                .withValues(alpha: 0.4),
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.fullscreen,
                                color: Colors.orange, size: 16),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildTerritoryStatChip(
                "$miosTotales", "míos", Icons.flag_rounded, Colors.orange),
            const SizedBox(width: 8),
            if (deteriorados > 0)
              _buildTerritoryStatChip("$deteriorados", "deteriorados",
                  Icons.warning_amber_rounded, Colors.amber),
            if (deteriorados > 0) const SizedBox(width: 8),
            if (enPeligro > 0)
              _buildTerritoryStatChip("$enPeligro", "en peligro",
                  Icons.dangerous_rounded, Colors.redAccent),
          ],
        ),
        const SizedBox(height: 10),
        _buildBotonTerritoriosCercanos(),
        if (_panelCercanosExpandido) _buildPanelCercanos(),
        if (deteriorados > 0 || enPeligro > 0)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined,
                    color: Colors.redAccent, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    enPeligro > 0
                        ? '⚠️ Tienes $enPeligro ${enPeligro == 1 ? 'territorio' : 'territorios'} que cualquiera puede conquistar. ¡Sal a defenderlos!'
                        : '⚠️ $deteriorados ${deteriorados == 1 ? 'territorio debilitado' : 'territorios debilitados'}. Visítalos antes de que los pierdan.',
                    style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBotonTerritoriosCercanos() {
    final int totalMostrado = _gruposTerritoriosCercanos.isEmpty
        ? _territorios.length
        : _gruposTerritoriosCercanos
            .fold<int>(0, (s, g) => s + g.territorios.length);

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: Colors.greenAccent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            _loadingCercanos
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: Colors.orange, strokeWidth: 2),
                  )
                : Text(
                    _panelCercanosExpandido
                        ? '$totalMostrado territorios en zona (5 km) ▲'
                        : '$totalMostrado territorios en zona (5 km) ▼',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
            const Spacer(),
            const Icon(Icons.people_alt_outlined,
                color: Colors.white38, size: 15),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelCercanos() {
    if (_gruposTerritoriosCercanos.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: const Text(
          'No hay territorios de otros jugadores en 5 km',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: _gruposTerritoriosCercanos.asMap().entries.map((entry) {
          final index = entry.key;
          final grupo = entry.value;
          final isExpanded = _userExpandido == grupo.ownerId;
          final detalles = _detallesPorUser[grupo.ownerId];
          final isLast = index == _gruposTerritoriosCercanos.length - 1;

          return Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
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
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: grupo.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          grupo.esMio
                              ? '${grupo.nickname} (tú)'
                              : grupo.nickname,
                          style: TextStyle(
                            color: grupo.esMio
                                ? Colors.orange
                                : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: grupo.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'NIV. ${grupo.nivel}',
                          style: TextStyle(
                            color: grupo.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${grupo.territorios.length} 🏴',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                      const SizedBox(width: 6),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded)
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: grupo.color.withValues(alpha: 0.2)),
                  ),
                  child: detalles == null
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                                color: Colors.orange, strokeWidth: 2),
                          ),
                        )
                      : detalles.isEmpty
                          ? const Text('Sin territorios',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12))
                          : Column(
                              children: detalles
                                  .asMap()
                                  .entries
                                  .map((e) => _buildTerritoryDetailCard(
                                      e.key,
                                      e.value,
                                      grupo.color,
                                      grupo.esMio
                                          ? 'YO'
                                          : grupo.nickname))
                                  .toList(),
                            ),
                ),
              if (!isLast)
                Divider(
                    color: Colors.white.withValues(alpha: 0.05), height: 1),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTerritoryDetailCard(
      int index, _TerritoryDetail det, Color color, String ownerNickname) {
    String estadoDeterioro = 'Activo';
    Color colorEstado = Colors.greenAccent;
    if (det.diasSinVisitar != null && det.diasSinVisitar! >= 10) {
      estadoDeterioro = 'En peligro';
      colorEstado = Colors.redAccent;
    } else if (det.diasSinVisitar != null && det.diasSinVisitar! >= 5) {
      estadoDeterioro = 'Deteriorado';
      colorEstado = Colors.amber;
    }

    return GestureDetector(
      onTap: () => _mostrarDialogTerritorio(det, color, ownerNickname),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.crop_square_rounded, color: color, size: 14),
            const SizedBox(width: 8),
            Text(
              'Territorio #${index + 1}',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: colorEstado.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(estadoDeterioro,
                  style: TextStyle(
                      color: colorEstado,
                      fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            Text('${det.distanciaAlCentroKm.toStringAsFixed(1)} km',
                style:
                    const TextStyle(color: Colors.white38, fontSize: 10)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                color: color.withValues(alpha: 0.5), size: 16),
          ],
        ),
      ),
    );
  }

  String _formatFecha(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  Widget _buildTerritoryStatChip(
      String valor, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text("$valor $label",
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildMapHeader(double screenHeight) {
    return SizedBox(
      height: screenHeight * 0.38,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/Mapa_risk.png', fit: BoxFit.cover),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xBB000000),
                  Color(0x66000000),
                  Color(0xDD000000),
                  Colors.black,
                ],
                stops: [0.0, 0.35, 0.75, 1.0],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.5),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                      border: Border.all(color: Colors.orange, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.black,
                      child: ClipOval(
                        child: fotoBase64 != null
                            ? Image.memory(base64Decode(fotoBase64!),
                                fit: BoxFit.cover, width: 64, height: 64)
                            : const Icon(Icons.person,
                                color: Colors.white, size: 36),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          nickname.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text("NIV. $nivel",
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1)),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "CONQUISTA TU TERRITORIO",
                              style: TextStyle(
                                  color:
                                      Colors.orange.withValues(alpha: 0.7),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
            child: _buildStatCard("NIVEL", nivel.toString(),
                Icons.military_tech_rounded, Colors.orange)),
        const SizedBox(width: 14),
        Expanded(
            child: _buildStatCard("MONEDAS", monedas.toString(),
                Icons.stars_rounded, const Color(0xFFFFD700))),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      shadows: [
                        Shadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 8)
                      ])),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
      String title, IconData icon, String action, VoidCallback? onAction) {
    return Row(
      children: [
        Icon(icon, color: Colors.orange, size: 18),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 2)),
        const Spacer(),
        if (action.isNotEmpty)
          GestureDetector(
            onTap: onAction,
            child: Text(action,
                style: TextStyle(
                    color: Colors.orange.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _buildDailyResetTimer() {
    final h = _timeUntilReset.inHours.toString().padLeft(2, '0');
    final m =
        _timeUntilReset.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s =
        _timeUntilReset.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Row(
      children: [
        const Icon(Icons.timer_outlined, color: Colors.white24, size: 13),
        const SizedBox(width: 5),
        Text("Reset en $h:$m:$s",
            style: const TextStyle(
                color: Colors.white24, fontSize: 11, letterSpacing: 1)),
      ],
    );
  }

  Widget _buildCompletedChallengesList() {
    if (_completedChallengesCache.isEmpty) {
      return _buildEmptyState(
          "Ningún reto completado hoy todavía", Icons.hourglass_empty_rounded);
    }
    final lista = _mostrarTodosLosLogros
        ? _completedChallengesCache
        : _completedChallengesCache.take(3).toList();

    return Column(
      children: lista.map((data) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Colors.amber.withValues(alpha: 0.2), width: 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.emoji_events_rounded,
                    color: Colors.amber, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(data['titulo'] ?? "Reto completado",
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text("+${data['recompensa']}",
                    style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDailyChallengesList() {
    if (_loadingChallenges) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.orange));
    }
    if (_dailyChallenges.isEmpty) {
      return _buildEmptyState("¡Todos los desafíos completados!",
          Icons.check_circle_outline_rounded);
    }
    return Column(
      children: _dailyChallenges.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return GestureDetector(
          onTap: () => _finalizarActividad(
              doc.id, data['titulo'], data['recompensas_monedas']),
          child: _buildMissionCard(data['titulo'], data['descripcion'],
              data['recompensas_monedas'].toString()),
        );
      }).toList(),
    );
  }

  Widget _buildMissionCard(String title, String desc, String reward) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.orange.withValues(alpha: 0.15), width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.orange.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.bolt_rounded,
                color: Colors.orange, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 3),
                Text(desc,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              Text("+$reward",
                  style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w900,
                      fontSize: 16)),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white24, size: 18),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white24, size: 16),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildTestButton() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 5),
      child: OutlinedButton.icon(
        onPressed: _testSimularCarrera,
        icon: const Text("🧪", style: TextStyle(fontSize: 16)),
        label: const Text("TEST — Simular carrera y ver territorio",
            style: TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.orange,
          side: BorderSide(color: Colors.orange.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildTestConquistaButton() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 5),
      child: OutlinedButton.icon(
        onPressed: _testSimularConquista,
        icon: const Text("⚔️", style: TextStyle(fontSize: 16)),
        label: const Text("TEST — Conquistar territorio de amigo",
            style: TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.redAccent,
          side:
              BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildUserMenu() => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.orange),
        onSelected: (value) async {
          if (value == 'logout') {
            try {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/login', (route) => false);
              }
            } catch (e) {
              debugPrint("Error al cerrar sesión: $e");
            }
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'logout',
            child: Row(
              children: [
                Icon(Icons.logout, color: Colors.redAccent, size: 20),
                SizedBox(width: 10),
                Text('Cerrar sesión',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ],
      );
}

// ── Modelos auxiliares ────────────────────────────────────────────────────────

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