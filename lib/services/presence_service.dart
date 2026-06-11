import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PresenceService {
  static final _db = FirebaseFirestore.instance;

  // Stream de jugadores activos en los últimos 5 minutos
  static Stream<QuerySnapshot<Map<String, dynamic>>> stream(Timestamp cutoff) =>
      _db
          .collection('presencia_activa')
          .where('timestamp', isGreaterThan: cutoff)
          .limit(100)
          .snapshots();

  // Publica o actualiza la posición del jugador en la colección de presencia
  static Future<void> publicar({
    required String uid,
    required double lat,
    required double lng,
    required int colorValue,
    required String nickname,
  }) async {
    try {
      await _db.collection('presencia_activa').doc(uid).set({
        'lat':       lat,
        'lng':       lng,
        'color':     colorValue,
        'nickname':  nickname,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('PresenceService.publicar error: $e');
    }
  }

  // Elimina la presencia del jugador al terminar la sesión
  static Future<void> eliminar(String uid) async {
    try {
      await _db.collection('presencia_activa').doc(uid).delete();
    } catch (_) {}
  }
}
