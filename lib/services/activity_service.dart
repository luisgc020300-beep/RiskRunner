// lib/services/activity_service.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> _toMap() => {
    'userNick':          userNick,
    'territoryId':       territoryId,
    'territoryName':     territoryName,
    'mode':              mode,
    'timestamp':         timestamp.millisecondsSinceEpoch,
    'previousOwnerNick': previousOwnerNick,
    'fromColorValue':    fromColorValue,
  };

  factory ActivityEntry._fromMap(Map<String, dynamic> m) => ActivityEntry(
    userNick:          m['userNick'] as String? ?? '?',
    territoryId:       m['territoryId'] as String? ?? '',
    territoryName:     m['territoryName'] as String? ?? 'Zona desconocida',
    mode:              m['mode'] as String? ?? 'competitivo',
    timestamp:         DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
    previousOwnerNick: m['previousOwnerNick'] as String?,
    fromColorValue:    m['fromColorValue'] as int? ?? 0xFFCC2222,
  );
}

// ── Servicio ──────────────────────────────────────────────────────────────────
class ActivityService {
  static final _db = FirebaseFirestore.instance;

  static const _kFeedDataKey = 'act_feed_data';
  static const _kFeedTsKey   = 'act_feed_ts';
  static const _kTtlMs       = 5 * 60 * 1000; // 5 minutos

  // Invalidar caché manualmente (botón refresh)
  static Future<void> invalidarCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFeedTsKey);
  }

  // Feed global reciente — sirve desde caché 5 min antes de ir a Firestore
  static Future<List<ActivityEntry>> obtenerFeedReciente(
      {int limit = 15}) async {
    final prefs = await SharedPreferences.getInstance();
    final ts    = prefs.getInt(_kFeedTsKey) ?? 0;
    final now   = DateTime.now().millisecondsSinceEpoch;

    if (now - ts < _kTtlMs) {
      final raw = prefs.getString(_kFeedDataKey);
      if (raw != null) {
        try {
          final list = jsonDecode(raw) as List;
          return list
              .map((e) => ActivityEntry._fromMap(e as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }
    }

    try {
      final snap = await _db
          .collection('activity_feed')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();
      final entries = snap.docs.map(ActivityEntry.fromDoc).toList();

      await prefs.setInt(_kFeedTsKey, now);
      await prefs.setString(
          _kFeedDataKey, jsonEncode(entries.map((e) => e._toMap()).toList()));

      return entries;
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
