import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/territory_service.dart';
import '../../pestañas/fullscreen_map_screen.dart';
import '../../config/env.dart';

const _kBorder2  = Color(0xFFD1D1D6);
const _kGrey     = Color(0xFF636366);
const _kWhite    = Color(0xFF1C1C1E);

const _kMapboxToken   = Env.mapboxPublicToken;
const _kMapboxTileUrl =
    'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12'
    '/tiles/512/{z}/{x}/{y}@2x?access_token=$_kMapboxToken';

class ResumenMapSection extends StatelessWidget {
  final List<LatLng>        ruta;
  final bool                modoRuta;
  final bool                esDesdeCarrera;
  final List<TerritoryData> territoriosEnMapa;
  final Color               acento;
  final LatLng              centroMapa;
  final MapController       mapController;
  final Animation<double>   rutaProgress;
  final int                 territoriosConquistados;
  final String              sectionLabel;
  final String              modoInicial;

  const ResumenMapSection({
    super.key,
    required this.ruta,
    required this.modoRuta,
    required this.esDesdeCarrera,
    required this.territoriosEnMapa,
    required this.acento,
    required this.centroMapa,
    required this.mapController,
    required this.rutaProgress,
    required this.territoriosConquistados,
    required this.sectionLabel,
    this.modoInicial = 'competitivo',
  });

  @override
  Widget build(BuildContext context) {
    final tieneRuta = ruta.length > 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(sectionLabel),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(context, MaterialPageRoute(builder: (_) =>
              FullscreenMapScreen(
                territorios:     territoriosEnMapa,
                colorTerritorio: acento,
                centroInicial:   centroMapa,
                ruta:            ruta,
                mostrarRuta:     esDesdeCarrera,
                modoInicial:     modoInicial,
              )));
        },
        child: Container(
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: acento.withValues(alpha: 0.6), width: 1.5),
            boxShadow: [
              BoxShadow(color: acento.withValues(alpha: 0.15), blurRadius: 28, spreadRadius: 1),
              BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(children: [
              FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: centroMapa,
                  initialZoom:   15,
                  interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none),
                  onMapReady: () {
                    if (tieneRuta) {
                      mapController.fitCamera(CameraFit.bounds(
                          bounds:  LatLngBounds.fromPoints(ruta),
                          padding: const EdgeInsets.all(48)));
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: _kMapboxTileUrl,
                    userAgentPackageName: 'com.runner_risk.app',
                    tileDimension: 256,
                    keepBuffer:    4,
                    panBuffer:     1,
                  ),
                  if (territoriosEnMapa.isNotEmpty)
                    PolygonLayer(polygons: territoriosEnMapa.map((t) =>
                        Polygon(
                          points:            t.puntos,
                          color:             t.color.withValues(alpha: 0.40),
                          borderColor:       t.color,
                          borderStrokeWidth: 2.5,
                        )).toList()),
                  if (tieneRuta)
                    AnimatedBuilder(
                      animation: rutaProgress,
                      builder: (_, __) {
                        final n = (ruta.length * rutaProgress.value)
                            .round().clamp(2, ruta.length);
                        return PolylineLayer(polylines: [
                          Polyline(
                              points:      ruta.sublist(0, n),
                              strokeWidth: 9.0,
                              color:       acento.withValues(alpha: 0.20)),
                          Polyline(
                              points:      ruta.sublist(0, n),
                              strokeWidth: 3.5,
                              color:       acento),
                        ]);
                      },
                    ),
                  if (!tieneRuta)
                    MarkerLayer(markers: [
                      Marker(
                        point: centroMapa,
                        child: Icon(Icons.location_on, color: acento, size: 28),
                      ),
                    ]),
                ],
              ),
              Positioned.fill(child: IgnorePointer(
                  child: DecoratedBox(decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: RadialGradient(
                        center: Alignment.center, radius: 1.2,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                        ]),
                  )))),
              Positioned(top: 10, left: 10,
                  child: _MapBadge(
                      '${territoriosEnMapa.length} zona${territoriosEnMapa.length == 1 ? '' : 's'}')),
              Positioned(top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color:        Colors.black.withValues(alpha: 0.70),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: acento.withValues(alpha: 0.4), width: 1),
                  ),
                  child: Icon(Icons.open_in_full_rounded,
                      color: acento.withValues(alpha: 0.85), size: 13),
                )),
              if (tieneRuta)
                Positioned(bottom: 0, left: 0, right: 0,
                  child: AnimatedBuilder(
                    animation: rutaProgress,
                    builder: (_, __) => LinearProgressIndicator(
                      value:           rutaProgress.value,
                      backgroundColor: Colors.black.withValues(alpha: 0.3),
                      valueColor:      AlwaysStoppedAnimation(
                          acento.withValues(alpha: 0.8)),
                      minHeight: 2.5,
                    ),
                  )),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _MapBadge extends StatelessWidget {
  final String text;
  const _MapBadge(this.text);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
        color:        Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: _kBorder2)),
    child: Text(text, style: const TextStyle(
        color: _kWhite, fontSize: 9, fontWeight: FontWeight.w800)),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 3, height: 11,
      decoration: BoxDecoration(
          color: _kGrey, borderRadius: BorderRadius.circular(2)),
    ),
    const SizedBox(width: 8),
    Text(text, style: const TextStyle(
        color:         _kGrey,
        fontSize:      8,
        fontWeight:    FontWeight.w900,
        letterSpacing: 3)),
  ]);
}
