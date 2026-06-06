// test/services/stats_service_test.dart
//
// Unit tests for pure-Dart logic in StatsService.
// No Firebase — all helpers are stateless functions.

import 'package:flutter_test/flutter_test.dart';
import 'package:RiskRunner/services/stats_service.dart';

CarreraStats _c({
  String id = 'x',
  double km = 5.0,
  int seg = 1800,
  DateTime? fecha,
}) =>
    CarreraStats(
      id: id,
      fecha: fecha ?? DateTime.now(),
      distanciaKm: km,
      tiempoSeg: seg,
      ritmoMinKm: StatsService.ritmoMinKm(km, seg),
      zona: ZonaRitmo.moderado,
      calles: [],
      ruta: [],
    );

void main() {
  // ── velocidadKmh ────────────────────────────────────────────────────────────
  group('velocidadKmh', () {
    test('10 km en 3600 s → 10 km/h', () {
      expect(StatsService.velocidadKmh(10.0, 3600), closeTo(10.0, 0.001));
    });
    test('5 km en 1800 s → 10 km/h', () {
      expect(StatsService.velocidadKmh(5.0, 1800), closeTo(10.0, 0.001));
    });
    test('tiempo 0 → 0.0 (no divide por cero)', () {
      expect(StatsService.velocidadKmh(5.0, 0), 0.0);
    });
  });

  // ── ritmoMinKm ──────────────────────────────────────────────────────────────
  group('ritmoMinKm', () {
    test('5 km en 30 min → 6 min/km', () {
      expect(StatsService.ritmoMinKm(5.0, 1800), closeTo(6.0, 0.001));
    });
    test('10 km en 60 min → 6 min/km', () {
      expect(StatsService.ritmoMinKm(10.0, 3600), closeTo(6.0, 0.001));
    });
    test('distancia 0 → 0.0 (no divide por cero)', () {
      expect(StatsService.ritmoMinKm(0.0, 600), 0.0);
    });
  });

  // ── calcularPrediccion ──────────────────────────────────────────────────────
  group('calcularPrediccion', () {
    test('lista vacía → null', () {
      expect(StatsService.calcularPrediccion([]), isNull);
    });

    test('ignora carreras con distancia < 1 km', () {
      final carreras = [_c(km: 0.5, seg: 180)];
      expect(StatsService.calcularPrediccion(carreras), isNull);
    });

    test('con 5 carreras de 5 km a 6 min/km devuelve tiempos coherentes', () {
      final carreras = List.generate(5, (i) => _c(id: 'r$i'));
      final pred = StatsService.calcularPrediccion(carreras);
      expect(pred, isNotNull);
      // 5k < 10k < media maratón en duración
      expect(pred!.tiempo5k.inSeconds, lessThan(pred.tiempo10k.inSeconds));
      expect(pred.tiempo10k.inSeconds, lessThan(pred.tiempoMediaMaraton.inSeconds));
    });

    test('ritmoBase positivo', () {
      final carreras = List.generate(3, (i) => _c(id: 'r$i', km: 8.0, seg: 2880));
      final pred = StatsService.calcularPrediccion(carreras);
      expect(pred!.ritmoBase, greaterThan(0));
    });
  });

  // ── calcularTendencia4Semanas ───────────────────────────────────────────────
  group('calcularTendencia4Semanas', () {
    test('siempre devuelve exactamente 4 puntos', () {
      expect(StatsService.calcularTendencia4Semanas([]).length, 4);
    });

    test('sin carreras todos los ritmos son 0', () {
      final puntos = StatsService.calcularTendencia4Semanas([]);
      expect(puntos.every((p) => p.ritmoMedio == 0), isTrue);
    });

    test('carrera de esta semana aparece en la última semana', () {
      // Restar 1 hora para evitar coincidencia al milisegundo con DateTime.now() interno
      final fecha = DateTime.now().subtract(const Duration(hours: 1));
      final carreras = [_c(km: 5.0, seg: 1500, fecha: fecha)];
      final puntos = StatsService.calcularTendencia4Semanas(carreras);
      final ultimaSemana = puntos.last;
      expect(ultimaSemana.numCarreras, 1);
      expect(ultimaSemana.distanciaTotal, closeTo(5.0, 0.001));
    });
  });

  // ── calcularComparativaSemanal ──────────────────────────────────────────────
  group('calcularComparativaSemanal', () {
    test('sin carreras → todo cero', () {
      final comp = StatsService.calcularComparativaSemanal([]);
      expect(comp.kmEstaSemana, 0.0);
      expect(comp.kmSemanaAnterior, 0.0);
      expect(comp.carrerasEstaSemana, 0);
    });

    test('carrera de hoy cuenta en esta semana', () {
      final comp = StatsService.calcularComparativaSemanal(
          [_c(km: 7.0, seg: 2100, fecha: DateTime.now())]);
      expect(comp.kmEstaSemana, closeTo(7.0, 0.001));
      expect(comp.kmSemanaAnterior, 0.0);
    });

    test('deltaKm correcto cuando esta semana supera a la anterior', () {
      final ahora = DateTime.now();
      final semanaAnterior = ahora.subtract(const Duration(days: 8));
      final comp = StatsService.calcularComparativaSemanal([
        _c(km: 10.0, seg: 3000, fecha: ahora),
        _c(km: 6.0,  seg: 1800, fecha: semanaAnterior),
      ]);
      expect(comp.mejorKm, isTrue);
      expect(comp.deltaKm, greaterThan(0));
    });
  });

  // ── ComparativaSemanal.deltaKmStr ───────────────────────────────────────────
  group('ComparativaSemanal.deltaKmStr', () {
    test('sin semana anterior devuelve "+X km"', () {
      final comp = StatsService.calcularComparativaSemanal(
          [_c(km: 5.0, seg: 1800, fecha: DateTime.now())]);
      expect(comp.deltaKmStr, contains('km'));
    });
  });
}
