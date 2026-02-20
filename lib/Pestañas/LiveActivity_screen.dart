import 'dart:async';
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

void stopTracking() {
    _timerController.pause();
    positionStream?.cancel();

    // 1. Capturamos los datos
    final Duration tiempoFinal = _timerController.remaining.value.duration;
    final List<LatLng> rutaFinal = List<LatLng>.from(routePoints);
    final double distanciaFinal = _distanciaTotal;

    // 2. Avisamos al Wrapper (por si acaso guarda los datos)
    if (widget.onFinish != null) {
      widget.onFinish!(distanciaFinal, tiempoFinal, rutaFinal);
    }

    // 3. LA SOLUCIÓN DEFINITIVA: Forzamos el salto de pantalla por ruta
    // Esto te saca de aquí aunque el Wrapper no quiera
 Navigator.of(context).push(MaterialPageRoute(
  builder: (context) => ResumenScreen(
    distancia: distanciaFinal,
    tiempo: tiempoFinal,
    ruta: rutaFinal,
  ),
));
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