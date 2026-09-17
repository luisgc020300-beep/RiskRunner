// test/services/territory_service_test.dart
//
// Unit tests for TerritoryService pure-Dart methods.
// No Firebase required — only geometry calculations.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:RiskRunner/services/territory_service.dart';

void main() {
  // ── calcularAreaM2 ──────────────────────────────────────────────────────────
  group('calcularAreaM2', () {
    test('devuelve 0 con 0 puntos', () {
      expect(TerritoryService.calcularAreaM2([]), 0);
    });

    test('devuelve 0 con 1 punto', () {
      expect(TerritoryService.calcularAreaM2([const LatLng(40, -3)]), 0);
    });

    test('devuelve 0 con 2 puntos', () {
      expect(TerritoryService.calcularAreaM2([
        const LatLng(40.0,   -3.0),
        const LatLng(40.001, -3.0),
      ]), 0);
    });

    // Cuadrado de 0.001° × 0.001° en 40°N.
    // cosLat ≈ 0.766 → ancho ≈ 85.3 m, alto ≈ 111.3 m → área ≈ 9490 m²
    test('cuadrado 0.001° × 0.001° en 40°N → ≈ 9490 m²', () {
      const pts = [
        LatLng(40.000, -3.000),
        LatLng(40.000, -2.999),
        LatLng(40.001, -2.999),
        LatLng(40.001, -3.000),
      ];
      expect(TerritoryService.calcularAreaM2(pts), closeTo(9490, 150));
    });

    test('triángulo rectángulo ≈ mitad del cuadrado equivalente', () {
      const pts = [
        LatLng(40.000, -3.000),
        LatLng(40.001, -3.000),
        LatLng(40.000, -2.999),
      ];
      final area = TerritoryService.calcularAreaM2(pts);
      expect(area, greaterThan(4000));
      expect(area, lessThan(5500));
    });

    test('polígono en sentido horario y antihorario da el mismo resultado', () {
      const ccw = [
        LatLng(40.000, -3.000),
        LatLng(40.000, -2.999),
        LatLng(40.001, -2.999),
        LatLng(40.001, -3.000),
      ];
      final cw = ccw.reversed.toList();
      expect(
        TerritoryService.calcularAreaM2(ccw),
        closeTo(TerritoryService.calcularAreaM2(cw), 1),
      );
    });

    test('cuadrado doble tiene área 4× mayor que el cuadrado unitario', () {
      const small = [
        LatLng(40.000, -3.000), LatLng(40.000, -2.999),
        LatLng(40.001, -2.999), LatLng(40.001, -3.000),
      ];
      const large = [
        LatLng(40.000, -3.000), LatLng(40.000, -2.998),
        LatLng(40.002, -2.998), LatLng(40.002, -3.000),
      ];
      final aSmall = TerritoryService.calcularAreaM2(small);
      final aLarge = TerritoryService.calcularAreaM2(large);
      expect(aLarge, closeTo(aSmall * 4, aSmall * 0.1));
    });

    test('área es positiva para cualquier orientación', () {
      const pts = [
        LatLng(40.000, -3.000),
        LatLng(40.002, -3.001),
        LatLng(40.001, -2.998),
        LatLng(40.003, -2.999),
      ];
      expect(TerritoryService.calcularAreaM2(pts), greaterThan(0));
    });
  });

  // ── distanciaCierreM ────────────────────────────────────────────────────────
  group('distanciaCierreM', () {
    test('devuelve 0 con menos de 2 puntos', () {
      expect(TerritoryService.distanciaCierreM([]), 0);
      expect(TerritoryService.distanciaCierreM([const LatLng(40, -3)]), 0);
    });

    test('devuelve 0 cuando el punto inicial y final coinciden', () {
      const pts = [
        LatLng(40.000, -3.000),
        LatLng(40.001, -3.000),
        LatLng(40.000, -3.000),
      ];
      expect(TerritoryService.distanciaCierreM(pts), closeTo(0, 0.01));
    });

    test('circuito bien cerrado (~7 m de separación) queda por debajo del máximo', () {
      const pts = [
        LatLng(40.00000, -3.00000),
        LatLng(40.00100, -3.00000),
        LatLng(40.00100, -3.00100),
        LatLng(40.00005, -3.00005), // ~7 m de (40.00000, -3.00000)
      ];
      final cierre = TerritoryService.distanciaCierreM(pts);
      expect(cierre, lessThan(kDistanciaMaximaCierreM));
    });

    test('línea recta sin cerrar supera el máximo de cierre', () {
      const pts = [
        LatLng(40.00000, -3.00000),
        LatLng(40.00100, -3.00000),
        LatLng(40.00200, -3.00000),
        LatLng(40.00300, -3.00000), // ~333 m del punto inicial
      ];
      final cierre = TerritoryService.distanciaCierreM(pts);
      expect(cierre, greaterThan(kDistanciaMaximaCierreM));
    });
  });

  // ── geocellDe ────────────────────────────────────────────────────────────────
  group('geocellDe', () {
    test('dos puntos en la misma celda dan la misma geocelda', () {
      expect(TerritoryService.geocellDe(0.10, 0.10),
          TerritoryService.geocellDe(0.12, 0.12));
    });

    test('cruzar el borde de una celda cambia la geocelda', () {
      // kGeocellSizeDeg = 0.05 → el borde está en 0.05, 0.10, ...
      final antes    = TerritoryService.geocellDe(0.049, 0.0);
      final despues  = TerritoryService.geocellDe(0.051, 0.0);
      expect(antes, isNot(equals(despues)));
    });

    test('coordenadas negativas (hemisferio sur/oeste) no rompen el cálculo', () {
      // floor(-0.01/0.05) = floor(-0.2) = -1, no 0
      expect(TerritoryService.geocellDe(-0.01, -0.01), '-1_-1');
    });

    test('el origen (0,0) cae en la celda 0_0', () {
      expect(TerritoryService.geocellDe(0.0, 0.0), '0_0');
    });
  });

  // ── geocellsParaRadio ──────────────────────────────────────────────────────────
  group('geocellsParaRadio', () {
    test('radio 0 devuelve solo la celda del propio punto', () {
      final celdas = TerritoryService.geocellsParaRadio(0.1, 0.1, 0);
      expect(celdas, [TerritoryService.geocellDe(0.1, 0.1)]);
    });

    test('radio igual al tamaño de celda cubre las 8 celdas vecinas (3x3)', () {
      final celdas = TerritoryService.geocellsParaRadio(0.1, 0.1, kGeocellSizeDeg);
      expect(celdas.length, 9);
      expect(celdas.toSet().length, 9); // sin duplicados
      expect(celdas, contains(TerritoryService.geocellDe(0.1, 0.1)));
    });

    test('un radio muy grande se recorta a 2 celdas de margen (5x5), no más', () {
      final celdas = TerritoryService.geocellsParaRadio(0.1, 0.1, 5.0);
      expect(celdas.length, 25);
    });

    test('el punto de búsqueda siempre está entre las celdas devueltas', () {
      const lat = 40.4167, lng = -3.70325;
      final celdas = TerritoryService.geocellsParaRadio(lat, lng, 0.05);
      expect(celdas, contains(TerritoryService.geocellDe(lat, lng)));
    });
  });
}
