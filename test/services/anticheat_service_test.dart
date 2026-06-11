// test/services/anticheat_service_test.dart
//
// Unit tests for AntiCheatService pure logic.
// No Firebase — _guardarLogFirestore is fire-and-forget and silent on failure.

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:RiskRunner/services/anticheat_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Position _pos({
  double lat = 40.4168,
  double lng = -3.7038,
  double accuracy = 10.0,
  double speed = 3.0,   // m/s ≈ 10.8 km/h
  double altitude = 650.0,
  bool isMocked = false,
  DateTime? timestamp,
}) =>
    Position(
      latitude: lat,
      longitude: lng,
      accuracy: accuracy,
      altitude: altitude,
      altitudeAccuracy: 1.0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0.5,
      timestamp: timestamp ?? DateTime.now(),
      isMocked: isMocked,
    );

void main() {
  // ── analizarSesionCompleta (static — no Firestore) ───────────────────────

  group('analizarSesionCompleta', () {
    test('ruta de un solo punto siempre es válida', () {
      final r = AntiCheatService.analizarSesionCompleta(
        ruta: [const LatLng(40.41, -3.70)],
        tiempo: const Duration(minutes: 30),
        distanciaKm: 5.0,
      );
      expect(r.esValida, isTrue);
    });

    test('velocidad media dentro del límite → válida', () {
      // 10 km en 60 min = 10 km/h < 22 km/h
      final ruta = List.generate(
          10, (i) => LatLng(40.41 + i * 0.001, -3.70));
      final r = AntiCheatService.analizarSesionCompleta(
        ruta: ruta,
        tiempo: const Duration(minutes: 60),
        distanciaKm: 10.0,
      );
      expect(r.esValida, isTrue);
    });

    test('velocidad media imposible → inválida', () {
      final ruta = List.generate(
          10, (i) => LatLng(40.41 + i * 0.001, -3.70));
      final r = AntiCheatService.analizarSesionCompleta(
        ruta: ruta,
        tiempo: const Duration(minutes: 5),
        distanciaKm: 50.0, // 50 km en 5 min = 600 km/h
      );
      expect(r.esValida, isFalse);
      expect(r.tipo, AntiCheatVeredicto.velocidad);
    });

    test('ruta con zigzags extremos (>30%) → inválida', () {
      // Genera puntos que alternan dirección en 180° → patrón bot
      final ruta = <LatLng>[];
      for (int i = 0; i < 30; i++) {
        ruta.add(LatLng(40.41 + (i.isEven ? 0.001 : -0.001), -3.70));
      }
      final r = AntiCheatService.analizarSesionCompleta(
        ruta: ruta,
        tiempo: const Duration(minutes: 30),
        distanciaKm: 5.0,
      );
      expect(r.esValida, isFalse);
      expect(r.tipo, AntiCheatVeredicto.mockLocation);
    });

    test('ruta con pocos zigzags normales (curvas de carrera) → válida', () {
      // Ruta rectilínea sin cambios bruscos
      final ruta = List.generate(
          30, (i) => LatLng(40.41 + i * 0.0005, -3.70 + i * 0.0001));
      final r = AntiCheatService.analizarSesionCompleta(
        ruta: ruta,
        tiempo: const Duration(minutes: 30),
        distanciaKm: 5.0,
      );
      expect(r.esValida, isTrue);
    });
  });

  // ── AntiCheatConfig umbrales ─────────────────────────────────────────────

  group('AntiCheatConfig valores de umbral', () {
    test('velocidadMaxKmh es 22', () {
      expect(AntiCheatConfig.velocidadMaxKmh, 22.0);
    });
    test('distanciaAbsolutaMaxM es 250', () {
      expect(AntiCheatConfig.distanciaAbsolutaMaxM, 250.0);
    });
    test('infraccionesParaCancelar es 6', () {
      expect(AntiCheatConfig.infraccionesParaCancelar, 6);
    });
  });

  // ── analizarPunto — flujo básico ─────────────────────────────────────────

  group('analizarPunto', () {
    late AntiCheatService svc;
    final t0 = DateTime(2025, 6, 1, 8, 0, 0);

    setUp(() => svc = AntiCheatService()..resetear());

    test('primer punto siempre válido', () {
      final r = svc.analizarPunto(_pos(timestamp: t0));
      expect(r.esValido, isTrue);
      expect(r.veredicto, AntiCheatVeredicto.ok);
    });

    test('precisión GPS mala → inválido pero no cancela sesión', () {
      svc.analizarPunto(_pos(timestamp: t0)); // primer punto
      final r = svc.analizarPunto(
          _pos(accuracy: 100.0, timestamp: t0.add(const Duration(seconds: 3))));
      expect(r.esValido, isFalse);
      expect(r.veredicto, AntiCheatVeredicto.precisionBaja);
      expect(svc.sesionCancelada, isFalse);
    });

    test('movimiento normal en 3 s → válido', () {
      svc.analizarPunto(_pos(timestamp: t0));
      // +15 m en 3 s ≈ 5 m/s = 18 km/h — dentro del límite
      final r = svc.analizarPunto(_pos(
        lat: 40.4169, // ~11 m al norte
        timestamp: t0.add(const Duration(seconds: 3)),
        speed: 4.0, // 14.4 km/h chip GPS
      ));
      expect(r.esValido, isTrue);
    });

    test('sesionCancelada tras 6 infracciones consecutivas', () {
      // Los 8 primeros puntos están en warmup y no cuentan como infracciones.
      // Primero procesamos 9 puntos legítimos para salir del warmup, luego
      // generamos 6 teletransportes con chip-GPS también alto.
      for (int i = 0; i < 9; i++) {
        svc.analizarPunto(_pos(
          lat: 40.4168 + i * 0.00001, // movimiento mínimo, válido
          timestamp: t0.add(Duration(seconds: i * 3)),
        ));
      }
      expect(svc.sesionCancelada, isFalse);

      final base = t0.add(const Duration(seconds: 30));
      for (int i = 1; i <= 6; i++) {
        // Salto de ~330 m en 1 s — supera cap absoluto de 250 m
        svc.analizarPunto(_pos(
          lat: 40.4168 + i * 0.003, // ~333 m por paso
          timestamp: base.add(Duration(seconds: i)),
          speed: 100.0, // chip GPS también alto → no se ignora como spike
        ));
      }
      expect(svc.sesionCancelada, isTrue);
    });

    test('reset limpia el estado completamente', () {
      svc.analizarPunto(_pos(timestamp: t0));
      svc.resetear();
      expect(svc.sesionCancelada, isFalse);
      // Después del reset el siguiente punto es "primer punto" de nuevo
      final r = svc.analizarPunto(_pos(timestamp: t0));
      expect(r.esValido, isTrue);
    });

    // ── Warmup bypass fix ───────────────────────────────────────────────────
    group('warmup', () {
      test('salto >80m durante warmup es rechazado (no se añade a ruta)', () {
        svc.analizarPunto(_pos(timestamp: t0)); // primer punto
        // ~110m al norte — >80m pero <250m: debe ser rechazado
        final r = svc.analizarPunto(_pos(
          lat: 40.4178, // ≈110m desde 40.4168
          timestamp: t0.add(const Duration(seconds: 3)),
          speed: 3.0,
        ));
        expect(r.esValido, isFalse);
        expect(r.veredicto, AntiCheatVeredicto.teletransporte);
      });

      test('salto ≤80m durante warmup es aceptado (GPS estabilizándose)', () {
        svc.analizarPunto(_pos(timestamp: t0));
        // ~55m al norte — ≤80m: warmup lo acepta
        final r = svc.analizarPunto(_pos(
          lat: 40.4173, // ≈55m
          timestamp: t0.add(const Duration(seconds: 3)),
          speed: 3.0,
        ));
        expect(r.esValido, isTrue);
      });
    });

    // ── Speed near-zero bypass fix ──────────────────────────────────────────
    group('speed near-zero bypass', () {
      // Helper: avanza el servicio pasado el periodo warmup
      void pasarWarmup() {
        for (int i = 0; i < 9; i++) {
          svc.analizarPunto(_pos(
            lat: 40.4168 + i * 0.00001,
            timestamp: t0.add(Duration(seconds: i * 3)),
          ));
        }
      }

      test('speed≈0 spoofed no bypassa salto >80m fuera de warmup', () {
        pasarWarmup();
        // ~100m de salto con speed=0.1 m/s (0.36 km/h < velocidadMinChipKmh)
        final r = svc.analizarPunto(_pos(
          lat: 40.4168 + 9 * 0.00001 + 0.001, // ~110m del último punto
          timestamp: t0.add(const Duration(seconds: 30)),
          speed: 0.1, // spoofed near-zero
        ));
        expect(r.esValido, isFalse);
        expect(r.veredicto, AntiCheatVeredicto.teletransporte);
      });

      test('spike GPS con chip-speed plausible (≥1 km/h) sigue siendo aceptado', () {
        pasarWarmup();
        // Mismo salto pero con chip speed legítimo de 5 km/h (1.4 m/s)
        final r = svc.analizarPunto(_pos(
          lat: 40.4168 + 9 * 0.00001 + 0.001,
          timestamp: t0.add(const Duration(seconds: 30)),
          speed: 1.4, // 5.0 km/h — ≥1 km/h → se confía como spike posicional
        ));
        expect(r.esValido, isTrue);
      });
    });
  });
}
