import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MiniMapaNotif extends StatelessWidget {
  final List<LatLng> puntos;
  final LatLng centro;
  final Color color;
  final String label;

  const MiniMapaNotif({
    super.key,
    required this.puntos,
    required this.centro,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: centro,
        initialZoom: 15,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.tuapp.juego',
        ),
        PolygonLayer(
          polygons: [
            Polygon(
              points: puntos,
              // El relleno se aplica automáticamente al poner un color aquí
              color: color.withOpacity(0.3), 
              borderStrokeWidth: 3,
              borderColor: color,
              // isFilled: true, <-- ESTA LÍNEA SOBRA Y DA ERROR
            ),
          ],
        ),
      ],
    );
  }
}