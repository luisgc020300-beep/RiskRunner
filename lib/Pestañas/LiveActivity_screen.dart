import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:custom_timer/custom_timer.dart';
import 'Resumen_screen.dart';

class LiveActivityScreen extends StatefulWidget {
  final Function(double, Duration, List<LatLng>)? onFinish;

  const LiveActivityScreen({super.key, this.onFinish});

  @override
  State<LiveActivityScreen> createState() => _LiveActivityScreenState();
}

class _LiveActivityScreenState extends State<LiveActivityScreen> with TickerProviderStateMixin {
  late final CustomTimerController _timerController = CustomTimerController(
    vsync: this,
    begin: const Duration(),
    end: const Duration(hours: 24),
    initialState: CustomTimerState.reset,
    interval: CustomTimerInterval.milliseconds,
  );

  final MapController _mapController = MapController(); 

  List<LatLng> routePoints = [];
  bool isTracking = false;
  bool isPaused = false;
  double _distanciaTotal = 0.0; 
  StreamSubscription<Position>? positionStream;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _determinePosition(); 
  }

  Future<void> _determinePosition() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
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
    });
    
    _timerController.start();

    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high, 
        distanceFilter: 5
      ),
    ).listen((Position position) {
      if (!isPaused && mounted) {
        LatLng newPoint = LatLng(position.latitude, position.longitude);
        
        setState(() {
          if (routePoints.isNotEmpty) {
            double meters = Geolocator.distanceBetween(
              routePoints.last.latitude,
              routePoints.last.longitude,
              newPoint.latitude,
              newPoint.longitude,
            );
            _distanciaTotal += meters / 1000;
          }
          routePoints.add(newPoint);
          _currentPosition = position;
        });
        
        _mapController.move(newPoint, 15);
      }
    });
  }

  void togglePause() {
    setState(() {
      isPaused = !isPaused;
      isPaused ? _timerController.pause() : _timerController.start();
    });
  }

Future<void> stopTracking() async {
  // 1. DETENCIÓN DE SERVICIOS
  // Detenemos el cronómetro y la escucha del GPS inmediatamente
  _timerController.pause();
  positionStream?.cancel();

  // 2. CAPTURA Y CÁLCULO DE DATOS FINALES
  // Extraemos los valores actuales antes de limpiar el estado
  final Duration tiempoFinal = _timerController.remaining.value.duration;
  final List<LatLng> rutaFinal = List<LatLng>.from(routePoints);
  final double distanciaFinal = _distanciaTotal;
  // Cálculo de puntos: 10 monedas por cada kilómetro
  final int monedasGanadas = (distanciaFinal * 10).toInt();

  // 3. PERSISTENCIA EN FIREBASE
  // Solo guardamos si hay un usuario autenticado y si realmente se ha movido
  final user = FirebaseAuth.instance.currentUser;
  if (user != null && distanciaFinal > 0) {
    try {
      // A. Creamos el registro en el historial (activity_logs)
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user.uid,
        'titulo': 'Sesión de carrera',
        'recompensa': monedasGanadas,
        'distancia': distanciaFinal,
        'tiempo_segundos': tiempoFinal.inSeconds,
        'timestamp': FieldValue.serverTimestamp(), // Hora del servidor
        'fecha_dia': "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}",
      });

      // B. Actualizamos el saldo total del jugador (players)
      // Usamos increment para evitar errores de sincronización
      await FirebaseFirestore.instance.collection('players').doc(user.uid).update({
        'monedas': FieldValue.increment(monedasGanadas),
      });
      
      debugPrint("Datos guardados exitosamente en Firebase");
    } catch (e) {
      debugPrint("Error crítico al guardar en Firebase: $e");
      // Opcional: podrías mostrar un SnackBar aquí si falla el guardado
    }
  }

  // 4. COMUNICACIÓN CON EL WRAPPER (Si existe)
  if (widget.onFinish != null) {
    widget.onFinish!(distanciaFinal, tiempoFinal, rutaFinal);
  }

  // 5. NAVEGACIÓN A LA PANTALLA DE RESUMEN
  // El chequeo 'mounted' asegura que la pantalla aún existe antes de navegar
  if (mounted) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ResumenScreen(
          distancia: distanciaFinal,
          tiempo: tiempoFinal,
          ruta: rutaFinal,
        ),
      ),
    );
  }
}

  @override
  void dispose() {
    _timerController.dispose();
    positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              if (routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routePoints,
                      strokeWidth: 5,
                      color: Colors.orange,
                    ),
                  ],
                ),
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn(_distanciaTotal.toStringAsFixed(2), "KM"),
                  _buildStatColumn(
                    !isTracking ? "LISTO" : (isPaused ? "PAUSA" : "VIVO"), 
                    "STATUS"
                  ),
                  _buildStatColumn("${(_distanciaTotal * 10).toInt()}", "PTOS"),
                ],
              ),
            ),
          ),
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
                        fontSize: 65,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [Shadow(blurRadius: 15, color: Colors.black)],
                      ),
                    );
                  },
                ),
              ),
            ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
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