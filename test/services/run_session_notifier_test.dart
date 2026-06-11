// test/services/run_session_notifier_test.dart
//
// Unit tests for RunSessionNotifier — pure Dart, no Firebase, no Flutter.

import 'package:flutter_test/flutter_test.dart';
import 'package:RiskRunner/services/run_session_notifier.dart';
import 'package:RiskRunner/services/narrador_service.dart';

void main() {
  // ── startSession ──────────────────────────────────────────────────────────
  group('startSession', () {
    test('activa isTracking y desactiva isPaused', () {
      final s = RunSessionNotifier();
      s.startSession();
      expect(s.isTracking, isTrue);
      expect(s.isPaused,   isFalse);
    });

    test('resetea todas las métricas a cero', () {
      final s = RunSessionNotifier()
        ..distanciaTotal  = 5.0
        ..velocidadKmh    = 12.0
        ..velocidadMaxKmh = 15.0
        ..elevacionGanada  = 80.0
        ..elevacionPerdida = 30.0
        ..kmUltimoSplit    = 3
        ..tiempoUltimoSplitSeg = 900.0
        ..porcentajeRuta  = 0.7
        ..fueraDeRuta     = true
        ..rutaCompletada  = true;
      s.splits.addAll([5.0, 4.8]);

      s.startSession();

      expect(s.distanciaTotal,       0.0);
      expect(s.velocidadKmh,         0.0);
      expect(s.velocidadMaxKmh,      0.0);
      expect(s.elevacionGanada,       0.0);
      expect(s.elevacionPerdida,      0.0);
      expect(s.splits,               isEmpty);
      expect(s.kmUltimoSplit,         0);
      expect(s.tiempoUltimoSplitSeg, 0.0);
      expect(s.porcentajeRuta,       0.0);
      expect(s.fueraDeRuta,          isFalse);
      expect(s.rutaCompletada,       isFalse);
      expect(s.mensajeNarrador,      isNull);
    });

    test('notifica listeners', () {
      final s = RunSessionNotifier();
      var notified = false;
      s.addListener(() => notified = true);
      s.startSession();
      expect(notified, isTrue);
    });
  });

  // ── stopSession ───────────────────────────────────────────────────────────
  group('stopSession', () {
    test('desactiva tracking y pone velocidad a 0', () {
      final s = RunSessionNotifier()..startSession();
      s.updateGpsMetrics(
        distanciaTotal: 3.0, velocidadKmh: 10.0, velocidadMaxKmh: 14.0,
        elevacionGanada: 20.0, elevacionPerdida: 5.0,
      );
      s.stopSession();
      expect(s.isTracking,   isFalse);
      expect(s.isPaused,     isFalse);
      expect(s.velocidadKmh, 0.0);
    });

    test('conserva distancia y métricas acumuladas tras parar', () {
      final s = RunSessionNotifier()..startSession();
      s.updateGpsMetrics(
        distanciaTotal: 4.5, velocidadKmh: 11.0, velocidadMaxKmh: 16.0,
        elevacionGanada: 50.0, elevacionPerdida: 10.0,
      );
      s.stopSession();
      expect(s.distanciaTotal,  4.5);
      expect(s.velocidadMaxKmh, 16.0);
      expect(s.elevacionGanada,  50.0);
    });
  });

  // ── setPaused ─────────────────────────────────────────────────────────────
  group('setPaused', () {
    test('pausar pone velocidad a 0', () {
      final s = RunSessionNotifier()..startSession();
      s.updateGpsMetrics(
        distanciaTotal: 1.0, velocidadKmh: 9.0, velocidadMaxKmh: 9.0,
        elevacionGanada: 0.0, elevacionPerdida: 0.0,
      );
      s.setPaused(true);
      expect(s.isPaused,     isTrue);
      expect(s.velocidadKmh, 0.0);
    });

    test('reanudar mantiene isPaused = false', () {
      final s = RunSessionNotifier()..startSession();
      s.setPaused(true);
      s.setPaused(false);
      expect(s.isPaused, isFalse);
    });
  });

  // ── resumeSession ─────────────────────────────────────────────────────────
  group('resumeSession', () {
    test('restaura distancia y queda en pausa', () {
      final s = RunSessionNotifier();
      s.resumeSession(3.7);
      expect(s.isTracking,    isTrue);
      expect(s.isPaused,      isTrue);
      expect(s.distanciaTotal, 3.7);
    });
  });

  // ── updateGpsMetrics ──────────────────────────────────────────────────────
  group('updateGpsMetrics', () {
    test('actualiza todos los campos y notifica', () {
      final s = RunSessionNotifier()..startSession();
      var notified = false;
      s.addListener(() => notified = true);

      s.updateGpsMetrics(
        distanciaTotal: 2.5,  velocidadKmh: 11.0, velocidadMaxKmh: 13.0,
        elevacionGanada: 40.0, elevacionPerdida: 8.0,
      );

      expect(s.distanciaTotal,  2.5);
      expect(s.velocidadKmh,    11.0);
      expect(s.velocidadMaxKmh, 13.0);
      expect(s.elevacionGanada,  40.0);
      expect(s.elevacionPerdida, 8.0);
      expect(notified, isTrue);
    });
  });

  // ── addSplit ──────────────────────────────────────────────────────────────
  group('addSplit', () {
    test('acumula splits en orden', () {
      final s = RunSessionNotifier()..startSession();
      s.addSplit(5.1);
      s.addSplit(4.8);
      s.addSplit(5.3);
      expect(s.splits, [5.1, 4.8, 5.3]);
    });

    test('startSession limpia splits previos', () {
      final s = RunSessionNotifier()..startSession();
      s.addSplit(5.0);
      s.startSession();
      expect(s.splits, isEmpty);
    });
  });

  // ── updateRuta ────────────────────────────────────────────────────────────
  group('updateRuta', () {
    test('actualiza solo los campos proporcionados', () {
      final s = RunSessionNotifier()..startSession();
      s.updateRuta(porcentaje: 0.45);
      expect(s.porcentajeRuta, 0.45);
      expect(s.fueraDeRuta,    isFalse); // no cambiado

      s.updateRuta(fuera: true);
      expect(s.fueraDeRuta,    isTrue);
      expect(s.porcentajeRuta, 0.45);   // no cambiado
    });

    test('completada → rutaCompletada = true', () {
      final s = RunSessionNotifier()..startSession();
      s.updateRuta(completada: true);
      expect(s.rutaCompletada, isTrue);
    });
  });

  // ── ritmoStr ──────────────────────────────────────────────────────────────
  group('ritmoStr', () {
    test('devuelve --:-- cuando no está tracking', () {
      final s = RunSessionNotifier();
      expect(s.ritmoStr, '--:--');
    });

    test('devuelve --:-- cuando está pausado', () {
      final s = RunSessionNotifier()..startSession();
      s.updateGpsMetrics(
        distanciaTotal: 1.0, velocidadKmh: 10.0, velocidadMaxKmh: 10.0,
        elevacionGanada: 0.0, elevacionPerdida: 0.0,
      );
      s.setPaused(true);
      expect(s.ritmoStr, '--:--');
    });

    test('devuelve --:-- con velocidad < 0.5 km/h', () {
      final s = RunSessionNotifier()..startSession();
      s.updateGpsMetrics(
        distanciaTotal: 0.01, velocidadKmh: 0.3, velocidadMaxKmh: 0.3,
        elevacionGanada: 0.0, elevacionPerdida: 0.0,
      );
      expect(s.ritmoStr, '--:--');
    });

    test('10 km/h → 6\'00"', () {
      final s = RunSessionNotifier()..startSession();
      s.updateGpsMetrics(
        distanciaTotal: 1.0, velocidadKmh: 10.0, velocidadMaxKmh: 10.0,
        elevacionGanada: 0.0, elevacionPerdida: 0.0,
      );
      expect(s.ritmoStr, "6'00\"");
    });

    test('12 km/h → 5\'00"', () {
      final s = RunSessionNotifier()..startSession();
      s.updateGpsMetrics(
        distanciaTotal: 1.0, velocidadKmh: 12.0, velocidadMaxKmh: 12.0,
        elevacionGanada: 0.0, elevacionPerdida: 0.0,
      );
      expect(s.ritmoStr, "5'00\"");
    });

    test('8 km/h → 7\'30"', () {
      final s = RunSessionNotifier()..startSession();
      s.updateGpsMetrics(
        distanciaTotal: 1.0, velocidadKmh: 8.0, velocidadMaxKmh: 8.0,
        elevacionGanada: 0.0, elevacionPerdida: 0.0,
      );
      expect(s.ritmoStr, "7'30\"");
    });
  });

  // ── setNarratorMessage ────────────────────────────────────────────────────
  group('setNarratorMessage', () {
    test('asigna y limpia mensajeNarrador', () {
      final s = RunSessionNotifier();
      const msg = MensajeNarrador(texto: 'Buen ritmo', emoji: '💪', tipo: NarradorTipo.rendimiento);
      s.setNarratorMessage(msg);
      expect(s.mensajeNarrador, msg);
      s.setNarratorMessage(null);
      expect(s.mensajeNarrador, isNull);
    });
  });
}
