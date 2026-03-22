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
  final double ritmoMinKm;
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

  String get tiempoStr {
    final m = tiempoSeg ~/ 60;
    final s = tiempoSeg % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

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

// ── Predictor ─────────────────────────────────────────────────────────────────
class PrediccionTiempo {
  final Duration tiempo5k;
  final Duration tiempo10k;
  final Duration tiempoMediaMaraton;
  final double ritmoBase;

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

  String get str5k           => _formatDuration(tiempo5k);
  String get str10k          => _formatDuration(tiempo10k);
  String get strMediaMaraton => _formatDuration(tiempoMediaMaraton);
}

// ── Comparativa de ruta ───────────────────────────────────────────────────────
class ComparativaRuta {
  final CarreraStats actual;
  final CarreraStats anterior;
  final double deltaRitmoSeg;
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
  final double ritmoMedio;
  final double distanciaTotal;
  final int numCarreras;

  const PuntoTendencia({
    required this.semana,
    required this.ritmoMedio,
    required this.distanciaTotal,
    required this.numCarreras,
  });
}

// ── NUEVO: Comparativa semanal ────────────────────────────────────────────────
class ComparativaSemanal {
  final double kmEstaSemana;
  final double kmSemanaAnterior;
  final int minutosEstaSemana;
  final int minutosSemanaAnterior;
  final int carrerasEstaSemana;
  final int carrerasSemanaAnterior;

  const ComparativaSemanal({
    required this.kmEstaSemana,
    required this.kmSemanaAnterior,
    required this.minutosEstaSemana,
    required this.minutosSemanaAnterior,
    required this.carrerasEstaSemana,
    required this.carrerasSemanaAnterior,
  });

  double get deltaKm => kmEstaSemana - kmSemanaAnterior;
  bool get mejorKm   => deltaKm >= 0;

  /// Porcentaje de cambio en km
  String get deltaKmStr {
    if (kmSemanaAnterior == 0) return '+${kmEstaSemana.toStringAsFixed(1)} km';
    final pct = ((deltaKm / kmSemanaAnterior) * 100).round();
    return '${pct >= 0 ? '+' : ''}$pct%';
  }

  /// Próximo hito de km basado en el ritmo semanal actual
  String get proximoHito {
    if (kmEstaSemana <= 0) return '--';
    // Hitos: 50, 100, 150, 200, 300, 500 km totales semanales acumulados
    // Aquí usamos ritmo semanal para proyectar cuándo llegar al siguiente hito
    final hitosSemanales = [10.0, 20.0, 30.0, 40.0, 50.0];
    for (final hito in hitosSemanales) {
      if (kmEstaSemana < hito) {
        final faltan = hito - kmEstaSemana;
        return '${faltan.toStringAsFixed(1)} km para ${hito.toInt()} km/sem';
      }
    }
    return '🏆 +50 km/semana';
  }
}

// =============================================================================
// SERVICIO PRINCIPAL
// =============================================================================

class StatsService {

  static String mapboxToken = '';

  // ==========================================================================
  // CARGA DE CARRERAS
  // ==========================================================================

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
        final data      = doc.data();
        final distancia = (data['distancia'] as num?)?.toDouble() ?? 0;
        final tiempo    = (data['tiempo_segundos'] as num?)?.toInt() ?? 0;
        final ts        = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

        if (distancia <= 0 || tiempo <= 0) continue;

        final ritmo  = _calcularRitmo(distancia, tiempo);
        final zona   = _calcularZona(ritmo);
        final calles = (data['calles'] as List<dynamic>? ?? []).cast<String>();
        final ruta   = (data['ruta'] as List<dynamic>? ?? [])
            .map((p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ))
            .toList();

        carreras.add(CarreraStats(
          id:          doc.id,
          fecha:       ts,
          distanciaKm: distancia,
          tiempoSeg:   tiempo,
          ritmoMinKm:  ritmo,
          zona:        zona,
          calles:      calles,
          ruta:        ruta,
        ));
      }
      return carreras;
    } catch (e) {
      debugPrint('StatsService.cargarCarreras error: $e');
      return [];
    }
  }

  // ==========================================================================
  // TENDENCIA 4 SEMANAS (existente)
  // ==========================================================================

  static List<PuntoTendencia> calcularTendencia4Semanas(
      List<CarreraStats> carreras) =>
      _calcularTendencia(carreras, semanas: 4);

  // ==========================================================================
  // NUEVO: TENDENCIA 8 SEMANAS (premium)
  // ==========================================================================

  static List<PuntoTendencia> calcularTendencia8Semanas(
      List<CarreraStats> carreras) =>
      _calcularTendencia(carreras, semanas: 8);

  /// Método base para calcular tendencia de N semanas
  static List<PuntoTendencia> _calcularTendencia(
      List<CarreraStats> carreras, {required int semanas}) {
    final ahora  = DateTime.now();
    final puntos = <PuntoTendencia>[];

    for (int semana = semanas - 1; semana >= 0; semana--) {
      final inicio = ahora.subtract(Duration(days: (semana + 1) * 7));
      final fin    = ahora.subtract(Duration(days: semana * 7));

      final delaSemana = carreras.where((c) =>
          c.fecha.isAfter(inicio) && c.fecha.isBefore(fin)).toList();

      if (delaSemana.isEmpty) {
        puntos.add(PuntoTendencia(
          semana:         inicio,
          ritmoMedio:     0,
          distanciaTotal: 0,
          numCarreras:    0,
        ));
        continue;
      }

      final ritmoMedio = delaSemana
              .map((c) => c.ritmoMinKm)
              .reduce((a, b) => a + b) /
          delaSemana.length;
      final distTotal =
          delaSemana.map((c) => c.distanciaKm).reduce((a, b) => a + b);

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
  // NUEVO: COMPARATIVA SEMANAL (premium)
  // ==========================================================================

  /// Compara esta semana (lunes-hoy) con la semana anterior (lunes-domingo pasado)
  static ComparativaSemanal calcularComparativaSemanal(
      List<CarreraStats> carreras) {
    final ahora = DateTime.now();

    // Inicio de esta semana (lunes)
    final diasDesdeLunes = ahora.weekday - 1; // weekday: 1=lun, 7=dom
    final inicioEstaSemana = DateTime(
        ahora.year, ahora.month, ahora.day - diasDesdeLunes);
    final inicioSemanaAnterior =
        inicioEstaSemana.subtract(const Duration(days: 7));
    final finSemanaAnterior = inicioEstaSemana;

    final estaSemana = carreras
        .where((c) => c.fecha.isAfter(inicioEstaSemana))
        .toList();
    final semanaAnterior = carreras
        .where((c) =>
            c.fecha.isAfter(inicioSemanaAnterior) &&
            c.fecha.isBefore(finSemanaAnterior))
        .toList();

    double kmEsta = 0, kmAnterior = 0;
    int minEsta = 0, minAnterior = 0;

    for (final c in estaSemana) {
      kmEsta  += c.distanciaKm;
      minEsta += c.tiempoSeg ~/ 60;
    }
    for (final c in semanaAnterior) {
      kmAnterior  += c.distanciaKm;
      minAnterior += c.tiempoSeg ~/ 60;
    }

    return ComparativaSemanal(
      kmEstaSemana:         kmEsta,
      kmSemanaAnterior:     kmAnterior,
      minutosEstaSemana:    minEsta,
      minutosSemanaAnterior: minAnterior,
      carrerasEstaSemana:   estaSemana.length,
      carrerasSemanaAnterior: semanaAnterior.length,
    );
  }

  // ==========================================================================
  // NUEVO: GEOCODING DE TERRITORIOS (premium)
  // Convierte los puntos de un territorio en nombres de calle/barrio
  // ==========================================================================

  /// Obtiene el nombre de zona/barrio para un territorio a partir de su centroide
  static Future<String> obtenerNombreZona(LatLng centro) async {
    if (mapboxToken.isEmpty) return 'Zona desconocida';
    try {
      final url = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/'
        '${centro.longitude},${centro.latitude}.json'
        '?types=neighborhood,locality,place'
        '&language=es'
        '&access_token=$mapboxToken',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data     = json.decode(resp.body);
        final features = data['features'] as List<dynamic>?;
        if (features != null && features.isNotEmpty) {
          // Preferir neighborhood > locality > place
          return features.first['text'] as String? ?? 'Zona desconocida';
        }
      }
    } catch (e) {
      debugPrint('geocoding error: $e');
    }
    return 'Zona desconocida';
  }

  /// Batch geocoding para múltiples territorios
  /// Devuelve un mapa de índice → nombre de zona
  static Future<Map<int, String>> geocodificarTerritorios(
      List<LatLng> centroides) async {
    final resultado = <int, String>{};
    for (int i = 0; i < centroides.length; i++) {
      resultado[i] = await obtenerNombreZona(centroides[i]);
      // Pequeño delay para no saturar la API de Mapbox
      if (i < centroides.length - 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    return resultado;
  }

  // ==========================================================================
  // PREDICTOR
  // ==========================================================================

  static PrediccionTiempo? calcularPrediccion(List<CarreraStats> carreras) {
    final recientes =
        carreras.where((c) => c.distanciaKm >= 1.0).take(5).toList();
    if (recientes.isEmpty) return null;

    double sumPeso = 0, sumRitmo = 0;
    for (final c in recientes) {
      sumPeso  += c.distanciaKm;
      sumRitmo += c.ritmoMinKm * c.distanciaKm;
    }
    final ritmoBase = sumRitmo / sumPeso;
    final distRef   = recientes.map((c) => c.distanciaKm).reduce((a, b) => a + b)
        / recientes.length;
    final tiempoRefSeg = (ritmoBase * 60 * distRef).round();

    Duration riegel(double distTarget) {
      final secs = tiempoRefSeg * math.pow(distTarget / distRef, 1.06);
      return Duration(seconds: secs.round());
    }

    return PrediccionTiempo(
      tiempo5k:           riegel(5.0),
      tiempo10k:          riegel(10.0),
      tiempoMediaMaraton: riegel(21.0975),
      ritmoBase:          ritmoBase,
    );
  }

  // ==========================================================================
  // ZONAS DE RITMO
  // ==========================================================================

  static Map<ZonaRitmo, _RangoRitmo> calcularZonasPersonalizadas(
      List<CarreraStats> carreras) {
    if (carreras.isEmpty) return _zonasDefault();
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

  static ComparativaRuta? compararConAnterior(
      CarreraStats actual, List<CarreraStats> historial) {
    if (historial.length < 2 || actual.ruta.isEmpty) return null;

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

    if (mejorMatch == null || mejorScore < 0.30) return null;

    final deltaRitmo = (actual.ritmoMinKm - mejorMatch.ritmoMinKm) * 60;
    return ComparativaRuta(
      actual:           actual,
      anterior:         mejorMatch,
      deltaRitmoSeg:    deltaRitmo,
      deltaDistanciaKm: actual.distanciaKm - mejorMatch.distanciaKm,
    );
  }

  static double _solapamientoRuta(List<LatLng> r1, List<LatLng> r2) {
    if (r1.isEmpty || r2.isEmpty) return 0;
    const radioM  = 50.0;
    int cercanos  = 0;
    final muestra = r1.length > 20 ? r1.take(20).toList() : r1;
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

  static Future<List<String>> extraerCalles(List<LatLng> ruta) async {
    if (ruta.isEmpty || mapboxToken.isEmpty) return [];
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
          final data     = json.decode(resp.body);
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
  // GUARDAR CARRERA CON RUTA Y CALLES
  // ==========================================================================

  static Future<void> enriquecerLog({
    required String logId,
    required List<LatLng> ruta,
  }) async {
    try {
      final rutaReducida = _reducirRuta(ruta, maxPuntos: 500);
      final rutaJson     = rutaReducida
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList();
      final calles = await extraerCalles(rutaReducida);
      await FirebaseFirestore.instance
          .collection('activity_logs')
          .doc(logId)
          .update({'ruta': rutaJson, 'calles': calles});
    } catch (e) {
      debugPrint('StatsService.enriquecerLog error: $e');
    }
  }

  static List<LatLng> _reducirRuta(List<LatLng> ruta,
      {required int maxPuntos}) {
    if (ruta.length <= maxPuntos) return ruta;
    final paso      = ruta.length / maxPuntos;
    final resultado = <LatLng>[];
    for (int i = 0; i < maxPuntos; i++) {
      resultado
          .add(ruta[(i * paso).round().clamp(0, ruta.length - 1)]);
    }
    return resultado;
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  static double _calcularRitmo(double distanciaKm, int tiempoSeg) {
    if (distanciaKm <= 0) return 0;
    return (tiempoSeg / 60) / distanciaKm;
  }

  static ZonaRitmo _calcularZona(double ritmoMinKm) {
    if (ritmoMinKm <= 0)  return ZonaRitmo.recuperacion;
    if (ritmoMinKm < 4.5) return ZonaRitmo.competicion;
    if (ritmoMinKm < 5.5) return ZonaRitmo.umbral;
    if (ritmoMinKm < 6.5) return ZonaRitmo.moderado;
    if (ritmoMinKm < 7.5) return ZonaRitmo.facil;
    return ZonaRitmo.recuperacion;
  }
}

class _RangoRitmo {
  final double min;
  final double max;
  const _RangoRitmo(this.min, this.max);
  bool contains(double ritmo) => ritmo >= min && ritmo < max;
}