// lib/services/last_seen_service.dart
//
// Heartbeat ligero de "última vez visto en la app". A diferencia de
// PresenceService (posición en vivo mientras se corre, solo para el mapa),
// esto solo marca que el usuario tiene la app abierta en primer plano, sin
// importar en qué pantalla esté — es lo que Social usa para saber quién
// está realmente conectado, en vez del campo de racha diaria (pensado para
// otra cosa y que solo se actualiza al terminar una carrera).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class LastSeenService {
  static FirebaseFirestore _db = FirebaseFirestore.instance;

  @visibleForTesting
  static void setDb(FirebaseFirestore db) => _db = db;

  /// Ventana de "en línea": si el latido más reciente cae dentro de este
  /// margen se considera conectado. Cubre con holgura el intervalo entre
  /// latidos (ver AppShell) más el tiempo de red.
  static const Duration ventanaEnLinea = Duration(minutes: 3);

  static Future<void> latido() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('players').doc(uid).update({
        'ultima_conexion': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('LastSeenService.latido error: $e');
    }
  }

  /// true si [ts] cae dentro de la ventana "en línea".
  static bool estaEnLinea(Timestamp? ts) {
    if (ts == null) return false;
    return DateTime.now().difference(ts.toDate()) <= ventanaEnLinea;
  }
}
