// test/services/tracking_service_test.dart
//
// Unit tests for TrackingService — pure Dart, no Firebase, no GPS hardware.
// Injects positions via a broadcast StreamController; keeps jumps < 80m so
// AntiCheatService (warmup=8 pts, absMax=250m) accepts every test point.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:RiskRunner/services/anticheat_service.dart';
import 'package:RiskRunner/services/run_session_notifier.dart';
import 'package:RiskRunner/services/tracking_service.dart';

// ── Position helper ───────────────────────────────────────────────────────────
// 0.0005° lat ≈ 55 m  |  0.0007° lng at 40° ≈ 59 m  → within 80m anticheat limit

Position _pos(double lat, double lng, {
  double altitude = 0.0,
  double speed    = 0.0,
  DateTime? timestamp,
}) =>
    Position(
      latitude:         lat,
      longitude:        lng,
      altitude:         altitude,
      altitudeAccuracy: 1,
      accuracy:         5,      // 5 m < 35 m threshold → accepted
      heading:          0,
      headingAccuracy:  0,
      speed:            speed,
      speedAccuracy:    0,
      timestamp:        timestamp ?? DateTime.now(),
      floor:            null,
      isMocked:         false,
    );

// Base point for all tests
const _lat0 = 40.0;
const _lng0 = -3.0;

// ── Fixture ───────────────────────────────────────────────────────────────────

late StreamController<Position> _posCtrl;
late RunSessionNotifier         _session;
late AntiCheatService           _antiCheat;
late TrackingService            _svc;

void _buildSvc() {
  // broadcast so resume() can re-listen to the same controller
  _posCtrl   = StreamController<Position>.broadcast();
  _session   = RunSessionNotifier();
  _antiCheat = AntiCheatService();
  _svc = TrackingService(
    session:               _session,
    antiCheat:             _antiCheat,
    positionStreamFactory: () => _posCtrl.stream,
  );
  _svc.start();
}

Future<void> _feed(Position pos) async {
  _posCtrl.add(pos);
  await Future.delayed(Duration.zero);
}

Future<void> _tearDown() async {
  await _posCtrl.close();
  _svc.dispose();
  _session.dispose();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(_buildSvc);
  tearDown(_tearDown);

  // ── primer punto ──────────────────────────────────────────────────────────
  group('primer punto GPS', () {
    test('emite GpsPointEvent con bearing 0', () async {
      final events = <TrackingEvent>[];
      _svc.events.listen(events.add);

      await _feed(_pos(_lat0, _lng0));

      expect(events.length, 1);
      final e = events.first as GpsPointEvent;
      expect(e.punto, LatLng(_lat0, _lng0));
      expect(e.bearing, 0.0);
    });

    test('no incrementa distancia en el primer punto', () async {
      await _feed(_pos(_lat0, _lng0));
      expect(_session.distanciaTotal, 0.0);
    });
  });

  // ── distancia ─────────────────────────────────────────────────────────────
  group('cálculo de distancia', () {
    test('acumula distancia entre dos puntos (~55 m)', () async {
      await _feed(_pos(_lat0,        _lng0));
      await _feed(_pos(_lat0 + 0.0005, _lng0)); // ~55 m norte
      expect(_session.distanciaTotal, greaterThan(0));
      expect(_session.distanciaTotal, lessThan(0.1)); // < 100 m en km
    });

    test('distancia crece monotónicamente con más puntos', () async {
      await _feed(_pos(_lat0,           _lng0));
      await _feed(_pos(_lat0 + 0.0005,  _lng0));
      final d1 = _session.distanciaTotal;

      await _feed(_pos(_lat0 + 0.001, _lng0));
      expect(_session.distanciaTotal, greaterThan(d1));
    });
  });

  // ── bearing ───────────────────────────────────────────────────────────────
  group('bearing', () {
    test('movimiento puro al norte → bearing ≈ 0°', () async {
      final events = <TrackingEvent>[];
      _svc.events.listen(events.add);

      await _feed(_pos(_lat0,          _lng0));
      await _feed(_pos(_lat0 + 0.0005, _lng0)); // norte puro

      final e = events[1] as GpsPointEvent;
      expect(e.bearing, closeTo(0.0, 1.0));
    });

    test('movimiento puro al este → bearing ≈ 90°', () async {
      final events = <TrackingEvent>[];
      _svc.events.listen(events.add);

      await _feed(_pos(_lat0, _lng0));
      await _feed(_pos(_lat0, _lng0 + 0.0007)); // este puro (~59 m)

      final e = events[1] as GpsPointEvent;
      expect(e.bearing, closeTo(90.0, 2.0));
    });
  });

  // ── elevación ─────────────────────────────────────────────────────────────
  // _lastAltitude se fija en el 2º punto (cuando _lastPoint != null);
  // la diferencia se calcula a partir del 3º punto.
  group('elevación', () {
    test('acumula elevación ganada al subir > 0.5 m', () async {
      await _feed(_pos(_lat0,           _lng0, altitude: 100)); // punto base
      await _feed(_pos(_lat0 + 0.0005,  _lng0, altitude: 100)); // fija _lastAltitude
      await _feed(_pos(_lat0 + 0.001,   _lng0, altitude: 110)); // +10 m
      expect(_session.elevacionGanada, closeTo(10.0, 0.1));
    });

    test('acumula elevación perdida al bajar > 0.5 m', () async {
      await _feed(_pos(_lat0,           _lng0, altitude: 100));
      await _feed(_pos(_lat0 + 0.0005,  _lng0, altitude: 100));
      await _feed(_pos(_lat0 + 0.001,   _lng0, altitude: 90));  // -10 m
      expect(_session.elevacionPerdida, closeTo(10.0, 0.1));
    });

    test('ignora micro-variaciones ≤ 0.5 m', () async {
      await _feed(_pos(_lat0,           _lng0, altitude: 100));
      await _feed(_pos(_lat0 + 0.0005,  _lng0, altitude: 100));
      await _feed(_pos(_lat0 + 0.001,   _lng0, altitude: 100.3));
      expect(_session.elevacionGanada, 0.0);
    });
  });

  // ── isPaused guard ────────────────────────────────────────────────────────
  group('isPaused guard', () {
    test('ignora puntos GPS cuando la sesión está pausada', () async {
      final events = <TrackingEvent>[];
      _svc.events.listen(events.add);

      _session.setPaused(true);
      await _feed(_pos(_lat0, _lng0));

      expect(events, isEmpty);
    });

    test('procesa puntos cuando se reanuda', () async {
      final events = <TrackingEvent>[];
      _svc.events.listen(events.add);

      _session.setPaused(true);
      await _feed(_pos(_lat0, _lng0));
      _session.setPaused(false);
      await _feed(_pos(_lat0 + 0.0005, _lng0));

      expect(events.length, 1);
      expect(events.first, isA<GpsPointEvent>());
    });
  });

  // ── pause / resume ────────────────────────────────────────────────────────
  group('pause / resume', () {
    test('resume reanuda recepción de eventos', () async {
      final events = <TrackingEvent>[];
      _svc.events.listen(events.add);

      await _feed(_pos(_lat0, _lng0));
      _svc.pause();
      _svc.resume();
      await _feed(_pos(_lat0 + 0.0005, _lng0));

      expect(events.length, 2);
    });
  });

  // ── stop ──────────────────────────────────────────────────────────────────
  group('stop', () {
    test('bearing interno se resetea a 0 tras stop + restart', () async {
      // Establece bearing ~90° (este)
      await _feed(_pos(_lat0, _lng0));
      await _feed(_pos(_lat0, _lng0 + 0.0007)); // bearing ~90°
      _svc.stop();

      // Restart en el mismo servicio; _lastPoint = null → primer punto da bearing 0
      _svc.start();
      final events2 = <TrackingEvent>[];
      _svc.events.listen(events2.add);
      // Posición cercana a la anterior → AntiCheat (en warmup) la acepta
      await _feed(_pos(_lat0 + 0.0001, _lng0));

      expect((events2.first as GpsPointEvent).bearing, 0.0);
    });
  });

  // ── error GPS ─────────────────────────────────────────────────────────────
  group('GpsErrorEvent', () {
    test('emite GpsErrorEvent cuando el stream falla', () async {
      final events = <TrackingEvent>[];
      _svc.events.listen(events.add);

      _posCtrl.addError(Exception('GPS lost'));
      await Future.delayed(Duration.zero);

      expect(events.length, 1);
      expect(events.first, isA<GpsErrorEvent>());
    });
  });
}
