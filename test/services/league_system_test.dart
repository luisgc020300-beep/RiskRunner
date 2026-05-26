// test/services/league_system_test.dart
//
// Tests for the pure-Dart logic in LeagueSystem / LeagueHelper.
// No Firebase — no mocking needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:RiskRunner/services/league_service.dart';

void main() {
  group('LeagueSystem.calcularLigaPorPuntos', () {
    test('0 pts → bronce', () {
      expect(LeagueSystem.calcularLigaPorPuntos(0).id, 'bronce');
    });

    test('499 pts → bronce (límite superior)', () {
      expect(LeagueSystem.calcularLigaPorPuntos(499).id, 'bronce');
    });

    test('500 pts → plata (límite inferior)', () {
      expect(LeagueSystem.calcularLigaPorPuntos(500).id, 'plata');
    });

    test('1499 pts → plata (límite superior)', () {
      expect(LeagueSystem.calcularLigaPorPuntos(1499).id, 'plata');
    });

    test('1500 pts → oro', () {
      expect(LeagueSystem.calcularLigaPorPuntos(1500).id, 'oro');
    });

    test('3500 pts → platino', () {
      expect(LeagueSystem.calcularLigaPorPuntos(3500).id, 'platino');
    });

    test('7000 pts → diamante', () {
      expect(LeagueSystem.calcularLigaPorPuntos(7000).id, 'diamante');
    });

    test('12000 pts → leyenda', () {
      expect(LeagueSystem.calcularLigaPorPuntos(12000).id, 'leyenda');
    });

    test('puntos muy altos → leyenda', () {
      expect(LeagueSystem.calcularLigaPorPuntos(999999).id, 'leyenda');
    });
  });

  group('LeagueSystem.progresoDentroLiga', () {
    test('0 pts en bronce → progreso 0.0', () {
      expect(LeagueSystem.progresoDentroLiga(0), closeTo(0.0, 0.01));
    });

    test('250 pts en bronce → progreso ~50%', () {
      // bronce: 0-499 (500 pts de rango)
      final p = LeagueSystem.progresoDentroLiga(250);
      expect(p, greaterThan(0.49));
      expect(p, lessThan(0.51));
    });

    test('progreso en leyenda (sin máximo) → 1.0', () {
      expect(LeagueSystem.progresoDentroLiga(99999), 1.0);
    });

    test('progreso siempre acotado [0, 1]', () {
      for (final pts in [0, 499, 500, 1000, 3500, 7000, 12000, 50000]) {
        final p = LeagueSystem.progresoDentroLiga(pts);
        expect(p, inInclusiveRange(0.0, 1.0),
            reason: 'pts=$pts dio progreso fuera de rango');
      }
    });
  });

  group('LeagueSystem.puntosParaSiguienteLiga', () {
    test('desde bronce con 0 pts → faltan 500', () {
      expect(LeagueSystem.puntosParaSiguienteLiga(0), 500);
    });

    test('desde bronce con 400 pts → faltan 100', () {
      expect(LeagueSystem.puntosParaSiguienteLiga(400), 100);
    });

    test('en leyenda (sin siguiente) → 0', () {
      expect(LeagueSystem.puntosParaSiguienteLiga(12000), 0);
    });
  });

  group('LeagueSystem.indice', () {
    test('bronce → 0', () => expect(LeagueSystem.indice('bronce'), 0));
    test('plata → 1',  () => expect(LeagueSystem.indice('plata'),  1));
    test('oro → 2',    () => expect(LeagueSystem.indice('oro'),    2));
    test('platino → 3',() => expect(LeagueSystem.indice('platino'),3));
    test('diamante → 4',()=> expect(LeagueSystem.indice('diamante'),4));
    test('leyenda → 5',() => expect(LeagueSystem.indice('leyenda'), 5));
    test('id desconocido → 0 (fallback)', () {
      expect(LeagueSystem.indice('xyz'), 0);
    });
    test('case-insensitive', () {
      expect(LeagueSystem.indice('ORO'), 2);
    });
  });

  group('LeagueSystem.getLeagueById', () {
    test('devuelve la liga correcta por id', () {
      final liga = LeagueSystem.getLeagueById('platino');
      expect(liga.id, 'platino');
      expect(liga.minPts, 3500);
    });

    test('id desconocido → bronce (fallback)', () {
      final liga = LeagueSystem.getLeagueById('nonexistent');
      expect(liga.id, 'bronce');
    });
  });

  group('LeagueHelper (alias)', () {
    test('getLeague es alias de calcularLigaPorPuntos', () {
      expect(LeagueHelper.getLeague(1500).id,
          LeagueSystem.calcularLigaPorPuntos(1500).id);
    });

    test('getProgress es alias de progresoDentroLiga', () {
      expect(LeagueHelper.getProgress(800),
          LeagueSystem.progresoDentroLiga(800));
    });

    test('ptsParaSiguiente es alias de puntosParaSiguienteLiga', () {
      expect(LeagueHelper.ptsParaSiguiente(200),
          LeagueSystem.puntosParaSiguienteLiga(200));
    });
  });
}
