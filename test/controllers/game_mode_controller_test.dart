import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:RiskRunner/controllers/game_mode_controller.dart';
import 'package:RiskRunner/services/territory_service.dart';

TerritoryData fakeTerritory(String docId) => TerritoryData(
      docId: docId,
      ownerId: 'uid-test',
      ownerNickname: 'Tester',
      color: Colors.blue,
      puntos: const [],
      centro: const LatLng(0, 0),
      esMio: false,
    );

void main() {
  late GameModeController ctrl;

  setUp(() => ctrl = GameModeController());

  // ── estado inicial ──────────────────────────────────────────────────────────

  group('estado inicial', () {
    test('arranca en modo competitivo por defecto', () {
      expect(ctrl.isCompetitivo, isTrue);
      expect(ctrl.modoSolitario, isFalse);
      expect(ctrl.modoRuta, isFalse);
      expect(ctrl.isGlobal, isFalse);
    });

    test('territoriosCargados empieza en false', () {
      expect(ctrl.territoriosCargados, isFalse);
    });

    test('territorios empieza vacío', () {
      expect(ctrl.territorios, isEmpty);
    });
  });

  // ── Bug #1: territoriosCargados no se reseteaba en cambios de modo ──────────

  group('switchToCompetitivo — reset territoriosCargados', () {
    setUp(() {
      ctrl.switchToSolitario();
      ctrl.onTerritoriosCargados([fakeTerritory('t1'), fakeTerritory('t2')]);
    });

    test('resetea territoriosCargados a false', () {
      ctrl.switchToCompetitivo();
      expect(ctrl.territoriosCargados, isFalse);
    });

    test('vacía la lista de territorios', () {
      ctrl.switchToCompetitivo();
      expect(ctrl.territorios, isEmpty);
    });

    test('desactiva modoSolitario', () {
      ctrl.switchToCompetitivo();
      expect(ctrl.modoSolitario, isFalse);
    });

    test('limpia objetivoGlobal si había uno', () {
      ctrl.setObjetivoGlobal({'territorioId': 'abc', 'kmRequeridos': 3.0});
      ctrl.switchToCompetitivo();
      expect(ctrl.objetivoGlobal, isNull);
    });

    test('isCompetitivo queda en true', () {
      ctrl.switchToCompetitivo();
      expect(ctrl.isCompetitivo, isTrue);
    });
  });

  group('switchToSolitario — reset territoriosCargados', () {
    setUp(() {
      ctrl.onTerritoriosCargados([fakeTerritory('t1')]);
    });

    test('resetea territoriosCargados a false', () {
      ctrl.switchToSolitario();
      expect(ctrl.territoriosCargados, isFalse);
    });

    test('vacía territorios', () {
      ctrl.switchToSolitario();
      expect(ctrl.territorios, isEmpty);
    });

    test('activa modoSolitario', () {
      ctrl.switchToSolitario();
      expect(ctrl.modoSolitario, isTrue);
    });

    test('desactiva modoRuta', () {
      ctrl.modoRuta = true;
      ctrl.switchToSolitario();
      expect(ctrl.modoRuta, isFalse);
    });
  });

  group('switchToRuta — reset territoriosCargados', () {
    setUp(() {
      ctrl.switchToSolitario();
      ctrl.onTerritoriosCargados([fakeTerritory('t1')]);
    });

    test('resetea territoriosCargados a false', () {
      ctrl.switchToRuta();
      expect(ctrl.territoriosCargados, isFalse);
    });

    test('vacía territorios', () {
      ctrl.switchToRuta();
      expect(ctrl.territorios, isEmpty);
    });

    test('activa modoRuta', () {
      ctrl.switchToRuta();
      expect(ctrl.modoRuta, isTrue);
    });

    test('desactiva modoSolitario', () {
      ctrl.switchToRuta();
      expect(ctrl.modoSolitario, isFalse);
    });
  });

  group('switchToGlobal — reset territoriosCargados', () {
    setUp(() {
      ctrl.onTerritoriosCargados([fakeTerritory('t1')]);
    });

    test('resetea territoriosCargados a false', () {
      ctrl.switchToGlobal();
      expect(ctrl.territoriosCargados, isFalse);
    });

    test('activa seleccionandoGlobal', () {
      ctrl.switchToGlobal();
      expect(ctrl.seleccionandoGlobal, isTrue);
    });

    test('desactiva modoSolitario y modoRuta', () {
      ctrl.modoSolitario = true;
      ctrl.modoRuta = true;
      ctrl.switchToGlobal();
      expect(ctrl.modoSolitario, isFalse);
      expect(ctrl.modoRuta, isFalse);
    });
  });

  // ── Flujo completo: carga de territorios ────────────────────────────────────

  group('onTerritoriosCargados', () {
    test('marca territoriosCargados = true', () {
      ctrl.onTerritoriosCargados([fakeTerritory('t1')]);
      expect(ctrl.territoriosCargados, isTrue);
    });

    test('almacena la lista recibida', () {
      final lista = [fakeTerritory('t1'), fakeTerritory('t2')];
      ctrl.onTerritoriosCargados(lista);
      expect(ctrl.territorios.length, 2);
      expect(ctrl.territorios.first.docId, 't1');
    });

    test('tras cambio de modo, territoriosCargados vuelve a false', () {
      ctrl.onTerritoriosCargados([fakeTerritory('t1')]);
      expect(ctrl.territoriosCargados, isTrue);
      ctrl.switchToSolitario();
      expect(ctrl.territoriosCargados, isFalse,
          reason: 'Bug #1: el chip mostraba "0 territorios" en lugar de "Cargando..."');
    });
  });

  // ── Invariantes de modo ──────────────────────────────────────────────────────

  group('invariantes entre modos', () {
    test('solitario y ruta nunca activos al mismo tiempo', () {
      ctrl.switchToSolitario();
      ctrl.switchToRuta();
      expect(ctrl.modoSolitario && ctrl.modoRuta, isFalse);
    });

    test('isCompetitivo es false cuando modoSolitario está activo', () {
      ctrl.switchToSolitario();
      expect(ctrl.isCompetitivo, isFalse);
    });

    test('isCompetitivo es false cuando modoRuta está activo', () {
      ctrl.switchToRuta();
      expect(ctrl.isCompetitivo, isFalse);
    });

    test('isGlobal es true solo cuando hay objetivoGlobal', () {
      expect(ctrl.isGlobal, isFalse);
      ctrl.setObjetivoGlobal({'territorioId': 'xyz', 'kmRequeridos': 5.0});
      expect(ctrl.isGlobal, isTrue);
    });

    test('setObjetivoGlobal desactiva seleccionandoGlobal', () {
      ctrl.switchToGlobal();
      expect(ctrl.seleccionandoGlobal, isTrue);
      ctrl.setObjetivoGlobal({'territorioId': 'xyz', 'kmRequeridos': 5.0});
      expect(ctrl.seleccionandoGlobal, isFalse);
    });
  });
}
