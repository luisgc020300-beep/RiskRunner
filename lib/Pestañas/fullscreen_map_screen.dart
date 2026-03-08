import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/territory_service.dart';

// ── Pon aquí tu token de Mapbox ───────────────────────────────────────────────
const String _kMapboxToken = 'pk.eyJ1IjoibHVpaXNnb29tZXp6MSIsImEiOiJjbW1keTI1bjkwN25qMm9zNzFlOXZkeG9wIn0.l186BxbIhi6-vAXtBjIzsw';
const String _kMapboxUrl =
    'https://api.mapbox.com/styles/v1/luiisgoomezz1/cmmdzh1aj00f501r68crag5gv'
    '/tiles/256/{z}/{x}/{y}@2x?access_token=$_kMapboxToken';

class FullscreenMapScreen extends StatefulWidget {
  final List<TerritoryData> territorios;
  final Color colorTerritorio;
  final List<LatLng> ruta;
  final LatLng centroInicial;
  final bool mostrarRuta;

  const FullscreenMapScreen({
    super.key,
    required this.territorios,
    required this.colorTerritorio,
    required this.centroInicial,
    this.ruta = const [],
    this.mostrarRuta = false,
  });

  @override
  State<FullscreenMapScreen> createState() => _FullscreenMapScreenState();
}

class _FullscreenMapScreenState extends State<FullscreenMapScreen> {
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final bool tieneRutaValida = widget.ruta.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.centroInicial,
              initialZoom: 14,
              minZoom: 3,
              maxZoom: 19,
              onMapReady: () {
                if (tieneRutaValida && widget.mostrarRuta) {
                  _mapController.fitCamera(
                    CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(widget.ruta),
                      padding: const EdgeInsets.all(60),
                    ),
                  );
                } else if (widget.territorios.isNotEmpty) {
                  final todosLosPuntos =
                      widget.territorios.expand((t) => t.puntos).toList();
                  if (todosLosPuntos.isNotEmpty) {
                    _mapController.fitCamera(
                      CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(todosLosPuntos),
                        padding: const EdgeInsets.all(60),
                      ),
                    );
                  }
                }
              },
            ),
            children: [
              // ── MAPA ACUARELA MAPBOX (mismo estilo que LiveActivity) ──────
              TileLayer(
                urlTemplate: _kMapboxUrl,
                userAgentPackageName: 'com.runner_risk.app',
                tileSize: 256,
              ),

              // ── Polígonos con color/opacidad real de TerritoryData ────────
              if (widget.territorios.isNotEmpty)
                PolygonLayer(
                  polygons: widget.territorios.map((t) {
                    return Polygon(
                      points: t.puntos,
                      color: t.color.withValues(alpha: t.opacidadRelleno),
                      borderColor:
                          t.color.withValues(alpha: t.opacidadBorde),
                      borderStrokeWidth: t.estaDeterirado ? 1.5 : 3.0,
                    );
                  }).toList(),
                ),

              // ── Nicknames sobre territorios ──────────────────────────────
              if (widget.territorios.isNotEmpty)
                MarkerLayer(
                  markers: widget.territorios.map((t) {
                    final String label = t.esMio ? 'YO' : t.ownerNickname;
                    return Marker(
                      point: t.centro,
                      width: 100,
                      height: 26,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: t.color, width: 1.5),
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.color,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

              // ── Ruta de carrera ──────────────────────────────────────────
              if (tieneRutaValida && widget.mostrarRuta)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: widget.ruta,
                      strokeWidth: 4.0,
                      color: Colors.orange,
                    ),
                  ],
                ),
            ],
          ),

          // ── Botón cerrar ─────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.fullscreen_exit,
                    color: Colors.orange, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }
}