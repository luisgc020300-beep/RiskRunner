// test/services/activity_service_test.dart
//
// Unit tests for ActivityService and ActivityEntry — uses FakeFirebaseFirestore.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:RiskRunner/services/activity_service.dart';

void main() {
  late FakeFirebaseFirestore fakeDb;

  setUp(() {
    fakeDb = FakeFirebaseFirestore();
    ActivityService.setDb(fakeDb);
  });

  // ── ActivityEntry serialization ───────────────────────────────────────────
  group('ActivityEntry.timeAgo', () {
    test('minutos recientes', () {
      final e = ActivityEntry(
        userNick: 'test', territoryId: 't1', territoryName: 'Zona',
        mode: 'competitivo', timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
      );
      expect(e.timeAgo, 'hace 3min');
    });

    test('horas', () {
      final e = ActivityEntry(
        userNick: 'test', territoryId: 't1', territoryName: 'Zona',
        mode: 'competitivo', timestamp: DateTime.now().subtract(const Duration(hours: 5)),
      );
      expect(e.timeAgo, 'hace 5h');
    });

    test('días', () {
      final e = ActivityEntry(
        userNick: 'test', territoryId: 't1', territoryName: 'Zona',
        mode: 'competitivo', timestamp: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(e.timeAgo, 'hace 2d');
    });
  });

  // ── registrarSesion ───────────────────────────────────────────────────────
  group('registrarSesion', () {
    test('crea doc en activity_logs y devuelve su id', () async {
      final id = await ActivityService.registrarSesion({
        'uid': 'u1', 'km': 5.2, 'modo': 'competitivo',
      });

      expect(id, isNotNull);
      final doc = await fakeDb.collection('activity_logs').doc(id!).get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['km'], 5.2);
    });

    test('incluye campo timestamp', () async {
      final id = await ActivityService.registrarSesion({'uid': 'u2', 'km': 3.0});
      final doc = await fakeDb.collection('activity_logs').doc(id!).get();
      expect(doc.data()!.containsKey('timestamp'), isTrue);
    });
  });

  // ── vincularLogTerritorio ─────────────────────────────────────────────────
  group('vincularLogTerritorio', () {
    test('añade territorio_id al log existente', () async {
      final id = await ActivityService.registrarSesion({'uid': 'u1', 'km': 1.0});
      ActivityService.vincularLogTerritorio(id!, 'ter_abc');
      // pequeño delay para que el fire-and-forget complete
      await Future.delayed(const Duration(milliseconds: 50));
      final doc = await fakeDb.collection('activity_logs').doc(id).get();
      expect(doc.data()!['territorio_id'], 'ter_abc');
    });
  });

  // ── publicarConquistaFeed ─────────────────────────────────────────────────
  group('publicarConquistaFeed', () {
    test('crea entrada en activity_feed con campos requeridos', () async {
      await ActivityService.publicarConquistaFeed(
        uid: 'u1', nickname: 'Runner1', territoryId: 'ter1',
        territoryName: 'Zona Norte', mode: 'competitivo',
        previousOwnerNick: 'Rival', fromColorValue: 0xFFFF0000,
      );

      final snap = await fakeDb.collection('activity_feed').get();
      expect(snap.docs.length, 1);
      final data = snap.docs.first.data();
      expect(data['userNick'],      'Runner1');
      expect(data['territoryName'], 'Zona Norte');
      expect(data['mode'],          'competitivo');
      expect(data['previousOwnerNick'], 'Rival');
    });
  });

  // ── escribirHistorialConquista ────────────────────────────────────────────
  group('escribirHistorialConquista', () {
    test('crea doc en history e incrementa conquistas_count', () async {
      // Crear el territorio previamente para que update no falle
      await fakeDb.collection('territories').doc('ter1').set({'conquistas_count': 0});

      await ActivityService.escribirHistorialConquista(
        territoryId:      'ter1',
        ownerNickname:    'Runner1',
        ownerColorValue:  0xFF0000FF,
        previousOwnerNick: 'Rival',
      );

      final history = await fakeDb
          .collection('territories').doc('ter1').collection('history').get();
      expect(history.docs.length, 1);
      expect(history.docs.first.data()['ownerNickname'], 'Runner1');

      final terr = await fakeDb.collection('territories').doc('ter1').get();
      expect(terr.data()!['conquistas_count'], 1);
    });
  });

  // ── acreditarMonedas ──────────────────────────────────────────────────────
  group('acreditarMonedas', () {
    test('incrementa monedas del jugador', () async {
      await fakeDb.collection('players').doc('u1').set({'monedas': 100});
      await ActivityService.acreditarMonedas('u1', 50);
      final doc = await fakeDb.collection('players').doc('u1').get();
      expect(doc.data()!['monedas'], 150);
    });
  });

  // ── enviarNotificacion ────────────────────────────────────────────────────
  group('enviarNotificacion', () {
    test('crea doc con read=false', () async {
      await ActivityService.enviarNotificacion({
        'uid': 'u1', 'tipo': 'conquista', 'titulo': 'Nueva conquista',
      });
      final snap = await fakeDb.collection('notifications').get();
      expect(snap.docs.length, 1);
      expect(snap.docs.first.data()['read'], isFalse);
      expect(snap.docs.first.data()['titulo'], 'Nueva conquista');
    });
  });

  // ── obtenerHistorialTerritorio ────────────────────────────────────────────
  group('obtenerHistorialTerritorio', () {
    test('devuelve lista de eventos de conquista', () async {
      final terrRef = fakeDb.collection('territories').doc('ter1');
      await terrRef.collection('history').add({'ownerNickname': 'A', 'conquista_ts': Timestamp.now()});
      await terrRef.collection('history').add({'ownerNickname': 'B', 'conquista_ts': Timestamp.now()});

      final hist = await ActivityService.obtenerHistorialTerritorio('ter1');
      expect(hist.length, 2);
    });

    test('devuelve lista vacía si no hay historial', () async {
      final hist = await ActivityService.obtenerHistorialTerritorio('ter_nueva');
      expect(hist, isEmpty);
    });
  });

  // ── programarNotificacionesPostCarrera ────────────────────────────────────
  group('programarNotificacionesPostCarrera', () {
    test('completa sin lanzar aunque LocalNotifService no esté inicializado', () async {
      await fakeDb.collection('players').doc('uid1').set({'racha_actual': 5});
      await fakeDb.collection('activity_logs').add({
        'userId': 'uid1',
        'distancia': 3.5,
        'timestamp': Timestamp.fromDate(DateTime.now()),
      });
      await expectLater(
        ActivityService.programarNotificacionesPostCarrera('uid1', 3.5),
        completes,
      );
    });

    test('completa sin lanzar cuando el jugador no tiene racha', () async {
      await fakeDb.collection('players').doc('uid2').set({'racha_actual': 0});
      await expectLater(
        ActivityService.programarNotificacionesPostCarrera('uid2', 1.0),
        completes,
      );
    });
  });
}
