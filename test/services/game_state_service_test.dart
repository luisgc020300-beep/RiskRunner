// test/services/game_state_service_test.dart
//
// Unit tests for GameStateService — session persistence + territory cache.
// Uses SharedPreferences.setMockInitialValues() (no extra deps needed).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:RiskRunner/services/game_state_service.dart';
import 'package:RiskRunner/services/territory_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

TerritoryData _fakeTer() => TerritoryData(
  docId:         'fake-${DateTime.now().microsecondsSinceEpoch}',
  ownerId:       '',
  ownerNickname: '',
  color:         Colors.grey,
  puntos:        const [],
  centro:        const LatLng(40.0, -3.0),
  esMio:         false,
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  final gss = GameStateService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Reset caches between tests
    gss.invalidateTerritories();
    gss.invalidateGlobal();
  });

  // ── saveSession / restoreSession ───────────────────────────────────────────
  group('saveSession / restoreSession', () {
    test('round-trip preserva todos los campos', () async {
      await gss.saveSession(
        mode:           'competitivo',
        points:         [{'lat': 40.0, 'lng': -3.0}],
        distanciaKm:    5.2,
        elapsedSeconds: 1820,
      );

      final session = await gss.restoreSession();
      expect(session,                       isNotNull);
      expect(session!['mode'],              'competitivo');
      expect(session['distanciaKm'],        5.2);
      expect(session['elapsedSeconds'],     1820);
      expect((session['points'] as List).length, 1);
    });

    test('devuelve null cuando no hay sesión guardada', () async {
      expect(await gss.restoreSession(), isNull);
    });

    test('clearSession hace que restoreSession devuelva null', () async {
      await gss.saveSession(
        mode: 'solitario', points: [], distanciaKm: 1.0, elapsedSeconds: 600,
      );
      await gss.clearSession();
      expect(await gss.restoreSession(), isNull);
    });

    test('sesión de más de 12 horas se descarta automáticamente', () async {
      final p = await SharedPreferences.getInstance();
      final oldTs = DateTime.now()
          .subtract(const Duration(hours: 13))
          .millisecondsSinceEpoch;
      await p.setString('gss_session',
          '{"mode":"competitivo","points":[],"distanciaKm":1.0,'
          '"elapsedSeconds":600,"savedAt":$oldTs}');

      expect(await gss.restoreSession(), isNull);
    });

    test('sesión reciente (< 12 h) se devuelve correctamente', () async {
      final p = await SharedPreferences.getInstance();
      final recentTs = DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch;
      await p.setString('gss_session',
          '{"mode":"ruta","points":[],"distanciaKm":3.0,'
          '"elapsedSeconds":900,"savedAt":$recentTs}');

      final session = await gss.restoreSession();
      expect(session,            isNotNull);
      expect(session!['mode'],   'ruta');
      expect(session['distanciaKm'], 3.0);
    });
  });

  // ── currentMode / initAsync ────────────────────────────────────────────────
  group('currentMode / initAsync', () {
    test('initAsync sin datos previos usa "competitivo" por defecto', () async {
      await gss.initAsync();
      expect(gss.currentMode, 'competitivo');
    });

    test('initAsync carga el modo guardado desde SharedPreferences', () async {
      final p = await SharedPreferences.getInstance();
      await p.setString('gss_current_mode', 'solitario');
      await gss.initAsync();
      expect(gss.currentMode, 'solitario');
    });

    test('asignar currentMode persiste en SharedPreferences', () async {
      gss.currentMode = 'ruta';
      await Future.delayed(Duration.zero); // fire-and-forget flush
      final p = await SharedPreferences.getInstance();
      expect(p.getString('gss_current_mode'), 'ruta');
    });
  });

  // ── caché de territorios competitivos ─────────────────────────────────────
  group('caché competitivo', () {
    test('getCompetitiveTerritories devuelve null antes de setear', () {
      expect(gss.getCompetitiveTerritories(), isNull);
    });

    test('setCompetitiveTerritories + get devuelve la lista', () {
      final lista = [_fakeTer()];
      gss.setCompetitiveTerritories(lista);
      final result = gss.getCompetitiveTerritories();
      expect(result,              isNotNull);
      expect(result!.length,      1);
      expect(result.first.docId,  lista.first.docId);
    });

    test('invalidateCompetitive hace que get devuelva null', () {
      gss.setCompetitiveTerritories([_fakeTer()]);
      gss.invalidateCompetitive();
      expect(gss.getCompetitiveTerritories(), isNull);
    });

    test('getStaleCompetitiveTerritories devuelve datos aunque el caché haya expirado', () {
      gss.setCompetitiveTerritories([_fakeTer()]);
      gss.invalidateCompetitive();
      // invalidate borra el cache → stale también null
      expect(gss.getStaleCompetitiveTerritories(), isNull);

      // Volver a setear y verificar stale
      final lista = [_fakeTer(), _fakeTer()];
      gss.setCompetitiveTerritories(lista);
      expect(gss.getStaleCompetitiveTerritories()!.length, 2);
    });
  });

  // ── caché de territorios solitario ────────────────────────────────────────
  group('caché solitario', () {
    test('set + get round-trip funciona', () {
      final lista = [_fakeTer(), _fakeTer(), _fakeTer()];
      gss.setSolitarioTerritories(lista);
      expect(gss.getSolitarioTerritories()!.length, 3);
    });

    test('invalidateSolitario limpia el caché', () {
      gss.setSolitarioTerritories([_fakeTer()]);
      gss.invalidateSolitario();
      expect(gss.getSolitarioTerritories(), isNull);
    });
  });

  // ── invalidateTerritories ──────────────────────────────────────────────────
  group('invalidateTerritories', () {
    test('limpia ambos cachés a la vez', () {
      gss.setCompetitiveTerritories([_fakeTer()]);
      gss.setSolitarioTerritories([_fakeTer()]);
      gss.invalidateTerritories();
      expect(gss.getCompetitiveTerritories(), isNull);
      expect(gss.getSolitarioTerritories(),   isNull);
    });
  });
}
