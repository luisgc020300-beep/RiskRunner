// lib/services/activity_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ── Modelo de una entrada del feed ────────────────────────────────────────────
class ActivityEntry {
  final String userNick;
  final String territoryId;
  final String territoryName;
  final String mode; // 'competitivo' | 'solitario'
  final DateTime timestamp;
  final String? previousOwnerNick;
  final int fromColorValue;

  const ActivityEntry({
    required this.userNick,
    required this.territoryId,
    required this.territoryName,
    required this.mode,
    required this.timestamp,
    this.previousOwnerNick,
    this.fromColorValue = 0xFFCC2222,
  });

  Color get color => Color(fromColorValue);

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    if (diff.inHours < 24)   return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }

  factory ActivityEntry.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return ActivityEntry(
      userNick:          d['userNick'] as String? ?? d['fromNickname'] as String? ?? '?',
      territoryId:       d['territoryId'] as String? ?? '',
      territoryName:     d['territoryName'] as String? ?? 'Zona desconocida',
      mode:              d['mode'] as String? ?? 'competitivo',
      timestamp:         (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      previousOwnerNick: d['previousOwnerNick'] as String?,
      fromColorValue:    (d['fromColor'] as num?)?.toInt() ?? 0xFFCC2222,
    );
  }
}

// ── Servicio ──────────────────────────────────────────────────────────────────
class ActivityService {
  static final _db = FirebaseFirestore.instance;

  // Feed global reciente — lee la colección activity_feed que ya existe
  static Future<List<ActivityEntry>> obtenerFeedReciente(
      {int limit = 15}) async {
    try {
      final snap = await _db
          .collection('activity_feed')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map(ActivityEntry.fromDoc).toList();
    } catch (e) {
      debugPrint('ActivityService.obtenerFeedReciente error: $e');
      return [];
    }
  }

  // Escribe en el historial del territorio y aumenta conquistas_count
  static Future<void> escribirHistorialConquista({
    required String territoryId,
    required String ownerNickname,
    required int ownerColorValue,
    String? previousOwnerNick,
  }) async {
    try {
      final terrRef = _db.collection('territories').doc(territoryId);
      final histRef = terrRef.collection('history').doc();
      final batch   = _db.batch();

      batch.set(histRef, {
        'ownerNickname':    ownerNickname,
        'ownerColor':       ownerColorValue,
        'previousOwner':    previousOwnerNick,
        'conquista_ts':     FieldValue.serverTimestamp(),
      });

      // Increment — si el campo no existe se crea en 1
      batch.update(terrRef, {
        'conquistas_count': FieldValue.increment(1),
      });

      await batch.commit();
    } catch (e) {
      debugPrint('ActivityService.escribirHistorialConquista error: $e');
    }
  }

  // Historial de cambios de dueño de un territorio
  static Future<List<Map<String, dynamic>>> obtenerHistorialTerritorio(
      String territoryId,
      {int limit = 4}) async {
    try {
      final snap = await _db
          .collection('territories')
          .doc(territoryId)
          .collection('history')
          .orderBy('conquista_ts', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) => d.data()).toList();
    } catch (e) {
      debugPrint('ActivityService.obtenerHistorialTerritorio error: $e');
      return [];
    }
  }
}
