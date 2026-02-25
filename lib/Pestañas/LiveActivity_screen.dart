import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:custom_timer/custom_timer.dart';

import '../services/territory_service.dart';

class LiveActivityScreen extends StatefulWidget {
  final Function(double distancia, Duration tiempo, List<LatLng> ruta)? onFinish;
  const LiveActivityScreen({super.key, this.onFinish});

  @override
  State<LiveActivityScreen> createState() => _LiveActivityScreenState();
}

class _LiveActivityScreenState extends State<LiveActivityScreen>
    with TickerProviderStateMixin {
  late final CustomTimerController _timerController = CustomTimerController(
    vsync: this,
    begin: const Duration(),
    end: const Duration(hours: 24),
    initialState: CustomTimerState.reset,
    interval: CustomTimerInterval.milliseconds,
  );

  final Stopwatch _stopwatch = Stopwatch();
  final MapController _mapController = MapController();
  List<LatLng> routePoints = [];
  bool isTracking = false;
  bool isPaused = false;
  double _distanciaTotal = 0.0;
  StreamSubscription<Position>? positionStream;
  Position? _currentPosition;

  List<TerritoryData> _territorios = [];
  bool _territoriosCargados = false;
  String _miNickname = 'Alguien';

  final Set<String> _territoriosNotificadosEnSesion = {};
  final Set<String> _territoriosVisitadosEnSesion = {};

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _cargarDatosIniciales();
  }

  @override
  void dispose() {
    _timerController.dispose();
    positionStream?.cancel();
    super.dispose();
  }

  Future<void> _cargarDatosIniciales() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final myDoc = await FirebaseFirestore.instance
          .collection('players')
          .doc(user.uid)
          .get();
      if (myDoc.exists) {
        _miNickname = myDoc.data()?['nickname'] ?? 'Alguien';
      }
      final lista = await TerritoryService.cargarTodosLosTerritorios();
      if (mounted) {
        setState(() {
          _territorios = lista;
          _territoriosCargados = true;
        });
      }
    } catch (e) {
      debugPrint("Error cargando datos iniciales: $e");
    }
  }

  Future<void> _determinePosition() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _currentPosition = position);
        _mapController.move(LatLng(position.latitude, position.longitude), 15);
      }
    }
  }

  void startTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    setState(() {
      isTracking = true;
      isPaused = false;
      _distanciaTotal = 0.0;
      routePoints.clear();
      _territoriosNotificadosEnSesion.clear();
      _territoriosVisitadosEnSesion.clear();
    });

    _stopwatch.reset();
    _stopwatch.start();
    _timerController.start();

    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (Position position) {
        if (!isPaused && mounted) {
          final LatLng newPoint = LatLng(position.latitude, position.longitude);
          setState(() {
            if (routePoints.isNotEmpty) {
              _distanciaTotal += Geolocator.distanceBetween(
                    routePoints.last.latitude,
                    routePoints.last.longitude,
                    newPoint.latitude,
                    newPoint.longitude,
                  ) /
                  1000;
            }
            routePoints.add(newPoint);
            _currentPosition = position;
          });
          _mapController.move(newPoint, 15);
          _procesarPosicionEnTerritorios(newPoint);
        }
      },
      onError: (e) => debugPrint("GPS error (ignorado en web): $e"),
    );
  }

  void _procesarPosicionEnTerritorios(LatLng posicion) {
    if (_territorios.isEmpty) return;
    final TerritoryData? territorioActual =
        TerritoryService.territorioEnPosicion(_territorios, posicion);
    if (territorioActual == null) return;

    if (territorioActual.esMio) {
      if (!_territoriosVisitadosEnSesion.contains(territorioActual.docId)) {
        _territoriosVisitadosEnSesion.add(territorioActual.docId);
        TerritoryService.actualizarUltimaVisita(territorioActual.docId);
        _mostrarSnackRefuerzo();
      }
    } else {
      if (!_territoriosNotificadosEnSesion.contains(territorioActual.docId)) {
        _territoriosNotificadosEnSesion.add(territorioActual.docId);
        TerritoryService.crearNotificacionInvasion(
          toUserId: territorioActual.ownerId,
          fromNickname: _miNickname,
          territoryId: territorioActual.docId,
        );
        _mostrarSnackInvasion(territorioActual.ownerNickname);
      }
    }
  }

  void _mostrarSnackInvasion(String ownerNick) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFCC0000), Color(0xFFFF4500)]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.red.withValues(alpha: 0.4), blurRadius: 10)
            ],
          ),
          child: Row(
            children: [
              const Text('⚔️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¡Estás invadiendo el territorio de $ownerNick!',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarSnackRefuerzo() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
          ),
          child: const Row(
            children: [
              Icon(Icons.shield_rounded, color: Colors.orange, size: 18),
              SizedBox(width: 10),
              Text('¡Territorio reforzado!',
                  style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  void togglePause() {
    setState(() {
      isPaused = !isPaused;
      if (isPaused) {
        _timerController.pause();
        _stopwatch.stop();
      } else {
        _timerController.start();
        _stopwatch.start();
      }
    });
  }

  Future<void> stopTracking() async {
    _stopwatch.stop();
    _timerController.pause();
    positionStream?.cancel();

    final Duration tiempoFinal = _stopwatch.elapsed;
    final List<LatLng> rutaFinal = List<LatLng>.from(routePoints);
    final double distanciaFinal = _distanciaTotal;

    if (mounted) setState(() { isTracking = false; isPaused = false; });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('activity_logs').add({
          'userId': user.uid,
          'distancia': distanciaFinal,
          'tiempo_segundos': tiempoFinal.inSeconds,
          'timestamp': FieldValue.serverTimestamp(),
          'titulo': 'Carrera Libre',
          'fecha_dia':
              "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}",
        });
      }
    } catch (e) {
      debugPrint("Error guardando activity_log: $e");
    }

    final int territoriosConquistados =
        await _procesarConquistas(rutaFinal, tiempoFinal, distanciaFinal);

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/resumen', arguments: {
        'distancia': distanciaFinal,
        'tiempo': tiempoFinal,
        'ruta': rutaFinal,
        'esDesdeCarrera': true,
        'territoriosConquistados': territoriosConquistados,
      });
    }
  }

  // ── Conquistas al terminar ── ahora con territoryId en notificación ───────
  Future<int> _procesarConquistas(
      List<LatLng> ruta, Duration tiempo, double distancia) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || ruta.isEmpty || _territorios.isEmpty) return 0;

    int conquistados = 0;
    final territoriosAmigos = _territorios.where((t) => !t.esMio).toList();

    for (final territorio in territoriosAmigos) {
      final bool pasoPorEl = _rutaPasaPorPoligono(ruta, territorio.puntos);
      final bool conquistablePorDeterioro =
          territorio.esConquistableSinPasar &&
              _rutaPasaCercaDe(ruta, territorio.centro, radioMetros: 200);

      if (pasoPorEl || conquistablePorDeterioro) {
        try {
          await FirebaseFirestore.instance
              .collection('territories')
              .doc(territorio.docId)
              .update({
            'userId': user.uid,
            'ultima_visita': FieldValue.serverTimestamp(),
          });

          // ── Notificación al dueño (territory_lost) CON territoryId ─────
          await FirebaseFirestore.instance.collection('notifications').add({
            'toUserId': territorio.ownerId,
            'type': 'territory_lost',
            'message':
                '😤 ¡$_miNickname te ha robado un territorio! Sal a recuperarlo.',
            'fromNickname': _miNickname,
            'territoryId': territorio.docId, // ← NUEVO
            'read': false,
            'timestamp': FieldValue.serverTimestamp(),
          });

          // ── Notificación al conquistador (territory_conquered) ─────────
          await FirebaseFirestore.instance.collection('notifications').add({
            'toUserId': user.uid,
            'type': 'territory_conquered',
            'message':
                '🏴 ¡Has conquistado un territorio de ${territorio.ownerNickname}!',
            'fromNickname': territorio.ownerNickname,
            'territoryId': territorio.docId, // ← NUEVO
            'distancia': distancia,
            'tiempo_segundos': tiempo.inSeconds,
            'read': false,
            'timestamp': FieldValue.serverTimestamp(),
          });

          conquistados++;
          debugPrint("🏴 Conquistado ${territorio.docId}");
        } catch (e) {
          debugPrint("Error conquistando ${territorio.docId}: $e");
        }
      }
    }
    return conquistados;
  }

  bool _rutaPasaPorPoligono(List<LatLng> ruta, List<LatLng> poligono) {
    for (final punto in ruta) {
      if (_puntoEnPoligono(punto, poligono)) return true;
    }
    return false;
  }

  bool _puntoEnPoligono(LatLng punto, List<LatLng> poligono) {
    int intersecciones = 0;
    final int n = poligono.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final double xi = poligono[i].longitude;
      final double yi = poligono[i].latitude;
      final double xj = poligono[j].longitude;
      final double yj = poligono[j].latitude;
      final bool cruza = ((yi > punto.latitude) != (yj > punto.latitude)) &&
          (punto.longitude <
              (xj - xi) * (punto.latitude - yi) / (yj - yi) + xi);
      if (cruza) intersecciones++;
    }
    return intersecciones % 2 == 1;
  }

  bool _rutaPasaCercaDe(List<LatLng> ruta, LatLng objetivo,
      {required double radioMetros}) {
    for (final punto in ruta) {
      final double distancia = Geolocator.distanceBetween(
          punto.latitude, punto.longitude,
          objetivo.latitude, objetivo.longitude);
      if (distancia <= radioMetros) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final territoriosPropios = _territorios.where((t) => t.esMio).toList();
    final territoriosAmigos = _territorios.where((t) => !t.esMio).toList();
    final int totalTerritorios = _territorios.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition != null
                  ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                  : const LatLng(40.4167, -3.70325),
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.runner_risk.app',
              ),
              if (territoriosAmigos.isNotEmpty)
                PolygonLayer(
                  polygons: territoriosAmigos.map((t) => Polygon(
                    points: t.puntos,
                    color: t.color.withValues(alpha: t.opacidadRelleno),
                    borderColor: t.color.withValues(alpha: t.opacidadBorde),
                    borderStrokeWidth: t.estaDeterirado ? 1.5 : 2.5,
                  )).toList(),
                ),
              if (territoriosPropios.isNotEmpty)
                PolygonLayer(
                  polygons: territoriosPropios.map((t) => Polygon(
                    points: t.puntos,
                    color: t.color.withValues(alpha: t.opacidadRelleno),
                    borderColor: t.color.withValues(alpha: t.opacidadBorde),
                    borderStrokeWidth: 3,
                  )).toList(),
                ),
              if (_territorios.isNotEmpty)
                MarkerLayer(
                  markers: _territorios.map((t) => Marker(
                    point: t.centro,
                    width: 120,
                    height: 30,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.color, width: 1.5),
                      ),
                      child: Text(
                        t.esMio ? 'YO' : t.ownerNickname,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.color, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  )).toList(),
                ),
              if (routePoints.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(points: routePoints, strokeWidth: 5, color: Colors.orange),
                ]),
              if (_currentPosition != null)
                MarkerLayer(markers: [
                  Marker(
                    point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.4), blurRadius: 8)],
                      ),
                    ),
                  ),
                ]),
            ],
          ),

          // HUD stats
          Positioned(
            top: 60, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn(_distanciaTotal.toStringAsFixed(2), "KM"),
                  _buildStatColumn(!isTracking ? "LISTO" : (isPaused ? "PAUSA" : "VIVO"), "STATUS"),
                  _buildStatColumn("${(_distanciaTotal * 10).toInt()}", "PTOS"),
                ],
              ),
            ),
          ),

          // Indicador territorios en zona
          if (_territoriosCargados)
            Positioned(
              top: 160, left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(
                      totalTerritorios == 0 ? 'Sin territorios en zona' : '$totalTerritorios territorios en zona',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),

          // Indicador reforzados
          if (isTracking && _territoriosVisitadosEnSesion.isNotEmpty)
            Positioned(
              top: 200, left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_rounded, color: Colors.orange, size: 12),
                    const SizedBox(width: 6),
                    Text(
                      '${_territoriosVisitadosEnSesion.length} ${_territoriosVisitadosEnSesion.length == 1 ? 'territorio reforzado' : 'territorios reforzados'}',
                      style: const TextStyle(color: Colors.orange, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),

          // Indicador invadidos
          if (isTracking && _territoriosNotificadosEnSesion.isNotEmpty)
            Positioned(
              top: _territoriosVisitadosEnSesion.isNotEmpty ? 240 : 200,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⚔️', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 6),
                    Text(
                      '${_territoriosNotificadosEnSesion.length} ${_territoriosNotificadosEnSesion.length == 1 ? 'territorio invadido' : 'territorios invadidos'}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),

          // Timer
          if (isTracking)
            Align(
              alignment: Alignment.center,
              child: IgnorePointer(
                child: CustomTimer(
                  controller: _timerController,
                  builder: (state, remaining) {
                    return Text(
                      "${remaining.hours}:${remaining.minutes}:${remaining.seconds}",
                      style: const TextStyle(
                        fontSize: 65, fontWeight: FontWeight.bold, color: Colors.white,
                        shadows: [Shadow(blurRadius: 15, color: Colors.black)],
                      ),
                    );
                  },
                ),
              ),
            ),

          // Botonera
          Positioned(
            bottom: 60, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isTracking)
                  ElevatedButton(
                    onPressed: startTracking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
                    ),
                    child: const Text("EMPEZAR ACTIVIDAD",
                        style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                  )
                else ...[
                  GestureDetector(
                    onTap: togglePause,
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: const BoxDecoration(color: Color(0xFF1A1A1A), shape: BoxShape.circle),
                      child: Icon(isPaused ? Icons.play_arrow : Icons.pause, color: Colors.orange, size: 35),
                    ),
                  ),
                  const SizedBox(width: 25),
                  ElevatedButton.icon(
                    onPressed: stopTracking,
                    icon: const Icon(Icons.stop, color: Colors.white),
                    label: const Text("TERMINAR",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}