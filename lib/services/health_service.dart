// lib/services/health_service.dart
//
// Registra las carreras completadas en Apple Health (iOS) y Google Health
// Connect (Android). Se llama al terminar sesión en cualquier modo.
// Todos los errores se capturan en silencio para no interrumpir el flujo.
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

class HealthService {
  static final Health _health = Health();
  static bool _configurado = false;

  static Future<void> _configurar() async {
    if (_configurado) return;
    await _health.configure();
    _configurado = true;
  }

  /// Pide permiso de escritura la primera vez que se llama.
  /// Devuelve true si el permiso fue concedido.
  static Future<bool> _pedirPermisos() async {
    try {
      await _configurar();
      return await _health.requestAuthorization(
        [
          HealthDataType.WORKOUT,
          HealthDataType.DISTANCE_WALKING_RUNNING,
          HealthDataType.ACTIVE_ENERGY_BURNED,
        ],
        permissions: [
          HealthDataAccess.WRITE,
          HealthDataAccess.WRITE,
          HealthDataAccess.WRITE,
        ],
      );
    } catch (e) {
      debugPrint('HealthService._pedirPermisos: $e');
      return false;
    }
  }

  /// Registra una carrera en Apple Health / Google Health Connect.
  ///
  /// [inicio] y [fin] delimitan la sesión.
  /// [distanciaKm] se usa para calcular distancia y calorías estimadas.
  static Future<void> registrarCarrera({
    required DateTime inicio,
    required DateTime fin,
    required double distanciaKm,
  }) async {
    if (distanciaKm <= 0) return;
    try {
      final autorizado = await _pedirPermisos();
      if (!autorizado) return;

      // ~65 kcal/km es una estimación conservadora para running
      final calorias = (distanciaKm * 65).round();
      final distanciaM = (distanciaKm * 1000).round();

      await _health.writeWorkoutData(
        activityType: HealthWorkoutActivityType.RUNNING,
        start: inicio,
        end: fin,
        totalEnergyBurned: calorias,
        totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
        totalDistance: distanciaM,
        totalDistanceUnit: HealthDataUnit.METER,
      );
    } catch (e) {
      debugPrint('HealthService.registrarCarrera: $e');
    }
  }
}
