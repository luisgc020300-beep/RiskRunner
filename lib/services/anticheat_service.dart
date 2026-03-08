import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// =============================================================================
// CONFIGURACIÓN DE UMBRALES
// =============================================================================

class AntiCheatConfig {
  /// Velocidad máxima permitida en km/h.
  /// Un runner élite hace ~22 km/h. 35 km/h es imposible a pie.
  static const double velocidadMaxKmh = 35.0;

  /// Distancia máxima entre dos puntos consecutivos en metros.
  /// Si el usuario "salta" más de esto instantáneamente = teletransporte.
  /// A 35 km/h en 3 segundos (máx entre eventos GPS) = ~29m. Ponemos 150m de margen.
  static const double distanciaMaxEntreEventosM = 150.0;

  /// Precisión mínima aceptable del GPS en metros.
  /// Precisión > 50m suele indicar señal muy débil o GPS falseado.
  static const double precisionMinM = 50.0;

  /// Número de infracciones consecutivas antes de cancelar la sesión.
  static const int infraccionesParaCancelar = 4;

  /// Número de infracciones totales en la sesión antes de cancelar.
  static const int infraccionesTotalesParaCancelar = 8;

  /// Altitud máxima razonable para una carrera urbana (metros sobre el mar).
  /// Filtra altitudes absurdas que algunos spoofers generan.
  static const double altitudMaxM = 5000.0;

  /// Aceleración máxima posible entre dos puntos (km/h por segundo).
  /// Un humano puede acelerar ~3 km/h/s como máximo.
  static const double aceleracionMaxKmhS = 5.0;
}

// =============================================================================
// RESULTADO DEL ANÁLISIS
// =============================================================================

enum AntiCheatVeredicto {
  ok,              // punto válido
  velocidad,       // velocidad imposible
  teletransporte,  // salto de distancia imposible
  mockLocation,    // mock location detectada
  precisionBaja,   // precisión GPS muy baja (posible spoof)
  aceleracion,     // aceleración imposible
}

class AntiCheatResultado {
  final AntiCheatVeredicto veredicto;
  final bool esValido;
  final String? detalle;
  final double? valorDetectado; // el valor que disparó la alarma

  const AntiCheatResultado({
    required this.veredicto,
    required this.esValido,
    this.detalle,
    this.valorDetectado,
  });

  static const AntiCheatResultado valido = AntiCheatResultado(
    veredicto: AntiCheatVeredicto.ok,
    esValido: true,
  );
}

// =============================================================================
// SERVICIO PRINCIPAL
// =============================================================================

class AntiCheatService {
  // Estado de la sesión actual
  int _infraccionesConsecutivas = 0;
  int _infraccionesTotales      = 0;
  Position? _ultimaPosicion;
  DateTime? _ultimoTimestamp;
  double _ultimaVelocidadKmh = 0;

  bool get sesionCancelada =>
      _infraccionesConsecutivas >= AntiCheatConfig.infraccionesParaCancelar ||
      _infraccionesTotales >= AntiCheatConfig.infraccionesTotalesParaCancelar;

  /// Resetea el estado para una nueva sesión
  void resetear() {
    _infraccionesConsecutivas = 0;
    _infraccionesTotales      = 0;
    _ultimaPosicion           = null;
    _ultimoTimestamp          = null;
    _ultimaVelocidadKmh       = 0;
  }

  // ==========================================================================
  // ANÁLISIS PRINCIPAL — llamar en cada evento GPS
  // ==========================================================================

  AntiCheatResultado analizarPunto(Position pos) {
    // ── 1. Mock Location (Android) ──────────────────────────────────────────
    final mockResult = _checkMockLocation(pos);
    if (!mockResult.esValido) {
      return _registrarInfraccion(mockResult, pos);
    }

    // ── 2. Precisión GPS ────────────────────────────────────────────────────
    final precResult = _checkPrecision(pos);
    if (!precResult.esValido) {
      // Precisión baja no cancela sesión pero sí descarta el punto
      _infraccionesTotales++;
      return precResult;
    }

    // ── 3. Altitud absurda ─────────────────────────────────────────────────
    if (pos.altitude.abs() > AntiCheatConfig.altitudMaxM) {
      return _registrarInfraccion(AntiCheatResultado(
        veredicto: AntiCheatVeredicto.mockLocation,
        esValido: false,
        detalle: 'Altitud imposible: ${pos.altitude.toStringAsFixed(0)}m',
        valorDetectado: pos.altitude,
      ), pos);
    }

    // Si no hay posición previa, este es el primer punto → siempre válido
    if (_ultimaPosicion == null || _ultimoTimestamp == null) {
      _actualizarEstado(pos);
      return AntiCheatResultado.valido;
    }

    // ── 4. Calcular delta tiempo y distancia ────────────────────────────────
    final dtMs = pos.timestamp
        .difference(_ultimoTimestamp!)
        .inMilliseconds
        .abs();
    final dtSeg = dtMs / 1000.0;

    final distM = Geolocator.distanceBetween(
      _ultimaPosicion!.latitude,  _ultimaPosicion!.longitude,
      pos.latitude,               pos.longitude,
    );

    // ── 5. Teletransporte ───────────────────────────────────────────────────
    final teleResult = _checkTeletransporte(distM, dtSeg);
    if (!teleResult.esValido) {
      return _registrarInfraccion(teleResult, pos);
    }

    // ── 6. Velocidad imposible ──────────────────────────────────────────────
    if (dtSeg > 0) {
      final velKmh = (distM / dtSeg) * 3.6;
      final velResult = _checkVelocidad(velKmh);
      if (!velResult.esValido) {
        return _registrarInfraccion(velResult, pos);
      }

      // ── 7. Aceleración imposible ──────────────────────────────────────────
      final accelResult = _checkAceleracion(velKmh, dtSeg);
      if (!accelResult.esValido) {
        return _registrarInfraccion(accelResult, pos);
      }

      _ultimaVelocidadKmh = velKmh;
    }

    // ── Todo OK ─────────────────────────────────────────────────────────────
    _infraccionesConsecutivas = 0; // reset de consecutivas
    _actualizarEstado(pos);
    return AntiCheatResultado.valido;
  }

  // ==========================================================================
  // DETECTORES INDIVIDUALES
  // ==========================================================================

  AntiCheatResultado _checkMockLocation(Position pos) {
    // Geolocator expone isMocked en Android
    if (pos.isMocked) {
      return AntiCheatResultado(
        veredicto: AntiCheatVeredicto.mockLocation,
        esValido: false,
        detalle: 'Mock location detectada (Android)',
      );
    }
    return AntiCheatResultado.valido;
  }

  AntiCheatResultado _checkPrecision(Position pos) {
    if (pos.accuracy > AntiCheatConfig.precisionMinM) {
      return AntiCheatResultado(
        veredicto: AntiCheatVeredicto.precisionBaja,
        esValido: false,
        detalle: 'Precisión GPS insuficiente: ${pos.accuracy.toStringAsFixed(0)}m',
        valorDetectado: pos.accuracy,
      );
    }
    return AntiCheatResultado.valido;
  }

  AntiCheatResultado _checkTeletransporte(double distM, double dtSeg) {
    // Si el delta tiempo es muy pequeño (<0.5s) y la distancia es grande → teletransporte
    if (distM > AntiCheatConfig.distanciaMaxEntreEventosM) {
      return AntiCheatResultado(
        veredicto: AntiCheatVeredicto.teletransporte,
        esValido: false,
        detalle: 'Salto de ${distM.toStringAsFixed(0)}m en ${dtSeg.toStringAsFixed(1)}s',
        valorDetectado: distM,
      );
    }
    return AntiCheatResultado.valido;
  }

  AntiCheatResultado _checkVelocidad(double velKmh) {
    if (velKmh > AntiCheatConfig.velocidadMaxKmh) {
      return AntiCheatResultado(
        veredicto: AntiCheatVeredicto.velocidad,
        esValido: false,
        detalle: 'Velocidad imposible: ${velKmh.toStringAsFixed(1)} km/h',
        valorDetectado: velKmh,
      );
    }
    return AntiCheatResultado.valido;
  }

  AntiCheatResultado _checkAceleracion(double velActualKmh, double dtSeg) {
    if (dtSeg <= 0 || _ultimaVelocidadKmh <= 0) return AntiCheatResultado.valido;
    final accel = (velActualKmh - _ultimaVelocidadKmh).abs() / dtSeg;
    if (accel > AntiCheatConfig.aceleracionMaxKmhS) {
      return AntiCheatResultado(
        veredicto: AntiCheatVeredicto.aceleracion,
        esValido: false,
        detalle: 'Aceleración imposible: ${accel.toStringAsFixed(1)} km/h/s',
        valorDetectado: accel,
      );
    }
    return AntiCheatResultado.valido;
  }

  // ==========================================================================
  // HELPERS INTERNOS
  // ==========================================================================

  AntiCheatResultado _registrarInfraccion(
      AntiCheatResultado resultado, Position pos) {
    _infraccionesConsecutivas++;
    _infraccionesTotales++;
    debugPrint(
        '⚠️ AntiCheat [${resultado.veredicto.name}]: ${resultado.detalle} '
        '(consecutivas: $_infraccionesConsecutivas / totales: $_infraccionesTotales)');
    _guardarLogFirestore(resultado, pos);
    return resultado;
  }

  void _actualizarEstado(Position pos) {
    _ultimaPosicion  = pos;
    _ultimoTimestamp = pos.timestamp;
  }

  // ==========================================================================
  // LOG EN FIRESTORE (asíncrono, no bloquea el stream GPS)
  // ==========================================================================

  Future<void> _guardarLogFirestore(
      AntiCheatResultado resultado, Position pos) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('anticheat_logs').add({
        'userId':    uid,
        'tipo':      resultado.veredicto.name,
        'detalle':   resultado.detalle,
        'valor':     resultado.valorDetectado,
        'lat':       pos.latitude,
        'lng':       pos.longitude,
        'precision': pos.accuracy,
        'isMocked':  pos.isMocked,
        'timestamp': FieldValue.serverTimestamp(),
        'consecutivas': _infraccionesConsecutivas,
        'totales':   _infraccionesTotales,
      });
    } catch (e) {
      debugPrint('Error guardando log anticheat: $e');
    }
  }

  // ==========================================================================
  // ANÁLISIS POST-SESIÓN — valida la ruta completa al terminar
  // Detecta patrones imposibles en la ruta entera que no se ven punto a punto
  // ==========================================================================

  static AntiCheatSesionResultado analizarSesionCompleta({
    required List<LatLng> ruta,
    required Duration tiempo,
    required double distanciaKm,
  }) {
    if (ruta.length < 2) {
      return AntiCheatSesionResultado(esValida: true, motivo: null);
    }

    // Velocidad media de toda la sesión
    final horas = tiempo.inSeconds / 3600.0;
    if (horas > 0) {
      final velMedia = distanciaKm / horas;
      if (velMedia > AntiCheatConfig.velocidadMaxKmh) {
        return AntiCheatSesionResultado(
          esValida: false,
          motivo: 'Velocidad media imposible: ${velMedia.toStringAsFixed(1)} km/h',
          tipo: AntiCheatVeredicto.velocidad,
        );
      }
    }

    // Detectar segmentos de ruta con ángulos imposibles (zigzag perfecto = bot)
    int zigzagsExtremos = 0;
    for (int i = 1; i < ruta.length - 1; i++) {
      final a1 = _angulo(ruta[i - 1], ruta[i]);
      final a2 = _angulo(ruta[i], ruta[i + 1]);
      final diff = (a2 - a1).abs() % 360;
      final cambio = diff > 180 ? 360 - diff : diff;
      if (cambio > 170) zigzagsExtremos++; // cambio de dirección de ~180°
    }
    // Si más del 30% de los puntos tienen zigzag extremo → sospechoso
    if (zigzagsExtremos > ruta.length * 0.30 && ruta.length > 20) {
      return AntiCheatSesionResultado(
        esValida: false,
        motivo: 'Patrón de movimiento anómalo ($zigzagsExtremos zigzags)',
        tipo: AntiCheatVeredicto.mockLocation,
      );
    }

    return AntiCheatSesionResultado(esValida: true, motivo: null);
  }

  static double _angulo(LatLng a, LatLng b) {
    final dy = b.latitude  - a.latitude;
    final dx = b.longitude - a.longitude;
    return math.atan2(dy, dx) * 180 / math.pi;
  }
}

// =============================================================================
// RESULTADO DEL ANÁLISIS DE SESIÓN COMPLETA
// =============================================================================

class AntiCheatSesionResultado {
  final bool esValida;
  final String? motivo;
  final AntiCheatVeredicto? tipo;

  const AntiCheatSesionResultado({
    required this.esValida,
    required this.motivo,
    this.tipo,
  });
}