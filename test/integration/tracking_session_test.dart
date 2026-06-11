// test/integration/tracking_session_test.dart
//
// Integration tests: TrackingService + RunSessionNotifier + AntiCheatService
// trabajando juntos con instancias reales y GPS inyectado.
//
// Diferencia con los unit tests:
//   - Unit: cada servicio aislado con colaboradores mockeados/stub
//   - Integration: los tres servicios reales, se verifica el contrato entre ellos

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:RiskRunner/services/anticheat_service.dart';
import 'package:RiskRunner/services/run_session_notifier.dart';
import 'package:RiskRunner/services/tracking_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _lat0 = 40.0;
const _lng0 = -3.0;
final _t0   = DateTime(2025, 6, 1, 8, 0, 0);

Position _pos(double lat, double lng, {
  double    altitude  = 0.0,
  double    speed     = 0.0,
  Duration  dt        = Duration.zero,
}) =>
    Position(
      latitude:         lat,
      longitude:        lng,
      altitude:         altitude,
      altitudeAccuracy: 1,
      accuracy:         5,
      heading:          0,
      headingAccuracy:  0,
      speed:            speed,
      speedAccuracy:    0,
      timestamp:        _t0.add(dt),
      floor:            null,
      isMocked:         false,
    );

// ── Fixture ───────────────────────────────────────────────────────────────────

late StreamController<Position> _posCtrl;
late RunSessionNotifier          _session;
late AntiCheatService            _antiCheat;
late TrackingService             _svc;

void _build() {
  _posCtrl   = StreamController<Position>.broadcast();
  _session   = RunSessionNotifier();
  _antiCheat = AntiCheatService();
  _svc = TrackingService(
    session:               _session,
    antiCheat:             _antiCheat,
    positionStreamFactory: () => _posCtrl.stream,
  );
  _session.startSession();
  _svc.start();
}

Future<void> _tearDown() async {
  _svc.dispose();
  await _posCtrl.close();
  _session.dispose();
}

Future<void> _feed(Position pos) async {
  _posCtrl.add(pos);
  await Future.delayed(Duration.zero);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(_build);
  tearDown(_tearDown);

  // ── Flujo básico: GPS → métricas ──────────────────────────────────────────
  group('métricas end-to-end', () {
    test('distanciaTotal acumula 2 segmentos de ~55 m', () async {
      await _feed(_pos(_lat0,          _lng0, dt: Duration.zero));
      await _feed(_pos(_lat0 + 0.0005, _lng0, dt: const Duration(seconds: 10)));
      await _feed(_pos(_lat0 + 0.001,  _lng0, dt: const Duration(seconds: 20)));

      // 2 × ~55 m = ~0.11 km
      expect(_session.distanciaTotal, greaterThan(0.05));
      expect(_session.distanciaTotal, lessThan(0.20));
    });

    test('velocidadKmh > 0 después del segundo punto con delta temporal real', () async {
      // 55 m en 10 s = ~19.8 km/h → tras smoothing ~7.9 km/h
      await _feed(_pos(_lat0,          _lng0, dt: Duration.zero));
      await _feed(_pos(_lat0 + 0.0005, _lng0, dt: const Duration(seconds: 10)));

      expect(_session.velocidadKmh, greaterThan(0));
    });

    test('velocidadMaxKmh se actualiza con el pico más alto', () async {
      // Primer tramo: ~55 m en 10 s ≈ 7.9 km/h (smoothed)
      await _feed(_pos(_lat0,          _lng0, dt: Duration.zero));
      await _feed(_pos(_lat0 + 0.0005, _lng0, dt: const Duration(seconds: 10)));
      final velMax1 = _session.velocidadMaxKmh;

      // Segundo tramo: mismo espacio en 3 s → velocidad más alta
      await _feed(_pos(_lat0 + 0.001, _lng0, dt: const Duration(seconds: 13)));
      expect(_session.velocidadMaxKmh, greaterThanOrEqualTo(velMax1));
    });

    test('elevacionGanada ≈ 20 m con 3 puntos ascendentes', () async {
      await _feed(_pos(_lat0,          _lng0, altitude: 100, dt: Duration.zero));
      await _feed(_pos(_lat0 + 0.0005, _lng0, altitude: 100, dt: const Duration(seconds: 10)));
      await _feed(_pos(_lat0 + 0.001,  _lng0, altitude: 120, dt: const Duration(seconds: 20)));

      expect(_session.elevacionGanada, closeTo(20.0, 0.5));
      expect(_session.elevacionPerdida, 0.0);
    });

    test('elevacionPerdida ≈ 15 m con 3 puntos descendentes', () async {
      await _feed(_pos(_lat0,          _lng0, altitude: 200, dt: Duration.zero));
      await _feed(_pos(_lat0 + 0.0005, _lng0, altitude: 200, dt: const Duration(seconds: 10)));
      await _feed(_pos(_lat0 + 0.001,  _lng0, altitude: 185, dt: const Duration(seconds: 20)));

      expect(_session.elevacionPerdida, closeTo(15.0, 0.5));
      expect(_session.elevacionGanada, 0.0);
    });

    test('GpsPointEvent lleva bearing correcto al moverse al norte', () async {
      final events = <TrackingEvent>[];
      _svc.events.listen(events.add);

      await _feed(_pos(_lat0,          _lng0, dt: Duration.zero));
      await _feed(_pos(_lat0 + 0.0005, _lng0, dt: const Duration(seconds: 10)));

      final e = events[1] as GpsPointEvent;
      expect(e.bearing, closeTo(0.0, 1.5));
    });

    test('GpsPointEvent lleva bearing correcto al moverse al este', () async {
      final events = <TrackingEvent>[];
      _svc.events.listen(events.add);

      await _feed(_pos(_lat0, _lng0,          dt: Duration.zero));
      await _feed(_pos(_lat0, _lng0 + 0.0007, dt: const Duration(seconds: 10))); // ~59 m este

      final e = events[1] as GpsPointEvent;
      expect(e.bearing, closeTo(90.0, 2.0));
    });
  });

  // ── Pausa ─────────────────────────────────────────────────────────────────
  group('pausa / reanudación', () {
    test('puntos durante pausa no acumulan distancia ni emiten eventos', () async {
      final events = <TrackingEvent>[];
      _svc.events.listen(events.add);

      await _feed(_pos(_lat0, _lng0, dt: Duration.zero));
      _session.setPaused(true);
      await _feed(_pos(_lat0 + 0.0005, _lng0, dt: const Duration(seconds: 10)));

      expect(_session.distanciaTotal, 0.0);
      expect(events.length, 1); // solo el primer punto
    });

    test('al reanudar se sigue acumulando distancia desde el primer punto válido', () async {
      await _feed(_pos(_lat0, _lng0, dt: Duration.zero));

      _session.setPaused(true);
      await _feed(_pos(_lat0 + 0.0005, _lng0, dt: const Duration(seconds: 10))); // ignorado

      _session.setPaused(false);
      // El anticheat no vio el punto pausado — su referencia sigue siendo _lat0.
      // Usamos < 80m (límite warmup) para que el primer punto post-pausa sea válido.
      await _feed(_pos(_lat0 + 0.0006, _lng0, dt: const Duration(seconds: 20))); // ~66 m

      expect(_session.distanciaTotal, greaterThan(0));
    });
  });

  // ── AntiCheat integrado ───────────────────────────────────────────────────
  group('AntiCheat integrado', () {
    Future<void> pasarWarmup() async {
      for (int i = 0; i < 9; i++) {
        await _feed(_pos(
          _lat0 + i * 0.00001, _lng0,
          dt: Duration(seconds: i * 3),
        ));
      }
    }

    test('6 teletransportes fuera de warmup emiten AntiCheatCancelEvent', () async {
      final events = <TrackingEvent>[];
      _svc.events.listen(events.add);

      await pasarWarmup();

      for (int i = 1; i <= 6; i++) {
        await _feed(_pos(
          _lat0 + i * 0.003, _lng0, // ~333 m por salto > 250 m cap
          speed: 100.0,              // chip speed alto → no pasa como spike GPS
          dt: Duration(seconds: 27 + i),
        ));
      }

      expect(events.whereType<AntiCheatCancelEvent>(), isNotEmpty);
      expect(_antiCheat.sesionCancelada, isTrue);
    });

    test('puntos legítimos durante y después del warmup NO cancelan la sesión', () async {
      // 20 puntos a ~55 m cada uno, 10 s de separación → ~19.8 km/h < 22 km/h límite
      for (int i = 0; i < 20; i++) {
        await _feed(_pos(
          _lat0 + i * 0.0005, _lng0,
          dt: Duration(seconds: i * 10),
        ));
      }

      expect(_antiCheat.sesionCancelada, isFalse);
      expect(_session.distanciaTotal, greaterThan(0.5)); // >20 tramos de 55 m = >1 km
    });
  });

  // ── Stop + restart ────────────────────────────────────────────────────────
  group('stop y reinicio', () {
    test('después de stop+startSession las métricas vuelven a cero', () async {
      await _feed(_pos(_lat0,          _lng0, dt: Duration.zero));
      await _feed(_pos(_lat0 + 0.0005, _lng0, dt: const Duration(seconds: 10)));

      _svc.stop();
      _session.stopSession();
      _session.startSession();
      _svc.start();

      // Primer punto del nuevo ciclo — no añade distancia
      await _feed(_pos(_lat0, _lng0, dt: Duration.zero));

      expect(_session.distanciaTotal, 0.0);
    });

    test('bearing se resetea a 0 tras stop+restart', () async {
      // Establece bearing ~90° (este)
      await _feed(_pos(_lat0, _lng0,          dt: Duration.zero));
      await _feed(_pos(_lat0, _lng0 + 0.0007, dt: const Duration(seconds: 10)));

      _svc.stop();
      _session.stopSession();
      _session.startSession();
      _svc.start();

      final events2 = <TrackingEvent>[];
      _svc.events.listen(events2.add);
      await _feed(_pos(_lat0, _lng0, dt: Duration.zero));

      expect((events2.first as GpsPointEvent).bearing, 0.0);
    });
  });
}
