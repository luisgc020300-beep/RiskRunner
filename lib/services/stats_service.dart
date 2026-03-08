import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:latlong2/latlong.dart';

// =============================================================================
// MODELOS
// =============================================================================

class CarreraStats {
  final String id;
  final DateTime fecha;
  final double distanciaKm;
  final int tiempoSeg;
  final double ritmoMinKm;       // min/km
  final ZonaRitmo zona;
  final List<String> calles;
  final List<LatLng> ruta;

  const CarreraStats({
    required this.id,
    required this.fecha,
    required this.distanciaKm,
    required this.tiempoSeg,
    required this.ritmoMinKm,
    required this.zona,
    required this.calles,
    required this.ruta,
  });

  /// Tiempo formateado: "42:30"
  String get tiempoStr {
    final m = tiempoSeg ~/ 60;
    final s = tiempoSeg % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Ritmo formateado: "5'23\""
  String get ritmoStr {
    final min = ritmoMinKm.floor();
    final seg = ((ritmoMinKm - min) * 60).round();
    return "$min'${seg.toString().padLeft(2, '0')}\"";
  }
}

// ── Zonas de ritmo ────────────────────────────────────────────────────────────
enum ZonaRitmo { recuperacion, facil, moderado, umbral, competicion }

extension ZonaRitmoX on ZonaRitmo {
  String get nombre {
    switch (this) {
      case ZonaRitmo.recuperacion: return 'Recuperación';
      case ZonaRitmo.facil:        return 'Fácil';
      case ZonaRitmo.moderado:     return 'Moderado';
      case ZonaRitmo.umbral:       return 'Umbral';
      case ZonaRitmo.competicion:  return 'Competición';
    }
  }

  String get emoji {
    switch (this) {
      case ZonaRitmo.recuperacion: return '🟦';
      case ZonaRitmo.facil:        return '🟩';
      case ZonaRitmo.moderado:     return '🟨';
      case ZonaRitmo.umbral:       return '🟧';
      case ZonaRitmo.competicion:  return '🟥';
    }
  }

  /// Color hex para UI
  String get colorHex {
    switch (this) {
      case ZonaRitmo.recuperacion: return '#3b82f6';
      case ZonaRitmo.facil:        return '#22c55e';
      case ZonaRitmo.moderado:     return '#eab308';
      case ZonaRitmo.umbral:       return '#f97316';
      case ZonaRitmo.competicion:  return '#ef4444';
    }
  }
}

// ── Resultado del predictor ───────────────────────────────────────────────────
class PrediccionTiempo {
  final Duration tiempo5k;
  final Duration tiempo10k;
  final Duration tiempoMediaMaraton;
  final double ritmoBase; // min/km usado para la predicción

  const PrediccionTiempo({
    required this.tiempo5k,
    required this.tiempo10k,
    required this.tiempoMediaMaraton,
    required this.ritmoBase,
  });

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get str5k         => _formatDuration(tiempo5k);
  String get str10k        => _formatDuration(tiempo10k);
  String get strMediaMaraton => _formatDuration(tiempoMediaMaraton);
}

// ── Comparativa de ruta ───────────────────────────────────────────────────────
class ComparativaRuta {
  final CarreraStats actual;
  final CarreraStats anterior;
  final double deltaRitmoSeg;   // positivo = más lento, negativo = más rápido
  final double deltaDistanciaKm;

  const ComparativaRuta({
    required this.actual,
    required this.anterior,
    required this.deltaRitmoSeg,
    required this.deltaDistanciaKm,
  });

  bool get esMasRapido => deltaRitmoSeg < 0;

  String get deltaRitmoStr {
    final abs = deltaRitmoSeg.abs();
    final min = (abs ~/ 60);
    final seg = (abs % 60).round();
    final prefix = esMasRapido ? '-' : '+';
    return "$prefix${min > 0 ? '${min}m ' : ''}${seg}s/km";
  }
}

// ── Punto de tendencia semanal ────────────────────────────────────────────────
class PuntoTendencia {
  final DateTime semana;
  final double ritmoMedio;   // min/km
  final double distanciaTotal;
  final int numCarreras;

  const PuntoTendencia({
    required this.semana,
    required this.ritmoMedio,
    required this.distanciaTotal,
    required this.numCarreras,
  });
}

// =============================================================================
// SERVICIO PRINCIPAL
// =============================================================================

class StatsService {

  // ── Token Mapbox (mismo que usa la app) ──────────────────────────────────
  // Se inyecta desde el exterior para no duplicar el secret
  static String mapboxToken = '';

  // ==========================================================================
  // CARGA DE CARRERAS
  // ==========================================================================

  /// Carga las últimas [limite] carreras del usuario desde Firestore.
  static Future<List<CarreraStats>> cargarCarreras({int limite = 50}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    try {
      final snap = await FirebaseFirestore.instance
          .collection('activity_logs')
          .where('userId', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(limite)
          .get();

      final carreras = <CarreraStats>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final distancia = (data['distancia'] as num?)?.toDouble() ?? 0;
        final tiempo    = (data['tiempo_segundos'] as num?)?.toInt() ?? 0;
        final ts        = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

        if (distancia <= 0 || tiempo <= 0) continue;

        final ritmo = _calcularRitmo(distancia, tiempo);
        final zona  = _calcularZona(ritmo);

        // Calles guardadas en Firestore (si existen)
        final callesRaw = data['calles'] as List<dynamic>? ?? [];
        final calles    = callesRaw.cast<String>();

        // Ruta guardada en Firestore (si existe)
        final rutaRaw = data['ruta'] as List<dynamic>? ?? [];
        final ruta    = rutaRaw
            .map((p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ))
            .toList();

        carreras.add(CarreraStats(
          id:           doc.id,
          fecha:        ts,
          distanciaKm:  distancia,
          tiempoSeg:    tiempo,
          ritmoMinKm:   ritmo,
          zona:         zona,
          calles:       calles,
          ruta:         ruta,
        ));
      }
      return carreras;
    } catch (e) {
      debugPrint('StatsService.cargarCarreras error: $e');
      return [];
    }
  }

  // ==========================================================================
  // TENDENCIA 4 SEMANAS
  // ==========================================================================

  static List<PuntoTendencia> calcularTendencia4Semanas(
      List<CarreraStats> carreras) {
    final ahora  = DateTime.now();
    final puntos = <PuntoTendencia>[];

    for (int semana = 3; semana >= 0; semana--) {
      final inicio = ahora.subtract(Duration(days: (semana + 1) * 7));
      final fin    = ahora.subtract(Duration(days: semana * 7));

      final delaSemana = carreras.where((c) =>
          c.fecha.isAfter(inicio) && c.fecha.isBefore(fin)).toList();

      if (delaSemana.isEmpty) {
        puntos.add(PuntoTendencia(
          semana:        inicio,
          ritmoMedio:    0,
          distanciaTotal: 0,
          numCarreras:   0,
        ));
        continue;
      }

      final ritmoMedio = delaSemana.map((c) => c.ritmoMinKm).reduce((a, b) => a + b)
          / delaSemana.length;
      final distTotal  = delaSemana.map((c) => c.distanciaKm).reduce((a, b) => a + b);

      puntos.add(PuntoTendencia(
        semana:         inicio,
        ritmoMedio:     ritmoMedio,
        distanciaTotal: distTotal,
        numCarreras:    delaSemana.length,
      ));
    }
    return puntos;
  }

  // ==========================================================================
  // PREDICTOR 5K / 10K
  // ==========================================================================

  /// Usa la fórmula de Riegel: T2 = T1 × (D2/D1)^1.06
  /// Toma las últimas 5 carreras para calcular el ritmo base.
  static PrediccionTiempo? calcularPrediccion(List<CarreraStats> carreras) {
    final recientes = carreras
        .where((c) => c.distanciaKm >= 1.0)
        .take(5)
        .toList();

    if (recientes.isEmpty) return null;

    // Ritmo medio ponderado por distancia (las carreras largas pesan más)
    double sumPeso = 0;
    double sumRitmo = 0;
    for (final c in recientes) {
      sumPeso  += c.distanciaKm;
      sumRitmo += c.ritmoMinKm * c.distanciaKm;
    }
    final ritmoBase = sumRitmo / sumPeso; // min/km

    // Distancia representativa (media de las últimas carreras)
    final distRef = recientes.map((c) => c.distanciaKm).reduce((a, b) => a + b)
        / recientes.length;
    final tiempoRefSeg = (ritmoBase * 60 * distRef).round();

    Duration _riegel(double distTarget) {
      final secs = tiempoRefSeg * math.pow(distTarget / distRef, 1.06);
      return Duration(seconds: secs.round());
    }

    return PrediccionTiempo(
      tiempo5k:           _riegel(5.0),
      tiempo10k:          _riegel(10.0),
      tiempoMediaMaraton: _riegel(21.0975),
      ritmoBase:          ritmoBase,
    );
  }

  // ==========================================================================
  // ZONAS DE RITMO
  // ==========================================================================

  /// Calcula las zonas personalizadas basadas en el ritmo base del corredor.
  /// Las zonas se calculan como porcentajes del ritmo umbral estimado.
  static Map<ZonaRitmo, _RangoRitmo> calcularZonasPersonalizadas(
      List<CarreraStats> carreras) {
    if (carreras.isEmpty) return _zonasDefault();

    // Ritmo umbral estimado: percentil 20 más rápido de las últimas 10 carreras
    final recientes = carreras.take(10).map((c) => c.ritmoMinKm).toList()
      ..sort();
    final umbral = recientes[(recientes.length * 0.2).floor()];

    return {
      ZonaRitmo.recuperacion: _RangoRitmo(umbral * 1.30, double.infinity),
      ZonaRitmo.facil:        _RangoRitmo(umbral * 1.15, umbral * 1.30),
      ZonaRitmo.moderado:     _RangoRitmo(umbral * 1.05, umbral * 1.15),
      ZonaRitmo.umbral:       _RangoRitmo(umbral * 0.95, umbral * 1.05),
      ZonaRitmo.competicion:  _RangoRitmo(0, umbral * 0.95),
    };
  }

  static Map<ZonaRitmo, _RangoRitmo> _zonasDefault() => {
    ZonaRitmo.recuperacion: _RangoRitmo(7.5, double.infinity),
    ZonaRitmo.facil:        _RangoRitmo(6.5, 7.5),
    ZonaRitmo.moderado:     _RangoRitmo(5.5, 6.5),
    ZonaRitmo.umbral:       _RangoRitmo(4.5, 5.5),
    ZonaRitmo.competicion:  _RangoRitmo(0,   4.5),
  };

  // ==========================================================================
  // COMPARATIVA DE RUTA
  // ==========================================================================

  /// Busca en el historial la carrera anterior que más se solape con la actual.
  static ComparativaRuta? compararConAnterior(
      CarreraStats actual, List<CarreraStats> historial) {
    if (historial.length < 2 || actual.ruta.isEmpty) return null;

    // Buscar la carrera más similar por ruta (excluir la actual)
    CarreraStats? mejorMatch;
    double mejorScore = 0;

    for (final c in historial) {
      if (c.id == actual.id || c.ruta.isEmpty) continue;
      final score = _solapamientoRuta(actual.ruta, c.ruta);
      if (score > mejorScore) {
        mejorScore = score;
        mejorMatch = c;
      }
    }

    // Si hay menos de 30% de solapamiento, no es la misma ruta
    if (mejorMatch == null || mejorScore < 0.30) return null;

    final deltaRitmo = (actual.ritmoMinKm - mejorMatch.ritmoMinKm) * 60; // en segundos

    return ComparativaRuta(
      actual:           actual,
      anterior:         mejorMatch,
      deltaRitmoSeg:    deltaRitmo,
      deltaDistanciaKm: actual.distanciaKm - mejorMatch.distanciaKm,
    );
  }

  /// Calcula solapamiento geográfico entre dos rutas (0.0 → 1.0).
  static double _solapamientoRuta(List<LatLng> r1, List<LatLng> r2) {
    if (r1.isEmpty || r2.isEmpty) return 0;
    const radioM = 50.0; // punto "cerca" si está a <50m
    int cercanos = 0;

    // Muestra aleatoria para no hacer O(n²) completo
    final muestra = r1.length > 20
        ? r1.where((_, ) => true).take(20).toList()
        : r1;

    for (final p1 in muestra) {
      for (final p2 in r2) {
        if (Geolocator.distanceBetween(
                p1.latitude, p1.longitude, p2.latitude, p2.longitude) <=
            radioM) {
          cercanos++;
          break;
        }
      }
    }
    return cercanos / muestra.length;
  }

  // ==========================================================================
  // GEOCODING — CALLES RECORRIDAS
  // ==========================================================================

  /// Extrae los nombres de calles únicas de una ruta usando Mapbox Geocoding.
  /// Hace una petición cada ~200m para no saturar la API.
  static Future<List<String>> extraerCalles(List<LatLng> ruta) async {
    if (ruta.isEmpty || mapboxToken.isEmpty) return [];

    // Muestrear cada ~200m
    final muestras = _muestrearRuta(ruta, cadaMetros: 200);
    final calles   = <String>{};

    for (final punto in muestras) {
      try {
        final url = Uri.parse(
          'https://api.mapbox.com/geocoding/v5/mapbox.places/'
          '${punto.longitude},${punto.latitude}.json'
          '?types=address&language=es&access_token=$mapboxToken',
        );
        final resp = await http.get(url).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final data    = json.decode(resp.body);
          final features = data['features'] as List<dynamic>?;
          if (features != null && features.isNotEmpty) {
            final text = features.first['text'] as String?;
            if (text != null && text.isNotEmpty) calles.add(text);
          }
        }
      } catch (_) {}
    }

    return calles.toList();
  }

  /// Muestrea puntos de la ruta cada [cadaMetros] metros aprox.
  static List<LatLng> _muestrearRuta(List<LatLng> ruta,
      {required double cadaMetros}) {
    if (ruta.isEmpty) return [];
    final resultado = <LatLng>[ruta.first];
    double acumulado = 0;

    for (int i = 1; i < ruta.length; i++) {
      acumulado += Geolocator.distanceBetween(
        ruta[i - 1].latitude, ruta[i - 1].longitude,
        ruta[i].latitude,     ruta[i].longitude,
      );
      if (acumulado >= cadaMetros) {
        resultado.add(ruta[i]);
        acumulado = 0;
      }
    }
    return resultado;
  }

  // ==========================================================================
  // GUARDAR CARRERA CON RUTA Y CALLES EN FIRESTORE
  // ==========================================================================

  /// Enriquece un activity_log existente con ruta y calles.
  /// Llamar desde stopTracking() en LiveActivity tras guardar el log base.
  static Future<void> enriquecerLog({
    required String logId,
    required List<LatLng> ruta,
  }) async {
    try {
      // Reducir ruta a máximo 500 puntos para no saturar Firestore
      final rutaReducida = _reducirRuta(ruta, maxPuntos: 500);
      final rutaJson = rutaReducida
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList();

      // Extraer calles (async, no bloquea la UI)
      final calles = await extraerCalles(rutaReducida);

      await FirebaseFirestore.instance
          .collection('activity_logs')
          .doc(logId)
          .update({
        'ruta':   rutaJson,
        'calles': calles,
      });
    } catch (e) {
      debugPrint('StatsService.enriquecerLog error: $e');
    }
  }

  /// Reduce la ruta a [maxPuntos] usando muestreo uniforme.
  static List<LatLng> _reducirRuta(List<LatLng> ruta, {required int maxPuntos}) {
    if (ruta.length <= maxPuntos) return ruta;
    final paso      = ruta.length / maxPuntos;
    final resultado = <LatLng>[];
    for (int i = 0; i < maxPuntos; i++) {
      resultado.add(ruta[(i * paso).round().clamp(0, ruta.length - 1)]);
    }
    return resultado;
  }

  // ==========================================================================
  // HELPERS INTERNOS
  // ==========================================================================

  static double _calcularRitmo(double distanciaKm, int tiempoSeg) {
    if (distanciaKm <= 0) return 0;
    return (tiempoSeg / 60) / distanciaKm; // min/km
  }

  static ZonaRitmo _calcularZona(double ritmoMinKm) {
    if (ritmoMinKm <= 0)   return ZonaRitmo.recuperacion;
    if (ritmoMinKm < 4.5)  return ZonaRitmo.competicion;
    if (ritmoMinKm < 5.5)  return ZonaRitmo.umbral;
    if (ritmoMinKm < 6.5)  return ZonaRitmo.moderado;
    if (ritmoMinKm < 7.5)  return ZonaRitmo.facil;
    return ZonaRitmo.recuperacion;
  }
}

// ── Rango interno ─────────────────────────────────────────────────────────────
class _RangoRitmo {
  final double min;
  final double max;
  const _RangoRitmo(this.min, this.max);
  bool contains(double ritmo) => ritmo >= min && ritmo < max;
}