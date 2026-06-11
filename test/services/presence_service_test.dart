// test/services/presence_service_test.dart
//
// Unit tests for PresenceService — uses FakeFirebaseFirestore.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:RiskRunner/services/presence_service.dart';

void main() {
  late FakeFirebaseFirestore fakeDb;

  setUp(() {
    fakeDb = FakeFirebaseFirestore();
    PresenceService.setDb(fakeDb);
  });

  // ── publicar ──────────────────────────────────────────────────────────────
  group('publicar', () {
    test('crea doc en presencia_activa con campos correctos', () async {
      await PresenceService.publicar(
        uid: 'u1', lat: 40.4, lng: -3.7,
        colorValue: 0xFFFF0000, nickname: 'Runner1',
      );

      final doc = await fakeDb.collection('presencia_activa').doc('u1').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['lat'],      40.4);
      expect(doc.data()!['lng'],      -3.7);
      expect(doc.data()!['color'],    0xFFFF0000);
      expect(doc.data()!['nickname'], 'Runner1');
    });

    test('sobreescribe presencia anterior del mismo uid', () async {
      await PresenceService.publicar(
        uid: 'u1', lat: 40.4, lng: -3.7, colorValue: 0xFFFF0000, nickname: 'A',
      );
      await PresenceService.publicar(
        uid: 'u1', lat: 41.0, lng: -4.0, colorValue: 0xFF00FF00, nickname: 'A',
      );

      final doc = await fakeDb.collection('presencia_activa').doc('u1').get();
      expect(doc.data()!['lat'], 41.0);
      expect(doc.data()!['color'], 0xFF00FF00);

      // Solo hay un doc (set reemplaza)
      final all = await fakeDb.collection('presencia_activa').get();
      expect(all.docs.length, 1);
    });
  });

  // ── eliminar ──────────────────────────────────────────────────────────────
  group('eliminar', () {
    test('borra el doc del uid', () async {
      await fakeDb.collection('presencia_activa').doc('u1').set({'lat': 40.0});
      await PresenceService.eliminar('u1');
      final doc = await fakeDb.collection('presencia_activa').doc('u1').get();
      expect(doc.exists, isFalse);
    });

    test('no falla si el uid no existe', () async {
      // No debe lanzar excepción
      await expectLater(
        PresenceService.eliminar('uid_inexistente'),
        completes,
      );
    });
  });

  // ── stream ────────────────────────────────────────────────────────────────
  group('stream', () {
    test('devuelve docs más recientes que cutoff', () async {
      final ahora = Timestamp.now();
      final hace10 = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 10)));

      await fakeDb.collection('presencia_activa').doc('reciente').set({
        'lat': 40.0, 'lng': -3.0, 'timestamp': ahora,
      });
      await fakeDb.collection('presencia_activa').doc('viejo').set({
        'lat': 39.0, 'lng': -2.0, 'timestamp': hace10,
      });

      final cutoff = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 5)));
      final snap = await PresenceService.stream(cutoff).first;
      expect(snap.docs.length, 1);
      expect(snap.docs.first.id, 'reciente');
    });
  });
}
