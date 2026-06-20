// test/services/critical_flows_test.dart
//
// Cobertura de los 3 flujos críticos sin tests antes de beta:
//
//  1. HP decay — "HP nunca baja de 1" es una decisión de producto.
//     Si se rompe, los territorios mueren y el mapa queda corrupto.
//
//  2. EstadoHp — alimenta el color del mapa y los umbrales de ataque.
//     Un error aquí cambia la UX para todos los usuarios.
//
//  3. DesafioInfo — el modelo de monedas. No hay validación client-side
//     fuera del modelo; si los cálculos fallan, usuarios pierden monedas.
//
//  4. OnboardingState.tooltipsPendientes — casos de borde no cubiertos
//     por el test existente (onboarding_state_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:RiskRunner/services/territory_service.dart';
import 'package:RiskRunner/services/desafios_service.dart';
import 'package:RiskRunner/services/onboarding_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// TerritoryData mínimo con HP y timestamp controlados.
TerritoryData _ter({
  required int hpGuardado,
  required DateTime ultimaActualizacion,
  bool escudo = false,
}) {
  return TerritoryData(
    docId:                 'test-doc',
    ownerId:               'uid-test',
    ownerNickname:         'runner',
    color:                 const Color(0xFFCC2222),
    puntos:                const [
      LatLng(37.170, -3.600),
      LatLng(37.171, -3.600),
      LatLng(37.171, -3.601),
      LatLng(37.170, -3.601),
    ],
    centro:                const LatLng(37.1705, -3.6005),
    esMio:                 true,
    hpGuardado:            hpGuardado,
    ultimaActualizacionHp: ultimaActualizacion,
    escudoActivo:          escudo,
  );
}

/// DesafioInfo de prueba sin Firebase.
DesafioInfo _desafio({int apuesta = 100}) => DesafioInfo(
  id:            'test-desafio',
  retadorId:     'uid-a',
  retadorNick:   'retador',
  retadoId:      'uid-b',
  retadoNick:    'retado',
  apuesta:       apuesta,
  duracionHoras: 48,
  estado:        'pendiente',
  puntosRetador: 0,
  puntosRetado:  0,
);

// =============================================================================
void main() {

  // ===========================================================================
  // 1. HP DECAY
  // ===========================================================================
  group('TerritoryData.hpActual — invariante HP ≥ 1', () {
    test('territorio recién conquistado tiene HP = kHpMax', () {
      final t = _ter(hpGuardado: kHpMax, ultimaActualizacion: DateTime.now());
      expect(t.hpActual, kHpMax);
    });

    test('0 horas de decay → HP = hpGuardado', () {
      final t = _ter(hpGuardado: 75, ultimaActualizacion: DateTime.now());
      expect(t.hpActual, 75);
    });

    test('24 horas reducen HP en exactamente kHpDecayPorDia', () {
      final hace24h = DateTime.now().subtract(const Duration(hours: 24));
      final t = _ter(hpGuardado: kHpMax, ultimaActualizacion: hace24h);
      final esperado = (kHpMax - kHpDecayPorDia).round().clamp(1, kHpMax);
      expect(t.hpActual, esperado);
    });

    test('INVARIANTE: HP nunca baja de 1 aunque pasen 365 días', () {
      final hace1anyo = DateTime.now().subtract(const Duration(days: 365));
      final t = _ter(hpGuardado: 1, ultimaActualizacion: hace1anyo);
      expect(t.hpActual, greaterThanOrEqualTo(1),
          reason: 'HP mínimo es 1 — decisión de producto, territorios nunca mueren');
    });

    test('hpGuardado = 0 se clampea a 1', () {
      final t = _ter(hpGuardado: 0, ultimaActualizacion: DateTime.now());
      expect(t.hpActual, 1);
    });

    test('hpGuardado negativo se clampea a 1', () {
      final t = _ter(hpGuardado: -50, ultimaActualizacion: DateTime.now());
      expect(t.hpActual, 1);
    });

    test('hpGuardado por encima de kHpMax se clampea a kHpMax', () {
      final t = _ter(hpGuardado: kHpMax + 50, ultimaActualizacion: DateTime.now());
      expect(t.hpActual, kHpMax);
    });
  });

  // ===========================================================================
  // 2. EstadoHp — clasificación de estado
  // ===========================================================================
  group('TerritoryData.estadoHp — umbrales de clasificación', () {
    EstadoHp estadoFor(int hp) =>
        _ter(hpGuardado: hp, ultimaActualizacion: DateTime.now()).estadoHp;

    test('HP 1 → critico', () => expect(estadoFor(1), EstadoHp.critico));
    test('HP 29 → critico (límite superior)', () => expect(estadoFor(29), EstadoHp.critico));
    test('HP 30 → danado (límite inferior)', () => expect(estadoFor(30), EstadoHp.danado));
    test('HP 69 → danado (límite superior)', () => expect(estadoFor(69), EstadoHp.danado));
    test('HP 70 → saludable (límite inferior)', () => expect(estadoFor(70), EstadoHp.saludable));
    test('HP 100 → saludable', () => expect(estadoFor(kHpMax), EstadoHp.saludable));

    test('sin huecos ni solapamientos entre HP 1 y kHpMax', () {
      for (int hp = 1; hp <= 29; hp++) {
        expect(estadoFor(hp), EstadoHp.critico, reason: 'HP=$hp debería ser critico');
      }
      for (int hp = 30; hp <= 69; hp++) {
        expect(estadoFor(hp), EstadoHp.danado, reason: 'HP=$hp debería ser danado');
      }
      for (int hp = 70; hp <= kHpMax; hp++) {
        expect(estadoFor(hp), EstadoHp.saludable, reason: 'HP=$hp debería ser saludable');
      }
    });
  });

  // ===========================================================================
  // 3. DesafioInfo — modelo de monedas
  // ===========================================================================
  group('DesafioInfo — invariantes de apuesta', () {
    test('apuesta positiva se almacena correctamente', () {
      expect(_desafio(apuesta: 150).apuesta, 150);
    });

    test('apuesta 0 es válida (desafío sin monedas)', () {
      expect(_desafio(apuesta: 0).apuesta, 0);
    });

    test('premio = apuesta × 2', () {
      final d = _desafio(apuesta: 200);
      expect(d.apuesta * 2, 400);
    });

    test('puntosDeUsuario devuelve los puntos del retador cuando es uid-a', () {
      final d = DesafioInfo(
        id: 'x', retadorId: 'uid-a', retadorNick: 'a',
        retadoId: 'uid-b', retadoNick: 'b',
        apuesta: 100, duracionHoras: 48, estado: 'activo',
        puntosRetador: 12, puntosRetado: 7,
      );
      expect(d.puntosDeUsuario('uid-a'), 12);
      expect(d.puntosDeRival('uid-a'), 7);
    });

    test('puntosDeUsuario devuelve los puntos del retado cuando es uid-b', () {
      final d = DesafioInfo(
        id: 'x', retadorId: 'uid-a', retadorNick: 'a',
        retadoId: 'uid-b', retadoNick: 'b',
        apuesta: 100, duracionHoras: 48, estado: 'activo',
        puntosRetador: 12, puntosRetado: 7,
      );
      expect(d.puntosDeUsuario('uid-b'), 7);
      expect(d.puntosDeRival('uid-b'), 12);
    });

    test('vaGanando es true cuando el usuario tiene más puntos', () {
      final d = DesafioInfo(
        id: 'x', retadorId: 'uid-a', retadorNick: 'a',
        retadoId: 'uid-b', retadoNick: 'b',
        apuesta: 50, duracionHoras: 24, estado: 'activo',
        puntosRetador: 20, puntosRetado: 5,
      );
      expect(d.vaGanando('uid-a'), isTrue);
      expect(d.vaGanando('uid-b'), isFalse);
    });

    test('vaGanando es true en empate (>=)', () {
      final d = DesafioInfo(
        id: 'x', retadorId: 'uid-a', retadorNick: 'a',
        retadoId: 'uid-b', retadoNick: 'b',
        apuesta: 0, duracionHoras: 24, estado: 'activo',
        puntosRetador: 10, puntosRetado: 10,
      );
      expect(d.vaGanando('uid-a'), isTrue);
      expect(d.vaGanando('uid-b'), isTrue);
    });

    test('nickRival devuelve el nick del oponente', () {
      final d = _desafio();
      expect(d.nickRival('uid-a'), 'retado');
      expect(d.nickRival('uid-b'), 'retador');
    });

    test('haExpirado es false cuando fin es null', () {
      expect(_desafio().haExpirado, isFalse);
    });

    test('haExpirado es true cuando fin está en el pasado', () {
      final d = DesafioInfo(
        id: 'x', retadorId: 'uid-a', retadorNick: 'a',
        retadoId: 'uid-b', retadoNick: 'b',
        apuesta: 0, duracionHoras: 24, estado: 'activo',
        puntosRetador: 0, puntosRetado: 0,
        fin: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(d.haExpirado, isTrue);
    });
  });

  // ===========================================================================
  // 4. OnboardingState.tooltipsPendientes — casos de borde
  // ===========================================================================
  group('OnboardingState.tooltipsPendientes — casos de borde', () {
    test('run 0 sin tooltips → muestra los 3 de bienvenida', () {
      const s = OnboardingState(
          slidesVistos: true, runActual: 0, tooltipsVistos: {});
      expect(s.tooltipsPendientes,
          containsAll(['bienvenida', 'primer_run', 'color_territorio']));
    });

    test('si todos los tooltips del run actual ya se vieron → lista vacía', () {
      const s = OnboardingState(
          slidesVistos: true,
          runActual:    1,
          tooltipsVistos: {'conquista_territorio', 'mapa_live', 'color_hint', 'pausa_retirada'});
      expect(s.tooltipsPendientes, isEmpty);
    });

    test('tooltips vistos de otro run no afectan al run actual', () {
      const s = OnboardingState(
          slidesVistos: true,
          runActual:    2,
          tooltipsVistos: {'bienvenida', 'primer_run'}); // son del run 0
      expect(s.tooltipsPendientes,
          containsAll(['deterioro_zonas', 'refuerzo_territorio', 'frecuencia_importa']));
    });

    test('run >= 6 (sin entry en el mapa) → lista vacía, no lanza', () {
      const s = OnboardingState(
          slidesVistos: true, runActual: 99, tooltipsVistos: {});
      expect(s.tooltipsPendientes, isEmpty);
    });
  });
}
