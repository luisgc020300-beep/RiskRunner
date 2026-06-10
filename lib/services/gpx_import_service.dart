// lib/services/gpx_import_service.dart
//
// Parsea archivos GPX (Strava, Garmin, Komoot…) y procesa
// los territorios que la ruta atraviesa.
// ignore_for_file: deprecated_member_use

import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';
import 'territory_service.dart';

// ── Modelo de datos GPX parseados ─────────────────────────────────────────────
class GpxData {
  final List<LatLng> puntos;
  final DateTime? inicio;
  final DateTime? fin;
  final double distanciaKm;
  final Duration duracion;
  final double velocidadMediaKmh;

  const GpxData({
    required this.puntos,
    this.inicio,
    this.fin,
    required this.distanciaKm,
    required this.duracion,
    required this.velocidadMediaKmh,
  });
}

// ── Resultado del procesado territorial ───────────────────────────────────────
class ImportResult {
  final GpxData datos;
  final int conquistados;
  final int danados;
  final int sinCambio;
  final List<String> mensajes;

  const ImportResult({
    required this.datos,
    required this.conquistados,
    required this.danados,
    required this.sinCambio,
    required this.mensajes,
  });

  bool get hayResultado => conquistados > 0 || danados > 0;
}

// ── Servicio principal ─────────────────────────────────────────────────────────
class GpxImportService {

  // ── Parser GPX ───────────────────────────────────────────────────────────────
  static GpxData? parseGpx(String content) {
    try {
      final doc = XmlDocument.parse(content);
      final trkpts = doc.findAllElements('trkpt').toList();
      if (trkpts.isEmpty) return null;

      final puntos   = <LatLng>[];
      final tiempos  = <DateTime>[];

      for (final pt in trkpts) {
        final lat = double.tryParse(pt.getAttribute('lat') ?? '');
        final lon = double.tryParse(pt.getAttribute('lon') ?? '');
        if (lat == null || lon == null) continue;
        puntos.add(LatLng(lat, lon));

        final timeEl = pt.findElements('time').firstOrNull;
        if (timeEl != null) {
          try { tiempos.add(DateTime.parse(timeEl.innerText.trim())); } catch (_) {}
        }
      }

      if (puntos.isEmpty) return null;

      // Calcular distancia recorriendo los segmentos
      double distanciaKm = 0;
      for (int i = 1; i < puntos.length; i++) {
        distanciaKm += Geolocator.distanceBetween(
          puntos[i - 1].latitude, puntos[i - 1].longitude,
          puntos[i].latitude, puntos[i].longitude,
        ) / 1000;
      }

      final inicio = tiempos.isNotEmpty ? tiempos.first : null;
      final fin    = tiempos.length > 1  ? tiempos.last  : null;
      final dur    = (inicio != null && fin != null)
          ? fin.difference(inicio)
          : Duration.zero;
      final vel    = dur.inSeconds > 0
          ? distanciaKm / (dur.inSeconds / 3600)
          : 5.0;

      return GpxData(
        puntos:           puntos,
        inicio:           inicio,
        fin:              fin,
        distanciaKm:      distanciaKm,
        duracion:         dur,
        velocidadMediaKmh: vel.clamp(1.0, 50.0),
      );
    } catch (e) {
      return null;
    }
  }

  // ── Procesado territorial ────────────────────────────────────────────────────
  static Future<ImportResult> procesarImportacion(GpxData datos) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || datos.puntos.isEmpty) {
      return ImportResult(datos: datos, conquistados: 0, danados: 0,
          sinCambio: 0, mensajes: ['Sin sesión activa']);
    }

    // Centro geográfico de la ruta para cargar territorios relevantes
    final centro = _centroRuta(datos.puntos);

    // Cargar territorios en el área (modo competitivo por defecto en import)
    final territorios = await TerritoryService.cargarTodosLosTerritorios(
      centro: centro,
      modo: 'competitivo',
    );

    // Filtrar los que la ruta atraviesa y no son propios
    final objetivo = territorios.where((t) {
      if (t.ownerId == user.uid) return false;
      return _rutaPasaPorPoligono(datos.puntos, t.puntos) ||
          (t.esConquistableSinPasar &&
              _rutaPasaCercaDe(datos.puntos, t.centro, radioMetros: 50));
    }).toList();

    int conquistados = 0, danados = 0, sinCambio = 0;
    final mensajes   = <String>[];

    if (objetivo.isEmpty) {
      mensajes.add('La ruta no atraviesa territorios rivales.');
    }

    // Procesar en paralelo, igual que LiveActivity
    await Future.wait(
      objetivo.map((t) async {
        try {
          final ataque = await TerritoryService.atacarTerritorio(
            territorioDefensorId: t.docId,
            rutaAtacante:         datos.puntos,
            velocidadMediaKmh:    datos.velocidadMediaKmh,
          );
          if (ataque.conquistoAlgo) {
            conquistados++;
            mensajes.add('Conquistado: ${t.nombreTerritorio ?? t.ownerNickname}');
          } else if (ataque.accion == 'daño' && ataque.ok) {
            danados++;
            mensajes.add(
                'Daño a ${t.nombreTerritorio ?? t.ownerNickname} '
                '(HP: ${ataque.hpAntes}% → ${ataque.hpDespues}%)');
          } else {
            sinCambio++;
          }
        } catch (_) {
          sinCambio++;
        }
      }),
      eagerError: false,
    );

    return ImportResult(
      datos:        datos,
      conquistados: conquistados,
      danados:      danados,
      sinCambio:    sinCambio,
      mensajes:     mensajes,
    );
  }

  // ── Geométrica: ray-casting point-in-polygon ─────────────────────────────────
  static bool _puntoEnPoligono(LatLng punto, List<LatLng> pol) {
    final n = pol.length;
    int inter = 0;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = pol[i].longitude, yi = pol[i].latitude;
      final xj = pol[j].longitude, yj = pol[j].latitude;
      if (((yi > punto.latitude) != (yj > punto.latitude)) &&
          punto.longitude < (xj - xi) * (punto.latitude - yi) / (yj - yi) + xi) {
        inter++;
      }
    }
    return inter % 2 == 1;
  }

  static bool _rutaPasaPorPoligono(List<LatLng> ruta, List<LatLng> pol) =>
      ruta.any((p) => _puntoEnPoligono(p, pol));

  static bool _rutaPasaCercaDe(List<LatLng> ruta, LatLng obj,
          {required double radioMetros}) =>
      ruta.any((p) =>
          Geolocator.distanceBetween(
              p.latitude, p.longitude, obj.latitude, obj.longitude) <=
          radioMetros);

  // ── Centro geográfico de la ruta ─────────────────────────────────────────────
  static LatLng _centroRuta(List<LatLng> puntos) {
    if (puntos.isEmpty) return const LatLng(0, 0);
    // Bounding box center (más rápido que centroide real para nuestro uso)
    double minLat = puntos.first.latitude,  maxLat = minLat;
    double minLon = puntos.first.longitude, maxLon = minLon;
    for (final p in puntos) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }
    return LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
  }
}
