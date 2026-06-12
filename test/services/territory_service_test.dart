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
}
