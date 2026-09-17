// test/services/last_seen_service_test.dart
//
// Unit tests for LastSeenService.estaEnLinea — la lógica que decide si un
// amigo aparece "en línea" en Social y en el chat. No requiere Firebase:
// es pura aritmética de fechas.
//
// latido() (la escritura del latido) depende de FirebaseAuth.instance.
// currentUser, que no está mockeado en este proyecto todavía — por eso
// solo se prueba aquí la parte pura, que es la que decidía el bug real
// (un amigo desconectado seguía apareciendo "en línea" durante horas).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:RiskRunner/services/last_seen_service.dart';

void main() {
  group('estaEnLinea', () {
    test('null (nunca ha mandado un latido) → desconectado', () {
      expect(LastSeenService.estaEnLinea(null), isFalse);
    });

    test('latido de hace 10 segundos → en línea', () {
      final ts = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(seconds: 10)));
      expect(LastSeenService.estaEnLinea(ts), isTrue);
    });

    test('latido a 5s del borde de la ventana (3 min) → todavía en línea', () {
      // No se prueba el borde exacto: entre construir el timestamp y que
      // estaEnLinea() vuelva a leer DateTime.now() pasan microsegundos
      // reales, así que comparar justo en el límite sería un test frágil.
      final ts = Timestamp.fromDate(DateTime.now()
          .subtract(LastSeenService.ventanaEnLinea - const Duration(seconds: 5)));
      expect(LastSeenService.estaEnLinea(ts), isTrue);
    });

    test('latido de hace 4 minutos → desconectado', () {
      final ts = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 4)));
      expect(LastSeenService.estaEnLinea(ts), isFalse);
    });

    test('latido de hace 24 horas → desconectado (el bug original: '
        'esto antes se consideraba "activo" con el campo de racha)', () {
      final ts = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 24)));
      expect(LastSeenService.estaEnLinea(ts), isFalse);
    });

    test('latido en el futuro (reloj del servidor adelantado) no revienta', () {
      final ts = Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: 5)));
      expect(LastSeenService.estaEnLinea(ts), isTrue);
    });
  });
}
