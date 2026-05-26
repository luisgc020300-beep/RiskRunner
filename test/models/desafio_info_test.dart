// test/models/desafio_info_test.dart
//
// Tests for the pure-Dart logic in DesafioInfo.
// No Firebase — tests model methods and computed properties.

import 'package:flutter_test/flutter_test.dart';
import 'package:RiskRunner/services/desafios_service.dart';

DesafioInfo _makeDesafio({
  String id = 'test-id',
  String retadorId = 'uid-retador',
  String retadorNick = 'Retador',
  String retadoId = 'uid-retado',
  String retadoNick = 'Retado',
  int apuesta = 100,
  int duracionHoras = 24,
  String estado = 'activo',
  int puntosRetador = 50,
  int puntosRetado = 30,
  DateTime? inicio,
  DateTime? fin,
  String? ganadorId,
}) {
  return DesafioInfo(
    id: id,
    retadorId: retadorId,
    retadorNick: retadorNick,
    retadoId: retadoId,
    retadoNick: retadoNick,
    apuesta: apuesta,
    duracionHoras: duracionHoras,
    estado: estado,
    puntosRetador: puntosRetador,
    puntosRetado: puntosRetado,
    inicio: inicio,
    fin: fin,
    ganadorId: ganadorId,
  );
}

void main() {
  group('DesafioInfo.haExpirado', () {
    test('fin null → no ha expirado', () {
      final d = _makeDesafio(fin: null);
      expect(d.haExpirado, false);
    });

    test('fin en el futuro → no ha expirado', () {
      final d = _makeDesafio(
          fin: DateTime.now().add(const Duration(hours: 1)));
      expect(d.haExpirado, false);
    });

    test('fin en el pasado → ha expirado', () {
      final d = _makeDesafio(
          fin: DateTime.now().subtract(const Duration(seconds: 1)));
      expect(d.haExpirado, true);
    });
  });

  group('DesafioInfo.tiempoRestante', () {
    test('fin null → "--"', () {
      final d = _makeDesafio(fin: null);
      expect(d.tiempoRestante, '--');
    });

    test('fin en el pasado → "Expirado"', () {
      final d = _makeDesafio(
          fin: DateTime.now().subtract(const Duration(minutes: 5)));
      expect(d.tiempoRestante, 'Expirado');
    });

    test('más de 1 día restante → contiene "d"', () {
      final d = _makeDesafio(
          fin: DateTime.now().add(const Duration(days: 2, hours: 3)));
      expect(d.tiempoRestante, contains('d'));
    });

    test('entre 1h y 24h restantes → contiene "h"', () {
      final d = _makeDesafio(
          fin: DateTime.now().add(const Duration(hours: 5)));
      expect(d.tiempoRestante, contains('h'));
    });

    test('menos de 1h restante → contiene "m"', () {
      final d = _makeDesafio(
          fin: DateTime.now().add(const Duration(minutes: 45)));
      expect(d.tiempoRestante, contains('m'));
    });
  });

  group('DesafioInfo.puntosDeUsuario / puntosDeRival', () {
    test('como retador: puntosDeUsuario = puntosRetador', () {
      final d = _makeDesafio(puntosRetador: 80, puntosRetado: 40);
      expect(d.puntosDeUsuario('uid-retador'), 80);
      expect(d.puntosDeRival('uid-retador'), 40);
    });

    test('como retado: puntosDeUsuario = puntosRetado', () {
      final d = _makeDesafio(puntosRetador: 80, puntosRetado: 40);
      expect(d.puntosDeUsuario('uid-retado'), 40);
      expect(d.puntosDeRival('uid-retado'), 80);
    });
  });

  group('DesafioInfo.nickRival', () {
    test('como retador → nick del retado', () {
      final d = _makeDesafio();
      expect(d.nickRival('uid-retador'), 'Retado');
    });

    test('como retado → nick del retador', () {
      final d = _makeDesafio();
      expect(d.nickRival('uid-retado'), 'Retador');
    });
  });

  group('DesafioInfo.vaGanando', () {
    test('retador con más puntos → va ganando', () {
      final d = _makeDesafio(puntosRetador: 100, puntosRetado: 50);
      expect(d.vaGanando('uid-retador'), true);
    });

    test('retado con más puntos → retador NO va ganando', () {
      final d = _makeDesafio(puntosRetador: 30, puntosRetado: 90);
      expect(d.vaGanando('uid-retador'), false);
    });

    test('empate → ambos van "ganando" (>=)', () {
      final d = _makeDesafio(puntosRetador: 50, puntosRetado: 50);
      expect(d.vaGanando('uid-retador'), true);
      expect(d.vaGanando('uid-retado'), true);
    });
  });
}
