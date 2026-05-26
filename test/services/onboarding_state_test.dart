// test/services/onboarding_state_test.dart
//
// Tests for the pure-Dart logic in OnboardingState.
// No Firebase — tests computed properties on the model.

import 'package:flutter_test/flutter_test.dart';
import 'package:RiskRunner/services/onboarding_service.dart';

void main() {
  group('OnboardingState.onboardingCompleto', () {
    test('run 0-4 → no completo', () {
      for (final run in [0, 1, 2, 3, 4]) {
        final s = OnboardingState(
            slidesVistos: true, runActual: run, tooltipsVistos: const {});
        expect(s.onboardingCompleto, false,
            reason: 'runActual=$run debería ser incompleto');
      }
    });

    test('run 5 → completo', () {
      const s = OnboardingState(
          slidesVistos: true, runActual: 5, tooltipsVistos: {});
      expect(s.onboardingCompleto, true);
    });

    test('run > 5 → también completo', () {
      const s = OnboardingState(
          slidesVistos: true, runActual: 10, tooltipsVistos: {});
      expect(s.onboardingCompleto, true);
    });
  });

  group('OnboardingState.tooltipsPendientes', () {
    test('run 0 sin ningún tooltip visto → devuelve los 3 del run 0', () {
      const s = OnboardingState(
          slidesVistos: false, runActual: 0, tooltipsVistos: {});
      expect(s.tooltipsPendientes,
          containsAll(['bienvenida', 'primer_run', 'color_territorio']));
      expect(s.tooltipsPendientes.length, 3);
    });

    test('run 0 con un tooltip ya visto → excluye el visto', () {
      const s = OnboardingState(
          slidesVistos: false,
          runActual: 0,
          tooltipsVistos: {'bienvenida'});
      expect(s.tooltipsPendientes, isNot(contains('bienvenida')));
      expect(s.tooltipsPendientes.length, 2);
    });

    test('run 0 con todos los tooltips vistos → lista vacía', () {
      const s = OnboardingState(
          slidesVistos: false,
          runActual: 0,
          tooltipsVistos: {'bienvenida', 'primer_run', 'color_territorio'});
      expect(s.tooltipsPendientes, isEmpty);
    });

    test('run 1 → devuelve los tooltips del run 1', () {
      const s = OnboardingState(
          slidesVistos: true, runActual: 1, tooltipsVistos: {});
      expect(s.tooltipsPendientes,
          containsAll(['conquista_territorio', 'mapa_live', 'color_hint', 'pausa_retirada']));
    });

    test('run sin tooltips definidos (>5) → lista vacía', () {
      const s = OnboardingState(
          slidesVistos: true, runActual: 99, tooltipsVistos: {});
      expect(s.tooltipsPendientes, isEmpty);
    });

    test('tooltipsVistos de otros runs no afectan al run actual', () {
      // Run 1 tiene ['conquista_territorio', 'mapa_live', 'color_hint', 'pausa_retirada']
      // Si tenemos vistos tooltips del run 0, no deben afectar al run 1
      const s = OnboardingState(
          slidesVistos: true,
          runActual: 1,
          tooltipsVistos: {'bienvenida', 'primer_run'});
      expect(s.tooltipsPendientes.length, 4);
    });
  });
}
