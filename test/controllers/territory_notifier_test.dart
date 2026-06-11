// test/controllers/territory_notifier_test.dart
//
// Unit tests for TerritoryNotifier — pure Dart, no Firebase.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:latlong2/latlong.dart';
import 'package:RiskRunner/controllers/territory_notifier.dart';
import 'package:RiskRunner/services/territory_service.dart';

void main() {
  late TerritoryNotifier n;

  setUp(() => n = TerritoryNotifier());
  tearDown(() => n.dispose());

  // ── switches de modo ───────────────────────────────────────────────────────
  group('switchToCompetitivo', () {
    test('resetea modo y limpia territorios', () {
      n.modoSolitario  = true;
      n.modoRuta       = true;
      n.territorios    = [_fakeTerritory()];
      n.objetivoGlobal = {'id': 'x'};
      n.switchToCompetitivo();
      expect(n.modoSolitario,       isFalse);
      expect(n.modoRuta,            isFalse);
      expect(n.territorios,         isEmpty);
      expect(n.objetivoGlobal,      isNull);
      expect(n.territoriosCargados, isFalse);
      expect(n.isCompetitivo,       isTrue);
    });

    test('notifica listeners', () {
      var called = false;
      n.addListener(() => called = true);
      n.switchToCompetitivo();
      expect(called, isTrue);
    });
  });

  group('switchToSolitario', () {
    test('activa modoSolitario y limpia territorios', () {
      n.switchToSolitario();
      expect(n.modoSolitario,       isTrue);
      expect(n.modoRuta,            isFalse);
      expect(n.territorios,         isEmpty);
      expect(n.territoriosCargados, isFalse);
    });
  });

  group('switchToRuta', () {
    test('activa modoRuta y limpia territorios', () {
      n.switchToRuta();
      expect(n.modoRuta,            isTrue);
      expect(n.modoSolitario,       isFalse);
      expect(n.territoriosCargados, isFalse);
    });
  });

  group('switchToGlobal', () {
    test('activa seleccionandoGlobal', () {
      n.switchToGlobal();
      expect(n.seleccionandoGlobal, isTrue);
      expect(n.modoRuta,            isFalse);
      expect(n.territoriosCargados, isFalse);
    });
  });

  // ── objetivoGlobal ────────────────────────────────────────────────────────
  group('setObjetivoGlobal', () {
    test('asigna objetivo y cierra selección', () {
      n.switchToGlobal();
      n.setObjetivoGlobal({'territorioId': 'ter1'});
      expect(n.objetivoGlobal!['territorioId'], 'ter1');
      expect(n.seleccionandoGlobal, isFalse);
      expect(n.isGlobal,            isTrue);
    });
  });

  // ── carga de territorios ──────────────────────────────────────────────────
  group('onTerritoriosCargados', () {
    test('asigna lista y marca cargados', () {
      final lista = [_fakeTerritory(), _fakeTerritory()];
      n.onTerritoriosCargados(lista);
      expect(n.territorios.length,  2);
      expect(n.territoriosCargados, isTrue);
    });
  });

  // ── conquista global ──────────────────────────────────────────────────────
  group('setGlobalConquistando', () {
    test('activa y desactiva flag', () {
      n.setGlobalConquistando(true);
      expect(n.globalConquistando, isTrue);
      n.setGlobalConquistando(false);
      expect(n.globalConquistando, isFalse);
    });
  });

  group('setConquistaGlobalExito', () {
    test('marca conquistado y asigna cláusula', () {
      n.setConquistaGlobalExito(nuevaCl: 2.5);
      expect(n.globalConquistado, isTrue);
      expect(n.nuevaClausula,     2.5);
    });

    test('acepta cláusula null', () {
      n.setConquistaGlobalExito(nuevaCl: null);
      expect(n.globalConquistado, isTrue);
      expect(n.nuevaClausula,     isNull);
    });
  });

  group('setGlobalKmAlcanzados', () {
    test('activa flag y notifica', () {
      var called = false;
      n.addListener(() => called = true);
      n.setGlobalKmAlcanzados();
      expect(n.globalKmAlcanzados, isTrue);
      expect(called,               isTrue);
    });
  });

  // ── estado de sesión ──────────────────────────────────────────────────────
  group('setMapaDesactualizado', () {
    test('cambia valor y notifica', () {
      var calls = 0;
      n.addListener(() => calls++);
      n.setMapaDesactualizado(true);
      expect(n.mapaDesactualizado, isTrue);
      expect(calls, 1);
    });

    test('no notifica si el valor no cambia', () {
      n.setMapaDesactualizado(false); // ya era false
      var calls = 0;
      n.addListener(() => calls++);
      n.setMapaDesactualizado(false);
      expect(calls, 0);
    });
  });

  group('setZonaValida', () {
    test('cambia valor', () {
      n.setZonaValida(true);
      expect(n.zonaValida, isTrue);
      n.setZonaValida(false);
      expect(n.zonaValida, isFalse);
    });

    test('no notifica si el valor no cambia', () {
      n.setZonaValida(true);
      var calls = 0;
      n.addListener(() => calls++);
      n.setZonaValida(true);
      expect(calls, 0);
    });
  });

  group('setRetoCompletado', () {
    test('pone retoCompletado a true', () {
      n.setRetoCompletado();
      expect(n.retoCompletado, isTrue);
    });
  });

  group('setColorTerritorio', () {
    test('asigna color y notifica', () {
      var called = false;
      n.addListener(() => called = true);
      n.setColorTerritorio(Colors.red);
      expect(n.colorTerritorio, Colors.red);
      expect(called, isTrue);
    });
  });

  // ── resets ────────────────────────────────────────────────────────────────
  group('resetParaSesion', () {
    test('limpia todos los flags de sesión', () {
      n.setGlobalConquistando(true);
      n.setConquistaGlobalExito(nuevaCl: 3.0);
      n.setGlobalKmAlcanzados();
      n.setRetoCompletado();
      n.setZonaValida(true);

      n.resetParaSesion();

      expect(n.globalKmAlcanzados, isFalse);
      expect(n.globalConquistado,  isFalse);
      expect(n.globalConquistando, isFalse);
      expect(n.nuevaClausula,      isNull);
      expect(n.retoCompletado,     isFalse);
      expect(n.zonaValida,         isFalse);
    });
  });

  group('resetConquistaGlobal', () {
    test('limpia solo flags de conquista', () {
      n.setConquistaGlobalExito(nuevaCl: 1.0);
      n.setGlobalConquistando(true);
      n.setGlobalKmAlcanzados();

      n.resetConquistaGlobal();

      expect(n.globalConquistado,  isFalse);
      expect(n.globalConquistando, isFalse);
      // globalKmAlcanzados no se toca
      expect(n.globalKmAlcanzados, isTrue);
    });
  });
}

TerritoryData _fakeTerritory() => TerritoryData(
  docId:         'fake-${DateTime.now().microsecondsSinceEpoch}',
  ownerId:       '',
  ownerNickname: '',
  color:         Colors.grey,
  puntos:        const [],
  centro:        const LatLng(40.0, -3.0),
  esMio:         false,
);
